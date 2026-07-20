// Package apppush 离线推送抽象层:App 进程不在线(ws 无连接)时经 APNs/厂商系统级通道触达。
// Manager 按 token 的 channel 路由驱动;未配置的渠道静默跳过(本地/CI 零外部依赖,失败不阻塞业务)。
// 驱动矩阵:mock(联调冒烟,写 Redis 供断言)、apns(HTTP/2+JWT ES256,已实现);
// huawei/xiaomi/oppo/vivo 随厂商账号开通逐家补(实现 Pusher 接口注册进 Manager 即可)。
package apppush

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/zeromicro/go-zero/core/logx"
	"github.com/zeromicro/go-zero/core/stores/redis"
)

// Notification 一条离线推送。Deeplink 形如 yiora://post/123,客户端点击通知路由。
type Notification struct {
	Title    string `json:"title"`
	Body     string `json:"body"`
	Deeplink string `json:"deeplink"`
}

// Pusher 单渠道驱动。
type Pusher interface {
	Name() string
	Send(ctx context.Context, token string, n Notification) error
}

// Manager 渠道路由器。空 Manager(无驱动)所有 Send 直接跳过。
// 每次发送按渠道×结果落 Redis 日计数(30 天滚动),供后台推送看板。
type Manager struct {
	drivers map[string]Pusher
	rds     *redis.Redis
}

func NewManager(rds *redis.Redis) *Manager {
	return &Manager{drivers: map[string]Pusher{}, rds: rds}
}

func (m *Manager) Register(channel string, p Pusher) {
	if p != nil {
		m.drivers[channel] = p
	}
}

// Enabled 是否有任一驱动在册(调用方可先判再查 token 表,省一次查询)。
func (m *Manager) Enabled() bool { return len(m.drivers) > 0 }

// Channels 在册渠道名(看板遍历用),字典序稳定输出。
func (m *Manager) Channels() []string {
	out := make([]string, 0, len(m.drivers))
	for c := range m.drivers {
		out = append(out, c)
	}
	sort.Strings(out)
	return out
}

// StatKey 渠道日计数 key(Manager 写入与看板读取共用,result 取 ok/fail)。
func StatKey(channel, result, yyyymmdd string) string {
	return fmt.Sprintf("push:stat:%s:%s:%s", channel, result, yyyymmdd)
}

func (m *Manager) incrStat(ctx context.Context, channel, result string) {
	if m.rds == nil {
		return
	}
	key := StatKey(channel, result, time.Now().Format("20060102"))
	if n, err := m.rds.IncrCtx(ctx, key); err == nil && n == 1 {
		_ = m.rds.ExpireCtx(ctx, key, 30*86400)
	}
}

// Send 按渠道路由;渠道未配置或发送失败只记日志(离线推送是尽力而为的补偿,不影响主链路)。
func (m *Manager) Send(ctx context.Context, channel, token string, n Notification) {
	d, ok := m.drivers[channel]
	if !ok {
		return
	}
	if err := d.Send(ctx, token, n); err != nil {
		logx.WithContext(ctx).Errorf("apppush %s: %v", d.Name(), err)
		m.incrStat(ctx, channel, "fail")
		return
	}
	m.incrStat(ctx, channel, "ok")
}
