package handler

import (
	"net/http"

	"github.com/yiora/server/internal/svc"

	"github.com/zeromicro/go-zero/rest"
)

// RegisterHandlers 注册 /api/v1 路由。
// 公开路由支持可选登录态(optionalUID):带 token 返回个性化字段(liked/joined/followed等),游客可浏览。
// M2 业务接口已齐;M3 起新增软件库/搜索/任务/忧珠模块,按 handler→logic→model 模式扩展。
func RegisterHandlers(server *rest.Server, svcCtx *svc.ServiceContext) {
	// 公开路由
	server.AddRoutes([]rest.Route{
		{Method: http.MethodPost, Path: "/auth/email-code", Handler: sendEmailCodeHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/auth/register", Handler: registerHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/auth/login", Handler: loginHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/auth/reset-password", Handler: resetPasswordHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/auth/refresh", Handler: refreshTokenHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/agreements/:kind", Handler: agreementHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/share/:code", Handler: resolveShareHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/home/config", Handler: homeConfigHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/posts", Handler: feedHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/posts/:id", Handler: postDetailHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/comments", Handler: commentListHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/topics/:id/posts", Handler: topicPostsHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/circles", Handler: circleListHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/circles/:id", Handler: circleDetailHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/circles/:id/posts", Handler: circlePostsHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/users/:id", Handler: userProfileHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/users/:id/posts", Handler: userPostsHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/users/:id/following", Handler: followingListHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/users/:id/fans", Handler: fansListHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/search", Handler: searchHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/search/suggest", Handler: suggestHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/software", Handler: softwareListHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/software/categories", Handler: softwareCategoriesHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/software/:id", Handler: softwareDetailHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/software/:id/download", Handler: softwareDownloadHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/mall/decorations", Handler: decorationsHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/mall/pretty-no", Handler: prettyNoListHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/lottery/pools", Handler: lotteryPoolsHandler(svcCtx)},
	}, rest.WithPrefix("/api/v1"))

	// 登录态路由(JWT + 注销吊销守卫)
	jwtRoutes := []rest.Route{
		{Method: http.MethodGet, Path: "/user/me", Handler: meHandler(svcCtx)},
		{Method: http.MethodPut, Path: "/user/me", Handler: updateMeHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/user/devices", Handler: deviceListHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/user/devices/:id", Handler: kickDeviceHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/user/settings", Handler: userSettingsHandler(svcCtx)},
		{Method: http.MethodPut, Path: "/user/settings", Handler: updateSettingsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/user/push-token", Handler: pushTokenHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/user/deactivate", Handler: deactivateHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/user/history", Handler: userHistoryHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/user/history", Handler: clearHistoryHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/user/favorites", Handler: userFavoritesHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/reports", Handler: createReportHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/posts", Handler: createPostHandler(svcCtx)},
		{Method: http.MethodPut, Path: "/posts/:id", Handler: editPostHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/posts/:id", Handler: deletePostHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/drafts", Handler: saveDraftHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/drafts", Handler: draftListHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/drafts/:id", Handler: deleteDraftHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/posts/:id/like", Handler: likePostHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/posts/:id/like", Handler: unlikePostHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/posts/:id/share", Handler: sharePostHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/posts/:id/favorite", Handler: favoritePostHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/posts/:id/favorite", Handler: unfavoritePostHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/posts/:id/unlock", Handler: unlockPostHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/posts/:id/cocreate/confirm", Handler: cocreateConfirmHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/comments", Handler: createCommentHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/comments/:id/like", Handler: likeCommentHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/comments/:id/like", Handler: unlikeCommentHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/circles/:id/join", Handler: joinCircleHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles/:id/leave", Handler: leaveCircleHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles/:id/admin/top", Handler: circleTopHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles/:id/admin/essence", Handler: circleEssenceHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles/:id/admin/remove-post", Handler: circleRemovePostHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles/:id/admin/mute", Handler: circleMuteHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/certifications", Handler: certifyHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/certifications/mine", Handler: myCertsHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/users/:id/follow", Handler: followHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/users/:id/follow", Handler: unfollowHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/users/:id/block", Handler: blockHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/users/:id/block", Handler: unblockHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/software", Handler: createSoftwareHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/software/mine", Handler: softwareMineHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/software/:id/versions", Handler: createVersionHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/im/conversations", Handler: conversationsHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/im/conversations/:id", Handler: deleteConversationHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/im/messages", Handler: sendMessageHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/im/messages", Handler: messagesHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/im/messages/recall", Handler: recallMessageHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/im/read", Handler: markReadHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/notifications", Handler: notifyListHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/notifications/read", Handler: notifyReadHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/notifications/unread", Handler: unreadHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/upload/presign", Handler: presignHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/upload/multipart/init", Handler: multipartInitHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/upload/multipart/complete", Handler: multipartCompleteHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/upload/multipart/abort", Handler: multipartAbortHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/upload/multipart/parts", Handler: multipartPartsHandler(svcCtx)},

		{Method: http.MethodGet, Path: "/tasks", Handler: taskListHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/tasks/sign-in", Handler: signInHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/tasks/:id/claim", Handler: claimTaskHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/youzhu/account", Handler: youzhuAccountHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/youzhu/logs", Handler: youzhuLogsHandler(svcCtx)},

		{Method: http.MethodPost, Path: "/mall/decorations/:id/exchange", Handler: exchangeDecoHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/decorations/:id/wear", Handler: wearHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/decorations/:id/take-off", Handler: takeOffHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/mall/decorations/mine", Handler: myDecorationsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/pretty-no/:id/exchange", Handler: exchangeNoHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/lottery/draw", Handler: drawHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/exchange/records", Handler: exchangeRecordsHandler(svcCtx)},
	}
	server.AddRoutes(
		rest.WithMiddlewares([]rest.Middleware{deactivatedGuard(svcCtx)}, jwtRoutes...),
		rest.WithPrefix("/api/v1"), rest.WithJwt(svcCtx.Config.Auth.AccessSecret))

	// 管理后台(/admin/v1):独立管理令牌 + RBAC,鉴权在 adminAuth 内完成
	server.AddRoutes([]rest.Route{
		{Method: http.MethodGet, Path: "/captcha", Handler: adminCaptchaHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/login", Handler: adminLoginHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/login/totp", Handler: adminTotpLoginHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/password", Handler: adminChangePwdHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/upload/presign", Handler: adminPresignHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/totp/status", Handler: adminTotpStatusHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/totp/setup", Handler: adminTotpSetupHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/totp/confirm", Handler: adminTotpConfirmHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/totp/disable", Handler: adminTotpDisableHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/admins", Handler: adminAccountsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/admins", Handler: adminCreateAccountHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/admins/:id", Handler: adminUpdateAccountHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/roles", Handler: adminRolesHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/audits", Handler: adminAuditsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/audits/:id/decide", Handler: adminDecideHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/certifications", Handler: adminCertsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/certifications/:id/decide", Handler: adminDecideCertHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/circles", Handler: adminCirclesHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles", Handler: adminSaveCircleHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/circles/:id/appoint", Handler: adminAppointHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/posts/:id/ops", Handler: adminPostOpsHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/topics", Handler: adminTopicsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/topics/:id", Handler: adminUpdateTopicHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/oplogs", Handler: adminOpLogsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/notices", Handler: adminNoticeHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/reports", Handler: adminReportsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/reports/:id/handle", Handler: adminHandleReportHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/contents", Handler: adminContentsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/contents/takedown", Handler: adminTakedownHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/users", Handler: adminUsersHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/users/:id/ban", Handler: adminBanHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/users/:id/level", Handler: adminUserLevelHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/users/:id/title", Handler: adminUserTitleHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/agreements/:kind", Handler: adminAgreementHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/agreements/:kind", Handler: adminSaveAgreementHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/banners", Handler: adminBannersHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/banners", Handler: adminSaveBannerHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/banners/:id", Handler: adminDeleteBannerHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/dashboard", Handler: adminDashboardHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/dashboard/trend", Handler: adminTrendHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/software/categories", Handler: adminCategoriesHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/software/categories", Handler: adminSaveCategoryHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/words", Handler: adminWordsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/words", Handler: adminSaveWordHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/words/:id", Handler: adminDeleteWordHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/faqs", Handler: adminFaqsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/faqs", Handler: adminSaveFaqHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/faqs/:id", Handler: adminDeleteFaqHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/bot/stats", Handler: adminBotStatsHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/mall/decorations", Handler: adminDecosHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/decorations", Handler: adminSaveDecoHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/mall/prizes", Handler: adminPrizesHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/prizes", Handler: adminSavePrizeHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/mall/tasks", Handler: adminTaskCfgsHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/tasks", Handler: adminSaveTaskCfgHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/mall/prettynos", Handler: adminPrettyNosHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/mall/prettynos", Handler: adminSavePrettyNoHandler(svcCtx)},
		{Method: http.MethodDelete, Path: "/mall/prettynos/:id", Handler: adminDeletePrettyNoHandler(svcCtx)},
		{Method: http.MethodPost, Path: "/youzhu/grant", Handler: adminGrantYouzhuHandler(svcCtx)},
		{Method: http.MethodGet, Path: "/youzhu/logs", Handler: adminYouzhuLogsHandler(svcCtx)},
	}, rest.WithPrefix("/admin/v1"))
}
