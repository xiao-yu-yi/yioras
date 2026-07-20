package model

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 举报对象类型(report.target_type)
const (
	ReportTargetPost    = 1
	ReportTargetComment = 2
	ReportTargetUser    = 3
	ReportTargetMessage = 4
)

// ReportModel 举报。
type ReportModel struct{ conn sqlx.SqlConn }

func NewReportModel(conn sqlx.SqlConn) *ReportModel { return &ReportModel{conn: conn} }

// Create 写举报单。images 序列化为 JSON 数组存证。
func (m *ReportModel) Create(ctx context.Context, uid int64, targetType int, targetID int64, category int, reason string, images []string) error {
	var imgJSON any
	if len(images) > 0 {
		b, err := json.Marshal(images)
		if err != nil {
			return fmt.Errorf("marshal report images: %w", err)
		}
		imgJSON = string(b)
	}
	if _, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `report` (user_id, target_type, target_id, category, reason, images) VALUES (?, ?, ?, ?, ?, ?)",
		uid, targetType, targetID, category, reason, imgJSON); err != nil {
		return fmt.Errorf("insert report: %w", err)
	}
	return nil
}

// HasPending 同人同对象是否已有待处理举报(防重复刷单)。
func (m *ReportModel) HasPending(ctx context.Context, uid int64, targetType int, targetID int64) (bool, error) {
	var n int
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT COUNT(1) FROM `report` WHERE user_id = ? AND target_type = ? AND target_id = ? AND status = 0",
		uid, targetType, targetID)
	return n > 0, err
}
