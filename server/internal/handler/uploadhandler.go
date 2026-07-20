package handler

import (
	"net/http"

	"github.com/yiora/server/internal/logic/uploadlogic"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func presignHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.PresignReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := uploadlogic.New(svcCtx).Presign(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func multipartInitHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.MultipartInitReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := uploadlogic.New(svcCtx).MultipartInit(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func multipartCompleteHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.MultipartCompleteReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := uploadlogic.New(svcCtx).MultipartComplete(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func multipartAbortHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.MultipartAbortReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := uploadlogic.New(svcCtx).MultipartAbort(r.Context(), uid, &req); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	}
}

func multipartPartsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := mustUID(w, r)
		if !ok {
			return
		}
		var req types.MultipartPartsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := uploadlogic.New(svcCtx).MultipartParts(r.Context(), uid, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}
