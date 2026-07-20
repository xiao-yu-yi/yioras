// Package softwarelogic 社区软件库:发布(强校验+机审前置+全量人审)/新版本/列表/详情/我的发布/下载计数/分类。
package softwarelogic

import (
	"context"
	"fmt"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/yiora/server/internal/logic/draftlogic"
	"github.com/yiora/server/internal/logic/postlogic"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

const (
	minIntroImages = 3
	maxIntroImages = 6
	maxTags        = 5
	maxIntroRunes  = 1000
)

// versionPattern 版本号:1~4 段数字,如 2 / 2.3 / 2.3.1 / 2.3.1.100
var versionPattern = regexp.MustCompile(`^\d+(\.\d+){0,3}$`)

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// Create 发软件。需求 3.5.2:介绍图 3-6 张强校验;新软件一律进人审(机审仅前置粗筛,拦截级直接驳回)。
func (l *Logic) Create(ctx context.Context, uid int64, req *types.CreateSoftwareReq) (*types.CreateSoftwareResp, error) {
	name := strings.TrimSpace(req.Name)
	intro := strings.TrimSpace(req.Intro)
	if name == "" {
		return nil, xerr.Param("软件名字不能为空")
	}
	if utf8.RuneCountInString(name) > 50 {
		return nil, xerr.Param("软件名字最多 50 字")
	}
	if intro == "" {
		return nil, xerr.Param("软件简介不能为空")
	}
	if utf8.RuneCountInString(intro) > maxIntroRunes {
		return nil, xerr.Param(fmt.Sprintf("软件简介最多 %d 字", maxIntroRunes))
	}
	if err := checkURL(req.Logo, "Logo"); err != nil {
		return nil, err
	}
	if len(req.Images) < minIntroImages || len(req.Images) > maxIntroImages {
		return nil, xerr.Param(fmt.Sprintf("介绍图需为 %d-%d 张", minIntroImages, maxIntroImages))
	}
	for _, img := range req.Images {
		if err := checkURL(img, "介绍图"); err != nil {
			return nil, err
		}
	}
	if len(req.Tags) > maxTags {
		return nil, xerr.Param(fmt.Sprintf("标签最多 %d 个", maxTags))
	}
	tags := make([]string, 0, len(req.Tags))
	for _, t := range req.Tags {
		t = strings.TrimSpace(t)
		if t == "" {
			continue
		}
		if utf8.RuneCountInString(t) > 20 {
			return nil, xerr.Param("单个标签最多 20 字")
		}
		tags = append(tags, t)
	}
	version, size, channel, err := checkVersionFields(req.Version, req.Size, req.Channel, req.DownloadURL)
	if err != nil {
		return nil, err
	}

	// 机审前置粗筛:名字/简介/标签,拦截级直接驳回;其余(含疑似)统一进人审
	texts := append([]string{name, intro}, tags...)
	checked, level, hit, err := l.svcCtx.Filter.CheckAll(ctx, texts...)
	if err != nil {
		return nil, fmt.Errorf("sensitive check: %w", err)
	}
	if level == model.WordLevelBlock {
		return nil, xerr.New(xerr.CodeContentBlocked, "内容包含违禁词,请修改后重试")
	}
	name, intro = checked[0], checked[1]
	tags = checked[2:]

	imagesJSON, err := model.MarshalImages(req.Images)
	if err != nil {
		return nil, err
	}
	if _, err := l.svcCtx.SoftwareModel.FindCategory(ctx, req.CategoryID); err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "分类不存在")
		}
		return nil, fmt.Errorf("find category: %w", err)
	}

	softwareID, versionID, err := l.svcCtx.SoftwareModel.Create(ctx,
		&model.Software{
			UserID: uid, Name: name, Logo: req.Logo, Intro: intro,
			Images: imagesJSON, Type: req.Type, CategoryID: req.CategoryID,
		},
		&model.SoftwareVersion{
			Version: version, Size: size, Channel: channel,
			DownloadURL: req.DownloadURL, ExtractCode: strings.TrimSpace(req.ExtractCode),
		}, tags)
	if err != nil {
		return nil, fmt.Errorf("create software: %w", err)
	}
	// 新软件全量人审;机审命中疑似词的写入命中明细
	machine := 1
	if level == model.WordLevelReview {
		machine = model.MachineSuspect
	}
	if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizSoftware, softwareID, machine,
		fmt.Sprintf(`{"kind":"software","versionId":%d,"hit":%q}`, versionID, hit)); err != nil {
		logx.WithContext(ctx).Errorf("software %d audit enqueue: %v", softwareID, err)
	}
	draftlogic.CleanAfterPublish(ctx, l.svcCtx, uid, req.DraftID)
	return &types.CreateSoftwareResp{
		SoftwareID: softwareID, VersionID: versionID,
		Status: model.SoftwareStatusPending, Tip: "已提交审核,通过后上架",
	}, nil
}

