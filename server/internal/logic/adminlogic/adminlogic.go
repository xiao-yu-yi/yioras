// Package adminlogic 管理后台:登录/RBAC/审核工作台/认证审核/圈主任命/操作日志。
// 所有敏感操作落 admin_op_log 留痕(需求 3.12)。
package adminlogic

import (
	"context"
	cryptorand "crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/yiora/server/internal/logic/uploadlogic"
	"github.com/yiora/server/internal/logic/userlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/apppush"
	"github.com/yiora/server/internal/pkg/captcha"
	"github.com/yiora/server/internal/pkg/jwtx"
	"github.com/yiora/server/internal/pkg/totp"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
	"golang.org/x/crypto/bcrypt"
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Captcha 生成登录图形验证码(一次性,5 分钟)。
func (l *Logic) Captcha(ctx context.Context) (*types.CaptchaResp, error) {
	id, img, err := captcha.New(ctx, l.svcCtx.Redis)
	if err != nil {
		return nil, err
	}
	return &types.CaptchaResp{CaptchaID: id, Image: img}, nil
}

// Login 后台登录:验证码前置(先消码再验密,防撞库)+ 同账号连续错密锁定,发放 8h 管理令牌。
func (l *Logic) Login(ctx context.Context, req *types.AdminLoginReq) (*types.AdminLoginResp, error) {
	if !captcha.Verify(ctx, l.svcCtx.Redis, req.CaptchaID, req.CaptchaCode) {
		return nil, xerr.Param("验证码错误或已过期")
	}
	username := strings.TrimSpace(req.Username)
	if locked, ttl := l.loginLocked(ctx, username); locked {
		return nil, xerr.New(xerr.CodeForbidden,
			fmt.Sprintf("失败次数过多,账号已锁定,请 %d 分钟后再试", (ttl+59)/60))
	}
	a, err := l.svcCtx.AdminModel.FindByUsername(ctx, username)
	if err != nil {
		if model.IsNotFound(err) {
			l.recordLoginFail(ctx, username) // 不存在的账号同样计数,防用户名枚举
			return nil, xerr.New(xerr.CodeBadCredential, "账号或密码错误")
		}
		return nil, fmt.Errorf("find admin: %w", err)
	}
	if a.Status != 1 {
		return nil, xerr.New(xerr.CodeForbidden, "账号已停用")
	}
	if bcrypt.CompareHashAndPassword([]byte(a.PasswordHash), []byte(req.Password)) != nil {
		l.recordLoginFail(ctx, username)
		return nil, xerr.New(xerr.CodeBadCredential, "账号或密码错误")
	}
	_, _ = l.svcCtx.Redis.DelCtx(ctx, loginFailKey(username)) // 成功即清空计数

	// 已开二步验证:密码通过只发 5 分钟票据,凭 TOTP/恢复码换正式令牌
	if a.TotpEnabled == 1 {
		ticket := randTicket()
		if err := l.svcCtx.Redis.SetexCtx(ctx, totpTicketKey(ticket), fmt.Sprintf("%d", a.ID), 300); err != nil {
			return nil, fmt.Errorf("store totp ticket: %w", err)
		}
		return &types.AdminLoginResp{TotpRequired: true, Ticket: ticket, Username: a.Username}, nil
	}
	return l.issueToken(ctx, a)
}

// LoginTotp 二步验证:票据 + 动态口令/恢复码 → 正式管理令牌。
func (l *Logic) LoginTotp(ctx context.Context, req *types.AdminTotpLoginReq) (*types.AdminLoginResp, error) {
	idStr, err := l.svcCtx.Redis.GetCtx(ctx, totpTicketKey(req.Ticket))
	if err != nil || idStr == "" {
		return nil, xerr.New(xerr.CodeUnauthorized, "登录票据无效或已过期,请重新登录")
	}
	adminID, _ := strconv.ParseInt(idStr, 10, 64)
	a, err := l.svcCtx.AdminModel.FindAdminByID(ctx, adminID)
	if err != nil {
		return nil, fmt.Errorf("find admin: %w", err)
	}
	if a.Status != 1 {
		return nil, xerr.New(xerr.CodeForbidden, "账号已停用")
	}
	if !l.verifySecondFactor(ctx, a, req.Code) {
		return nil, xerr.New(xerr.CodeBadCode, "动态口令错误或已被使用")
	}
	_, _ = l.svcCtx.Redis.DelCtx(ctx, totpTicketKey(req.Ticket)) // 票据一次性
	return l.issueToken(ctx, a)
}

// verifySecondFactor 校验 6 位 TOTP(同码防重放)或一次性恢复码。
func (l *Logic) verifySecondFactor(ctx context.Context, a *model.AdminUser, code string) bool {
	code = strings.TrimSpace(code)
	if a.TotpEnabled != 1 {
		return false
	}
	if len(code) == totp.Digits {
		step, ok := totp.Verify(a.TotpSecret, code, time.Now())
		if !ok {
			return false
		}
		// 同一时间步的码只能用一次(防抓包重放)
		usedKey := fmt.Sprintf("admin:totp:used:%d:%d", a.ID, step)
		set, err := l.svcCtx.Redis.SetnxExCtx(ctx, usedKey, "1", 120)
		return err == nil && set
	}
	// 长度不符则按恢复码消费
	used, err := l.svcCtx.AdminModel.UseRecoveryCode(ctx, a.ID, hashRecovery(code))
	return err == nil && used
}

// issueToken 密码(及二步验证)通过后的统一发令牌出口。
func (l *Logic) issueToken(ctx context.Context, a *model.AdminUser) (*types.AdminLoginResp, error) {
	perms, err := l.svcCtx.AdminModel.RolePerms(ctx, a.RoleID)
	if err != nil {
		return nil, fmt.Errorf("role perms: %w", err)
	}
	token, expireAt, err := jwtx.GenAdminToken(l.svcCtx.Config.Auth.AccessSecret, a.ID, a.RoleID)
	if err != nil {
		return nil, fmt.Errorf("gen admin token: %w", err)
	}
	l.svcCtx.AdminModel.TouchLogin(ctx, a.ID)
	return &types.AdminLoginResp{
		Token: token, ExpireAt: expireAt, Username: a.Username, Perms: perms,
	}, nil
}

func totpTicketKey(t string) string  { return "admin:totp:ticket:" + t }
func totpPendingKey(id int64) string { return fmt.Sprintf("admin:totp:pending:%d", id) }

func randTicket() string {
	b := make([]byte, 24)
	_, _ = cryptorand.Read(b)
	return hex.EncodeToString(b)
}

func hashRecovery(code string) string {
	sum := sha256.Sum256([]byte(strings.ToUpper(strings.TrimSpace(code))))
	return hex.EncodeToString(sum[:])
}

// TotpStatus 当前账号二步验证状态。
func (l *Logic) TotpStatus(ctx context.Context, adminID int64) (*types.TotpStatusResp, error) {
	a, err := l.svcCtx.AdminModel.FindAdminByID(ctx, adminID)
	if err != nil {
		return nil, fmt.Errorf("find admin: %w", err)
	}
	left, err := l.svcCtx.AdminModel.RecoveryCodesLeft(ctx, adminID)
	if err != nil {
		return nil, fmt.Errorf("recovery left: %w", err)
	}
	return &types.TotpStatusResp{Enabled: a.TotpEnabled == 1, RecoveryCodesLeft: left}, nil
}

// TotpSetup 发起绑定:生成密钥与 10 个恢复码,暂存 Redis 10 分钟,confirm 验证通过才落库。
func (l *Logic) TotpSetup(ctx context.Context, adminID int64) (*types.TotpSetupResp, error) {
	a, err := l.svcCtx.AdminModel.FindAdminByID(ctx, adminID)
	if err != nil {
		return nil, fmt.Errorf("find admin: %w", err)
	}
	if a.TotpEnabled == 1 {
		return nil, xerr.New(xerr.CodeTooFrequent, "已启用二步验证,如需换绑请先解绑")
	}
	secret, err := totp.NewSecret()
	if err != nil {
		return nil, err
	}
	codes := make([]string, 10)
	hashes := make([]string, 10)
	for i := range codes {
		b := make([]byte, 5)
		_, _ = cryptorand.Read(b)
		codes[i] = strings.ToUpper(hex.EncodeToString(b)) // 10 位 hex 恢复码
		hashes[i] = hashRecovery(codes[i])
	}
	pending, _ := json.Marshal(map[string]any{"secret": secret, "hashes": hashes})
	if err := l.svcCtx.Redis.SetexCtx(ctx, totpPendingKey(adminID), string(pending), 600); err != nil {
		return nil, fmt.Errorf("store totp pending: %w", err)
	}
	return &types.TotpSetupResp{
		Secret: secret, URI: totp.URI(secret, a.Username, "Yiora-Admin"), RecoveryCodes: codes,
	}, nil
}

// TotpConfirm 输入验证器当前口令,校验通过才真正启用(防绑错设备锁死账号)。
func (l *Logic) TotpConfirm(ctx context.Context, adminID int64, req *types.TotpCodeReq, ip string) error {
	raw, err := l.svcCtx.Redis.GetCtx(ctx, totpPendingKey(adminID))
	if err != nil || raw == "" {
		return xerr.New(xerr.CodeNotFound, "绑定会话已过期,请重新发起")
	}
	var pending struct {
		Secret string   `json:"secret"`
		Hashes []string `json:"hashes"`
	}
	if err := json.Unmarshal([]byte(raw), &pending); err != nil {
		return fmt.Errorf("parse totp pending: %w", err)
	}
	if _, ok := totp.Verify(pending.Secret, req.Code, time.Now()); !ok {
		return xerr.New(xerr.CodeBadCode, "动态口令错误,请核对验证器")
	}
	if err := l.svcCtx.AdminModel.EnableTotp(ctx, adminID, pending.Secret, pending.Hashes); err != nil {
		return err
	}
	_, _ = l.svcCtx.Redis.DelCtx(ctx, totpPendingKey(adminID))
	l.opLog(ctx, adminID, "admin.totp.enable", fmt.Sprintf("admin:%d", adminID), "", ip)
	return nil
}

// TotpDisable 解绑:需当前动态口令或恢复码。
func (l *Logic) TotpDisable(ctx context.Context, adminID int64, req *types.TotpCodeReq, ip string) error {
	a, err := l.svcCtx.AdminModel.FindAdminByID(ctx, adminID)
	if err != nil {
		return fmt.Errorf("find admin: %w", err)
	}
	if a.TotpEnabled != 1 {
		return xerr.New(xerr.CodeNotFound, "尚未启用二步验证")
	}
	if !l.verifySecondFactor(ctx, a, req.Code) {
		return xerr.New(xerr.CodeBadCode, "动态口令错误或已被使用")
	}
	if err := l.svcCtx.AdminModel.DisableTotp(ctx, adminID); err != nil {
		return err
	}
	l.opLog(ctx, adminID, "admin.totp.disable", fmt.Sprintf("admin:%d", adminID), "", ip)
	return nil
}

func loginFailKey(username string) string { return "admin:login:fail:" + username }

// lockPolicy 锁定参数,配置缺失/非法时落安全默认(5 次/900 秒),避免零值把 expire 0 变成立即删 key。
func (l *Logic) lockPolicy() (limit, lockSec int) {
	limit, lockSec = l.svcCtx.Config.Admin.LoginFailLimit, l.svcCtx.Config.Admin.LoginLockSec
	if limit <= 0 {
		limit = 5
	}
	if lockSec <= 0 {
		lockSec = 900
	}
	return limit, lockSec
}

// loginLocked 达到错密上限即锁定,锁定期 = 计数 key 剩余 TTL(固定窗口)。
func (l *Logic) loginLocked(ctx context.Context, username string) (bool, int) {
	limit, lockSec := l.lockPolicy()
	n, err := l.svcCtx.Redis.GetCtx(ctx, loginFailKey(username))
	if err != nil || n == "" {
		return false, 0
	}
	cnt, _ := strconv.Atoi(n)
	if cnt < limit {
		return false, 0
	}
	ttl, err := l.svcCtx.Redis.TtlCtx(ctx, loginFailKey(username))
	if err != nil || ttl <= 0 {
		ttl = lockSec
	}
	return true, ttl
}

// recordLoginFail 错密计数 +1;首次失败起固定窗口(窗口内攒满即锁到窗口结束)。
func (l *Logic) recordLoginFail(ctx context.Context, username string) {
	limit, lockSec := l.lockPolicy()
	key := loginFailKey(username)
	cnt, err := l.svcCtx.Redis.IncrCtx(ctx, key)
	if err != nil {
		logx.WithContext(ctx).Errorf("login fail incr: %v", err)
		return
	}
	if cnt == 1 {
		if err := l.svcCtx.Redis.ExpireCtx(ctx, key, lockSec); err != nil {
			logx.WithContext(ctx).Errorf("login fail expire: %v", err)
		}
	}
	if int(cnt) >= limit {
		logx.WithContext(ctx).Errorf("admin login locked: username=%s fails=%d", username, cnt)
	}
}

// ChangePassword 管理员改密:验旧密+强度校验,清除强制改密标记。
func (l *Logic) ChangePassword(ctx context.Context, adminID int64, req *types.AdminChangePwdReq, ip string) error {
	a, err := l.svcCtx.AdminModel.FindAdminByID(ctx, adminID)
	if err != nil {
		return fmt.Errorf("find admin: %w", err)
	}
	if bcrypt.CompareHashAndPassword([]byte(a.PasswordHash), []byte(req.OldPassword)) != nil {
		return xerr.New(xerr.CodeBadCredential, "原密码错误")
	}
	if err := checkPwdStrength(req.NewPassword); err != nil {
		return err
	}
	if req.NewPassword == req.OldPassword {
		return xerr.Param("新密码不能与原密码相同")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}
	if err := l.svcCtx.AdminModel.UpdateAdminPassword(ctx, adminID, string(hash)); err != nil {
		return err
	}
	l.opLog(ctx, adminID, "admin.password.change", fmt.Sprintf("admin:%d", adminID), "", ip)
	return nil
}

// checkPwdStrength 后台密码强度:至少 8 位且同时含字母与数字。
func checkPwdStrength(pwd string) error {
	if len(pwd) < 8 || len(pwd) > 64 {
		return xerr.Param("密码长度需为 8-64 位")
	}
	var hasLetter, hasDigit bool
	for _, c := range pwd {
		switch {
		case c >= '0' && c <= '9':
			hasDigit = true
		case (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'):
			hasLetter = true
		}
	}
	if !hasLetter || !hasDigit {
		return xerr.Param("密码必须同时包含字母和数字")
	}
	return nil
}

// Admins 后台账号列表(账号管理页)。
func (l *Logic) Admins(ctx context.Context) ([]types.AdminAccountItem, error) {
	rows, err := l.svcCtx.AdminModel.ListAdmins(ctx)
	if err != nil {
		return nil, fmt.Errorf("list admins: %w", err)
	}
	out := make([]types.AdminAccountItem, 0, len(rows))
	for _, a := range rows {
		item := types.AdminAccountItem{
			ID: a.ID, Username: a.Username, RoleID: a.RoleID, RoleName: a.RoleName,
			Status: a.Status,
		}
		if a.LastLoginAt.Valid {
			item.LastLoginAt = a.LastLoginAt.Time.UnixMilli()
		}
		out = append(out, item)
	}
	return out, nil
}

// CreateAdmin 新建后台账号,初始密码由创建者设定,首登强制改密。
func (l *Logic) CreateAdmin(ctx context.Context, adminID int64, req *types.AdminCreateAccountReq, ip string) (int64, error) {
	username := strings.TrimSpace(req.Username)
	if len(username) < 3 || len(username) > 30 {
		return 0, xerr.Param("用户名长度需为 3-30 位")
	}
	if err := checkPwdStrength(req.Password); err != nil {
		return 0, err
	}
	if _, err := l.svcCtx.AdminModel.RolePerms(ctx, req.RoleID); err != nil {
		if model.IsNotFound(err) {
			return 0, xerr.Param("角色不存在")
		}
		return 0, fmt.Errorf("check role: %w", err)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return 0, fmt.Errorf("hash password: %w", err)
	}
	id, err := l.svcCtx.AdminModel.CreateAdmin(ctx, username, string(hash), req.RoleID)
	if err != nil {
		if errors.Is(err, model.ErrAdminExists) {
			return 0, xerr.New(xerr.CodeTooFrequent, "用户名已存在")
		}
		return 0, err
	}
	l.opLog(ctx, adminID, "admin.account.create", fmt.Sprintf("admin:%d(%s) role:%d", id, username, req.RoleID), "", ip)
	return id, nil
}

// UpdateAdmin 调整角色/启停/重置密码。禁止操作自己(防误锁死)。
func (l *Logic) UpdateAdmin(ctx context.Context, adminID int64, req *types.AdminUpdateAccountReq, ip string) error {
	if req.ID == adminID {
		return xerr.New(xerr.CodeForbidden, "不能对自己的账号执行此操作,改密请用修改密码功能")
	}
	if _, err := l.svcCtx.AdminModel.FindAdminByID(ctx, req.ID); err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "账号不存在")
		}
		return fmt.Errorf("find admin: %w", err)
	}
	if req.RoleID > 0 {
		if _, err := l.svcCtx.AdminModel.RolePerms(ctx, req.RoleID); err != nil {
			if model.IsNotFound(err) {
				return xerr.Param("角色不存在")
			}
			return fmt.Errorf("check role: %w", err)
		}
	}
	var hash string
	if req.NewPassword != "" {
		if err := checkPwdStrength(req.NewPassword); err != nil {
			return err
		}
		b, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
		if err != nil {
			return fmt.Errorf("hash password: %w", err)
		}
		hash = string(b)
	}
	if err := l.svcCtx.AdminModel.UpdateAdmin(ctx, req.ID, req.RoleID, req.Status, hash); err != nil {
		return err
	}
	if req.ResetTotp {
		if err := l.svcCtx.AdminModel.DisableTotp(ctx, req.ID); err != nil {
			return err
		}
	}
	l.opLog(ctx, adminID, "admin.account.update",
		fmt.Sprintf("admin:%d role:%d status:%d resetPwd:%t resetTotp:%t", req.ID, req.RoleID, req.Status, hash != "", req.ResetTotp), "", ip)
	return nil
}

