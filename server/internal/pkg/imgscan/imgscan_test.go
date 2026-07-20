package imgscan

import (
	"context"
	"testing"
)

func TestNewProvider(t *testing.T) {
	if s, err := New(""); err != nil || s != nil {
		t.Fatalf("empty provider should be nil scanner, got %v %v", s, err)
	}
	if s, err := New("mock"); err != nil || s == nil || s.Name() != "mock" {
		t.Fatalf("mock provider: got %v %v", s, err)
	}
	if _, err := New("unknown-vendor"); err == nil {
		t.Fatal("unknown provider should error out")
	}
}

func TestMockVerdicts(t *testing.T) {
	s, _ := New("mock")
	cases := []struct {
		url  string
		want Verdict
	}{
		{"http://localhost:9000/yiora/post/1/abc.png", VerdictPass},
		{"http://localhost:9000/yiora/post/1/mock-review.png", VerdictReview},
		{"http://localhost:9000/yiora/post/1/MOCK-BLOCK.png", VerdictBlock},
	}
	for _, c := range cases {
		r, err := s.Scan(context.Background(), c.url)
		if err != nil || r.Verdict != c.want {
			t.Fatalf("%s: got %v %v want %v", c.url, r, err, c.want)
		}
	}
}
