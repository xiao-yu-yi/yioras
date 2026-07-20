package model

import (
	"context"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	Banner struct {
		ID        int64     `db:"id"`
		Title     string    `db:"title"`
		Image     string    `db:"image"`
		LinkType  int64     `db:"link_type"`
		LinkValue string    `db:"link_value"`
		Sort      int64     `db:"sort"`
		CreatedAt time.Time `db:"created_at"`
	}

	BannerModel struct{ conn sqlx.SqlConn }
)

func NewBannerModel(conn sqlx.SqlConn) *BannerModel { return &BannerModel{conn: conn} }

// ListOnline 当前在线的公告 Banner(状态上线且在投放时段内)。
func (m *BannerModel) ListOnline(ctx context.Context, limit int) ([]*Banner, error) {
	var rows []*Banner
	err := m.conn.QueryRowsCtx(ctx, &rows,
		`SELECT id, title, image, link_type, link_value, sort, created_at FROM `+"`banner`"+`
		 WHERE status = 1 AND (start_at IS NULL OR start_at <= NOW(3)) AND (end_at IS NULL OR end_at >= NOW(3))
		 ORDER BY sort ASC, id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}
