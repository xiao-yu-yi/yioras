-- ============================================================
-- Yiora M2 (MVP) 建表 SQL
-- 依据: docs/Yiora开发需求文档.md v1.1 · M2 范围
--   邮箱账号体系 / 首页推荐流 / 圈子 / 发动态 / 帖子互动 /
--   消息(私信+通知) / 个人中心 / 基础审核后台
-- 环境: MySQL 8.0+, InnoDB, utf8mb4
-- 约定:
--   * 主键 BIGINT UNSIGNED 自增；时间 DATETIME(3)
--   * 点赞/评论/浏览等计数列由 Redis 聚合后回写，DB 值允许短暂滞后
--   * 邮箱验证码只存 Redis(带 TTL)，不建表
--   * M3/M4 表(软件库/忧珠/装扮/靓号/抽奖)在后续迁移文件中新增
--   * 忧珠付费解锁(post_paid_content/post_unlock_record)属 M4，本文件不建
-- ============================================================

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS yiora DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE yiora;

-- ------------------------------------------------------------
-- 用户域
-- ------------------------------------------------------------

-- 用户主表（资料字段并入本表：M2 无独立 user_profile 的查询路径，避免 1:1 拆表 JOIN）
CREATE TABLE `user` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '用户ID(UID)',
  `display_no`  VARCHAR(20)     NULL COMMENT '展示编号,默认 N+id,靓号功能(M4)可更换;NULL 允许多行,注册事务内回填',
  `nickname`    VARCHAR(30)     NOT NULL COMMENT '昵称',
  `avatar`      VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '头像URL',
  `cover`       VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '主页封面URL',
  `signature`   VARCHAR(100)    NOT NULL DEFAULT '' COMMENT '个性签名',
  `gender`      TINYINT         NOT NULL DEFAULT 0 COMMENT '0未知 1男 2女',
  `birthday`    DATE            NULL COMMENT '生日',
  `level`       INT             NOT NULL DEFAULT 0 COMMENT '等级 Lv.0起',
  `exp`         BIGINT          NOT NULL DEFAULT 0 COMMENT '经验值',
  `status`      TINYINT         NOT NULL DEFAULT 1 COMMENT '1正常 2禁言 3封禁 4已注销',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_display_no` (`display_no`)
) ENGINE=InnoDB COMMENT='用户';

-- 登录凭证（v1.1 仅邮箱一种方式；如未来扩展登录方式,加 identity_type 列做迁移）
CREATE TABLE `user_auth` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`       BIGINT UNSIGNED NOT NULL COMMENT '用户ID',
  `email`         VARCHAR(254)    NOT NULL COMMENT '登录邮箱(全小写存储)',
  `password_hash` VARCHAR(100)    NOT NULL COMMENT 'bcrypt 哈希',
  `last_login_at` DATETIME(3)     NULL COMMENT '最近登录时间',
  `last_login_ip` VARCHAR(45)     NOT NULL DEFAULT '' COMMENT '最近登录IP',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_email` (`email`),
  UNIQUE KEY `uk_user` (`user_id`)
) ENGINE=InnoDB COMMENT='登录凭证(邮箱)';

-- 关注关系
CREATE TABLE `follow` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '关注者',
  `target_uid` BIGINT UNSIGNED NOT NULL COMMENT '被关注者',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pair` (`user_id`, `target_uid`),
  KEY `idx_fans` (`target_uid`, `id`)
) ENGINE=InnoDB COMMENT='关注关系';

