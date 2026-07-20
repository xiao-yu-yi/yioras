// Package uploadlogic 对象存储预签名直传:服务端只发签名不经手文件字节,
// 客户端拿 uploadUrl PUT 原文,再把 fileUrl 回填业务接口(头像/图片/APK)。
package uploadlogic

import (
	"context"
	"fmt"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/yiora/server/internal/config"
	"github.com/yiora/server/internal/pkg/multipart"
	"github.com/yiora/server/internal/pkg/presign"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

const (
	presignTTL = 10 * time.Minute

	// 分片上传:8MB/片(5MiB 下限之上,2GB→256 片),任务与归属票据保留 24h
	multipartPartSize = 8 << 20
	multipartMaxSize  = 2 << 30
	multipartTTL      = 24 * time.Hour
)

// kindRule 用途 → 尺寸与扩展名白名单。
type kindRule struct {
	maxSize int64
	exts    map[string]bool
}

var imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true}

var rules = map[string]kindRule{
	"avatar":   {maxSize: 5 << 20, exts: imageExts},
	"cover":    {maxSize: 10 << 20, exts: imageExts},
	"post":     {maxSize: 10 << 20, exts: imageExts},
	"software": {maxSize: 10 << 20, exts: imageExts},
	"banner":   {maxSize: 10 << 20, exts: imageExts}, // 后台运营位
	"deco":     {maxSize: 10 << 20, exts: imageExts}, // 后台装扮预览
	"circle":   {maxSize: 10 << 20, exts: imageExts}, // 后台圈子图标/封面
	"apk":      {maxSize: 500 << 20, exts: map[string]bool{".apk": true}},
}

// AllowedImageURL 图片 URL 域名白名单:配置了对象存储时,业务图片必须来自我方存储前缀
// (PublicBaseURL/Bucket,兜底 Endpoint/Bucket),防外链盗刷与钓鱼图注入;
// 未配置对象存储的部署退化为 http(s) 前缀检查(向后兼容)。
func AllowedImageURL(cfg config.Config, u string) bool {
	if len(u) > 255 || (!strings.HasPrefix(u, "https://") && !strings.HasPrefix(u, "http://")) {
		return false
	}
	st := cfg.Storage
	if st.Endpoint == "" || st.Bucket == "" {
		return true
	}
	for _, base := range []string{st.PublicBaseURL, st.Endpoint} {
		if base == "" {
			continue
		}
		if strings.HasPrefix(u, strings.TrimRight(base, "/")+"/"+st.Bucket+"/") {
			return true
		}
	}
	return false
}

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Presign 校验用途规则后签发 10 分钟 PUT 直传 URL。
func (l *Logic) Presign(ctx context.Context, uid int64, req *types.PresignReq) (*types.PresignResp, error) {
	st := l.svcCtx.Config.Storage
	if st.Endpoint == "" || st.Bucket == "" {
		return nil, xerr.New(xerr.CodeServer, "对象存储未配置,上传功能暂不可用")
	}
	rule, ok := rules[req.Kind]
	if !ok {
		return nil, xerr.Param("不支持的上传用途")
	}
	ext := strings.ToLower(path.Ext(req.FileName))
	if !rule.exts[ext] {
		return nil, xerr.Param("文件类型不支持: " + ext)
	}
	if req.Size <= 0 || req.Size > rule.maxSize {
		return nil, xerr.Param(fmt.Sprintf("文件大小需在 1B - %dMB 之间", rule.maxSize>>20))
	}

	now := time.Now()
	// key 含 uid 与纳秒时间戳:不可预测且天然不冲突,客户端传的文件名只取扩展名
	objectKey := fmt.Sprintf("%s/%s/%d_%d%s", req.Kind, now.Format("2006/01"), uid, now.UnixNano(), ext)

	base := st.PublicBaseURL
	if base == "" {
		base = st.Endpoint
	}
	uploadURL, err := presign.PresignPut(presign.Config{
		Endpoint: base, Region: st.Region, Bucket: st.Bucket,
		AccessKey: st.AccessKey, SecretKey: st.SecretKey,
	}, objectKey, presignTTL, now)
	if err != nil {
		return nil, fmt.Errorf("presign put: %w", err)
	}
	return &types.PresignResp{
		UploadURL: uploadURL,
		FileURL:   strings.TrimRight(base, "/") + "/" + st.Bucket + "/" + objectKey,
		ExpireAt:  now.Add(presignTTL).UnixMilli(),
	}, nil
}

// ---- 大文件分片上传(S3 Multipart,APK 500MB~2GB 与弱网断点续传) ----

func (l *Logic) mpClient() (*multipart.Client, error) {
	if l.svcCtx.Multipart == nil {
		return nil, xerr.New(xerr.CodeServer, "对象存储未配置,上传功能暂不可用")
	}
	return l.svcCtx.Multipart, nil
}

func mpTicketKey(uploadID string) string { return "mp:" + uploadID }

// checkTicket 校验分片任务归属(uploadID 必须由本人 init 且 key 匹配),返回总分片数。
func (l *Logic) checkTicket(ctx context.Context, uid int64, uploadID, key string) (int, error) {
	raw, err := l.svcCtx.Redis.GetCtx(ctx, mpTicketKey(uploadID))
	if err != nil || raw == "" {
		return 0, xerr.New(xerr.CodeNotFound, "分片任务不存在或已过期")
	}
	parts := strings.SplitN(raw, "|", 3)
	if len(parts) != 3 || parts[0] != strconv.FormatInt(uid, 10) || parts[1] != key {
		return 0, xerr.New(xerr.CodeForbidden, "无权操作该分片任务")
	}
	n, _ := strconv.Atoi(parts[2])
	return n, nil
}

