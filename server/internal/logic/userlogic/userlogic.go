// Package userlogic 个人中心:我的资料/他人主页(数据栏)/关注关系/拉黑。
package userlogic

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/logic/uploadlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/imgscan"
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

func (l *Logic) Me(ctx context.Context, uid int64) (*types.UserInfoResp, error) {
	u, err := l.findVisible(ctx, uid)
	if err != nil {
		return nil, err
	}
	return &types.UserInfoResp{
		UserID:    u.ID,
		DisplayNo: u.DisplayNo.String,
		Nickname:  u.Nickname,
		Avatar:    u.Avatar,
		Cover:     u.Cover,
		Signature: u.Signature,
		Level:     u.Level,
	}, nil
}

// UpdateMe 编辑资料。PATCH 三态:nil 不更新;昵称/签名过敏感词(拦截与人审级直接拒绝,打码级替换)。
func (l *Logic) UpdateMe(ctx context.Context, uid int64, req *types.UpdateProfileReq) error {
	fields := make(map[string]any, 6)
	if req.Nickname != nil {
		nickname := strings.TrimSpace(*req.Nickname)
		n := utf8.RuneCountInString(nickname)
		if n < 2 || n > 30 {
			return xerr.Param("昵称长度需为 2-30 字")
		}
		res, err := l.svcCtx.Filter.Check(ctx, nickname)
		if err != nil {
			return fmt.Errorf("nickname check: %w", err)
		}
		// 昵称全站高频展示,疑似词不进人审队列,直接要求改名
		if res.Level == model.WordLevelBlock || res.Level == model.WordLevelReview {
			return xerr.New(xerr.CodeContentBlocked, "昵称包含违禁词,请更换")
		}
		fields["nickname"] = res.Text
	}
	if req.Signature != nil {
		sig := strings.TrimSpace(*req.Signature)
		if utf8.RuneCountInString(sig) > 100 {
			return xerr.Param("签名最多 100 字")
		}
		res, err := l.svcCtx.Filter.Check(ctx, sig)
		if err != nil {
			return fmt.Errorf("signature check: %w", err)
		}
		if res.Level == model.WordLevelBlock || res.Level == model.WordLevelReview {
			return xerr.New(xerr.CodeContentBlocked, "签名包含违禁词,请修改")
		}
		fields["signature"] = res.Text
	}
	if req.Avatar != nil {
		if !uploadlogic.AllowedImageURL(l.svcCtx.Config, *req.Avatar) {
			return xerr.Param("头像链接不合法,请通过上传接口获取")
		}
		if err := l.scanProfileImage(ctx, *req.Avatar, "头像"); err != nil {
			return err
		}
		fields["avatar"] = *req.Avatar
	}
	if req.Cover != nil {
		if !uploadlogic.AllowedImageURL(l.svcCtx.Config, *req.Cover) {
			return xerr.Param("封面链接不合法,请通过上传接口获取")
		}
		if err := l.scanProfileImage(ctx, *req.Cover, "封面"); err != nil {
			return err
		}
		fields["cover"] = *req.Cover
	}
	if req.Gender != nil {
		if *req.Gender < 0 || *req.Gender > 2 {
			return xerr.Param("性别取值不正确")
		}
		fields["gender"] = *req.Gender
	}
	if req.Birthday != nil {
		day, err := time.Parse("2006-01-02", *req.Birthday)
		if err != nil || day.After(time.Now()) {
			return xerr.Param("生日格式不正确")
		}
		fields["birthday"] = day
	}
	if len(fields) == 0 {
		return xerr.Param("没有需要更新的字段")
	}
	if err := l.svcCtx.UserModel.UpdateProfile(ctx, uid, fields); err != nil {
		return fmt.Errorf("update profile: %w", err)
	}
	return nil
}

