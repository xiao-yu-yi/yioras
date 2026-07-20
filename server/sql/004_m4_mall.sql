-- ============================================================
-- Yiora M4 增量迁移 001:忧珠消耗侧(装扮商城/靓号商城/积分抽奖/兑换记录)
-- 依据: docs/Yiora开发需求文档.md 3.9 成长激励与忧珠商城
-- 约定:
--   * 所有消耗走单事务:账户行锁 + youzhu_log 幂等键 + 发放 + exchange_record
--   * 抽奖概率公示:奖池接口返回 weight,客户端按 weight/SUM 展示概率
--   * 一期奖池只投放 忧珠/装扮 两类奖品(靓号库存唯一,运营后台定向投放)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 装扮(头像框;气泡商城已按需求裁剪)
CREATE TABLE `decoration` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `kind`          TINYINT         NOT NULL COMMENT '1头像框',
  `name`          VARCHAR(30)     NOT NULL,
  `preview`       VARCHAR(255)    NOT NULL COMMENT '预览/素材URL(CDN)',
  `price`         INT             NOT NULL COMMENT '忧珠价格',
  `duration_days` INT             NOT NULL DEFAULT 0 COMMENT '有效天数,0=永久',
  `sort`          INT             NOT NULL DEFAULT 0,
  `status`        TINYINT         NOT NULL DEFAULT 1 COMMENT '1上架 0下架',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_kind` (`kind`, `status`, `sort`)
) ENGINE=InnoDB COMMENT='装扮商品';

-- 我的装扮仓库(同装扮一行,限时续期延长 expire_at)
CREATE TABLE `user_decoration` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`       BIGINT UNSIGNED NOT NULL,
  `decoration_id` BIGINT UNSIGNED NOT NULL,
  `expire_at`     DATETIME(3)     NULL COMMENT 'NULL=永久',
  `worn`          TINYINT         NOT NULL DEFAULT 0 COMMENT '1佩戴中(同 kind 至多一件)',
  `created_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at`    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_deco` (`user_id`, `decoration_id`),
  KEY `idx_user_worn` (`user_id`, `worn`)
) ENGINE=InnoDB COMMENT='我的装扮仓库';

-- 靓号库存(每个号码唯一,售出即止)
CREATE TABLE `pretty_no_sku` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `no`         VARCHAR(20)     NOT NULL COMMENT '展示编号,如 N88888',
  `rarity`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1普通 2稀有 3传说',
  `price`      INT             NOT NULL COMMENT '忧珠价格',
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1在售 2已售 0下架',
  `sold_to`    BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `sold_at`    DATETIME(3)     NULL,
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_no` (`no`),
  KEY `idx_sale` (`status`, `rarity`, `price`)
) ENGINE=InnoDB COMMENT='靓号库存';

-- 抽奖奖池(weight 权重抽取,概率=weight/SUM 公示)
CREATE TABLE `lottery_pool` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`       VARCHAR(30)     NOT NULL COMMENT '奖品名',
  `kind`       TINYINT         NOT NULL COMMENT '1忧珠 2装扮',
  `ref_id`     BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '装扮ID(kind=2)',
  `amount`     INT             NOT NULL DEFAULT 0 COMMENT '忧珠数量(kind=1)',
  `weight`     INT             NOT NULL COMMENT '抽取权重',
  `stock`      INT             NOT NULL DEFAULT -1 COMMENT '-1=不限量',
  `status`     TINYINT         NOT NULL DEFAULT 1 COMMENT '1启用 0停用',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB COMMENT='抽奖奖池';

-- 抽奖流水(奖品快照)
CREATE TABLE `lottery_log` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `pool_id`    BIGINT UNSIGNED NOT NULL,
  `prize_name` VARCHAR(30)     NOT NULL,
  `kind`       TINYINT         NOT NULL,
  `amount`     INT             NOT NULL DEFAULT 0,
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_user` (`user_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='抽奖流水';

-- 兑换记录(装扮/靓号/抽奖统一入口,侧边抽屉"兑换记录"页数据源)
CREATE TABLE `exchange_record` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `kind`       TINYINT         NOT NULL COMMENT '1装扮 2靓号 3抽奖',
  `ref_id`     BIGINT UNSIGNED NOT NULL COMMENT '装扮ID/靓号skuID/抽奖流水ID',
  `name`       VARCHAR(50)     NOT NULL COMMENT '名称快照',
  `cost`       INT             NOT NULL COMMENT '消耗忧珠',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_user` (`user_id`, `id` DESC)
) ENGINE=InnoDB COMMENT='兑换记录';

-- 种子:装扮 / 靓号 / 奖池
INSERT INTO `decoration` (`kind`, `name`, `preview`, `price`, `duration_days`, `sort`) VALUES
  (1, '星空头像框', 'https://cdn.example.com/deco/star-frame.png', 30, 0, 10),
  (1, '樱花头像框(7天)', 'https://cdn.example.com/deco/sakura-frame.png', 10, 7, 20);

INSERT INTO `pretty_no_sku` (`no`, `rarity`, `price`) VALUES
  ('N66666', 2, 100), ('N88888', 3, 300), ('N12321', 1, 50);

INSERT INTO `lottery_pool` (`name`, `kind`, `ref_id`, `amount`, `weight`, `stock`) VALUES
  ('5 忧珠', 1, 0, 5, 50, -1),
  ('20 忧珠', 1, 0, 20, 30, -1),
  ('樱花头像框(7天)', 2, 2, 0, 20, 10);
