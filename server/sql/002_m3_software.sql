-- ============================================================
-- Yiora M3 增量迁移 001:社区软件库
-- 依据: docs/Yiora开发需求文档.md 3.5.2 发软件 / 3.6 应用中心 / 4.4 数据模型
-- 环境: MySQL 8.0+, InnoDB, utf8mb4;不修改 001 已有表
-- 约定:
--   * 新软件与版本更新均需人工审核(status=0 待审核起步)
--   * software.download_count/hot_score 为冗余计数,允许短暂滞后
--   * 介绍图(3-6张)存 software.images JSON 数组,无独立查询路径不拆表
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 软件主体
CREATE TABLE `software` (
  `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`           BIGINT UNSIGNED NOT NULL COMMENT '发布者',
  `name`              VARCHAR(50)     NOT NULL COMMENT '软件名',
  `logo`              VARCHAR(255)    NOT NULL COMMENT 'Logo URL(方图)',
  `intro`             VARCHAR(1000)   NOT NULL COMMENT '简介',
  `images`            JSON            NOT NULL COMMENT '介绍图URL数组(3-6张,发布强校验)',
  `type`              TINYINT         NOT NULL COMMENT '1应用 2游戏',
  `category_id`       BIGINT UNSIGNED NOT NULL COMMENT '细分类目',
  `latest_version_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '最新已发布版本(审核通过时回填)',
  `download_count`    BIGINT          NOT NULL DEFAULT 0 COMMENT '下载点击数(冗余)',
  `hot_score`         BIGINT          NOT NULL DEFAULT 0 COMMENT '热度分(离线计算)',
  `status`            TINYINT         NOT NULL DEFAULT 0 COMMENT '0待审核 1已上架 2已驳回 3已下架 4已删除',
  `reject_reason`     VARCHAR(255)    NOT NULL DEFAULT '',
  `created_at`        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_list_new` (`status`, `type`, `id` DESC) COMMENT '列表-最新',
  KEY `idx_list_hot` (`status`, `type`, `hot_score` DESC) COMMENT '列表-最热',
  KEY `idx_list_dl` (`status`, `type`, `download_count` DESC) COMMENT '列表-下载最多',
  KEY `idx_category` (`category_id`, `status`, `id` DESC) COMMENT '分类筛选',
  KEY `idx_author` (`user_id`, `id` DESC) COMMENT '我的发布'
) ENGINE=InnoDB COMMENT='社区软件';

-- 软件版本(同一软件多版本,下载链接挂在版本上)
CREATE TABLE `software_version` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `software_id`   BIGINT UNSIGNED NOT NULL,
  `version`       VARCHAR(20)     NOT NULL COMMENT '版本号,如 2.3.1',
  `size`          VARCHAR(20)     NOT NULL COMMENT '展示用大小,如 128MB',
  `channel`       VARCHAR(30)     NOT NULL DEFAULT '' COMMENT '渠道:官方/第三方/自制等',
  `download_url`  VARCHAR(500)    NOT NULL COMMENT '下载链接(http/https)',
  `extract_code`  VARCHAR(20)     NOT NULL DEFAULT '' COMMENT '网盘提取码',
  `status`        TINYINT         NOT NULL DEFAULT 0 COMMENT '0待审核 1已发布 2已驳回',
  `reject_reason` VARCHAR(255)    NOT NULL DEFAULT '',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_soft_ver` (`software_id`, `version`) COMMENT '同软件版本号唯一',
  KEY `idx_soft` (`software_id`, `status`, `id` DESC) COMMENT '版本历史'
) ENGINE=InnoDB COMMENT='软件版本';

-- 细分类目(后台可配;type 区分所属大类)
CREATE TABLE `software_category` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `type`       TINYINT         NOT NULL COMMENT '1应用 2游戏',
  `name`       VARCHAR(20)     NOT NULL,
  `sort`       INT             NOT NULL DEFAULT 0 COMMENT '小在前',
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_type_name` (`type`, `name`),
  KEY `idx_type` (`type`, `status`, `sort`)
) ENGINE=InnoDB COMMENT='软件分类';

-- APK 标签(发布者自定义,如 免登录/去广告)
CREATE TABLE `software_tag` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `software_id` BIGINT UNSIGNED NOT NULL,
  `name`        VARCHAR(20)     NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_soft_tag` (`software_id`, `name`)
) ENGINE=InnoDB COMMENT='软件标签';

-- 下载点击流水(热度排序与风控数据源)
CREATE TABLE `software_download_log` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `software_id` BIGINT UNSIGNED NOT NULL,
  `version_id`  BIGINT UNSIGNED NOT NULL,
  `user_id`     BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=游客',
  `created_at`  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_soft_time` (`software_id`, `created_at`),
  KEY `idx_user` (`user_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='下载点击流水';

-- 分类种子
INSERT INTO `software_category` (`type`, `name`, `sort`) VALUES
  (1, '实用工具', 10), (1, '社交通讯', 20), (1, '影音播放', 30), (1, '学习办公', 40),
  (2, '休闲益智', 10), (2, '角色扮演', 20), (2, '策略塔防', 30), (2, '竞速体育', 40);
