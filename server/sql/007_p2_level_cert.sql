-- ============================================================
-- Yiora P2 增量迁移:等级阈值 + 权益认证 + 圈内置顶
-- 依据: docs/Yiora开发需求文档.md 3.1(等级/权益认证) / 3.4(圈子管理)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 等级经验阈值(后台可配;level 连续递增,need_exp 严格递增)
CREATE TABLE `level_rule` (
  `level`    INT    NOT NULL COMMENT '等级 Lv.N',
  `need_exp` BIGINT NOT NULL COMMENT '达到该等级所需累计经验',
  PRIMARY KEY (`level`)
) ENGINE=InnoDB COMMENT='等级经验阈值';

INSERT INTO `level_rule` (`level`, `need_exp`) VALUES
  (0, 0), (1, 100), (2, 300), (3, 600), (4, 1000),
  (5, 1500), (6, 2100), (7, 2800), (8, 3600), (9, 4500), (10, 5500);

-- 权益认证(达人/开发者,人工审核授头衔;无实名,见需求 3.1)
CREATE TABLE `certification` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `kind`       TINYINT         NOT NULL COMMENT '1达人 2开发者',
  `material`   VARCHAR(1000)   NOT NULL COMMENT '佐证材料说明/作品链接',
  `status`     TINYINT         NOT NULL DEFAULT 0 COMMENT '0待审 1通过 2驳回',
  `reason`     VARCHAR(255)    NOT NULL DEFAULT '' COMMENT '驳回原因',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_kind` (`user_id`, `kind`),
  KEY `idx_pending` (`status`, `id`) COMMENT '后台认证审核队列'
) ENGINE=InnoDB COMMENT='权益认证';

-- 圈内置顶(is_top 是首页置顶精选,语义不同)
ALTER TABLE `post`
  ADD COLUMN `circle_top` TINYINT NOT NULL DEFAULT 0 COMMENT '1圈内置顶(圈主/管理员操作)' AFTER `is_essence`;
