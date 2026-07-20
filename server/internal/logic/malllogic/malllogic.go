// Package malllogic 忧珠商城:装扮兑换/仓库/佩戴、靓号兑换、积分抽奖、兑换记录。
// 全部消耗经 model 层单事务(账户行锁+幂等键),余额不足统一 42200 之外的业务码提示。
package malllogic

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/yiora/server/internal/logic/userlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

// drawCost 单次抽奖消耗忧珠。后台可配属运营配置,M4 取产品默认值。
const drawCost = 10

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Decorations 装扮商城列表,登录态标记已拥有。
func (l *Logic) Decorations(ctx context.Context, uid int64, req *types.DecorationListReq) ([]types.DecorationItem, error) {
	rows, err := l.svcCtx.MallModel.ListDecorations(ctx, req.Kind)
	if err != nil {
		return nil, fmt.Errorf("list decorations: %w", err)
	}
	owned := map[int64]bool{}
	if uid > 0 {
		mine, err := l.svcCtx.MallModel.MyDecorations(ctx, uid, req.Kind)
		if err != nil {
			return nil, fmt.Errorf("my decorations: %w", err)
		}
		now := time.Now()
		for _, d := range mine {
			if !d.ExpireAt.Valid || d.ExpireAt.Time.After(now) {
				owned[d.DecorationID] = true
			}
		}
	}
	out := make([]types.DecorationItem, 0, len(rows))
	for _, d := range rows {
		out = append(out, types.DecorationItem{
			ID: d.ID, Kind: d.Kind, Name: d.Name, Preview: d.Preview,
			Price: d.Price, DurationDays: d.DurationDays, Owned: owned[d.ID],
		})
	}
	return out, nil
}

// Exchange 兑换装扮。
func (l *Logic) Exchange(ctx context.Context, uid, decorationID int64) error {
	if err := userlogic.EnsureNotTeen(ctx, l.svcCtx, uid); err != nil {
		return err
	}
	d, err := l.svcCtx.MallModel.FindDecoration(ctx, decorationID)
	if err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "装扮不存在或已下架")
		}
		return fmt.Errorf("find decoration: %w", err)
	}
	if err := l.svcCtx.MallModel.ExchangeDecoration(ctx, uid, d); err != nil {
		switch {
		case errors.Is(err, model.ErrAlreadyOwned):
			return xerr.New(xerr.CodeTooFrequent, "你已拥有该装扮")
		case errors.Is(err, model.ErrInsufficientBalance):
			return xerr.New(xerr.CodeForbidden, "忧珠余额不足")
		}
		return fmt.Errorf("exchange decoration: %w", err)
	}
	return nil
}

// Mine 我的仓库。
func (l *Logic) Mine(ctx context.Context, uid int64, req *types.DecorationListReq) ([]types.MyDecorationItem, error) {
	rows, err := l.svcCtx.MallModel.MyDecorations(ctx, uid, req.Kind)
	if err != nil {
		return nil, fmt.Errorf("my decorations: %w", err)
	}
	now := time.Now()
	out := make([]types.MyDecorationItem, 0, len(rows))
	for _, d := range rows {
		item := types.MyDecorationItem{
			DecorationID: d.DecorationID,
			Kind:         d.Kind,
			Name:         d.Name,
			Preview:      d.Preview,
			Worn:         d.Worn == 1,
		}
		if d.ExpireAt.Valid {
			item.ExpireAt = d.ExpireAt.Time.UnixMilli()
			item.Expired = d.ExpireAt.Time.Before(now)
		}
		out = append(out, item)
	}
	return out, nil
}

// Wear 佩戴(同 kind 互斥);TakeOff 卸下。
func (l *Logic) Wear(ctx context.Context, uid, decorationID int64) error {
	if err := l.svcCtx.MallModel.Wear(ctx, uid, decorationID); err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "未拥有该装扮或已过期")
		}
		return fmt.Errorf("wear: %w", err)
	}
	return nil
}

func (l *Logic) TakeOff(ctx context.Context, uid, decorationID int64) error {
	if err := l.svcCtx.MallModel.TakeOff(ctx, uid, decorationID); err != nil {
		return fmt.Errorf("take off: %w", err)
	}
	return nil
}

