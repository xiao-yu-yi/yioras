-- ============================================================
-- Yiora M4 增量迁移 002:忧珠付费解锁帖 + AI 管家(规则引擎一期)
-- 依据: docs/Yiora开发需求文档.md 3.3 付费解锁 / 3.7 AI 管家 / 4.3-5 分段存储
-- 约定:
--   * 付费全文独立存储,服务端校验解锁记录后才下发,防客户端绕过
--   * 解锁 = 买家扣款 + 作者分成 双账户单事务(平台抽成落差额)
--   * AI 管家为系统账号(固定 uid 999999),FAQ 关键词规则引擎,二期接大模型
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 付费段(帖子可选,一帖一段;post.content 存免费摘要)
CREATE TABLE `post_paid_content` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id`    BIGINT UNSIGNED NOT NULL,
  `price`      INT             NOT NULL COMMENT '解锁价(忧珠),平台设定区间',
  `content`    TEXT            NOT NULL COMMENT '付费全文段',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_post` (`post_id`)
) ENGINE=InnoDB COMMENT='帖子付费段';

-- 解锁记录(uk 幂等防重复扣款)
CREATE TABLE `post_unlock_record` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `post_id`       BIGINT UNSIGNED NOT NULL,
  `user_id`       BIGINT UNSIGNED NOT NULL COMMENT '解锁者',
  `price`         INT             NOT NULL COMMENT '成交价快照',
  `author_income` INT             NOT NULL COMMENT '作者分成(平台抽成后)',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_post_user` (`post_id`, `user_id`),
  KEY `idx_user` (`user_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='付费帖解锁记录';

-- AI 管家 FAQ 规则(关键词包含匹配,priority 小者优先)
CREATE TABLE `faq_rule` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `keywords`   VARCHAR(200)    NOT NULL COMMENT '关键词,竖线分隔,命中任一即回复',
  `reply`      VARCHAR(1000)   NOT NULL,
  `priority`   INT             NOT NULL DEFAULT 100,
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `priority`)
) ENGINE=InnoDB COMMENT='AI管家FAQ规则';

-- AI 管家系统账号(固定 uid,与代码内 model.BotUID 一致;普通注册不受影响)
INSERT INTO `user` (`id`, `display_no`, `nickname`, `avatar`, `signature`, `status`)
VALUES (999999, 'YOBOT', 'Yo酱', 'https://cdn.example.com/bot/yo.png', '社区智能管家,回复关键词试试~', 1)
ON DUPLICATE KEY UPDATE nickname = VALUES(nickname);

-- FAQ 种子
INSERT INTO `faq_rule` (`keywords`, `reply`, `priority`) VALUES
  ('帮助|help|菜单', '你好,我是 Yo酱~ 可以问我:「签到」「忧珠」「审核」「靓号」「装扮」「抽奖」相关问题哦。', 10),
  ('签到', '每天在「任务中心」签到可得忧珠,连续签到 7 天一循环,奖励越签越多(第 7 天 30 忧珠)!', 20),
  ('忧珠', '忧珠是社区积分:做任务、签到可获取;可用于装扮商城、靓号商城、积分抽奖和解锁付费帖。忧珠不可充值、不可提现哦。', 30),
  ('审核', '发布的动态/软件命中疑似内容会转人工审核,一般会尽快处理;结果会通过「系统通知」告诉你。', 40),
  ('靓号', '在商城 Tab 的「靓号商城」可以用忧珠兑换心仪的展示编号,兑换后立即替换你的 ID~', 50),
  ('装扮', '「装扮商城」有头像框和聊天气泡,兑换后在「我的仓库」佩戴,全站立即生效!', 60),
  ('抽奖', '「积分抽奖」消耗 10 忧珠抽一次,奖池概率全部公示,试试手气吧~', 70);
