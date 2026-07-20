package svc

import (
	"context"
	"fmt"

	"github.com/yiora/server/internal/config"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/apppush"
	"github.com/yiora/server/internal/pkg/emailx"
	"github.com/yiora/server/internal/pkg/imgscan"
	"github.com/yiora/server/internal/pkg/ipallow"
	"github.com/yiora/server/internal/pkg/llm"
	"github.com/yiora/server/internal/pkg/multipart"
	"github.com/yiora/server/internal/pkg/search"
	"github.com/yiora/server/internal/pkg/sensitive"
	"github.com/yiora/server/internal/pkg/wspush"

	"github.com/zeromicro/go-zero/core/logx"
	"github.com/zeromicro/go-zero/core/stores/redis"
	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type ServiceContext struct {
	Config config.Config
	Redis  *redis.Redis
	Email  *emailx.Sender
	Pusher *wspush.Pusher    // api → ws 网关内部下行推送
	Filter *sensitive.Filter // 发布/评论/私信共用的敏感词机审
	Search search.Searcher   // 全站搜索:mysql(LIKE)或 meili 驱动,配置切换
	Meili  *search.Meili     // 非 nil 时 api 进程负责起增量同步 daemon
	AdminIPs *ipallow.List   // 后台访问 IP 白名单(启动时解析)
	ImgScanner imgscan.Scanner // 图片机审驱动,nil=关闭(直传后异步送审)
	Multipart *multipart.Client // S3 分片上传(APK 大文件),nil=对象存储未配置
	LLM *llm.Client // AI 管家大模型,nil=纯 FAQ 规则模式
	AppPush *apppush.Manager // 离线推送(APNs/厂商通道),无驱动时所有发送跳过

	UserModel      *model.UserModel
	PushModel      *model.PushModel
	CircleModel    *model.CircleModel
	PostModel      *model.PostModel
	InteractModel  *model.InteractModel
	IMModel        *model.IMModel
	NotifyModel    *model.NotifyModel
	SensitiveModel *model.SensitiveModel
	RelationModel  *model.RelationModel
	BannerModel    *model.BannerModel
	ReportModel    *model.ReportModel
	SoftwareModel  *model.SoftwareModel
	TaskModel      *model.TaskModel
	YouzhuModel    *model.YouzhuModel
	MallModel      *model.MallModel
	PaidModel      *model.PaidModel
	FaqModel       *model.FaqModel
	TopicModel     *model.TopicModel
	CocreatorModel *model.CocreatorModel
	DraftModel     *model.DraftModel
	CertModel      *model.CertModel
	AdminModel     *model.AdminModel
}

// notifyPushHook 站内通知切面:先经 WS 给在线端推 notify.new 帧(实时小红点),
// 不在线且有推送驱动时走 APNs/厂商通道,按类别合并频控防轰炸:
// 互动类(赞/评论)5 分钟一条汇总文案;系统类(审核/处置结果)1 分钟一条推原文。
// 尊重用户设置页的分类推送开关(user.push_prefs)。
func notifyPushHook(pusher *wspush.Pusher, mgr *apppush.Manager, pm *model.PushModel, um *model.UserModel, rds *redis.Redis) model.NotifyHook {
	return func(ctx context.Context, n *model.Notification) {
		online := pusher.Push(ctx, n.UserID, "notify.new", map[string]any{"type": n.Type})
		if online || !mgr.Enabled() {
			return
		}
		title, body := "Yiora", n.Content
		gate, gateSec, prefBit := "", 0, int64(0)
		switch n.Type {
		case model.NotifyTypeLike, model.NotifyTypeComment:
			gate, gateSec, prefBit = fmt.Sprintf("push:ntf:i:%d", n.UserID), 300, model.PushPrefInteract
			title, body = "互动提醒", "你收到了新的点赞/评论,点开看看"
		default: // 系统通知逐条推原文,短频控防连发
			gate, gateSec, prefBit = fmt.Sprintf("push:ntf:s:%d", n.UserID), 60, model.PushPrefSystem
			title = "系统通知"
		}
		if prefs, err := um.PushPrefs(ctx, n.UserID); err != nil || prefs&prefBit == 0 {
			return
		}
		// 先查 token 再消耗频控窗口:未注册推送的用户不白耗合并窗口
		tokens, err := pm.TokensByUser(ctx, n.UserID)
		if err != nil || len(tokens) == 0 {
			return
		}
		ok, err := rds.SetnxExCtx(ctx, gate, "1", gateSec)
		if err != nil || !ok {
			return
		}
		note := apppush.Notification{
			Title: title, Body: body,
			Deeplink: fmt.Sprintf("yiora://notifications/%d", n.Type),
		}
		for _, t := range tokens {
			mgr.Send(ctx, t.Channel, t.Token, note)
		}
	}
}

func NewServiceContext(c config.Config) *ServiceContext {
	conn := sqlx.NewMysql(c.MySQL.DataSource)
	sensitiveModel := model.NewSensitiveModel(conn)
	adminIPs, err := ipallow.Parse(c.Admin.IPAllowlist)
	if err != nil {
		logx.Must(err) // 白名单写错宁可起不来,不能静默放行
	}
	scanner, err := imgscan.New(c.ImgScan.Provider)
	if err != nil {
		logx.Must(err) // provider 写错宁可起不来,不能静默关闭机审
	}
	var mpClient *multipart.Client
	if c.Storage.Endpoint != "" && c.Storage.Bucket != "" {
		mpClient, err = multipart.New(multipart.Config{
			Endpoint: c.Storage.Endpoint, PublicBaseURL: c.Storage.PublicBaseURL,
			Region: c.Storage.Region, Bucket: c.Storage.Bucket,
			AccessKey: c.Storage.AccessKey, SecretKey: c.Storage.SecretKey,
		})
		if err != nil {
			logx.Must(err)
		}
	}
	searchModel := model.NewSearchModel(conn)
	var searcher search.Searcher = searchModel
	var meiliClient *search.Meili
	if c.Search.Provider == "meili" {
		meiliClient, err = search.NewMeili(c.Search.Host, c.Search.APIKey, searchModel)
		if err != nil {
			logx.Must(err) // 显式选择 meili 却连不上,宁可起不来,不能静默退化
		}
		searcher = meiliClient
	}
	rds := redis.MustNewRedis(c.Redis)
	pushMgr := apppush.NewManager()
	if c.Push.Mock {
		pushMgr.Register("mock", apppush.NewMock(rds))
	}
	apns, err := apppush.NewAPNs(apppush.APNsConfig{
		KeyID: c.Push.APNs.KeyID, TeamID: c.Push.APNs.TeamID, BundleID: c.Push.APNs.BundleID,
		PrivateKey: c.Push.APNs.PrivateKey, Production: c.Push.APNs.Production,
	})
	if err != nil {
		logx.Must(err) // 配了 APNs 却密钥非法,宁可起不来
	}
	pushMgr.Register("apns", apns)

	pusher := wspush.New(c.WsPush.URL, c.WsPush.Token)
	notifyModel := model.NewNotifyModel(conn)
	pushModel := model.NewPushModel(conn)
	userModel := model.NewUserModel(conn)
	// 通知落库切面:WS 在线端实时刷小红点;不在线走离线推送(互动 5 分钟/系统 1 分钟分类合并)
	notifyModel.SetHook(notifyPushHook(pusher, pushMgr, pushModel, userModel, rds))
	return &ServiceContext{
		Config: c,
		Redis:  rds,
		AppPush: pushMgr,
		AdminIPs: adminIPs,
		ImgScanner: scanner,
		Multipart: mpClient,
		Meili: meiliClient,
		LLM: llm.New(llm.Config{
			BaseURL: c.LLM.BaseURL, APIKey: c.LLM.APIKey,
			Model: c.LLM.Model, TimeoutSec: c.LLM.TimeoutSec,
		}),
		Email: emailx.NewSender(emailx.Config{
			Host: c.Email.Host, Port: c.Email.Port,
			Username: c.Email.Username, Password: c.Email.Password,
			From: c.Email.From, Mock: c.Email.Mock,
		}),
		Pusher: pusher,
		Filter: sensitive.NewFilter(sensitiveModel),
		Search: searcher,

		UserModel:      userModel,
		PushModel:      pushModel,
		CircleModel:    model.NewCircleModel(conn),
		PostModel:      model.NewPostModel(conn),
		InteractModel:  model.NewInteractModel(conn),
		IMModel:        model.NewIMModel(conn),
		NotifyModel:    notifyModel,
		SensitiveModel: sensitiveModel,
		RelationModel:  model.NewRelationModel(conn),
		BannerModel:    model.NewBannerModel(conn),
		ReportModel:    model.NewReportModel(conn),
		SoftwareModel:  model.NewSoftwareModel(conn),
		TaskModel:      model.NewTaskModel(conn),
		YouzhuModel:    model.NewYouzhuModel(conn),
		MallModel:      model.NewMallModel(conn),
		PaidModel:      model.NewPaidModel(conn),
		FaqModel:       model.NewFaqModel(conn),
		TopicModel:     model.NewTopicModel(conn),
		CocreatorModel: model.NewCocreatorModel(conn),
		DraftModel:     model.NewDraftModel(conn),
		CertModel:      model.NewCertModel(conn),
		AdminModel:     model.NewAdminModel(conn),
	}
}
