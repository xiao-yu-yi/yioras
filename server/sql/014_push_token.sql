-- ============================================================
-- 离线推送:设备推送 token(APNs/厂商通道),与设备体系(device_id)对齐
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

CREATE TABLE `push_token` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT UNSIGNED NOT NULL,
  `device_id`  VARCHAR(32)     NOT NULL COMMENT '登录设备指纹(auth 设备体系)',
  `platform`   VARCHAR(16)     NOT NULL COMMENT 'ios/android/harmony',
  `channel`    VARCHAR(16)     NOT NULL COMMENT 'apns/huawei/xiaomi/oppo/vivo/mock',
  `token`      VARCHAR(255)    NOT NULL COMMENT '通道下发凭证',
  `updated_at` DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_device` (`user_id`, `device_id`) COMMENT '一设备一行,重复上报覆盖',
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB COMMENT='离线推送设备令牌';
