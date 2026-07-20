// Package reportlogic 举报:帖子/评论/用户/私信四类对象,分类+证据图,后台处置闭环的入口。
package reportlogic

import (
	"context"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

const (
	maxReasonRunes = 500
	maxImages      = 9
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Create 提交举报。对象存在性/归属校验后落 report 表,同人同对象待处理期内防重复。
func (l *Logic) Create(ctx context.Context, uid int64, req *types.CreateReportReq) error {
	reason := strings.TrimSpace(req.Reason)
	if utf8.RuneCountInString(reason) > maxReasonRunes {
		return xerr.Param("补充说明超出长度限制")
	}
	if len(req.Images) > maxImages {
		return xerr.Param(fmt.Sprintf("证据图最多 %d 张", maxImages))
	}
	for _, u := range req.Images {
		if !strings.HasPrefix(u, "https://") && !strings.HasPrefix(u, "http://") {
			return xerr.Param("证据图链接格式不正确")
		}
	}
	if err := l.checkTarget(ctx, uid, req.TargetType, req.TargetID); err != nil {
		return err
	}
	dup, err := l.svcCtx.ReportModel.HasPending(ctx, uid, req.TargetType, req.TargetID)
	if err != nil {
		return fmt.Errorf("report dedup: %w", err)
	}
	if dup {
		return xerr.New(xerr.CodeTooFrequent, "你已举报过,平台正在处理")
	}
	if err := l.svcCtx.ReportModel.Create(ctx, uid, req.TargetType, req.TargetID, req.Category, reason, req.Images); err != nil {
		return err
	}
	return nil
}

// checkTarget 被举报对象必须真实存在;私信只能举报自己会话里的消息。
func (l *Logic) checkTarget(ctx context.Context, uid int64, targetType int, targetID int64) error {
	switch targetType {
	case model.ReportTargetPost:
		p, err := l.svcCtx.PostModel.FindByID(ctx, targetID)
		if err != nil {
			if model.IsNotFound(err) {
				return xerr.New(xerr.CodeNotFound, "帖子不存在")
			}
			return fmt.Errorf("report post find: %w", err)
		}
		if p.Status == model.PostStatusDeleted {
			return xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
	case model.ReportTargetComment:
		if _, err := l.svcCtx.InteractModel.FindCommentByID(ctx, targetID); err != nil {
			if model.IsNotFound(err) {
				return xerr.New(xerr.CodeNotFound, "评论不存在")
			}
			return fmt.Errorf("report comment find: %w", err)
		}
	case model.ReportTargetUser:
		if targetID == uid {
			return xerr.Param("不能举报自己")
		}
		if _, err := l.svcCtx.UserModel.FindByID(ctx, targetID); err != nil {
			if model.IsNotFound(err) {
				return xerr.New(xerr.CodeNotFound, "用户不存在")
			}
			return fmt.Errorf("report user find: %w", err)
		}
	case model.ReportTargetSoftware:
		if _, err := l.svcCtx.SoftwareModel.FindByID(ctx, targetID); err != nil {
			if model.IsNotFound(err) {
				return xerr.New(xerr.CodeNotFound, "软件不存在")
			}
			return fmt.Errorf("report software find: %w", err)
		}
	case model.ReportTargetMessage:
		msg, err := l.svcCtx.IMModel.FindMessage(ctx, targetID)
		if err != nil {
			if model.IsNotFound(err) {
				return xerr.New(xerr.CodeNotFound, "消息不存在")
			}
			return fmt.Errorf("report message find: %w", err)
		}
		if msg.SenderID == uid {
			return xerr.Param("不能举报自己发送的消息")
		}
		conv, err := l.svcCtx.IMModel.FindConversation(ctx, msg.ConversationID)
		if err != nil {
			return fmt.Errorf("report conversation find: %w", err)
		}
		if conv.UserMin != uid && conv.UserMax != uid {
			return xerr.New(xerr.CodeForbidden, "只能举报自己会话中的消息")
		}
	}
	return nil
}