// CreateVersion 发布新版本(仅发布者;版本更新同样需审核)。
func (l *Logic) CreateVersion(ctx context.Context, uid int64, req *types.CreateVersionReq) (*types.CreateVersionResp, error) {
	s, err := l.svcCtx.SoftwareModel.FindByID(ctx, req.SoftwareID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "软件不存在")
		}
		return nil, fmt.Errorf("find software: %w", err)
	}
	if s.UserID != uid {
		return nil, xerr.New(xerr.CodeForbidden, "只有发布者可以更新版本")
	}
	if s.Status == model.SoftwareStatusDeleted {
		return nil, xerr.New(xerr.CodeNotFound, "软件不存在")
	}
	version, size, channel, err := checkVersionFields(req.Version, req.Size, req.Channel, req.DownloadURL)
	if err != nil {
		return nil, err
	}
	versionID, err := l.svcCtx.SoftwareModel.AddVersion(ctx, &model.SoftwareVersion{
		SoftwareID: req.SoftwareID, Version: version, Size: size, Channel: channel,
		DownloadURL: req.DownloadURL, ExtractCode: strings.TrimSpace(req.ExtractCode),
	})
	if err != nil {
		if model.IsDupKey(err) {
			return nil, xerr.Param("该版本号已存在")
		}
		return nil, err
	}
	if err := l.svcCtx.SensitiveModel.AddAudit(ctx, model.AuditBizSoftware, req.SoftwareID, 1,
		fmt.Sprintf(`{"kind":"version","versionId":%d}`, versionID)); err != nil {
		logx.WithContext(ctx).Errorf("version %d audit enqueue: %v", versionID, err)
	}
	return &types.CreateVersionResp{VersionID: versionID, Status: model.VersionStatusPending, Tip: "已提交审核,通过后可下载"}, nil
}

// List 软件库列表(最新/最热/下载最多,分类筛选)。
func (l *Logic) List(ctx context.Context, req *types.SoftwareListReq) ([]types.SoftwareItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.SoftwareModel.List(ctx, req.Type, req.CategoryID, req.Sort, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("software list: %w", err)
	}
	return l.decorate(ctx, rows)
}

// Mine 我的发布(含审核状态)。
func (l *Logic) Mine(ctx context.Context, uid int64, req *types.PageReq) ([]types.SoftwareItem, error) {
	offset, limit := req.Offset()
	rows, err := l.svcCtx.SoftwareModel.ListByAuthor(ctx, uid, offset, limit)
	if err != nil {
		return nil, fmt.Errorf("my software: %w", err)
	}
	return l.decorate(ctx, rows)
}

