// Package draftlogic 发布器草稿箱(动态/软件双通道)。payload 为客户端表单快照,发布时才做业务校验。
package draftlogic

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

const (
	maxDraftsPerUser = 10
	maxPayloadBytes  = 64 << 10
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Save 新建/覆盖保存草稿。
func (l *Logic) Save(ctx context.Context, uid int64, req *types.SaveDraftReq) (*types.SaveDraftResp, error) {
	if len(req.Payload) > maxPayloadBytes {
		return nil, xerr.Param("草稿内容过大")
	}
	if !json.Valid([]byte(req.Payload)) {
		return nil, xerr.Param("草稿格式不正确")
	}
	if req.ID == 0 {
		n, err := l.svcCtx.DraftModel.Count(ctx, uid)
		if err != nil {
			return nil, fmt.Errorf("draft count: %w", err)
		}
		if n >= maxDraftsPerUser {
			return nil, xerr.New(xerr.CodeTooFrequent, fmt.Sprintf("草稿箱最多保存 %d 条,请先清理", maxDraftsPerUser))
		}
	}
	id, err := l.svcCtx.DraftModel.Save(ctx, uid, req.ID, req.Kind, req.Payload)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "草稿不存在")
		}
		return nil, fmt.Errorf("save draft: %w", err)
	}
	return &types.SaveDraftResp{ID: id}, nil
}

// List 我的草稿。
func (l *Logic) List(ctx context.Context, uid int64, req *types.DraftListReq) ([]types.DraftItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.DraftModel.List(ctx, uid, req.Kind, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("draft list: %w", err)
	}
	out := make([]types.DraftItem, 0, len(rows))
	for _, d := range rows {
		out = append(out, types.DraftItem{
			ID: d.ID, Kind: d.Kind, Payload: d.Payload, UpdatedAt: d.UpdatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// Delete 删除草稿。
func (l *Logic) Delete(ctx context.Context, uid, id int64) error {
	return l.svcCtx.DraftModel.Delete(ctx, uid, id)
}

// CleanAfterPublish 发布成功后清理来源草稿,失败只记日志不影响发布结果。
func CleanAfterPublish(ctx context.Context, svcCtx *svc.ServiceContext, uid, draftID int64) {
	if draftID <= 0 {
		return
	}
	if err := svcCtx.DraftModel.Delete(ctx, uid, draftID); err != nil {
		logx.WithContext(ctx).Errorf("clean draft %d: %v", draftID, err)
	}
}
