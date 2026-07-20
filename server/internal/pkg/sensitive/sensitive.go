// Package sensitive 文本敏感词过滤(M2 机审的本地实现;云内容安全接入后作为前置粗筛保留)。
package sensitive

import (
	"context"
	"strings"
	"sync"
	"time"

	"github.com/yiora/server/internal/model"
)

const cacheTTL = 5 * time.Minute

// Result 检查结果。Level 取所有命中词的最高处置等级(Block > Review > Mask > 0)。
type Result struct {
	Level int    // 0=干净 1=拦截 2=转人审 3=已打码
	Hit   string // 首个最高等级命中词(入审核明细)
	Text  string // Mask 级命中已替换为*的文本
}

// WordSource 词库来源,生产为 *model.SensitiveModel,测试可注入假实现。
type WordSource interface {
	ListEnabled(ctx context.Context) ([]model.SensitiveWord, error)
}

type Filter struct {
	m        WordSource
	mu       sync.Mutex
	words    []model.SensitiveWord // 已按 level 降序,保证先匹配处置最重的词
	expireAt time.Time
}

func NewFilter(m WordSource) *Filter { return &Filter{m: m} }

// Invalidate 使词库缓存立即失效(管理端增删改后调用,下次 Check 重载,实现热更新)。
func (f *Filter) Invalidate() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.expireAt = time.Time{}
}

// Check 惰性加载词库(TTL 5min),对 text 做大小写不敏感子串匹配。
// ponytail: O(词数*文本长)朴素匹配,词库过万或帖子体量大时换 Aho-Corasick。
func (f *Filter) Check(ctx context.Context, text string) (Result, error) {
	words, err := f.load(ctx)
	if err != nil {
		return Result{}, err
	}
	// words 已按 level 升序:先 Block,再 Review,后 Mask
	res := Result{Text: text}
	lower := strings.ToLower(text)
	for _, w := range words {
		if w.Word == "" || !strings.Contains(lower, strings.ToLower(w.Word)) {
			continue
		}
		switch int(w.Level) {
		case model.WordLevelBlock:
			return Result{Level: model.WordLevelBlock, Hit: w.Word, Text: text}, nil
		case model.WordLevelReview:
			if res.Level == 0 {
				res.Level, res.Hit = model.WordLevelReview, w.Word
			}
		case model.WordLevelMask:
			res.Text = maskAll(res.Text, w.Word)
			if res.Level == 0 {
				res.Level, res.Hit = model.WordLevelMask, w.Word
			}
		}
	}
	return res, nil
}

// CheckAll 依次机审多段文本,返回打码后的文本、最重处置等级(Block>Review>Mask,0=干净)与首个命中词。
func (f *Filter) CheckAll(ctx context.Context, texts ...string) ([]string, int, string, error) {
	out := make([]string, len(texts))
	level, hit := 0, ""
	for i, t := range texts {
		res, err := f.Check(ctx, t)
		if err != nil {
			return nil, 0, "", err
		}
		out[i] = res.Text
		// level 数值越小处置越重(1拦截 2人审 3打码)
		if res.Level != 0 && (level == 0 || res.Level < level) {
			level, hit = res.Level, res.Hit
		}
	}
	return out, level, hit, nil
}

func (f *Filter) load(ctx context.Context) ([]model.SensitiveWord, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if time.Now().Before(f.expireAt) {
		return f.words, nil
	}
	rows, err := f.m.ListEnabled(ctx)
	if err != nil {
		if f.words != nil { // 加载失败降级用旧词库,不阻塞发布链路
			return f.words, nil
		}
		return nil, err
	}
	// Block(1) 优先于 Review(2) 优先于 Mask(3):按 level 升序即为处置优先级
	for i := 1; i < len(rows); i++ {
		for j := i; j > 0 && rows[j].Level < rows[j-1].Level; j-- {
			rows[j], rows[j-1] = rows[j-1], rows[j]
		}
	}
	f.words, f.expireAt = rows, time.Now().Add(cacheTTL)
	return f.words, nil
}

// maskAll 大小写不敏感地把 word 全部替换为等长*。
func maskAll(text, word string) string {
	lower, lw := strings.ToLower(text), strings.ToLower(word)
	var b strings.Builder
	for {
		i := strings.Index(lower, lw)
		if i < 0 {
			b.WriteString(text)
			return b.String()
		}
		b.WriteString(text[:i])
		b.WriteString(strings.Repeat("*", len([]rune(word))))
		text, lower = text[i+len(lw):], lower[i+len(lw):]
	}
}
