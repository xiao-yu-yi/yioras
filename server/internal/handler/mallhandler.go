package handler

import (
	"net/http"

	"github.com/yiora/server/internal/logic/malllogic"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func decorationsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.DecorationListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := malllogic.New(svcCtx).Decorations(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

// mallActionHandler 兑换/佩戴/卸下共用骨架(path id + uid)。
func mallActionHandler(svcCtx *svc.ServiceContext,
	act func(l *malllogic.Logic, r *http.Request, uid, id int64) error) http.HandlerFunc {
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
		if err := act(malllogic.New(svcCtx), r, uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func exchangeDecoHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return mallActionHandler(svcCtx, func(l *malllogic.Logic, r *http.Request, uid, id int64) error {
		return l.Exchange(r.Context(), uid, id)
	})
}

func wearHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return mallActionHandler(svcCtx, func(l *malllogic.Logic, r *http.Request, uid, id int64) error {
		return l.Wear(r.Context(), uid, id)
	})
}

func takeOffHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return mallActionHandler(svcCtx, func(l *malllogic.Logic, r *http.Request, uid, id int64) error {
		return l.TakeOff(r.Context(), uid, id)
	})
}

func myDecorationsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.DecorationListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := malllogic.New(svcCtx).Mine(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func prettyNoListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.PageReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := malllogic.New(svcCtx).PrettyNos(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func exchangeNoHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		out, err := malllogic.New(svcCtx).ExchangeNo(r.Context(), uid, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func lotteryPoolsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := malllogic.New(svcCtx).Pools(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func drawHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := malllogic.New(svcCtx).Draw(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func exchangeRecordsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		out, err := malllogic.New(svcCtx).Records(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}
