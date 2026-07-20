package model

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 点赞对象类型
const (
	LikeTargetPost    = 1
	LikeTargetComment = 2
)

// 评论所属业务对象(comment.biz_type)
const (
	CommentBizPost     = 1
	CommentBizSoftware = 2
)

type (
	Comment struct {
		ID         int64     `db:"id"`
		BizType    int64     `db:"biz_type"` // 1帖子 2软件
		BizID      int64     `db:"biz_id"`
		UserID     int64     `db:"user_id"`
		RootID     int64     `db:"root_id"`
		ParentID   int64     `db:"parent_id"`
		ReplyUID   int64     `db:"reply_uid"`
		Content    string    `db:"content"`
		LikeCount  int64     `db:"like_count"`
		ReplyCount int64     `db:"reply_count"`
		Status     int64     `db:"status"`
		CreatedAt  time.Time `db:"created_at"`
	}

	InteractModel struct{ conn sqlx.SqlConn }
)

const commentCols = "id, biz_type, biz_id, user_id, root_id, parent_id, reply_uid, content, like_count, reply_count, status, created_at"

func NewInteractModel(conn sqlx.SqlConn) *InteractModel { return &InteractModel{conn: conn} }

// Like 幂等点赞。返回 true=本次新增(需发通知),false=已赞过。
func (m *InteractModel) Like(ctx context.Context, uid int64, targetType int, targetID int64) (bool, error) {
	var added bool
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `like_record` (user_id, target_type, target_id) VALUES (?, ?, ?)",
			uid, targetType, targetID)
		if err != nil {
			return fmt.Errorf("like insert: %w", err)
		}
		n, _ := r.RowsAffected()
		added = n == 1
		if !added {
			return nil
		}
		return m.bumpLikeCount(ctx, s, targetType, targetID, 1)
	})
	return added, err
}

func (m *InteractModel) Unlike(ctx context.Context, uid int64, targetType int, targetID int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"DELETE FROM `like_record` WHERE user_id = ? AND target_type = ? AND target_id = ?",
			uid, targetType, targetID)
		if err != nil {
			return fmt.Errorf("unlike delete: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 1 {
			return m.bumpLikeCount(ctx, s, targetType, targetID, -1)
		}
		return nil
	})
}

func (m *InteractModel) bumpLikeCount(ctx context.Context, s sqlx.Session, targetType int, targetID, delta int64) error {
	table := "post"
	if targetType == LikeTargetComment {
		table = "comment"
	}
	// GREATEST 防止并发下减到负数
	q := fmt.Sprintf("UPDATE `%s` SET like_count = GREATEST(like_count + ?, 0) WHERE id = ?", table)
	if _, err := s.ExecCtx(ctx, q, delta, targetID); err != nil {
		return fmt.Errorf("bump like count: %w", err)
	}
	return nil
}

// LikedSet 批量查询 uid 对一组对象的点赞状态。
func (m *InteractModel) LikedSet(ctx context.Context, uid int64, targetType int, ids []int64) (map[int64]bool, error) {
	out := make(map[int64]bool, len(ids))
	if uid <= 0 || len(ids) == 0 {
		return out, nil
	}
	q, args := inQuery("SELECT target_id FROM `like_record` WHERE user_id = ? AND target_type = ? AND target_id IN (%s)",
		ids, uid, targetType)
	var hit []int64
	if err := m.conn.QueryRowsCtx(ctx, &hit, q, args...); err != nil {
		return nil, err
	}
	for _, id := range hit {
		out[id] = true
	}
	return out, nil
}

// Favorite 幂等收藏。返回 true=本次新增。
func (m *InteractModel) Favorite(ctx context.Context, uid, postID int64) (bool, error) {
	var added bool
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `favorite` (user_id, post_id) VALUES (?, ?)", uid, postID)
		if err != nil {
			return fmt.Errorf("favorite insert: %w", err)
		}
		n, _ := r.RowsAffected()
		added = n == 1
		if added {
			if _, err = s.ExecCtx(ctx,
				"UPDATE `post` SET favorite_count = favorite_count + 1 WHERE id = ?", postID); err != nil {
				return fmt.Errorf("favorite count: %w", err)
			}
		}
		return nil
	})
	return added, err
}

