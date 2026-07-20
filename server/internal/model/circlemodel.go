package model

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	Circle struct {
		ID          int64     `db:"id"`
		Name        string    `db:"name"`
		Icon        string    `db:"icon"`
		Cover       string    `db:"cover"`
		Intro       string    `db:"intro"`
		Description string    `db:"description"`
		MemberCount int64     `db:"member_count"`
		PostCount   int64     `db:"post_count"`
		HotScore    int64     `db:"hot_score"`
		IsOfficial  int64     `db:"is_official"`
		Pinned      int64     `db:"pinned"`
		Sort        int64     `db:"sort"`
		Status      int64     `db:"status"`
		CreatedAt   time.Time `db:"created_at"`
		UpdatedAt   time.Time `db:"updated_at"`
	}

	CircleModel struct{ conn sqlx.SqlConn }
)

const circleCols = "id, name, icon, cover, intro, description, member_count, post_count, hot_score, is_official, pinned, sort, status, created_at, updated_at"

func NewCircleModel(conn sqlx.SqlConn) *CircleModel { return &CircleModel{conn: conn} }

// List 发现页列表。sort: hot=置顶+热度, new=最新创建。
func (m *CircleModel) List(ctx context.Context, sort string, offset, limit int) ([]*Circle, error) {
	order := "pinned DESC, hot_score DESC, sort ASC, id ASC"
	if sort == "new" {
		order = "id DESC"
	}
	var rows []*Circle
	q := fmt.Sprintf("SELECT %s FROM `circle` WHERE status = 1 ORDER BY %s LIMIT ?, ?", circleCols, order)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

func (m *CircleModel) FindByID(ctx context.Context, id int64) (*Circle, error) {
	var c Circle
	q := fmt.Sprintf("SELECT %s FROM `circle` WHERE id = ? AND status = 1 LIMIT 1", circleCols)
	if err := m.conn.QueryRowCtx(ctx, &c, q, id); err != nil {
		return nil, err
	}
	return &c, nil
}

func (m *CircleModel) IsMember(ctx context.Context, circleID, uid int64) (bool, error) {
	var n int
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT COUNT(1) FROM `circle_member` WHERE circle_id = ? AND user_id = ?", circleID, uid)
	return n > 0, err
}

// MemberMap 批量查询 uid 加入的圈子,返回 circleID 集合。
func (m *CircleModel) MemberMap(ctx context.Context, uid int64, circleIDs []int64) (map[int64]bool, error) {
	out := make(map[int64]bool, len(circleIDs))
	if uid <= 0 || len(circleIDs) == 0 {
		return out, nil
	}
	q, args := inQuery("SELECT circle_id FROM `circle_member` WHERE user_id = ? AND circle_id IN (%s)", circleIDs, uid)
	var ids []int64
	if err := m.conn.QueryRowsCtx(ctx, &ids, q, args...); err != nil {
		return nil, err
	}
	for _, id := range ids {
		out[id] = true
	}
	return out, nil
}

// 圈成员角色(circle_member.role)
const (
	CircleRoleMember = 0
	CircleRoleAdmin  = 1
	CircleRoleOwner  = 2
)

// RoleOf 用户在圈内的角色;非成员返回 -1。
func (m *CircleModel) RoleOf(ctx context.Context, circleID, uid int64) (int64, error) {
	var role int64
	err := m.conn.QueryRowCtx(ctx, &role,
		"SELECT role FROM `circle_member` WHERE circle_id = ? AND user_id = ? LIMIT 1", circleID, uid)
	if err != nil {
		if IsNotFound(err) {
			return -1, nil
		}
		return -1, err
	}
	return role, nil
}

// MutedUntil 圈内禁言截止时间;未禁言/非成员返回零值。
// NULL 列经结构体字段扫描(go-zero sqlx 不支持裸 sql.NullTime 目标)。
func (m *CircleModel) MutedUntil(ctx context.Context, circleID, uid int64) (time.Time, error) {
	var row struct {
		MutedUntil sql.NullTime `db:"muted_until"`
	}
	err := m.conn.QueryRowCtx(ctx, &row,
		"SELECT muted_until FROM `circle_member` WHERE circle_id = ? AND user_id = ? LIMIT 1", circleID, uid)
	if err != nil {
		if IsNotFound(err) {
			return time.Time{}, nil
		}
		return time.Time{}, err
	}
	if !row.MutedUntil.Valid {
		return time.Time{}, nil
	}
	return row.MutedUntil.Time, nil
}

// MuteMember 圈内禁言:days>0 禁言 N 天,days=0 解除。目标须为圈成员。
func (m *CircleModel) MuteMember(ctx context.Context, circleID, uid int64, days int) (bool, error) {
	var q string
	args := []any{circleID, uid}
	if days > 0 {
		q = "UPDATE `circle_member` SET muted_until = DATE_ADD(NOW(3), INTERVAL ? DAY) WHERE circle_id = ? AND user_id = ?"
		args = []any{days, circleID, uid}
	} else {
		q = "UPDATE `circle_member` SET muted_until = NULL WHERE circle_id = ? AND user_id = ?"
	}
	r, err := m.conn.ExecCtx(ctx, q, args...)
	if err != nil {
		return false, fmt.Errorf("mute member: %w", err)
	}
	n, _ := r.RowsAffected()
	// 解除禁言时 muted_until 本为 NULL 会 affected=0,单独确认成员存在
	if n == 0 {
		var cnt int
		if err := m.conn.QueryRowCtx(ctx, &cnt,
			"SELECT COUNT(1) FROM `circle_member` WHERE circle_id = ? AND user_id = ?", circleID, uid); err != nil {
			return false, err
		}
		return cnt > 0, nil
	}
	return true, nil
}

// Join 幂等加入;重复加入不重复计数。
func (m *CircleModel) Join(ctx context.Context, circleID, uid int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `circle_member` (circle_id, user_id) VALUES (?, ?)", circleID, uid)
		if err != nil {
			return fmt.Errorf("join insert: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 1 {
			if _, err = s.ExecCtx(ctx,
				"UPDATE `circle` SET member_count = member_count + 1 WHERE id = ?", circleID); err != nil {
				return fmt.Errorf("join count: %w", err)
			}
		}
		return nil
	})
}

func (m *CircleModel) Leave(ctx context.Context, circleID, uid int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"DELETE FROM `circle_member` WHERE circle_id = ? AND user_id = ?", circleID, uid)
		if err != nil {
			return fmt.Errorf("leave delete: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 1 {
			if _, err = s.ExecCtx(ctx,
				"UPDATE `circle` SET member_count = GREATEST(member_count - 1, 0) WHERE id = ?", circleID); err != nil {
				return fmt.Errorf("leave count: %w", err)
			}
		}
		return nil
	})
}

// FindNames 批量取圈子名(帖子卡片展示用),返回 circleID -> name。
func (m *CircleModel) FindNames(ctx context.Context, ids []int64) (map[int64]string, error) {
	out := make(map[int64]string, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	type row struct {
		ID   int64  `db:"id"`
		Name string `db:"name"`
	}
	q, args := inQuery("SELECT id, name FROM `circle` WHERE id IN (%s)", ids)
	var rows []row
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.ID] = r.Name
	}
	return out, nil
}

// inQuery 构造 IN (?,?,...) 查询。ids 仅来自服务端整型,无注入面。
func inQuery(format string, ids []int64, head ...any) (string, []any) {
	ph := ""
	args := append([]any{}, head...)
	for i, id := range ids {
		if i > 0 {
			ph += ","
		}
		ph += "?"
		args = append(args, id)
	}
	return fmt.Sprintf(format, ph), args
}
