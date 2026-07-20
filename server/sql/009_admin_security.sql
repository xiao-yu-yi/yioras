-- ============================================================
-- Yiora 管理后台安全加固:
-- 1. admin_user 增加 must_change_pwd(初始账号/管理员重置密码后首登强制改密)
-- 2. 补审核员/运营两个常用角色种子,供账号管理页角色分配
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

ALTER TABLE `admin_user`
  ADD COLUMN `must_change_pwd` TINYINT NOT NULL DEFAULT 0 COMMENT '1=下次登录必须改密' AFTER `status`;

-- 初始 admin 账号首登强制改密
UPDATE `admin_user` SET must_change_pwd = 1 WHERE username = 'admin';

INSERT INTO `admin_role` (`name`, `permissions`) VALUES
  ('审核员', JSON_ARRAY('audit', 'log.view')),
  ('运营', JSON_ARRAY('ops.notice', 'ops.banner', 'dashboard', 'user.ban', 'log.view'))
ON DUPLICATE KEY UPDATE permissions = VALUES(permissions);
