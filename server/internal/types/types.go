// Package types API 请求/响应 DTO(与持久化 struct 分离,禁止直接 bind 到 model)。
package types

type EmailCodeReq struct {
	Email string `json:"email"`
	Scene string `json:"scene,options=register|reset"` // 用途隔离,注册码不能用于改密
}

type RegisterReq struct {
	Email      string `json:"email"`
	Code       string `json:"code"`
	Password   string `json:"password"` // 8-32 位
	Nickname   string `json:"nickname,optional"`
	DeviceName string `json:"deviceName,optional"` // 设备名,如 "Xiaomi 14"
}

type LoginReq struct {
	Email      string `json:"email"`
	Password   string `json:"password"`
	DeviceName string `json:"deviceName,optional"`
}

type RefreshReq struct {
	RefreshToken string `json:"refreshToken"`
	DeviceID     string `json:"deviceId"`
}

type DeviceItem struct {
	DeviceID    string `json:"deviceId"`
	Name        string `json:"name"`
	IP          string `json:"ip"`
	LastLoginAt int64  `json:"lastLoginAt"`
	Current     bool   `json:"current"` // 是否当前请求所用设备
}

type KickDeviceReq struct {
	DeviceID string `path:"id"`
}

// ---- 用户设置(青少年模式/推送开关) ----

type UserSettingsResp struct {
	TeenMode     bool `json:"teenMode"`
	PushDM       bool `json:"pushDm"`       // 私信离线推送
	PushInteract bool `json:"pushInteract"` // 点赞/评论离线推送
	PushSystem   bool `json:"pushSystem"`   // 系统通知离线推送
}

type UpdateSettingsReq struct {
	TeenMode     *bool `json:"teenMode,optional"` // 缺省不变,下同
	PushDM       *bool `json:"pushDm,optional"`
	PushInteract *bool `json:"pushInteract,optional"`
	PushSystem   *bool `json:"pushSystem,optional"`
}

// ---- 大文件分片上传(APK) ----

type MultipartInitReq struct {
	Kind     string `json:"kind,options=apk"` // 当前仅 APK,视频二期扩展
	FileName string `json:"fileName"`
	Size     int64  `json:"size"`
}

type MultipartPartURL struct {
	PartNumber int    `json:"partNumber"`
	URL        string `json:"url"`
}

type MultipartInitResp struct {
	UploadID string             `json:"uploadId"`
	Key      string             `json:"key"`
	PartSize int64              `json:"partSize"`
	URLs     []MultipartPartURL `json:"urls"`
	ExpireAt int64              `json:"expireAt"` // 分片 URL 过期时间(毫秒),过期用 parts 接口补签
}

type MultipartPartETag struct {
	PartNumber int    `json:"partNumber"`
	ETag       string `json:"etag"`
}

type MultipartCompleteReq struct {
	UploadID string              `json:"uploadId"`
	Key      string              `json:"key"`
	Parts    []MultipartPartETag `json:"parts"`
}

type MultipartCompleteResp struct {
	FileURL string `json:"fileUrl"`
}

type MultipartAbortReq struct {
	UploadID string `json:"uploadId"`
	Key      string `json:"key"`
}

type MultipartPartsReq struct {
	UploadID string `form:"uploadId"`
	Key      string `form:"key"`
}

type MultipartPartsResp struct {
	Parts []MultipartPartETag `json:"parts"`
	URLs  []MultipartPartURL  `json:"urls"` // 未完成分片的新签 URL(续传直接用)
}

// ---- 离线推送 token 上报 ----

type PushTokenReq struct {
	DeviceID string `json:"deviceId"` // 登录响应下发的设备指纹
	Platform string `json:"platform,options=ios|android|harmony"`
	Channel  string `json:"channel,options=apns|huawei|xiaomi|oppo|vivo|mock"`
	Token    string `json:"token"`
}

// ---- 管家应答统计 ----

type BotStatsReq struct {
	Days int `form:"days,default=7,range=[1:30]"`
}

type BotStatDay struct {
	Date     string `json:"date"` // yyyy-mm-dd
	Faq      int64  `json:"faq"`
	LLM      int64  `json:"llm"`
	Fallback int64  `json:"fallback"`
}

type BotStatsResp struct {
	Days []BotStatDay `json:"days"`
}

// ---- 审核内容预览 ----

type AuditPreviewResp struct {
	Kind       string   `json:"kind"` // post / comment / software
	Title      string   `json:"title"`
	Content    string   `json:"content"`
	Logo       string   `json:"logo,omitempty"`
	Images     []string `json:"images"`
	AuthorID   int64    `json:"authorId"`
	AuthorName string   `json:"authorName"`
}

// ---- 软件库管理 ----

type AdminSoftwareListReq struct {
	Kw     string `form:"kw,optional"`
	Status int64  `form:"status,default=-1"` // -1全部 0待审 1上架 2驳回 3下架
	PageReq
}

type AdminSoftwareItem struct {
	ID            int64  `json:"id"`
	UserID        int64  `json:"userId"`
	Nickname      string `json:"nickname"`
	Name          string `json:"name"`
	Logo          string `json:"logo"`
	Type          int64  `json:"type"` // 1应用 2游戏
	CategoryName  string `json:"categoryName"`
	Status        int64  `json:"status"`
	DownloadCount int64  `json:"downloadCount"`
	CommentCount  int64  `json:"commentCount"`
	CreatedAt     int64  `json:"createdAt"`
}

type AdminSoftwareListResp struct {
	Total int64               `json:"total"`
	List  []AdminSoftwareItem `json:"list"`
}

type AdminSoftwareOpsReq struct {
	ID     int64  `path:"id"`
	Action int64  `json:"action,options=0|1"` // 1下架 0恢复上架
	Reason string `json:"reason,optional"`    // 下架必填,通知发布者
}

type AdminSoftwareVersionItem struct {
	ID        int64  `json:"id"`
	Version   string `json:"version"`
	Size      string `json:"size"`
	Channel   string `json:"channel"`
	Status    int64  `json:"status"`
	CreatedAt int64  `json:"createdAt"`
}

// ---- 用户设备管理(管理侧) ----

type AdminKickDeviceReq struct {
	UserID   int64  `path:"id"`
	DeviceID string `json:"deviceId"`
}

// ---- 运营参数(app_config) ----

type AppConfigListReq struct {
	Prefix string `form:"prefix,optional"` // 如 exp.
}

type AppConfigItem struct {
	K         string `json:"k"`
	V         string `json:"v"`
	Remark    string `json:"remark"`
	UpdatedAt int64  `json:"updatedAt"`
}

type AppConfigSaveReq struct {
	Items []struct {
		K string `json:"k"`
		V string `json:"v"`
	} `json:"items"`
}

// ---- 等级规则管理 ----

type LevelRuleItem struct {
	Level   int64 `json:"level"`
	NeedExp int64 `json:"needExp"`
}

