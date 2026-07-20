// Package postlogic 帖子:发布(机审)/推荐流/圈内流/详情/删除/点赞收藏。
package postlogic

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/yiora/server/internal/logic/draftlogic"
	"github.com/yiora/server/internal/logic/growth"
	"github.com/yiora/server/internal/logic/uploadlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/imgscan"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

const (
	maxTitleRunes   = 30
	maxContentRunes = 10000
	maxImages       = 9
	maxTopics       = 5
	maxMentions     = 10
	maxCocreators   = 3

	// 付费解锁定价区间与平台抽成的兜底默认(运营值走 app_config paid.*,后台「运营参数」页可调)
	defMinPaidPrice     = 1
	defMaxPaidPrice     = 1000
	defUnlockFeePercent = 10

	// 互动 → 热度实时增量权重(真值由周期重算公式兜底,见 PostModel.RecalcHotScores)
	hotLike     = 10
	hotComment  = 15
	hotFavorite = 12
)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Create 发动态。机审:拦截级直接驳回,人审级入审核队列,打码级替换后直发。
func (l *Logic) Create(ctx context.Context, uid int64, req *types.CreatePostReq) (*types.CreatePostResp, error) {
	title := strings.TrimSpace(req.Title)
	content := strings.TrimSpace(req.Content)
	if content == "" {
		return nil, xerr.Param("正文不能为空")
	}
	if utf8.RuneCountInString(title) > maxTitleRunes {
		return nil, xerr.Param(fmt.Sprintf("标题最多 %d 字", maxTitleRunes))
	}
	if utf8.RuneCountInString(content) > maxContentRunes {
		return nil, xerr.Param("正文超出长度限制")
	}
	if len(req.Images) > maxImages {
		return nil, xerr.Param(fmt.Sprintf("最多上传 %d 张图片", maxImages))
	}
	if err := l.checkImages(req.Images); err != nil {
		return nil, err
	}
	if req.LinkType != 0 {
		if !strings.HasPrefix(req.LinkURL, "https://") && !strings.HasPrefix(req.LinkURL, "http://") {
			return nil, xerr.Param("附加链接格式不正确")
		}
	}
	paidContent := strings.TrimSpace(req.PaidContent)
	if req.PaidPrice != 0 {
		minPrice := l.svcCtx.ConfigModel.Int(ctx, "paid.min_price", defMinPaidPrice)
		maxPrice := l.svcCtx.ConfigModel.Int(ctx, "paid.max_price", defMaxPaidPrice)
		if req.PaidPrice < minPrice || req.PaidPrice > maxPrice {
			return nil, xerr.Param(fmt.Sprintf("付费定价需为 %d-%d 忧珠", minPrice, maxPrice))
		}
		if paidContent == "" {
			return nil, xerr.Param("付费内容不能为空")
		}
		if utf8.RuneCountInString(paidContent) > maxContentRunes {
			return nil, xerr.Param("付费内容超出长度限制")
		}
	}
	circle, err := l.svcCtx.CircleModel.FindByID(ctx, req.CircleID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "圈子不存在")
		}
		return nil, fmt.Errorf("circle find: %w", err)
	}
	// 官方圈(官方公告等)仅圈主/管理员可发帖(需求 3.4),普通用户只读
	if circle.IsOfficial == 1 {
		role, err := l.svcCtx.CircleModel.RoleOf(ctx, req.CircleID, uid)
		if err != nil {
			return nil, fmt.Errorf("circle role: %w", err)
		}
		if role < model.CircleRoleAdmin {
			return nil, xerr.New(xerr.CodeForbidden, "官方圈子仅管理人员可以发帖")
		}
	}
	if err := l.checkMuted(ctx, req.CircleID, uid); err != nil {
		return nil, err
	}
	topics, err := l.checkTopics(ctx, req.Topics)
	if err != nil {
		return nil, err
	}
	mentions := dedupeUIDs(req.Mentions, uid)
	if len(mentions) > maxMentions {
		return nil, xerr.Param(fmt.Sprintf("最多@ %d 位好友", maxMentions))
	}
	cocreators, err := l.checkCocreators(ctx, uid, req.Cocreators)
	if err != nil {
		return nil, err
	}

	// 机审覆盖标题/摘要/付费段全文
	texts, level, hit, err := l.svcCtx.Filter.CheckAll(ctx, title, content, paidContent)
	if err != nil {
		return nil, fmt.Errorf("sensitive check: %w", err)
	}
	if level == model.WordLevelBlock {
		return nil, xerr.New(xerr.CodeContentBlocked, "内容包含违禁词,请修改后重试")
	}
	status, tip := model.PostStatusPublished, "发布成功"
	if level == model.WordLevelReview {
		status, tip = model.PostStatusPending, "已提交审核,通过后对外展示"
	}

	topicIDs, err := l.svcCtx.TopicModel.EnsureTopics(ctx, topics)
	if err != nil {
		return nil, err
	}
	images := make([]model.PostImage, 0, len(req.Images))
	for i, img := range req.Images {
		images = append(images, model.PostImage{URL: img.URL, Width: img.Width, Height: img.Height, Sort: int64(i)})
	}
	postID, err := l.svcCtx.PostModel.Create(ctx, &model.Post{
		UserID:   uid,
		CircleID: req.CircleID,
		Title:    texts[0],
		Content:  texts[1],
		LinkType: int64(req.LinkType),
		LinkURL:  req.LinkURL,
		Status:   int64(status),
	}, images, model.CreateExtra{
		PaidPrice:   req.PaidPrice,
		PaidContent: texts[2],
		TopicIDs:    topicIDs,
		Cocreators:  cocreators,
	})
	if err != nil {
		return nil, fmt.Errorf("create post: %w", err)
	}
	draftlogic.CleanAfterPublish(ctx, l.svcCtx, uid, req.DraftID)
	if status == model.PostStatusPending {
		if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizPost, postID, model.MachineSuspect, hit); err != nil {
			// 帖子已按待审核落库不外显,队列写失败只记日志,由后台待审列表兜底
			logx.WithContext(ctx).Errorf("post %d audit enqueue: %v", postID, err)
		}
	}
	l.scanImagesAsync(postID, uid, req.Images)
	if status == model.PostStatusPublished {
		l.taskProgress(ctx, uid, "post")
		growth.Grant(ctx, l.svcCtx, uid, growth.KindPost)
		// @通知与共创邀请通知仅对已发布帖发送;待审帖过审后由后台补发(M2 后台流程)
		brief := postBrief(&model.Post{Title: texts[0], Content: texts[1]})
		for _, m := range mentions {
			l.notify(ctx, &model.Notification{
				UserID: m, Type: model.NotifyTypeComment, ActorID: uid,
				TargetType: model.LikeTargetPost, TargetID: postID,
				Content: "在帖子中@了你: " + brief,
			})
		}
		for _, c := range cocreators {
			l.notify(ctx, &model.Notification{
				UserID: c, Type: model.NotifyTypeSystem, ActorID: uid,
				TargetType: model.LikeTargetPost, TargetID: postID,
				Content: "邀请你共创帖子: " + brief + ",进入帖子确认",
			})
		}
	}
	return &types.CreatePostResp{PostID: postID, Status: status, Tip: tip}, nil
}