// Roles 角色下拉(账号管理页分配用)。
func (l *Logic) Roles(ctx context.Context) ([]types.AdminRoleItem, error) {
	rows, err := l.svcCtx.AdminModel.ListRoles(ctx)
	if err != nil {
		return nil, fmt.Errorf("list roles: %w", err)
	}
	out := make([]types.AdminRoleItem, 0, len(rows))
	for _, r := range rows {
		item := types.AdminRoleItem{ID: r.ID, Name: r.Name, Perms: []string{}}
		if err := json.Unmarshal([]byte(r.Permissions), &item.Perms); err != nil {
			logx.WithContext(ctx).Errorf("role %d perms parse: %v", r.ID, err)
		}
		out = append(out, item)
	}
	return out, nil
}

// RequirePerm RBAC 校验:角色权限含 "*" 或指定权限码。
func (l *Logic) RequirePerm(ctx context.Context, roleID int64, perm string) error {
	perms, err := l.svcCtx.AdminModel.RolePerms(ctx, roleID)
	if err != nil {
		return fmt.Errorf("role perms: %w", err)
	}
	for _, p := range perms {
		if p == "*" || p == perm {
			return nil
		}
	}
	return xerr.New(xerr.CodeForbidden, "没有该操作权限")
}

// Audits 待人审队列。
func (l *Logic) Audits(ctx context.Context, req *types.AuditListReq) ([]types.AuditQueueItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.AdminModel.PendingAudits(ctx, req.BizType, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("pending audits: %w", err)
	}
	out := make([]types.AuditQueueItem, 0, len(rows))
	for _, a := range rows {
		out = append(out, types.AuditQueueItem{
			ID: a.ID, BizType: a.BizType, BizID: a.BizID,
			MachineResult: a.MachineResult, MachineDetail: a.MachineDetail,
			CreatedAt: a.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// Decide 审核单裁决:按 biz_type 分发落地,通知作者,落操作日志。
func (l *Logic) Decide(ctx context.Context, adminID int64, req *types.AuditDecideReq, ip string) error {
	if !req.Approve && strings.TrimSpace(req.Reason) == "" {
		return xerr.Param("驳回必须填写原因")
	}
	audit, err := l.svcCtx.AdminModel.FindAudit(ctx, req.AuditID)
	if err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "审核单不存在")
		}
		return fmt.Errorf("find audit: %w", err)
	}

	var authorID int64
	var noun string
	switch audit.BizType {
	case model.AuditBizPost:
		noun = "帖子"
		authorID, err = l.svcCtx.AdminModel.DecidePost(ctx, audit.ID, audit.BizID, adminID, req.Approve, req.Reason)
	case model.AuditBizComment:
		noun = "评论"
		authorID, err = l.svcCtx.AdminModel.DecideComment(ctx, audit.ID, audit.BizID, adminID, req.Approve, req.Reason)
	case model.AuditBizSoftware:
		noun = "软件"
		var detail struct {
			Kind      string `json:"kind"`
			VersionID int64  `json:"versionId"`
		}
		if audit.MachineDetail != "" {
			if err := json.Unmarshal([]byte(audit.MachineDetail), &detail); err != nil {
				logx.WithContext(ctx).Errorf("audit %d detail parse: %v", audit.ID, err)
			}
		}
		if detail.Kind == "" {
			detail.Kind = "software"
		}
		authorID, err = l.svcCtx.AdminModel.DecideSoftware(ctx, audit.ID, audit.BizID, detail.VersionID, adminID, detail.Kind, req.Approve, req.Reason)
	default:
		return xerr.Param("未知的审核类型")
	}
	if err != nil {
		if errors.Is(err, model.ErrAuditDone) {
			return xerr.New(xerr.CodeTooFrequent, "该审核单已被处理")
		}
		return fmt.Errorf("decide audit: %w", err)
	}

	// 审核结果通知作者(系统通知)
	text := "你的" + noun + "已通过审核"
	if !req.Approve {
		text = "你的" + noun + "未通过审核: " + req.Reason
	}
	if authorID > 0 {
		if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
			UserID: authorID, Type: model.NotifyTypeSystem, TargetID: audit.BizID, Content: text,
		}); err != nil {
			logx.WithContext(ctx).Errorf("audit notification: %v", err)
		}
	}
	l.opLog(ctx, adminID, decisionAction("audit", req.Approve),
		fmt.Sprintf("audit:%d biz:%d/%d", audit.ID, audit.BizType, audit.BizID), req.Reason, ip)
	return nil
}

