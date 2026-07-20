// Package imgscan 图片机审抽象层:直传落库后异步送云端审核,结果三态(放行/转人审/拦截)。
// 设计约束:未配置 Provider 时上层拿到 nil Scanner 直接跳过,本地开发与 CI 不依赖外网;
// 云端故障由调用方降级放行(纯人审兜底),不阻断业务发布链路。
package imgscan

import (
	"context"
	"fmt"
	"strings"
)

// Verdict 机审结论。
type Verdict int

const (
	VerdictPass   Verdict = iota // 放行
	VerdictReview                // 疑似,转人审队列
	VerdictBlock                 // 高置信违规,直接拦截
)

// Result 单图机审结果。
type Result struct {
	Verdict Verdict
	Label   string  // 命中标签,如 porn/terror/ad
	Score   float64 // 置信度 0~1
}

// Scanner 机审驱动接口。腾讯 IMS/阿里云驱动二期按此实现,单点替换。
type Scanner interface {
	Name() string
	Scan(ctx context.Context, imageURL string) (*Result, error)
}

// New 按配置构造驱动。provider 为空返回 nil(功能关闭);未知 provider 报错(防配置写错静默失效)。
func New(provider string) (Scanner, error) {
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case "":
		return nil, nil
	case "mock":
		return &mockScanner{}, nil
	default:
		// tencent/aliyun 驱动随二期机审接入落地
		return nil, fmt.Errorf("imgscan: unsupported provider %q", provider)
	}
}

// mockScanner 联调/冒烟驱动:按 URL 关键字出结论,不访问网络。
// 约定:URL 含 mock-block 判拦截,含 mock-review 判转人审,其余放行。
type mockScanner struct{}

func (s *mockScanner) Name() string { return "mock" }

func (s *mockScanner) Scan(_ context.Context, imageURL string) (*Result, error) {
	u := strings.ToLower(imageURL)
	switch {
	case strings.Contains(u, "mock-block"):
		return &Result{Verdict: VerdictBlock, Label: "mock_porn", Score: 0.98}, nil
	case strings.Contains(u, "mock-review"):
		return &Result{Verdict: VerdictReview, Label: "mock_sexy_suspect", Score: 0.72}, nil
	default:
		return &Result{Verdict: VerdictPass, Label: "normal", Score: 0.99}, nil
	}
}