// Detail 详情:已上架对所有人可见;待审/驳回/下架仅发布者。发布者可见全部版本与提取码。
func (l *Logic) Detail(ctx context.Context, uid, softwareID int64) (*types.SoftwareDetailResp, error) {
	s, err := l.findVisible(ctx, uid, softwareID)
	if err != nil {
		return nil, err
	}
	self := s.UserID == uid
	versions, err := l.svcCtx.SoftwareModel.Versions(ctx, softwareID, !self)
	if err != nil {
		return nil, fmt.Errorf("versions: %w", err)
	}
	tags, err := l.svcCtx.SoftwareModel.Tags(ctx, []int64{softwareID})
	if err != nil {
		return nil, fmt.Errorf("tags: %w", err)
	}
	briefs, err := l.svcCtx.UserModel.FindBriefs(ctx, []int64{s.UserID})
	if err != nil {
		return nil, fmt.Errorf("publisher brief: %w", err)
	}

	item := toItem(s)
	item.Tags = tags[softwareID]
	if item.Tags == nil {
		item.Tags = []string{}
	}
	resp := &types.SoftwareDetailResp{
		SoftwareItem: item,
		Images:       model.UnmarshalImages(s.Images),
		Publisher:    postlogic.ToUserBrief(s.UserID, briefs[s.UserID]),
		Versions:     make([]types.VersionItem, 0, len(versions)),
	}
	for _, v := range versions {
		resp.Versions = append(resp.Versions, types.VersionItem{
			ID: v.ID, Version: v.Version, Size: v.Size, Channel: v.Channel,
			DownloadURL: v.DownloadURL, ExtractCode: v.ExtractCode,
			Status: v.Status, CreatedAt: v.CreatedAt.UnixMilli(),
		})
	}
	// 列表项冗余最新版本号(取最新已发布)
	for _, v := range versions {
		if v.Status == model.VersionStatusPublished {
			resp.Version, resp.Size = v.Version, v.Size
			break
		}
	}
	return resp, nil
}

// Download 下载点击:校验软件已上架、版本已发布 → 计数 → 返回链接。
func (l *Logic) Download(ctx context.Context, uid int64, req *types.DownloadReq) (*types.DownloadResp, error) {
	s, err := l.svcCtx.SoftwareModel.FindByID(ctx, req.SoftwareID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "软件不存在")
		}
		return nil, fmt.Errorf("find software: %w", err)
	}
	if s.Status != model.SoftwareStatusOnline {
		return nil, xerr.New(xerr.CodeNotFound, "软件不存在或已下架")
	}
	var v *model.SoftwareVersion
	if req.VersionID > 0 {
		if v, err = l.svcCtx.SoftwareModel.FindVersion(ctx, req.VersionID); err != nil {
			if model.IsNotFound(err) {
				return nil, xerr.New(xerr.CodeNotFound, "版本不存在")
			}
			return nil, fmt.Errorf("find version: %w", err)
		}
		if v.SoftwareID != req.SoftwareID || v.Status != model.VersionStatusPublished {
			return nil, xerr.New(xerr.CodeNotFound, "版本不存在")
		}
	} else {
		versions, err := l.svcCtx.SoftwareModel.Versions(ctx, req.SoftwareID, true)
		if err != nil {
			return nil, fmt.Errorf("versions: %w", err)
		}
		if len(versions) == 0 {
			return nil, xerr.New(xerr.CodeNotFound, "暂无可下载版本")
		}
		v = versions[0]
	}
	if err := l.svcCtx.SoftwareModel.RecordDownload(ctx, req.SoftwareID, v.ID, uid); err != nil {
		// 计数失败不阻塞下载,热度允许少记
		logx.WithContext(ctx).Errorf("software %d download record: %v", req.SoftwareID, err)
	}
	return &types.DownloadResp{
		VersionID: v.ID, Version: v.Version,
		DownloadURL: v.DownloadURL, ExtractCode: v.ExtractCode,
	}, nil
}

// DecorateSoftware 供搜索等外部模块复用的列表装配入口。
func (l *Logic) DecorateSoftware(ctx context.Context, rows []*model.Software) ([]types.SoftwareItem, error) {
	return l.decorate(ctx, rows)
}

// Categories 分类列表(发布器选择器与列表筛选共用)。
func (l *Logic) Categories(ctx context.Context, req *types.CategoryListReq) ([]types.CategoryItem, error) {
	rows, err := l.svcCtx.SoftwareModel.Categories(ctx, req.Type)
	if err != nil {
		return nil, fmt.Errorf("categories: %w", err)
	}
	out := make([]types.CategoryItem, 0, len(rows))
	for _, c := range rows {
		out = append(out, types.CategoryItem{ID: c.ID, Type: c.Type, Name: c.Name})
	}
	return out, nil
}

