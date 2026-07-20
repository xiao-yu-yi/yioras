package model

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 草稿类型(draft.kind)
const (
	DraftKindPost     = 1
	DraftKindSoftware = 2
)

type (
	Draft struct {
		ID        int64     `db:"id"`
		UserID    int64     `db:"user_id"`
		Kind      int64     `db:"kind"`
		Payload   string    `db:"payload"`
		UpdatedAt time.Time `db:"updated_at"`
	}

	DraftModel struct{ conn sqlx.SqlConn }
)

func NewDraftModel(conn sqlx.SqlConn) *DraftModel { return &DraftModel{conn: conn} }

// Save 新建(id=0)或覆盖保存(id>0,归属校验)。返回草稿 ID。
func (m *DraftModel) Save(ctx context.Context, uid, id, kind int64, payload string) (int64, error) {
	if id > 0 {
		r, err := m.conn.ExecCtx(ctx,
			"UPDATE `draft` SET payload = ?, kind = ? WHERE id = ? AND user_id = ?", payload, kind, id, uid)
		if err != nil {
			return 0, fmt.Errorf("update draft: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 0 {
			// 可能内容未变更(affected=0),存在性单独确认
			var cnt int
			if err := m.conn.QueryRowCtx(ctx, &cnt,
				"SELECT COUNT(1) FROM `draft` WHERE id = ? AND user_id = ?", id, uid); err != nil {
				return 0, fmt.Errorf("check draft: %w", err)
			}
			if cnt == 0 {
				return 0, sqlx.ErrNotFound
			}
		}
		return id, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `draft` (user_id, kind, payload) VALUES (?, ?, ?)", uid, kind, payload)
	if err != nil {
		return 0, fmt.Errorf("insert draft: %w", err)
	}
	newID, err := r.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("draft id: %w", err)
	}
	return newID, nil
}

// Count 用户草稿数(上限控制)。
func (m *DraftModel) Count(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `draft` WHERE user_id = ?", uid)
	return n, err
}

// List 我的草稿(按更新时间倒序)。kind=0 不筛。
func (m *DraftModel) List(ctx context.Context, uid, kind int64, offset, limit int) ([]*Draft, error) {
	cond, args := "user_id = ?", []any{uid}
	if kind > 0 {
		cond += " AND kind = ?"
		args = append(args, kind)
	}
	args = append(args, offset, limit)
	var rows []*Draft
	q := fmt.Sprintf("SELECT id, user_id, kind, payload, updated_at FROM `draft` WHERE %s ORDER BY updated_at DESC LIMIT ?, ?", cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

// Delete 删除草稿(归属校验)。
func (m *DraftModel) Delete(ctx context.Context, uid, id int64) error {
	if _, err := m.conn.ExecCtx(ctx,
		"DELETE FROM `draft` WHERE id = ? AND user_id = ?", id, uid); err != nil {
		return fmt.Errorf("delete draft: %w", err)
	}
	return nil
}