-- 拉黑
CREATE TABLE `black_list` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '操作者',
  `target_uid` BIGINT UNSIGNED NOT NULL COMMENT '被拉黑者',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pair` (`user_id`, `target_uid`)
) ENGINE=InnoDB COMMENT='黑名单';

-- ------------------------------------------------------------
-- 内容域：圈子 / 帖子 / 话题 / 互动
-- ------------------------------------------------------------

CREATE TABLE `circle` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`         VARCHAR(30)     NOT NULL COMMENT '圈子名',
  `icon`         VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '图标URL',
  `cover`        VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '详情页封面URL',
  `intro`        VARCHAR(100)    NOT NULL DEFAULT '' COMMENT '一句话简介',
  `description`  VARCHAR(1000)   NOT NULL DEFAULT '' COMMENT '详细介绍',
  `member_count` INT             NOT NULL DEFAULT 0 COMMENT '成员数(冗余,Redis回写)',
  `post_count`   INT             NOT NULL DEFAULT 0 COMMENT '帖子数(冗余,Redis回写)',
  `hot_score`    BIGINT          NOT NULL DEFAULT 0 COMMENT '热度分(离线计算)',
  `is_official`  TINYINT         NOT NULL DEFAULT 0 COMMENT '1官方圈(公告/举报等)',
  `pinned`       TINYINT         NOT NULL DEFAULT 0 COMMENT '1发现页置顶',
  `sort`         INT             NOT NULL DEFAULT 0 COMMENT '运营排序,小在前',
  `status`       TINYINT         NOT NULL DEFAULT 1 COMMENT '1正常 2隐藏 3解散',
  `created_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_name` (`name`),
  KEY `idx_hot` (`status`, `hot_score` DESC),
  KEY `idx_new` (`status`, `id` DESC)
) ENGINE=InnoDB COMMENT='圈子';

CREATE TABLE `circle_member` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `circle_id`   BIGINT UNSIGNED NOT NULL,
  `user_id`     BIGINT UNSIGNED NOT NULL,
  `role`        TINYINT         NOT NULL DEFAULT 0 COMMENT '0成员 1管理员 2圈主',
  `muted_until` DATETIME(3)     NULL COMMENT '圈内禁言截止,NULL未禁言',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_member` (`circle_id`, `user_id`),
  KEY `idx_user` (`user_id`, `id`)
) ENGINE=InnoDB COMMENT='圈子成员';

CREATE TABLE `post` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`        BIGINT UNSIGNED NOT NULL COMMENT '作者',
  `circle_id`      BIGINT UNSIGNED NOT NULL COMMENT '所属圈子(发帖必选)',
  `title`          VARCHAR(30)     NOT NULL DEFAULT '' COMMENT '标题,<=30字',
  `content`        TEXT            NOT NULL COMMENT '正文(含@与话题标记)',
  `link_type`      TINYINT         NOT NULL DEFAULT 0 COMMENT '附加卡片 0无 1外链 2抖音',
  `link_url`       VARCHAR(500)    NOT NULL DEFAULT '' COMMENT '附加卡片链接',
  `visibility`     TINYINT         NOT NULL DEFAULT 0 COMMENT '0公开 1仅粉丝 2仅自己',
  `status`         TINYINT         NOT NULL DEFAULT 0 COMMENT '0待审核 1已发布 2已驳回 3已下架 4已删除',
  `reject_reason`  VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '驳回原因',
  `is_top`         TINYINT         NOT NULL DEFAULT 0 COMMENT '1首页置顶精选',
  `is_essence`     TINYINT         NOT NULL DEFAULT 0 COMMENT '1圈内加精',
  `view_count`     BIGINT          NOT NULL DEFAULT 0 COMMENT '浏览量(24h去重,Redis回写)',
  `like_count`     BIGINT          NOT NULL DEFAULT 0,
  `comment_count`  BIGINT          NOT NULL DEFAULT 0,
  `favorite_count` BIGINT          NOT NULL DEFAULT 0,
  `hot_score`      BIGINT          NOT NULL DEFAULT 0 COMMENT '推荐热度分(离线计算)',
  `created_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_feed_hot` (`status`, `hot_score` DESC) COMMENT '推荐流',
  KEY `idx_feed_new` (`status`, `id` DESC) COMMENT '最新流/审核队列',
  KEY `idx_circle` (`circle_id`, `status`, `id` DESC) COMMENT '圈内流',
  KEY `idx_author` (`user_id`, `status`, `id` DESC) COMMENT '个人主页作品'
) ENGINE=InnoDB COMMENT='帖子';