type AdminLevelRulesSaveReq struct {
	Rules []LevelRuleItem `json:"rules"`
}

// ---- 推送渠道看板 ----

type PushStatsReq struct {
	Days int `form:"days,default=7,range=[1:30]"`
}

type PushChannelStat struct {
	Channel string `json:"channel"`
	OK      int64  `json:"ok"`
	Fail    int64  `json:"fail"`
	Days    []struct {
		Date string `json:"date"`
		OK   int64  `json:"ok"`
		Fail int64  `json:"fail"`
	} `json:"days"`
}

type PushStatsResp struct {
	Channels []PushChannelStat `json:"channels"`
}

// ---- 搜索联想 ----

type SuggestReq struct {
	Kw string `form:"kw"`
}

type SuggestItem struct {
	Type        string `json:"type"` // post / software / circle / topic
	ID          int64  `json:"id"`
	Text        string `json:"text"`
	Highlighted string `json:"highlighted"` // 带 <em></em> 命中标记(mysql 驱动同 text)
}

type SuggestResp struct {
	Suggestions []SuggestItem `json:"suggestions"`
}

// ---- 帖子分享口令 ----

type SharePostResp struct {
	Code string `json:"code"` // 口令,如 YR1A2B3C4D
	Text string `json:"text"` // 可直接复制的分享文案
}

type ShareResolveReq struct {
	Code string `path:"code"`
}

type ShareResolveResp struct {
	PostID   int64  `json:"postId"`
	Title    string `json:"title"`
	Summary  string `json:"summary"`
	Author   string `json:"author"`
	AuthorID int64  `json:"authorId"`
}

type ResetPasswordReq struct {
	Email    string `json:"email"`
	Code     string `json:"code"` // scene=reset 的邮箱验证码
	Password string `json:"password"`
}

type DeactivateReq struct {
	Password string `json:"password"` // 注销前密码确认
}

type TokenResp struct {
	UserID          int64  `json:"userId"`
	Token           string `json:"token"`
	ExpireAt        int64  `json:"expireAt"` // Unix 秒
	RefreshToken    string `json:"refreshToken"`
	RefreshExpireAt int64  `json:"refreshExpireAt"` // Unix 秒
	DeviceID        string `json:"deviceId"`        // 客户端持久化,刷新/设备管理用
	IsNewUser       bool   `json:"isNewUser"`
	DisplayNo       string `json:"displayNo"`
	Nickname        string `json:"nickname"`
	Avatar          string `json:"avatar"`
}

type UserInfoResp struct {
	UserID       int64  `json:"userId"`
	DisplayNo    string `json:"displayNo"`
	Nickname     string `json:"nickname"`
	Avatar       string `json:"avatar"`
	Cover        string `json:"cover"`
	Signature    string `json:"signature"`
	Level        int64  `json:"level"`
	Exp          int64  `json:"exp"`          // 当前累计经验
	NextLevelExp int64  `json:"nextLevelExp"` // 升下一级所需累计经验;0=已满级
}

// ---- 通用 ----

// IDPath REST 路径参数 /xxx/:id。
type IDPath struct {
	ID int64 `path:"id"`
}

type PageReq struct {
	Page int `form:"page,default=1"`
	Size int `form:"size,default=20"`
}

// Offset 返回分页偏移并把 Size 钳制到 [1,50]。
func (p *PageReq) Offset() (offset, limit int) {
	if p.Size < 1 || p.Size > 50 {
		p.Size = 20
	}
	if p.Page < 1 {
		p.Page = 1
	}
	return (p.Page - 1) * p.Size, p.Size
}

type UserBrief struct {
	UserID      int64  `json:"userId"`
	DisplayNo   string `json:"displayNo"`
	Nickname    string `json:"nickname"`
	Avatar      string `json:"avatar"`
	Level       int64  `json:"level"`
	AvatarFrame string `json:"avatarFrame,omitempty"` // 佩戴中的头像框素材 URL
}

// ---- 首页 ----

type BannerItem struct {
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Image     string `json:"image"`
	LinkType  int64  `json:"linkType"` // 0无跳转 1帖子 2H5 3圈子
	LinkValue string `json:"linkValue"`
}

type TopPostItem struct {
	PostID int64  `json:"postId"`
	Title  string `json:"title"`
}

type HomeConfigResp struct {
	Banners  []BannerItem  `json:"banners"`
	TopPosts []TopPostItem `json:"topPosts"`
}

// ---- 用户主页与关系 ----

type UserProfileResp struct {
	UserID    int64   `json:"userId"`
	DisplayNo string  `json:"displayNo"`
	Nickname  string  `json:"nickname"`
	Avatar    string  `json:"avatar"`
	Cover     string  `json:"cover"`
	Signature string  `json:"signature"`
	Level     int64   `json:"level"`
	Following int64   `json:"following"` // 关注数
	Fans      int64   `json:"fans"`      // 粉丝数
	Likes     int64   `json:"likes"`     // 获赞数
	Posts     int64   `json:"posts"`     // 帖子数
	IsSelf    bool    `json:"isSelf"`
	Followed  bool    `json:"followed"`        // 我是否已关注他
	Blocked   bool    `json:"blocked"`         // 我是否已拉黑他
	Certs     []int64 `json:"certs,omitempty"` // 已通过的认证:1达人 2开发者(头衔徽章)
}

type RelationUserItem struct {
	UserBrief
	Followed bool `json:"followed"` // 我是否已关注该用户
}

type AuthorPostsReq struct {
	UserID int64 `path:"id"`
	PageReq
}

// ---- 私信管理 ----

type RecallMessageReq struct {
	ConvID int64 `json:"convId"`
	MsgID  int64 `json:"msgId"`
}

// ---- 资料编辑(PATCH 三态:nil=不改,指针值=改成该值) ----

type UpdateProfileReq struct {
	Nickname  *string `json:"nickname,optional"`
	Avatar    *string `json:"avatar,optional"`
	Cover     *string `json:"cover,optional"`
	Signature *string `json:"signature,optional"` // 传空串=清空签名
	Gender    *int64  `json:"gender,optional"`    // 0未知 1男 2女
	Birthday  *string `json:"birthday,optional"`  // YYYY-MM-DD
}

// ---- 软件库 ----

type CreateSoftwareReq struct {
	Name        string   `json:"name"`
	Logo        string   `json:"logo"`
	Intro       string   `json:"intro"`
	Images      []string `json:"images"`           // 介绍图 3-6 张,强校验
	Type        int64    `json:"type,options=1|2"` // 1应用 2游戏
	CategoryID  int64    `json:"categoryId"`
	Tags        []string `json:"tags,optional"`    // APK 标签 ≤5 个
	Version     string   `json:"version"`          // 如 2.3.1
	Size        string   `json:"size"`             // 如 128MB
	Channel     string   `json:"channel,optional"` // 官方/第三方/自制
	DownloadURL string   `json:"downloadUrl"`
	ExtractCode string   `json:"extractCode,optional"` // 网盘提取码
	DraftID     int64    `json:"draftId,optional"`     // 由草稿发布时带上,发布成功自动删草稿
}