const shareTTLSec = 30 * 86400

// Share 生成帖子分享口令:同帖 30 天内复用同一口令,首次生成计入 share_count。
func (l *Logic) Share(ctx context.Context, uid, postID int64) (*types.SharePostResp, error) {
	p, err := l.findPublished(ctx, postID)
	if err != nil {
		return nil, err
	}
	reuseKey := fmt.Sprintf("share:post:%d", postID)
	code, _ := l.svcCtx.Redis.GetCtx(ctx, reuseKey)
	if code == "" {
		code = "YR" + randShareCode(8)
		if err := l.svcCtx.Redis.SetexCtx(ctx, "share:code:"+code, fmt.Sprint(postID), shareTTLSec); err != nil {
			return nil, fmt.Errorf("store share code: %w", err)
		}
		_ = l.svcCtx.Redis.SetexCtx(ctx, reuseKey, code, shareTTLSec)
		if err := l.svcCtx.PostModel.IncrShareCount(ctx, postID); err != nil {
			logx.WithContext(ctx).Errorf("share count: %v", err)
		}
	}
	l.taskProgress(ctx, uid, "share") // 分享任务埋点(需求 3.8,后台可建 action=share 的任务)
	name := p.Title
	if name == "" {
		name = truncateShare(p.Content, 20)
	}
	return &types.SharePostResp{
		Code: code,
		Text: fmt.Sprintf("【%s】复制这段话打开 Yiora,输入口令即可查看:%s", name, code),
	}, nil
}

// ResolveShare 口令解析(免登录):返回帖子摘要供跳转确认。
func (l *Logic) ResolveShare(ctx context.Context, code string) (*types.ShareResolveResp, error) {
	code = strings.ToUpper(strings.TrimSpace(code))
	raw, err := l.svcCtx.Redis.GetCtx(ctx, "share:code:"+code)
	if err != nil || raw == "" {
		return nil, xerr.New(xerr.CodeNotFound, "口令无效或已过期")
	}
	postID, _ := strconv.ParseInt(raw, 10, 64)
	p, err := l.findPublished(ctx, postID)
	if err != nil {
		return nil, xerr.New(xerr.CodeNotFound, "帖子已下架或删除")
	}
	author, _ := l.svcCtx.UserModel.FindByID(ctx, p.UserID)
	authorName := ""
	if author != nil {
		authorName = author.Nickname
	}
	return &types.ShareResolveResp{
		PostID: p.ID, Title: p.Title, Summary: truncateShare(p.Content, 60),
		Author: authorName, AuthorID: p.UserID,
	}, nil
}

