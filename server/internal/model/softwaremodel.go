package model

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 软件状态(software.status)
const (
	SoftwareStatusPending   = 0
	SoftwareStatusOnline    = 1
	SoftwareStatusRejected  = 2
	SoftwareStatusTakenDown = 3
	SoftwareStatusDeleted   = 4
)

// 版本状态(software_version.status)
const (
	VersionStatusPending   = 0
	VersionStatusPublished = 1
	VersionStatusRejected  = 2
)

type (
	Software struct {
		ID              int64     `db:"id"`
		UserID          int64     `db:"user_id"`
		Name            string    `db:"name"`
		Logo            string    `db:"logo"`
		Intro           string    `db:"intro"`
		Images          string    `db:"images"` // JSON 数组
		Type            int64     `db:"type"`
		CategoryID      int64     `db:"category_id"`
		LatestVersionID int64     `db:"latest_version_id"`
		DownloadCount   int64     `db:"download_count"`
		CommentCount    int64     `db:"comment_count"`
		HotScore        int64     `db:"hot_score"`
		Status          int64     `db:"status"`
		RejectReason    string    `db:"reject_reason"`
		CreatedAt       time.Time `db:"created_at"`
		UpdatedAt       time.Time `db:"updated_at"`
	}

	SoftwareVersion struct {
		ID           int64     `db:"id"`
		SoftwareID   int64     `db:"software_id"`
		Version      string    `db:"version"`
		Size         string    `db:"size"`
		Channel      string    `db:"channel"`
		DownloadURL  string    `db:"download_url"`
		ExtractCode  string    `db:"extract_code"`
		Status       int64     `db:"status"`
		RejectReason string    `db:"reject_reason"`
		CreatedAt    time.Time `db:"created_at"`
	}

	SoftwareCategory struct {
		ID   int64  `db:"id"`
		Type int64  `db:"type"`
		Name string `db:"name"`
		Sort int64  `db:"sort"`
	}

	SoftwareModel struct{ conn sqlx.SqlConn }
)

const (
	softwareCols = "id, user_id, name, logo, intro, images, type, category_id, latest_version_id, download_count, comment_count, hot_score, status, reject_reason, created_at, updated_at"
	versionCols  = "id, software_id, version, size, channel, download_url, extract_code, status, reject_reason, created_at"
)

func NewSoftwareModel(conn sqlx.SqlConn) *SoftwareModel { return &SoftwareModel{conn: conn} }

// MarshalImages 介绍图数组 → JSON 列值。
func MarshalImages(urls []string) (string, error) {
	b, err := json.Marshal(urls)
	if err != nil {
		return "", fmt.Errorf("marshal images: %w", err)
	}
	return string(b), nil
}

// UnmarshalImages JSON 列值 → 介绍图数组。
func UnmarshalImages(s string) []string {
	var out []string
	if s == "" {
		return out
	}
	_ = json.Unmarshal([]byte(s), &out) // 列值由服务端写入,格式可信;异常时返回空数组
	return out
}

// Create 发布软件:软件主体 + 首版本 + 标签,同事务,全部待审核状态。
func (m *SoftwareModel) Create(ctx context.Context, s *Software, v *SoftwareVersion, tags []string) (softwareID, versionID int64, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, sess sqlx.Session) error {
		r, err := sess.ExecCtx(ctx,
			"INSERT INTO `software` (user_id, name, logo, intro, images, type, category_id, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
			s.UserID, s.Name, s.Logo, s.Intro, s.Images, s.Type, s.CategoryID, SoftwareStatusPending)
		if err != nil {
			return fmt.Errorf("insert software: %w", err)
		}
		if softwareID, err = r.LastInsertId(); err != nil {
			return fmt.Errorf("software id: %w", err)
		}
		rv, err := sess.ExecCtx(ctx,
			"INSERT INTO `software_version` (software_id, version, size, channel, download_url, extract_code, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
			softwareID, v.Version, v.Size, v.Channel, v.DownloadURL, v.ExtractCode, VersionStatusPending)
		if err != nil {
			return fmt.Errorf("insert version: %w", err)
		}
		if versionID, err = rv.LastInsertId(); err != nil {
			return fmt.Errorf("version id: %w", err)
		}
		for _, tag := range tags {
			if _, err = sess.ExecCtx(ctx,
				"INSERT IGNORE INTO `software_tag` (software_id, name) VALUES (?, ?)", softwareID, tag); err != nil {
				return fmt.Errorf("insert tag: %w", err)
			}
		}
		return nil
	})
	return softwareID, versionID, err
}

// AddVersion 发布新版本(待审核)。同软件版本号唯一,冲突由 uk_soft_ver 兜底。
func (m *SoftwareModel) AddVersion(ctx context.Context, v *SoftwareVersion) (int64, error) {
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `software_version` (software_id, version, size, channel, download_url, extract_code, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
		v.SoftwareID, v.Version, v.Size, v.Channel, v.DownloadURL, v.ExtractCode, VersionStatusPending)
	if err != nil {
		return 0, fmt.Errorf("insert version: %w", err)
	}
	id, err := r.LastInsertId()
	if err != nil {
		return 0, fmt.Errorf("version id: %w", err)
	}
	return id, nil
}

