package authlogic

// 设备与刷新令牌:Redis 存储,支持多端登录、上限淘汰、单设备踢下线(存量 access token 即时失效)。
// 结构:
//   user:devices:{uid}       hash  field=deviceId value=JSON{rtHash,name,ip,lastLoginMs}
//   user:rt:{sha256(rt)}     string JSON{uid,deviceId}  TTL=RefreshExpire(轮换即删旧建新)
//   user:kick:{uid}:{did}    string "1"                 TTL=AccessExpire(踢下线标记,guard 拦截)

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/yiora/server/internal/pkg/jwtx"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

type deviceInfo struct {
	RtHash    string `json:"rtHash"`
	Name      string `json:"name"`
	IP        string `json:"ip"`
	LastLogin int64  `json:"lastLogin"` // 毫秒
}

func devicesKey(uid int64) string          { return fmt.Sprintf("user:devices:%d", uid) }
func rtKey(rtHash string) string           { return "user:rt:" + rtHash }
func kickKey(uid int64, did string) string { return fmt.Sprintf("user:kick:%d:%s", uid, did) }

// KickKey 供 handler 层守卫检查(claim 带 did 的存量 token)。
func KickKey(uid int64, did string) string { return kickKey(uid, did) }

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func hashRT(rt string) string {
	sum := sha256.Sum256([]byte(rt))
	return hex.EncodeToString(sum[:])
}

// registerDevice 登录/注册时登记设备并签发刷新令牌;超上限按最久未登录淘汰(等效踢下线)。
func (l *Logic) registerDevice(ctx context.Context, uid int64, deviceName, ip string) (deviceID, refreshToken string, refreshExpireAt int64) {
	deviceID = randHex(8)
	refreshToken = randHex(32)
	name := strings.TrimSpace(deviceName)
	if name == "" {
		name = "未命名设备"
	}
	if len(ip) > 45 {
		ip = ip[:45]
	}
	rtHash := hashRT(refreshToken)
	refreshExpire := l.svcCtx.Config.Auth.RefreshExpire
	refreshExpireAt = time.Now().Add(time.Duration(refreshExpire) * time.Second).Unix()

	info, _ := json.Marshal(deviceInfo{RtHash: rtHash, Name: truncate(name, 40), IP: ip, LastLogin: time.Now().UnixMilli()})
	if err := l.svcCtx.Redis.HsetCtx(ctx, devicesKey(uid), deviceID, string(info)); err != nil {
		logx.WithContext(ctx).Errorf("register device: %v", err)
		return deviceID, "", 0 // Redis 故障降级:无刷新能力但登录不受阻
	}
	_ = l.svcCtx.Redis.ExpireCtx(ctx, devicesKey(uid), int(refreshExpire))
	payload, _ := json.Marshal(map[string]any{"uid": uid, "did": deviceID})
	if err := l.svcCtx.Redis.SetexCtx(ctx, rtKey(rtHash), string(payload), int(refreshExpire)); err != nil {
		logx.WithContext(ctx).Errorf("store refresh token: %v", err)
	}
	l.evictOverLimit(ctx, uid)
	return deviceID, refreshToken, refreshExpireAt
}

// evictOverLimit 设备数超上限时,踢最久未登录的设备。
func (l *Logic) evictOverLimit(ctx context.Context, uid int64) {
	limit := l.svcCtx.Config.Auth.MaxDevices
	if limit <= 0 {
		limit = 5
	}
	all, err := l.svcCtx.Redis.HgetallCtx(ctx, devicesKey(uid))
	if err != nil || len(all) <= limit {
		return
	}
	type entry struct {
		did  string
		info deviceInfo
	}
	list := make([]entry, 0, len(all))
	for did, raw := range all {
		var d deviceInfo
		if json.Unmarshal([]byte(raw), &d) == nil {
			list = append(list, entry{did: did, info: d})
		}
	}
	sort.Slice(list, func(i, j int) bool { return list[i].info.LastLogin < list[j].info.LastLogin })
	for i := 0; i < len(list)-limit; i++ {
		l.removeDevice(ctx, uid, list[i].did, list[i].info.RtHash)
	}
}

func (l *Logic) removeDevice(ctx context.Context, uid int64, did, rtHash string) {
	_, _ = l.svcCtx.Redis.HdelCtx(ctx, devicesKey(uid), did)
	if rtHash != "" {
		_, _ = l.svcCtx.Redis.DelCtx(ctx, rtKey(rtHash))
	}
	// 存量 access token 拦到自然过期即可
	_ = l.svcCtx.Redis.SetexCtx(ctx, kickKey(uid, did), "1", int(l.svcCtx.Config.Auth.AccessExpire))
}

