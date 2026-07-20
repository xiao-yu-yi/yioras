package model

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// ErrAlreadyUnlocked 已解锁过该帖。
var ErrAlreadyUnlocked = errors.New("post already unlocked")

type (
	PaidContent struct {
		ID      int64  `db:"id"`
		PostID  int64  `db:"post_id"`
		Price   int64  `db:"price"`
		Content string `db:"content"`
	}

	PaidModel struct{ conn sqlx.SqlConn }
)

func NewPaidModel(conn sqlx.SqlConn) *PaidModel { return &PaidModel{conn: conn} }

// CreateIn 事务内写入付费段(发帖事务复用)。
func CreatePaidContentIn(ctx context.Context, s sqlx.Session, postID, price int64, content string) error {
	if _, err := s.ExecCtx(ctx,
		"INSERT INTO `post_paid_content` (post_id, price, content) VALUES (?, ?, ?)",
		postID, price, content); err != nil {
		return fmt.Errorf("insert paid content: %w", err)
	}
	return nil
}

// Find 帖子付费段,无则 ErrNotFound。
func (m *PaidModel) Find(ctx context.Context, postID int64) (*PaidContent, error) {
	var p PaidContent
	err := m.conn.QueryRowCtx(ctx, &p,
		"SELECT id, post_id, price, content FROM `post_paid_content` WHERE post_id = ? LIMIT 1", postID)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// Prices 批量取付费价,返回 postID -> price(列表打付费标)。
func (m *PaidModel) Prices(ctx context.Context, postIDs []int64) (map[int64]int64, error) {
	out := make(map[int64]int64, len(postIDs))
	if len(postIDs) == 0 {
		return out, nil
	}
	type row struct {
		PostID int64 `db:"post_id"`
		Price  int64 `db:"price"`
	}
	q, args := inQuery("SELECT post_id, price FROM `post_paid_content` WHERE post_id IN (%s)", postIDs)
	var rows []row
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.PostID] = r.Price
	}
	return out, nil
}

// UnlockedSet 批量查询 uid 已解锁的帖子。
func (m *PaidModel) UnlockedSet(ctx context.Context, uid int64, postIDs []int64) (map[int64]bool, error) {
	out := make(map[int64]bool, len(postIDs))
	if uid <= 0 || len(postIDs) == 0 {
		return out, nil
	}
	q, args := inQuery("SELECT post_id FROM `post_unlock_record` WHERE user_id = ? AND post_id IN (%s)", postIDs, uid)
	var hit []int64
	if err := m.conn.QueryRowsCtx(ctx, &hit, q, args...); err != nil {
		return nil, err
	}
	for _, id := range hit {
		out[id] = true
	}
	return out, nil
}

// Unlock 解锁付费帖:买家扣款 + 作者分成 + 解锁记录,双账户单事务。
// feePercent 平台抽成百分比;两笔记账各自带幂等键,uk_post_user 兜底重复解锁。
// 死锁预防:双账户按 uid 升序加锁(youzhuChangeIn 内部锁账户行)。
func (m *PaidModel) Unlock(ctx context.Context, uid, authorID, postID, price int64, feePercent int64) (income int64, err error) {
	income = price * (100 - feePercent) / 100
	err = withDeadlockRetry(func() error {
		return m.unlockTx(ctx, uid, authorID, postID, price, income)
	})
	return income, err
}

