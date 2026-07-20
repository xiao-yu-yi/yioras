// Package emailx 邮箱验证码发送,标准库 net/smtp,无第三方依赖。
package emailx

import (
	"fmt"
	"net/smtp"

	"github.com/zeromicro/go-zero/core/logx"
)

type Config struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
	Mock     bool
}

type Sender struct{ cfg Config }

func NewSender(cfg Config) *Sender { return &Sender{cfg: cfg} }

func (s *Sender) SendCode(to, code string) error {
	if s.cfg.Mock {
		logx.Infof("[emailx mock] send code %s to %s", code, to)
		return nil
	}
	body := fmt.Sprintf("From: Yiora <%s>\r\nTo: %s\r\nSubject: Yiora 验证码\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n您的验证码是 %s,10 分钟内有效。若非本人操作请忽略。\r\n",
		s.cfg.From, to, code)
	addr := fmt.Sprintf("%s:%d", s.cfg.Host, s.cfg.Port)
	auth := smtp.PlainAuth("", s.cfg.Username, s.cfg.Password, s.cfg.Host)
	if err := smtp.SendMail(addr, auth, s.cfg.From, []string{to}, []byte(body)); err != nil {
		return fmt.Errorf("smtp send to %s: %w", to, err)
	}
	return nil
}
