// Package growth 成长体系公共入口:行为经验授予(权重后台可配 + 每日上限)。
// 独立小包无 logic 依赖,post/comment/task 等任何 logic 均可安全引用(不会成环)。
package growth

import (
	"context"
	"fmt"
	"time"

	"github.com/yiora/server/internal/svc"

	"github.com/zeromicro/go-zero/core/logx"
)

// 行为类型 → 配置键(app_config,后台「等级规则」页可调)
const (
	KindPost         = "exp.post"          // 发帖
	KindComment      = "exp.comment"       // 评论
	KindSign         = "exp.sign"          // 签到
	KindLikeReceived = "exp.like_received" // 帖子被赞(给作者)
)

// 参数表被清空时的兜底默认(与迁移种子一致)
var defaults = map[string]int64{
	KindPost: 5, KindComment: 2, KindSign: 5, KindLikeReceived: 1,
	"exp.daily_cap": 100,
}

// Grant 行为加经验:读权重 → 每日上限裁剪(Redis 日计数) → 入账。
// 失败只记日志不阻塞业务主流程(经验是激励,不是账务)。
func Grant(ctx context.Context, svcCtx *svc.ServiceContext, uid int64, kind string) {
	exp := svcCtx.ConfigModel.Int(ctx, kind, defaults[kind])
	GrantN(ctx, svcCtx, uid, exp)
}

// GrantN 指定数值加经验(任务奖励等自带配置的场景),同样受每日上限约束。
func GrantN(ctx context.Context, svcCtx *svc.ServiceContext, uid, exp int64) {
	if exp <= 0 {
		return
	}
	cap_ := svcCtx.ConfigModel.Int(ctx, "exp.daily_cap", defaults["exp.daily_cap"])
	if cap_ > 0 {
		key := fmt.Sprintf("exp:daily:%d:%s", uid, time.Now().Format("20060102"))
		used, err := svcCtx.Redis.IncrbyCtx(ctx, key, exp)
		if err == nil && used == exp {
			_ = svcCtx.Redis.ExpireCtx(ctx, key, 2*86400)
		}
		if err == nil {
			if used-exp >= cap_ { // 加之前已满
				return
			}
			if used > cap_ { // 本次跨过上限,只给剩余额度
				exp = cap_ - (used - exp)
			}
		}
	}
	if err := svcCtx.UserModel.AddExp(ctx, uid, exp); err != nil {
		logx.WithContext(ctx).Errorf("grant exp uid=%d: %v", uid, err)
	}
}