// Refresh 刷新令牌轮换:旧 refresh token 一次性作废,发新 access + refresh 对。
func (l *Logic) Refresh(ctx context.Context, req *types.RefreshReq, ip string) (*types.TokenResp, error) {
	rtHash := hashRT(strings.TrimSpace(req.RefreshToken))
	raw, err := l.svcCtx.Redis.GetCtx(ctx, rtKey(rtHash))
	if err != nil || raw == "" {
		return nil, xerr.New(xerr.CodeUnauthorized, "刷新令牌无效或已过期,请重新登录")
	}
	var payload struct {
		UID int64  `json:"uid"`
		DID string `json:"did"`
	}
	if err := json.Unmarshal([]byte(raw), &payload); err != nil || payload.DID != strings.TrimSpace(req.DeviceID) {
		return nil, xerr.New(xerr.CodeUnauthorized, "刷新令牌与设备不匹配")
	}
	u, err := l.svcCtx.UserModel.FindByID(ctx, payload.UID)
	if err != nil {
		return nil, xerr.New(xerr.CodeUnauthorized, "账号状态异常,请重新登录")
	}
	if u.Status == 3 || u.Status == 4 {
		return nil, xerr.New(xerr.CodeForbidden, "账号不可用")
	}

	// 轮换:删旧 rt,同设备位写入新 rt
	_, _ = l.svcCtx.Redis.DelCtx(ctx, rtKey(rtHash))
	newRT := randHex(32)
	newHash := hashRT(newRT)
	refreshExpire := l.svcCtx.Config.Auth.RefreshExpire
	if len(ip) > 45 {
		ip = ip[:45]
	}
	// 保留设备名
	name := "未命名设备"
	if old, err := l.svcCtx.Redis.HgetCtx(ctx, devicesKey(payload.UID), payload.DID); err == nil && old != "" {
		var d deviceInfo
		if json.Unmarshal([]byte(old), &d) == nil && d.Name != "" {
			name = d.Name
		}
	}
	info, _ := json.Marshal(deviceInfo{RtHash: newHash, Name: name, IP: ip, LastLogin: time.Now().UnixMilli()})
	if err := l.svcCtx.Redis.HsetCtx(ctx, devicesKey(payload.UID), payload.DID, string(info)); err != nil {
		return nil, fmt.Errorf("rotate device: %w", err)
	}
	_ = l.svcCtx.Redis.ExpireCtx(ctx, devicesKey(payload.UID), int(refreshExpire))
	np, _ := json.Marshal(map[string]any{"uid": payload.UID, "did": payload.DID})
	if err := l.svcCtx.Redis.SetexCtx(ctx, rtKey(newHash), string(np), int(refreshExpire)); err != nil {
		return nil, fmt.Errorf("store rotated rt: %w", err)
	}

	token, expireAt, err := jwtx.GenUserToken(l.svcCtx.Config.Auth.AccessSecret, payload.UID, payload.DID, l.svcCtx.Config.Auth.AccessExpire)
	if err != nil {
		return nil, fmt.Errorf("gen token: %w", err)
	}
	return &types.TokenResp{
		UserID: payload.UID, Token: token, ExpireAt: expireAt,
		RefreshToken: newRT, RefreshExpireAt: time.Now().Add(time.Duration(refreshExpire) * time.Second).Unix(),
		DeviceID: payload.DID, DisplayNo: u.DisplayNo.String, Nickname: u.Nickname, Avatar: u.Avatar,
	}, nil
}

// Devices 我的登录设备列表(按最近登录倒序)。
func (l *Logic) Devices(ctx context.Context, uid int64, currentDID string) ([]types.DeviceItem, error) {
	all, err := l.svcCtx.Redis.HgetallCtx(ctx, devicesKey(uid))
	if err != nil {
		return nil, fmt.Errorf("list devices: %w", err)
	}
	out := make([]types.DeviceItem, 0, len(all))
	for did, raw := range all {
		var d deviceInfo
		if json.Unmarshal([]byte(raw), &d) != nil {
			continue
		}
		out = append(out, types.DeviceItem{
			DeviceID: did, Name: d.Name, IP: d.IP, LastLoginAt: d.LastLogin, Current: did == currentDID,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].LastLoginAt > out[j].LastLoginAt })
	return out, nil
}

// KickDevice 踢设备下线:刷新令牌作废 + 存量 access token 即时失效。
func (l *Logic) KickDevice(ctx context.Context, uid int64, did string) error {
	raw, err := l.svcCtx.Redis.HgetCtx(ctx, devicesKey(uid), did)
	if err != nil || raw == "" {
		return xerr.New(xerr.CodeNotFound, "设备不存在或已下线")
	}
	var d deviceInfo
	_ = json.Unmarshal([]byte(raw), &d)
	l.removeDevice(ctx, uid, did, d.RtHash)
	return nil
}
