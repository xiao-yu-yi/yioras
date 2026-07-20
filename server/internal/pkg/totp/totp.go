// Package totp RFC 6238 时间动态口令(SHA1/30s/6 位,兼容 Google Authenticator 等主流验证器)。
package totp

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

const (
	Period = 30 // 时间步长(秒)
	Digits = 6
)

var b32 = base32.StdEncoding.WithPadding(base32.NoPadding)

// NewSecret 生成 160 位随机密钥(base32,无填充)。
func NewSecret() (string, error) {
	buf := make([]byte, 20)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("totp secret: %w", err)
	}
	return b32.EncodeToString(buf), nil
}

// URI 生成 otpauth:// 供验证器 App 扫码/导入。
func URI(secret, account, issuer string) string {
	return fmt.Sprintf("otpauth://totp/%s:%s?secret=%s&issuer=%s&period=%d&digits=%d",
		url.PathEscape(issuer), url.PathEscape(account), secret, url.QueryEscape(issuer), Period, Digits)
}

// Code 计算指定时间步的口令。
func Code(secret string, timestep int64) (string, error) {
	key, err := b32.DecodeString(strings.ToUpper(strings.TrimSpace(secret)))
	if err != nil {
		return "", fmt.Errorf("decode secret: %w", err)
	}
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], uint64(timestep))
	mac := hmac.New(sha1.New, key)
	mac.Write(msg[:])
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	bin := binary.BigEndian.Uint32(sum[offset:offset+4]) & 0x7fffffff
	return fmt.Sprintf("%06d", bin%1000000), nil
}

// Timestep 当前时间步(校验防重放时用作一次性标记键)。
func Timestep(now time.Time) int64 { return now.Unix() / Period }

// Verify 校验口令,容忍前后各一个时间步(±30s 时钟偏移)。
// 返回命中的时间步,便于调用方做同码防重放。
func Verify(secret, code string, now time.Time) (int64, bool) {
	code = strings.TrimSpace(code)
	if len(code) != Digits {
		return 0, false
	}
	ts := Timestep(now)
	for _, step := range []int64{ts, ts - 1, ts + 1} {
		want, err := Code(secret, step)
		if err != nil {
			return 0, false
		}
		if hmac.Equal([]byte(want), []byte(code)) {
			return step, true
		}
	}
	return 0, false
}
