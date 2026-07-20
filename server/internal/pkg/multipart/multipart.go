// Package multipart S3 分片上传封装(minio-go Core):大文件(APK/视频)三段式直传。
// Init 签发全量分片预签名 URL → 客户端并发 PUT → Complete 服务端合并;
// ListParts 支撑断点续传(App 重启后只补缺口),Abort 清碎片。
// 签名注意:分片 URL 由 PublicBaseURL 客户端(host 参与 SigV4)签发,
// Init/Complete/List/Abort 等控制面调用走内网 Endpoint。
package multipart

import (
	"context"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type Config struct {
	Endpoint      string // 内网控制面端点,如 http://minio:9000
	PublicBaseURL string // 客户端可达基址(分片 URL 以此签名),如 http://localhost:9000
	Region        string
	Bucket        string
	AccessKey     string
	SecretKey     string
}

type PartURL struct {
	PartNumber int    `json:"partNumber"`
	URL        string `json:"url"`
}

type Part struct {
	PartNumber int    `json:"partNumber"`
	ETag       string `json:"etag"`
	Size       int64  `json:"size,omitempty"`
}

type Client struct {
	core      *minio.Core   // 控制面(内网)
	presigner *minio.Client // 分片 URL 签名(公网基址)
	bucket    string
}

// parseEndpoint 拆 scheme://host 为 minio.New 需要的 host + secure。
func parseEndpoint(raw string) (host string, secure bool, err error) {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return "", false, fmt.Errorf("multipart: bad endpoint %q", raw)
	}
	return u.Host, u.Scheme == "https", nil
}

func New(cfg Config) (*Client, error) {
	if cfg.PublicBaseURL == "" {
		cfg.PublicBaseURL = cfg.Endpoint
	}
	inHost, inSecure, err := parseEndpoint(cfg.Endpoint)
	if err != nil {
		return nil, err
	}
	pubHost, pubSecure, err := parseEndpoint(cfg.PublicBaseURL)
	if err != nil {
		return nil, err
	}
	creds := credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, "")
	core, err := minio.NewCore(inHost, &minio.Options{Creds: creds, Secure: inSecure, Region: cfg.Region})
	if err != nil {
		return nil, fmt.Errorf("multipart core client: %w", err)
	}
	presigner, err := minio.New(pubHost, &minio.Options{Creds: creds, Secure: pubSecure, Region: cfg.Region})
	if err != nil {
		return nil, fmt.Errorf("multipart presign client: %w", err)
	}
	return &Client{core: core, presigner: presigner, bucket: cfg.Bucket}, nil
}

// Init 创建分片任务并一次性签发全部分片 URL。
func (c *Client) Init(ctx context.Context, objectKey string, partCount int, expiry time.Duration) (string, []PartURL, error) {
	uploadID, err := c.core.NewMultipartUpload(ctx, c.bucket, objectKey, minio.PutObjectOptions{})
	if err != nil {
		return "", nil, fmt.Errorf("new multipart upload: %w", err)
	}
	urls, err := c.PresignParts(ctx, objectKey, uploadID, 1, partCount, expiry)
	if err != nil {
		return "", nil, err
	}
	return uploadID, urls, nil
}

// PresignParts 为 [from, to] 分片区间签发 URL(断点续传时补签过期 URL)。
func (c *Client) PresignParts(ctx context.Context, objectKey, uploadID string, from, to int, expiry time.Duration) ([]PartURL, error) {
	urls := make([]PartURL, 0, to-from+1)
	for n := from; n <= to; n++ {
		q := make(url.Values)
		q.Set("uploadId", uploadID)
		q.Set("partNumber", strconv.Itoa(n))
		u, err := c.presigner.Presign(ctx, "PUT", c.bucket, objectKey, expiry, q)
		if err != nil {
			return nil, fmt.Errorf("presign part %d: %w", n, err)
		}
		urls = append(urls, PartURL{PartNumber: n, URL: u.String()})
	}
	return urls, nil
}

// Complete 合并分片(自动按 partNumber 升序,规避 InvalidPartOrder)。
func (c *Client) Complete(ctx context.Context, objectKey, uploadID string, parts []Part) error {
	sort.Slice(parts, func(i, j int) bool { return parts[i].PartNumber < parts[j].PartNumber })
	cp := make([]minio.CompletePart, 0, len(parts))
	for _, p := range parts {
		cp = append(cp, minio.CompletePart{PartNumber: p.PartNumber, ETag: strings.Trim(p.ETag, `"`)})
	}
	if _, err := c.core.CompleteMultipartUpload(ctx, c.bucket, objectKey, uploadID, cp, minio.PutObjectOptions{}); err != nil {
		return fmt.Errorf("complete multipart: %w", err)
	}
	return nil
}

// Abort 放弃任务并清理已传分片碎片。
func (c *Client) Abort(ctx context.Context, objectKey, uploadID string) error {
	if err := c.core.AbortMultipartUpload(ctx, c.bucket, objectKey, uploadID); err != nil {
		return fmt.Errorf("abort multipart: %w", err)
	}
	return nil
}

// ListParts 已成功上传的分片(断点续传比对用)。
func (c *Client) ListParts(ctx context.Context, objectKey, uploadID string) ([]Part, error) {
	var out []Part
	marker := 0
	for {
		res, err := c.core.ListObjectParts(ctx, c.bucket, objectKey, uploadID, marker, 1000)
		if err != nil {
			return nil, fmt.Errorf("list parts: %w", err)
		}
		for _, p := range res.ObjectParts {
			out = append(out, Part{PartNumber: p.PartNumber, ETag: strings.Trim(p.ETag, `"`), Size: p.Size})
		}
		if !res.IsTruncated {
			break
		}
		marker = res.NextPartNumberMarker
	}
	return out, nil
}
