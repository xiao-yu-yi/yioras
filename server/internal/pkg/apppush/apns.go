package apppush

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// APNsConfig .p8 鉴权密钥方式(免证书轮换)。Production=false 走沙箱环境。
type APNsConfig struct {
	KeyID      string
	TeamID     string
	BundleID   string
	PrivateKey string // p8 PEM 全文(经环境变量注入)
	Production bool
}

type apnsPusher struct {
	cfg    APNsConfig
	key    *ecdsa.PrivateKey
	client *http.Client
	host   string

	mu       sync.Mutex
	jwtToken string
	jwtAt    time.Time
}

// NewAPNs 解析 .p8 私钥并构造驱动;配置不全返回 nil(渠道不启用)。
func NewAPNs(cfg APNsConfig) (Pusher, error) {
	if cfg.KeyID == "" || cfg.TeamID == "" || cfg.BundleID == "" || cfg.PrivateKey == "" {
		return nil, nil
	}
	block, _ := pem.Decode([]byte(cfg.PrivateKey))
	if block == nil {
		return nil, fmt.Errorf("apns: bad p8 pem")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("apns: parse p8: %w", err)
	}
	ecKey, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("apns: p8 is not an ECDSA key")
	}
	host := "https://api.sandbox.push.apple.com"
	if cfg.Production {
		host = "https://api.push.apple.com"
	}
	return &apnsPusher{
		cfg: cfg, key: ecKey, host: host,
		client: &http.Client{Timeout: 5 * time.Second}, // Go http 对 https 默认启用 HTTP/2
	}, nil
}

func (p *apnsPusher) Name() string { return "apns" }

// jwt 提供商令牌 50 分钟内复用(Apple 要求 20~60 分钟内轮换)。
func (p *apnsPusher) jwt() (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.jwtToken != "" && time.Since(p.jwtAt) < 50*time.Minute {
		return p.jwtToken, nil
	}
	b64 := func(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": p.cfg.KeyID})
	claims, _ := json.Marshal(map[string]any{"iss": p.cfg.TeamID, "iat": time.Now().Unix()})
	signing := b64(header) + "." + b64(claims)
	sum := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, p.key, sum[:])
	if err != nil {
		return "", fmt.Errorf("apns sign: %w", err)
	}
	// JOSE 签名格式:r/s 各定长 32 字节拼接
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	p.jwtToken = signing + "." + b64(sig)
	p.jwtAt = time.Now()
	return p.jwtToken, nil
}

func (p *apnsPusher) Send(ctx context.Context, token string, n Notification) error {
	jwt, err := p.jwt()
	if err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{
		"aps": map[string]any{
			"alert": map[string]string{"title": n.Title, "body": n.Body},
			"sound": "default",
		},
		"deeplink": n.Deeplink,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		p.host+"/3/device/"+strings.TrimSpace(token), bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", p.cfg.BundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("apns status %d: %s", resp.StatusCode, string(raw))
	}
	return nil
}
