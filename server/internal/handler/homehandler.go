package handler

import (
	"net/http"

	"github.com/yiora/server/internal/logic/homelogic"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/svc"
)

func homeConfigHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := homelogic.New(svcCtx).Config(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}