// randShareCode 口令随机段(去易混淆字符)。
func randShareCode(n int) string {
	const set = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
	var b strings.Builder
	for i := 0; i < n; i++ {
		idx, _ := rand.Int(rand.Reader, big.NewInt(int64(len(set))))
		b.WriteByte(set[idx.Int64()])
	}
	return b.String()
}

func truncateShare(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "..."
}

// checkImages 帖图必须来自我方对象存储(直传 fileUrl),防外链注入。
func (l *Logic) checkImages(images []types.ImageReq) error {
	for _, img := range images {
		if !uploadlogic.AllowedImageURL(l.svcCtx.Config, img.URL) {
			return xerr.Param("图片链接不合法,请通过上传接口获取")
		}
	}
	return nil
}

// checkTopics 话题名规范化:去 #/去空白/去重,≤5 个,每个 1-30 字且不含违禁词。
func (l *Logic) checkTopics(ctx context.Context, raw []string) ([]string, error) {
	out := make([]string, 0, len(raw))
	seen := map[string]bool{}
	for _, t := range raw {
		t = strings.TrimSpace(strings.Trim(strings.TrimSpace(t), "#"))
		if t == "" || seen[t] {
			continue
		}
		if utf8.RuneCountInString(t) > 30 {
			return nil, xerr.Param("话题名最多 30 字")
		}
		res, err := l.svcCtx.Filter.Check(ctx, t)
		if err != nil {
			return nil, fmt.Errorf("topic check: %w", err)
		}
		if res.Level != 0 {
			return nil, xerr.New(xerr.CodeContentBlocked, "话题包含违禁词,请更换")
		}
		seen[t] = true
		out = append(out, t)
	}
	if len(out) > maxTopics {
		return nil, xerr.Param(fmt.Sprintf("最多选择 %d 个话题", maxTopics))
	}
	return out, nil
}

// checkCocreators 共创者:≤3 人、去重排自己、必须互关(需求 3.5.1)。
func (l *Logic) checkCocreators(ctx context.Context, uid int64, raw []int64) ([]int64, error) {
	out := dedupeUIDs(raw, uid)
	if len(out) > maxCocreators {
		return nil, xerr.Param(fmt.Sprintf("最多邀请 %d 位共创者", maxCocreators))
	}
	for _, c := range out {
		mutual, err := l.svcCtx.IMModel.IsMutualFollow(ctx, uid, c)
		if err != nil {
			return nil, fmt.Errorf("check mutual: %w", err)
		}
		if !mutual {
			return nil, xerr.Param("共创者需为互关好友")
		}
	}
	return out, nil
}

func dedupeUIDs(raw []int64, exclude int64) []int64 {
	out := make([]int64, 0, len(raw))
	seen := map[int64]bool{}
	for _, id := range raw {
		if id <= 0 || id == exclude || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

// TopicPosts 话题聚合页:话题信息 + 按热度/时间聚合的帖子。
func (l *Logic) TopicPosts(ctx context.Context, uid int64, req *types.TopicPostsReq) (*types.TopicPostsResp, error) {
	t, err := l.svcCtx.TopicModel.FindByID(ctx, req.TopicID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "话题不存在")
		}
		return nil, fmt.Errorf("topic find: %w", err)
	}
	offset, limit := req.Offset()
	rows, err := l.svcCtx.TopicModel.PostsByTopic(ctx, req.TopicID, req.Sort, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("topic posts: %w", err)
	}
	posts, err := l.decorate(ctx, uid, rows)
	if err != nil {
		return nil, err
	}
	return &types.TopicPostsResp{
		Topic: types.TopicItem{ID: t.ID, Name: t.Name, PostCount: t.PostCount},
		Posts: posts,
	}, nil
}

