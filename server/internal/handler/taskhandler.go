package handler

import (
	"net/http"

	"github.com/yiora/server/internal/logic/searchlogic"
	"github.com/yiora/server/internal/logic/tasklogic"
	"github.com/yiora/server/internal/logic/youzhulogic"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func searchHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.SearchReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		uid := optionalUID(r, svcCtx.Config.Auth.AccessSecret)
		out, err := searchlogic.New(svcCtx).Search(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func suggestHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.SuggestReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := searchlogic.New(svcCtx).Suggest(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func taskListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := tasklogic.New(svcCtx).List(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func signInHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := tasklogic.New(svcCtx).SignIn(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func claimTaskHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		out, err := tasklogic.New(svcCtx).Claim(r.Context(), uid, req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func youzhuAccountHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		out, err := youzhulogic.New(svcCtx).Account(r.Context(), uid)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func youzhuLogsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.YouzhuLogsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := youzhulogic.New(svcCtx).Logs(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}