type CreateSoftwareResp struct {
	SoftwareID int64  `json:"softwareId"`
	VersionID  int64  `json:"versionId"`
	Status     int    `json:"status"` // 0待审核
	Tip        string `json:"tip"`
}

type CreateVersionReq struct {
	SoftwareID  int64  `path:"id"`
	Version     string `json:"version"`
	Size        string `json:"size"`
	Channel     string `json:"channel,optional"`
	DownloadURL string `json:"downloadUrl"`
	ExtractCode string `json:"extractCode,optional"`
}

type CreateVersionResp struct {
	VersionID int64  `json:"versionId"`
	Status    int    `json:"status"`
	Tip       string `json:"tip"`
}

type SoftwareListReq struct {
	Type       int64  `form:"type,optional"` // 0全部 1应用 2游戏
	CategoryID int64  `form:"categoryId,optional"`
	Sort       string `form:"sort,default=new,options=new|hot|download"`
	PageReq
}

type SoftwareItem struct {
	ID            int64    `json:"id"`
	Name          string   `json:"name"`
	Logo          string   `json:"logo"`
	Intro         string   `json:"intro"`
	Type          int64    `json:"type"`
	CategoryID    int64    `json:"categoryId"`
	Tags          []string `json:"tags"`
	Version       string   `json:"version,omitempty"` // 最新已发布版本号
	Size          string   `json:"size,omitempty"`
	DownloadCount int64    `json:"downloadCount"`
	CommentCount  int64    `json:"commentCount"`
	Status        int64    `json:"status"` // 0待审核 1已上架 2驳回 3下架(0 也要下发)
	CreatedAt     int64    `json:"createdAt"`
}

type VersionItem struct {
	ID          int64  `json:"id"`
	Version     string `json:"version"`
	Size        string `json:"size"`
	Channel     string `json:"channel"`
	DownloadURL string `json:"downloadUrl"`
	ExtractCode string `json:"extractCode,omitempty"`
	Status      int64  `json:"status"` // 0待审核 1已发布 2驳回(游客只会看到已发布)
	CreatedAt   int64  `json:"createdAt"`
}

type SoftwareDetailResp struct {
	SoftwareItem
	Images    []string      `json:"images"`
	Publisher UserBrief     `json:"publisher"`
	Versions  []VersionItem `json:"versions"`
}

type DownloadReq struct {
	SoftwareID int64 `path:"id"`
	VersionID  int64 `json:"versionId,optional"` // 0=最新已发布版本
}

type DownloadResp struct {
	VersionID   int64  `json:"versionId"`
	Version     string `json:"version"`
	DownloadURL string `json:"downloadUrl"`
	ExtractCode string `json:"extractCode,omitempty"`
}

type CategoryItem struct {
	ID   int64  `json:"id"`
	Type int64  `json:"type"`
	Name string `json:"name"`
}

type CategoryListReq struct {
	Type int64 `form:"type,optional"`
}

// ---- 搜索 ----

type SearchReq struct {
	Type string `form:"type,options=post|user|circle|software|topic"`
	Kw   string `form:"kw"`
	PageReq
}

type TopicItem struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	PostCount int64  `json:"postCount"`
}

// SearchResp 按 type 只填充对应一组结果。
type SearchResp struct {
	Type     string             `json:"type"`
	Posts    []PostItem         `json:"posts,omitempty"`
	Users    []RelationUserItem `json:"users,omitempty"`
	Circles  []CircleItem       `json:"circles,omitempty"`
	Software []SoftwareItem     `json:"software,omitempty"`
	Topics   []TopicItem        `json:"topics,omitempty"`
}

// ---- 任务中心与签到 ----

type TaskItem struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Type         int64  `json:"type"` // 1每日 2新手
	Action       string `json:"action"`
	Target       int64  `json:"target"`
	Progress     int64  `json:"progress"`
	RewardYouzhu int64  `json:"rewardYouzhu"`
	RewardExp    int64  `json:"rewardExp"`
	Status       int64  `json:"status"` // 0进行中 1可领取 2已领取
}

type TasksResp struct {
	SignedToday bool       `json:"signedToday"`
	Continuous  int64      `json:"continuous"` // 连续签到天数(未签今天则为截至昨天)
	NextReward  int64      `json:"nextReward"` // 下一次签到可得忧珠
	Tasks       []TaskItem `json:"tasks"`
}

type SignInResp struct {
	Reward     int64 `json:"reward"`
	Continuous int64 `json:"continuous"`
	Balance    int64 `json:"balance"`
}

type ClaimResp struct {
	Reward  int64 `json:"reward"`
	Balance int64 `json:"balance"`
}

// ---- 忧珠资产 ----

type YouzhuAccountResp struct {
	Balance     int64 `json:"balance"`
	SignedToday bool  `json:"signedToday"`
}

type YouzhuLogsReq struct {
	BizType int64 `form:"bizType,optional"` // 0全部 1任务 2签到 3运营 4兑换 5抽奖 6付费解锁
	PageReq
}

type YouzhuLogItem struct {
	ID           int64  `json:"id"`
	BizType      int64  `json:"bizType"`
	Amount       int64  `json:"amount"`
	BalanceAfter int64  `json:"balanceAfter"`
	Remark       string `json:"remark"`
	CreatedAt    int64  `json:"createdAt"`
}

// ---- 忧珠商城(装扮/靓号/抽奖/兑换记录) ----

type DecorationListReq struct {
	Kind int64 `form:"kind,optional"` // 0全部 1头像框
}

type DecorationItem struct {
	ID           int64  `json:"id"`
	Kind         int64  `json:"kind"`
	Name         string `json:"name"`
	Preview      string `json:"preview"`
	Price        int64  `json:"price"`
	DurationDays int64  `json:"durationDays"` // 0=永久
	Owned        bool   `json:"owned"`        // 登录态:是否已拥有(未过期)
}

type MyDecorationItem struct {
	DecorationID int64  `json:"decorationId"`
	Kind         int64  `json:"kind"`
	Name         string `json:"name"`
	Preview      string `json:"preview"`
	Worn         bool   `json:"worn"`
	ExpireAt     int64  `json:"expireAt"` // 0=永久,Unix 毫秒
	Expired      bool   `json:"expired"`
}

type PrettyNoItem struct {
	ID     int64  `json:"id"`
	No     string `json:"no"`
	Rarity int64  `json:"rarity"` // 1普通 2稀有 3传说
	Price  int64  `json:"price"`
}

type ExchangeNoResp struct {
	No      string `json:"no"`
	Balance int64  `json:"balance"`
}