CREATE TABLE `post_image` (
  `id`      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id` BIGINT UNSIGNED NOT NULL,
  `url`     VARCHAR(255)    NOT NULL COMMENT '图片URL',
  `width`   INT             NOT NULL DEFAULT 0,
  `height`  INT             NOT NULL DEFAULT 0,
  `sort`    TINYINT         NOT NULL DEFAULT 0 COMMENT '顺序 0-8',
  PRIMARY KEY (`id`),
  KEY `idx_post` (`post_id`, `sort`)
) ENGINE=InnoDB COMMENT='帖子图片(0-9张)';

CREATE TABLE `post_cocreator` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id`    BIGINT UNSIGNED NOT NULL,
  `user_id`    BIGINT UNSIGNED NOT NULL COMMENT '共创者',
  `status`     TINYINT         NOT NULL DEFAULT 0 COMMENT '0待确认 1已确认 2已拒绝',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_post_user` (`post_id`, `user_id`),
  KEY `idx_user` (`user_id`, `status`)
) ENGINE=InnoDB COMMENT='帖子共创者';

CREATE TABLE `topic` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`       VARCHAR(30)     NOT NULL COMMENT '话题名(不含#)',
  `post_count` INT             NOT NULL DEFAULT 0 COMMENT '帖子数(冗余)',
  `hot_score`  BIGINT          NOT NULL DEFAULT 0,
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1正常 2封禁',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_name` (`name`),
  KEY `idx_hot` (`status`, `hot_score` DESC)
) ENGINE=InnoDB COMMENT='话题';

CREATE TABLE `post_topic` (
  `id`       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id`  BIGINT UNSIGNED NOT NULL,
  `topic_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pair` (`post_id`, `topic_id`),
  KEY `idx_topic` (`topic_id`, `post_id` DESC) COMMENT '话题聚合页'
) ENGINE=InnoDB COMMENT='帖子-话题关联(<=5)';

CREATE TABLE `comment` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id`     BIGINT UNSIGNED NOT NULL,
  `user_id`     BIGINT UNSIGNED NOT NULL COMMENT '评论者',
  `root_id`     BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '一级评论ID,0=自身是一级',
  `parent_id`   BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '直接回复的评论ID,0=回帖',
  `reply_uid`   BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '被回复用户,用于"回复@xx"展示',
  `content`     VARCHAR(1000)   NOT NULL,
  `like_count`  INT             NOT NULL DEFAULT 0,
  `reply_count` INT             NOT NULL DEFAULT 0 COMMENT '仅一级评论维护',
  `status`      TINYINT         NOT NULL DEFAULT 1 COMMENT '0待审核 1已发布 2违规屏蔽 4已删除',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_post` (`post_id`, `root_id`, `id`) COMMENT '详情页两级评论',
  KEY `idx_user` (`user_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='评论(两级)';

-- like 是保留字,表名用 like_record
CREATE TABLE `like_record` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`     BIGINT UNSIGNED NOT NULL,
  `target_type` TINYINT         NOT NULL COMMENT '1帖子 2评论',
  `target_id`   BIGINT UNSIGNED NOT NULL,
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_like` (`user_id`, `target_type`, `target_id`) COMMENT '幂等防重复点赞',
  KEY `idx_target` (`target_type`, `target_id`)
) ENGINE=InnoDB COMMENT='点赞';

CREATE TABLE `favorite` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `post_id`    BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fav` (`user_id`, `post_id`),
  KEY `idx_post` (`post_id`)
) ENGINE=InnoDB COMMENT='收藏';

-- 我的足迹：同帖重复浏览只更新时间(UPSERT)
CREATE TABLE `view_history` (
  `id`        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`   BIGINT UNSIGNED NOT NULL,
  `post_id`   BIGINT UNSIGNED NOT NULL,
  `viewed_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_view` (`user_id`, `post_id`),
  KEY `idx_user_time` (`user_id`, `viewed_at` DESC)
) ENGINE=InnoDB COMMENT='浏览足迹(仅自己可见)';

