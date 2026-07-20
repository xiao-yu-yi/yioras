// Yiora IM WS 网关,独立于业务 API 部署(长连接资源模型不同)。
package main

import (
	"context"
	"errors"
	"flag"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yiora/server/internal/ws"

	"github.com/zeromicro/go-zero/core/conf"
	"github.com/zeromicro/go-zero/core/logx"
)

type wsConfig struct {
	Addr string `json:",default=0.0.0.0:8889"`
	Auth struct {
		AccessSecret string
	}
	InternalToken string // api→ws 内部推送鉴权,与 yiora-api.yaml WsPush.Token 一致
}

var configFile = flag.String("f", "etc/yiora-ws.yaml", "config file")

func main() {
	flag.Parse()

	var c wsConfig
	// UseEnv: 与 api 一致,生产密钥经环境变量注入
	conf.MustLoad(*configFile, &c, conf.UseEnv())

	hub := ws.NewHub(c.Auth.AccessSecret)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /ws", hub.ServeWS)
	mux.HandleFunc("POST /internal/push", hub.ServeInternalPush(c.InternalToken))

	srv := &http.Server{
		Addr:              c.Addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		// 长连接不设 Read/WriteTimeout,读写超时由 ws 心跳 deadline 控制
		IdleTimeout: 90 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		logx.Infof("ws gateway listening on %s", c.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logx.Errorf("ws server: %v", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}
