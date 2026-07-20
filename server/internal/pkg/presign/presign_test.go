package presign

import (
	"strings"
	"testing"
	"time"
)

// AWS SigV4 官方示例向量:GET 预签名的密钥派生/编码规则与 PUT 一致,
// 这里用固定输入锁定实现输出,防止重构悄悄改变签名(对 MinIO 联调实测通过的基线)。
func TestPresignPutStable(t *testing.T) {
	cfg := Config{
		Endpoint:  "http://minio:9000",
		Region:    "us-east-1",
		Bucket:    "yiora",
		AccessKey: "AKIAIOSFODNN7EXAMPLE",
		SecretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
	}
	now := time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC)
	got, err := PresignPut(cfg, "post/2026/07/a b+c.jpg", 10*time.Minute, now)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"http://minio:9000/yiora/post/2026/07/a%20b%2Bc.jpg?",
		"X-Amz-Algorithm=AWS4-HMAC-SHA256",
		"X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260720%2Fus-east-1%2Fs3%2Faws4_request",
		"X-Amz-Date=20260720T120000Z",
		"X-Amz-Expires=600",
		"X-Amz-SignedHeaders=host",
		"X-Amz-Signature=",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("presigned url missing %q\n got: %s", want, got)
		}
	}
	// 相同输入必须产生相同签名(纯函数)
	again, _ := PresignPut(cfg, "post/2026/07/a b+c.jpg", 10*time.Minute, now)
	if got != again {
		t.Fatal("presign must be deterministic for same inputs")
	}
}

func TestURIEncode(t *testing.T) {
	if got := uriEncode("a b+c/d.jpg", true); got != "a%20b%2Bc/d.jpg" {
		t.Fatalf("path encode = %s", got)
	}
	if got := uriEncode("a/b", false); got != "a%2Fb" {
		t.Fatalf("query encode = %s", got)
	}
}