CREATE TABLE `report` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`     BIGINT UNSIGNED NOT NULL COMMENT '举报人',
  `target_type` TINYINT         NOT NULL COMMENT '1帖子 2评论 3用户 4私信 5软件(M3)',
  `target_id`   BIGINT UNSIGNED NOT NULL,
  `category`    TINYINT         NOT NULL DEFAULT 0 COMMENT '举报分类:1违法 2色情 3诈骗 4侵权 5其他',
  `reason`      VARCHAR(500)    NOT NULL DEFAULT '' COMMENT '补充说明',
  `images`      JSON            NULL COMMENT '证据图URL数组',
  `status`      TINYINT         NOT NULL DEFAULT 0 COMMENT '0待处理 1已处理 2已驳回',
  `handled_by`  BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '处理管理员',
  `handled_at`  DATETIME(3)     NULL,
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `id`),
  KEY `idx_target` (`target_type`, `target_id`)
) ENGINE=InnoDB COMMENT='举报';

-- ------------------------------------------------------------
-- 消息域：私信 / 通知
-- ------------------------------------------------------------

-- 单聊会话(v1.1 无群聊)。user_min/user_max 为两参与者按大小排序,保证会话唯一
CREATE TABLE `conversation` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_min`     BIGINT UNSIGNED NOT NULL COMMENT '较小的用户ID',
  `user_max`     BIGINT UNSIGNED NOT NULL COMMENT '较大的用户ID',
  `last_msg_seq` BIGINT          NOT NULL DEFAULT 0 COMMENT '当前最大seq,发消息时原子+1',
  `last_preview` VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '最后一条消息摘要',
  `last_msg_at`  DATETIME(3)     NULL COMMENT '最后消息时间',
  `created_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pair` (`user_min`, `user_max`)
) ENGINE=InnoDB COMMENT='私信会话(单聊)';

-- 会话成员视角。last_read_seq 即已读回执(文档中 message_read 并入本表:单聊场景每会话每人一行,无需独立表)
CREATE TABLE `conversation_member` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` BIGINT UNSIGNED NOT NULL,
  `user_id`         BIGINT UNSIGNED NOT NULL,
  `last_read_seq`   BIGINT          NOT NULL DEFAULT 0 COMMENT '已读到的seq,未读数=last_msg_seq-last_read_seq',
  `deleted`         TINYINT         NOT NULL DEFAULT 0 COMMENT '1已删除会话(仅影响自己列表)',
  `updated_at`      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_member` (`conversation_id`, `user_id`),
  KEY `idx_user` (`user_id`, `updated_at` DESC) COMMENT '会话列表'
) ENGINE=InnoDB COMMENT='会话成员状态';

CREATE TABLE `message` (
  `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` BIGINT UNSIGNED NOT NULL,
  `seq`             BIGINT          NOT NULL COMMENT '会话内序号,保证有序',
  `sender_id`       BIGINT UNSIGNED NOT NULL,
  `msg_type`        TINYINT         NOT NULL DEFAULT 1 COMMENT '1文本 2图片 3表情 4分享卡片(帖子/软件)',
  `content`         TEXT            NOT NULL COMMENT 'JSON:{text}|{url,w,h}|{cardType,refId,...}',
  `status`          TINYINT         NOT NULL DEFAULT 0 COMMENT '0正常 1已撤回 2违规屏蔽',
  `created_at`      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_conv_seq` (`conversation_id`, `seq`),
  KEY `idx_conv` (`conversation_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='私信消息';

-- 互动/系统通知(消息页三个聚合入口的数据源)
CREATE TABLE `notification` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`     BIGINT UNSIGNED NOT NULL COMMENT '接收者',
  `type`        TINYINT         NOT NULL COMMENT '1赞与收藏 2评论和@ 3系统通知',
  `actor_id`    BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '触发者,系统通知为0',
  `target_type` TINYINT         NOT NULL DEFAULT 0 COMMENT '1帖子 2评论',
  `target_id`   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `content`     VARCHAR(500)    NOT NULL DEFAULT '' COMMENT '摘要文案',
  `is_read`     TINYINT         NOT NULL DEFAULT 0,
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_user_type` (`user_id`, `type`, `id` DESC),
  KEY `idx_unread` (`user_id`, `is_read`)
) ENGINE=InnoDB COMMENT='互动与系统通知';

-- ------------------------------------------------------------
-- 运营域：首页配置 / 审核 / 后台
-- ------------------------------------------------------------

