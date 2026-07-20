// Package jwtx 生成访问令牌;校验由 go-zero rest.WithJwt / ws 网关完成。
package jwtx

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ponytail: 仅 access token(7天),refresh token 轮换等有多端踢下线需求时再加。

const (
	ClaimUID = "uid"
	ClaimDID = "did" // 设备标识,设备踢下线用;旧 token 无此 claim 时跳过设备检查
)

func GenToken(secret string, uid int64, expireSec int64) (token string, expireAt int64, err error) {
	return GenUserToken(secret, uid, "", expireSec)
}

// GenUserToken 用户令牌(带设备标识)。
func GenUserToken(secret string, uid int64, deviceID string, expireSec int64) (token string, expireAt int64, err error) {
	now := time.Now()
	expireAt = now.Add(time.Duration(expireSec) * time.Second).Unix()
	claims := jwt.MapClaims{
		ClaimUID: uid,
		"iat":    now.Unix(),
		"exp":    expireAt,
	}
	if deviceID != "" {
		claims[ClaimDID] = deviceID
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	token, err = t.SignedString([]byte(secret))
	return token, expireAt, err
}

// ---- 管理后台令牌(与用户令牌 claim 结构隔离,用户 token 打后台接口必被拒) ----

const (
	ClaimAdminID = "aid"
	ClaimRoleID  = "role"
)

// GenAdminToken 后台访问令牌(8 小时)。
func GenAdminToken(secret string, adminID, roleID int64) (string, int64, error) {
	now := time.Now()
	expireAt := now.Add(8 * time.Hour).Unix()
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		ClaimAdminID: adminID,
		ClaimRoleID:  roleID,
		"iat":        now.Unix(),
		"exp":        expireAt,
	})
	token, err := t.SignedString([]byte(secret))
	return token, expireAt, err
}

// ParseAdmin 解析后台令牌,返回 adminID/roleID。
func ParseAdmin(secret, tokenStr string) (adminID, roleID int64, err error) {
	t, err := jwt.Parse(tokenStr, func(*jwt.Token) (any, error) { return []byte(secret), nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil {
		return 0, 0, err
	}
	claims, ok := t.Claims.(jwt.MapClaims)
	if !ok {
		return 0, 0, jwt.ErrTokenInvalidClaims
	}
	aid, ok1 := claims[ClaimAdminID].(float64)
	role, ok2 := claims[ClaimRoleID].(float64)
	if !ok1 || !ok2 {
		return 0, 0, jwt.ErrTokenInvalidClaims
	}
	return int64(aid), int64(role), nil
}

// ParseUID 供 ws 网关握手鉴权使用。
func ParseUID(secret, tokenStr string) (int64, error) {
	t, err := jwt.Parse(tokenStr, func(*jwt.Token) (any, error) { return []byte(secret), nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil {
		return 0, err
	}
	claims, ok := t.Claims.(jwt.MapClaims)
	if !ok {
		return 0, jwt.ErrTokenInvalidClaims
	}
	uid, ok := claims[ClaimUID].(float64) // JSON 数字默认 float64
	if !ok {
		return 0, jwt.ErrTokenInvalidClaims
	}
	return int64(uid), nil
}
