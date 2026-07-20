// Package wspush api 服务 → ws 网关的内部下行推送客户端。
// 单实例直连;多实例部署时网关前挂内部 LB 或改走 Redis Pub/Sub,调用方接口不变。
package wspush

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/zeromicro/go-zero/core/logx"
)

type Pusher struct {
	url    string // 例 http://127.0.0.1:8889/internal/push
	token  string // 内部鉴权,与 ws 网关 InternalToken 一致
	client *http.Client
}

func New(url, token string) *Pusher {
	return &Pusher{url: url, token: token, client: &http.Client{Timeout: 2 * time.Second}}
}

type pushReq struct {
	UID  int64  `json:"uid"`
	Op   string `json:"op"`
	Data any    `json:"data,omitempty"`
}

// Push 尽力而为:网关不可达或用户离线只记日志,不阻塞业务事务(离线补偿靠登录拉取)。
// 返回值 online 表示对端此刻是否经 ws 在线收到该帧(false=离线,调用方可走离线推送补偿);
// 网关不可达时按 false 处理。
func (p *Pusher) Push(ctx context.Context, uid int64, op string, data any) (online bool) {
	if p.url == "" {
		return false
	}
	body, err := json.Marshal(pushReq{UID: uid, Op: op, Data: data})
	if err != nil {
		logx.WithContext(ctx).Errorf("wspush marshal: %v", err)
		return false
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.url, bytes.NewReader(body))
	if err != nil {
		logx.WithContext(ctx).Errorf("wspush request: %v", err)
		return false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", p.token)
	resp, err := p.client.Do(req)
	if err != nil {
		logx.WithContext(ctx).Errorf("wspush do: %v", err)
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		logx.WithContext(ctx).Errorf("wspush status: %s", resp.Status)
		return false
	}
	var out struct {
		Online bool `json:"online"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return false
	}
	return out.Online
}
