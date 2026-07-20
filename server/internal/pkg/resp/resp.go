// Package resp 统一响应包 {code,msg,data,traceId}。
package resp

import (
	"errors"
	"net/http"

	"github.com/yiora/server/internal/pkg/xerr"

	"github.com/zeromicro/go-zero/core/logx"
	"github.com/zeromicro/go-zero/core/trace"
	"github.com/zeromicro/go-zero/rest/httpx"
)

type Body struct {
	Code    int    `json:"code"`
	Msg     string `json:"msg"`
	Data    any    `json:"data,omitempty"`
	TraceID string `json:"traceId"`
}

func OK(w http.ResponseWriter, r *http.Request, data any) {
	httpx.OkJsonCtx(r.Context(), w, &Body{
		Code:    xerr.CodeOK,
		Msg:     "ok",
		Data:    data,
		TraceID: trace.TraceIDFromContext(r.Context()),
	})
}

// Error 业务错误返回业务码,未知错误统一 50000 且不向客户端泄漏内部信息。
func Error(w http.ResponseWriter, r *http.Request, err error) {
	var biz *xerr.BizError
	if !errors.As(err, &biz) {
		logx.WithContext(r.Context()).Errorf("internal error: %v", err)
		biz = xerr.New(xerr.CodeServer, "服务器开小差了,请稍后再试")
	}
	httpx.OkJsonCtx(r.Context(), w, &Body{
		Code:    biz.Code,
		Msg:     biz.Msg,
		TraceID: trace.TraceIDFromContext(r.Context()),
	})
}
