package handler

import (
	"encoding/json"
	"net/http"

	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/logic/userlogic"
	"github.com/yiora/server/internal/pkg/jwtx"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

// uidFromCtx 取 go-zero JWT 中间件注入的 uid claim(json.Number)。
func uidFromCtx(r *http.Request) (int64, bool) {
	v := r.Context().Value(jwtx.ClaimUID)
	if n, ok := v.(json.Number); ok {
		if uid, err := n.Int64(); err == nil && uid > 0 {
			return uid, true
		}
	}
	return 0, false
}

func meHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := userlogic.New(svcCtx).Me(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func updateMeHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.UpdateProfileReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := userlogic.New(svcCtx).UpdateMe(r.Context(), uid, &req); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func deactivateHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.DeactivateReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := userlogic.New(svcCtx).Deactivate(r.Context(), uid, req.Password); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func userHistoryHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.PageReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := postlogic.New(svcCtx).History(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func clearHistoryHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		if err := postlogic.New(svcCtx).ClearHistory(r.Context(), uid); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func userFavoritesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.PageReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := postlogic.New(svcCtx).Favorites(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func userProfileHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		viewer := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := userlogic.New(svcCtx).Profile(r.Context(), viewer, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func userPostsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.AuthorPostsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		viewer := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := postlogic.New(svcCtx).AuthorPosts(r.Context(), viewer, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

// relationListHandler 关注/粉丝列表共用骨架。
func relationListHandler(svcCtx *svc.ServiceContext,
	list func(l *userlogic.Logic, r *http.Request, viewer, target int64, page *types.PageReq) ([]types.RelationUserItem, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.AuthorPostsReq // 复用 path:id + 分页
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		viewer := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := list(userlogic.New(svcCtx), r, viewer, req.UserID, &req.PageReq)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func followingListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return relationListHandler(svcCtx, func(l *userlogic.Logic, r *http.Request, viewer, target int64, page *types.PageReq) ([]types.RelationUserItem, error) {
		return l.Following(r.Context(), viewer, target, page)
	})
}

func fansListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return relationListHandler(svcCtx, func(l *userlogic.Logic, r *http.Request, viewer, target int64, page *types.PageReq) ([]types.RelationUserItem, error) {
		return l.Fans(r.Context(), viewer, target, page)
	})
}

// userActionHandler 关注/取关/拉黑/解除拉黑共用骨架。
func userActionHandler(svcCtx *svc.ServiceContext,
	act func(l *userlogic.Logic, r *http.Request, uid, target int64) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := act(userlogic.New(svcCtx), r, uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func followHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return userActionHandler(svcCtx, func(l *userlogic.Logic, r *http.Request, uid, target int64) error {
		return l.Follow(r.Context(), uid, target)
	})
}

func unfollowHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return userActionHandler(svcCtx, func(l *userlogic.Logic, r *http.Request, uid, target int64) error {
		return l.Unfollow(r.Context(), uid, target)
	})
}

func blockHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return userActionHandler(svcCtx, func(l *userlogic.Logic, r *http.Request, uid, target int64) error {
		return l.Block(r.Context(), uid, target)
	})
}

func unblockHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return userActionHandler(svcCtx, func(l *userlogic.Logic, r *http.Request, uid, target int64) error {
		return l.Unblock(r.Context(), uid, target)
	})
}