// scanProfileImage 头像/封面属高曝光位,保存前同步机审:高置信违规直接拒绝。
// 疑似(review)放行不入队(audit_queue 无用户资料类目,低置信不阻塞体验);
// 机审关闭或云端异常按放行降级,不阻断资料编辑。
func (l *Logic) scanProfileImage(ctx context.Context, imageURL, what string) error {
	if l.svcCtx.ImgScanner == nil {
		return nil
	}
	r, err := l.svcCtx.ImgScanner.Scan(ctx, imageURL)
	if err != nil {
		logx.WithContext(ctx).Errorf("imgscan %s %s: %v", what, imageURL, err)
		return nil
	}
	if r.Verdict == imgscan.VerdictBlock {
		return xerr.New(xerr.CodeContentBlocked, what+"图片涉嫌违规,请更换后重试")
	}
	return nil
}

// ReportPushToken 设备推送令牌上报(离线推送;客户端启动/令牌轮换时调用)。
func (l *Logic) ReportPushToken(ctx context.Context, uid int64, req *types.PushTokenReq) error {
	if strings.TrimSpace(req.DeviceID) == "" || strings.TrimSpace(req.Token) == "" {
		return xerr.Param("deviceId 与 token 不能为空")
	}
	if len(req.Token) > 255 || len(req.DeviceID) > 32 {
		return xerr.Param("参数长度非法")
	}
	return l.svcCtx.PushModel.UpsertToken(ctx, &model.PushToken{
		UserID: uid, DeviceID: req.DeviceID,
		Platform: req.Platform, Channel: req.Channel, Token: req.Token,
	})
}

// Settings 用户设置(青少年模式等)。
func (l *Logic) Settings(ctx context.Context, uid int64) (*types.UserSettingsResp, error) {
	u, err := l.svcCtx.UserModel.FindByID(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("find user: %w", err)
	}
	return &types.UserSettingsResp{TeenMode: u.TeenMode == 1}, nil
}

// UpdateSettings 更新设置。
func (l *Logic) UpdateSettings(ctx context.Context, uid int64, req *types.UpdateSettingsReq) error {
	if req.TeenMode == nil {
		return xerr.Param("没有需要更新的设置")
	}
	if err := l.svcCtx.UserModel.SetTeenMode(ctx, uid, *req.TeenMode); err != nil {
		return err
	}
	return nil
}

// EnsureNotTeen 青少年模式下禁用消费类功能(付费解锁/抽奖/兑换),合规基线。
func EnsureNotTeen(ctx context.Context, svcCtx *svc.ServiceContext, uid int64) error {
	u, err := svcCtx.UserModel.FindByID(ctx, uid)
	if err != nil {
		return fmt.Errorf("find user: %w", err)
	}
	if u.TeenMode == 1 {
		return xerr.New(xerr.CodeForbidden, "青少年模式下无法使用该功能")
	}
	return nil
}

// DeactivateKey 注销吊销标记(JWT 无状态,注销后按 uid 拉黑到令牌自然过期)。
func DeactivateKey(uid int64) string { return fmt.Sprintf("user:deactivated:%d", uid) }

// BannedKey 封禁标记:命中后所有登录态请求 401(后台封禁动作写入/恢复删除)。
func BannedKey(uid int64) string { return fmt.Sprintf("user:banned:%d", uid) }

// MutedKey 全站禁言标记:命中后发帖/评论/私信被拦(浏览不受限)。
func MutedKey(uid int64) string { return fmt.Sprintf("user:muted:%d", uid) }

