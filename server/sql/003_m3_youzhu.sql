-- ============================================================
-- Yiora M3 增量迁移 002:忧珠(积分)账户 + 任务中心 + 签到
-- 依据: docs/Yiora开发需求文档.md 3.9 成长激励 / 3.10 忧珠资产 / 4.3-4 账务安全
-- 约定:
--   * 忧珠不可充值/提现/转赠;全部变动走事务 + biz_key 幂等键
--   * youzhu_log.balance_after 冗余入账后余额,对账与客服排查用
--   * 签到独立闭环(阶梯奖励);task 表只放行为任务(发帖/评论/点赞/浏览)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 忧珠账户(每用户一行,行锁串行化变动)
CREATE TABLE `youzhu_account` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `balance`    BIGINT          NOT NULL DEFAULT 0 COMMENT '当前余额,禁止为负',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user` (`user_id`)
) ENGINE=InnoDB COMMENT='忧珠账户';

-- 忧珠流水(收支双向;biz_key 幂等防重复入账)
CREATE TABLE `youzhu_log` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`       BIGINT UNSIGNED NOT NULL,
  `biz_type`      TINYINT         NOT NULL COMMENT '1任务奖励 2签到 3运营发放 4兑换消耗 5抽奖 6付费解锁',
  `biz_key`       VARCHAR(64)     NOT NULL COMMENT '幂等键,如 sign:{uid}:{day}',
  `amount`        BIGINT          NOT NULL COMMENT '正=入账 负=支出',
  `balance_after` BIGINT          NOT NULL COMMENT '入账后余额(冗余,对账用)',
  `remark`        VARCHAR(100)    NOT NULL DEFAULT '',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_biz_key` (`biz_key`),
  KEY `idx_user` (`user_id`, `id` DESC) COMMENT '流水明细页',
  KEY `idx_user_type` (`user_id`, `biz_type`, `id` DESC) COMMENT '按类型筛选'
) ENGINE=InnoDB COMMENT='忧珠流水';

-- 行为任务配置(后台可配)
CREATE TABLE `task` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`          VARCHAR(30)     NOT NULL,
  `type`          TINYINT         NOT NULL DEFAULT 1 COMMENT '1每日 2新手',
  `action`        VARCHAR(20)     NOT NULL COMMENT '行为:post/comment/like/browse',
  `target_count`  INT             NOT NULL DEFAULT 1 COMMENT '完成所需次数',
  `reward_youzhu` INT             NOT NULL DEFAULT 0,
  `reward_exp`    INT             NOT NULL DEFAULT 0,
  `sort`          INT             NOT NULL DEFAULT 0,
  `status`        TINYINT         NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_action` (`status`, `action`)
) ENGINE=InnoDB COMMENT='任务配置';

-- 任务进度(每日任务按天一行;新手任务 day 固定 1970-01-01)
CREATE TABLE `user_task_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `task_id`    BIGINT UNSIGNED NOT NULL,
  `day`        DATE            NOT NULL COMMENT '每日任务=当天;新手任务=1970-01-01',
  `progress`   INT             NOT NULL DEFAULT 0,
  `status`     TINYINT         NOT NULL DEFAULT 0 COMMENT '0进行中 1可领取 2已领取',
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_task_day` (`user_id`, `task_id`, `day`),
  KEY `idx_user_day` (`user_id`, `day`)
) ENGINE=InnoDB COMMENT='任务进度';

-- 签到流水(连续天数快照;阶梯奖励)
CREATE TABLE `sign_in_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `day`        DATE            NOT NULL,
  `continuous` INT             NOT NULL DEFAULT 1 COMMENT '截至当天的连续签到天数',
  `reward`     INT             NOT NULL DEFAULT 0 COMMENT '当日签到奖励忧珠',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_day` (`user_id`, `day`) COMMENT '幂等防重复签到',
  KEY `idx_user` (`user_id`, `day` DESC)
) ENGINE=InnoDB COMMENT='签到流水';

-- 行为任务种子
INSERT INTO `task` (`name`, `type`, `action`, `target_count`, `reward_youzhu`, `reward_exp`, `sort`) VALUES
  ('发布 1 篇动态', 1, 'post', 1, 10, 10, 10),
  ('发表 3 条评论', 1, 'comment', 3, 5, 5, 20),
  ('点赞 5 次', 1, 'like', 5, 5, 5, 30),
  ('浏览 3 篇帖子', 1, 'browse', 3, 3, 3, 40),
  ('发布你的第一篇动态', 2, 'post', 1, 20, 20, 10);
