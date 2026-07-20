package config

import (
	"github.com/zeromicro/go-zero/core/stores/redis"
	"github.com/zeromicro/go-zero/rest"
)

type Config struct {
	rest.RestConf

	Auth struct {
		AccessSecret  string // JWT HS256 密钥,api 与 ws 网关必须一致
		AccessExpire  int64  // 访问令牌有效期(秒)
		RefreshExpire int64  `json:",default=2592000"` // 刷新令牌有效期(秒,默认 30 天)
		MaxDevices    int    `json:",default=5"`       // 单账号设备上限,超出踢最久未活跃
	}

	MySQL struct {
		DataSource string
	}

	Redis redis.RedisConf

	WsPush struct {
		URL   string `json:",optional"`
		Token string `json:",optional"`
	}

	Email struct {
		Host     string
		Port     int
		Username string
		Password string
		From     string
		Mock     bool // true 时验证码只写日志不真发,本地开发用
	}

	Admin struct {
		IPAllowlist    string `json:",optional"`    // 后台访问 IP 白名单,逗号分隔 IP/CIDR;空=不限制
		LoginFailLimit int    `json:",default=5"`   // 同账号连续错密上限
		LoginLockSec   int    `json:",default=900"` // 触发上限后的锁定秒数
	} `json:",optional"`

	Storage struct {
		Endpoint      string `json:",optional"` // S3 兼容端点(容器内可达),如 http://minio:9000
		PublicBaseURL string `json:",optional"` // 客户端可达的公开基址(直传与回源),如 http://localhost:9000
		Region        string `json:",default=us-east-1"`
		Bucket        string `json:",optional"`
		AccessKey     string `json:",optional"`
		SecretKey     string `json:",optional"`
	} `json:",optional"` // Endpoint 为空时上传接口返回未配置错误
}
