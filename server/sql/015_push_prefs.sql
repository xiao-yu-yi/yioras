-- ============================================================
-- 通知推送开关:用户级分类偏好(bit0 私信 / bit1 互动 / bit2 系统),默认全开
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

ALTER TABLE `user`
  ADD COLUMN `push_prefs` TINYINT NOT NULL DEFAULT 7 COMMENT '离线推送开关位:1私信 2互动 4系统,默认全开' AFTER `teen_mode`;
