-- ============================================================
-- 运营参数表(KV,通用基建)+ 成长体系首批收编:经验权重与每日上限
-- 需求 3.1:发帖/评论/签到/被赞加经验,后台可配权重与每日上限
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

CREATE TABLE `app_config` (
  `k`          VARCHAR(64)  NOT NULL COMMENT '参数键,点分命名空间(如 exp.post)',
  `v`          VARCHAR(255) NOT NULL COMMENT '参数值(字符串,语义由使用方解释)',
  `remark`     VARCHAR(255) NOT NULL DEFAULT '' COMMENT '后台展示说明',
  `updated_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`k`)
) ENGINE=InnoDB COMMENT='运营参数(后台可配)';

-- 默认值与既有硬编码一致,升级不改变现网行为;like_received 为本次新增能力
INSERT INTO `app_config` (`k`, `v`, `remark`) VALUES
  ('exp.post',          '5',   '发帖加经验'),
  ('exp.comment',       '2',   '评论加经验'),
  ('exp.sign',          '5',   '每日签到加经验'),
  ('exp.like_received', '1',   '帖子被赞,作者加经验'),
  ('exp.daily_cap',     '100', '行为经验每日上限(不含任务奖励配置的经验)');
