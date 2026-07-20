// Meilisearch 驱动:查询走引擎(中文分词/错字容忍/相关性),命中 ID 回 MySQL 取整行,
// 五域 decorate 逻辑零改动;引擎故障时自动降级回 MySQL LIKE,搜索不因外部组件不可用而中断。
// 写路径不侵入业务:SyncDaemon 水位增量(帖/用户按 updated_at)+ 小表全量 upsert,
// 下架/删除等状态变化随 upsert 带入文档,查询侧 Filter 过滤,无需 delete 同步。
package search

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
	"unicode"

	"github.com/meilisearch/meilisearch-go"
	"github.com/yiora/server/internal/model"

	"github.com/zeromicro/go-zero/core/logx"
)

const (
	idxPosts    = "posts"
	idxUsers    = "users"
	idxCircles  = "circles"
	idxSoftware = "software"
	idxTopics   = "topics"
)

type Meili struct {
	client meilisearch.ServiceManager
	db     *model.SearchModel // 回表 + 降级
}

// NewMeili 构造驱动并确保各索引 settings(幂等,可重复执行)。
// compose 同启时 meili 可能晚于 api 就绪,健康检查带 30s 重试。
func NewMeili(host, apiKey string, db *model.SearchModel) (*Meili, error) {
	m := &Meili{client: meilisearch.New(host, meilisearch.WithAPIKey(apiKey)), db: db}
	var err error
	for i := 0; i < 15; i++ {
		if _, err = m.client.Health(); err == nil {
			break
		}
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		return nil, fmt.Errorf("meilisearch unreachable at %s: %w", host, err)
	}
	if err := m.ensureIndexes(); err != nil {
		return nil, err
	}
	return m, nil
}

// ensureIndexes 索引 settings:可搜字段对齐 LIKE 字段,过滤字段承担原 WHERE,排序规则插静态热度。
func (m *Meili) ensureIndexes() error {
	type idxCfg struct {
		uid        string
		searchable []string
		filterable []string
		ranking    []string
	}
	base := []string{"words", "typo", "proximity", "attribute", "exactness"}
	cfgs := []idxCfg{
		{idxPosts, []string{"title", "content"}, []string{"status", "visibility"}, append(base, "hotScore:desc")},
		{idxUsers, []string{"nickname", "displayNo"}, []string{"status"}, append(base, "level:desc")},
		{idxCircles, []string{"name", "intro"}, []string{"status"}, append(base, "hotScore:desc")},
		{idxSoftware, []string{"name", "intro"}, []string{"status"}, append(base, "downloadCount:desc")},
		{idxTopics, []string{"name"}, []string{"status"}, append(base, "hotScore:desc")},
	}
	for _, c := range cfgs {
		if _, err := m.client.Index(c.uid).UpdateSettings(&meilisearch.Settings{
			SearchableAttributes: c.searchable,
			FilterableAttributes: c.filterable,
			RankingRules:         c.ranking,
		}); err != nil {
			return fmt.Errorf("meili settings %s: %w", c.uid, err)
		}
	}
	return nil
}

// hasSearchableRune 无字母/数字/汉字的查询(如纯符号 "%%")在 meili 里等价空查询会 match-all,
// 与 LIKE 语义(转义后零命中)不一致,直接判零结果。
func hasSearchableRune(s string) bool {
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return true
		}
	}
	return false
}