// Deactivate 注销账号(应用商店合规必备):密码确认 → status=4 → Redis 吊销标记覆盖存量 token。
// 邮箱保留不释放;内容按"已注销用户"展示。
func (l *Logic) Deactivate(ctx context.Context, uid int64, password string) error {
	auth, err := l.svcCtx.UserModel.FindAuthByUID(ctx, uid)
	if err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "用户不存在")
		}
		return fmt.Errorf("find auth: %w", err)
	}
	if bcrypt.CompareHashAndPassword([]byte(auth.PasswordHash), []byte(password)) != nil {
		return xerr.New(xerr.CodeBadCredential, "密码错误")
	}
	ok, err := l.svcCtx.UserModel.Deactivate(ctx, uid)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeTooFrequent, "账号已注销")
	}
	// 吊销窗口 = 令牌最长寿命,存量 JWT 全部失效
	if err := l.svcCtx.Redis.SetexCtx(ctx, DeactivateKey(uid), "1", int(l.svcCtx.Config.Auth.AccessExpire)); err != nil {
		return fmt.Errorf("revoke mark: %w", err)
	}
	return nil
}

// Profile 个人主页(自己/他人通用):资料 + 数据栏 5 项中的 4 项(忧珠属 M3)+ 关系状态。
func (l *Logic) Profile(ctx context.Context, viewer, targetID int64) (*types.UserProfileResp, error) {
	u, err := l.findVisible(ctx, targetID)
	if err != nil {
		return nil, err
	}
	following, err := l.svcCtx.RelationModel.CountFollowing(ctx, targetID)
	if err != nil {
		return nil, fmt.Errorf("count following: %w", err)
	}
	fans, err := l.svcCtx.RelationModel.CountFans(ctx, targetID)
	if err != nil {
		return nil, fmt.Errorf("count fans: %w", err)
	}
	posts, likes, err := l.svcCtx.PostModel.AuthorStats(ctx, targetID)
	if err != nil {
		return nil, fmt.Errorf("author stats: %w", err)
	}
	resp := &types.UserProfileResp{
		UserID:    u.ID,
		DisplayNo: u.DisplayNo.String,
		Nickname:  u.Nickname,
		Avatar:    u.Avatar,
		Cover:     u.Cover,
		Signature: u.Signature,
		Level:     u.Level,
		Following: following,
		Fans:      fans,
		Likes:     likes,
		Posts:     posts,
		IsSelf:    viewer == targetID,
	}
	if viewer > 0 && viewer != targetID {
		if resp.Followed, err = l.svcCtx.RelationModel.IsFollowing(ctx, viewer, targetID); err != nil {
			return nil, fmt.Errorf("is following: %w", err)
		}
		if resp.Blocked, err = l.svcCtx.IMModel.IsBlocked(ctx, viewer, targetID); err != nil {
			return nil, fmt.Errorf("is blocked: %w", err)
		}
	}
	if resp.Certs, err = l.svcCtx.CertModel.ApprovedKinds(ctx, targetID); err != nil {
		return nil, fmt.Errorf("approved certs: %w", err)
	}
	return resp, nil
}

// Certify 提交权益认证(达人/开发者,人工审核授头衔)。
func (l *Logic) Certify(ctx context.Context, uid int64, req *types.CertifyReq) error {
	material := strings.TrimSpace(req.Material)
	if material == "" {
		return xerr.Param("请填写佐证材料")
	}
	if utf8.RuneCountInString(material) > 1000 {
		return xerr.Param("佐证材料最多 1000 字")
	}
	if err := l.svcCtx.CertModel.Submit(ctx, uid, req.Kind, material); err != nil {
		if errors.Is(err, model.ErrCertDuplicated) {
			return xerr.New(xerr.CodeTooFrequent, "该类认证已在审核中或已通过")
		}
		return fmt.Errorf("submit cert: %w", err)
	}
	return nil
}

// MyCerts 我的认证记录。
func (l *Logic) MyCerts(ctx context.Context, uid int64) ([]types.CertItem, error) {
	rows, err := l.svcCtx.CertModel.Mine(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("my certs: %w", err)
	}
	out := make([]types.CertItem, 0, len(rows))
	for _, c := range rows {
		out = append(out, types.CertItem{
			Kind: c.Kind, Status: c.Status, Reason: c.Reason, UpdatedAt: c.UpdatedAt.UnixMilli(),
		})
	}
	return out, nil
}