// ConfirmCocreate 共创邀请确认/拒绝,双方主页展示随确认生效。
func (l *Logic) ConfirmCocreate(ctx context.Context, uid, postID int64, accept bool) error {
	p, err := l.svcCtx.PostModel.FindByID(ctx, postID)
	if err != nil {
		if model.IsNotFound(err) {
			return xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
		return fmt.Errorf("post find: %w", err)
	}
	ok, err := l.svcCtx.CocreatorModel.Confirm(ctx, postID, uid, accept)
	if err != nil {
		return err
	}
	if !ok {
		return xerr.New(xerr.CodeNotFound, "邀请不存在或已处理")
	}
	text := "接受了你的共创邀请"
	if !accept {
		text = "拒绝了你的共创邀请"
	}
	l.notify(ctx, &model.Notification{
		UserID: p.UserID, Type: model.NotifyTypeSystem, ActorID: uid,
		TargetType: model.LikeTargetPost, TargetID: postID,
		Content: text,
	})
	return nil
}

// taskProgress 行为任务埋点,失败不阻塞主流程。
func (l *Logic) taskProgress(ctx context.Context, uid int64, action string) {
	if err := l.svcCtx.TaskModel.IncrProgress(ctx, uid, action, time.Now()); err != nil {
		logx.WithContext(ctx).Errorf("task progress %s: %v", action, err)
	}
}

// checkMuted 禁言拦截:全站禁言(后台处置)优先,再查圈内禁言(需求 3.4/3.12)。
func (l *Logic) checkMuted(ctx context.Context, circleID, uid int64) error {
	if err := CheckGlobalMuted(ctx, l.svcCtx, uid); err != nil {
		return err
	}
	until, err := l.svcCtx.CircleModel.MutedUntil(ctx, circleID, uid)
	if err != nil {
		return fmt.Errorf("muted check: %w", err)
	}
	if until.After(time.Now()) {
		return xerr.New(xerr.CodeForbidden, "你在该圈内已被禁言至 "+until.Format("2006-01-02 15:04"))
	}
	return nil
}

// CheckGlobalMuted 全站禁言检查(发帖/评论/私信共用;Redis 故障放行,浏览类接口不调用)。
func CheckGlobalMuted(ctx context.Context, svcCtx *svc.ServiceContext, uid int64) error {
	muted, err := svcCtx.Redis.ExistsCtx(ctx, fmt.Sprintf("user:muted:%d", uid))
	if err != nil {
		logx.WithContext(ctx).Errorf("global mute check: %v", err)
		return nil
	}
	if muted {
		return xerr.New(xerr.CodeForbidden, "账号已被禁言,暂时无法发布内容")
	}
	return nil
}

// DecoratePosts 供搜索等外部模块复用的列表装配入口。
func (l *Logic) DecoratePosts(ctx context.Context, uid int64, rows []*model.Post) ([]types.PostItem, error) {
	return l.decorate(ctx, uid, rows)
}

// Feed 首页推荐单列表。
func (l *Logic) Feed(ctx context.Context, uid int64, req *types.FeedReq) ([]types.PostItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.PostModel.ListFeed(ctx, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("feed list: %w", err)
	}
	return l.decorate(ctx, uid, rows)
}

// CirclePosts 圈内信息流。
func (l *Logic) CirclePosts(ctx context.Context, uid int64, req *types.CirclePostsReq) ([]types.PostItem, error) {
	if _, err := l.svcCtx.CircleModel.FindByID(ctx, req.CircleID); err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "圈子不存在")
		}
		return nil, fmt.Errorf("circle find: %w", err)
	}
	offset, limit := req.Offset()
	rows, err := l.svcCtx.PostModel.ListByCircle(ctx, req.CircleID, req.Sort, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("circle posts: %w", err)
	}
	return l.decorate(ctx, uid, rows)
}

// Edit 作者编辑帖子(需求 3.3):重过机审,疑似词重回待审;付费段不可改。
func (l *Logic) Edit(ctx context.Context, uid int64, req *types.EditPostReq) (*types.EditPostResp, error) {
	p, err := l.svcCtx.PostModel.FindByID(ctx, req.PostID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
		return nil, fmt.Errorf("post find: %w", err)
	}
	if p.UserID != uid {
		return nil, xerr.New(xerr.CodeForbidden, "只有作者可以编辑")
	}
	if p.Status == model.PostStatusDeleted || p.Status == model.PostStatusTakenDown {
		return nil, xerr.New(xerr.CodeNotFound, "帖子不存在或已下架")
	}

	title := strings.TrimSpace(req.Title)
	content := strings.TrimSpace(req.Content)
	if content == "" {
		return nil, xerr.Param("正文不能为空")
	}
	if utf8.RuneCountInString(title) > maxTitleRunes {
		return nil, xerr.Param(fmt.Sprintf("标题最多 %d 字", maxTitleRunes))
	}
	if utf8.RuneCountInString(content) > maxContentRunes {
		return nil, xerr.Param("正文超出长度限制")
	}
	if len(req.Images) > maxImages {
		return nil, xerr.Param(fmt.Sprintf("最多上传 %d 张图片", maxImages))
	}
	if err := l.checkImages(req.Images); err != nil {
		return nil, err
	}
	if req.LinkType != 0 {
		if !strings.HasPrefix(req.LinkURL, "https://") && !strings.HasPrefix(req.LinkURL, "http://") {
			return nil, xerr.Param("附加链接格式不正确")
		}
	}
	topics, err := l.checkTopics(ctx, req.Topics)
	if err != nil {
		return nil, err
	}

	texts, level, hit, err := l.svcCtx.Filter.CheckAll(ctx, title, content)
	if err != nil {
		return nil, fmt.Errorf("sensitive check: %w", err)
	}
	if level == model.WordLevelBlock {
		return nil, xerr.New(xerr.CodeContentBlocked, "内容包含违禁词,请修改后重试")
	}
	newStatus, tip := model.PostStatusPublished, "已保存"
	if level == model.WordLevelReview {
		newStatus, tip = model.PostStatusPending, "已保存,修改内容需重新审核"
	}

	topicIDs, err := l.svcCtx.TopicModel.EnsureTopics(ctx, topics)
	if err != nil {
		return nil, err
	}
	images := make([]model.PostImage, 0, len(req.Images))
	for i, img := range req.Images {
		images = append(images, model.PostImage{URL: img.URL, Width: img.Width, Height: img.Height, Sort: int64(i)})
	}
	upd := *p
	upd.Title, upd.Content = texts[0], texts[1]
	upd.LinkType, upd.LinkURL = int64(req.LinkType), req.LinkURL
	if err := l.svcCtx.PostModel.Update(ctx, &upd, int64(newStatus), images, topicIDs); err != nil {
		return nil, fmt.Errorf("update post: %w", err)
	}
	if newStatus == model.PostStatusPending {
		if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizPost, p.ID, model.MachineSuspect, hit); err != nil {
			logx.WithContext(ctx).Errorf("post %d audit enqueue: %v", p.ID, err)
		}
	}
	l.scanImagesAsync(p.ID, uid, req.Images)
	return &types.EditPostResp{Status: newStatus, Tip: tip}, nil
}