func (m *PaidModel) unlockTx(ctx context.Context, uid, authorID, postID, price, income int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		// 先查解锁记录(uk 兜底并发):已解锁直接返回
		var n int
		if err := s.QueryRowCtx(ctx, &n,
			"SELECT COUNT(1) FROM `post_unlock_record` WHERE post_id = ? AND user_id = ?", postID, uid); err != nil {
			return fmt.Errorf("check unlocked: %w", err)
		}
		if n > 0 {
			return ErrAlreadyUnlocked
		}
		// 双账户按 uid 升序记账,避免交叉加锁死锁
		type entry struct {
			uid    int64
			amount int64
			key    string
			remark string
		}
		entries := []entry{
			{uid, -price, fmt.Sprintf("unlock:%d:%d", uid, postID), "解锁付费帖"},
			{authorID, income, fmt.Sprintf("unlock-inc:%d:%d", uid, postID), "付费帖解锁分成"},
		}
		if entries[0].uid > entries[1].uid {
			entries[0], entries[1] = entries[1], entries[0]
		}
		for _, e := range entries {
			if _, err := youzhuChangeIn(ctx, s, e.uid, YouzhuBizUnlock, e.key, e.amount, e.remark); err != nil {
				return err
			}
		}
		if _, err := s.ExecCtx(ctx,
			"INSERT INTO `post_unlock_record` (post_id, user_id, price, author_income) VALUES (?, ?, ?, ?)",
			postID, uid, price, income); err != nil {
			if IsDupKey(err) {
				return ErrAlreadyUnlocked
			}
			return fmt.Errorf("insert unlock record: %w", err)
		}
		return nil
	})
}

// ---- AI 管家 ----

// BotUID AI 管家系统账号,与 005 迁移种子一致。后台可配属运营配置。
const BotUID = 999999

type (
	FaqRule struct {
		ID       int64  `db:"id"`
		Keywords string `db:"keywords"` // 竖线分隔
		Reply    string `db:"reply"`
		Priority int64  `db:"priority"`
	}

	FaqModel struct{ conn sqlx.SqlConn }
)

func NewFaqModel(conn sqlx.SqlConn) *FaqModel { return &FaqModel{conn: conn} }

// ListEnabled 启用规则(priority 升序,先命中先回复)。
func (m *FaqModel) ListEnabled(ctx context.Context) ([]*FaqRule, error) {
	var rows []*FaqRule
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, keywords, reply, priority FROM `faq_rule` WHERE status = 1 ORDER BY priority, id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// FaqRuleFull 词条管理页完整行。
type FaqRuleFull struct {
	ID        int64     `db:"id"`
	Keywords  string    `db:"keywords"`
	Reply     string    `db:"reply"`
	Priority  int64     `db:"priority"`
	Status    int64     `db:"status"`
	CreatedAt time.Time `db:"created_at"`
}

// ListAll 词条管理列表(含停用),priority 升序与应答顺序一致。
func (m *FaqModel) ListAll(ctx context.Context, offset, limit int) (int64, []*FaqRuleFull, error) {
	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) FROM `faq_rule`"); err != nil {
		return 0, nil, fmt.Errorf("count faq: %w", err)
	}
	var rows []*FaqRuleFull
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, keywords, reply, priority, status, created_at FROM `faq_rule` ORDER BY priority, id LIMIT ?, ?", offset, limit)
	if err != nil {
		return 0, nil, fmt.Errorf("list faq: %w", err)
	}
	return total, rows, nil
}

func (m *FaqModel) Create(ctx context.Context, keywords, reply string, priority int64) (int64, error) {
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `faq_rule` (keywords, reply, priority) VALUES (?, ?, ?)", keywords, reply, priority)
	if err != nil {
		return 0, fmt.Errorf("create faq: %w", err)
	}
	return r.LastInsertId()
}

// Update 全量更新词条。返回 false 表示词条不存在。
func (m *FaqModel) Update(ctx context.Context, id int64, keywords, reply string, priority, status int64) (bool, error) {
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `faq_rule` SET keywords = ?, reply = ?, priority = ?, status = ? WHERE id = ?",
		keywords, reply, priority, status, id); err != nil {
		return false, fmt.Errorf("update faq: %w", err)
	}
	var n int
	if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `faq_rule` WHERE id = ?", id); err != nil {
		return false, err
	}
	return n > 0, nil
}

func (m *FaqModel) Delete(ctx context.Context, id int64) error {
	if _, err := m.conn.ExecCtx(ctx, "DELETE FROM `faq_rule` WHERE id = ?", id); err != nil {
		return fmt.Errorf("delete faq: %w", err)
	}
	return nil
}
