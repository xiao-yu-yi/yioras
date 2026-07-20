# 二期调研:Meilisearch 搜索升级方案

> 2026-07 调研。现状:全站搜索(帖/用户/圈子/软件/话题五域)由 `searchmodel` 以 MySQL LIKE 实现,
> `search.Searcher` 接口已预留替换点(svc 注入,logic 层零感知)。

## 一、现状痛点

- **中文无分词**:LIKE '%绿色软件%' 只能连续子串命中,"绿色免费软件"搜"绿色软件"失败;
- **无相关性排序**:只能按 hot_score/download_count 等静态热度排,与查询词的匹配度无关;
- **无错字容忍/前缀联想**:"绿包软件"零结果;搜索框实时联想做不了;
- **性能天花板**:`LIKE '%kw%'` 无法走索引,帖子表到十万级后全表扫描明显变慢。

## 二、方案对比

| 维度 | Meilisearch(推荐) | Elasticsearch | MySQL FULLTEXT(ngram) |
| --- | --- | --- | --- |
| 中文分词 | 内置 charabia+jieba 专用管道,零配置 | 需装 IK 插件 | ngram 二元切分,噪声大 |
| 错字容忍/前缀 | 原生 typo-tolerance+前缀即时搜 | 需调 fuzziness | 无 |
| 部署 | Rust 单二进制/官方镜像,数百 MB 内存起步 | JVM,2GB+ 内存,集群运维面大 | 零新增组件 |
| Go SDK | 官方 meilisearch-go | 官方 | - |
| 排序定制 | rankingRules 可插 hot_score 静态分 | 灵活 | 差 |
| 适用规模 | 单机千万文档内舒适 | 亿级/复杂聚合 | 过渡用 |

**结论:Meilisearch**。社区单机规模最优解,中文管道开箱即用(jieba 精确切分,长词二次切分已在
charabia 上游演进);ES 对当前体量过重;FULLTEXT 效果提升有限不值得动 schema。
索引期内存偏高是已知特性,用 `--max-indexing-memory` 限住即可。

## 三、接入设计(贴合 search.Searcher 预留点)

```
写路径(增量同步):reconcile 式 daemon 每 1~5 分钟按 updated_at/id 水位拉变更 → upsert/删除文档
   (不侵入业务写点,失败自动补追;冷启动全量重建一次)
读路径:internal/pkg/search 新增 meili 实现 → 查询返回 ID 列表 → 回 MySQL 取整行
   (返回 model.* 结构不变,五域 decorate 逻辑零改动;meili 故障时降级回 MySQL LIKE 实现)
```

1. **索引规划**:五个索引 posts/users/circles/software/topics;
   searchableAttributes 对齐现 LIKE 字段(如 posts=title+content);
   filterableAttributes 承担现 WHERE(status/visibility);
   rankingRules 在默认相关性后追加 `hot_score:desc` 等静态热度分。
2. **配置**:`Search{Provider: mysql|meili, Host, APIKey}`,默认 mysql(本地/CI 不依赖新组件,与 imgscan 同一策略);
   compose 加 `getmeili/meilisearch:v1` 服务 + `MEILI_MASTER_KEY` + 数据卷。
3. **一致性容忍**:社区搜索允许分钟级延迟,增量水位即可;删除/下架靠同步器按状态字段推 delete。
4. **依赖**:官方 `meilisearch-go` SDK。

## 四、落地里程碑

- M1(1~1.5 天):meili Searcher 驱动 + 同步 daemon(水位增量+启动全量)+ compose 服务
  + 冒烟(中文分词命中率 case:分词/错字/前缀,对照 LIKE 结果)
- M2(0.5 天):搜索联想接口(前缀即时搜)+ 关键词高亮字段透传
- 上线开关:Provider 切 meili 前先跑一周双写观察索引一致性,可随时切回 mysql
