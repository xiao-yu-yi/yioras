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

// SuggestItem 搜索联想条目。Highlighted 为带 <em> 标记的高亮片段(mysql 驱动无高亮,同原文)。
type SuggestItem struct {
	Type        string `json:"type"` // post / software / circle / topic
	ID          int64  `json:"id"`
	Text        string `json:"text"`
	Highlighted string `json:"highlighted"`
}

// Suggest MySQL 前缀匹配联想(kw% 可走索引;LIKE 驱动的降级实现,无分词无高亮)。
func (m *SearchModel) Suggest(ctx context.Context, kw string, limit int) ([]SuggestItem, error) {
	prefix := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(kw) + "%"
	type row struct {
		ID   int64  `db:"id"`
		Text string `db:"t"`
	}
	pull := func(q string) []row {
		var rows []row
		if err := m.conn.QueryRowsCtx(ctx, &rows, q, prefix, limit); err != nil {
			return nil
		}
		return rows
	}
	out := make([]SuggestItem, 0, limit*4)
	add := func(typ string, rows []row) {
		for _, r := range rows {
			if r.Text == "" {
				continue
			}
			out = append(out, SuggestItem{Type: typ, ID: r.ID, Text: r.Text, Highlighted: r.Text})
		}
	}
	add("post", pull(fmt.Sprintf("SELECT id, title AS t FROM `post` WHERE status = %d AND visibility = 0 AND title LIKE ? ORDER BY hot_score DESC LIMIT ?", PostStatusPublished)))
	add("software", pull(fmt.Sprintf("SELECT id, name AS t FROM `software` WHERE status = %d AND name LIKE ? ORDER BY download_count DESC LIMIT ?", SoftwareStatusOnline)))
	add("circle", pull("SELECT id, name AS t FROM `circle` WHERE status = 1 AND name LIKE ? ORDER BY hot_score DESC LIMIT ?"))
	add("topic", pull("SELECT id, name AS t FROM `topic` WHERE status = 1 AND name LIKE ? ORDER BY hot_score DESC LIMIT ?"))
	return out, nil
}

// ---- Meilisearch 同步:增量拉取(索引文档) + 按 ID 保序回表 ----

// IndexDoc 送入搜索引擎的轻文档(检索字段+过滤字段+排序字段)。
type IndexDoc = map[string]any

const pullBatch = 5000

// PullPostDocs 帖子增量:updated_at 水位,全状态入索引(下架/删除靠查询侧 status 过滤隐藏)。
func (m *SearchModel) PullPostDocs(ctx context.Context, since string) ([]IndexDoc, string, error) {
	var rows []struct {
		ID         int64  `db:"id"`
		Title      string `db:"title"`
		Content    string `db:"content"`
		Status     int64  `db:"status"`
		Visibility int64  `db:"visibility"`
		HotScore   int64  `db:"hot_score"`
		UpdatedAt  string `db:"updated_at"`
	}
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, title, content, status, visibility, hot_score, DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i:%s.%f') AS updated_at FROM `post` WHERE updated_at > ? ORDER BY updated_at LIMIT ?",
		since, pullBatch)
	if err != nil {
		return nil, since, err
	}
	docs := make([]IndexDoc, 0, len(rows))
	next := since
	for _, r := range rows {
		docs = append(docs, IndexDoc{
			"id": r.ID, "title": r.Title, "content": r.Content,
			"status": r.Status, "visibility": r.Visibility, "hotScore": r.HotScore,
		})
		next = r.UpdatedAt
	}
	return docs, next, nil
}

// PullUserDocs 用户增量:updated_at 水位。
func (m *SearchModel) PullUserDocs(ctx context.Context, since string) ([]IndexDoc, string, error) {
	var rows []struct {
		ID        int64  `db:"id"`
		Nickname  string `db:"nickname"`
		DisplayNo string `db:"display_no"`
		Level     int64  `db:"level"`
		Status    int64  `db:"status"`
		UpdatedAt string `db:"updated_at"`
	}
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, nickname, COALESCE(display_no, '') AS display_no, level, status, DATE_FORMAT(updated_at, '%Y-%m-%d %H:%i:%s.%f') AS updated_at FROM `user` WHERE updated_at > ? ORDER BY updated_at LIMIT ?",
		since, pullBatch)
	if err != nil {
		return nil, since, err
	}
	docs := make([]IndexDoc, 0, len(rows))
	next := since
	for _, r := range rows {
		docs = append(docs, IndexDoc{
			"id": r.ID, "nickname": r.Nickname, "displayNo": r.DisplayNo,
			"level": r.Level, "status": r.Status,
		})
		next = r.UpdatedAt
	}
	return docs, next, nil
}

