package model

import (
	"context"
	"fmt"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	PushToken struct {
		UserID   int64  `db:"user_id"`
		DeviceID string `db:"device_id"`
		Platform string `db:"platform"`
		Channel  string `db:"channel"`
		Token    string `db:"token"`
	}

	PushModel struct{ conn sqlx.SqlConn }
)

func NewPushModel(conn sqlx.SqlConn) *PushModel { return &PushModel{conn: conn} }

// UpsertToken 设备推送令牌上报(客户端每次启动/令牌轮换时调用,按 user+device 覆盖)。
func (m *PushModel) UpsertToken(ctx context.Context, t *PushToken) error {
	if _, err := m.conn.ExecCtx(ctx,
		`INSERT INTO push_token (user_id, device_id, platform, channel, token) VALUES (?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE platform = VALUES(platform), channel = VALUES(channel), token = VALUES(token)`,
		t.UserID, t.DeviceID, t.Platform, t.Channel, t.Token); err != nil {
		return fmt.Errorf("upsert push token: %w", err)
	}
	return nil
}

// DeleteToken 退出登录/踢设备时清除,避免向已下线设备继续推。
func (m *PushModel) DeleteToken(ctx context.Context, uid int64, deviceID string) error {
	_, err := m.conn.ExecCtx(ctx,
		"DELETE FROM push_token WHERE user_id = ? AND device_id = ?", uid, deviceID)
	return err
}

// TokensByUser 用户全部在册设备令牌(离线推送遍历下发)。
func (m *PushModel) TokensByUser(ctx context.Context, uid int64) ([]*PushToken, error) {
	var rows []*PushToken
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT user_id, device_id, platform, channel, token FROM push_token WHERE user_id = ? LIMIT 10", uid)
	if err != nil {
		return nil, err
	}
	return rows, nil
}