func (l *Logic) findVisible(ctx context.Context, uid, softwareID int64) (*model.Software, error) {
	s, err := l.svcCtx.SoftwareModel.FindByID(ctx, softwareID)
	if err != nil {
		if model.IsNotFound(err) {
			return nil, xerr.New(xerr.CodeNotFound, "软件不存在")
		}
		return nil, fmt.Errorf("find software: %w", err)
	}
	if s.Status == model.SoftwareStatusOnline {
		return s, nil
	}
	if s.Status != model.SoftwareStatusDeleted && s.UserID == uid {
		return s, nil
	}
	return nil, xerr.New(xerr.CodeNotFound, "软件不存在")
}

// decorate 批量补齐标签与最新版本号。Status 恒下发:公开列表只有已上架(1),发布者视角为真实状态。
func (l *Logic) decorate(ctx context.Context, rows []*model.Software) ([]types.SoftwareItem, error) {
	out := make([]types.SoftwareItem, 0, len(rows))
	if len(rows) == 0 {
		return out, nil
	}
	ids := make([]int64, 0, len(rows))
	versionIDs := make([]int64, 0, len(rows))
	for _, s := range rows {
		ids = append(ids, s.ID)
		if s.LatestVersionID > 0 {
			versionIDs = append(versionIDs, s.LatestVersionID)
		}
	}
	tags, err := l.svcCtx.SoftwareModel.Tags(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("tags: %w", err)
	}
	latest := make(map[int64]*model.SoftwareVersion, len(versionIDs))
	for _, vid := range versionIDs {
		v, err := l.svcCtx.SoftwareModel.FindVersion(ctx, vid)
		if err != nil {
			if model.IsNotFound(err) {
				continue
			}
			return nil, fmt.Errorf("latest version: %w", err)
		}
		latest[vid] = v
	}
	for _, s := range rows {
		item := toItem(s)
		item.Tags = tags[s.ID]
		if item.Tags == nil {
			item.Tags = []string{}
		}
		if v := latest[s.LatestVersionID]; v != nil {
			item.Version, item.Size = v.Version, v.Size
		}
		out = append(out, item)
	}
	return out, nil
}

func toItem(s *model.Software) types.SoftwareItem {
	return types.SoftwareItem{
		ID:            s.ID,
		Name:          s.Name,
		Logo:          s.Logo,
		Intro:         s.Intro,
		Type:          s.Type,
		CategoryID:    s.CategoryID,
		DownloadCount: s.DownloadCount,
		CommentCount:  s.CommentCount,
		Status:        s.Status,
		CreatedAt:     s.CreatedAt.UnixMilli(),
	}
}

func checkURL(u, field string) error {
	if len(u) > 500 || (!strings.HasPrefix(u, "https://") && !strings.HasPrefix(u, "http://")) {
		return xerr.Param(field + "链接格式不正确")
	}
	return nil
}

// checkVersionFields 版本号/大小/渠道/下载链接四件套校验(发布与更新共用)。
func checkVersionFields(version, size, channel, downloadURL string) (string, string, string, error) {
	version = strings.TrimSpace(version)
	size = strings.TrimSpace(size)
	channel = strings.TrimSpace(channel)
	if !versionPattern.MatchString(version) {
		return "", "", "", xerr.Param("版本号格式不正确,如 2.3.1")
	}
	if size == "" || len(size) > 20 {
		return "", "", "", xerr.Param("软件大小不能为空且最多 20 字符")
	}
	if utf8.RuneCountInString(channel) > 30 {
		return "", "", "", xerr.Param("渠道最多 30 字")
	}
	if err := checkURL(downloadURL, "下载"); err != nil {
		return "", "", "", err
	}
	return version, size, channel, nil
}