// Certs 待审认证队列。
func (l *Logic) Certs(ctx context.Context, req *types.PageReq) ([]types.AdminCertItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.AdminModel.PendingCerts(ctx, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("pending certs: %w", err)
	}
	out := make([]types.AdminCertItem, 0, len(rows))
	for _, c := range rows {
		out = append(out, types.AdminCertItem{
			ID: c.ID, UserID: c.UserID, Kind: c.Kind, Material: c.Material, CreatedAt: c.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// DecideCert 认证裁决 + 通知 + 留痕。
func (l *Logic) DecideCert(ctx context.Context, adminID int64, req *types.CertDecideReq, ip string) error {
	if !req.Approve && strings.TrimSpace(req.Reason) == "" {
		return xerr.Param("驳回必须填写原因")
	}
	userID, kind, err := l.svcCtx.AdminModel.DecideCert(ctx, req.CertID, req.Approve, req.Reason)
	if err != nil {
		switch {
		case model.IsNotFound(err):
			return xerr.New(xerr.CodeNotFound, "认证申请不存在")
		case errors.Is(err, model.ErrAuditDone):
			return xerr.New(xerr.CodeTooFrequent, "该申请已被处理")
		}
		return fmt.Errorf("decide cert: %w", err)
	}
	noun := "达人认证"
	if kind == 2 {
		noun = "开发者认证"
	}
	text := "你的" + noun + "已通过,头衔徽章已点亮"
	if !req.Approve {
		text = "你的" + noun + "未通过: " + req.Reason
	}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: userID, Type: model.NotifyTypeSystem, Content: text,
	}); err != nil {
		logx.WithContext(ctx).Errorf("cert notification: %v", err)
	}
	l.opLog(ctx, adminID, decisionAction("cert", req.Approve),
		fmt.Sprintf("cert:%d user:%d", req.CertID, userID), req.Reason, ip)
	return nil
}

// Circles 后台圈子列表。
func (l *Logic) Circles(ctx context.Context, req *types.AdminCircleListReq) (*types.AdminCircleListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.AdminModel.ListCirclesAdmin(ctx, strings.TrimSpace(req.Keyword), offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminCircleListResp{Total: total, List: make([]types.AdminCircleItem, 0, len(rows))}
	for _, c := range rows {
		out.List = append(out.List, types.AdminCircleItem{
			ID: c.ID, Name: c.Name, Icon: c.Icon, Cover: c.Cover, Intro: c.Intro, Description: c.Description,
			MemberCount: c.MemberCount, PostCount: c.PostCount, IsOfficial: c.IsOfficial,
			Pinned: c.Pinned, Sort: c.Sort, Status: c.Status,
		})
	}
	return out, nil
}

// SaveCircle 新建/更新圈子(名称唯一;图标必须直传)。
func (l *Logic) SaveCircle(ctx context.Context, adminID int64, req *types.AdminCircleSaveReq, ip string) (int64, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" || len([]rune(name)) > 30 {
		return 0, xerr.Param("圈子名长度需为 1-30 字符")
	}
	if !uploadlogic.AllowedImageURL(l.svcCtx.Config, req.Icon) {
		return 0, xerr.Param("圈子图标链接不合法,请通过上传获取")
	}
	if req.Cover != "" && !uploadlogic.AllowedImageURL(l.svcCtx.Config, req.Cover) {
		return 0, xerr.Param("封面链接不合法,请通过上传获取")
	}
	id, ok, err := l.svcCtx.AdminModel.SaveCircleAdmin(ctx, &model.AdminCircleRow{
		ID: req.ID, Name: name, Icon: req.Icon, Cover: req.Cover,
		Intro: strings.TrimSpace(req.Intro), Description: strings.TrimSpace(req.Description),
		IsOfficial: req.IsOfficial, Pinned: req.Pinned, Sort: req.Sort, Status: req.Status,
	})
	if err != nil {
		if errors.Is(err, model.ErrCircleExists) {
			return 0, xerr.New(xerr.CodeTooFrequent, "圈子名已存在")
		}
		return 0, err
	}
	if !ok {
		return 0, xerr.New(xerr.CodeNotFound, "圈子不存在")
	}
	l.opLog(ctx, adminID, "circle.save", fmt.Sprintf("circle:%d status:%d", id, req.Status), "", ip)
	return id, nil
}

// PostOps 帖子运营位:首页置顶/加精。
func (l *Logic) PostOps(ctx context.Context, adminID int64, req *types.AdminPostOpsReq, ip string) error {
	ok, err := l.svcCtx.AdminModel.SetPostOps(ctx, req.PostID, req.IsTop, req.IsEssence)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "帖子不存在或未发布")
	}
	l.opLog(ctx, adminID, "content.postops",
		fmt.Sprintf("post:%d top:%d essence:%d", req.PostID, req.IsTop, req.IsEssence), "", ip)
	return nil
}

