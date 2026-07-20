package model

import (
	"context"
	"fmt"
	"strings"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	Topic struct {
		ID        int64  `db:"id"`
		Name      string `db:"name"`
		PostCount int64  `db:"post_count"`
	}

	// SearchModel MySQL LIKE 实现的全站搜索(pkg/search.Searcher 的默认实现)。
	// 数据量上来后换 Meilisearch:实现同一接口后在 svc 替换装配即可,调用方零改动。
	SearchModel struct{ conn sqlx.SqlConn }
)

func NewSearchModel(conn sqlx.SqlConn) *SearchModel { return &SearchModel{conn: conn} }

// escapeLike 转义 LIKE 通配符,防止关键词里的 %/_ 变成任意匹配。
func escapeLike(kw string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return "%" + r.Replace(kw) + "%"
}

// SearchPosts 已发布公开帖,标题/正文匹配,热度优先。
func (m *SearchModel) SearchPosts(ctx context.Context, kw string, offset, limit int) ([]*Post, error) {
	var rows []*Post
	q := fmt.Sprintf(
		"SELECT %s FROM `post` WHERE status = %d AND visibility = 0 AND (title LIKE ? OR content LIKE ?) ORDER BY hot_score DESC, id DESC LIMIT ?, ?",
		postCols, PostStatusPublished)
	p := escapeLike(kw)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, p, p, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// SearchUsers 昵称/靓号匹配(注销号除外)。
func (m *SearchModel) SearchUsers(ctx context.Context, kw string, offset, limit int) ([]*UserBrief, error) {
	var rows []*UserBrief
	p := escapeLike(kw)
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, display_no, nickname, avatar, level FROM `user` WHERE status != 4 AND (nickname LIKE ? OR display_no LIKE ?) ORDER BY level DESC, id LIMIT ?, ?",
		p, p, offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// SearchCircles 圈子名/简介匹配。
func (m *SearchModel) SearchCircles(ctx context.Context, kw string, offset, limit int) ([]*Circle, error) {
	var rows []*Circle
	p := escapeLike(kw)
	q := fmt.Sprintf("SELECT %s FROM `circle` WHERE status = 1 AND (name LIKE ? OR intro LIKE ?) ORDER BY hot_score DESC, id LIMIT ?, ?", circleCols)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, p, p, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// SearchSoftware 已上架软件,名字/简介匹配。
func (m *SearchModel) SearchSoftware(ctx context.Context, kw string, offset, limit int) ([]*Software, error) {
	var rows []*Software
	p := escapeLike(kw)
	q := fmt.Sprintf("SELECT %s FROM `software` WHERE status = %d AND (name LIKE ? OR intro LIKE ?) ORDER BY download_count DESC, id DESC LIMIT ?, ?",
		softwareCols, SoftwareStatusOnline)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, p, p, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// SearchTopics 话题名匹配。
func (m *SearchModel) SearchTopics(ctx context.Context, kw string, offset, limit int) ([]*Topic, error) {
	var rows []*Topic
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, post_count FROM `topic` WHERE status = 1 AND name LIKE ? ORDER BY hot_score DESC, id LIMIT ?, ?",
		escapeLike(kw), offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}
