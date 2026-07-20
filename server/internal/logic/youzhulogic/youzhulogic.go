// Package youzhulogic 忧珠(积分)资产:余额与收支流水。
package youzhulogic

import (
	"context"
	"fmt"
	"time"

	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Account 忧珠资产页头部:余额 + 今日签到状态。
func (l *Logic) Account(ctx context.Context, uid int64) (*types.YouzhuAccountResp, error) {
	balance, err := l.svcCtx.YouzhuModel.Balance(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("balance: %w", err)
	}
	signed := true
	if _, err := l.svcCtx.TaskModel.FindSign(ctx, uid, time.Now().Format("2006-01-02")); err != nil {
		if !model.IsNotFound(err) {
			return nil, fmt.Errorf("find sign: %w", err)
		}
		signed = false
	}
	return &types.YouzhuAccountResp{Balance: balance, SignedToday: signed}, nil
}

// Logs 收支流水(按类型筛选)。
func (l *Logic) Logs(ctx context.Context, uid int64, req *types.YouzhuLogsReq) ([]types.YouzhuLogItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.YouzhuModel.Logs(ctx, uid, req.BizType, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("youzhu logs: %w", err)
	}
	out := make([]types.YouzhuLogItem, 0, len(rows))
	for _, r := range rows {
		out = append(out, types.YouzhuLogItem{
			ID:           r.ID,
			BizType:      r.BizType,
			Amount:       r.Amount,
			BalanceAfter: r.BalanceAfter,
			Remark:       r.Remark,
			CreatedAt:    r.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}
