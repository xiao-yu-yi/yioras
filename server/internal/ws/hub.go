// Package ws IM 长连接网关:连接鉴权、心跳、在线路由。
// 消息收发协议帧: {"op":"ping"|"pong"|"msg"|"ack", "d":{...}}
package ws

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"

	"github.com/yiora/server/internal/pkg/jwtx"

	"github.com/gorilla/websocket"
	"github.com/zeromicro/go-zero/core/logx"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 75 * time.Second // 客户端心跳间隔 30s,给 2 个周期余量
	pingPeriod = 30 * time.Second
	maxMsgSize = 64 << 10
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	// App 客户端无 Origin 语义;Web 端接入时按域名白名单收紧
	CheckOrigin: func(*http.Request) bool { return true },
}

type Frame struct {
	Op string `json:"op"`
	D  any    `json:"d,omitempty"`
}

type client struct {
	uid  int64
	conn *websocket.Conn
	send chan Frame
}

// Hub 单机在线表。多实例部署时路由表迁移 Redis(uid->instance),扩展点见 Push。
type Hub struct {
	secret  string
	mu      sync.RWMutex
	clients map[int64]*client // ponytail: 单端在线,同 uid 新连接踢旧连接;多端在线时改 map[int64][]*client
}

func NewHub(secret string) *Hub {
	return &Hub{secret: secret, clients: make(map[int64]*client)}
}

// ServeWS 处理 GET /ws?token=xxx 握手。
func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	uid, err := jwtx.ParseUID(h.secret, r.URL.Query().Get("token"))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		logx.Errorf("ws upgrade uid=%d: %v", uid, err)
		return
	}
	c := &client{uid: uid, conn: conn, send: make(chan Frame, 64)}
	h.register(c)
	go c.writeLoop()
	go func() {
		defer h.unregister(c)
		c.readLoop(h)
	}()
}

// ServeInternalPush 处理 api 服务的内部下行推送 POST /internal/push。
// 仅内网部署+共享 token 鉴权;公网不得暴露该端口路径。
func (h *Hub) ServeInternalPush(internalToken string) http.HandlerFunc {
	type pushReq struct {
		UID  int64           `json:"uid"`
		Op   string          `json:"op"`
		Data json.RawMessage `json:"data"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		if internalToken == "" || r.Header.Get("X-Internal-Token") != internalToken {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		var req pushReq
		if err := json.NewDecoder(io.LimitReader(r.Body, maxMsgSize)).Decode(&req); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		online := h.Push(r.Context(), req.UID, Frame{Op: req.Op, D: req.Data})
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"online":%t}`, online)
	}
}

// Push 向在线用户推送帧;不在线返回 false,调用方走离线推送补偿。
// 发送必须在 RLock 内完成:close(send) 只发生在写锁内,读写锁互斥保证不会向已关闭 channel 发送。
func (h *Hub) Push(_ context.Context, uid int64, f Frame) bool {
	var sent, slow bool
	h.mu.RLock()
	c, ok := h.clients[uid]
	if ok {
		select {
		case c.send <- f:
			sent = true
		default: // 发送缓冲满视为慢连接,断开触发客户端重连补拉
			slow = true
		}
	}
	h.mu.RUnlock()
	if slow {
		h.unregister(c)
	}
	return sent
}

func (h *Hub) register(c *client) {
	h.mu.Lock()
	old, exists := h.clients[c.uid]
	h.clients[c.uid] = c
	if exists {
		close(old.send) // 与 Push 的 RLock 互斥,见 Push 注释
	}
	h.mu.Unlock()
	if exists {
		_ = old.conn.Close() // 立即释放旧连接,readLoop 随之退出
	}
}

func (h *Hub) unregister(c *client) {
	h.mu.Lock()
	if cur, ok := h.clients[c.uid]; ok && cur == c {
		delete(h.clients, c.uid)
		close(c.send)
	}
	h.mu.Unlock()
	_ = c.conn.Close()
}

func (c *client) readLoop(h *Hub) {
	c.conn.SetReadLimit(maxMsgSize)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(pongWait))
	})
	for {
		var f Frame
		if err := c.conn.ReadJSON(&f); err != nil {
			return
		}
		_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
		switch f.Op {
		case "ping":
			h.Push(context.Background(), c.uid, Frame{Op: "pong"})
		default:
			// M2 扩展点:客户端发消息走 HTTP API 落库后由消息服务调 Push 下行,
			// WS 上行仅保留心跳与 ack,避免长连接链路承载写路径。
		}
	}
}

func (c *client) writeLoop() {
	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()
	for {
		select {
		case f, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok { // 被踢下线或注销
				_ = c.conn.WriteMessage(websocket.CloseMessage, nil)
				return
			}
			if err := c.conn.WriteJSON(f); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
