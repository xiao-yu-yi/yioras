// Yiora 业务 API 服务(模块化单体)。IM 长连接由 cmd/ws 独立部署。
package main

import (
	"context"
	"flag"
	"time"

	"github.com/yiora/server/internal/config"
	"github.com/yiora/server/internal/handler"
	"github.com/yiora/server/internal/svc"

	"github.com/zeromicro/go-zero/core/conf"
	"github.com/zeromicro/go-zero/core/logx"
	"github.com/zeromicro/go-zero/rest"
)

var configFile = flag.String("f", "etc/yiora-api.yaml", "config file")

func main() {
	flag.Parse()

	var c config.Config
	// UseEnv: 生产配置(etc/prod)用 ${ENV} 占位,密钥经环境变量注入不落盘
	conf.MustLoad(*configFile, &c, conf.UseEnv())

	server := rest.MustNewServer(c.RestConf)
	defer server.Stop()

	svcCtx := svc.NewServiceContext(c)
	handler.RegisterHandlers(server, svcCtx)

	go reconcileDaemon(svcCtx)
	go hotScoreDaemon(svcCtx)
	if svcCtx.Meili != nil {
		interval := time.Duration(c.Search.SyncIntervalSec) * time.Second
		if interval <= 0 {
			interval = time.Minute
		}
		go svcCtx.Meili.SyncDaemon(interval)
	}

	server.Start()
}

// hotScoreDaemon 热度分周期重算(需求 3.2 推荐流排序):
// 时间衰减+互动热度+运营加权,公式见 PostModel.RecalcHotScores;互动实时增量只是两次重算间的近似。
// 启动即跑一轮(冷启动修正),此后每小时重算。
func hotScoreDaemon(svcCtx *svc.ServiceContext) {
	defer func() {
		if r := recover(); r != nil {
			logx.Errorf("hot score daemon panic: %v", r)
		}
	}()
	run := func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		if err := svcCtx.PostModel.RecalcHotScores(ctx); err != nil {
			logx.Errorf("hot score recalc: %v", err)
			return
		}
		logx.Info("hot score recalc done")
	}
	run()
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		run()
	}
}

// reconcileDaemon 忧珠每日对账巡检:余额与流水合计不平的账户告警(需求 3.10)。
// 守护 goroutine,owner=main,随进程退出;panic 自恢复。
func reconcileDaemon(svcCtx *svc.ServiceContext) {
	defer func() {
		if r := recover(); r != nil {
			logx.Errorf("youzhu reconcile daemon panic: %v", r)
		}
	}()
	run := func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		diffs, err := svcCtx.YouzhuModel.Reconcile(ctx, 100)
		if err != nil {
			logx.Errorf("youzhu reconcile: %v", err)
			return
		}
		if len(diffs) == 0 {
			logx.Info("youzhu reconcile: all balanced")
			return
		}
		for _, d := range diffs {
			logx.Errorf("youzhu reconcile MISMATCH uid=%d balance=%d logSum=%d", d.UserID, d.Balance, d.LogSum)
		}
	}
	// 启动后先跑一轮,此后每 24h 巡检一次
	run()
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		run()
	}
}
