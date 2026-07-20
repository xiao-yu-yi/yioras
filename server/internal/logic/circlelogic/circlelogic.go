// Package circlelogic 圈子:发现列表/详情/加入退出/圈内信息流。
package circlelogic

import (
	"context"
	"fmt"

	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// List 发现圈子。uid=0(未登录)时 joined 恒为 false。
func (l *Logic) List(ctx context.Context, uid int64, req *types.CircleListReq) ([]types.CircleItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.CircleModel.List(ctx, req.Sort, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("circle list: %w", err)
	}
	ids := make([]int64, 0, len(rows))
	for _, c := range rows {
		ids = append(ids, c.ID)
	}
	joined, err := l.svcCtx.CircleModel.MemberMap(ctx, uid, ids)
	if err != nil {
		return nil, fmt.Errorf("member map: %w", err)
	}
	out := make([]types.CircleItem, 0, len(rows))
	for _, c := range rows {
		out = append(out, toItem(c, joined[c.ID]))
	}
	return out, nil
}

// DecorateCircles 供搜索等外部模块复用:批量补 joined 状态并组装列表项。
func (l *Logic) DecorateCircles(ctx context.Context, uid int64, rows []*model.Circle) ([]types.CircleItem, error) {
	ids := make([]int64, 0, len(rows))
	for _, c := range rows {
		ids = append(ids, c.ID)
	}
	joined, err := l.svcCtx.CircleModel.MemberMap(ctx, uid, ids)
	if err != nil {
		return nil, fmt.Errorf("member map: %w", err)
	}
	out := make([]types.CircleItem, 0, len(rows))
	for _, c := range rows {
		out = append(out, toItem(c, joined[c.ID]))
	}
	return out, nil
}

func (l *Logic) Detail(ctx context.Context, uid, circleID int64) (*types.CircleDetailResp, error) {
	c, err := l.svcCtx.CircleModel.FindByID(ctx, circleID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "圈子不存在")
		}
		return nil, fmt.Errorf("circle find: %w", err)
	}
	joined := false
	if uid > 0 {
		if joined, err = l.svcCtx.CircleModel.IsMember(ctx, circleID, uid); err != nil {
			return nil, fmt.Errorf("is member: %w", err)
		}
	}
	return &types.CircleDetailResp{
		CircleItem:  toItem(c, joined),
		Cover:       c.Cover,
		Description: c.Description,
	}, nil
}

func (l *Logic) Join(ctx context.Context, uid, circleID int64) error {
	if _, err := l.svcCtx.CircleModel.FindByID(ctx, circleID); err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "圈子不存在")
		}
		return fmt.Errorf("circle find: %w", err)
	}
	if err := l.svcCtx.CircleModel.Join(ctx, circleID, uid); err != nil {
		return fmt.Errorf("circle join: %w", err)
	}
	return nil
}

func (l *Logic) Leave(ctx context.Context, uid, circleID int64) error {
	if err := l.svcCtx.CircleModel.Leave(ctx, circleID, uid); err != nil {
		return fmt.Errorf("circle leave: %w", err)
	}
	return nil
}

// requireAdmin 圈管理操作鉴权:圈主/管理员。
func (l *Logic) requireAdmin(ctx context.Context, circleID, uid int64) error {
	role, err := l.svcCtx.CircleModel.RoleOf(ctx, circleID, uid)
	if err != nil {
		return fmt.Errorf("circle role: %w", err)
	}
	if role < model.CircleRoleAdmin {
		return xerr.New(xerr.CodeForbidden, "需要圈主或管理员权限")
	}
	return nil
}

// SetTop 圈内置顶/取消(需求 3.4 圈子管理)。
func (l *Logic) SetTop(ctx context.Context, uid int64, req *types.CircleAdminPostReq) error {
	if err := l.requireAdmin(ctx, req.CircleID, uid); err != nil {
		return err
	}
	ok, err := l.svcCtx.PostModel.SetCircleTop(ctx, req.CircleID, req.PostID, req.On)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "帖子不存在或不属于本圈")
	}
	return nil
}

// SetEssence 圈内加精/取消。
func (l *Logic) SetEssence(ctx context.Context, uid int64, req *types.CircleAdminPostReq) error {
	if err := l.requireAdmin(ctx, req.CircleID, uid); err != nil {
		return err
	}
	ok, err := l.svcCtx.PostModel.SetEssence(ctx, req.CircleID, req.PostID, req.On)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "帖子不存在或不属于本圈")
	}
	return nil
}

// RemovePost 圈管理下架帖(与作者删除区分),并通知作者。
func (l *Logic) RemovePost(ctx context.Context, uid int64, req *types.CircleAdminPostReq) error {
	if err := l.requireAdmin(ctx, req.CircleID, uid); err != nil {
		return err
	}
	authorID, hit, err := l.svcCtx.PostModel.Takedown(ctx, req.CircleID, req.PostID)
	if err != nil {
		return err
	}
	if !hit {
		return xerr.New(xerr.CodeNotFound, "帖子不存在、不属于本圈或已下架")
	}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: authorID, Type: model.NotifyTypeSystem, ActorID: 0,
		TargetType: model.LikeTargetPost, TargetID: req.PostID,
		Content: "你的帖子因违反圈规被管理员下架,可修改后重新发布",
	}); err != nil {
		logx.WithContext(ctx).Errorf("takedown notification: %v", err)
	}
	return nil
}

// Mute 圈内禁言/解除(days=0 解除)。不可禁言圈主/管理员。
func (l *Logic) Mute(ctx context.Context, uid int64, req *types.CircleMuteReq) error {
	if err := l.requireAdmin(ctx, req.CircleID, uid); err != nil {
		return err
	}
	if req.Days < 0 || req.Days > 365 {
		return xerr.Param("禁言天数需为 0-365")
	}
	targetRole, err := l.svcCtx.CircleModel.RoleOf(ctx, req.CircleID, req.UserID)
	if err != nil {
		return fmt.Errorf("target role: %w", err)
	}
	if targetRole < 0 {
		return xerr.New(xerr.CodeNotFound, "对方不是本圈成员")
	}
	if targetRole >= model.CircleRoleAdmin {
		return xerr.New(xerr.CodeForbidden, "不能禁言圈主或管理员")
	}
	ok, err := l.svcCtx.CircleModel.MuteMember(ctx, req.CircleID, req.UserID, req.Days)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "对方不是本圈成员")
	}
	if req.Days > 0 {
		if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
			UserID: req.UserID, Type: model.NotifyTypeSystem, ActorID: 0,
			Content: fmt.Sprintf("你在圈子内被禁言 %d 天", req.Days),
		}); err != nil {
			logx.WithContext(ctx).Errorf("mute notification: %v", err)
		}
	}
	return nil
}

func toItem(c *model.Circle, joined bool) types.CircleItem {
	return types.CircleItem{
		ID:          c.ID,
		Name:        c.Name,
		Icon:        c.Icon,
		Intro:       c.Intro,
		MemberCount: c.MemberCount,
		PostCount:   c.PostCount,
		IsOfficial:  c.IsOfficial == 1,
		Pinned:      c.Pinned == 1,
		Joined:      joined,
	}
}
