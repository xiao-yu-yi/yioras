-- ============================================================
-- Yiora P 级收尾:青少年模式开关(合规) + 帖子分享计数
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

ALTER TABLE `user`
  ADD COLUMN `teen_mode` TINYINT NOT NULL DEFAULT 0 COMMENT '1=青少年模式(付费/抽奖/兑换等消费功能禁用)' AFTER `status`;

ALTER TABLE `post`
  ADD COLUMN `share_count` INT NOT NULL DEFAULT 0 COMMENT '分享口令生成次数' AFTER `favorite_count`;
