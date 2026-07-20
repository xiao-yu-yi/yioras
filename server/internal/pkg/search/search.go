// Package search 全站搜索抽象。
// 一期由 model.SearchModel(MySQL LIKE)实现;数据量增长后接 Meilisearch:
// 新建 meili.Client 实现本接口,替换 svc.ServiceContext 装配即可,logic 层零改动。
package search

import (
	"context"

	"github.com/yiora/server/internal/model"
)

type Searcher interface {
	SearchPosts(ctx context.Context, kw string, offset, limit int) ([]*model.Post, error)
	SearchUsers(ctx context.Context, kw string, offset, limit int) ([]*model.UserBrief, error)
	SearchCircles(ctx context.Context, kw string, offset, limit int) ([]*model.Circle, error)
	SearchSoftware(ctx context.Context, kw string, offset, limit int) ([]*model.Software, error)
	SearchTopics(ctx context.Context, kw string, offset, limit int) ([]*model.Topic, error)
	// Suggest 搜索联想:帖/软件/圈子/话题混合,meili 驱动带 <em> 高亮片段,mysql 驱动为前缀命中原文。
	Suggest(ctx context.Context, kw string, limit int) ([]model.SuggestItem, error)
}

// 编译期断言:MySQL 实现满足接口。
var _ Searcher = (*model.SearchModel)(nil)
