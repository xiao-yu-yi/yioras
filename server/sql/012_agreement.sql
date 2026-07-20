-- ============================================================
-- Yiora 合规:协议静态页(用户协议/隐私政策),客户端注册页强制同意时拉取
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

CREATE TABLE `agreement` (
  `kind`       VARCHAR(20)  NOT NULL COMMENT 'user=用户协议 privacy=隐私政策',
  `title`      VARCHAR(100) NOT NULL,
  `content`    MEDIUMTEXT   NOT NULL COMMENT 'Markdown/纯文本',
  `updated_at` DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`kind`)
) ENGINE=InnoDB COMMENT='协议静态页';

INSERT INTO `agreement` (`kind`, `title`, `content`) VALUES
  ('user', 'Yiora 用户协议', '欢迎使用 Yiora。本协议为占位文本,正式上线前由法务提供终稿并经后台「协议管理」更新。\n\n1. 账号注册与使用规范\n2. 用户内容与知识产权\n3. 社区行为准则\n4. 免责声明\n5. 协议变更与终止'),
  ('privacy', 'Yiora 隐私政策', '本政策为占位文本,正式上线前由法务提供终稿并经后台「协议管理」更新。\n\n1. 我们收集哪些信息\n2. 信息的使用方式\n3. 信息的存储与保护\n4. 你的权利\n5. 未成年人保护\n6. 政策更新');