type PrizeItem struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	Kind   int64  `json:"kind"` // 1忧珠 2装扮
	Amount int64  `json:"amount"`
	Weight int64  `json:"weight"` // 概率=weight/sum(weight),客户端公示
}

type LotteryPoolsResp struct {
	Cost   int64       `json:"cost"` // 单次抽奖消耗忧珠
	Prizes []PrizeItem `json:"prizes"`
}

type DrawResp struct {
	Prize   PrizeItem `json:"prize"`
	Balance int64     `json:"balance"`
}

type ExchangeRecordItem struct {
	ID        int64  `json:"id"`
	Kind      int64  `json:"kind"` // 1装扮 2靓号 3抽奖
	Name      string `json:"name"`
	Cost      int64  `json:"cost"`
	CreatedAt int64  `json:"createdAt"`
}

// ---- 举报 ----

type CreateReportReq struct {
	TargetType int      `json:"targetType,options=1|2|3|4|5"` // 1帖子 2评论 3用户 4私信 5软件
	TargetID   int64    `json:"targetId"`
	Category   int      `json:"category,options=1|2|3|4|5"` // 1违法 2色情 3诈骗 4侵权 5其他
	Reason     string   `json:"reason,optional"`            // 补充说明 ≤500
	Images     []string `json:"images,optional"`            // 证据图 ≤9
}

// ---- 管理后台 ----

type AdminLoginReq struct {
	Username    string `json:"username"`
	Password    string `json:"password"`
	CaptchaID   string `json:"captchaId"`
	CaptchaCode string `json:"captchaCode"`
}

type AdminLoginResp struct {
	Token        string   `json:"token"`
	ExpireAt     int64    `json:"expireAt"`
	Username     string   `json:"username"`
	Perms        []string `json:"perms"`
	TotpRequired bool     `json:"totpRequired,omitempty"` // true=还需二步验证,用 ticket 换 token
	Ticket       string   `json:"ticket,omitempty"`       // 二步验证临时票据(5 分钟)
}

type AdminTotpLoginReq struct {
	Ticket string `json:"ticket"`
	Code   string `json:"code"` // 6 位动态口令或恢复码
}

type TotpSetupResp struct {
	Secret        string   `json:"secret"`        // base32,手动录入用
	URI           string   `json:"uri"`           // otpauth://,验证器扫码导入
	RecoveryCodes []string `json:"recoveryCodes"` // 明文仅此一次,库中只存哈希
}

type TotpCodeReq struct {
	Code string `json:"code"`
}

type TotpStatusResp struct {
	Enabled           bool  `json:"enabled"`
	RecoveryCodesLeft int64 `json:"recoveryCodesLeft"`
}

type CaptchaResp struct {
	CaptchaID string `json:"captchaId"`
	Image     string `json:"image"` // data:image/svg+xml;base64,...
}

type AdminChangePwdReq struct {
	OldPassword string `json:"oldPassword"`
	NewPassword string `json:"newPassword"`
}

type AdminAccountItem struct {
	ID          int64  `json:"id"`
	Username    string `json:"username"`
	RoleID      int64  `json:"roleId"`
	RoleName    string `json:"roleName"`
	Status      int64  `json:"status"`      // 1正常 0停用
	LastLoginAt int64  `json:"lastLoginAt"` // 0=从未登录
}

type AdminCreateAccountReq struct {
	Username string `json:"username"`
	Password string `json:"password"`
	RoleID   int64  `json:"roleId"`
}

type AdminUpdateAccountReq struct {
	ID          int64  `path:"id"`
	RoleID      int64  `json:"roleId,optional"`                           // >0 调整角色
	Status      int64  `json:"status,optional,options=0|1|-1,default=-1"` // -1 不改
	NewPassword string `json:"newPassword,optional"`                      // 非空=重置密码并强制改密
	ResetTotp   bool   `json:"resetTotp,optional"`                        // true=强制解绑二步验证(丢失验证器场景)
}

type AdminRoleItem struct {
	ID    int64    `json:"id"`
	Name  string   `json:"name"`
	Perms []string `json:"perms"`
}

// ---- 敏感词库管理 ----

type AdminWordListReq struct {
	Keyword  string `form:"keyword,optional"`
	Category int64  `form:"category,optional"` // 0全部 1政治 2色情 3辱骂 4广告 5其他
	Level    int64  `form:"level,optional"`    // 0全部 1拦截 2人审 3打码
	Status   int64  `form:"status,default=-1"` // -1全部 1启用 0停用
	PageReq
}

type AdminWordItem struct {
	ID        int64  `json:"id"`
	Word      string `json:"word"`
	Category  int64  `json:"category"`
	Level     int64  `json:"level"`
	Status    int64  `json:"status"`
	CreatedAt int64  `json:"createdAt"`
}

type AdminWordListResp struct {
	Total int64           `json:"total"`
	List  []AdminWordItem `json:"list"`
}

type AdminWordSaveReq struct {
	ID       int64  `json:"id,optional"` // >0 更新(改分类/等级/启停),0 新建
	Word     string `json:"word,optional"`
	Category int64  `json:"category,options=1|2|3|4|5"`
	Level    int64  `json:"level,options=1|2|3"`
	Status   int64  `json:"status,optional,options=0|1,default=1"`
}

// ---- AI 管家 FAQ 管理 ----

type AdminFaqItem struct {
	ID        int64  `json:"id"`
	Keywords  string `json:"keywords"`
	Reply     string `json:"reply"`
	Priority  int64  `json:"priority"`
	Status    int64  `json:"status"`
	CreatedAt int64  `json:"createdAt"`
}

type AdminFaqListResp struct {
	Total int64          `json:"total"`
	List  []AdminFaqItem `json:"list"`
}

type AdminFaqSaveReq struct {
	ID       int64  `json:"id,optional"` // >0 更新
	Keywords string `json:"keywords"`    // 竖线分隔,命中任一即回复
	Reply    string `json:"reply"`
	Priority int64  `json:"priority,optional,default=100"`
	Status   int64  `json:"status,optional,options=0|1,default=1"`
}

// ---- 商城/任务运营配置 ----

type AdminDecoItem struct {
	ID           int64  `json:"id"`
	Kind         int64  `json:"kind"` // 1头像框
	Name         string `json:"name"`
	Preview      string `json:"preview"`
	Price        int64  `json:"price"`
	DurationDays int64  `json:"durationDays"` // 0=永久
	Sort         int64  `json:"sort"`
	Status       int64  `json:"status"` // 1上架 0下架
}

type AdminDecoSaveReq struct {
	ID           int64  `json:"id,optional"`
	Kind         int64  `json:"kind,options=1|2"`
	Name         string `json:"name"`
	Preview      string `json:"preview"`
	Price        int64  `json:"price"`
	DurationDays int64  `json:"durationDays,optional"`
	Sort         int64  `json:"sort,optional"`
	Status       int64  `json:"status,optional,options=0|1,default=1"`
}

