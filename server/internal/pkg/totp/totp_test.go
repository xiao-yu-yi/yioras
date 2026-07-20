package totp

import (
	"encoding/base32"
	"testing"
	"time"
)

// RFC 6238 附录 B 测试向量(SHA1,密钥 "12345678901234567890",8 位截 6 位对照)。
// RFC 给的是 8 位码,这里取其后 6 位即等价于 6 位实现的输出。
func TestRFC6238Vectors(t *testing.T) {
	secret := base32.StdEncoding.WithPadding(base32.NoPadding).
		EncodeToString([]byte("12345678901234567890"))
	cases := []struct {
		unix int64
		want string // RFC 8 位码的后 6 位
	}{
		{59, "287082"},
		{1111111109, "081804"},
		{1111111111, "050471"},
		{1234567890, "005924"},
		{2000000000, "279037"},
	}
	for _, c := range cases {
		got, err := Code(secret, c.unix/Period)
		if err != nil {
			t.Fatalf("Code(%d): %v", c.unix, err)
		}
		if got != c.want {
			t.Fatalf("Code at unix %d = %s, want %s", c.unix, got, c.want)
		}
	}
}

func TestVerifyWindow(t *testing.T) {
	secret, err := NewSecret()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1700000000, 0)

	cur, _ := Code(secret, Timestep(now))
	if _, ok := Verify(secret, cur, now); !ok {
		t.Fatal("current step code must verify")
	}
	prev, _ := Code(secret, Timestep(now)-1)
	if _, ok := Verify(secret, prev, now); !ok {
		t.Fatal("previous step code must verify (clock skew)")
	}
	old, _ := Code(secret, Timestep(now)-2)
	if _, ok := Verify(secret, old, now); ok {
		t.Fatal("two steps old code must fail")
	}
	if _, ok := Verify(secret, "000000", now); ok {
		t.Fatal("random code should fail")
	}
	if _, ok := Verify(secret, "12345", now); ok {
		t.Fatal("short code should fail")
	}
}