func (m *InteractModel) Unfavorite(ctx context.Context, uid, postID int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"DELETE FROM `favorite` WHERE user_id = ? AND post_id = ?", uid, postID)
		if err != nil {
			return fmt.Errorf("unfavorite delete: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 1 {
			if _, err = s.ExecCtx(ctx,
				"UPDATE `post` SET favorite_count = GREATEST(favorite_count - 1, 0) WHERE id = ?", postID); err != nil {
				return fmt.Errorf("unfavorite count: %w", err)
			}
		}
		return nil
	})
}

// FavoritedSet 批量查询 uid 对一组帖子的收藏状态。
func (m *InteractModel) FavoritedSet(ctx context.Context, uid int64, postIDs []int64) (map[int64]bool, error) {
	out := make(map[int64]bool, len(postIDs))
	if uid <= 0 || len(postIDs) == 0 {
		return out, nil
	}
	q, args := inQuery("SELECT post_id FROM `favorite` WHERE user_id = ? AND post_id IN (%s)", postIDs, uid)
	var hit []int64
	if err := m.conn.QueryRowsCtx(ctx, &hit, q, args...); err != nil {
		return nil, err
	}
	for _, id := range hit {
		out[id] = true
	}
	return out, nil
}

// CreateComment 发评论:落库+所属对象计数+一级评论回复数,同事务。
func (m *InteractModel) CreateComment(ctx context.Context, c *Comment) (int64, error) {
	var id int64
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT INTO `comment` (biz_type, biz_id, user_id, root_id, parent_id, reply_uid, content, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
			c.BizType, c.BizID, c.UserID, c.RootID, c.ParentID, c.ReplyUID, c.Content, c.Status)
		if err != nil {
			return fmt.Errorf("insert comment: %w", err)
		}
		if id, err = r.LastInsertId(); err != nil {
			return fmt.Errorf("comment id: %w", err)
		}
		// 计数只统计已发布评论;转人审的评论待后台通过时再补计数(M2 后台流程)
		if c.Status == 1 {
			table := "post"
			if c.BizType == CommentBizSoftware {
				table = "software"
			}
			if _, err = s.ExecCtx(ctx,
				fmt.Sprintf("UPDATE `%s` SET comment_count = comment_count + 1 WHERE id = ?", table), c.BizID); err != nil {
				return fmt.Errorf("%s comment count: %w", table, err)
			}
			if c.RootID > 0 {
				if _, err = s.ExecCtx(ctx,
					"UPDATE `comment` SET reply_count = reply_count + 1 WHERE id = ?", c.RootID); err != nil {
					return fmt.Errorf("root reply count: %w", err)
				}
			}
		}
		return nil
	})
	return id, err
}

func (m *InteractModel) FindCommentByID(ctx context.Context, id int64) (*Comment, error) {
	var c Comment
	q := fmt.Sprintf("SELECT %s FROM `comment` WHERE id = ? LIMIT 1", commentCols)
	if err := m.conn.QueryRowCtx(ctx, &c, q, id); err != nil {
		return nil, err
	}
	return &c, nil
}

// ListRootComments 一级评论列表(时间正序,楼层语义)。
func (m *InteractModel) ListRootComments(ctx context.Context, bizType, bizID int64, offset, limit int) ([]*Comment, error) {
	var rows []*Comment
	q := fmt.Sprintf("SELECT %s FROM `comment` WHERE biz_type = ? AND biz_id = ? AND root_id = 0 AND status = 1 ORDER BY id ASC LIMIT ?, ?", commentCols)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, bizType, bizID, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// ListReplies 某一级评论下的回复(时间正序)。
func (m *InteractModel) ListReplies(ctx context.Context, rootID int64, offset, limit int) ([]*Comment, error) {
	var rows []*Comment
	q := fmt.Sprintf("SELECT %s FROM `comment` WHERE root_id = ? AND status = 1 ORDER BY id ASC LIMIT ?, ?", commentCols)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, rootID, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}
