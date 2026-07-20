// Package uploadlogic 对象存储预签名直传:服务端只发签名不经手文件字节,
// 客户端拿 uploadUrl PUT 原文,再把 fileUrl 回填业务接口(头像/图片/APK)。
package uploadlogic

import (
	"context"
	"fmt"
	"path"
	"strings"
	"time"

	"github.com/yiora/server/internal/config"
	"github.com/yiora/server/internal/pkg/presign"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

const presignTTL = 10 * time.Minute

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