// Topics 后台话题列表。
func (l *Logic) Topics(ctx context.Context, req *types.AdminTopicListReq) (*types.AdminTopicListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.AdminModel.ListTopicsAdmin(ctx, strings.TrimSpace(req.Keyword), req.Status, offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminTopicListResp{Total: total, List: make([]types.AdminTopicItem, 0, len(rows))}
	for _, t := range rows {
		out.List = append(out.List, types.AdminTopicItem{
			ID: t.ID, Name: t.Name, PostCount: t.PostCount, HotScore: t.HotScore,
			Status: t.Status, CreatedAt: t.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// UpdateTopic 话题封禁/恢复/热度调整。
func (l *Logic) UpdateTopic(ctx context.Context, adminID int64, req *types.AdminTopicUpdateReq, ip string) error {
	ok, err := l.svcCtx.AdminModel.UpdateTopicAdmin(ctx, req.TopicID, req.Status, req.HotScore)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "话题不存在")
	}
	l.opLog(ctx, adminID, "content.topic",
		fmt.Sprintf("topic:%d status:%d hot:%d", req.TopicID, req.Status, req.HotScore), "", ip)
	return nil
}

// Appoint 圈主/管理员任命。
func (l *Logic) Appoint(ctx context.Context, adminID int64, req *types.AppointReq, ip string) error {
	if _, err := l.svcCtx.CircleModel.FindByID(ctx, req.CircleID); err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "圈子不存在")
		}
		return fmt.Errorf("find circle: %w", err)
	}
	if _, err := l.svcCtx.UserModel.FindByID(ctx, req.UserID); err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "用户不存在")
		}
		return fmt.Errorf("find user: %w", err)
	}
	if err := l.svcCtx.AdminModel.AppointCircleRole(ctx, req.CircleID, req.UserID, req.Role); err != nil {
		return err
	}
	if req.Role >= model.CircleRoleAdmin {
		if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
			UserID: req.UserID, Type: model.NotifyTypeSystem,
			Content: "你已被任命为圈子管理员,请遵守社区规范用好管理权限",
		}); err != nil {
			logx.WithContext(ctx).Errorf("appoint notification: %v", err)
		}
	}
	l.opLog(ctx, adminID, "circle.appoint",
		fmt.Sprintf("circle:%d user:%d role:%d", req.CircleID, req.UserID, req.Role), "", ip)
	return nil
}

// OpLogs 操作日志列表。
func (l *Logic) OpLogs(ctx context.Context, req *types.PageReq) ([]types.OpLogItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.AdminModel.OpLogs(ctx, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("op logs: %w", err)
	}
	out := make([]types.OpLogItem, 0, len(rows))
	for _, r := range rows {
		out = append(out, types.OpLogItem{
			ID: r.ID, AdminID: r.AdminID, Action: r.Action, Target: r.Target,
			IP: r.IP, CreatedAt: r.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// PublishNotice 公告落库并全员群发系统通知。
func (l *Logic) PublishNotice(ctx context.Context, adminID int64, req *types.AdminNoticeReq, ip string) error {
	title := strings.TrimSpace(req.Title)
	content := strings.TrimSpace(req.Content)
	if title == "" || content == "" {
		return xerr.Param("公告标题与内容不能为空")
	}
	noticeID, err := l.svcCtx.AdminModel.PublishNotice(ctx, adminID, title, content)
	if err != nil {
		return fmt.Errorf("publish notice: %w", err)
	}
	l.opLog(ctx, adminID, "ops.notice", fmt.Sprintf("notice:%d", noticeID), title, ip)
	return nil
}

// Agreement 协议内容(用户侧/后台共用读取)。
// agreementKinds 协议/静态文案合法类型;bot_prompt 为管家 LLM 系统提示词(仅后台可读写,用户侧接口拒绝)。
var agreementKinds = map[string]bool{"user": true, "privacy": true, "bot_prompt": true}

// PushStats 推送渠道看板:各渠道发送/失败日计数(apppush.Manager 写入)。
func (l *Logic) PushStats(ctx context.Context, days int) (*types.PushStatsResp, error) {
	out := &types.PushStatsResp{Channels: []types.PushChannelStat{}}
	getN := func(key string) int64 {
		v, err := l.svcCtx.Redis.GetCtx(ctx, key)
		if err != nil || v == "" {
			return 0
		}
		n, _ := strconv.ParseInt(v, 10, 64)
		return n
	}
	for _, ch := range l.svcCtx.AppPush.Channels() {
		stat := types.PushChannelStat{Channel: ch}
		for i := days - 1; i >= 0; i-- {
			day := time.Now().AddDate(0, 0, -i)
			ok := getN(apppush.StatKey(ch, "ok", day.Format("20060102")))
			fail := getN(apppush.StatKey(ch, "fail", day.Format("20060102")))
			stat.OK += ok
			stat.Fail += fail
			stat.Days = append(stat.Days, struct {
				Date string `json:"date"`
				OK   int64  `json:"ok"`
				Fail int64  `json:"fail"`
			}{Date: day.Format("2006-01-02"), OK: ok, Fail: fail})
		}
		out.Channels = append(out.Channels, stat)
	}
	return out, nil
}

// BotStats 管家应答命中来源统计(Redis 按日计数,imlogic.botReply 写入)。
func (l *Logic) BotStats(ctx context.Context, days int) (*types.BotStatsResp, error) {
	out := &types.BotStatsResp{Days: make([]types.BotStatDay, 0, days)}
	for i := days - 1; i >= 0; i-- {
		day := time.Now().AddDate(0, 0, -i)
		key := day.Format("20060102")
		row := types.BotStatDay{Date: day.Format("2006-01-02")}
		for _, src := range []string{"faq", "llm", "fallback"} {
			v, err := l.svcCtx.Redis.GetCtx(ctx, fmt.Sprintf("bot:stat:%s:%s", src, key))
			if err != nil || v == "" {
				continue
			}
			n, _ := strconv.ParseInt(v, 10, 64)
			switch src {
			case "faq":
				row.Faq = n
			case "llm":
				row.LLM = n
			case "fallback":
				row.Fallback = n
			}
		}
		out.Days = append(out.Days, row)
	}
	return out, nil
}

func (l *Logic) Agreement(ctx context.Context, kind string) (*types.AgreementResp, error) {
	if !agreementKinds[kind] {
		return nil, xerr.Param("协议类型不存在")
	}
	row, err := l.svcCtx.AdminModel.GetAgreement(ctx, kind)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "协议不存在")
		}
		return nil, fmt.Errorf("get agreement: %w", err)
	}
	return &types.AgreementResp{
		Kind: row.Kind, Title: row.Title, Content: row.Content, UpdatedAt: row.UpdatedAt.UnixMilli(),
	}, nil
}

// SaveAgreement 后台编辑协议。
func (l *Logic) SaveAgreement(ctx context.Context, adminID int64, req *types.AdminAgreementSaveReq, ip string) error {
	if !agreementKinds[req.Kind] {
		return xerr.Param("协议类型不存在")
	}
	title := strings.TrimSpace(req.Title)
	content := strings.TrimSpace(req.Content)
	if title == "" || content == "" {
		return xerr.Param("标题与正文不能为空")
	}
	if err := l.svcCtx.AdminModel.SaveAgreement(ctx, req.Kind, title, content); err != nil {
		return err
	}
	l.opLog(ctx, adminID, "ops.agreement", "agreement:"+req.Kind, "", ip)
	return nil
}

// SetUserLevel 后台调整用户等级/经验。
func (l *Logic) SetUserLevel(ctx context.Context, adminID int64, req *types.AdminUserLevelReq, ip string) error {
	if req.Level < -1 || req.Level > 100 || req.Exp > 100000000 {
		return xerr.Param("等级需在 0-100,经验需在 1 亿以内")
	}
	ok, err := l.svcCtx.AdminModel.SetUserLevel(ctx, req.UserID, req.Level, req.Exp)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "用户不存在或已注销")
	}
	l.opLog(ctx, adminID, "user.level",
		fmt.Sprintf("user:%d level:%d exp:%d", req.UserID, req.Level, req.Exp), "", ip)
	return nil
}

