// Package llm OpenAI 兼容对话补全客户端(AI 管家二期大模型应答)。
// 只依赖 /chat/completions 一个端点,DeepSeek/通义/豆包同协议,换厂商改 BaseURL+Model 即可。
// BaseURL 未配置时上层拿到 nil Client,管家退回纯 FAQ 规则模式(本地/CI 零外网依赖)。
package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type Config struct {
	BaseURL    string // 如 https://api.deepseek.com
	APIKey     string
	Model      string // 如 deepseek-v4-flash
	TimeoutSec int
}

type Message struct {
	Role    string `json:"role"` // system / user / assistant
	Content string `json:"content"`
}

type Client struct {
	cfg  Config
	http *http.Client
}

// New BaseURL 为空返回 nil(功能关闭)。
func New(cfg Config) *Client {
	if strings.TrimSpace(cfg.BaseURL) == "" {
		return nil
	}
	if cfg.TimeoutSec <= 0 {
		cfg.TimeoutSec = 5
	}
	return &Client{cfg: cfg, http: &http.Client{Timeout: time.Duration(cfg.TimeoutSec) * time.Second}}
}

type chatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	MaxTokens   int       `json:"max_tokens"`
	Temperature float64   `json:"temperature"`
}

type chatResponse struct {
	Choices []struct {
		Message Message `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

// Chat 单轮补全:system 提示 + 历史消息,返回助手回复文本。
func (c *Client) Chat(ctx context.Context, system string, msgs []Message) (string, error) {
	all := make([]Message, 0, len(msgs)+1)
	if system != "" {
		all = append(all, Message{Role: "system", Content: system})
	}
	all = append(all, msgs...)
	body, err := json.Marshal(chatRequest{Model: c.cfg.Model, Messages: all, MaxTokens: 500, Temperature: 0.7})
	if err != nil {
		return "", fmt.Errorf("llm marshal: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		strings.TrimRight(c.cfg.BaseURL, "/")+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("llm request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.cfg.APIKey)
	resp, err := c.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("llm call: %w", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", fmt.Errorf("llm read: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("llm status %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}
	var out chatResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("llm decode: %w", err)
	}
	if out.Error != nil {
		return "", fmt.Errorf("llm api error: %s", out.Error.Message)
	}
	if len(out.Choices) == 0 || strings.TrimSpace(out.Choices[0].Message.Content) == "" {
		return "", fmt.Errorf("llm empty completion")
	}
	return strings.TrimSpace(out.Choices[0].Message.Content), nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
