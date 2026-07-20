// Package captcha 后台登录图形验证码:无第三方依赖的自绘 SVG 方案。
// 码值存 Redis 一次性消费(校验即删),5 分钟过期;内部后台场景强度足够。
package captcha

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"math/big"
	"strings"

	"github.com/zeromicro/go-zero/core/stores/redis"
)

// 字符集去掉 0O/1I/L 等易混淆字符
const charset = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

const (
	codeLen = 5
	ttlSec  = 300
)

func key(id string) string { return "admin:captcha:" + id }

// New 生成验证码:返回 id 与 data URI 形式的 SVG 图。
func New(ctx context.Context, rds *redis.Redis) (id, imageURI string, err error) {
	id = randString(16)
	code := randString(codeLen)
	if err := rds.SetexCtx(ctx, key(id), code, ttlSec); err != nil {
		return "", "", fmt.Errorf("store captcha: %w", err)
	}
	svg := renderSVG(code)
	return id, "data:image/svg+xml;base64," + base64.StdEncoding.EncodeToString([]byte(svg)), nil
}

// Verify 校验并销毁(一次性,防重放)。大小写不敏感。
func Verify(ctx context.Context, rds *redis.Redis, id, code string) bool {
	if id == "" || code == "" {
		return false
	}
	want, err := rds.GetCtx(ctx, key(id))
	if err != nil || want == "" {
		return false
	}
	_, _ = rds.DelCtx(ctx, key(id))
	return strings.EqualFold(want, strings.TrimSpace(code))
}

func randString(n int) string {
	b := make([]byte, n)
	for i := range b {
		idx, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		b[i] = charset[idx.Int64()]
	}
	return string(b)
}

func randInt(n int) int {
	v, _ := rand.Int(rand.Reader, big.NewInt(int64(n)))
	return int(v.Int64())
}

// renderSVG 自绘验证码图:字符随机旋转/偏移 + 干扰线。
func renderSVG(code string) string {
	const w, h = 150, 50
	colors := []string{"#3b5b92", "#7a3b92", "#92553b", "#2e7d54", "#8a2e4d"}
	var sb strings.Builder
	fmt.Fprintf(&sb, `<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><rect width="100%%" height="100%%" fill="#f4f6fa"/>`, w, h, w, h)
	for i := 0; i < 3; i++ {
		fmt.Fprintf(&sb, `<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1" opacity="0.5"/>`,
			randInt(w/2), randInt(h), w/2+randInt(w/2), randInt(h), colors[randInt(len(colors))])
	}
	for i, ch := range code {
		x := 18 + i*26 + randInt(6) - 3
		y := 32 + randInt(10) - 5
		rot := randInt(50) - 25
		fmt.Fprintf(&sb,
			`<text x="%d" y="%d" font-family="Verdana,Arial,sans-serif" font-size="28" font-weight="bold" fill="%s" transform="rotate(%d %d %d)">%c</text>`,
			x, y, colors[randInt(len(colors))], rot, x, y, ch)
	}
	sb.WriteString("</svg>")
	return sb.String()
}