// GrantUserTitle 授予/撤销头衔(达人/开发者认证徽章)。
func (l *Logic) GrantUserTitle(ctx context.Context, adminID int64, req *types.AdminUserTitleReq, ip string) error {
	if _, err := l.svcCtx.UserModel.FindByID(ctx, req.UserID); err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "用户不存在")
		}
		return fmt.Errorf("find user: %w", err)
	}
	if err := l.svcCtx.AdminModel.GrantTitle(ctx, req.UserID, req.Kind, req.Grant); err != nil {
		return err
	}
	noun := "达人认证"
	if req.Kind == 2 {
		noun = "开发者认证"
	}
	text := "管理员已授予你" + noun + "头衔"
	if !req.Grant {
		text = "你的" + noun + "头衔已被撤销"
	}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: req.UserID, Type: model.NotifyTypeSystem, Content: text,
	}); err != nil {
		logx.WithContext(ctx).Errorf("title notification: %v", err)
	}
	l.opLog(ctx, adminID, "user.title",
		fmt.Sprintf("user:%d kind:%d grant:%t", req.UserID, req.Kind, req.Grant), "", ip)
	return nil
}

// Users 后台用户搜索列表(昵称/编号/邮箱模糊 + 状态筛选,分页带 total)。
func (l *Logic) Users(ctx context.Context, req *types.AdminUserListReq) (*types.AdminUserListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.AdminModel.SearchUsers(ctx, strings.TrimSpace(req.Keyword), req.Status, offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminUserListResp{Total: total, List: make([]types.AdminUserItem, 0, len(rows))}
	for _, u := range rows {
		item := types.AdminUserItem{
			UserID: u.ID, DisplayNo: u.DisplayNo, Nickname: u.Nickname, Avatar: u.Avatar,
			Email: u.Email, Level: u.Level, Status: u.Status, CreatedAt: u.CreatedAt.UnixMilli(),
		}
		if u.LastLoginAt.Valid {
			item.LastLoginAt = u.LastLoginAt.Time.UnixMilli()
		}
		out.List = append(out.List, item)
	}
	return out, nil
}

// Contents 后台内容检索(帖子/评论,关键词+全状态筛选)。
func (l *Logic) Contents(ctx context.Context, req *types.AdminContentListReq) (*types.AdminContentListResp, error) {
	offset, limit := req.Offset()
	kw := strings.TrimSpace(req.Keyword)
	var (
		total int64
		rows  []*model.AdminContentRow
		err   error
	)
	if req.Type == 1 {
		total, rows, err = l.svcCtx.AdminModel.SearchPostsAdmin(ctx, kw, req.Status, offset, limit)
	} else {
		total, rows, err = l.svcCtx.AdminModel.SearchCommentsAdmin(ctx, kw, req.Status, offset, limit)
	}
	if err != nil {
		return nil, err
	}
	out := &types.AdminContentListResp{Total: total, List: make([]types.AdminContentItem, 0, len(rows))}
	for _, r := range rows {
		out.List = append(out.List, types.AdminContentItem{
			ID: r.ID, AuthorID: r.UserID, AuthorName: r.Nickname,
			Title: r.Title, Content: truncateRunes(r.Content, 120), Status: r.Status,
			CircleID: r.CircleID, BizType: r.BizType, BizID: r.BizID,
			IsTop: r.IsTop, IsEssence: r.IsEssence,
			LikeCount: r.LikeCount, ViewCount: r.ViewCount, CreatedAt: r.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// TakedownContent 内容一键下架/恢复:帖(发布↔下架)、评(正常↔屏蔽),计数同步回补,通知作者,留痕。
func (l *Logic) TakedownContent(ctx context.Context, adminID int64, req *types.AdminTakedownReq, ip string) error {
	down := req.Action == 1
	if down && strings.TrimSpace(req.Reason) == "" {
		return xerr.Param("下架必须填写原因")
	}
	var (
		authorID int64
		hit      bool
		err      error
		noun     = "帖子"
	)
	switch {
	case req.Type == 1 && down:
		authorID, hit, err = l.svcCtx.AdminModel.TakedownPostByAdmin(ctx, req.ID)
	case req.Type == 1 && !down:
		authorID, hit, err = l.svcCtx.AdminModel.RestorePostByAdmin(ctx, req.ID)
	case down:
		noun = "评论"
		authorID, hit, err = l.svcCtx.AdminModel.TakedownCommentByAdmin(ctx, req.ID)
	default:
		noun = "评论"
		authorID, hit, err = l.svcCtx.AdminModel.RestoreCommentByAdmin(ctx, req.ID)
	}
	if err != nil {
		return fmt.Errorf("takedown content: %w", err)
	}
	if !hit {
		return xerr.New(xerr.CodeNotFound, "内容不存在或当前状态不可操作")
	}
	text := "你的" + noun + "已恢复展示"
	if down {
		text = "你的" + noun + "因违规被下架: " + req.Reason
	}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: authorID, Type: model.NotifyTypeSystem, TargetID: req.ID, Content: text,
	}); err != nil {
		logx.WithContext(ctx).Errorf("takedown notification: %v", err)
	}
	action := fmt.Sprintf("content.%s.%d", map[bool]string{true: "takedown", false: "restore"}[down], req.Type)
	l.opLog(ctx, adminID, action, fmt.Sprintf("type:%d id:%d", req.Type, req.ID), req.Reason, ip)
	return nil
}

// Reports 举报列表:按类型批量补目标摘要,供工作台判断与快捷处置。
func (l *Logic) Reports(ctx context.Context, req *types.AdminReportListReq) (*types.AdminReportListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.AdminModel.ListReports(ctx, req.Status, req.TargetType, offset, limit)
	if err != nil {
		return nil, err
	}

	// 目标摘要:同类型聚合一次批量查
	idsByType := map[int64][]int64{}
	for _, r := range rows {
		idsByType[r.TargetType] = append(idsByType[r.TargetType], r.TargetID)
	}
	briefs := map[int64]map[int64]*model.TargetBrief{}
	for tt, ids := range idsByType {
		b, err := l.svcCtx.AdminModel.TargetBriefs(ctx, tt, ids)
		if err != nil {
			return nil, err
		}
		briefs[tt] = b
	}

	out := &types.AdminReportListResp{Total: total, List: make([]types.AdminReportItem, 0, len(rows))}
	for _, r := range rows {
		item := types.AdminReportItem{
			ID: r.ID, ReporterID: r.UserID, ReporterName: r.Nickname,
			TargetType: r.TargetType, TargetID: r.TargetID,
			Category: r.Category, Reason: r.Reason, Status: r.Status,
			HandledBy: r.HandledBy, CreatedAt: r.CreatedAt.UnixMilli(),
			Images: []string{},
		}
		if r.Images.Valid && r.Images.String != "" {
			if err := json.Unmarshal([]byte(r.Images.String), &item.Images); err != nil {
				logx.WithContext(ctx).Errorf("report %d images parse: %v", r.ID, err)
			}
		}
		if r.HandledAt.Valid {
			item.HandledAt = r.HandledAt.Time.UnixMilli()
		}
		if b := briefs[r.TargetType][r.TargetID]; b != nil {
			item.TargetBrief = truncateRunes(b.Text, 60)
			item.TargetStatus = b.Status
		} else {
			item.TargetBrief = "(目标已不存在)"
			item.TargetStatus = -1
		}
		out.List = append(out.List, item)
	}
	return out, nil
}

// HandleReport 举报结单:1违规成立 2不成立(驳回),通知举报人,留痕。
// 目标本身的处置(下架/封禁)由管理员经内容管理/用户管理接口完成,此处只流转举报单。
func (l *Logic) HandleReport(ctx context.Context, adminID int64, req *types.AdminReportHandleReq, ip string) error {
	reporterID, hit, err := l.svcCtx.AdminModel.HandleReport(ctx, req.ReportID, adminID, req.Action)
	if err != nil {
		return fmt.Errorf("handle report: %w", err)
	}
	if reporterID == 0 {
		return xerr.New(xerr.CodeNotFound, "举报单不存在")
	}
	if !hit {
		return xerr.New(xerr.CodeTooFrequent, "该举报已被处理")
	}
	text := "你的举报已核实处理,感谢守护社区环境"
	if req.Action == 2 {
		text = "你的举报经核实暂不成立,感谢反馈"
	}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: reporterID, Type: model.NotifyTypeSystem, TargetID: req.ReportID, Content: text,
	}); err != nil {
		logx.WithContext(ctx).Errorf("report notification: %v", err)
	}
	l.opLog(ctx, adminID, decisionAction("report", req.Action == 1),
		fmt.Sprintf("report:%d", req.ReportID), "", ip)
	return nil
}

// truncateRunes 按字符截断摘要,避免撕裂多字节字符。
func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "..."
}