// scanImagesAsync 帖图异步机审:不阻塞发布,取全部图片中最严重结论落地。
// review → 进人审队列(帖子保持原状态,人工定夺);block → 直接驳回下架+通知作者(可人工翻案)。
// 云端出错按放行降级(纯人审兜底),绝不因外部依赖阻断业务。
func (l *Logic) scanImagesAsync(postID, uid int64, imgs []types.ImageReq) {
	if l.svcCtx.ImgScanner == nil || len(imgs) == 0 {
		return
	}
	urls := make([]string, 0, len(imgs))
	for _, im := range imgs {
		urls = append(urls, im.URL)
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		worst, worstURL := (*imgscan.Result)(nil), ""
		for _, u := range urls {
			r, err := l.svcCtx.ImgScanner.Scan(ctx, u)
			if err != nil {
				logx.Errorf("imgscan post %d url %s: %v", postID, u, err)
				continue
			}
			if worst == nil || r.Verdict > worst.Verdict {
				worst, worstURL = r, u
			}
		}
		if worst == nil || worst.Verdict == imgscan.VerdictPass {
			return
		}
		detail, _ := json.Marshal(map[string]any{
			"img": worstURL, "label": worst.Label, "score": worst.Score, "scanner": l.svcCtx.ImgScanner.Name(),
		})
		switch worst.Verdict {
		case imgscan.VerdictReview:
			if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizPost, postID, model.MachineSuspect, string(detail)); err != nil {
				logx.Errorf("imgscan post %d enqueue: %v", postID, err)
			}
		case imgscan.VerdictBlock:
			if err := l.svcCtx.PostModel.MachineReject(ctx, postID); err != nil {
				logx.Errorf("imgscan post %d reject: %v", postID, err)
				return
			}
			if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizPost, postID, model.MachineBlocked, string(detail)); err != nil {
				logx.Errorf("imgscan post %d block audit: %v", postID, err)
			}
			l.notify(ctx, &model.Notification{
				UserID: uid, Type: model.NotifyTypeSystem, ActorID: model.BotUID,
				TargetType: model.LikeTargetPost, TargetID: postID,
				Content: "你的帖子图片涉嫌违规已被系统拦截,如有异议请联系管理员申诉",
			})
		}
	}()
}

// AuthorPosts 个人主页作品 Tab。本人可见待审/驳回帖。
func (l *Logic) AuthorPosts(ctx context.Context, viewer int64, req *types.AuthorPostsReq) ([]types.PostItem, error) {
	self := viewer > 0 && viewer == req.UserID
	offset, limit := req.Offset()
	rows, err := l.svcCtx.PostModel.ListByAuthor(ctx, req.UserID, self, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("author posts: %w", err)
	}
	return l.decorate(ctx, viewer, rows)
}

// History 我的足迹(仅自己可见)。
func (l *Logic) History(ctx context.Context, uid int64, req *types.PageReq) ([]types.PostItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.PostModel.ListHistory(ctx, uid, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("history: %w", err)
	}
	return l.decorate(ctx, uid, rows)
}