type AdminPrizeItem struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	Kind   int64  `json:"kind"`   // 1忧珠 2装扮
	RefID  int64  `json:"refId"`  // kind=2 装扮ID
	Amount int64  `json:"amount"` // kind=1 忧珠数
	Weight int64  `json:"weight"`
	Stock  int64  `json:"stock"` // -1不限量
	Status int64  `json:"status"`
}

type AdminPrizeSaveReq struct {
	ID     int64  `json:"id,optional"`
	Name   string `json:"name"`
	Kind   int64  `json:"kind,options=1|2"`
	RefID  int64  `json:"refId,optional"`
	Amount int64  `json:"amount,optional"`
	Weight int64  `json:"weight"`
	Stock  int64  `json:"stock,optional,default=-1"`
	Status int64  `json:"status,optional,options=0|1,default=1"`
}

type AdminTaskCfgItem struct {
	ID           int64  `json:"id"`
	Name         string `json:"name"`
	Type         int64  `json:"type"` // 1每日 2新手
	Action       string `json:"action"`
	TargetCount  int64  `json:"targetCount"`
	RewardYouzhu int64  `json:"rewardYouzhu"`
	RewardExp    int64  `json:"rewardExp"`
	Sort         int64  `json:"sort"`
	Status       int64  `json:"status"`
}

type AdminTaskSaveReq struct {
	ID           int64  `json:"id,optional"`
	Name         string `json:"name"`
	Type         int64  `json:"type,options=1|2"`
	Action       string `json:"action,options=post|comment|like|browse"`
	TargetCount  int64  `json:"targetCount"`
	RewardYouzhu int64  `json:"rewardYouzhu,optional"`
	RewardExp    int64  `json:"rewardExp,optional"`
	Sort         int64  `json:"sort,optional"`
	Status       int64  `json:"status,optional,options=0|1,default=1"`
}

// ---- 对象存储直传 ----

type PresignReq struct {
	Kind     string `json:"kind,options=avatar|cover|post|software|banner|deco|circle|apk"` // 用途决定目录/大小/类型限制
	FileName string `json:"fileName"`
	Size     int64  `json:"size"` // 字节,用于服务端预校验
}

type PresignResp struct {
	UploadURL string `json:"uploadUrl"` // 客户端对此 URL 发 PUT(body=文件原文)
	FileURL   string `json:"fileUrl"`   // 上传成功后落库/展示的公开地址
	ExpireAt  int64  `json:"expireAt"`  // 签名过期时间(毫秒)
}

type TrendReq struct {
	Days int `form:"days,default=30"` // 7-90
}

type TrendResp struct {
	Dates        []string `json:"dates"`
	Users        []int64  `json:"users"`
	Posts        []int64  `json:"posts"`
	YouzhuIssued []int64  `json:"youzhuIssued"`
	YouzhuBurned []int64  `json:"youzhuBurned"`
}

type AdminCategoryItem struct {
	ID     int64  `json:"id"`
	Type   int64  `json:"type"` // 1应用 2游戏
	Name   string `json:"name"`
	Sort   int64  `json:"sort"`
	Status int64  `json:"status"`
}

type AdminCategorySaveReq struct {
	ID     int64  `json:"id,optional"`
	Type   int64  `json:"type,options=1|2"`
	Name   string `json:"name"`
	Sort   int64  `json:"sort,optional"`
	Status int64  `json:"status,optional,options=0|1,default=1"`
}

// ---- 后台圈子管理 ----

type AdminCircleListReq struct {
	Keyword string `form:"keyword,optional"`
	PageReq
}

type AdminCircleItem struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	Icon        string `json:"icon"`
	Cover       string `json:"cover"`
	Intro       string `json:"intro"`
	Description string `json:"description"`
	MemberCount int64  `json:"memberCount"`
	PostCount   int64  `json:"postCount"`
	IsOfficial  int64  `json:"isOfficial"`
	Pinned      int64  `json:"pinned"`
	Sort        int64  `json:"sort"`
	Status      int64  `json:"status"` // 1正常 2隐藏 3解散
}

type AdminCircleListResp struct {
	Total int64             `json:"total"`
	List  []AdminCircleItem `json:"list"`
}

type AdminCircleSaveReq struct {
	ID          int64  `json:"id,optional"`
	Name        string `json:"name"`
	Icon        string `json:"icon"`
	Cover       string `json:"cover,optional"`
	Intro       string `json:"intro,optional"`
	Description string `json:"description,optional"`
	IsOfficial  int64  `json:"isOfficial,optional,options=0|1"`
	Pinned      int64  `json:"pinned,optional,options=0|1"`
	Sort        int64  `json:"sort,optional"`
	Status      int64  `json:"status,optional,options=1|2|3,default=1"`
}

// ---- 帖子运营置顶/加精 ----

type AdminPostOpsReq struct {
	PostID     int64 `path:"id"`
	IsTop      int64 `json:"isTop,optional,options=0|1|-1,default=-1"`      // 首页置顶精选,-1 不变
	IsEssence  int64 `json:"isEssence,optional,options=0|1|-1,default=-1"`  // 加精,-1 不变
	IsRedTitle int64 `json:"isRedTitle,optional,options=0|1|-1,default=-1"` // 红色标题(运营帖),-1 不变
	IsSink     int64 `json:"isSink,optional,options=0|1|-1,default=-1"`     // 下沉(热度强制 0),-1 不变
}

// ---- 话题管理 ----

type AdminTopicListReq struct {
	Keyword string `form:"keyword,optional"`
	Status  int64  `form:"status,optional,options=0|1|2"` // 0全部 1正常 2封禁
	PageReq
}

type AdminTopicItem struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	PostCount int64  `json:"postCount"`
	HotScore  int64  `json:"hotScore"`
	Status    int64  `json:"status"`
	CreatedAt int64  `json:"createdAt"`
}

type AdminTopicListResp struct {
	Total int64            `json:"total"`
	List  []AdminTopicItem `json:"list"`
}

type AdminTopicUpdateReq struct {
	TopicID  int64 `path:"id"`
	Status   int64 `json:"status,optional,options=0|1|2"` // 0 不变
	HotScore int64 `json:"hotScore,optional,default=-1"`  // <0 不变
}

// ---- 忧珠运营 ----

type AdminYouzhuGrantReq struct {
	UserID int64  `json:"userId"`
	Amount int64  `json:"amount"` // 正=发放 负=回收
	Reason string `json:"reason"` // 必填:流水备注 + 用户通知
}

type AdminYouzhuLogListReq struct {
	UserID  int64 `form:"userId,optional"`
	BizType int64 `form:"bizType,optional"` // 0全部 1任务 2签到 3运营 4兑换 5抽奖 6解锁
	PageReq
}

