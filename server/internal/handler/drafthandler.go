package handler

import (
	"net/http"

	"github.com/yiora/server/internal/logic/draftlogic"
	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func saveDraftHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.SaveDraftReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := draftlogic.New(svcCtx).Save(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func draftListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.DraftListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := draftlogic.New(svcCtx).List(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func deleteDraftHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
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
		if err := draftlogic.New(svcCtx).Delete(r.Context(), uid, req.ID); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func editPostHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.EditPostReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := postlogic.New(svcCtx).Edit(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}
