// Package homelogic 首页配置:公告 Banner + 置顶精选横条。
package homelogic

import (
	"context"
	"fmt"

	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"
)

const (
	maxBanners  = 10
	maxTopPosts = 5
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

func (l *Logic) Config(ctx context.Context) (*types.HomeConfigResp, error) {
	banners, err := l.svcCtx.BannerModel.ListOnline(ctx, maxBanners)
	if err != nil {
		return nil, fmt.Errorf("banner list: %w", err)
	}
	tops, err := l.svcCtx.PostModel.ListTop(ctx, maxTopPosts)
	if err != nil {
		return nil, fmt.Errorf("top posts: %w", err)
	}
	resp := &types.HomeConfigResp{
		Banners:  make([]types.BannerItem, 0, len(banners)),
		TopPosts: make([]types.TopPostItem, 0, len(tops)),
	}
	for _, b := range banners {
		resp.Banners = append(resp.Banners, types.BannerItem{
			ID: b.ID, Title: b.Title, Image: b.Image,
			LinkType: b.LinkType, LinkValue: b.LinkValue,
		})
	}
	for _, p := range tops {
		title := p.Title
		if title == "" {
			r := []rune(p.Content)
			if len(r) > 20 {
				r = r[:20]
			}
			title = string(r)
		}
		resp.TopPosts = append(resp.TopPosts, types.TopPostItem{PostID: p.ID, Title: title})
	}
	return resp, nil
}