// searchIDs 查询引擎取命中 ID(相关性序)。
func (m *Meili) searchIDs(ctx context.Context, index, kw, filter string, offset, limit int) ([]int64, error) {
	if !hasSearchableRune(kw) {
		return nil, nil
	}
	resp, err := m.client.Index(index).SearchWithContext(ctx, kw, &meilisearch.SearchRequest{
		Offset: int64(offset), Limit: int64(limit),
		Filter:               filter,
		AttributesToRetrieve: []string{"id"},
	})
	if err != nil {
		return nil, err
	}
	ids := make([]int64, 0, len(resp.Hits))
	for _, h := range resp.Hits {
		var id int64
		if raw, ok := h["id"]; ok && json.Unmarshal(raw, &id) == nil {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

func (m *Meili) SearchPosts(ctx context.Context, kw string, offset, limit int) ([]*model.Post, error) {
	ids, err := m.searchIDs(ctx, idxPosts, kw, "status = 1 AND visibility = 0", offset, limit)
	if err != nil {
		logx.WithContext(ctx).Errorf("meili posts fallback to LIKE: %v", err)
		return m.db.SearchPosts(ctx, kw, offset, limit)
	}
	return m.db.PostsByIDs(ctx, ids)
}

func (m *Meili) SearchUsers(ctx context.Context, kw string, offset, limit int) ([]*model.UserBrief, error) {
	ids, err := m.searchIDs(ctx, idxUsers, kw, "status != 4", offset, limit)
	if err != nil {
		logx.WithContext(ctx).Errorf("meili users fallback to LIKE: %v", err)
		return m.db.SearchUsers(ctx, kw, offset, limit)
	}
	return m.db.UsersByIDs(ctx, ids)
}

func (m *Meili) SearchCircles(ctx context.Context, kw string, offset, limit int) ([]*model.Circle, error) {
	ids, err := m.searchIDs(ctx, idxCircles, kw, "status = 1", offset, limit)
	if err != nil {
		logx.WithContext(ctx).Errorf("meili circles fallback to LIKE: %v", err)
		return m.db.SearchCircles(ctx, kw, offset, limit)
	}
	return m.db.CirclesByIDs(ctx, ids)
}

func (m *Meili) SearchSoftware(ctx context.Context, kw string, offset, limit int) ([]*model.Software, error) {
	ids, err := m.searchIDs(ctx, idxSoftware, kw, fmt.Sprintf("status = %d", model.SoftwareStatusOnline), offset, limit)
	if err != nil {
		logx.WithContext(ctx).Errorf("meili software fallback to LIKE: %v", err)
		return m.db.SearchSoftware(ctx, kw, offset, limit)
	}
	return m.db.SoftwareByIDs(ctx, ids)
}

func (m *Meili) SearchTopics(ctx context.Context, kw string, offset, limit int) ([]*model.Topic, error) {
	ids, err := m.searchIDs(ctx, idxTopics, kw, "status = 1", offset, limit)
	if err != nil {
		logx.WithContext(ctx).Errorf("meili topics fallback to LIKE: %v", err)
		return m.db.SearchTopics(ctx, kw, offset, limit)
	}
	return m.db.TopicsByIDs(ctx, ids)
}

// Suggest 前缀即时搜联想:四域(帖标题/软件名/圈名/话题名)各取若干,带 <em> 高亮片段。
func (m *Meili) Suggest(ctx context.Context, kw string, limit int) ([]model.SuggestItem, error) {
	if !hasSearchableRune(kw) {
		return nil, nil
	}
	type domain struct {
		index  string
		typ    string
		field  string // 联想展示字段
		filter string
	}
	domains := []domain{
		{idxPosts, "post", "title", "status = 1 AND visibility = 0"},
		{idxSoftware, "software", "name", fmt.Sprintf("status = %d", model.SoftwareStatusOnline)},
		{idxCircles, "circle", "name", "status = 1"},
		{idxTopics, "topic", "name", "status = 1"},
	}
	out := make([]model.SuggestItem, 0, limit*len(domains))
	for _, d := range domains {
		resp, err := m.client.Index(d.index).SearchWithContext(ctx, kw, &meilisearch.SearchRequest{
			Limit:                 int64(limit),
			Filter:                d.filter,
			AttributesToRetrieve:  []string{"id", d.field},
			AttributesToHighlight: []string{d.field},
			HighlightPreTag:       "<em>",
			HighlightPostTag:      "</em>",
		})
		if err != nil {
			logx.WithContext(ctx).Errorf("meili suggest %s fallback: %v", d.index, err)
			return m.db.Suggest(ctx, kw, limit) // 引擎故障整体降级前缀 LIKE
		}
		for _, h := range resp.Hits {
			var id int64
			var text string
			if raw, ok := h["id"]; !ok || json.Unmarshal(raw, &id) != nil {
				continue
			}
			if raw, ok := h[d.field]; ok {
				_ = json.Unmarshal(raw, &text)
			}
			if text == "" {
				continue
			}
			highlighted := text
			if raw, ok := h["_formatted"]; ok {
				var fm map[string]json.RawMessage
				if json.Unmarshal(raw, &fm) == nil {
					var hl string
					if fraw, ok := fm[d.field]; ok && json.Unmarshal(fraw, &hl) == nil && hl != "" {
						highlighted = hl
					}
				}
			}
			out = append(out, model.SuggestItem{Type: d.typ, ID: id, Text: text, Highlighted: highlighted})
		}
	}
	return out, nil
}

var _ Searcher = (*Meili)(nil)

// SyncDaemon 增量同步守护:帖子/用户按 updated_at 水位,圈子/软件/话题全量 upsert。
// 进程内跑一个即可(多副本部署时 upsert 幂等,重复同步只是浪费,不会错)。
func (m *Meili) SyncDaemon(interval time.Duration) {
	const epoch = "1970-01-01 00:00:00.000000"
	postMark, userMark := epoch, epoch
	pk := "id"
	upsert := func(index string, docs []model.IndexDoc) {
		if len(docs) == 0 {
			return
		}
		if _, err := m.client.Index(index).AddDocuments(&docs, &meilisearch.DocumentOptions{PrimaryKey: &pk}); err != nil {
			logx.Errorf("meili sync %s: %v", index, err)
		}
	}
	for {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		if docs, next, err := m.db.PullPostDocs(ctx, postMark); err == nil {
			upsert(idxPosts, docs)
			postMark = next
		} else {
			logx.Errorf("meili pull posts: %v", err)
		}
		if docs, next, err := m.db.PullUserDocs(ctx, userMark); err == nil {
			upsert(idxUsers, docs)
			userMark = next
		} else {
			logx.Errorf("meili pull users: %v", err)
		}
		if docs, err := m.db.PullCircleDocs(ctx); err == nil {
			upsert(idxCircles, docs)
		}
		if docs, err := m.db.PullSoftwareDocs(ctx); err == nil {
			upsert(idxSoftware, docs)
		}
		if docs, err := m.db.PullTopicDocs(ctx); err == nil {
			upsert(idxTopics, docs)
		}
		cancel()
		time.Sleep(interval)
	}
}