type AdminYouzhuLogItem struct {
	ID           int64  `json:"id"`
	UserID       int64  `json:"userId"`
	Nickname     string `json:"nickname"`
	BizType      int64  `json:"bizType"`
	BizKey       string `json:"bizKey"`
	Amount       int64  `json:"amount"`
	BalanceAfter int64  `json:"balanceAfter"`
	Remark       string `json:"remark"`
	CreatedAt    int64  `json:"createdAt"`
}

type AdminYouzhuLogListResp struct {
	Total int64                `json:"total"`
	List  []AdminYouzhuLogItem `json:"list"`
}

// ---- 靓号库管理 ----

type AdminPrettyNoListReq struct {
	Keyword string `form:"keyword,optional"`  // 号码模糊
	Status  int64  `form:"status,default=-1"` // -1全部 0下架 1在售 2已售
	PageReq
}

type AdminPrettyNoItem struct {
	ID     int64  `json:"id"`
	No     string `json:"no"`
	Rarity int64  `json:"rarity"` // 1普通 2稀有 3传说
	Price  int64  `json:"price"`
	Status int64  `json:"status"`
	SoldTo int64  `json:"soldTo"`
	SoldAt int64  `json:"soldAt"` // 0=未售
}

type AdminPrettyNoListResp struct {
	Total int64               `json:"total"`
	List  []AdminPrettyNoItem `json:"list"`
}

type AdminPrettyNoSaveReq struct {
	ID     int64  `json:"id,optional"`
	No     string `json:"no"`
	Rarity int64  `json:"rarity,options=1|2|3"`
	Price  int64  `json:"price"`
	Status int64  `json:"status,optional,options=0|1,default=1"` // 已售(2)不可经此修改
}

// ---- 协议静态页 ----

type AgreementPathReq struct {
	Kind string `path:"kind"` // user | privacy
}

type AgreementResp struct {
	Kind      string `json:"kind"`
	Title     string `json:"title"`
	Content   string `json:"content"`
	UpdatedAt int64  `json:"updatedAt"`
}

type AdminAgreementSaveReq struct {
	Kind    string `path:"kind"`
	Title   string `json:"title"`
	Content string `json:"content"`
}

// ---- 用户等级/头衔后台调整 ----

type AdminUserLevelReq struct {
	UserID int64 `path:"id"`
	Level  int64 `json:"level,optional,default=-1"` // <0 不变
	Exp    int64 `json:"exp,optional,default=-1"`   // <0 不变
}

type AdminUserTitleReq struct {
	UserID int64 `path:"id"`
	Kind   int64 `json:"kind,options=1|2"` // 1达人 2开发者
	Grant  bool  `json:"grant"`            // true 授予 false 撤销
}

type AuditListReq struct {
	BizType int64 `form:"bizType,optional"` // 0全部 1帖子 2评论 3软件
	PageReq
}

type AuditQueueItem struct {
	ID            int64  `json:"id"`
	BizType       int64  `json:"bizType"`
	BizID         int64  `json:"bizId"`
	MachineResult int64  `json:"machineResult"`
	MachineDetail string `json:"machineDetail"`
	CreatedAt     int64  `json:"createdAt"`
}

type AuditDecideReq struct {
	AuditID int64  `path:"id"`
	Approve bool   `json:"approve"`
	Reason  string `json:"reason,optional"` // 驳回必填
}

type AdminCertItem struct {
	ID        int64  `json:"id"`
	UserID    int64  `json:"userId"`
	Kind      int64  `json:"kind"`
	Material  string `json:"material"`
	CreatedAt int64  `json:"createdAt"`
}

type CertDecideReq struct {
	CertID  int64  `path:"id"`
	Approve bool   `json:"approve"`
	Reason  string `json:"reason,optional"`
}

type AppointReq struct {
	CircleID int64 `path:"id"`
	UserID   int64 `json:"userId"`
	Role     int64 `json:"role,options=0|1|2"` // 0成员 1管理员 2圈主
}

type OpLogItem struct {
	ID        int64  `json:"id"`
	AdminID   int64  `json:"adminId"`
	Action    string `json:"action"`
	Target    string `json:"target"`
	IP        string `json:"ip"`
	CreatedAt int64  `json:"createdAt"`
}

type AdminNoticeReq struct {
	Title   string `json:"title"`
	Content string `json:"content"`
}

type UserBanReq struct {
	UserID int64 `path:"id"`
	Action int64 `json:"action,options=0|2|3"` // 0恢复 2禁言 3封禁
	Days   int   `json:"days,optional"`        // 处置时长,0=永久
}

type AdminUserListReq struct {
	Keyword string `form:"keyword,optional"`                  // 昵称/展示编号/邮箱模糊
	Status  int64  `form:"status,optional,options=0|1|2|3|4"` // 0全部 1正常 2禁言 3封禁 4已注销
	PageReq
}

type AdminUserItem struct {
	UserID      int64  `json:"userId"`
	DisplayNo   string `json:"displayNo"`
	Nickname    string `json:"nickname"`
	Avatar      string `json:"avatar"`
	Email       string `json:"email"`
	Level       int64  `json:"level"`
	Status      int64  `json:"status"`
	CreatedAt   int64  `json:"createdAt"`
	LastLoginAt int64  `json:"lastLoginAt"` // 0=从未登录
}

type AdminUserListResp struct {
	Total int64           `json:"total"`
	List  []AdminUserItem `json:"list"`
}

type AdminContentListReq struct {
	Type    int64  `form:"type,options=1|2"`  // 1帖子 2评论
	Keyword string `form:"keyword,optional"`  // 帖子搜标题/正文,评论搜内容
	Status  int64  `form:"status,default=-1"` // -1全部;帖:0待审1发布2驳回3下架4已删;评:0待审1正常2屏蔽
	PageReq
}

type AdminContentItem struct {
	ID         int64  `json:"id"`
	AuthorID   int64  `json:"authorId"`
	AuthorName string `json:"authorName"`
	Title      string `json:"title"`   // 评论恒空
	Content    string `json:"content"` // 已截断摘要
	Status     int64  `json:"status"`
	CircleID   int64  `json:"circleId,omitempty"` // 帖子专属
	BizType    int64  `json:"bizType,omitempty"`  // 评论专属:1帖子 2软件
	BizID      int64  `json:"bizId,omitempty"`    // 评论专属
	IsTop      int64  `json:"isTop"`              // 帖子:首页置顶精选
	IsEssence  int64  `json:"isEssence"`          // 帖子:加精
	IsRedTitle int64  `json:"isRedTitle"`         // 帖子:红色标题
	IsSink     int64  `json:"isSink"`             // 帖子:下沉
	FirstImage string `json:"firstImage"`         // 帖子首图(评论恒空)
	LikeCount  int64  `json:"likeCount"`
	ViewCount  int64  `json:"viewCount"` // 评论恒 0
	CreatedAt  int64  `json:"createdAt"`
}

type AdminContentListResp struct {
	Total int64              `json:"total"`
	List  []AdminContentItem `json:"list"`
}

