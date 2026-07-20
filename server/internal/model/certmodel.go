package model

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// ErrCertDuplicated 已有待审或已通过的同类认证。
var ErrCertDuplicated = errors.New("certification duplicated")

// 认证状态(certification.status)
const (
	CertStatusPending  = 0
	CertStatusApproved = 1
	CertStatusRejected = 2
)

type (
	Certification struct {
		ID        int64     `db:"id"`
		UserID    int64     `db:"user_id"`
		Kind      int64     `db:"kind"` // 1达人 2开发者
		Material  string    `db:"material"`
		Status    int64     `db:"status"`
		Reason    string    `db:"reason"`
		CreatedAt time.Time `db:"created_at"`
		UpdatedAt time.Time `db:"updated_at"`
	}

	CertModel struct{ conn sqlx.SqlConn }
)

func NewCertModel(conn sqlx.SqlConn) *CertModel { return &CertModel{conn: conn} }

// Submit 提交认证:同类无记录则新建;已驳回可重提(重置待审);待审/已通过拒绝重复。
func (m *CertModel) Submit(ctx context.Context, uid, kind int64, material string) error {
	var cur Certification
	err := m.conn.QueryRowCtx(ctx, &cur,
		"SELECT id, user_id, kind, material, status, reason, created_at, updated_at FROM `certification` WHERE user_id = ? AND kind = ? LIMIT 1",
		uid, kind)
	switch {
	case err == nil:
		if cur.Status != CertStatusRejected {
			return ErrCertDuplicated
		}
		if _, err := m.conn.ExecCtx(ctx,
			"UPDATE `certification` SET material = ?, status = ?, reason = '' WHERE id = ?",
			material, CertStatusPending, cur.ID); err != nil {
			return fmt.Errorf("resubmit cert: %w", err)
		}
		return nil
	case IsNotFound(err):
		if _, err := m.conn.ExecCtx(ctx,
			"INSERT INTO `certification` (user_id, kind, material) VALUES (?, ?, ?)", uid, kind, material); err != nil {
			if IsDupKey(err) { // 并发重复提交
				return ErrCertDuplicated
			}
			return fmt.Errorf("insert cert: %w", err)
		}
		return nil
	default:
		return fmt.Errorf("find cert: %w", err)
	}
}

// Mine 我的认证记录。
func (m *CertModel) Mine(ctx context.Context, uid int64) ([]*Certification, error) {
	var rows []*Certification
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, user_id, kind, material, status, reason, created_at, updated_at FROM `certification` WHERE user_id = ? ORDER BY kind", uid)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// ApprovedKinds 已通过的认证类型(主页徽章展示)。
func (m *CertModel) ApprovedKinds(ctx context.Context, uid int64) ([]int64, error) {
	var kinds []int64
	err := m.conn.QueryRowsCtx(ctx, &kinds,
		fmt.Sprintf("SELECT kind FROM `certification` WHERE user_id = ? AND status = %d ORDER BY kind", CertStatusApproved), uid)
	if err != nil {
		return nil, err
	}
	return kinds, nil
}
