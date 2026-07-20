package apppush

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/zeromicro/go-zero/core/stores/redis"
)

// mockPusher 联调/冒烟驱动:把最后一条推送写入 Redis(mockpush:last:{token}),
// 冒烟脚本经 redis-cli 断言离线路由与频控行为,不出外网。
type mockPusher struct {
	rds *redis.Redis
}

func NewMock(rds *redis.Redis) Pusher { return &mockPusher{rds: rds} }

func (p *mockPusher) Name() string { return "mock" }

func (p *mockPusher) Send(ctx context.Context, token string, n Notification) error {
	raw, _ := json.Marshal(n)
	if err := p.rds.SetexCtx(ctx, "mockpush:last:"+token, string(raw), 600); err != nil {
		return fmt.Errorf("mock push store: %w", err)
	}
	_, _ = p.rds.IncrCtx(ctx, "mockpush:count:"+token)
	_ = p.rds.ExpireCtx(ctx, "mockpush:count:"+token, 600)
	return nil
}