// ClearHistory 清空足迹。
func (l *Logic) ClearHistory(ctx context.Context, uid int64) error {
	return l.svcCtx.PostModel.ClearHistory(ctx, uid)
}

// Favorites 我的收藏。
func (l *Logic) Favorites(ctx context.Context, uid int64, req *types.PageReq) ([]types.PostItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.PostModel.ListFavorites(ctx, uid, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("favorites: %w", err)
	}
	return l.decorate(ctx, uid, rows)
}

// Detail 帖子详情。待审/驳回帖仅作者可见;登录用户浏览量 24h 去重计数。
func (l *Logic) Detail(ctx context.Context, uid, postID int64) (*types.PostItem, error) {
	p, err := l.findVisible(ctx, uid, postID)
	if err != nil {
		return nil, err
	}
	if uid > 0 && p.Status == model.PostStatusPublished {
		ok, err := l.svcCtx.Redis.SetnxExCtx(ctx, fmt.Sprintf("post:view:%d:%d", uid, postID), "1", 86400)
		if err != nil {
			logx.WithContext(ctx).Errorf("post %d view dedup: %v", postID, err)
		} else if ok {
			if err := l.svcCtx.PostModel.IncrView(ctx, postID, 1); err != nil {
				logx.WithContext(ctx).Errorf("post %d incr view: %v", postID, err)
			} else {
				p.ViewCount++
			}
			l.svcCtx.PostModel.BumpHotScore(ctx, postID, 1) // 有效浏览计热度
			l.taskProgress(ctx, uid, "browse")              // 24h 去重后的有效浏览才计任务
		}
		if err := l.svcCtx.PostModel.UpsertViewHistory(ctx, uid, postID); err != nil {
			logx.WithContext(ctx).Errorf("post %d view history: %v", postID, err)
		}
	}
	items, err := l.decorate(ctx, uid, []*model.Post{p})
	if err != nil {
		return nil, err
	}
	item := &items[0]
	// 付费段:作者或已解锁用户才下发全文,防客户端绕过
	if item.PaidPrice > 0 && item.Unlocked {
		paid, err := l.svcCtx.PaidModel.Find(ctx, postID)
		if err != nil {
			return nil, fmt.Errorf("paid content: %w", err)
		}
		item.PaidContent = paid.Content
	}
	// 已确认共创者(共创双方主页与详情展示)
	accepted, err := l.svcCtx.CocreatorModel.AcceptedOfPosts(ctx, []int64{postID})
	if err != nil {
		return nil, fmt.Errorf("cocreators: %w", err)
	}
	if uids := accepted[postID]; len(uids) > 0 {
		briefs, err := l.svcCtx.UserModel.FindBriefs(ctx, uids)
		if err != nil {
			return nil, fmt.Errorf("cocreator briefs: %w", err)
		}
		for _, cu := range uids {
			item.Cocreators = append(item.Cocreators, ToUserBrief(cu, briefs[cu]))
		}
	}
	return item, nil
}

// Unlock 忧珠解锁付费帖:买家扣款+作者分成(平台抽成)双账户单事务,成功即下发全文。
func (l *Logic) Unlock(ctx context.Context, uid, postID int64) (*types.UnlockResp, error) {
	// 青少年模式禁用消费(userlogic 依赖本包,这里内联检查避免 import 环)
	if u, err := l.svcCtx.UserModel.FindByID(ctx, uid); err == nil && u.TeenMode == 1 {
		return nil, xerr.New(xerr.CodeForbidden, "青少年模式下无法使用该功能")
	}
	p, err := l.findPublished(ctx, postID)
	if err != nil {
		return nil, err
	}
	if p.UserID == uid {
		return nil, xerr.Param("自己的帖子无需解锁")
	}
	paid, err := l.svcCtx.PaidModel.Find(ctx, postID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.Param("该帖子不是付费帖")
		}
		return nil, fmt.Errorf("paid find: %w", err)
	}
	feePercent := l.svcCtx.ConfigModel.Int(ctx, "paid.fee_percent", defUnlockFeePercent)
	if feePercent < 0 || feePercent > 50 {
		feePercent = defUnlockFeePercent
	}
	income, err := l.svcCtx.PaidModel.Unlock(ctx, uid, p.UserID, postID, paid.Price, feePercent)
	if err != nil {
		switch {
		case errors.Is(err, model.ErrAlreadyUnlocked):
			// 已解锁按成功返回全文,方便客户端重试
		case errors.Is(err, model.ErrInsufficientBalance):
			return nil, xerr.New(xerr.CodeForbidden, "忧珠余额不足")
		default:
			return nil, fmt.Errorf("unlock: %w", err)
		}
	} else {
		l.notify(ctx, &model.Notification{
			UserID: p.UserID, Type: model.NotifyTypeSystem, ActorID: uid,
			TargetType: model.LikeTargetPost, TargetID: postID,
			Content: fmt.Sprintf("解锁了你的付费帖,分成 +%d 忧珠", income),
		})
	}
	balance, err := l.svcCtx.YouzhuModel.Balance(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("balance: %w", err)
	}
	return &types.UnlockResp{PaidContent: paid.Content, Balance: balance}, nil
}

