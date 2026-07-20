package model

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	Conversation struct {
		ID          int64        `db:"id"`
		UserMin     int64        `db:"user_min"`
		UserMax     int64        `db:"user_max"`
		LastMsgSeq  int64        `db:"last_msg_seq"`
		LastPreview string       `db:"last_preview"`
		LastMsgAt   sql.NullTime `db:"last_msg_at"`
		CreatedAt   time.Time    `db:"created_at"`
		UpdatedAt   time.Time    `db:"updated_at"`
	}

	ConversationMember struct {
		ID             int64     `db:"id"`
		ConversationID int64     `db:"conversation_id"`
		UserID         int64     `db:"user_id"`
		LastReadSeq    int64     `db:"last_read_seq"`
		Deleted        int64     `db:"deleted"`
		UpdatedAt      time.Time `db:"updated_at"`
	}

	Message struct {
		ID             int64     `db:"id"`
		ConversationID int64     `db:"conversation_id"`
		Seq            int64     `db:"seq"`
		SenderID       int64     `db:"sender_id"`
		MsgType        int64     `db:"msg_type"`
		Content        string    `db:"content"`
		Status         int64     `db:"status"`
		CreatedAt      time.Time `db:"created_at"`
	}

	IMModel struct{ conn sqlx.SqlConn }
)

func NewIMModel(conn sqlx.SqlConn) *IMModel { return &IMModel{conn: conn} }

func pair(a, b int64) (int64, int64) {
	if a < b {
		return a, b
	}
	return b, a
}