// PrettyNos 靓号商城在售列表。
func (l *Logic) PrettyNos(ctx context.Context, req *types.PageReq) ([]types.PrettyNoItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.MallModel.ListPrettyNo(ctx, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("list pretty no: %w", err)
	}
	out := make([]types.PrettyNoItem, 0, len(rows))
	for _, s := range rows {
		out = append(out, types.PrettyNoItem{ID: s.ID, No: s.No, Rarity: s.Rarity, Price: s.Price})
	}
	return out, nil
}

// ExchangeNo 兑换靓号并替换展示编号。
func (l *Logic) ExchangeNo(ctx context.Context, uid, skuID int64) (*types.ExchangeNoResp, error) {
	if err := userlogic.EnsureNotTeen(ctx, l.svcCtx, uid); err != nil {
		return nil, err
	}
	no, err := l.svcCtx.MallModel.ExchangePrettyNo(ctx, uid, skuID)
	if err != nil {
		switch {
		case model.IsNotFound(err):
			return nil, xerr.New(xerr.CodeNotFound, "靓号不存在")
		case errors.Is(err, model.ErrSkuSoldOut):
			return nil, xerr.New(xerr.CodeTooFrequent, "手慢了,该靓号已被兑换")
		case errors.Is(err, model.ErrNoConflict):
			return nil, xerr.New(xerr.CodeInvalidParam, "该靓号与现有编号冲突,请联系客服")
		case errors.Is(err, model.ErrInsufficientBalance):
			return nil, xerr.New(xerr.CodeForbidden, "忧珠余额不足")
		}
		return nil, fmt.Errorf("exchange pretty no: %w", err)
	}
	balance, err := l.svcCtx.YouzhuModel.Balance(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("balance: %w", err)
	}
	return &types.ExchangeNoResp{No: no, Balance: balance}, nil
}

// Pools 奖池与概率公示。
func (l *Logic) Pools(ctx context.Context) (*types.LotteryPoolsResp, error) {
	rows, err := l.svcCtx.MallModel.ListPrizes(ctx)
	if err != nil {
		return nil, fmt.Errorf("list prizes: %w", err)
	}
	resp := &types.LotteryPoolsResp{Cost: drawCost, Prizes: make([]types.PrizeItem, 0, len(rows))}
	for _, p := range rows {
		resp.Prizes = append(resp.Prizes, types.PrizeItem{
			ID: p.ID, Name: p.Name, Kind: p.Kind, Amount: p.Amount, Weight: p.Weight,
		})
	}
	return resp, nil
}

// Draw 抽一次奖。
func (l *Logic) Draw(ctx context.Context, uid int64) (*types.DrawResp, error) {
	if err := userlogic.EnsureNotTeen(ctx, l.svcCtx, uid); err != nil {
		return nil, err
	}
	prize, err := l.svcCtx.MallModel.Draw(ctx, uid, drawCost)
	if err != nil {
		switch {
		case errors.Is(err, model.ErrInsufficientBalance):
			return nil, xerr.New(xerr.CodeForbidden, "忧珠余额不足")
		case errors.Is(err, model.ErrPoolEmpty):
			return nil, xerr.New(xerr.CodeNotFound, "奖池已空,请稍后再来")
		}
		return nil, fmt.Errorf("draw: %w", err)
	}
	balance, err := l.svcCtx.YouzhuModel.Balance(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("balance: %w", err)
	}
	return &types.DrawResp{
		Prize:   types.PrizeItem{ID: prize.ID, Name: prize.Name, Kind: prize.Kind, Amount: prize.Amount, Weight: prize.Weight},
		Balance: balance,
	}, nil
}

// Records 兑换记录页。
func (l *Logic) Records(ctx context.Context, uid int64, req *types.PageReq) ([]types.ExchangeRecordItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.MallModel.ExchangeRecords(ctx, uid, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("exchange records: %w", err)
	}
	out := make([]types.ExchangeRecordItem, 0, len(rows))
	for _, r := range rows {
		out = append(out, types.ExchangeRecordItem{
			ID: r.ID, Kind: r.Kind, Name: r.Name, Cost: r.Cost, CreatedAt: r.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}
