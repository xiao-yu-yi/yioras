package handler

import (
	"net/http"
	"strings"

	"github.com/yiora/server/internal/logic/authlogic"
	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/logic/userlogic"
	"github.com/yiora/server/internal/pkg/jwtx"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

// optionalUID 公开接口的可选登录态:带合法 token 则返回 uid 用于个性化(点赞/收藏/已加入),否则按游客(0)。
func optionalUID(r *http.Request, secret string) int64 {
	const prefix = "Bearer "
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, prefix) {
		return 0
	}
	uid, err := jwtx.ParseUID(secret, h[len(prefix):])
	if err != nil {
		return 0
	}
	return uid
}

// mustUID 登录态接口从 JWT 中间件取 uid,取不到直接 401。
func mustUID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	uid, ok := uidFromCtx(r)
	if !ok {
		resp.Error(w, r, xerr.New(xerr.CodeUnauthorized, "请先登录"))
	}
	return uid, ok
}

// deactivatedGuard JWT 路由组后置守卫:已注销/已封禁用户的存量 token 全部拒绝(JWT 无状态,靠 Redis 吊销标记)。
// Redis 故障时放行(可用性优先),标记有 user.status 落库兜底(登录/资料链路仍拦截)。
func deactivatedGuard(svcCtx *svc.ServiceContext) func(http.HandlerFunc) http.HandlerFunc {
	return func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if uid, ok := uidFromCtx(r); ok {
				if revoked, err := svcCtx.Redis.ExistsCtx(r.Context(), userlogic.DeactivateKey(uid)); err == nil && revoked {
					resp.Error(w, r, xerr.New(xerr.CodeUnauthorized, "账号已注销"))
					return
				}
				if banned, err := svcCtx.Redis.ExistsCtx(r.Context(), userlogic.BannedKey(uid)); err == nil && banned {
					resp.Error(w, r, xerr.New(xerr.CodeUnauthorized, "账号已被封禁"))
					return
				}
				// 设备被踢下线(仅新版带 did claim 的 token 参与)
				if did := didFromCtx(r); did != "" {
					if kicked, err := svcCtx.Redis.ExistsCtx(r.Context(), authlogic.KickKey(uid, did)); err == nil && kicked {
						resp.Error(w, r, xerr.New(xerr.CodeUnauthorized, "该设备已被下线,请重新登录"))
						return
					}
				}
			}
			next(w, r)
		}
	}
}

func sharePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		out, err := postlogic.New(svcCtx).Share(r.Context(), uid, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func resolveShareHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.ShareResolveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := postlogic.New(svcCtx).ResolveShare(r.Context(), req.Code)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func userSettingsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := userlogic.New(svcCtx).Settings(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func updateSettingsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.UpdateSettingsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := userlogic.New(svcCtx).UpdateSettings(r.Context(), uid, &req); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func feedHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.FeedReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := postlogic.New(svcCtx).Feed(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func postDetailHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := postlogic.New(svcCtx).Detail(r.Context(), uid, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func createPostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.CreatePostReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := postlogic.New(svcCtx).Create(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func deletePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		if err := postlogic.New(svcCtx).Delete(r.Context(), uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

// postActionHandler 点赞/取消点赞/收藏/取消收藏共用骨架。
func postActionHandler(svcCtx *svc.ServiceContext,
	act func(l *postlogic.Logic, r *http.Request, uid, postID int64) error) http.HandlerFunc {
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
		if err := act(postlogic.New(svcCtx), r, uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func topicPostsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.TopicPostsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := postlogic.New(svcCtx).TopicPosts(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func cocreateConfirmHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.CocreateConfirmReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := postlogic.New(svcCtx).ConfirmCocreate(r.Context(), uid, req.PostID, req.Accept); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func unlockPostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		out, err := postlogic.New(svcCtx).Unlock(r.Context(), uid, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func likePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return postActionHandler(svcCtx, func(l *postlogic.Logic, r *http.Request, uid, id int64) error {
		return l.Like(r.Context(), uid, id)
	})
}

func unlikePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return postActionHandler(svcCtx, func(l *postlogic.Logic, r *http.Request, uid, id int64) error {
		return l.Unlike(r.Context(), uid, id)
	})
}

func favoritePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return postActionHandler(svcCtx, func(l *postlogic.Logic, r *http.Request, uid, id int64) error {
		return l.Favorite(r.Context(), uid, id)
	})
}

func unfavoritePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return postActionHandler(svcCtx, func(l *postlogic.Logic, r *http.Request, uid, id int64) error {
		return l.Unfavorite(r.Context(), uid, id)
	})
}
