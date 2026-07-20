package model

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 共创状态(post_cocreator.status)
const (
	CocreatorPending  = 0
	CocreatorAccepted = 1
	CocreatorRejected = 2
)

type (
	Cocreator struct {
		ID        int64     `db:"id"`
		PostID    int64     `db:"post_id"`
		UserID    int64     `db:"user_id"`
		Status    int64     `db:"status"`
		CreatedAt time.Time `db:"created_at"`
	}

	CocreatorModel struct{ conn sqlx.SqlConn }
)

func NewCocreatorModel(conn sqlx.SqlConn) *CocreatorModel { return &CocreatorModel{conn: conn} }

// InviteIn 事务内写共创邀请(发帖事务复用),重复邀请幂等。
func InviteCocreatorsIn(ctx context.Context, s sqlx.Session, postID int64, uids []int64) error {
	for _, uid := range uids {
		if _, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `post_cocreator` (post_id, user_id) VALUES (?, ?)", postID, uid); err != nil {
			return fmt.Errorf("invite cocreator %d: %w", uid, err)
		}
	}
	return nil
}

// Confirm 被邀请者确认/拒绝,仅待确认态可流转(CAS 防重复)。
func (m *CocreatorModel) Confirm(ctx context.Context, postID, uid int64, accept bool) (bool, error) {
	to := CocreatorAccepted
	if !accept {
		to = CocreatorRejected
	}
	r, err := m.conn.ExecCtx(ctx,
		"UPDATE `post_cocreator` SET status = ? WHERE post_id = ? AND user_id = ? AND status = ?",
		to, postID, uid, CocreatorPending)
	if err != nil {
		return false, fmt.Errorf("confirm cocreator: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// AcceptedOfPosts 批量取已确认共创者,返回 postID -> uids。
func (m *CocreatorModel) AcceptedOfPosts(ctx context.Context, postIDs []int64) (map[int64][]int64, error) {
	out := make(map[int64][]int64, len(postIDs))
	if len(postIDs) == 0 {
		return out, nil
	}
	type row struct {
		PostID int64 `db:"post_id"`
		UserID int64 `db:"user_id"`
	}
	q, args := inQuery(
		fmt.Sprintf("SELECT post_id, user_id FROM `post_cocreator` WHERE status = %d AND post_id IN (%%s) ORDER BY id", CocreatorAccepted),
		postIDs)
	var rows []row
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.PostID] = append(out[r.PostID], r.UserID)
	}
	return out, nil
}