// Delete 作者删帖(软删)。
func (l *Logic) Delete(ctx context.Context, uid, postID int64) error {
	hit, err := l.svcCtx.PostModel.SoftDelete(ctx, postID, uid)
	if err != nil {
		return fmt.Errorf("post delete: %w", err)
	}
	if !hit {
		return xerr.New(xerr.CodeNotFound, "帖子不存在或无权删除")
	}
	return nil
}

// Like 点赞帖子,幂等;首次点赞给作者写通知。
func (l *Logic) Like(ctx context.Context, uid, postID int64) error {
	p, err := l.findPublished(ctx, postID)
	if err != nil {
		return err
	}
	added, err := l.svcCtx.InteractModel.Like(ctx, uid, model.LikeTargetPost, postID)
	if err != nil {
		return fmt.Errorf("post like: %w", err)
	}
	if added && p.UserID != uid {
		l.notify(ctx, &model.Notification{
			UserID: p.UserID, Type: model.NotifyTypeLike, ActorID: uid,
			TargetType: model.LikeTargetPost, TargetID: postID,
			Content: "赞了你的帖子 " + postBrief(p),
		})
		growth.Grant(ctx, l.svcCtx, p.UserID, growth.KindLikeReceived) // 被赞加经验(需求 3.1)
	}
	if added {
		l.taskProgress(ctx, uid, "like")
		l.svcCtx.PostModel.BumpHotScore(ctx, postID, hotLike)
	}
	return nil
}

func (l *Logic) Unlike(ctx context.Context, uid, postID int64) error {
	if err := l.svcCtx.InteractModel.Unlike(ctx, uid, model.LikeTargetPost, postID); err != nil {
		return fmt.Errorf("post unlike: %w", err)
	}
	l.svcCtx.PostModel.BumpHotScore(ctx, postID, -hotLike)
	return nil
}

// Favorite 收藏帖子,幂等;首次收藏给作者写通知。
func (l *Logic) Favorite(ctx context.Context, uid, postID int64) error {
	p, err := l.findPublished(ctx, postID)
	if err != nil {
		return err
	}
	added, err := l.svcCtx.InteractModel.Favorite(ctx, uid, postID)
	if err != nil {
		return fmt.Errorf("post favorite: %w", err)
	}
	if added && p.UserID != uid {
		l.notify(ctx, &model.Notification{
			UserID: p.UserID, Type: model.NotifyTypeLike, ActorID: uid,
			TargetType: model.LikeTargetPost, TargetID: postID,
			Content: "收藏了你的帖子 " + postBrief(p),
		})
	}
	if added {
		l.svcCtx.PostModel.BumpHotScore(ctx, postID, hotFavorite)
	}
	return nil
}

func (l *Logic) Unfavorite(ctx context.Context, uid, postID int64) error {
	if err := l.svcCtx.InteractModel.Unfavorite(ctx, uid, postID); err != nil {
		return fmt.Errorf("post unfavorite: %w", err)
	}
	l.svcCtx.PostModel.BumpHotScore(ctx, postID, -hotFavorite)
	return nil
}

// findVisible 详情可见性:已发布对所有人可见,待审/驳回仅作者,已删/下架一律 404。
func (l *Logic) findVisible(ctx context.Context, uid, postID int64) (*model.Post, error) {
	p, err := l.svcCtx.PostModel.FindByID(ctx, postID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
		return nil, fmt.Errorf("post find: %w", err)
	}
	switch p.Status {
	case model.PostStatusPublished:
		return p, nil
	case model.PostStatusPending, model.PostStatusRejected:
		if p.UserID == uid {
			return p, nil
		}
	}
	return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
}

// findPublished 互动前置校验:仅已发布帖可点赞/收藏/评论。
func (l *Logic) findPublished(ctx context.Context, postID int64) (*model.Post, error) {
	p, err := l.svcCtx.PostModel.FindByID(ctx, postID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
		}
		return nil, fmt.Errorf("post find: %w", err)
	}
	if p.Status != model.PostStatusPublished {
		return nil, xerr.New(xerr.CodeNotFound, "帖子不存在")
	}
	return p, nil
}

// notify 通知写失败不影响主操作,只记日志。
func (l *Logic) notify(ctx context.Context, n *model.Notification) {
	if err := l.svcCtx.NotifyModel.Add(ctx, n); err != nil {
		logx.WithContext(ctx).Errorf("add notification: %v", err)
	}
}

