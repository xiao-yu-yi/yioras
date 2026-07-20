// Package commentlogic 评论:发布(机审)/两级列表/评论点赞。
package commentlogic

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

const (
	maxCommentRunes = 1000
	maxMentions     = 10
)

// 评论状态(comment.status)
const (
	commentStatusPending   = 0
	commentStatusPublished = 1
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// resolveBiz 归一化评论对象:bizType 0/1=帖子(bizId 兼容 postId),2=软件。
func resolveBiz(req0 *types.CreateCommentReq, list *types.CommentListReq) (bizType, bizID int64, err error) {
	if req0 != nil {
		bizType, bizID = req0.BizType, req0.BizID
		if bizID == 0 {
			bizID = req0.PostID
		}
	} else {
		bizType, bizID = list.BizType, list.BizID
		if bizID == 0 {
			bizID = list.PostID
		}
	}
	if bizType == 0 {
		bizType = model.CommentBizPost
	}
	if bizType != model.CommentBizPost && bizType != model.CommentBizSoftware {
		return 0, 0, xerr.Param("评论对象类型不正确")
	}
	if bizID <= 0 {
		return 0, 0, xerr.Param("评论对象不能为空")
	}
	return bizType, bizID, nil
}

// checkTarget 评论目标可见性校验,返回被通知的对象作者。帖子评论受圈内禁言约束。
func (l *Logic) checkTarget(ctx context.Context, uid, bizType, bizID int64) (ownerUID int64, err error) {
	if bizType == model.CommentBizPost {
		post, err := l.findPublishedPost(ctx, bizID)
		if err != nil {
			return 0, err
		}
		until, err := l.svcCtx.CircleModel.MutedUntil(ctx, post.CircleID, uid)
		if err != nil {
			return 0, fmt.Errorf("muted check: %w", err)
		}
		if until.After(time.Now()) {
			return 0, xerr.New(xerr.CodeForbidden, "你在该圈内已被禁言至 "+until.Format("2006-01-02 15:04"))
		}
		return post.UserID, nil
	}
	s, err := l.svcCtx.SoftwareModel.FindByID(ctx, bizID)
	if err != nil {
		if model.IsNotFound(err) {
			return 0, xerr.New(xerr.CodeNotFound, "软件不存在")
		}
		return 0, fmt.Errorf("software find: %w", err)
	}
	if s.Status != model.SoftwareStatusOnline && s.UserID != uid {
		return 0, xerr.New(xerr.CodeNotFound, "软件不存在")
	}
	return s.UserID, nil
}

// Create 发评论/回复(帖子/软件详情页共用)。机审同发帖:拦截驳回、疑似转人审、打码直发。
func (l *Logic) Create(ctx context.Context, uid int64, req *types.CreateCommentReq) (*types.CreateCommentResp, error) {
	content := strings.TrimSpace(req.Content)
	if content == "" {
		return nil, xerr.Param("评论内容不能为空")
	}
	if utf8.RuneCountInString(content) > maxCommentRunes {
		return nil, xerr.Param("评论超出长度限制")
	}
	bizType, bizID, err := resolveBiz(req, nil)
	if err != nil {
		return nil, err
	}
	if err := postlogic.CheckGlobalMuted(ctx, l.svcCtx, uid); err != nil {
		return nil, err
	}
	ownerUID, err := l.checkTarget(ctx, uid, bizType, bizID)
	if err != nil {
		return nil, err
	}

	var rootID, parentID, replyUID int64
	if req.ParentID > 0 {
		parent, err := l.svcCtx.InteractModel.FindCommentByID(ctx, req.ParentID)
		if err != nil {
			if model.IsNotFound(err) {
				return nil, xerr.New(xerr.CodeNotFound, "回复的评论不存在")
			}
			return nil, fmt.Errorf("parent comment: %w", err)
		}
		if parent.BizType != bizType || parent.BizID != bizID || parent.Status != commentStatusPublished {
			return nil, xerr.New(xerr.CodeNotFound, "回复的评论不存在")
		}
		parentID, replyUID = parent.ID, parent.UserID
		if rootID = parent.RootID; rootID == 0 {
			rootID = parent.ID
		}
	}

	texts, level, hit, err := l.svcCtx.Filter.CheckAll(ctx, content)
	if err != nil {
		return nil, fmt.Errorf("sensitive check: %w", err)
	}
	if level == model.WordLevelBlock {
		return nil, xerr.New(xerr.CodeContentBlocked, "评论包含违禁词,请修改后重试")
	}
	status, tip := commentStatusPublished, "评论成功"
	if level == model.WordLevelReview {
		status, tip = commentStatusPending, "已提交审核,通过后展示"
	}

	id, err := l.svcCtx.InteractModel.CreateComment(ctx, &model.Comment{
		BizType:  bizType,
		BizID:    bizID,
		UserID:   uid,
		RootID:   rootID,
		ParentID: parentID,
		ReplyUID: replyUID,
		Content:  texts[0],
		Status:   int64(status),
	})
	if err != nil {
		return nil, fmt.Errorf("create comment: %w", err)
	}
	if status == commentStatusPending {
		if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizComment, id, model.MachineSuspect, hit); err != nil {
			logx.WithContext(ctx).Errorf("comment %d audit enqueue: %v", id, err)
		}
	}
	if status == commentStatusPublished {
		l.notifyComment(ctx, uid, bizType, bizID, ownerUID, replyUID, texts[0])
		// @通知:去重排自己,且不与"被回复"通知重复
		mentions := dedupeMentions(req.Mentions, uid, replyUID)
		if len(mentions) > maxMentions {
			mentions = mentions[:maxMentions]
		}
		for _, m := range mentions {
			l.notify(ctx, &model.Notification{
				UserID: m, Type: model.NotifyTypeComment, ActorID: uid,
				TargetType: model.LikeTargetPost, TargetID: bizID,
				Content: "在评论中@了你: " + preview(texts[0], 30),
			})
		}
		if err := l.svcCtx.TaskModel.IncrProgress(ctx, uid, "comment", time.Now()); err != nil {
			logx.WithContext(ctx).Errorf("task progress comment: %v", err)
		}
		if err := l.svcCtx.UserModel.AddExp(ctx, uid, 2); err != nil {
			logx.WithContext(ctx).Errorf("comment exp: %v", err)
		}
	}
	return &types.CreateCommentResp{CommentID: id, Status: status, Tip: tip}, nil
}

