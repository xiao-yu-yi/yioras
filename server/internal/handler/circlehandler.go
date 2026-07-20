package handler

import (
	"net/http"

	"github.com/yiora/server/internal/logic/circlelogic"
	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/logic/userlogic"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func circleListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.CircleListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := circlelogic.New(svcCtx).List(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func circleDetailHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := circlelogic.New(svcCtx).Detail(r.Context(), uid, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func circlePostsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.CirclePostsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := postlogic.New(svcCtx).CirclePosts(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func joinCircleHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		if err := circlelogic.New(svcCtx).Join(r.Context(), uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

// circleAdminHandler 圈管理动作共用骨架(path 圈 id + body)。
func circleAdminHandler(svcCtx *svc.ServiceContext,
	act func(l *circlelogic.Logic, r *http.Request, uid int64, req *types.CircleAdminPostReq) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.CircleAdminPostReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := act(circlelogic.New(svcCtx), r, uid, &req); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func circleTopHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return circleAdminHandler(svcCtx, func(l *circlelogic.Logic, r *http.Request, uid int64, req *types.CircleAdminPostReq) error {
		return l.SetTop(r.Context(), uid, req)
	})
}

func circleEssenceHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return circleAdminHandler(svcCtx, func(l *circlelogic.Logic, r *http.Request, uid int64, req *types.CircleAdminPostReq) error {
		return l.SetEssence(r.Context(), uid, req)
	})
}

func circleRemovePostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return circleAdminHandler(svcCtx, func(l *circlelogic.Logic, r *http.Request, uid int64, req *types.CircleAdminPostReq) error {
		return l.RemovePost(r.Context(), uid, req)
	})
}

func circleMuteHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.CircleMuteReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := circlelogic.New(svcCtx).Mute(r.Context(), uid, &req); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func certifyHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.CertifyReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := userlogic.New(svcCtx).Certify(r.Context(), uid, &req); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func myCertsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := userlogic.New(svcCtx).MyCerts(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func leaveCircleHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		if err := circlelogic.New(svcCtx).Leave(r.Context(), uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}
