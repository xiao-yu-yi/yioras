package model

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 帖子状态
const (
	PostStatusPending   = 0
	PostStatusPublished = 1
	PostStatusRejected  = 2
	PostStatusTakenDown = 3
	PostStatusDeleted   = 4
)

type (
	Post struct {
		ID            int64     `db:"id"`
		UserID        int64     `db:"user_id"`
		CircleID      int64     `db:"circle_id"`
		Title         string    `db:"title"`
		Content       string    `db:"content"`
		LinkType      int64     `db:"link_type"`
		LinkURL       string    `db:"link_url"`
		Visibility    int64     `db:"visibility"`
		Status        int64     `db:"status"`
		RejectReason  string    `db:"reject_reason"`
		IsTop         int64     `db:"is_top"`
		IsEssence     int64     `db:"is_essence"`
		CircleTop     int64     `db:"circle_top"`
		ViewCount     int64     `db:"view_count"`
		LikeCount     int64     `db:"like_count"`
		CommentCount  int64     `db:"comment_count"`
		FavoriteCount int64     `db:"favorite_count"`
		HotScore      int64     `db:"hot_score"`
		CreatedAt     time.Time `db:"created_at"`
		UpdatedAt     time.Time `db:"updated_at"`
	}

	PostImage struct {
		ID     int64  `db:"id"`
		PostID int64  `db:"post_id"`
		URL    string `db:"url"`
		Width  int64  `db:"width"`
		Height int64  `db:"height"`
		Sort   int64  `db:"sort"`
	}

	PostModel struct{ conn sqlx.SqlConn }
)

const postCols = "id, user_id, circle_id, title, content, link_type, link_url, visibility, status, reject_reason, is_top, is_essence, circle_top, view_count, like_count, comment_count, favorite_count, hot_score, created_at, updated_at"

// postColsP 带 p. 前缀的列清单(join 查询用)。
const postColsP = "p.id, p.user_id, p.circle_id, p.title, p.content, p.link_type, p.link_url, p.visibility, p.status, p.reject_reason, p.is_top, p.is_essence, p.circle_top, p.view_count, p.like_count, p.comment_count, p.favorite_count, p.hot_score, p.created_at, p.updated_at"

func NewPostModel(conn sqlx.SqlConn) *PostModel { return &PostModel{conn: conn} }

// CreateExtra 发帖附加内容:付费段/话题/共创邀请。
type CreateExtra struct {
	PaidPrice   int64
	PaidContent string
	TopicIDs    []int64
	Cocreators  []int64 // 共创邀请对象(待确认)
}

// Create 发帖:帖子+图片+付费段+话题+共创邀请+圈子计数同事务;status 由审核策略决定(待审/直发)。
func (m *PostModel) Create(ctx context.Context, p *Post, images []PostImage, extra CreateExtra) (int64, error) {
	var postID int64
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT INTO `post` (user_id, circle_id, title, content, link_type, link_url, visibility, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
			p.UserID, p.CircleID, p.Title, p.Content, p.LinkType, p.LinkURL, p.Visibility, p.Status)
		if err != nil {
			return fmt.Errorf("insert post: %w", err)
		}
		if postID, err = r.LastInsertId(); err != nil {
			return fmt.Errorf("post id: %w", err)
		}
		if extra.PaidPrice > 0 {
			if err = CreatePaidContentIn(ctx, s, postID, extra.PaidPrice, extra.PaidContent); err != nil {
				return err
			}
		}
		if err = BindPostTopicsIn(ctx, s, postID, extra.TopicIDs, p.Status == PostStatusPublished); err != nil {
			return err
		}
		if err = InviteCocreatorsIn(ctx, s, postID, extra.Cocreators); err != nil {
			return err
		}
		for _, img := range images {
			if _, err = s.ExecCtx(ctx,
				"INSERT INTO `post_image` (post_id, url, width, height, sort) VALUES (?, ?, ?, ?, ?)",
				postID, img.URL, img.Width, img.Height, img.Sort); err != nil {
				return fmt.Errorf("insert image: %w", err)
			}
		}
		if p.Status == PostStatusPublished {
			if _, err = s.ExecCtx(ctx,
				"UPDATE `circle` SET post_count = post_count + 1 WHERE id = ?", p.CircleID); err != nil {
				return fmt.Errorf("circle post count: %w", err)
			}
		}
		return nil
	})
	return postID, err
}