// Follow 关注,幂等;拉黑状态下不可关注,首次关注给对方写通知。
func (l *Logic) Follow(ctx context.Context, uid, targetID int64) error {
	if uid == targetID {
		return xerr.Param("不能关注自己")
	}
	if _, err := l.findVisible(ctx, targetID); err != nil {
		return err
	}
	if blocked, err := l.svcCtx.IMModel.IsBlocked(ctx, uid, targetID); err != nil {
		return fmt.Errorf("check blocked: %w", err)
	} else if blocked {
		return xerr.New(xerr.CodeForbidden, "你已拉黑对方,请先解除")
	}
	added, err := l.svcCtx.RelationModel.Follow(ctx, uid, targetID)
	if err != nil {
		return err
	}
	if added {
		if err := l.svcCtx.NotifyModel.Add(ctx, &model.Notification{
			UserID: targetID, Type: model.NotifyTypeSystem, ActorID: uid, Content: "关注了你",
		}); err != nil {
			logx.WithContext(ctx).Errorf("follow notification: %v", err)
		}
	}
	return nil
}

func (l *Logic) Unfollow(ctx context.Context, uid, targetID int64) error {
	return l.svcCtx.RelationModel.Unfollow(ctx, uid, targetID)
}

// Block 拉黑:写黑名单并解除双向关注。
func (l *Logic) Block(ctx context.Context, uid, targetID int64) error {
	if uid == targetID {
		return xerr.Param("不能拉黑自己")
	}
	if _, err := l.findVisible(ctx, targetID); err != nil {
		return err
	}
	return l.svcCtx.RelationModel.Block(ctx, uid, targetID)
}

func (l *Logic) Unblock(ctx context.Context, uid, targetID int64) error {
	return l.svcCtx.RelationModel.Unblock(ctx, uid, targetID)
}

// Following 关注列表;Fans 粉丝列表。均补齐 viewer 视角的已关注状态。
func (l *Logic) Following(ctx context.Context, viewer, targetID int64, req *types.PageReq) ([]types.RelationUserItem, error) {
	offset, limit := req.Offset()
	ids, err := l.svcCtx.RelationModel.ListFollowing(ctx, targetID, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("list following: %w", err)
	}
	return l.decorate(ctx, viewer, ids)
}

func (l *Logic) Fans(ctx context.Context, viewer, targetID int64, req *types.PageReq) ([]types.RelationUserItem, error) {
	offset, limit := req.Offset()
	ids, err := l.svcCtx.RelationModel.ListFans(ctx, targetID, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("list fans: %w", err)
	}
	return l.decorate(ctx, viewer, ids)
}

func (l *Logic) decorate(ctx context.Context, viewer int64, ids []int64) ([]types.RelationUserItem, error) {
	out := make([]types.RelationUserItem, 0, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	briefs, err := l.svcCtx.UserModel.FindBriefs(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("relation briefs: %w", err)
	}
	followed, err := l.svcCtx.RelationModel.FollowedSet(ctx, viewer, ids)
	if err != nil {
		return nil, fmt.Errorf("followed set: %w", err)
	}
	for _, id := range ids {
		out = append(out, types.RelationUserItem{
			UserBrief: postlogic.ToUserBrief(id, briefs[id]),
			Followed:  followed[id],
		})
	}
	return out, nil
}

// findVisible 注销账号对外不可见。
func (l *Logic) findVisible(ctx context.Context, uid int64) (*model.User, error) {
	u, err := l.svcCtx.UserModel.FindByID(ctx, uid)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "用户不存在")
		}
		return nil, fmt.Errorf("find user %d: %w", uid, err)
	}
	if u.Status == 4 {
		return nil, xerr.New(xerr.CodeNotFound, "用户不存在")
	}
	return u, nil
}
