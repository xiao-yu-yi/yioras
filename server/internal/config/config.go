package config

import (
	"github.com/zeromicro/go-zero/core/stores/redis"
	"github.com/zeromicro/go-zero/rest"
)

type Config struct {
	rest.RestConf

	Auth struct {
		AccessSecret string // JWT HS256 密钥,api 与 ws 网关必须一致
		AccessExpire int64  // 秒
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
}