// BanUser 用户处置:恢复(0)/禁言(2)/封禁(3)。落库 + Redis 标记即时生效 + 通知 + 留痕。
func (l *Logic) BanUser(ctx context.Context, adminID int64, req *types.UserBanReq, ip string) error {
	if req.Days < 0 || req.Days > 3650 {
		return xerr.Param("处置时长需为 0-3650 天")
	}
	status := int64(model.UserStatusNormal)
	switch req.Action {
	case 2:
		status = model.UserStatusMuted
	case 3:
		status = model.UserStatusBanned
	}
	ok, err := l.svcCtx.AdminModel.SetUserStatus(ctx, req.UserID, status)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "用户不存在或已注销")
	}
	// Redis 标记即时生效(存量 token 同步受控);days=0 永久,恢复时清除
	bannedKey := userlogic.BannedKey(req.UserID)
	mutedKey := userlogic.MutedKey(req.UserID)
	ttl := req.Days * 86400
	switch req.Action {
	case 0:
		_, _ = l.svcCtx.Redis.DelCtx(ctx, bannedKey, mutedKey)
	case 2:
		_, _ = l.svcCtx.Redis.DelCtx(ctx, bannedKey)
		if err := setFlag(ctx, l.svcCtx, mutedKey, ttl); err != nil {
			return err
		}
	case 3:
		if err := setFlag(ctx, l.svcCtx, bannedKey, ttl); err != nil {
			return err
		}
	}
	texts := map[int64]string{0: "你的账号已恢复正常", 2: "你的账号因违规被禁言,期间无法发布内容", 3: "你的账号因严重违规被封禁"}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: req.UserID, Type: model.NotifyTypeSystem, Content: texts[req.Action],
	}); err != nil {
		logx.WithContext(ctx).Errorf("ban notification: %v", err)
	}
	l.opLog(ctx, adminID, fmt.Sprintf("user.ban.%d", req.Action),
		fmt.Sprintf("user:%d days:%d", req.UserID, req.Days), "", ip)
	return nil
}

func setFlag(ctx context.Context, svcCtx *svc.ServiceContext, key string, ttlSec int) error {
	if ttlSec > 0 {
		return svcCtx.Redis.SetexCtx(ctx, key, "1", ttlSec)
	}
	return svcCtx.Redis.SetCtx(ctx, key, "1")
}

// Banners 后台 Banner 列表(含下线与定时的)。
func (l *Logic) Banners(ctx context.Context) ([]types.AdminBannerItem, error) {
	rows, err := l.svcCtx.AdminModel.ListBanners(ctx)
	if err != nil {
		return nil, fmt.Errorf("list banners: %w", err)
	}
	out := make([]types.AdminBannerItem, 0, len(rows))
	for _, b := range rows {
		item := types.AdminBannerItem{
			ID: b.ID, Title: b.Title, Image: b.Image,
			LinkType: b.LinkType, LinkValue: b.LinkValue, Sort: b.Sort, Status: b.Status,
		}
		if b.StartAt.Valid {
			item.StartAt = b.StartAt.Time.UnixMilli()
		}
		if b.EndAt.Valid {
			item.EndAt = b.EndAt.Time.UnixMilli()
		}
		out = append(out, item)
	}
	return out, nil
}

// SaveBanner 新建/更新 Banner。
func (l *Logic) SaveBanner(ctx context.Context, adminID int64, req *types.AdminBannerReq, ip string) (int64, error) {
	if strings.TrimSpace(req.Title) == "" {
		return 0, xerr.Param("标题必填")
	}
	if !uploadlogic.AllowedImageURL(l.svcCtx.Config, req.Image) {
		return 0, xerr.Param("Banner 图链接不合法,请通过上传获取")
	}
	b := &model.BannerFull{
		ID: req.ID, Title: req.Title, Image: req.Image,
		LinkType: req.LinkType, LinkValue: req.LinkValue, Sort: req.Sort, Status: req.Status,
	}
	if req.StartAt > 0 {
		b.StartAt = sql.NullTime{Time: time.UnixMilli(req.StartAt), Valid: true}
	}
	if req.EndAt > 0 {
		b.EndAt = sql.NullTime{Time: time.UnixMilli(req.EndAt), Valid: true}
	}
	id, err := l.svcCtx.AdminModel.SaveBanner(ctx, b)
	if err != nil {
		return 0, err
	}
	l.opLog(ctx, adminID, "ops.banner.save", fmt.Sprintf("banner:%d", id), "", ip)
	return id, nil
}

// DeleteBanner 删除 Banner。
func (l *Logic) DeleteBanner(ctx context.Context, adminID, id int64, ip string) error {
	if err := l.svcCtx.AdminModel.DeleteBanner(ctx, id); err != nil {
		return err
	}
	l.opLog(ctx, adminID, "ops.banner.delete", fmt.Sprintf("banner:%d", id), "", ip)
	return nil
}

// Dashboard 数据看板。
func (l *Logic) Dashboard(ctx context.Context) (*types.DashboardResp, error) {
	s, err := l.svcCtx.AdminModel.Dashboard(ctx)
	if err != nil {
		return nil, fmt.Errorf("dashboard: %w", err)
	}
	return &types.DashboardResp{
		Users: s.Users, TodayUsers: s.TodayUsers, TodayActive: s.TodayActive,
		Posts: s.Posts, TodayPosts: s.TodayPosts, Software: s.Software,
		PendingAudits: s.PendingAudits, YouzhuIssued: s.YouzhuIssued, YouzhuBurned: s.YouzhuBurned,
	}, nil
}

// ---- 敏感词库管理(改动即调 Filter.Invalidate 热更新,发布链路下一次机审立即用新词库) ----