CREATE TABLE `banner` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title`      VARCHAR(50)     NOT NULL COMMENT '标题(如免责声明)',
  `image`      VARCHAR(255)    NOT NULL COMMENT '图URL',
  `link_type`  TINYINT         NOT NULL DEFAULT 0 COMMENT '0无跳转 1帖子 2H5 3圈子',
  `link_value` VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '帖子ID/URL/圈子ID',
  `sort`       INT             NOT NULL DEFAULT 0,
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1上线 0下线',
  `start_at`   DATETIME(3)     NULL COMMENT '定时上线,NULL立即',
  `end_at`     DATETIME(3)     NULL COMMENT '定时下线,NULL不限',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_online` (`status`, `sort`)
) ENGINE=InnoDB COMMENT='首页公告Banner';

CREATE TABLE `notice` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title`      VARCHAR(100)    NOT NULL,
  `content`    TEXT            NOT NULL,
  `created_by` BIGINT UNSIGNED NOT NULL COMMENT '发布管理员',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB COMMENT='系统公告(群发后写入 notification)';

CREATE TABLE `audit_queue` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `biz_type`       TINYINT         NOT NULL COMMENT '1帖子 2评论 3软件(M3)',
  `biz_id`         BIGINT UNSIGNED NOT NULL,
  `machine_result` TINYINT         NOT NULL DEFAULT 0 COMMENT '机审 0未审 1通过 2疑似转人审 3拒绝',
  `machine_detail` JSON            NULL COMMENT '机审命中明细',
  `status`         TINYINT         NOT NULL DEFAULT 0 COMMENT '0待人审 1通过 2驳回',
  `reason`         VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '人审驳回原因',
  `auditor_id`     BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `audited_at`     DATETIME(3)     NULL,
  `created_at`     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_pending` (`status`, `id`) COMMENT '人审工作台队列',
  KEY `idx_biz` (`biz_type`, `biz_id`)
) ENGINE=InnoDB COMMENT='审核队列(帖子/评论/软件复用)';

CREATE TABLE `sensitive_word` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `word`       VARCHAR(64)     NOT NULL,
  `category`   TINYINT         NOT NULL DEFAULT 0 COMMENT '1政治 2色情 3辱骂 4广告 5其他',
  `level`      TINYINT         NOT NULL DEFAULT 1 COMMENT '1直接拦截 2转人审 3替换为*',
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_word` (`word`)
) ENGINE=InnoDB COMMENT='敏感词';

CREATE TABLE `admin_role` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`        VARCHAR(30)     NOT NULL COMMENT '角色名:超管/审核/运营',
  `permissions` JSON            NOT NULL COMMENT '权限码数组',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_name` (`name`)
) ENGINE=InnoDB COMMENT='后台角色';

CREATE TABLE `admin_user` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `username`      VARCHAR(30)     NOT NULL,
  `password_hash` VARCHAR(100)    NOT NULL COMMENT 'bcrypt',
  `role_id`       BIGINT UNSIGNED NOT NULL,
  `status`        TINYINT         NOT NULL DEFAULT 1 COMMENT '1正常 0停用',
  `last_login_at` DATETIME(3)     NULL,
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_username` (`username`)
) ENGINE=InnoDB COMMENT='后台账号';

CREATE TABLE `admin_op_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `admin_id`   BIGINT UNSIGNED NOT NULL,
  `action`     VARCHAR(64)     NOT NULL COMMENT '操作码:audit.pass/user.ban/...',
  `target`     VARCHAR(128)    NOT NULL DEFAULT '' COMMENT '操作对象,如 post:123',
  `detail`     JSON            NULL COMMENT '操作明细快照',
  `ip`         VARCHAR(45)     NOT NULL DEFAULT '',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_admin` (`admin_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='后台操作日志(敏感操作留痕)';

-- ------------------------------------------------------------
-- 种子数据
-- ------------------------------------------------------------

INSERT INTO `circle` (`name`, `intro`, `is_official`, `pinned`, `sort`) VALUES
  ('官方公告', '社区最新通知,仅官方可发', 1, 1, 0),
  ('闲言碎语', '无聊就来此聊聊', 0, 0, 10),
  ('骗子举报', '曝光各类诈骗,强化审核', 1, 0, 20);

INSERT INTO `admin_role` (`name`, `permissions`) VALUES
  ('超级管理员', JSON_ARRAY('*'));