// Update 编辑帖子:更新主体 + 重建图片/话题(旧话题计数回减、新话题按状态累加),同事务。
// newStatus 由编辑后的机审结果决定(疑似词重回待审)。
func (m *PostModel) Update(ctx context.Context, p *Post, newStatus int64, images []PostImage, topicIDs []int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		wasPublished := p.Status == PostStatusPublished
		if _, err := s.ExecCtx(ctx,
			"UPDATE `post` SET title = ?, content = ?, link_type = ?, link_url = ?, status = ? WHERE id = ?",
			p.Title, p.Content, p.LinkType, p.LinkURL, newStatus, p.ID); err != nil {
			return fmt.Errorf("update post: %w", err)
		}
		// 可见性变化时圈子计数双向同步
		if wasPublished && newStatus != PostStatusPublished {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `circle` SET post_count = GREATEST(post_count - 1, 0) WHERE id = ?", p.CircleID); err != nil {
				return fmt.Errorf("circle count: %w", err)
			}
		}
		if !wasPublished && newStatus == PostStatusPublished {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `circle` SET post_count = post_count + 1 WHERE id = ?", p.CircleID); err != nil {
				return fmt.Errorf("circle count: %w", err)
			}
		}
		// 重建话题:旧绑定计数回减(仅原已发布),再按新状态绑定
		if wasPublished {
			if _, err := s.ExecCtx(ctx,
				`UPDATE topic t JOIN post_topic pt ON pt.topic_id = t.id
				 SET t.post_count = GREATEST(t.post_count - 1, 0) WHERE pt.post_id = ?`, p.ID); err != nil {
				return fmt.Errorf("old topic count: %w", err)
			}
		}
		if _, err := s.ExecCtx(ctx, "DELETE FROM `post_topic` WHERE post_id = ?", p.ID); err != nil {
			return fmt.Errorf("clear topics: %w", err)
		}
		if err := BindPostTopicsIn(ctx, s, p.ID, topicIDs, newStatus == PostStatusPublished); err != nil {
			return err
		}
		// 重建图片
		if _, err := s.ExecCtx(ctx, "DELETE FROM `post_image` WHERE post_id = ?", p.ID); err != nil {
			return fmt.Errorf("clear images: %w", err)
		}
		for _, img := range images {
			if _, err := s.ExecCtx(ctx,
				"INSERT INTO `post_image` (post_id, url, width, height, sort) VALUES (?, ?, ?, ?, ?)",
				p.ID, img.URL, img.Width, img.Height, img.Sort); err != nil {
				return fmt.Errorf("insert image: %w", err)
			}
		}
		return nil
	})
}

func (m *PostModel) FindByID(ctx context.Context, id int64) (*Post, error) {
	var p Post
	q := fmt.Sprintf("SELECT %s FROM `post` WHERE id = ? LIMIT 1", postCols)
	if err := m.conn.QueryRowCtx(ctx, &p, q, id); err != nil {
		return nil, err
	}
	return &p, nil
}

