package model

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 通知类型(消息页三个聚合入口)
const (
	NotifyTypeLike    = 1 // 赞与收藏
	NotifyTypeComment = 2 // 评论和@
	NotifyTypeSystem  = 3 // 系统通知
)

type (
	Notification struct {
		ID         int64     `db:"id"`
		UserID     int64     `db:"user_id"`
		Type       int64     `db:"type"`
		ActorID    int64     `db:"actor_id"`
		TargetType int64     `db:"target_type"`
		TargetID   int64     `db:"target_id"`
		Content    string    `db:"content"`
		IsRead     int64     `db:"is_read"`
		CreatedAt  time.Time `db:"created_at"`
	}

	// NotifyHook 单条通知落库成功后的切面(svc 注入:WS 小红点实时推 + 离线推送补偿)。
	// 放 model 层 hook 是为了让全部 Add 调用点(点赞/评论/审核/处置…)零改动统一生效;
	// 注:公告全员扇出走批量 SQL 不经 Add,天然不触发离线推送(避免广播轰炸)。
	NotifyHook func(ctx context.Context, n *Notification)

	NotifyModel struct {
		conn sqlx.SqlConn
		hook NotifyHook
	}
)

func NewNotifyModel(conn sqlx.SqlConn) *NotifyModel { return &NotifyModel{conn: conn} }

// SetHook 启动装配期一次性注入,运行期只读。
func (m *NotifyModel) SetHook(h NotifyHook) { m.hook = h }

// Add 写入通知。自己触发自己的互动不落通知,由调用方保证。
func (m *NotifyModel) Add(ctx context.Context, n *Notification) error {
	_, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `notification` (user_id, type, actor_id, target_type, target_id, content) VALUES (?, ?, ?, ?, ?, ?)",
		n.UserID, n.Type, n.ActorID, n.TargetType, n.TargetID, n.Content)
	if err != nil {
		return fmt.Errorf("insert notification: %w", err)
	}
	if m.hook != nil {
		m.hook(ctx, n)
	}
	return nil
}

func (m *NotifyModel) List(ctx context.Context, uid int64, typ int, offset, limit int) ([]*Notification, error) {
	var rows []*Notification
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, user_id, type, actor_id, target_type, target_id, content, is_read, created_at FROM `notification` WHERE user_id = ? AND type = ? ORDER BY id DESC LIMIT ?, ?",
		uid, typ, offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// UnreadCounts 三类入口未读角标。
func (m *NotifyModel) UnreadCounts(ctx context.Context, uid int64) (map[int64]int64, error) {
	type row struct {
		Type int64 `db:"type"`
		N    int64 `db:"n"`
	}
	var rows []row
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT type, COUNT(1) AS n FROM `notification` WHERE user_id = ? AND is_read = 0 GROUP BY type", uid)
	if err != nil {
		return nil, err
	}
	out := make(map[int64]int64, 3)
	for _, r := range rows {
		out[r.Type] = r.N
	}
	return out, nil
}

// MarkAllRead 进入某聚合页时清零该类未读。
func (m *NotifyModel) MarkAllRead(ctx context.Context, uid int64, typ int) error {
	_, err := m.conn.ExecCtx(ctx,
		"UPDATE `notification` SET is_read = 1 WHERE user_id = ? AND type = ? AND is_read = 0", uid, typ)
	return err
}
