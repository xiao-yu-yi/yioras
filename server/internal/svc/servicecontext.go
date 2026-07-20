package svc

import (
	"github.com/yiora/server/internal/config"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/emailx"
	"github.com/yiora/server/internal/pkg/ipallow"
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
	Search search.Searcher   // 全站搜索,当前 MySQL LIKE,可换 Meilisearch
	AdminIPs *ipallow.List   // 后台访问 IP 白名单(启动时解析)

	UserModel      *model.UserModel
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

func NewServiceContext(c config.Config) *ServiceContext {
	conn := sqlx.NewMysql(c.MySQL.DataSource)
	sensitiveModel := model.NewSensitiveModel(conn)
	adminIPs, err := ipallow.Parse(c.Admin.IPAllowlist)
	if err != nil {
		logx.Must(err) // 白名单写错宁可起不来,不能静默放行
	}
	return &ServiceContext{
		Config: c,
		Redis:  redis.MustNewRedis(c.Redis),
		AdminIPs: adminIPs,
		Email: emailx.NewSender(emailx.Config{
			Host: c.Email.Host, Port: c.Email.Port,
			Username: c.Email.Username, Password: c.Email.Password,
			From: c.Email.From, Mock: c.Email.Mock,
		}),
		Pusher: wspush.New(c.WsPush.URL, c.WsPush.Token),
		Filter: sensitive.NewFilter(sensitiveModel),
		Search: model.NewSearchModel(conn),

		UserModel:      model.NewUserModel(conn),
		CircleModel:    model.NewCircleModel(conn),
		PostModel:      model.NewPostModel(conn),
		InteractModel:  model.NewInteractModel(conn),
		IMModel:        model.NewIMModel(conn),
		NotifyModel:    model.NewNotifyModel(conn),
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