// ListFeed 推荐流(单列表):置顶精选优先+热度分,同分新帖在前。
func (m *PostModel) ListFeed(ctx context.Context, offset, limit int) ([]*Post, error) {
	var rows []*Post
	q := fmt.Sprintf(
		"SELECT %s FROM `post` WHERE status = %d AND visibility = 0 ORDER BY is_top DESC, hot_score DESC, id DESC LIMIT ?, ?",
		postCols, PostStatusPublished)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// ListByCircle 圈内信息流。圈内置顶>加精>排序维度(需求 3.4)。sort: new|hot。
func (m *PostModel) ListByCircle(ctx context.Context, circleID int64, sort string, offset, limit int) ([]*Post, error) {
	order := "id DESC"
	if sort == "hot" {
		order = "hot_score DESC, id DESC"
	}
	var rows []*Post
	q := fmt.Sprintf(
		"SELECT %s FROM `post` WHERE circle_id = ? AND status = %d AND visibility = 0 ORDER BY circle_top DESC, is_essence DESC, %s LIMIT ?, ?",
		postCols, PostStatusPublished, order)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, circleID, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// ListTop 首页置顶精选横条(运营置顶,按热度排序)。
func (m *PostModel) ListTop(ctx context.Context, limit int) ([]*Post, error) {
	var rows []*Post
	q := fmt.Sprintf(
		"SELECT %s FROM `post` WHERE status = %d AND visibility = 0 AND is_top = 1 ORDER BY hot_score DESC, id DESC LIMIT ?",
		postCols, PostStatusPublished)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// AuthorStats 主页数据栏:已发布帖子数与获赞总数(帖子维度)。
func (m *PostModel) AuthorStats(ctx context.Context, uid int64) (posts, likes int64, err error) {
	var row struct {
		Posts int64 `db:"posts"`
		Likes int64 `db:"likes"`
	}
	err = m.conn.QueryRowCtx(ctx, &row, fmt.Sprintf(
		"SELECT COUNT(1) AS posts, CAST(COALESCE(SUM(like_count), 0) AS SIGNED) AS likes FROM `post` WHERE user_id = ? AND status = %d",
		PostStatusPublished), uid)
	if err != nil {
		return 0, 0, err
	}
	return row.Posts, row.Likes, nil
}

// ListByAuthor 个人主页作品(含已确认共创帖,共创双方主页均展示)。
// self=true 时包含待审/驳回帖(仅自己可见状态)。
func (m *PostModel) ListByAuthor(ctx context.Context, authorID int64, self bool, offset, limit int) ([]*Post, error) {
	cond := fmt.Sprintf("status = %d AND visibility = 0", PostStatusPublished)
	if self {
		cond = fmt.Sprintf("status IN (%d, %d, %d)", PostStatusPending, PostStatusPublished, PostStatusRejected)
	}
	var rows []*Post
	q := fmt.Sprintf(
		`SELECT %s FROM `+"`post`"+` WHERE (user_id = ? OR EXISTS (
		   SELECT 1 FROM post_cocreator pc WHERE pc.post_id = post.id AND pc.user_id = ? AND pc.status = %d
		 )) AND %s ORDER BY id DESC LIMIT ?, ?`, postCols, CocreatorAccepted, cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, authorID, authorID, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// ImagesOf 批量取帖子图片,返回 postID -> images(按 sort 排序)。
func (m *PostModel) ImagesOf(ctx context.Context, postIDs []int64) (map[int64][]PostImage, error) {
	out := make(map[int64][]PostImage, len(postIDs))
	if len(postIDs) == 0 {
		return out, nil
	}
	q, args := inQuery("SELECT id, post_id, url, width, height, sort FROM `post_image` WHERE post_id IN (%s) ORDER BY post_id, sort", postIDs)
	var rows []PostImage
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, img := range rows {
		out[img.PostID] = append(out[img.PostID], img)
	}
	return out, nil
}

func (m *PostModel) IncrView(ctx context.Context, id int64, delta int64) error {
	_, err := m.conn.ExecCtx(ctx, "UPDATE `post` SET view_count = view_count + ? WHERE id = ?", delta, id)
	return err
}

// SoftDelete 作者删帖。WHERE 带 user_id 防越权;已发布帖同事务回减圈子/话题计数。
func (m *PostModel) SoftDelete(ctx context.Context, id, uid int64) (bool, error) {
	var hit bool
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var row struct {
			Status   int64 `db:"status"`
			CircleID int64 `db:"circle_id"`
		}
		err := s.QueryRowCtx(ctx, &row,
			"SELECT status, circle_id FROM `post` WHERE id = ? AND user_id = ? LIMIT 1 FOR UPDATE", id, uid)
		if err != nil {
			if IsNotFound(err) {
				return nil // 不存在或非本人,hit=false
			}
			return fmt.Errorf("load post: %w", err)
		}
		if row.Status == PostStatusDeleted {
			return nil
		}
		if _, err = s.ExecCtx(ctx,
			"UPDATE `post` SET status = ? WHERE id = ?", PostStatusDeleted, id); err != nil {
			return fmt.Errorf("delete post: %w", err)
		}
		if row.Status == PostStatusPublished {
			if _, err = s.ExecCtx(ctx,
				"UPDATE `circle` SET post_count = GREATEST(post_count - 1, 0) WHERE id = ?", row.CircleID); err != nil {
				return fmt.Errorf("circle post count: %w", err)
			}
			if _, err = s.ExecCtx(ctx,
				`UPDATE topic t JOIN post_topic pt ON pt.topic_id = t.id
				 SET t.post_count = GREATEST(t.post_count - 1, 0) WHERE pt.post_id = ?`, id); err != nil {
				return fmt.Errorf("topic post count: %w", err)
			}
		}
		hit = true
		return nil
	})
	return hit, err
}

// SetCircleTop 圈内置顶/取消(圈主管理)。仅已发布帖且属于该圈。
func (m *PostModel) SetCircleTop(ctx context.Context, circleID, postID int64, top bool) (bool, error) {
	v := 0
	if top {
		v = 1
	}
	r, err := m.conn.ExecCtx(ctx, fmt.Sprintf(
		"UPDATE `post` SET circle_top = ? WHERE id = ? AND circle_id = ? AND status = %d", PostStatusPublished),
		v, postID, circleID)
	if err != nil {
		return false, fmt.Errorf("set circle top: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// SetEssence 圈内加精/取消(圈主管理)。
func (m *PostModel) SetEssence(ctx context.Context, circleID, postID int64, essence bool) (bool, error) {
	v := 0
	if essence {
		v = 1
	}
	r, err := m.conn.ExecCtx(ctx, fmt.Sprintf(
		"UPDATE `post` SET is_essence = ? WHERE id = ? AND circle_id = ? AND status = %d", PostStatusPublished),
		v, postID, circleID)
	if err != nil {
		return false, fmt.Errorf("set essence: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// Takedown 圈管理下架帖(status=3,与作者删除区分),回减计数并返回作者(通知用)。
func (m *PostModel) Takedown(ctx context.Context, circleID, postID int64) (authorID int64, hit bool, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var row struct {
			UserID int64 `db:"user_id"`
			Status int64 `db:"status"`
		}
		err := s.QueryRowCtx(ctx, &row,
			"SELECT user_id, status FROM `post` WHERE id = ? AND circle_id = ? LIMIT 1 FOR UPDATE", postID, circleID)
		if err != nil {
			if IsNotFound(err) {
				return nil
			}
			return fmt.Errorf("load post: %w", err)
		}
		if row.Status != PostStatusPublished {
			return nil
		}
		if _, err = s.ExecCtx(ctx,
			"UPDATE `post` SET status = ?, circle_top = 0, is_essence = 0 WHERE id = ?", PostStatusTakenDown, postID); err != nil {
			return fmt.Errorf("takedown post: %w", err)
		}
		if _, err = s.ExecCtx(ctx,
			"UPDATE `circle` SET post_count = GREATEST(post_count - 1, 0) WHERE id = ?", circleID); err != nil {
			return fmt.Errorf("circle post count: %w", err)
		}
		if _, err = s.ExecCtx(ctx,
			`UPDATE topic t JOIN post_topic pt ON pt.topic_id = t.id
			 SET t.post_count = GREATEST(t.post_count - 1, 0) WHERE pt.post_id = ?`, postID); err != nil {
			return fmt.Errorf("topic post count: %w", err)
		}
		authorID, hit = row.UserID, true
		return nil
	})
	return authorID, hit, err
}

// ListHistory 我的足迹(按最近浏览,仅已发布帖)。
func (m *PostModel) ListHistory(ctx context.Context, uid int64, offset, limit int) ([]*Post, error) {
	var rows []*Post
	q := fmt.Sprintf(
		`SELECT %s FROM view_history vh JOIN post p ON p.id = vh.post_id
		 WHERE vh.user_id = ? AND p.status = %d AND p.visibility = 0
		 ORDER BY vh.viewed_at DESC LIMIT ?, ?`, postColsP, PostStatusPublished)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, uid, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// ClearHistory 清空足迹(需求 3.8:仅自己可见,可清空)。
func (m *PostModel) ClearHistory(ctx context.Context, uid int64) error {
	if _, err := m.conn.ExecCtx(ctx, "DELETE FROM `view_history` WHERE user_id = ?", uid); err != nil {
		return fmt.Errorf("clear history: %w", err)
	}
	return nil
}

// ListFavorites 我的收藏(按收藏时间倒序,仅已发布帖)。
func (m *PostModel) ListFavorites(ctx context.Context, uid int64, offset, limit int) ([]*Post, error) {
	var rows []*Post
	q := fmt.Sprintf(
		`SELECT %s FROM favorite f JOIN post p ON p.id = f.post_id
		 WHERE f.user_id = ? AND p.status = %d AND p.visibility = 0
		 ORDER BY f.id DESC LIMIT ?, ?`, postColsP, PostStatusPublished)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, uid, offset, limit); err != nil {
		return nil, err
	}
	return rows, nil
}

// UpsertViewHistory 足迹:同帖只更新时间。
func (m *PostModel) UpsertViewHistory(ctx context.Context, uid, postID int64) error {
	_, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `view_history` (user_id, post_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE viewed_at = NOW(3)",
		uid, postID)
	return err
}