// decorate 批量补齐作者/圈子名/图片/点赞收藏状态,组装列表项。
// Status 恒下发:公开流里只有已发布(1),作者视角能看到待审/驳回的真实状态。
func (l *Logic) decorate(ctx context.Context, uid int64, rows []*model.Post) ([]types.PostItem, error) {
	out := make([]types.PostItem, 0, len(rows))
	if len(rows) == 0 {
		return out, nil
	}
	postIDs := make([]int64, 0, len(rows))
	authorIDs := make([]int64, 0, len(rows))
	circleIDs := make([]int64, 0, len(rows))
	for _, p := range rows {
		postIDs = append(postIDs, p.ID)
		authorIDs = append(authorIDs, p.UserID)
		circleIDs = append(circleIDs, p.CircleID)
	}
	images, err := l.svcCtx.PostModel.ImagesOf(ctx, postIDs)
	if err != nil {
		return nil, fmt.Errorf("post images: %w", err)
	}
	briefs, err := l.svcCtx.UserModel.FindBriefs(ctx, authorIDs)
	if err != nil {
		return nil, fmt.Errorf("author briefs: %w", err)
	}
	names, err := l.svcCtx.CircleModel.FindNames(ctx, circleIDs)
	if err != nil {
		return nil, fmt.Errorf("circle names: %w", err)
	}
	liked, err := l.svcCtx.InteractModel.LikedSet(ctx, uid, model.LikeTargetPost, postIDs)
	if err != nil {
		return nil, fmt.Errorf("liked set: %w", err)
	}
	faved, err := l.svcCtx.InteractModel.FavoritedSet(ctx, uid, postIDs)
	if err != nil {
		return nil, fmt.Errorf("favorited set: %w", err)
	}
	prices, err := l.svcCtx.PaidModel.Prices(ctx, postIDs)
	if err != nil {
		return nil, fmt.Errorf("paid prices: %w", err)
	}
	unlocked, err := l.svcCtx.PaidModel.UnlockedSet(ctx, uid, postIDs)
	if err != nil {
		return nil, fmt.Errorf("unlocked set: %w", err)
	}
	topics, err := l.svcCtx.TopicModel.TopicsOfPosts(ctx, postIDs)
	if err != nil {
		return nil, fmt.Errorf("post topics: %w", err)
	}
	for _, p := range rows {
		item := types.PostItem{
			ID:            p.ID,
			Author:        ToUserBrief(p.UserID, briefs[p.UserID]),
			CircleID:      p.CircleID,
			CircleName:    names[p.CircleID],
			Title:         p.Title,
			Content:       p.Content,
			Images:        toImages(images[p.ID]),
			LinkType:      p.LinkType,
			LinkURL:       p.LinkURL,
			IsTop:         p.IsTop == 1,
			IsEssence:     p.IsEssence == 1,
			IsRedTitle:    p.IsRedTitle == 1,
			ViewCount:     p.ViewCount,
			LikeCount:     p.LikeCount,
			CommentCount:  p.CommentCount,
			FavoriteCount: p.FavoriteCount,
			Liked:         liked[p.ID],
			Favorited:     faved[p.ID],
			Status:        p.Status,
			CreatedAt:     p.CreatedAt.UnixMilli(),
		}
		if price := prices[p.ID]; price > 0 {
			item.PaidPrice = price
			item.Unlocked = p.UserID == uid || unlocked[p.ID]
		}
		for _, t := range topics[p.ID] {
			item.Topics = append(item.Topics, types.TopicItem{ID: t.ID, Name: t.Name, PostCount: t.PostCount})
		}
		out = append(out, item)
	}
	return out, nil
}

func toImages(imgs []model.PostImage) []types.ImageReq {
	out := make([]types.ImageReq, 0, len(imgs))
	for _, img := range imgs {
		out = append(out, types.ImageReq{URL: img.URL, Width: img.Width, Height: img.Height})
	}
	return out
}

// ToUserBrief 组装用户摘要;用户不存在(注销)时仅回 ID,昵称置"已注销"。
func ToUserBrief(uid int64, b *model.UserBrief) types.UserBrief {
	if b == nil {
		return types.UserBrief{UserID: uid, Nickname: "已注销用户"}
	}
	return types.UserBrief{
		UserID:      b.ID,
		DisplayNo:   b.DisplayNo.String,
		Nickname:    b.Nickname,
		Avatar:      b.Avatar,
		Level:       b.Level,
		AvatarFrame: b.AvatarFrame,
	}
}

// postBrief 通知文案里的帖子摘要:优先标题,无标题取正文前 20 字。
func postBrief(p *model.Post) string {
	s := p.Title
	if s == "" {
		s = p.Content
	}
	r := []rune(s)
	if len(r) > 20 {
		return string(r[:20]) + "…"
	}
	return s
}
