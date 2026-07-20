package model

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 敏感词处置等级(对应 sensitive_word.level)
const (
	WordLevelBlock  = 1 // 直接拦截
	WordLevelReview = 2 // 转人审
	WordLevelMask   = 3 // 替换为*
)

// 审核队列业务类型(对应 audit_queue.biz_type)
const (
	AuditBizPost     = 1
	AuditBizComment  = 2
	AuditBizSoftware = 3 // 软件与版本共用:detail 里区分 software/version
)

// 机审结果(对应 audit_queue.machine_result)
const (
	MachineSuspect = 2 // 疑似,转人审
)

type (
	SensitiveWord struct {
		Word  string `db:"word"`
		Level int64  `db:"level"`
	}

	SensitiveModel struct{ conn sqlx.SqlConn }
)

func NewSensitiveModel(conn sqlx.SqlConn) *SensitiveModel { return &SensitiveModel{conn: conn} }

func (m *SensitiveModel) ListEnabled(ctx context.Context) ([]SensitiveWord, error) {
	var rows []SensitiveWord
	if err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT word, level FROM `sensitive_word` WHERE status = 1"); err != nil {
		return nil, err
	}
	return rows, nil
}

// SensitiveWordFull 词库管理页完整行。
type SensitiveWordFull struct {
	ID        int64     `db:"id"`
	Word      string    `db:"word"`
	Category  int64     `db:"category"`
	Level     int64     `db:"level"`
	Status    int64     `db:"status"`
	CreatedAt time.Time `db:"created_at"`
}

// ListWords 词库管理列表:关键词模糊 + 分类/等级/状态筛选(0 不筛),新词在前。
func (m *SensitiveModel) ListWords(ctx context.Context, keyword string, category, level, status int64, offset, limit int) (int64, []*SensitiveWordFull, error) {
	cond, args := "1 = 1", []any{}
	if keyword != "" {
		cond += " AND word LIKE ?"
		args = append(args, escapeLike(keyword))
	}
	if category > 0 {
		cond += " AND category = ?"
		args = append(args, category)
	}
	if level > 0 {
		cond += " AND level = ?"
		args = append(args, level)
	}
	if status >= 0 {
		cond += " AND status = ?"
		args = append(args, status)
	}
	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) FROM `sensitive_word` WHERE "+cond, args...); err != nil {
		return 0, nil, fmt.Errorf("count words: %w", err)
	}
	var rows []*SensitiveWordFull
	q := "SELECT id, word, category, level, status, created_at FROM `sensitive_word` WHERE " + cond + " ORDER BY id DESC LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("list words: %w", err)
	}
	return total, rows, nil
}

// ErrWordExists 敏感词已存在(uk_word)。
var ErrWordExists = fmt.Errorf("sensitive word exists")

func (m *SensitiveModel) CreateWord(ctx context.Context, word string, category, level int64) (int64, error) {
	r, err := m.conn.ExecCtx(ctx,
		"INSERT IGNORE INTO `sensitive_word` (word, category, level) VALUES (?, ?, ?)", word, category, level)
	if err != nil {
		return 0, fmt.Errorf("create word: %w", err)
	}
	if n, _ := r.RowsAffected(); n == 0 {
		return 0, ErrWordExists
	}
	return r.LastInsertId()
}

// UpdateWord 调整分类/处置等级/启停。返回 false 表示词条不存在。
func (m *SensitiveModel) UpdateWord(ctx context.Context, id, category, level, status int64) (bool, error) {
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `sensitive_word` SET category = ?, level = ?, status = ? WHERE id = ?", category, level, status, id); err != nil {
		return false, fmt.Errorf("update word: %w", err)
	}
	var n int
	if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `sensitive_word` WHERE id = ?", id); err != nil {
		return false, err
	}
	return n > 0, nil
}

func (m *SensitiveModel) DeleteWord(ctx context.Context, id int64) error {
	if _, err := m.conn.ExecCtx(ctx, "DELETE FROM `sensitive_word` WHERE id = ?", id); err != nil {
		return fmt.Errorf("delete word: %w", err)
	}
	return nil
}

// AddAudit 机审命中转人审时写审核队列。
// machine_detail 是 JSON 列:入参已是合法 JSON 原样落库,否则包装成 {"hit": ...}。
func (m *SensitiveModel) AddAudit(ctx context.Context, bizType int, bizID int64, machineResult int, detail string) error {
	var detailJSON any
	if detail != "" {
		if json.Valid([]byte(detail)) {
			detailJSON = detail
		} else {
			b, err := json.Marshal(map[string]string{"hit": detail})
			if err != nil {
				return fmt.Errorf("marshal audit detail: %w", err)
			}
			detailJSON = string(b)
		}
	}
	_, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `audit_queue` (biz_type, biz_id, machine_result, machine_detail) VALUES (?, ?, ?, ?)",
		bizType, bizID, machineResult, detailJSON)
	return err
}
