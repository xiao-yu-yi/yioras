package model

import (
	"context"
	"fmt"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// RelationModel 关注与黑名单。
type RelationModel struct{ conn sqlx.SqlConn }

func NewRelationModel(conn sqlx.SqlConn) *RelationModel { return &RelationModel{conn: conn} }

// Follow 幂等关注。返回 true=本次新增(需发通知)。
func (m *RelationModel) Follow(ctx context.Context, uid, target int64) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"INSERT IGNORE INTO `follow` (user_id, target_uid) VALUES (?, ?)", uid, target)
	if err != nil {
		return false, fmt.Errorf("follow insert: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

func (m *RelationModel) Unfollow(ctx context.Context, uid, target int64) error {
	if _, err := m.conn.ExecCtx(ctx,
		"DELETE FROM `follow` WHERE user_id = ? AND target_uid = ?", uid, target); err != nil {
		return fmt.Errorf("unfollow delete: %w", err)
	}
	return nil
}

func (m *RelationModel) IsFollowing(ctx context.Context, uid, target int64) (bool, error) {
	var n int
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT COUNT(1) FROM `follow` WHERE user_id = ? AND target_uid = ?", uid, target)
	return n > 0, err
}

// FollowedSet 批量查询 viewer 对一组用户的关注状态。
func (m *RelationModel) FollowedSet(ctx context.Context, viewer int64, ids []int64) (map[int64]bool, error) {
	out := make(map[int64]bool, len(ids))
	if viewer <= 0 || len(ids) == 0 {
		return out, nil
	}
	q, args := inQuery("SELECT target_uid FROM `follow` WHERE user_id = ? AND target_uid IN (%s)", ids, viewer)
	var hit []int64
	if err := m.conn.QueryRowsCtx(ctx, &hit, q, args...); err != nil {
		return nil, err
	}
	for _, id := range hit {
		out[id] = true
	}
	return out, nil
}

func (m *RelationModel) CountFollowing(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `follow` WHERE user_id = ?", uid)
	return n, err
}

func (m *RelationModel) CountFans(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `follow` WHERE target_uid = ?", uid)
	return n, err
}

// ListFollowing 我关注的人(按关注时间倒序),返回 target_uid。
func (m *RelationModel) ListFollowing(ctx context.Context, uid int64, offset, limit int) ([]int64, error) {
	var ids []int64
	err := m.conn.QueryRowsCtx(ctx, &ids,
		"SELECT target_uid FROM `follow` WHERE user_id = ? ORDER BY id DESC LIMIT ?, ?", uid, offset, limit)
	return ids, err
}

// ListFans 关注我的人(按时间倒序),返回 user_id。
func (m *RelationModel) ListFans(ctx context.Context, uid int64, offset, limit int) ([]int64, error) {
	var ids []int64
	err := m.conn.QueryRowsCtx(ctx, &ids,
		"SELECT user_id FROM `follow` WHERE target_uid = ? ORDER BY id DESC LIMIT ?, ?", uid, offset, limit)
	return ids, err
}

// Block 拉黑:写黑名单并解除双向关注(拉黑后不应保留互关,否则绕过私信频控)。
func (m *RelationModel) Block(ctx context.Context, uid, target int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `black_list` (user_id, target_uid) VALUES (?, ?)", uid, target); err != nil {
			return fmt.Errorf("block insert: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"DELETE FROM `follow` WHERE (user_id = ? AND target_uid = ?) OR (user_id = ? AND target_uid = ?)",
			uid, target, target, uid); err != nil {
			return fmt.Errorf("block unfollow: %w", err)
		}
		return nil
	})
}

func (m *RelationModel) Unblock(ctx context.Context, uid, target int64) error {
	if _, err := m.conn.ExecCtx(ctx,
		"DELETE FROM `black_list` WHERE user_id = ? AND target_uid = ?", uid, target); err != nil {
		return fmt.Errorf("unblock delete: %w", err)
	}
	return nil
}
