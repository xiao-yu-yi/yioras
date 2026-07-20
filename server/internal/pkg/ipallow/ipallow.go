// Package ipallow 后台 IP 白名单:启动时解析一次,请求期零分配匹配。
package ipallow

import (
	"fmt"
	"net"
	"strings"
)

// List 已解析的白名单。空列表 = 不限制。
type List struct {
	nets []*net.IPNet
}

// Parse 解析逗号分隔的 IP/CIDR 清单(如 "10.0.0.0/8, 203.0.113.7")。
// 裸 IP 自动按 /32(IPv4)或 /128(IPv6)处理;空串返回不限制的列表。
func Parse(spec string) (*List, error) {
	l := &List{}
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if !strings.Contains(part, "/") {
			ip := net.ParseIP(part)
			if ip == nil {
				return nil, fmt.Errorf("invalid ip %q", part)
			}
			bits := 32
			if ip.To4() == nil {
				bits = 128
			}
			part = fmt.Sprintf("%s/%d", part, bits)
		}
		_, n, err := net.ParseCIDR(part)
		if err != nil {
			return nil, fmt.Errorf("invalid cidr %q: %w", part, err)
		}
		l.nets = append(l.nets, n)
	}
	return l, nil
}

// Enabled 是否启用限制(配置了至少一条规则)。
func (l *List) Enabled() bool { return l != nil && len(l.nets) > 0 }

// Allowed 判断地址是否放行。addr 可带端口("1.2.3.4:56")或为 XFF 列表("1.2.3.4, 5.6.7.8",取第一跳)。
// 未启用限制时恒为 true;解析不出 IP 时拒绝。
func (l *List) Allowed(addr string) bool {
	if !l.Enabled() {
		return true
	}
	ip := extractIP(addr)
	if ip == nil {
		return false
	}
	for _, n := range l.nets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

func extractIP(addr string) net.IP {
	addr = strings.TrimSpace(addr)
	if i := strings.IndexByte(addr, ','); i >= 0 { // XFF 多跳取客户端第一跳
		addr = strings.TrimSpace(addr[:i])
	}
	if host, _, err := net.SplitHostPort(addr); err == nil {
		addr = host
	}
	return net.ParseIP(strings.Trim(addr, "[]"))
}
