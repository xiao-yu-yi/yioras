package model

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	AppConfigRow struct {
		K         string    `db:"k"`
		V         string    `db:"v"`
		Remark    string    `db:"remark"`
		UpdatedAt time.Time `db:"updated_at"`
	}

	// ConfigModel 运营参数(app_config)。读路径带 60s 进程内缓存:
	// 热路径(加经验/热度)每请求都读参数,DB 压力不可接受;运营改参数分钟级生效可接受。
	ConfigModel struct {
		conn sqlx.SqlConn

		mu      sync.RWMutex
		cache   map[string]string
		cacheAt time.Time
	}
)

const configCacheTTL = 60 * time.Second

func NewConfigModel(conn sqlx.SqlConn) *ConfigModel { return &ConfigModel{conn: conn} }

func (m *ConfigModel) loadAll(ctx context.Context) (map[string]string, error) {
	m.mu.RLock()
	if m.cache != nil && time.Since(m.cacheAt) < configCacheTTL {
		c := m.cache
		m.mu.RUnlock()
		return c, nil
	}
	m.mu.RUnlock()

	var rows []AppConfigRow
	if err := m.conn.QueryRowsCtx(ctx, &rows, "SELECT k, v, remark, updated_at FROM `app_config`"); err != nil {
		return nil, fmt.Errorf("load app config: %w", err)
	}
	fresh := make(map[string]string, len(rows))
	for _, r := range rows {
		fresh[r.K] = r.V
	}
	m.mu.Lock()
	m.cache, m.cacheAt = fresh, time.Now()
	m.mu.Unlock()
	return fresh, nil
}

// Int 读整型参数;缺失或非法返回 def(参数表被误删时回退硬编码默认,不炸业务)。
func (m *ConfigModel) Int(ctx context.Context, key string, def int64) int64 {
	all, err := m.loadAll(ctx)
	if err != nil {
		return def
	}
	raw, ok := all[key]
	if !ok {
		return def
	}
	n, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return def
	}
	return n
}

// Str 读字符串参数;缺失返回 def。
func (m *ConfigModel) Str(ctx context.Context, key, def string) string {
	all, err := m.loadAll(ctx)
	if err != nil {
		return def
	}
	if raw, ok := all[key]; ok && raw != "" {
		return raw
	}
	return def
}

// Invalidate 后台保存后立即失效缓存(本实例即时生效;多实例等 TTL)。
func (m *ConfigModel) Invalidate() {
	m.mu.Lock()
	m.cache = nil
	m.mu.Unlock()
}

// ListByPrefix 后台配置页列表。
func (m *ConfigModel) ListByPrefix(ctx context.Context, prefix string) ([]AppConfigRow, error) {
	var rows []AppConfigRow
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT k, v, remark, updated_at FROM `app_config` WHERE k LIKE ? ORDER BY k", prefix+"%")
	if err != nil {
		return nil, fmt.Errorf("list app config: %w", err)
	}
	return rows, nil
}

// Save 更新已存在的参数(只允许改值,键与说明由迁移管理,防误建垃圾键)。返回 false=键不存在。
// 注:先查存在性再更新——RowsAffected 在值未变化时为 0,不能用来判断键是否存在。
func (m *ConfigModel) Save(ctx context.Context, k, v string) (bool, error) {
	var exists int
	if err := m.conn.QueryRowCtx(ctx, &exists,
		"SELECT COUNT(1) FROM `app_config` WHERE k = ?", k); err != nil {
		return false, fmt.Errorf("check app config: %w", err)
	}
	if exists == 0 {
		return false, nil
	}
	if _, err := m.conn.ExecCtx(ctx, "UPDATE `app_config` SET v = ? WHERE k = ?", v, k); err != nil {
		return false, fmt.Errorf("save app config: %w", err)
	}
	m.Invalidate()
	return true, nil
}
