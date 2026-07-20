// Package presign S3 兼容对象存储的 AWS Signature V4 预签名 PUT(直传用,无 SDK 依赖)。
// 适配 MinIO / 阿里云 OSS S3 端点 / AWS S3(path-style)。
package presign

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/url"
	"sort"
	"strings"
	"time"
)

// Config 存储端配置。
type Config struct {
	Endpoint  string // 如 http://minio:9000 或 https://s3.cn-north-1.amazonaws.com.cn
	Region    string // MinIO 任意值均可,常用 us-east-1
	Bucket    string
	AccessKey string
	SecretKey string
}

// PresignPut 生成预签名 PUT URL,expire 内有效。objectKey 形如 "post/2026/07/xxx.jpg"。
func PresignPut(cfg Config, objectKey string, expire time.Duration, now time.Time) (string, error) {
	u, err := url.Parse(cfg.Endpoint)
	if err != nil {
		return "", fmt.Errorf("parse endpoint: %w", err)
	}
	host := u.Host
	canonicalURI := "/" + cfg.Bucket + "/" + uriEncode(objectKey, true)

	amzDate := now.UTC().Format("20060102T150405Z")
	dateStamp := now.UTC().Format("20060102")
	scope := dateStamp + "/" + cfg.Region + "/s3/aws4_request"

	q := url.Values{}
	q.Set("X-Amz-Algorithm", "AWS4-HMAC-SHA256")
	q.Set("X-Amz-Credential", cfg.AccessKey+"/"+scope)
	q.Set("X-Amz-Date", amzDate)
	q.Set("X-Amz-Expires", fmt.Sprintf("%d", int(expire.Seconds())))
	q.Set("X-Amz-SignedHeaders", "host")

	canonicalQuery := canonicalQueryString(q)
	canonicalRequest := strings.Join([]string{
		"PUT",
		canonicalURI,
		canonicalQuery,
		"host:" + host + "\n",
		"host",
		"UNSIGNED-PAYLOAD",
	}, "\n")

	stringToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		amzDate,
		scope,
		hexSHA256([]byte(canonicalRequest)),
	}, "\n")

	signingKey := hmacSHA256(hmacSHA256(hmacSHA256(hmacSHA256(
		[]byte("AWS4"+cfg.SecretKey), []byte(dateStamp)), []byte(cfg.Region)), []byte("s3")), []byte("aws4_request"))
	signature := hex.EncodeToString(hmacSHA256(signingKey, []byte(stringToSign)))

	return u.Scheme + "://" + host + canonicalURI + "?" + canonicalQuery + "&X-Amz-Signature=" + signature, nil
}

// canonicalQueryString 按 key 排序并做 AWS 风格编码。
func canonicalQueryString(q url.Values) string {
	keys := make([]string, 0, len(q))
	for k := range q {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, uriEncode(k, false)+"="+uriEncode(q.Get(k), false))
	}
	return strings.Join(parts, "&")
}

// uriEncode AWS SigV4 规范编码:非保留字符透传,其余 %XX(大写);path 模式保留 '/'。
func uriEncode(s string, isPath bool) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		switch {
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9',
			c == '-', c == '_', c == '.', c == '~':
			b.WriteByte(c)
		case c == '/' && isPath:
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

func hexSHA256(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func hmacSHA256(key, data []byte) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(data)
	return h.Sum(nil)
}
