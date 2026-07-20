-- ============================================================
-- Yiora P1 增量迁移:评论多业务对象 + 软件评论计数 + 草稿箱
-- 依据: docs/Yiora开发需求文档.md 3.5(存草稿) / 3.6(软件详情评论区) / 3.3(帖子编辑)
-- 说明: 项目未上线,comment.post_id 直接改名 biz_id(biz_type 区分帖子/软件),无灰度兼容负担
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 评论表扩多业务对象:1帖子 2软件
ALTER TABLE `comment`
  RENAME COLUMN `post_id` TO `biz_id`,
  ADD COLUMN `biz_type` TINYINT NOT NULL DEFAULT 1 COMMENT '1帖子 2软件' AFTER `id`,
  DROP INDEX `idx_post`,
  ADD INDEX `idx_biz` (`biz_type`, `biz_id`, `root_id`, `id`) COMMENT '详情页两级评论';

-- 软件评论数(冗余计数,与帖子口径一致:仅已发布评论)
ALTER TABLE `software`
  ADD COLUMN `comment_count` BIGINT NOT NULL DEFAULT 0 AFTER `download_count`;

-- 敏感词三级处置样例(上线前由运营导入真实词库;样例词用于机审链路验证,正常内容不会命中)
INSERT IGNORE INTO `sensitive_word` (`word`, `category`, `level`) VALUES
  ('BLOCKWORD_SAMPLE', 5, 1),
  ('REVIEWWORD_SAMPLE', 5, 2),
  ('MASKWORD_SAMPLE', 5, 3);

-- 发布器草稿箱(动态/软件双通道,payload 为表单快照,发布时才做业务校验)
CREATE TABLE `draft` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `kind`       TINYINT         NOT NULL COMMENT '1动态 2软件',
  `payload`    JSON            NOT NULL COMMENT '发布器表单快照,客户端自解释',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_user` (`user_id`, `kind`, `updated_at` DESC)
) ENGINE=InnoDB COMMENT='发布草稿箱';