type AdminTakedownReq struct {
	Type   int64  `json:"type,options=1|2"` // 1帖子 2评论
	ID     int64  `json:"id"`
	Action int64  `json:"action,options=0|1"` // 1下架 0恢复
	Reason string `json:"reason,optional"`    // 下架必填,通知作者
}

type AdminReportListReq struct {
	Status     int64 `form:"status,default=0"`    // 0待处理 1已处理 2已驳回 -1全部
	TargetType int64 `form:"targetType,optional"` // 0全部 1帖 2评 3用户 4私信 5软件
	PageReq
}

type AdminReportItem struct {
	ID           int64    `json:"id"`
	ReporterID   int64    `json:"reporterId"`
	ReporterName string   `json:"reporterName"`
	TargetType   int64    `json:"targetType"`
	TargetID     int64    `json:"targetId"`
	TargetBrief  string   `json:"targetBrief"`  // 目标摘要(标题/内容/昵称)
	TargetStatus int64    `json:"targetStatus"` // 目标当前状态(语义随类型)
	Category     int64    `json:"category"`     // 1违法 2色情 3诈骗 4侵权 5其他
	Reason       string   `json:"reason"`
	Images       []string `json:"images"`
	Status       int64    `json:"status"`
	HandledBy    int64    `json:"handledBy"`
	HandledAt    int64    `json:"handledAt"`
	CreatedAt    int64    `json:"createdAt"`
}

type AdminReportListResp struct {
	Total int64             `json:"total"`
	List  []AdminReportItem `json:"list"`
}

type AdminReportHandleReq struct {
	ReportID int64 `path:"id"`
	Action   int64 `json:"action,options=1|2"` // 1违规成立(已处理) 2不成立(驳回)
}

type AdminBannerReq struct {
	ID        int64  `json:"id,optional"` // >0 更新
	Title     string `json:"title"`
	Image     string `json:"image"`
	LinkType  int64  `json:"linkType,options=0|1|2|3"`
	LinkValue string `json:"linkValue,optional"`
	Sort      int64  `json:"sort,optional"`
	Status    int64  `json:"status,options=0|1"`
	StartAt   int64  `json:"startAt,optional"` // Unix 毫秒,0=立即
	EndAt     int64  `json:"endAt,optional"`   // Unix 毫秒,0=不限
}

type AdminBannerItem struct {
	ID        int64  `json:"id"`
	Title     string `json:"title"`
	Image     string `json:"image"`
	LinkType  int64  `json:"linkType"`
	LinkValue string `json:"linkValue"`
	Sort      int64  `json:"sort"`
	Status    int64  `json:"status"`
	StartAt   int64  `json:"startAt"`
	EndAt     int64  `json:"endAt"`
}

type DashboardResp struct {
	Users         int64 `json:"users"`
	TodayUsers    int64 `json:"todayUsers"`
	TodayActive   int64 `json:"todayActive"`
	Posts         int64 `json:"posts"`
	TodayPosts    int64 `json:"todayPosts"`
	Software      int64 `json:"software"`
	PendingAudits int64 `json:"pendingAudits"`
	YouzhuIssued  int64 `json:"youzhuIssued"`
	YouzhuBurned  int64 `json:"youzhuBurned"`
}

// ---- 权益认证 ----

type CertifyReq struct {
	Kind     int64  `json:"kind,options=1|2"` // 1达人 2开发者
	Material string `json:"material"`         // 佐证材料说明/作品链接
}

type CertItem struct {
	Kind      int64  `json:"kind"`
	Status    int64  `json:"status"` // 0待审 1通过 2驳回
	Reason    string `json:"reason,omitempty"`
	UpdatedAt int64  `json:"updatedAt"`
}

// ---- 圈子管理(圈主/管理员) ----

type CircleAdminPostReq struct {
	CircleID int64 `path:"id"`
	PostID   int64 `json:"postId"`
	On       bool  `json:"on,optional"` // 置顶/加精开关,下架忽略
}

type CircleMuteReq struct {
	CircleID int64 `path:"id"`
	UserID   int64 `json:"userId"`
	Days     int   `json:"days"` // 0=解除禁言
}

// ---- 圈子 ----

type CircleListReq struct {
	Sort string `form:"sort,default=hot,options=hot|new"`
	PageReq
}

type CircleItem struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	Icon        string `json:"icon"`
	Intro       string `json:"intro"`
	MemberCount int64  `json:"memberCount"`
	PostCount   int64  `json:"postCount"`
	IsOfficial  bool   `json:"isOfficial"`
	Pinned      bool   `json:"pinned"`
	Joined      bool   `json:"joined"`
}

type CircleDetailResp struct {
	CircleItem
	Cover       string `json:"cover"`
	Description string `json:"description"`
}

// ---- 帖子 ----

type CreatePostReq struct {
	CircleID    int64      `json:"circleId"`
	Title       string     `json:"title,optional"`
	Content     string     `json:"content"` // 付费帖时为免费摘要段
	Images      []ImageReq `json:"images,optional"`
	LinkType    int        `json:"linkType,optional,options=0|1|2"` // 0无 1外链 2抖音
	LinkURL     string     `json:"linkUrl,optional"`
	PaidPrice   int64      `json:"paidPrice,optional"`   // >0 开启忧珠付费解锁
	PaidContent string     `json:"paidContent,optional"` // 付费全文段,PaidPrice>0 时必填
	Topics      []string   `json:"topics,optional"`      // 话题名 ≤5,自动创建
	Mentions    []int64    `json:"mentions,optional"`    // @的用户 ≤10(客户端好友选择器结构化上报)
	Cocreators  []int64    `json:"cocreators,optional"`  // 共创者 ≤3,需互关,对方确认后生效
	DraftID     int64      `json:"draftId,optional"`     // 由草稿发布时带上,发布成功自动删草稿
}

type EditPostReq struct {
	PostID   int64      `path:"id"`
	Title    string     `json:"title,optional"`
	Content  string     `json:"content"`
	Images   []ImageReq `json:"images,optional"`
	LinkType int        `json:"linkType,optional,options=0|1|2"`
	LinkURL  string     `json:"linkUrl,optional"`
	Topics   []string   `json:"topics,optional"`
	// 付费段不可编辑(已售出内容变更有纠纷风险);共创/@ 不在编辑范围
}

type EditPostResp struct {
	Status int    `json:"status"` // 编辑后状态:0重回待审 1仍已发布
	Tip    string `json:"tip"`
}

// ---- 草稿箱 ----

type SaveDraftReq struct {
	ID      int64  `json:"id,optional"`      // >0 覆盖保存
	Kind    int64  `json:"kind,options=1|2"` // 1动态 2软件
	Payload string `json:"payload"`          // 发布器表单快照 JSON,服务端只存不校验
}

type SaveDraftResp struct {
	ID int64 `json:"id"`
}