// MultipartInit 创建分片任务:校验规则 → 生成 key → 签发全量分片 URL → 归属票据入 Redis。
func (l *Logic) MultipartInit(ctx context.Context, uid int64, req *types.MultipartInitReq) (*types.MultipartInitResp, error) {
	mp, err := l.mpClient()
	if err != nil {
		return nil, err
	}
	ext := strings.ToLower(path.Ext(req.FileName))
	if ext != ".apk" {
		return nil, xerr.Param("文件类型不支持: " + ext)
	}
	if req.Size <= 0 || req.Size > multipartMaxSize {
		return nil, xerr.Param(fmt.Sprintf("文件大小需在 1B - %dGB 之间", multipartMaxSize>>30))
	}
	partCount := int((req.Size + multipartPartSize - 1) / multipartPartSize)

	now := time.Now()
	objectKey := fmt.Sprintf("%s/%s/%d_%d%s", req.Kind, now.Format("2006/01"), uid, now.UnixNano(), ext)
	uploadID, urls, err := mp.Init(ctx, objectKey, partCount, presignTTL)
	if err != nil {
		return nil, err
	}
	ticket := fmt.Sprintf("%d|%s|%d", uid, objectKey, partCount)
	if err := l.svcCtx.Redis.SetexCtx(ctx, mpTicketKey(uploadID), ticket, int(multipartTTL.Seconds())); err != nil {
		return nil, fmt.Errorf("store multipart ticket: %w", err)
	}
	out := make([]types.MultipartPartURL, 0, len(urls))
	for _, u := range urls {
		out = append(out, types.MultipartPartURL{PartNumber: u.PartNumber, URL: u.URL})
	}
	return &types.MultipartInitResp{
		UploadID: uploadID, Key: objectKey, PartSize: multipartPartSize,
		URLs: out, ExpireAt: now.Add(presignTTL).UnixMilli(),
	}, nil
}

// MultipartComplete 合并分片并返回最终 fileUrl(过既有域名白名单体系)。
func (l *Logic) MultipartComplete(ctx context.Context, uid int64, req *types.MultipartCompleteReq) (*types.MultipartCompleteResp, error) {
	mp, err := l.mpClient()
	if err != nil {
		return nil, err
	}
	if _, err := l.checkTicket(ctx, uid, req.UploadID, req.Key); err != nil {
		return nil, err
	}
	if len(req.Parts) == 0 {
		return nil, xerr.Param("分片列表为空")
	}
	parts := make([]multipart.Part, 0, len(req.Parts))
	for _, p := range req.Parts {
		parts = append(parts, multipart.Part{PartNumber: p.PartNumber, ETag: p.ETag})
	}
	if err := mp.Complete(ctx, req.Key, req.UploadID, parts); err != nil {
		return nil, xerr.Param("分片合并失败,请核对各分片 etag 后重试")
	}
	_, _ = l.svcCtx.Redis.DelCtx(ctx, mpTicketKey(req.UploadID))
	st := l.svcCtx.Config.Storage
	base := st.PublicBaseURL
	if base == "" {
		base = st.Endpoint
	}
	return &types.MultipartCompleteResp{
		FileURL: strings.TrimRight(base, "/") + "/" + st.Bucket + "/" + req.Key,
	}, nil
}

// MultipartAbort 用户取消:清云端分片碎片与票据。
func (l *Logic) MultipartAbort(ctx context.Context, uid int64, req *types.MultipartAbortReq) error {
	mp, err := l.mpClient()
	if err != nil {
		return err
	}
	if _, err := l.checkTicket(ctx, uid, req.UploadID, req.Key); err != nil {
		return err
	}
	if err := mp.Abort(ctx, req.Key, req.UploadID); err != nil {
		return err
	}
	_, _ = l.svcCtx.Redis.DelCtx(ctx, mpTicketKey(req.UploadID))
	return nil
}

// MultipartParts 断点续传:返回已完成分片,并为缺口分片补签新 URL。
func (l *Logic) MultipartParts(ctx context.Context, uid int64, req *types.MultipartPartsReq) (*types.MultipartPartsResp, error) {
	mp, err := l.mpClient()
	if err != nil {
		return nil, err
	}
	partCount, err := l.checkTicket(ctx, uid, req.UploadID, req.Key)
	if err != nil {
		return nil, err
	}
	done, err := mp.ListParts(ctx, req.Key, req.UploadID)
	if err != nil {
		return nil, err
	}
	doneSet := make(map[int]bool, len(done))
	outDone := make([]types.MultipartPartETag, 0, len(done))
	for _, p := range done {
		doneSet[p.PartNumber] = true
		outDone = append(outDone, types.MultipartPartETag{PartNumber: p.PartNumber, ETag: p.ETag})
	}
	var missing []types.MultipartPartURL
	for n := 1; n <= partCount; n++ {
		if doneSet[n] {
			continue
		}
		urls, err := mp.PresignParts(ctx, req.Key, req.UploadID, n, n, presignTTL)
		if err != nil {
			return nil, err
		}
		missing = append(missing, types.MultipartPartURL{PartNumber: urls[0].PartNumber, URL: urls[0].URL})
	}
	return &types.MultipartPartsResp{Parts: outDone, URLs: missing}, nil
}
