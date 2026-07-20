package jwtx

import "testing"

func TestTokenRoundTrip(t *testing.T) {
	token, expireAt, err := GenToken("test-secret", 42, 3600)
	if err != nil {
		t.Fatalf("gen: %v", err)
	}
	if expireAt == 0 || token == "" {
		t.Fatal("empty token or expire")
	}
	uid, err := ParseUID("test-secret", token)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if uid != 42 {
		t.Fatalf("uid = %d, want 42", uid)
	}
	if _, err := ParseUID("wrong-secret", token); err == nil {
		t.Fatal("wrong secret should fail")
	}
}
