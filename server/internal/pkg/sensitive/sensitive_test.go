package sensitive

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/yiora/server/internal/model"
)

type fakeSource struct {
	words []model.SensitiveWord
	err   error
	calls int
}

func (f *fakeSource) ListEnabled(context.Context) ([]model.SensitiveWord, error) {
	f.calls++
	if f.err != nil {
		return nil, f.err
	}
	return f.words, nil
}

func words() []model.SensitiveWord {
	return []model.SensitiveWord{
		{Word: "打码词", Level: model.WordLevelMask},
		{Word: "BlockWord", Level: model.WordLevelBlock},
		{Word: "人审词", Level: model.WordLevelReview},
	}
}

func TestCheckLevels(t *testing.T) {
	tests := []struct {
		name      string
		text      string
		wantLevel int
		wantHit   string
		wantText  string
	}{
		{"干净文本", "今天天气不错", 0, "", "今天天气不错"},
		{"拦截级命中", "内容含blockword触发", model.WordLevelBlock, "BlockWord", "内容含blockword触发"},
		{"人审级命中", "内容含人审词", model.WordLevelReview, "人审词", "内容含人审词"},
		{"打码级命中并替换", "前缀打码词后缀", model.WordLevelMask, "打码词", "前缀***后缀"},
		{"打码多次命中全部替换", "打码词A打码词", model.WordLevelMask, "打码词", "***A***"},
		{"拦截优先于打码", "打码词与BLOCKWORD同现", model.WordLevelBlock, "BlockWord", "打码词与BLOCKWORD同现"},
		{"人审优先于打码", "打码词与人审词同现", model.WordLevelReview, "人审词", "前缀无关"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := NewFilter(&fakeSource{words: words()})
			res, err := f.Check(context.Background(), tt.text)
			if err != nil {
				t.Fatalf("Check: %v", err)
			}
			if res.Level != tt.wantLevel {
				t.Fatalf("level = %d, want %d", res.Level, tt.wantLevel)
			}
			if res.Hit != tt.wantHit {
				t.Fatalf("hit = %q, want %q", res.Hit, tt.wantHit)
			}
			// 人审级命中时文本仍会做打码替换,只校验打码场景的文本
			if tt.wantLevel == model.WordLevelMask && res.Text != tt.wantText {
				t.Fatalf("text = %q, want %q", res.Text, tt.wantText)
			}
			if tt.wantLevel == model.WordLevelBlock && res.Text != tt.text {
				t.Fatalf("block text = %q, want original %q", res.Text, tt.text)
			}
		})
	}
}

func TestCheckAllSeverity(t *testing.T) {
	f := NewFilter(&fakeSource{words: words()})
	texts, level, hit, err := f.CheckAll(context.Background(), "标题打码词", "正文含人审词")
	if err != nil {
		t.Fatalf("CheckAll: %v", err)
	}
	// 人审(2)比打码(3)处置更重
	if level != model.WordLevelReview || hit != "人审词" {
		t.Fatalf("level=%d hit=%q, want review/人审词", level, hit)
	}
	if texts[0] != "标题***" {
		t.Fatalf("masked title = %q", texts[0])
	}
}

func TestLoadCacheAndDegrade(t *testing.T) {
	src := &fakeSource{words: words()}
	f := NewFilter(src)
	ctx := context.Background()

	if _, err := f.Check(ctx, "a"); err != nil {
		t.Fatalf("first check: %v", err)
	}
	if _, err := f.Check(ctx, "b"); err != nil {
		t.Fatalf("second check: %v", err)
	}
	if src.calls != 1 {
		t.Fatalf("TTL 内应命中缓存,实际加载 %d 次", src.calls)
	}

	// 缓存过期后词库加载失败 → 降级用旧词库,不阻塞发布链路
	f.expireAt = time.Time{}
	src.err = errors.New("db down")
	res, err := f.Check(ctx, "内容含人审词")
	if err != nil {
		t.Fatalf("degraded check: %v", err)
	}
	if res.Level != model.WordLevelReview {
		t.Fatalf("degraded level = %d, want review", res.Level)
	}

	// 从未加载成功过则报错
	f2 := NewFilter(&fakeSource{err: errors.New("db down")})
	if _, err := f2.Check(ctx, "x"); err == nil {
		t.Fatal("首次加载失败应返回错误")
	}
}