func dedupeMentions(raw []int64, self, replyUID int64) []int64 {
	out := make([]int64, 0, len(raw))
	seen := map[int64]bool{}
	for _, id := range raw {
		if id <= 0 || id == self || id == replyUID || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

// List 评论列表:RootID=0 拉一级评论,>0 拉某楼回复。帖子/软件详情页共用。
func (l *Logic) List(ctx context.Context, uid int64, req *types.CommentListReq) ([]types.CommentItem, error) {
	bizType, bizID, err := resolveBiz(nil, req)
	if err != nil {
		return nil, err
	}
	// 目标可见性与详情一致:未发布/未上架对象的评论仅作者可拉
	if bizType == model.CommentBizPost {
		post, err := l.svcCtx.PostModel.FindByID(ctx, bizID)
		if err != nil {
			if model.IsNotFound(err) {
				return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
			}
			return nil, fmt.Errorf("post find: %w", err)
		}
		if post.Status != model.PostStatusPublished && post.UserID != uid {
			return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
	} else {
		if _, err := l.checkTarget(ctx, uid, bizType, bizID); err != nil {
			return nil, err
		}
	}

	offset, limit := req.Offset()
	var rows []*model.Comment
	if req.RootID > 0 {
		// 楼层归属校验,防止用别的对象 ID 拉走这楼的回复
		root, err := l.svcCtx.InteractModel.FindCommentByID(ctx, req.RootID)
		if err != nil {
			if model.IsNotFound(err) {
				return nil, xerr.New(xerr.CodeNotFound, "评论不存在")
			}
			return nil, fmt.Errorf("root comment: %w", err)
		}
		if root.BizType != bizType || root.BizID != bizID {
			return nil, xerr.New(xerr.CodeNotFound, "评论不存在")
		}
		rows, err = l.svcCtx.InteractModel.ListReplies(ctx, req.RootID, offset, limit)
		if err != nil {
			return nil, fmt.Errorf("comment list: %w", err)
		}
		return l.decorate(ctx, uid, rows)
	}
	rows, err = l.svcCtx.InteractModel.ListRootComments(ctx, bizType, bizID, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("comment list: %w", err)
	}
	return l.decorate(ctx, uid, rows)
}

// Like 点赞评论,幂等;首次点赞通知评论作者。
func (l *Logic) Like(ctx context.Context, uid, commentID int64) error {
	c, err := l.findPublished(ctx, commentID)
	if err != nil {
		return err
	}
	added, err := l.svcCtx.InteractModel.Like(ctx, uid, model.LikeTargetComment, commentID)
	if err != nil {
		return fmt.Errorf("comment like: %w", err)
	}
	if added && c.UserID != uid {
		l.notify(ctx, &model.Notification{
			UserID: c.UserID, Type: model.NotifyTypeLike, ActorID: uid,
			TargetType: model.LikeTargetComment, TargetID: commentID,
			Content: "赞了你的评论 " + preview(c.Content, 20),
		})
	}
	return nil
}

func (l *Logic) Unlike(ctx context.Context, uid, commentID int64) error {
	if err := l.svcCtx.InteractModel.Unlike(ctx, uid, model.LikeTargetComment, commentID); err != nil {
		return fmt.Errorf("comment unlike: %w", err)
	}
	return nil
}

// notifyComment 回复通知被回复者,一级评论通知对象作者;自己评自己不通知。
func (l *Logic) notifyComment(ctx context.Context, uid, bizType, bizID, ownerUID, replyUID int64, content string) {
	target := ownerUID
	noun := "帖子"
	if bizType == model.CommentBizSoftware {
		noun = "软件"
	}
	text := "评论了你的" + noun + ": " + preview(content, 30)
	if replyUID > 0 {
		target = replyUID
		text = "回复了你的评论: " + preview(content, 30)
	}
	if target == uid {
		return
	}
	l.notify(ctx, &model.Notification{
		UserID: target, Type: model.NotifyTypeComment, ActorID: uid,
		TargetType: model.LikeTargetPost, TargetID: bizID,
		Content: text,
	})
}

func (l *Logic) notify(ctx context.Context, n *model.Notification) {
	if err := l.svcCtx.NotifyModel.Add(ctx, n); err != nil {
		logx.WithContext(ctx).Errorf("add notification: %v", err)
	}
}

func (l *Logic) findPublishedPost(ctx context.Context, postID int64) (*model.Post, error) {
	p, err := l.svcCtx.PostModel.FindByID(ctx, postID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
		return nil, fmt.Errorf("post find: %w", err)
	}
	if p.Status != model.PostStatusPublished {
		return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
	}
	return p, nil
}

func (l *Logic) findPublished(ctx context.Context, commentID int64) (*model.Comment, error) {
	c, err := l.svcCtx.InteractModel.FindCommentByID(ctx, commentID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "评论不存在")
		}
		return nil, fmt.Errorf("comment find: %w", err)
	}
	if c.Status != commentStatusPublished {
		return nil, xerr.New(xerr.CodeNotFound, "评论不存在")
	}
	return c, nil
}

// decorate 批量补齐评论者/被回复者昵称与点赞状态。
func (l *Logic) decorate(ctx context.Context, uid int64, rows []*model.Comment) ([]types.CommentItem, error) {
	out := make([]types.CommentItem, 0, len(rows))
	if len(rows) == 0 {
		return out, nil
	}
	ids := make([]int64, 0, len(rows))
	uids := make([]int64, 0, len(rows)*2)
	for _, c := range rows {
		ids = append(ids, c.ID)
		uids = append(uids, c.UserID)
		if c.ReplyUID > 0 {
			uids = append(uids, c.ReplyUID)
		}
	}
	briefs, err := l.svcCtx.UserModel.FindBriefs(ctx, uids)
	if err != nil {
		return nil, fmt.Errorf("comment briefs: %w", err)
	}
	liked, err := l.svcCtx.InteractModel.LikedSet(ctx, uid, model.LikeTargetComment, ids)
	if err != nil {
		return nil, fmt.Errorf("comment liked set: %w", err)
	}
	for _, c := range rows {
		item := types.CommentItem{
			ID:         c.ID,
			Author:     postlogic.ToUserBrief(c.UserID, briefs[c.UserID]),
			Content:    c.Content,
			LikeCount:  c.LikeCount,
			ReplyCount: c.ReplyCount,
			Liked:      liked[c.ID],
			CreatedAt:  c.CreatedAt.UnixMilli(),
		}
		// 楼中楼且回复对象不是楼主时展示"回复@xx"
		if c.ReplyUID > 0 && c.ParentID != c.RootID {
			if b := briefs[c.ReplyUID]; b != nil {
				item.ReplyTo = b.Nickname
			}
		}
		out = append(out, item)
	}
	return out, nil
}

func preview(s string, n int) string {
	r := []rune(s)
	if len(r) > n {
		return string(r[:n]) + "…"
	}
	return s
}