// Words 词库列表。
func (l *Logic) Words(ctx context.Context, req *types.AdminWordListReq) (*types.AdminWordListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.SensitiveModel.ListWords(ctx,
		strings.TrimSpace(req.Keyword), req.Category, req.Level, req.Status, offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminWordListResp{Total: total, List: make([]types.AdminWordItem, 0, len(rows))}
	for _, w := range rows {
		out.List = append(out.List, types.AdminWordItem{
			ID: w.ID, Word: w.Word, Category: w.Category, Level: w.Level,
			Status: w.Status, CreatedAt: w.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// SaveWord 新建/更新敏感词并热更新过滤器。
func (l *Logic) SaveWord(ctx context.Context, adminID int64, req *types.AdminWordSaveReq, ip string) (int64, error) {
	id := req.ID
	if id > 0 {
		ok, err := l.svcCtx.SensitiveModel.UpdateWord(ctx, id, req.Category, req.Level, req.Status)
		if err != nil {
			return 0, err
		}
		if !ok {
			return 0, xerr.New(xerr.CodeNotFound, "词条不存在")
		}
	} else {
		word := strings.TrimSpace(req.Word)
		if word == "" || len([]rune(word)) > 64 {
			return 0, xerr.Param("敏感词长度需为 1-64 字符")
		}
		var err error
		if id, err = l.svcCtx.SensitiveModel.CreateWord(ctx, word, req.Category, req.Level); err != nil {
			if errors.Is(err, model.ErrWordExists) {
				return 0, xerr.New(xerr.CodeTooFrequent, "该敏感词已存在")
			}
			return 0, err
		}
	}
	l.svcCtx.Filter.Invalidate()
	l.opLog(ctx, adminID, "ops.word.save", fmt.Sprintf("word:%d level:%d status:%d", id, req.Level, req.Status), "", ip)
	return id, nil
}

// DeleteWord 删除敏感词并热更新过滤器。
func (l *Logic) DeleteWord(ctx context.Context, adminID, id int64, ip string) error {
	if err := l.svcCtx.SensitiveModel.DeleteWord(ctx, id); err != nil {
		return err
	}
	l.svcCtx.Filter.Invalidate()
	l.opLog(ctx, adminID, "ops.word.delete", fmt.Sprintf("word:%d", id), "", ip)
	return nil
}

// ---- AI 管家 FAQ 词条管理(botReply 每次实时查库,改动即时生效) ----

// Faqs 词条列表。
func (l *Logic) Faqs(ctx context.Context, req *types.PageReq) (*types.AdminFaqListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.FaqModel.ListAll(ctx, offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminFaqListResp{Total: total, List: make([]types.AdminFaqItem, 0, len(rows))}
	for _, r := range rows {
		out.List = append(out.List, types.AdminFaqItem{
			ID: r.ID, Keywords: r.Keywords, Reply: r.Reply, Priority: r.Priority,
			Status: r.Status, CreatedAt: r.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// SaveFaq 新建/更新 FAQ 词条。
func (l *Logic) SaveFaq(ctx context.Context, adminID int64, req *types.AdminFaqSaveReq, ip string) (int64, error) {
	keywords := strings.Trim(strings.TrimSpace(req.Keywords), "|")
	reply := strings.TrimSpace(req.Reply)
	if keywords == "" || reply == "" {
		return 0, xerr.Param("关键词与回复内容不能为空")
	}
	id := req.ID
	if id > 0 {
		ok, err := l.svcCtx.FaqModel.Update(ctx, id, keywords, reply, req.Priority, req.Status)
		if err != nil {
			return 0, err
		}
		if !ok {
			return 0, xerr.New(xerr.CodeNotFound, "词条不存在")
		}
	} else {
		var err error
		if id, err = l.svcCtx.FaqModel.Create(ctx, keywords, reply, req.Priority); err != nil {
			return 0, err
		}
	}
	l.opLog(ctx, adminID, "ops.faq.save", fmt.Sprintf("faq:%d", id), "", ip)
	return id, nil
}

// DeleteFaq 删除 FAQ 词条。
func (l *Logic) DeleteFaq(ctx context.Context, adminID, id int64, ip string) error {
	if err := l.svcCtx.FaqModel.Delete(ctx, id); err != nil {
		return err
	}
	l.opLog(ctx, adminID, "ops.faq.delete", fmt.Sprintf("faq:%d", id), "", ip)
	return nil
}

// ---- 商城/任务运营配置(读取侧每次查库,保存即生效) ----

// Decorations 后台装扮列表(含下架)。
func (l *Logic) Decorations(ctx context.Context) ([]types.AdminDecoItem, error) {
	rows, err := l.svcCtx.MallModel.ListDecorationsAdmin(ctx)
	if err != nil {
		return nil, fmt.Errorf("list decorations admin: %w", err)
	}
	out := make([]types.AdminDecoItem, 0, len(rows))
	for _, d := range rows {
		out = append(out, types.AdminDecoItem{
			ID: d.ID, Kind: d.Kind, Name: d.Name, Preview: d.Preview,
			Price: d.Price, DurationDays: d.DurationDays, Sort: d.Sort, Status: d.Status,
		})
	}
	return out, nil
}

// SaveDecoration 新建/更新装扮商品。
func (l *Logic) SaveDecoration(ctx context.Context, adminID int64, req *types.AdminDecoSaveReq, ip string) (int64, error) {
	if strings.TrimSpace(req.Name) == "" {
		return 0, xerr.Param("名称必填")
	}
	if !uploadlogic.AllowedImageURL(l.svcCtx.Config, req.Preview) {
		return 0, xerr.Param("预览图链接不合法,请通过上传获取")
	}
	if req.Price < 0 || req.DurationDays < 0 {
		return 0, xerr.Param("价格与有效天数不能为负")
	}
	id, ok, err := l.svcCtx.MallModel.SaveDecoration(ctx, &model.Decoration{
		ID: req.ID, Kind: req.Kind, Name: strings.TrimSpace(req.Name), Preview: req.Preview,
		Price: req.Price, DurationDays: req.DurationDays, Sort: req.Sort, Status: req.Status,
	})
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, xerr.New(xerr.CodeNotFound, "装扮不存在")
	}
	l.opLog(ctx, adminID, "ops.mall.deco", fmt.Sprintf("deco:%d status:%d", id, req.Status), "", ip)
	return id, nil
}

// Prizes 后台奖池列表(含停用/售罄)。
func (l *Logic) Prizes(ctx context.Context) ([]types.AdminPrizeItem, error) {
	rows, err := l.svcCtx.MallModel.ListPrizesAdmin(ctx)
	if err != nil {
		return nil, fmt.Errorf("list prizes admin: %w", err)
	}
	out := make([]types.AdminPrizeItem, 0, len(rows))
	for _, p := range rows {
		out = append(out, types.AdminPrizeItem{
			ID: p.ID, Name: p.Name, Kind: p.Kind, RefID: p.RefID,
			Amount: p.Amount, Weight: p.Weight, Stock: p.Stock, Status: p.Status,
		})
	}
	return out, nil
}

// SavePrize 新建/更新奖池奖品。装扮类奖品校验装扮存在,防抽中发放失败。
func (l *Logic) SavePrize(ctx context.Context, adminID int64, req *types.AdminPrizeSaveReq, ip string) (int64, error) {
	if strings.TrimSpace(req.Name) == "" {
		return 0, xerr.Param("奖品名必填")
	}
	if req.Weight <= 0 || req.Stock < -1 {
		return 0, xerr.Param("权重需大于 0,库存需 >= -1(-1 为不限量)")
	}
	switch req.Kind {
	case 1:
		if req.Amount <= 0 {
			return 0, xerr.Param("忧珠奖品数量需大于 0")
		}
	case 2:
		if _, err := l.svcCtx.MallModel.FindDecoration(ctx, req.RefID); err != nil {
			if model.IsNotFound(err) {
				return 0, xerr.Param("奖品引用的装扮不存在")
			}
			return 0, fmt.Errorf("check prize deco: %w", err)
		}
	}
	full := &model.LotteryPrizeFull{Status: req.Status}
	full.ID, full.Name, full.Kind, full.RefID = req.ID, strings.TrimSpace(req.Name), req.Kind, req.RefID
	full.Amount, full.Weight, full.Stock = req.Amount, req.Weight, req.Stock
	id, ok, err := l.svcCtx.MallModel.SavePrize(ctx, full)
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, xerr.New(xerr.CodeNotFound, "奖品不存在")
	}
	l.opLog(ctx, adminID, "ops.mall.prize", fmt.Sprintf("prize:%d weight:%d stock:%d status:%d", id, req.Weight, req.Stock, req.Status), "", ip)
	return id, nil
}

// GrantYouzhu 忧珠运营发放/回收:复用幂等账本(YouzhuBizOps),通知用户,留痕。
func (l *Logic) GrantYouzhu(ctx context.Context, adminID int64, req *types.AdminYouzhuGrantReq, ip string) error {
	if req.Amount == 0 || req.Amount < -100000 || req.Amount > 100000 {
		return xerr.Param("发放/回收数量需在 ±100000 以内且不为 0")
	}
	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		return xerr.Param("必须填写发放/回收原因")
	}
	u, err := l.svcCtx.UserModel.FindByID(ctx, req.UserID)
	if err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "用户不存在")
		}
		return fmt.Errorf("find user: %w", err)
	}
	if u.Status == 4 {
		return xerr.New(xerr.CodeNotFound, "用户已注销")
	}
	bizKey := fmt.Sprintf("ops:grant:%d:%d", adminID, time.Now().UnixNano())
	if _, err := l.svcCtx.YouzhuModel.Change(ctx, req.UserID, model.YouzhuBizOps, bizKey, req.Amount, "运营: "+reason); err != nil {
		if errors.Is(err, model.ErrInsufficientBalance) {
			return xerr.Param("回收失败:用户忧珠余额不足")
		}
		return fmt.Errorf("ops grant: %w", err)
	}
	text := fmt.Sprintf("运营发放 %d 忧珠: %s", req.Amount, reason)
	if req.Amount < 0 {
		text = fmt.Sprintf("运营回收 %d 忧珠: %s", -req.Amount, reason)
	}
	if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
		UserID: req.UserID, Type: model.NotifyTypeSystem, Content: text,
	}); err != nil {
		logx.WithContext(ctx).Errorf("grant notification: %v", err)
	}
	l.opLog(ctx, adminID, "ops.youzhu.grant",
		fmt.Sprintf("user:%d amount:%d", req.UserID, req.Amount), reason, ip)
	return nil
}

// YouzhuLogs 后台忧珠流水查询。
func (l *Logic) YouzhuLogs(ctx context.Context, req *types.AdminYouzhuLogListReq) (*types.AdminYouzhuLogListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.AdminModel.ListYouzhuLogsAdmin(ctx, req.UserID, req.BizType, offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminYouzhuLogListResp{Total: total, List: make([]types.AdminYouzhuLogItem, 0, len(rows))}
	for _, r := range rows {
		out.List = append(out.List, types.AdminYouzhuLogItem{
			ID: r.ID, UserID: r.UserID, Nickname: r.Nickname, BizType: r.BizType, BizKey: r.BizKey,
			Amount: r.Amount, BalanceAfter: r.BalanceAfter, Remark: r.Remark, CreatedAt: r.CreatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// PrettyNos 后台靓号库列表。
func (l *Logic) PrettyNos(ctx context.Context, req *types.AdminPrettyNoListReq) (*types.AdminPrettyNoListResp, error) {
	offset, limit := req.Offset()
	total, rows, err := l.svcCtx.AdminModel.ListPrettyNosAdmin(ctx, strings.TrimSpace(req.Keyword), req.Status, offset, limit)
	if err != nil {
		return nil, err
	}
	out := &types.AdminPrettyNoListResp{Total: total, List: make([]types.AdminPrettyNoItem, 0, len(rows))}
	for _, p := range rows {
		item := types.AdminPrettyNoItem{
			ID: p.ID, No: p.No, Rarity: p.Rarity, Price: p.Price, Status: p.Status, SoldTo: p.SoldTo,
		}
		if p.SoldAt.Valid {
			item.SoldAt = p.SoldAt.Time.UnixMilli()
		}
		out.List = append(out.List, item)
	}
	return out, nil
}

// SavePrettyNo 新增/修改靓号 SKU(号码 N+数字,已售不可改)。
func (l *Logic) SavePrettyNo(ctx context.Context, adminID int64, req *types.AdminPrettyNoSaveReq, ip string) (int64, error) {
	no := strings.ToUpper(strings.TrimSpace(req.No))
	if len(no) < 2 || len(no) > 20 || no[0] != 'N' {
		return 0, xerr.Param("号码格式应为 N 开头,如 N88888")
	}
	for _, c := range no[1:] {
		if c < '0' || c > '9' {
			return 0, xerr.Param("号码 N 之后只能是数字")
		}
	}
	if req.Price <= 0 {
		return 0, xerr.Param("价格需大于 0")
	}
	id, ok, err := l.svcCtx.AdminModel.SavePrettyNoAdmin(ctx, &model.AdminPrettyNoRow{
		ID: req.ID, No: no, Rarity: req.Rarity, Price: req.Price, Status: req.Status,
	})
	if err != nil {
		switch {
		case errors.Is(err, model.ErrPrettyNoExists):
			return 0, xerr.New(xerr.CodeTooFrequent, "该号码已存在")
		case errors.Is(err, model.ErrPrettyNoSold):
			return 0, xerr.New(xerr.CodeForbidden, "已售出的靓号不可修改")
		}
		return 0, err
	}
	if !ok {
		return 0, xerr.New(xerr.CodeNotFound, "靓号不存在")
	}
	l.opLog(ctx, adminID, "ops.mall.prettyno", fmt.Sprintf("sku:%d no:%s price:%d status:%d", id, no, req.Price, req.Status), "", ip)
	return id, nil
}

// DeletePrettyNo 删除未售靓号 SKU。
func (l *Logic) DeletePrettyNo(ctx context.Context, adminID, id int64, ip string) error {
	ok, err := l.svcCtx.AdminModel.DeletePrettyNoAdmin(ctx, id)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeForbidden, "靓号不存在或已售出(已售不可删除)")
	}
	l.opLog(ctx, adminID, "ops.mall.prettyno.delete", fmt.Sprintf("sku:%d", id), "", ip)
	return nil
}

// TaskCfgs 后台任务列表(含停用)。
func (l *Logic) TaskCfgs(ctx context.Context) ([]types.AdminTaskCfgItem, error) {
	rows, err := l.svcCtx.TaskModel.ListTasksAdmin(ctx)
	if err != nil {
		return nil, fmt.Errorf("list tasks admin: %w", err)
	}
	out := make([]types.AdminTaskCfgItem, 0, len(rows))
	for _, t := range rows {
		out = append(out, types.AdminTaskCfgItem{
			ID: t.ID, Name: t.Name, Type: t.Type, Action: t.Action, TargetCount: t.TargetCount,
			RewardYouzhu: t.RewardYouzhu, RewardExp: t.RewardExp, Sort: t.Sort, Status: t.Status,
		})
	}
	return out, nil
}

// SaveTaskCfg 新建/更新任务配置。
func (l *Logic) SaveTaskCfg(ctx context.Context, adminID int64, req *types.AdminTaskSaveReq, ip string) (int64, error) {
	if strings.TrimSpace(req.Name) == "" {
		return 0, xerr.Param("任务名必填")
	}
	if req.TargetCount <= 0 {
		return 0, xerr.Param("完成次数需大于 0")
	}
	if req.RewardYouzhu < 0 || req.RewardExp < 0 {
		return 0, xerr.Param("奖励不能为负")
	}
	if req.RewardYouzhu == 0 && req.RewardExp == 0 {
		return 0, xerr.Param("忧珠与经验奖励至少配置一项")
	}
	full := &model.TaskFull{Status: req.Status}
	full.ID, full.Name, full.Type, full.Action = req.ID, strings.TrimSpace(req.Name), req.Type, req.Action
	full.TargetCount, full.RewardYouzhu, full.RewardExp, full.Sort = req.TargetCount, req.RewardYouzhu, req.RewardExp, req.Sort
	id, ok, err := l.svcCtx.TaskModel.SaveTask(ctx, full)
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, xerr.New(xerr.CodeNotFound, "任务不存在")
	}
	l.opLog(ctx, adminID, "ops.mall.task", fmt.Sprintf("task:%d status:%d", id, req.Status), "", ip)
	return id, nil
}

// Trend 看板近 N 日趋势(7-90 天钳制)。
func (l *Logic) Trend(ctx context.Context, req *types.TrendReq) (*types.TrendResp, error) {
	days := req.Days
	if days < 7 {
		days = 7
	}
	if days > 90 {
		days = 90
	}
	dates, users, posts, issued, burned, err := l.svcCtx.AdminModel.DashboardTrend(ctx, days)
	if err != nil {
		return nil, err
	}
	return &types.TrendResp{
		Dates: dates, Users: users, Posts: posts,
		YouzhuIssued: issued, YouzhuBurned: burned,
	}, nil
}

// Categories 后台软件分类列表(含停用)。
func (l *Logic) Categories(ctx context.Context) ([]types.AdminCategoryItem, error) {
	rows, err := l.svcCtx.AdminModel.ListCategoriesAdmin(ctx)
	if err != nil {
		return nil, fmt.Errorf("list categories admin: %w", err)
	}
	out := make([]types.AdminCategoryItem, 0, len(rows))
	for _, c := range rows {
		out = append(out, types.AdminCategoryItem{ID: c.ID, Type: c.Type, Name: c.Name, Sort: c.Sort, Status: c.Status})
	}
	return out, nil
}

// SaveCategory 新建/更新软件分类。停用后发布表单即不再出现,已发布软件不受影响。
func (l *Logic) SaveCategory(ctx context.Context, adminID int64, req *types.AdminCategorySaveReq, ip string) (int64, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" || len([]rune(name)) > 20 {
		return 0, xerr.Param("分类名长度需为 1-20 字符")
	}
	id, ok, err := l.svcCtx.AdminModel.SaveCategory(ctx, &model.SoftwareCategoryFull{
		ID: req.ID, Type: req.Type, Name: name, Sort: req.Sort, Status: req.Status,
	})
	if err != nil {
		if errors.Is(err, model.ErrCategoryExists) {
			return 0, xerr.New(xerr.CodeTooFrequent, "同类型下已有同名分类")
		}
		return 0, err
	}
	if !ok {
		return 0, xerr.New(xerr.CodeNotFound, "分类不存在")
	}
	l.opLog(ctx, adminID, "ops.software.category", fmt.Sprintf("category:%d status:%d", id, req.Status), "", ip)
	return id, nil
}

func (l *Logic) opLog(ctx context.Context, adminID int64, action, target, detail, ip string) {
	var detailJSON string
	if detail != "" {
		b, _ := json.Marshal(map[string]string{"reason": detail})
		detailJSON = string(b)
	}
	if err := l.svcCtx.AdminModel.AddOpLog(ctx, adminID, action, target, detailJSON, ip); err != nil {
		logx.WithContext(ctx).Errorf("op log: %v", err)
	}
}

func decisionAction(prefix string, approve bool) string {
	if approve {
		return prefix + ".pass"
	}
	return prefix + ".reject"
}
