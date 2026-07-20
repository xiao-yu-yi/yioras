# 二期调研:APK 大文件分片上传/断点续传方案

> 2026-07 调研。现状:APK 走单次预签名 PUT 直传,上限 500MB——弱网/大包(主流手游 1GB+)
> 一旦中断只能整包重传,且单请求超时风险高,是软件发布链路的体验短板。

## 一、候选方案

| 方案 | 原理 | 评估 |
| --- | --- | --- |
| **A. S3 Multipart + 预签名分片(推荐)** | S3 标准三段式:Init 取 uploadId → 各分片独立预签名 PUT → Complete 合并;ListParts 查已传分片实现续传 | 协议标准,MinIO/阿里 OSS/腾讯 COS 全兼容(迁移云存储零改动);分片独立重试,天然断点续传;无新增部署组件 |
| B. tus 协议(tusd 服务) | 开源断点续传协议,独立 tusd 服务器落盘再搬运 | 多一个常驻组件与运维面;文件先经 tusd 再进对象存储,链路变长;生态偏 Web,弃 |
| C. 单 PUT + Range 续传 | 中断后 Range 续写 | S3 PUT 不支持 Range 追加,协议上不可行,弃 |

## 二、方案 A 技术要点(已验证)

- 分片限制:每片 5MiB~5GiB、最多 1 万片;**取 8MB/片**(500MB→63 片,2GB→256 片,片数与单片超时都舒适)。
- 预签名分片 URL = 普通 PUT 预签名 + query 携带 `uploadId` 与 `partNumber`(1~10000);
  我们自研的 SigV4 签名器(`internal/pkg/presign`)已支持任意 query 参与签名,可直接扩展。
- Init/Complete/Abort/ListParts 是服务端对 S3 的 XML API 调用:**引入 minio-go 的 `minio.Core`**
  (NewMultipartUpload/CompleteMultipartUpload/AbortMultipartUpload/ListParts 现成,生产验证充分),
  比裸写 XML+SigV4 省一半工作量;Complete 时分片必须按 partNumber 升序(InvalidPartOrder 坑)。
- 合并后 ETag 非文件 MD5,完整性校验用客户端逐片 MD5(可选 Content-MD5 头签进预签名)。

## 三、接口设计(骨架)

```
POST /api/v1/upload/multipart/init      {kind:"apk", fileName, size}
  → {uploadId, key, partSize, urls:[{partNumber, url}...]}   // 一次签发全部分片 URL(10 分钟过期)
POST /api/v1/upload/multipart/complete  {uploadId, key, parts:[{partNumber, etag}...]}
  → {fileUrl}                            // 服务端 Complete 合并,返回最终地址(过白名单校验体系)
POST /api/v1/upload/multipart/abort     {uploadId, key}       // 用户取消,清分片碎片
GET  /api/v1/upload/multipart/parts?uploadId=&key=            // 断点续传:App 重启后查已传分片,只补缺口
```

- 权限与配额沿用现有 presign 规则表(kind=apk 限发布者,size 上限放宽至 2GB);
- uploadId 归属校验:init 时 `mp:{uploadId} → uid` 存 Redis(24h),complete/abort/parts 校验归属;
- 兜底:MinIO 桶生命周期规则清 7 天未完成的 multipart 碎片(`mc ilm` 一条命令)。

## 四、客户端(Flutter)流程

1. init 拿全量分片 URL → 并发 3~4 路 PUT(dio),逐片记录 etag 与完成位图(本地持久化);
2. 中断恢复:重启后调 parts 接口比对,只补未完成分片(URL 过期则重新 init 同 key 补签);
3. 全部完成 → complete → 拿 fileUrl 填入软件发布表单;暂停=取消在途请求,位图留存。

## 五、落地里程碑

- M1 后端(1~1.5 天):minio-go Core 接入 + 四接口 + 归属校验 + 冒烟(PS 脚本 3 片传 24MB 文件,
  验证合并一致性与"杀进程后 ListParts 续传")
- M2 客户端(Flutter 侧排期):分片上传器组件(并发/暂停恢复/进度回调)
- 顺带收益:帖子视频(二期)复用同一套分片通道