// EnsureConversation 取或建单聊会话(幂等,uk_pair 兜底并发)。
func (m *IMModel) EnsureConversation(ctx context.Context, uidA, uidB int64) (*Conversation, error) {
	lo, hi := pair(uidA, uidB)
	if _, err := m.conn.ExecCtx(ctx,
		"INSERT IGNORE INTO `conversation` (user_min, user_max) VALUES (?, ?)", lo, hi); err != nil {
		return nil, fmt.Errorf("ensure conversation: %w", err)
	}
	var c Conversation
	err := m.conn.QueryRowCtx(ctx, &c,
		"SELECT id, user_min, user_max, last_msg_seq, last_preview, last_msg_at, created_at, updated_at FROM `conversation` WHERE user_min = ? AND user_max = ? LIMIT 1",
		lo, hi)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (m *IMModel) FindConversation(ctx context.Context, id int64) (*Conversation, error) {
	var c Conversation
	err := m.conn.QueryRowCtx(ctx, &c,
		"SELECT id, user_min, user_max, last_msg_seq, last_preview, last_msg_at, created_at, updated_at FROM `conversation` WHERE id = ? LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// AppendMessage 发消息:seq 原子递增+消息落库+双方成员行,同事务。返回带 seq 的消息。
func (m *IMModel) AppendMessage(ctx context.Context, convID, senderID int64, msgType int64, content, preview string) (*Message, error) {
	var msg *Message
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		// 行锁下取号,保证会话内 seq 连续有序
		r, err := s.ExecCtx(ctx,
			"UPDATE `conversation` SET last_msg_seq = last_msg_seq + 1, last_preview = ?, last_msg_at = NOW(3) WHERE id = ?",
			preview, convID)
		if err != nil {
			return fmt.Errorf("bump seq: %w", err)
		}
		if n, _ := r.RowsAffected(); n != 1 {
			return fmt.Errorf("conversation %d not found", convID)
		}
		var seq int64
		if err = s.QueryRowCtx(ctx, &seq,
			"SELECT last_msg_seq FROM `conversation` WHERE id = ?", convID); err != nil {
			return fmt.Errorf("load seq: %w", err)
		}
		res, err := s.ExecCtx(ctx,
			"INSERT INTO `message` (conversation_id, seq, sender_id, msg_type, content) VALUES (?, ?, ?, ?, ?)",
			convID, seq, senderID, msgType, content)
		if err != nil {
			return fmt.Errorf("insert message: %w", err)
		}
		id, err := res.LastInsertId()
		if err != nil {
			return fmt.Errorf("message id: %w", err)
		}
		// 双方成员行:发送方已读推进到本条;接收方 deleted 复位(删除会话后来新消息要重新出现)
		if _, err = s.ExecCtx(ctx,
			"INSERT INTO `conversation_member` (conversation_id, user_id, last_read_seq) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE last_read_seq = ?, deleted = 0, updated_at = NOW(3)",
			convID, senderID, seq, seq); err != nil {
			return fmt.Errorf("sender member: %w", err)
		}
		var c Conversation
		if err = s.QueryRowCtx(ctx, &c,
			"SELECT id, user_min, user_max, last_msg_seq, last_preview, last_msg_at, created_at, updated_at FROM `conversation` WHERE id = ?", convID); err != nil {
			return fmt.Errorf("load conversation: %w", err)
		}
		peer := c.UserMin
		if senderID == c.UserMin {
			peer = c.UserMax
		}
		if _, err = s.ExecCtx(ctx,
			"INSERT INTO `conversation_member` (conversation_id, user_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE deleted = 0, updated_at = NOW(3)",
			convID, peer); err != nil {
			return fmt.Errorf("peer member: %w", err)
		}
		msg = &Message{ID: id, ConversationID: convID, Seq: seq, SenderID: senderID, MsgType: msgType, Content: content, CreatedAt: time.Now()}
		return nil
	})
	return msg, err
}

// ListConversations 会话列表(按最近活跃),含未读数。
type ConversationItem struct {
	Conversation
	LastReadSeq int64 `db:"last_read_seq"`
}

func (m *IMModel) ListConversations(ctx context.Context, uid int64, offset, limit int) ([]*ConversationItem, error) {
	var rows []*ConversationItem
	err := m.conn.QueryRowsCtx(ctx, &rows,
		`SELECT c.id, c.user_min, c.user_max, c.last_msg_seq, c.last_preview, c.last_msg_at, c.created_at, c.updated_at, cm.last_read_seq
		 FROM conversation_member cm JOIN conversation c ON c.id = cm.conversation_id
		 WHERE cm.user_id = ? AND cm.deleted = 0 AND c.last_msg_seq > 0
		 ORDER BY c.last_msg_at DESC LIMIT ?, ?`, uid, offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// ListMessages 拉取会话消息,beforeSeq=0 表示从最新开始,倒序分页。
func (m *IMModel) ListMessages(ctx context.Context, convID, beforeSeq int64, limit int) ([]*Message, error) {
	if beforeSeq <= 0 {
		beforeSeq = 1 << 62
	}
	var rows []*Message
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, conversation_id, seq, sender_id, msg_type, content, status, created_at FROM `message` WHERE conversation_id = ? AND seq < ? ORDER BY seq DESC LIMIT ?",
		convID, beforeSeq, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// FindMessage 按 ID 取单条消息(举报留证等场景)。
func (m *IMModel) FindMessage(ctx context.Context, id int64) (*Message, error) {
	var msg Message
	err := m.conn.QueryRowCtx(ctx, &msg,
		"SELECT id, conversation_id, seq, sender_id, msg_type, content, status, created_at FROM `message` WHERE id = ? LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &msg, nil
}

// UnreadTotal 全部会话未读总数(消息 Tab 角标)。
func (m *IMModel) UnreadTotal(ctx context.Context, uid int64) (int64, error) {
	var n int64
	err := m.conn.QueryRowCtx(ctx, &n,
		`SELECT CAST(COALESCE(SUM(GREATEST(c.last_msg_seq - cm.last_read_seq, 0)), 0) AS SIGNED)
		 FROM conversation_member cm JOIN conversation c ON c.id = cm.conversation_id
		 WHERE cm.user_id = ? AND cm.deleted = 0`, uid)
	return n, err
}

// MarkRead 已读推进(只前进不后退)。
func (m *IMModel) MarkRead(ctx context.Context, convID, uid, seq int64) error {
	_, err := m.conn.ExecCtx(ctx,
		"UPDATE `conversation_member` SET last_read_seq = GREATEST(last_read_seq, ?) WHERE conversation_id = ? AND user_id = ?",
		seq, convID, uid)
	return err
}

// 消息状态(message.status)
const (
	MsgStatusNormal   = 0
	MsgStatusRecalled = 1
)

// RecallMessage 撤回:仅发送者本人、normal 状态、withinSec 秒内;末条消息同步改会话摘要。
// 撤回窗口用 DB 时钟(created_at 与 NOW 同源)判定,避免应用与 DB 时区不一致导致误判。
func (m *IMModel) RecallMessage(ctx context.Context, convID, msgID, uid int64, withinSec int) (*Message, error) {
	var msg Message
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if err := s.QueryRowCtx(ctx, &msg,
			"SELECT id, conversation_id, seq, sender_id, msg_type, content, status, created_at FROM `message` WHERE id = ? AND conversation_id = ? LIMIT 1 FOR UPDATE",
			msgID, convID); err != nil {
			return err
		}
		if msg.SenderID != uid || msg.Status != MsgStatusNormal {
			return sqlx.ErrNotFound
		}
		r, err := s.ExecCtx(ctx,
			"UPDATE `message` SET status = ? WHERE id = ? AND created_at > NOW(3) - INTERVAL ? SECOND",
			MsgStatusRecalled, msgID, withinSec)
		if err != nil {
			return fmt.Errorf("recall update: %w", err)
		}
		if n, _ := r.RowsAffected(); n != 1 {
			return errRecallExpired
		}
		// 撤回的是最后一条时,会话列表摘要同步替换
		if _, err := s.ExecCtx(ctx,
			"UPDATE `conversation` SET last_preview = ? WHERE id = ? AND last_msg_seq = ?",
			"[消息已撤回]", convID, msg.Seq); err != nil {
			return fmt.Errorf("recall preview: %w", err)
		}
		msg.Status = MsgStatusRecalled
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &msg, nil
}

var errRecallExpired = fmt.Errorf("recall window expired")

// IsRecallExpired 判断撤回失败原因是否为超时。
func IsRecallExpired(err error) bool { return errors.Is(err, errRecallExpired) }

// DeleteConversation 删除会话(仅影响自己的列表,新消息到达自动恢复);
// 同时把已读推进到最新,避免删除后未读角标残留。
func (m *IMModel) DeleteConversation(ctx context.Context, convID, uid int64) error {
	_, err := m.conn.ExecCtx(ctx,
		`UPDATE conversation_member cm JOIN conversation c ON c.id = cm.conversation_id
		 SET cm.deleted = 1, cm.last_read_seq = c.last_msg_seq
		 WHERE cm.conversation_id = ? AND cm.user_id = ?`, convID, uid)
	return err
}

func (m *IMModel) IsBlocked(ctx context.Context, owner, target int64) (bool, error) {
	var n int
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT COUNT(1) FROM `black_list` WHERE user_id = ? AND target_uid = ?", owner, target)
	return n > 0, err
}

func (m *IMModel) IsMutualFollow(ctx context.Context, a, b int64) (bool, error) {
	var n int
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT COUNT(1) FROM `follow` WHERE (user_id = ? AND target_uid = ?) OR (user_id = ? AND target_uid = ?)",
		a, b, b, a)
	return n == 2, err
}