// PullCircleDocs / PullSoftwareDocs / PullTopicDocs 运营实体表(千级)每轮全量 upsert。
func (m *SearchModel) PullCircleDocs(ctx context.Context) ([]IndexDoc, error) {
	var rows []struct {
		ID       int64  `db:"id"`
		Name     string `db:"name"`
		Intro    string `db:"intro"`
		Status   int64  `db:"status"`
		HotScore int64  `db:"hot_score"`
	}
	if err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, intro, status, hot_score FROM `circle` LIMIT ?", pullBatch); err != nil {
		return nil, err
	}
	docs := make([]IndexDoc, 0, len(rows))
	for _, r := range rows {
		docs = append(docs, IndexDoc{"id": r.ID, "name": r.Name, "intro": r.Intro, "status": r.Status, "hotScore": r.HotScore})
	}
	return docs, nil
}

func (m *SearchModel) PullSoftwareDocs(ctx context.Context) ([]IndexDoc, error) {
	var rows []struct {
		ID            int64  `db:"id"`
		Name          string `db:"name"`
		Intro         string `db:"intro"`
		Status        int64  `db:"status"`
		DownloadCount int64  `db:"download_count"`
	}
	if err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, intro, status, download_count FROM `software` LIMIT ?", pullBatch); err != nil {
		return nil, err
	}
	docs := make([]IndexDoc, 0, len(rows))
	for _, r := range rows {
		docs = append(docs, IndexDoc{"id": r.ID, "name": r.Name, "intro": r.Intro, "status": r.Status, "downloadCount": r.DownloadCount})
	}
	return docs, nil
}

func (m *SearchModel) PullTopicDocs(ctx context.Context) ([]IndexDoc, error) {
	var rows []struct {
		ID        int64  `db:"id"`
		Name      string `db:"name"`
		Status    int64  `db:"status"`
		HotScore  int64  `db:"hot_score"`
		PostCount int64  `db:"post_count"`
	}
	if err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, status, hot_score, post_count FROM `topic` LIMIT ?", pullBatch); err != nil {
		return nil, err
	}
	docs := make([]IndexDoc, 0, len(rows))
	for _, r := range rows {
		docs = append(docs, IndexDoc{"id": r.ID, "name": r.Name, "status": r.Status, "hotScore": r.HotScore, "postCount": r.PostCount})
	}
	return docs, nil
}

// inPlaceholders 生成 IN (?,?,...) 与参数。
func inPlaceholders(ids []int64) (string, []any) {
	ph := make([]string, len(ids))
	args := make([]any, len(ids))
	for i, id := range ids {
		ph[i], args[i] = "?", id
	}
	return strings.Join(ph, ","), args
}

// PostsByIDs 按 ID 批量回表,返回顺序与 ids 一致(保持引擎相关性排序)。
func (m *SearchModel) PostsByIDs(ctx context.Context, ids []int64) ([]*Post, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	ph, args := inPlaceholders(ids)
	var rows []*Post
	q := fmt.Sprintf("SELECT %s FROM `post` WHERE id IN (%s)", postCols, ph)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return sortByIDs(rows, ids, func(p *Post) int64 { return p.ID }), nil
}

func (m *SearchModel) UsersByIDs(ctx context.Context, ids []int64) ([]*UserBrief, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	ph, args := inPlaceholders(ids)
	var rows []*UserBrief
	q := fmt.Sprintf("SELECT id, display_no, nickname, avatar, level FROM `user` WHERE id IN (%s)", ph)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return sortByIDs(rows, ids, func(u *UserBrief) int64 { return u.ID }), nil
}

func (m *SearchModel) CirclesByIDs(ctx context.Context, ids []int64) ([]*Circle, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	ph, args := inPlaceholders(ids)
	var rows []*Circle
	q := fmt.Sprintf("SELECT %s FROM `circle` WHERE id IN (%s)", circleCols, ph)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return sortByIDs(rows, ids, func(c *Circle) int64 { return c.ID }), nil
}

func (m *SearchModel) SoftwareByIDs(ctx context.Context, ids []int64) ([]*Software, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	ph, args := inPlaceholders(ids)
	var rows []*Software
	q := fmt.Sprintf("SELECT %s FROM `software` WHERE id IN (%s)", softwareCols, ph)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return sortByIDs(rows, ids, func(s *Software) int64 { return s.ID }), nil
}

func (m *SearchModel) TopicsByIDs(ctx context.Context, ids []int64) ([]*Topic, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	ph, args := inPlaceholders(ids)
	var rows []*Topic
	q := fmt.Sprintf("SELECT id, name, post_count FROM `topic` WHERE id IN (%s)", ph)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return sortByIDs(rows, ids, func(t *Topic) int64 { return t.ID }), nil
}

// sortByIDs 按给定 ids 顺序重排(引擎按相关性给序,IN 查询乱序返回)。
func sortByIDs[T any](rows []T, ids []int64, key func(T) int64) []T {
	byID := make(map[int64]T, len(rows))
	for _, r := range rows {
		byID[key(r)] = r
	}
	out := make([]T, 0, len(rows))
	for _, id := range ids {
		if r, ok := byID[id]; ok {
			out = append(out, r)
		}
	}
	return out
}
