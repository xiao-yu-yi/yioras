-- ============================================================
-- Yiora 管理后台:TOTP 二步验证
-- admin_user 加绑定字段;恢复码单独成表(一次性,哈希存储)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

ALTER TABLE `admin_user`
  ADD COLUMN `totp_secret`  VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'base32 密钥,空=未绑定' AFTER `must_change_pwd`,
  ADD COLUMN `totp_enabled` TINYINT     NOT NULL DEFAULT 0 COMMENT '1=已启用二步验证' AFTER `totp_secret`;

CREATE TABLE `admin_recovery_code` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `admin_id`   BIGINT UNSIGNED NOT NULL,
  `code_hash`  CHAR(64)        NOT NULL COMMENT 'sha256(hex) 恢复码哈希',
  `used_at`    DATETIME(3)     NULL COMMENT '使用时间,NULL=未用',
  `created_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_admin` (`admin_id`, `used_at`)
) ENGINE=InnoDB COMMENT='TOTP 一次性恢复码';