type DraftListReq struct {
	Kind int64 `form:"kind,optional"`
	PageReq
}

type DraftItem struct {
	ID        int64  `json:"id"`
	Kind      int64  `json:"kind"`
	Payload   string `json:"payload"`
	UpdatedAt int64  `json:"updatedAt"`
}

type ImageReq struct {
	URL    string `json:"url"`
	Width  int64  `json:"width,optional"`
	Height int64  `json:"height,optional"`
}

type CreatePostResp struct {
	PostID int64  `json:"postId"`
	Status int    `json:"status"` // 0待审核 1已发布
	Tip    string `json:"tip"`
}

type PostItem struct {
	ID            int64       `json:"id"`
	Author        UserBrief   `json:"author"`
	CircleID      int64       `json:"circleId"`
	CircleName    string      `json:"circleName,omitempty"`
	Title         string      `json:"title"`
	Content       string      `json:"content"`
	Images        []ImageReq  `json:"images"`
	LinkType      int64       `json:"linkType"`
	LinkURL       string      `json:"linkUrl,omitempty"`
	IsTop         bool        `json:"isTop"`
	IsEssence     bool        `json:"isEssence"`
	IsRedTitle    bool        `json:"isRedTitle"` // 运营帖红色标题(客户端标题高亮渲染)
	ViewCount     int64       `json:"viewCount"`
	LikeCount     int64       `json:"likeCount"`
	CommentCount  int64       `json:"commentCount"`
	FavoriteCount int64       `json:"favoriteCount"`
	Liked         bool        `json:"liked"`
	Favorited     bool        `json:"favorited"`
	Status        int64       `json:"status"`                // 0待审核 1已发布 2驳回(0 也要下发,不能 omitempty)
	PaidPrice     int64       `json:"paidPrice,omitempty"`   // >0 为付费帖
	Unlocked      bool        `json:"unlocked,omitempty"`    // 我是否可看付费段(作者恒 true)
	PaidContent   string      `json:"paidContent,omitempty"` // 付费全文,仅详情且可看时下发
	Topics        []TopicItem `json:"topics,omitempty"`      // 关联话题
	Cocreators    []UserBrief `json:"cocreators,omitempty"`  // 已确认共创者(仅详情下发)
	CreatedAt     int64       `json:"createdAt"`             // Unix 毫秒
}

type FeedReq struct {
	PageReq
}

type UnlockResp struct {
	PaidContent string `json:"paidContent"`
	Balance     int64  `json:"balance"`
}

// ---- 话题聚合页 ----

type TopicPostsReq struct {
	TopicID int64  `path:"id"`
	Sort    string `form:"sort,default=hot,options=hot|new"`
	PageReq
}

type TopicPostsResp struct {
	Topic TopicItem  `json:"topic"`
	Posts []PostItem `json:"posts"`
}

// ---- 共创确认 ----

type CocreateConfirmReq struct {
	PostID int64 `path:"id"`
	Accept bool  `json:"accept"`
}

type CirclePostsReq struct {
	CircleID int64  `path:"id"`
	Sort     string `form:"sort,default=new,options=new|hot"`
	PageReq
}

// ---- 评论 ----

type CreateCommentReq struct {
	PostID   int64   `json:"postId,optional"`                // 兼容字段,等价 bizType=1&bizId=postId
	BizType  int64   `json:"bizType,optional,options=0|1|2"` // 0/1帖子 2软件
	BizID    int64   `json:"bizId,optional"`
	ParentID int64   `json:"parentId,optional"` // 0=评论对象本身,>0=回复某条评论
	Content  string  `json:"content"`
	Mentions []int64 `json:"mentions,optional"` // @的用户 ≤10
}

type CreateCommentResp struct {
	CommentID int64  `json:"commentId"`
	Status    int    `json:"status"` // 0待审核 1已发布
	Tip       string `json:"tip"`
}

type CommentItem struct {
	ID         int64     `json:"id"`
	Author     UserBrief `json:"author"`
	ReplyTo    string    `json:"replyTo,omitempty"` // 被回复者昵称
	Content    string    `json:"content"`
	LikeCount  int64     `json:"likeCount"`
	ReplyCount int64     `json:"replyCount"`
	Liked      bool      `json:"liked"`
	CreatedAt  int64     `json:"createdAt"`
}

type CommentListReq struct {
	PostID  int64 `form:"postId,optional"` // 兼容字段,等价 bizType=1&bizId=postId
	BizType int64 `form:"bizType,optional"`
	BizID   int64 `form:"bizId,optional"`
	RootID  int64 `form:"rootId,optional"` // >0 拉某楼回复
	PageReq
}

// ---- 私信 ----

type SendMessageReq struct {
	TargetUID int64  `json:"targetUid"`
	MsgType   int64  `json:"msgType,default=1,options=1|2|3|4"` // 1文本 2图片 3表情 4分享卡片
	Content   string `json:"content"`                           // 文本或 JSON(图片/卡片)
}

type MessageItem struct {
	ID        int64  `json:"id"`
	ConvID    int64  `json:"convId"`
	Seq       int64  `json:"seq"`
	SenderID  int64  `json:"senderId"`
	MsgType   int64  `json:"msgType"`
	Content   string `json:"content"`
	Status    int64  `json:"status"`
	CreatedAt int64  `json:"createdAt"`
}

type ConversationItem struct {
	ConvID      int64     `json:"convId"`
	Peer        UserBrief `json:"peer"`
	IsBot       bool      `json:"isBot"` // AI 管家会话(客户端置顶+官方机器人标签)
	LastPreview string    `json:"lastPreview"`
	LastMsgAt   int64     `json:"lastMsgAt"`
	Unread      int64     `json:"unread"`
}

type MessageListReq struct {
	ConvID    int64 `form:"convId"`
	BeforeSeq int64 `form:"beforeSeq,optional"` // 0=最新
	Size      int   `form:"size,default=20"`
}

type MarkReadReq struct {
	ConvID int64 `json:"convId"`
	Seq    int64 `json:"seq"`
}

// ---- 通知 ----

type NotifyListReq struct {
	Type int `form:"type,options=1|2|3"` // 1赞与收藏 2评论和@ 3系统
	PageReq
}

type NotifyItem struct {
	ID         int64     `json:"id"`
	Type       int64     `json:"type"`
	Actor      UserBrief `json:"actor"`
	TargetType int64     `json:"targetType"`
	TargetID   int64     `json:"targetId"`
	Content    string    `json:"content"`
	IsRead     bool      `json:"isRead"`
	CreatedAt  int64     `json:"createdAt"`
}

type NotifyReadReq struct {
	Type int `json:"type,options=1|2|3"`
}

type UnreadResp struct {
	IM      int64 `json:"im"` // 私信未读总数
	Like    int64 `json:"like"`
	Comment int64 `json:"comment"`
	System  int64 `json:"system"`
	Total   int64 `json:"total"`
}
