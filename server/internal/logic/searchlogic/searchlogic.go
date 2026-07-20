// Package searchlogic 全站搜索:帖子/用户/圈子/软件/话题。
// 底层走 svc.Search(pkg/search.Searcher)抽象,当前为 MySQL LIKE,后续可换 Meilisearch。
package searchlogic

import (
	"context"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/yiora/server/internal/logic/circlelogic"
	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/logic/softwarelogic"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

const maxKwRunes = 50

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Suggest 搜索框联想(前缀即时搜):四域混合,meili 驱动带 <em> 高亮片段。
func (l *Logic) Suggest(ctx context.Context, req *types.SuggestReq) (*types.SuggestResp, error) {
	kw := strings.TrimSpace(req.Kw)
	if kw == "" {
		return nil, xerr.Param("关键词不能为空")
	}
	if utf8.RuneCountInString(kw) > maxKwRunes {
		return nil, xerr.Param("关键词过长")
	}
	items, err := l.svcCtx.Search.Suggest(ctx, kw, 3)
	if err != nil {
		return nil, fmt.Errorf("suggest: %w", err)
	}
	out := make([]types.SuggestItem, 0, len(items))
	for _, it := range items {
		out = append(out, types.SuggestItem{Type: it.Type, ID: it.ID, Text: it.Text, Highlighted: it.Highlighted})
	}
	return &types.SuggestResp{Suggestions: out}, nil
}

// Search 按 type 检索一类结果;uid 用于个性化状态(liked/joined/followed)。
func (l *Logic) Search(ctx context.Context, uid int64, req *types.SearchReq) (*types.SearchResp, error) {
	kw := strings.TrimSpace(req.Kw)
	if kw == "" {
		return nil, xerr.Param("关键词不能为空")
	}
	if utf8.RuneCountInString(kw) > maxKwRunes {
		return nil, xerr.Param("关键词过长")
	}
	offset, limit := req.Offset()
	resp := &types.SearchResp{Type: req.Type}

	switch req.Type {
	case "post":
		rows, err := l.svcCtx.Search.SearchPosts(ctx, kw, offset, limit)
		if err != nil {
			return nil, fmt.Errorf("search posts: %w", err)
		}
		if resp.Posts, err = postlogic.New(l.svcCtx).DecoratePosts(ctx, uid, rows); err != nil {
			return nil, err
		}
	case "user":
		rows, err := l.svcCtx.Search.SearchUsers(ctx, kw, offset, limit)
		if err != nil {
			return nil, fmt.Errorf("search users: %w", err)
		}
		ids := make([]int64, 0, len(rows))
		for _, u := range rows {
			ids = append(ids, u.ID)
		}
		followed, err := l.svcCtx.RelationModel.FollowedSet(ctx, uid, ids)
		if err != nil {
			return nil, fmt.Errorf("followed set: %w", err)
		}
		resp.Users = make([]types.RelationUserItem, 0, len(rows))
		for _, u := range rows {
			resp.Users = append(resp.Users, types.RelationUserItem{
				UserBrief: postlogic.ToUserBrief(u.ID, u),
				Followed:  followed[u.ID],
			})
		}
	case "circle":
		rows, err := l.svcCtx.Search.SearchCircles(ctx, kw, offset, limit)
		if err != nil {
			return nil, fmt.Errorf("search circles: %w", err)
		}
		if resp.Circles, err = circlelogic.New(l.svcCtx).DecorateCircles(ctx, uid, rows); err != nil {
			return nil, err
		}
	case "software":
		rows, err := l.svcCtx.Search.SearchSoftware(ctx, kw, offset, limit)
		if err != nil {
			return nil, fmt.Errorf("search software: %w", err)
		}
		if resp.Software, err = softwarelogic.New(l.svcCtx).DecorateSoftware(ctx, rows); err != nil {
			return nil, err
		}
	case "topic":
		rows, err := l.svcCtx.Search.SearchTopics(ctx, kw, offset, limit)
		if err != nil {
			return nil, fmt.Errorf("search topics: %w", err)
		}
		resp.Topics = make([]types.TopicItem, 0, len(rows))
		for _, t := range rows {
			resp.Topics = append(resp.Topics, types.TopicItem{ID: t.ID, Name: t.Name, PostCount: t.PostCount})
		}
	}
	return resp, nil
}
