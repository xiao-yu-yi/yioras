// Package authlogic 邮箱注册/登录/验证码(v1.1 唯一登录方式)。
package authlogic

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"net/mail"
	"strings"

	"github.com/yiora/server/internal/logic/imlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/jwtx"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"golang.org/x/crypto/bcrypt"
)

const (
	codeTTLSec     = 600 // 验证码 10 分钟
	codeSendGapSec = 60  // 同邮箱发送间隔
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

func codeKey(scene, email string) string { return fmt.Sprintf("auth:code:%s:%s", scene, email) }

func normEmail(email string) (string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if _, err := mail.ParseAddress(email); err != nil {
		return "", xerr.Param("邮箱格式不正确")
	}
	return email, nil
}

// SendEmailCode 发送验证码。register 场景不提前校验邮箱是否已注册(避免注册状态探测),注册提交时再判。
func (l *Logic) SendEmailCode(ctx context.Context, req *types.EmailCodeReq) error {
	email, err := normEmail(req.Email)
	if err != nil {
		return err
	}
	// 60s 频控,SETNX 原子占位;按场景隔离,注册码不阻塞找回码
	ok, err := l.svcCtx.Redis.SetnxExCtx(ctx, "auth:code:rl:"+req.Scene+":"+email, "1", codeSendGapSec)
	if err != nil {
		return fmt.Errorf("code rate limit: %w", err)
	}
	if !ok {
		return xerr.New(xerr.CodeTooFrequent, "发送太频繁,请稍后再试")
	}
	code, err := randCode(6)
	if err != nil {
		return fmt.Errorf("gen code: %w", err)
	}
	if err := l.svcCtx.Redis.SetexCtx(ctx, codeKey(req.Scene, email), code, codeTTLSec); err != nil {
		return fmt.Errorf("store code: %w", err)
	}
	if err := l.svcCtx.Email.SendCode(email, code); err != nil {
		return fmt.Errorf("send code mail: %w", err)
	}
	return nil
}

func (l *Logic) Register(ctx context.Context, req *types.RegisterReq, ip string) (*types.TokenResp, error) {
	email, err := normEmail(req.Email)
	if err != nil {
		return nil, err
	}
	if n := len(req.Password); n < 8 || n > 32 {
		return nil, xerr.Param("密码长度需为 8-32 位")
	}
	if err := l.consumeCode(ctx, "register", email, req.Code); err != nil {
		return nil, err
	}
	if _, err := l.svcCtx.UserModel.FindAuthByEmail(ctx, email); err == nil {
		return nil, xerr.New(xerr.CodeEmailTaken, "该邮箱已注册,请直接登录")
	} else if !isNotFound(err) {
		return nil, fmt.Errorf("check email: %w", err)
	}

	nickname := strings.TrimSpace(req.Nickname)
	if nickname == "" {
		nickname = truncate(strings.SplitN(email, "@", 2)[0], 30)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}
	uid, err := l.svcCtx.UserModel.CreateWithEmail(ctx, nickname, email, string(hash))
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	_ = l.svcCtx.UserModel.TouchLogin(ctx, uid, ip)
	// AI 管家自动问候,新用户消息列表即出现管家会话(失败只记日志)
	imlogic.SendBotWelcome(ctx, l.svcCtx, uid)
	return l.issueToken(ctx, uid, nickname, "N"+fmt.Sprint(uid), "", req.DeviceName, ip, true)
}

func (l *Logic) Login(ctx context.Context, req *types.LoginReq, ip string) (*types.TokenResp, error) {
	email, err := normEmail(req.Email)
	if err != nil {
		return nil, err
	}
	auth, err := l.svcCtx.UserModel.FindAuthByEmail(ctx, email)
	if err != nil {
		if isNotFound(err) {
			return nil, xerr.New(xerr.CodeBadCredential, "邮箱或密码错误")
		}
		return nil, fmt.Errorf("find auth: %w", err)
	}
	if bcrypt.CompareHashAndPassword([]byte(auth.PasswordHash), []byte(req.Password)) != nil {
		return nil, xerr.New(xerr.CodeBadCredential, "邮箱或密码错误")
	}
	u, err := l.svcCtx.UserModel.FindByID(ctx, auth.UserID)
	if err != nil {
		return nil, fmt.Errorf("find user: %w", err)
	}
	if u.Status == 3 || u.Status == 4 {
		return nil, xerr.New(xerr.CodeForbidden, "账号不可用")
	}
	_ = l.svcCtx.UserModel.TouchLogin(ctx, u.ID, ip)
	return l.issueToken(ctx, u.ID, u.Nickname, u.DisplayNo.String, u.Avatar, req.DeviceName, ip, false)
}

// ResetPassword 邮箱验证码重置密码(找回)。旧 JWT 在有效期内仍可用,会话吊销属后续版本。
func (l *Logic) ResetPassword(ctx context.Context, req *types.ResetPasswordReq) error {
	email, err := normEmail(req.Email)
	if err != nil {
		return err
	}
	if n := len(req.Password); n < 8 || n > 32 {
		return xerr.Param("密码长度需为 8-32 位")
	}
	if err := l.consumeCode(ctx, "reset", email, req.Code); err != nil {
		return err
	}
	auth, err := l.svcCtx.UserModel.FindAuthByEmail(ctx, email)
	if err != nil {
		if isNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "该邮箱未注册")
		}
		return fmt.Errorf("find auth: %w", err)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}
	return l.svcCtx.UserModel.UpdatePassword(ctx, auth.UserID, string(hash))
}

func (l *Logic) consumeCode(ctx context.Context, scene, email, input string) error {
	key := codeKey(scene, email)
	stored, err := l.svcCtx.Redis.GetCtx(ctx, key)
	if err != nil {
		return fmt.Errorf("load code: %w", err)
	}
	if stored == "" || stored != strings.TrimSpace(input) {
		return xerr.New(xerr.CodeBadCode, "验证码错误或已过期")
	}
	_, _ = l.svcCtx.Redis.DelCtx(ctx, key) // 一次性消费
	return nil
}

func (l *Logic) issueToken(ctx context.Context, uid int64, nickname, displayNo, avatar, deviceName, ip string, isNew bool) (*types.TokenResp, error) {
	deviceID, refreshToken, refreshExpireAt := l.registerDevice(ctx, uid, deviceName, ip)
	token, expireAt, err := jwtx.GenUserToken(l.svcCtx.Config.Auth.AccessSecret, uid, deviceID, l.svcCtx.Config.Auth.AccessExpire)
	if err != nil {
		return nil, fmt.Errorf("gen token: %w", err)
	}
	return &types.TokenResp{
		UserID: uid, Token: token, ExpireAt: expireAt,
		RefreshToken: refreshToken, RefreshExpireAt: refreshExpireAt, DeviceID: deviceID,
		IsNewUser: isNew, DisplayNo: displayNo, Nickname: nickname, Avatar: avatar,
	}, nil
}

func randCode(n int) (string, error) {
	var b strings.Builder
	for i := 0; i < n; i++ {
		d, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		fmt.Fprint(&b, d.Int64())
	}
	return b.String(), nil
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}

func isNotFound(err error) bool { return model.IsNotFound(err) }