func (m *SoftwareModel) FindByID(ctx context.Context, id int64) (*Software, error) {
	var s Software
	q := fmt.Sprintf("SELECT %s FROM `software` WHERE id = ? LIMIT 1", softwareCols)
	if err := m.conn.QueryRowCtx(ctx, &s, q, id); err != nil {
		return nil, err
	}
	return &s, nil
}

// List 软件库列表(仅已上架)。sort: new|hot|download;type/categoryID 传 0 表示不筛。
func (m *SoftwareModel) List(ctx context.Context, typ, categoryID int64, sort string, offset, limit int) ([]*Software, error) {
	order := "id DESC"
	switch sort {
	case "hot":
		order = "hot_score DESC, id DESC"
	case "download":
		order = "download_count DESC, id DESC"
	}
	cond := fmt.Sprintf("status = %d", SoftwareStatusOnline)
	args := make([]any, 0, 4)
	if typ > 0 {
		cond += " AND type = ?"
		args = append(args, typ)
	}
	if categoryID > 0 {
		cond += " AND category_id = ?"
		args = append(args, categoryID)
	}
	args = append(args, offset, limit)
	var rows []*Software
	q := fmt.Sprintf("SELECT %s FROM `software` WHERE %s ORDER BY %s LIMIT ?, ?", softwareCols, cond, order)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

// ListByAuthor 我的发布(含待审/驳回,自己可见状态)。
func (m *SoftwareModel) ListByAuthor(ctx context.Context, uid int64, offset, limit int) ([]*Software, error) {
	var rows []*Software
	q := fmt.Sprintf("SELECT %s FROM `software` WHERE user_id = ? AND status != %d ORDER BY id DESC LIMIT ?, ?",
		softwareCols, SoftwareStatusDeleted)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, uid, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// Versions 版本历史。publishedOnly=false 时(发布者视角)返回全部状态。
func (m *SoftwareModel) Versions(ctx context.Context, softwareID int64, publishedOnly bool) ([]*SoftwareVersion, error) {
	cond := ""
	if publishedOnly {
		cond = fmt.Sprintf(" AND status = %d", VersionStatusPublished)
	}
	var rows []*SoftwareVersion
	q := fmt.Sprintf("SELECT %s FROM `software_version` WHERE software_id = ?%s ORDER BY id DESC", versionCols, cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, softwareID); err != nil {
		return nil, err
	}
	return rows, nil
}

func (m *SoftwareModel) FindVersion(ctx context.Context, id int64) (*SoftwareVersion, error) {
	var v SoftwareVersion
	q := fmt.Sprintf("SELECT %s FROM `software_version` WHERE id = ? LIMIT 1", versionCols)
	if err := m.conn.QueryRowCtx(ctx, &v, q, id); err != nil {
		return nil, err
	}
	return &v, nil
}

// Tags 批量取标签,返回 softwareID -> names。
func (m *SoftwareModel) Tags(ctx context.Context, softwareIDs []int64) (map[int64][]string, error) {
	out := make(map[int64][]string, len(softwareIDs))
	if len(softwareIDs) == 0 {
		return out, nil
	}
	type row struct {
		SoftwareID int64  `db:"software_id"`
		Name       string `db:"name"`
	}
	q, args := inQuery("SELECT software_id, name FROM `software_tag` WHERE software_id IN (%s) ORDER BY id", softwareIDs)
	var rows []row
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.SoftwareID] = append(out[r.SoftwareID], r.Name)
	}
	return out, nil
}

// Categories 启用中的分类。typ=0 返回全部大类。
func (m *SoftwareModel) Categories(ctx context.Context, typ int64) ([]*SoftwareCategory, error) {
	cond, args := "status = 1", []any{}
	if typ > 0 {
		cond += " AND type = ?"
		args = append(args, typ)
	}
	var rows []*SoftwareCategory
	q := fmt.Sprintf("SELECT id, type, name, sort FROM `software_category` WHERE %s ORDER BY type, sort, id", cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

func (m *SoftwareModel) FindCategory(ctx context.Context, id int64) (*SoftwareCategory, error) {
	var c SoftwareCategory
	if err := m.conn.QueryRowCtx(ctx, &c,
		"SELECT id, type, name, sort FROM `software_category` WHERE id = ? AND status = 1 LIMIT 1", id); err != nil {
		return nil, err
	}
	return &c, nil
}

// RecordDownload 下载点击:流水 + 计数,同事务。
func (m *SoftwareModel) RecordDownload(ctx context.Context, softwareID, versionID, uid int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := s.ExecCtx(ctx,
			"INSERT INTO `software_download_log` (software_id, version_id, user_id) VALUES (?, ?, ?)",
			softwareID, versionID, uid); err != nil {
			return fmt.Errorf("download log: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `software` SET download_count = download_count + 1 WHERE id = ?", softwareID); err != nil {
			return fmt.Errorf("download count: %w", err)
		}
		return nil
	})
}

// IsDupKey 判断唯一键冲突(同软件重复版本号等);MySQL 错误码 1062。
func IsDupKey(err error) bool {
	return err != nil && strings.Contains(err.Error(), "Duplicate entry")
}
