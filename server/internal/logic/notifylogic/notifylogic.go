// Package notifylogic 聚合通知:三类列表/未读角标/进入清零。
package notifylogic

import (
	"context"
	"fmt"

	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// List 某一聚合入口的通知列表。
func (l *Logic) List(ctx context.Context, uid int64, req *types.NotifyListReq) ([]types.NotifyItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.NotifyModel.List(ctx, uid, req.Type, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("notify list: %w", err)
	}
	out := make([]types.NotifyItem, 0, len(rows))
	if len(rows) == 0 {
		return out, nil
	}
	actorIDs := make([]int64, 0, len(rows))
	for _, n := range rows {
		if n.ActorID > 0 {
			actorIDs = append(actorIDs, n.ActorID)
		}
	}
	briefs, err := l.svcCtx.UserModel.FindBriefs(ctx, actorIDs)
	if err != nil {
		return nil, fmt.Errorf("actor briefs: %w", err)
	}
	for _, n := range rows {
		item := types.NotifyItem{
			ID:         n.ID,
			Type:       n.Type,
			TargetType: n.TargetType,
			TargetID:   n.TargetID,
			Content:    n.Content,
			IsRead:     n.IsRead == 1,
			CreatedAt:  n.CreatedAt.UnixMilli(),
		}
		if n.ActorID > 0 {
			item.Actor = postlogic.ToUserBrief(n.ActorID, briefs[n.ActorID])
		}
		out = append(out, item)
	}
	return out, nil
}

// MarkRead 进入某聚合页时该类未读清零。
func (l *Logic) MarkRead(ctx context.Context, uid int64, req *types.NotifyReadReq) error {
	if err := l.svcCtx.NotifyModel.MarkAllRead(ctx, uid, req.Type); err != nil {
		return fmt.Errorf("notify mark read: %w", err)
	}
	return nil
}

// Unread 消息页角标:三类通知未读 + 私信未读总数。
func (l *Logic) Unread(ctx context.Context, uid int64) (*types.UnreadResp, error) {
	counts, err := l.svcCtx.NotifyModel.UnreadCounts(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("notify unread: %w", err)
	}
	im, err := l.svcCtx.IMModel.UnreadTotal(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("im unread: %w", err)
	}
	resp := &types.UnreadResp{
		IM:      im,
		Like:    counts[model.NotifyTypeLike],
		Comment: counts[model.NotifyTypeComment],
		System:  counts[model.NotifyTypeSystem],
	}
	resp.Total = resp.IM + resp.Like + resp.Comment + resp.System
	return resp, nil
}
