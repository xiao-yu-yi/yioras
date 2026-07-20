package handler

import (
	"context"
	"net/http"
	"strings"

	"github.com/yiora/server/internal/logic/adminlogic"
	"github.com/yiora/server/internal/logic/uploadlogic"
	"github.com/yiora/server/internal/pkg/jwtx"
	"github.com/yiora/server/internal/pkg/resp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/rest/httpx"
)

type adminCtxKey struct{}

type adminIdentity struct {
	AdminID int64
	RoleID  int64
}

// adminIPGuard 后台 IP 白名单:配置非空时,名单外一律拒绝(含登录/验证码)。
func adminIPGuard(svcCtx *svc.ServiceContext, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !svcCtx.AdminIPs.Allowed(httpx.GetRemoteAddr(r)) {
			resp.Error(w, r, xerr.New(xerr.CodeForbidden, "当前 IP 不在后台允许名单内"))
			return
		}
		next(w, r)
	}
}

// adminAuth 后台鉴权中间件:IP 白名单 + 解析管理令牌(与用户令牌 claim 隔离)+ RBAC 权限码校验。
func adminAuth(svcCtx *svc.ServiceContext, perm string, next func(w http.ResponseWriter, r *http.Request, id adminIdentity)) http.HandlerFunc {
	return adminIPGuard(svcCtx, func(w http.ResponseWriter, r *http.Request) {
		const prefix = "Bearer "
		h := r.Header.Get("Authorization")
		if !strings.HasPrefix(h, prefix) {
			resp.Error(w, r, xerr.New(xerr.CodeUnauthorized, "请先登录后台"))
			return
		}
		adminID, roleID, err := jwtx.ParseAdmin(svcCtx.Config.Auth.AccessSecret, h[len(prefix):])
		if err != nil || adminID <= 0 {
			resp.Error(w, r, xerr.New(xerr.CodeUnauthorized, "后台登录已失效"))
			return
		}
		if perm != "" {
			if err := adminlogic.New(svcCtx).RequirePerm(r.Context(), roleID, perm); err != nil {
				resp.Error(w, r, err)
				return
			}
		}
		next(w, r.WithContext(context.WithValue(r.Context(), adminCtxKey{}, adminIdentity{AdminID: adminID, RoleID: roleID})), adminIdentity{AdminID: adminID, RoleID: roleID})
	})
}

func adminCaptchaHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminIPGuard(svcCtx, func(w http.ResponseWriter, r *http.Request) {
		out, err := adminlogic.New(svcCtx).Captcha(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminTotpLoginHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminIPGuard(svcCtx, func(w http.ResponseWriter, r *http.Request) {
		var req types.AdminTotpLoginReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).LoginTotp(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminTotpStatusHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		out, err := adminlogic.New(svcCtx).TotpStatus(r.Context(), id.AdminID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminTotpSetupHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		out, err := adminlogic.New(svcCtx).TotpSetup(r.Context(), id.AdminID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminTotpConfirmHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.TotpCodeReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).TotpConfirm(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminTotpDisableHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.TotpCodeReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).TotpDisable(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminChangePwdHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminChangePwdReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).ChangePassword(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminAccountsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "admin.manage", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Admins(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminCreateAccountHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "admin.manage", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminCreateAccountReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		aid, err := adminlogic.New(svcCtx).CreateAdmin(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": aid})
	})
}

func adminUpdateAccountHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "admin.manage", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminUpdateAccountReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).UpdateAdmin(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminRolesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "admin.manage", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Roles(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminLoginHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminIPGuard(svcCtx, func(w http.ResponseWriter, r *http.Request) {
		var req types.AdminLoginReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Login(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminAuditsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AuditListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Audits(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminDecideHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AuditDecideReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).Decide(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminCertsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.PageReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Certs(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminDecideCertHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.CertDecideReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).DecideCert(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminCirclesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "circle.manage", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminCircleListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Circles(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveCircleHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "circle.manage", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminCircleSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		cid, err := adminlogic.New(svcCtx).SaveCircle(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": cid})
	})
}

func adminPostOpsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminPostOpsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).PostOps(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminTopicsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminTopicListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Topics(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminUpdateTopicHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminTopicUpdateReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).UpdateTopic(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminAppointHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "circle.manage", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AppointReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).Appoint(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminNoticeHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminNoticeReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).PublishNotice(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminUsersHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminUserListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Users(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminBanHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.UserBanReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).BanUser(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminContentsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminContentListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Contents(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminTakedownHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminTakedownReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).TakedownContent(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminReportsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminReportListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Reports(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminHandleReportHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminReportHandleReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).HandleReport(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminBannersHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.banner", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Banners(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveBannerHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.banner", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminBannerReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		bid, err := adminlogic.New(svcCtx).SaveBanner(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": bid})
	})
}

func adminDeleteBannerHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.banner", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).DeleteBanner(r.Context(), id.AdminID, req.ID, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminDashboardHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "dashboard", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Dashboard(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminWordsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminWordListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Words(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveWordHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminWordSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		wid, err := adminlogic.New(svcCtx).SaveWord(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": wid})
	})
}

func adminDeleteWordHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).DeleteWord(r.Context(), id.AdminID, req.ID, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminPushStatsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "dashboard", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.PushStatsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).PushStats(r.Context(), req.Days)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminBotStatsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.BotStatsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).BotStats(r.Context(), req.Days)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminFaqsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.PageReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Faqs(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveFaqHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminFaqSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		fid, err := adminlogic.New(svcCtx).SaveFaq(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": fid})
	})
}

func adminDeleteFaqHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).DeleteFaq(r.Context(), id.AdminID, req.ID, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminDecosHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Decorations(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveDecoHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminDecoSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		did, err := adminlogic.New(svcCtx).SaveDecoration(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": did})
	})
}

func adminPrizesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Prizes(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSavePrizeHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminPrizeSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		pid, err := adminlogic.New(svcCtx).SavePrize(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": pid})
	})
}

func adminGrantYouzhuHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminYouzhuGrantReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).GrantYouzhu(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminYouzhuLogsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminYouzhuLogListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).YouzhuLogs(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminPrettyNosHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminPrettyNoListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).PrettyNos(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSavePrettyNoHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminPrettyNoSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		pid, err := adminlogic.New(svcCtx).SavePrettyNo(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": pid})
	})
}

func adminDeletePrettyNoHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).DeletePrettyNo(r.Context(), id.AdminID, req.ID, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminTaskCfgsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).TaskCfgs(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveTaskCfgHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminTaskSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		tid, err := adminlogic.New(svcCtx).SaveTaskCfg(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": tid})
	})
}

func adminTrendHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "dashboard", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.TrendReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Trend(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminCategoriesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).Categories(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveCategoryHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.mall", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminCategorySaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		cid, err := adminlogic.New(svcCtx).SaveCategory(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r))
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, map[string]int64{"id": cid})
	})
}

// adminPresignHandler 管理端直传签名(Banner 图/装扮预览等),uid 记 adminID 便于按目录溯源。
func adminPresignHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.PresignReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := uploadlogic.New(svcCtx).Presign(r.Context(), id.AdminID, &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

// agreementHandler 用户侧协议读取(免登录)。bot_prompt 等内部文案不对外暴露。
func agreementHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req types.AgreementPathReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if req.Kind != "user" && req.Kind != "privacy" {
			resp.Error(w, r, xerr.New(xerr.CodeNotFound, "协议不存在"))
			return
		}
		out, err := adminlogic.New(svcCtx).Agreement(r.Context(), req.Kind)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	}
}

func adminAgreementHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AgreementPathReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).Agreement(r.Context(), req.Kind)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveAgreementHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "ops.notice", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminAgreementSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).SaveAgreement(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminAuditPreviewHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).AuditPreview(r.Context(), req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSoftwaresHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.AdminSoftwareListReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).SoftwaresAdmin(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSoftwareOpsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminSoftwareOpsReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).SoftwareOps(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminSoftwareVersionsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "audit", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).SoftwareVersionsAdmin(r.Context(), req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminUserDevicesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.IDPath
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).UserDevicesAdmin(r.Context(), req.ID)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminKickDeviceHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminKickDeviceReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).KickUserDevice(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminLevelRulesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		out, err := adminlogic.New(svcCtx).LevelRules(r.Context())
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}

func adminSaveLevelRulesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminLevelRulesSaveReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).SaveLevelRules(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminUserLevelHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminUserLevelReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).SetUserLevel(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminUserTitleHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "user.ban", func(w http.ResponseWriter, r *http.Request, id adminIdentity) {
		var req types.AdminUserTitleReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		if err := adminlogic.New(svcCtx).GrantUserTitle(r.Context(), id.AdminID, &req, httpx.GetRemoteAddr(r)); err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, nil)
	})
}

func adminOpLogsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return adminAuth(svcCtx, "log.view", func(w http.ResponseWriter, r *http.Request, _ adminIdentity) {
		var req types.PageReq
		if err := httpx.Parse(r, &req); err != nil {
			resp.Error(w, r, xerr.Param(err.Error()))
			return
		}
		out, err := adminlogic.New(svcCtx).OpLogs(r.Context(), &req)
		if err != nil {
			resp.Error(w, r, err)
			return
		}
		resp.OK(w, r, out)
	})
}
