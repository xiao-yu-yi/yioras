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
}

// 编译期断言:MySQL 实现满足接口。
var _ Searcher = (*model.SearchModel)(nil)
