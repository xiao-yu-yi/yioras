package model

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 忧珠流水业务类型(youzhu_log.biz_type)
const (
	YouzhuBizTask     = 1
	YouzhuBizSignIn   = 2
	YouzhuBizOps      = 3
	YouzhuBizExchange = 4
	YouzhuBizLottery  = 5
	YouzhuBizUnlock   = 6
)

// ErrInsufficientBalance 忧珠余额不足。
var ErrInsufficientBalance = errors.New("insufficient youzhu balance")

// IsDeadlock InnoDB 死锁(Error 1213):事务已整体回滚,可安全重试。
func IsDeadlock(err error) bool {
	return err != nil && strings.Contains(err.Error(), "Error 1213")
}

// withDeadlockRetry 账务事务死锁重试:InnoDB 死锁会回滚代价小的事务,
// 重放安全(幂等键兜底不重复入账)。
func withDeadlockRetry(fn func() error) error {
	var err error
	for attempt := 0; attempt < 5; attempt++ {
		if err = fn(); !IsDeadlock(err) {
			return err
		}
		time.Sleep(time.Duration(10*(attempt+1)) * time.Millisecond)
	}
	return err
}

// lockYouzhuAccount 锁定账户行并返回当前余额。
// 先查后插:账户已存在(常态)时不执行 INSERT,避免 uk 间隙锁在高并发下互相死锁。
func lockYouzhuAccount(ctx context.Context, s sqlx.Session, uid int64) (int64, error) {
	var balance int64
	err := s.QueryRowCtx(ctx, &balance,
		"SELECT balance FROM `youzhu_account` WHERE user_id = ? FOR UPDATE", uid)
	if err == nil {
		return balance, nil
	}
	if !errors.Is(err, sqlx.ErrNotFound) {
		return 0, fmt.Errorf("lock account: %w", err)
	}
	if _, err := s.ExecCtx(ctx,
		"INSERT IGNORE INTO `youzhu_account` (user_id, balance) VALUES (?, 0)", uid); err != nil {
		return 0, fmt.Errorf("ensure account: %w", err)
	}
	if err := s.QueryRowCtx(ctx, &balance,
		"SELECT balance FROM `youzhu_account` WHERE user_id = ? FOR UPDATE", uid); err != nil {
		return 0, fmt.Errorf("lock account: %w", err)
	}
	return balance, nil
}

type (
	YouzhuLog struct {
		ID           int64     `db:"id"`
		UserID       int64     `db:"user_id"`
		BizType      int64     `db:"biz_type"`
		BizKey       string    `db:"biz_key"`
		Amount       int64     `db:"amount"`
		BalanceAfter int64     `db:"balance_after"`
		Remark       string    `db:"remark"`
		CreatedAt    time.Time `db:"created_at"`
	}

	// ReconcileDiff 对账差异行。
	ReconcileDiff struct {
		UserID  int64 `db:"user_id"`
		Balance int64 `db:"balance"`
		LogSum  int64 `db:"log_sum"`
	}

	YouzhuModel struct{ conn sqlx.SqlConn }
)

func NewYouzhuModel(conn sqlx.SqlConn) *YouzhuModel { return &YouzhuModel{conn: conn} }

// Balance 当前余额,无账户视为 0。
func (m *YouzhuModel) Balance(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT balance FROM `youzhu_account` WHERE user_id = ? LIMIT 1", uid)
	if err != nil {
		if IsNotFound(err) {
			return 0, nil
		}
		return 0, err
	}
	return n, nil
}

// Change 幂等记账(独立事务入口):amount 正入负出。
// 返回 applied=false 表示该 bizKey 已入过账(重放),按成功处理不重复变动。
func (m *YouzhuModel) Change(ctx context.Context, uid int64, bizType int64, bizKey string, amount int64, remark string) (applied bool, err error) {
	if amount == 0 {
		return false, nil
	}
	err = withDeadlockRetry(func() error {
		return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
			applied, err = youzhuChangeIn(ctx, s, uid, bizType, bizKey, amount, remark)
			return err
		})
	})
	return applied, err
}

// youzhuChangeIn 事务内记账(装扮/靓号/抽奖等"扣款+发放"同事务场景复用):
// 锁账户行 → 幂等键查重 → 校验余额 → 写流水 → 更余额。
func youzhuChangeIn(ctx context.Context, s sqlx.Session, uid int64, bizType int64, bizKey string, amount int64, remark string) (bool, error) {
	balance, err := lockYouzhuAccount(ctx, s, uid)
	if err != nil {
		return false, err
	}
	// 账户行已锁,同 bizKey 的并发请求在此串行;查到即重放
	var dup int
	if err := s.QueryRowCtx(ctx, &dup,
		"SELECT COUNT(1) FROM `youzhu_log` WHERE biz_key = ?", bizKey); err != nil {
		return false, fmt.Errorf("check biz key: %w", err)
	}
	if dup > 0 {
		return false, nil
	}
	after := balance + amount
	if after < 0 {
		return false, ErrInsufficientBalance
	}
	if _, err := s.ExecCtx(ctx,
		"INSERT INTO `youzhu_log` (user_id, biz_type, biz_key, amount, balance_after, remark) VALUES (?, ?, ?, ?, ?, ?)",
		uid, bizType, bizKey, amount, after, remark); err != nil {
		if IsDupKey(err) { // 不同账户并发共享 bizKey 的兜底(理论不该发生)
			return false, nil
		}
		return false, fmt.Errorf("insert log: %w", err)
	}
	if _, err := s.ExecCtx(ctx,
		"UPDATE `youzhu_account` SET balance = ? WHERE user_id = ?", after, uid); err != nil {
		return false, fmt.Errorf("update balance: %w", err)
	}
	return true, nil
}

// Logs 流水明细,bizType=0 不筛类型。
func (m *YouzhuModel) Logs(ctx context.Context, uid int64, bizType int64, offset, limit int) ([]*YouzhuLog, error) {
	cond, args := "user_id = ?", []any{uid}
	if bizType > 0 {
		cond += " AND biz_type = ?"
		args = append(args, bizType)
	}
	args = append(args, offset, limit)
	var rows []*YouzhuLog
	q := fmt.Sprintf("SELECT id, user_id, biz_type, biz_key, amount, balance_after, remark, created_at FROM `youzhu_log` WHERE %s ORDER BY id DESC LIMIT ?, ?", cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

// Reconcile 对账:账户余额与流水合计不一致的用户(每日巡检,返回差异行)。
func (m *YouzhuModel) Reconcile(ctx context.Context, limit int) ([]*ReconcileDiff, error) {
	var rows []*ReconcileDiff
	err := m.conn.QueryRowsCtx(ctx, &rows,
		`SELECT a.user_id, a.balance, CAST(COALESCE(l.s, 0) AS SIGNED) AS log_sum
		 FROM youzhu_account a
		 LEFT JOIN (SELECT user_id, SUM(amount) AS s FROM youzhu_log GROUP BY user_id) l ON l.user_id = a.user_id
		 WHERE a.balance != COALESCE(l.s, 0) LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}
