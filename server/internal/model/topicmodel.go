package model

import (
	"context"
	"fmt"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// TopicModel 话题:find-or-create、帖子关联、聚合页。
type TopicModel struct{ conn sqlx.SqlConn }

func NewTopicModel(conn sqlx.SqlConn) *TopicModel { return &TopicModel{conn: conn} }

// EnsureTopics find-or-create 一组话题名,返回按入参顺序的话题 ID。
// uk_name 兜底并发同名创建。
func (m *TopicModel) EnsureTopics(ctx context.Context, names []string) ([]int64, error) {
	ids := make([]int64, 0, len(names))
	for _, name := range names {
		if _, err := m.conn.ExecCtx(ctx,
			"INSERT IGNORE INTO `topic` (name) VALUES (?)", name); err != nil {
			return nil, fmt.Errorf("ensure topic %q: %w", name, err)
		}
		var id int64
		if err := m.conn.QueryRowCtx(ctx, &id,
			"SELECT id FROM `topic` WHERE name = ? LIMIT 1", name); err != nil {
			return nil, fmt.Errorf("find topic %q: %w", name, err)
		}
		ids = append(ids, id)
	}
	return ids, nil
}

// BindPostTopicsIn 事务内绑定帖子话题;已发布帖同时累加话题帖子数。
func BindPostTopicsIn(ctx context.Context, s sqlx.Session, postID int64, topicIDs []int64, published bool) error {
	for _, tid := range topicIDs {
		if _, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `post_topic` (post_id, topic_id) VALUES (?, ?)", postID, tid); err != nil {
			return fmt.Errorf("bind topic %d: %w", tid, err)
		}
		if published {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `topic` SET post_count = post_count + 1 WHERE id = ?", tid); err != nil {
				return fmt.Errorf("topic count %d: %w", tid, err)
			}
		}
	}
	return nil
}

// FindByID 话题详情(启用中)。
func (m *TopicModel) FindByID(ctx context.Context, id int64) (*Topic, error) {
	var t Topic
	err := m.conn.QueryRowCtx(ctx, &t,
		"SELECT id, name, post_count FROM `topic` WHERE id = ? AND status = 1 LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// TopicsOfPosts 批量取帖子话题,返回 postID -> topics。
func (m *TopicModel) TopicsOfPosts(ctx context.Context, postIDs []int64) (map[int64][]*Topic, error) {
	out := make(map[int64][]*Topic, len(postIDs))
	if len(postIDs) == 0 {
		return out, nil
	}
	type row struct {
		PostID    int64  `db:"post_id"`
		ID        int64  `db:"id"`
		Name      string `db:"name"`
		PostCount int64  `db:"post_count"`
	}
	q, args := inQuery(
		`SELECT pt.post_id, t.id, t.name, t.post_count FROM post_topic pt
		 JOIN topic t ON t.id = pt.topic_id AND t.status = 1
		 WHERE pt.post_id IN (%s) ORDER BY pt.id`, postIDs)
	var rows []row
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.PostID] = append(out[r.PostID], &Topic{ID: r.ID, Name: r.Name, PostCount: r.PostCount})
	}
	return out, nil
}

// PostsByTopic 话题聚合页帖子列表。sort: hot|new。
func (m *TopicModel) PostsByTopic(ctx context.Context, topicID int64, sort string, offset, limit int) ([]*Post, error) {
	order := "p.hot_score DESC, p.id DESC"
	if sort == "new" {
		order = "p.id DESC"
	}
	var rows []*Post
	q := fmt.Sprintf(
		`SELECT %s FROM post_topic pt JOIN post p ON p.id = pt.post_id
		 WHERE pt.topic_id = ? AND p.status = %d AND p.visibility = 0
		 ORDER BY %s LIMIT ?, ?`, postColsP, PostStatusPublished, order)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, topicID, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}
