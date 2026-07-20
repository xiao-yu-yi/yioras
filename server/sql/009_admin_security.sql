-- ============================================================
-- Yiora 管理后台安全加固:
-- 补审核员/运营两个常用角色种子,供账号管理页角色分配
-- (曾含首登强制改密字段,产品决策移除,未发布故直接修订本迁移)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

INSERT INTO `admin_role` (`name`, `permissions`) VALUES
  ('审核员', JSON_ARRAY('audit', 'log.view')),
  ('运营', JSON_ARRAY('ops.notice', 'ops.banner', 'dashboard', 'user.ban', 'log.view'))
ON DUPLICATE KEY UPDATE permissions = VALUES(permissions);
