-- ============================================================
-- Yiora 管理后台:运营角色补商城/任务配置权限(ops.mall)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

UPDATE `admin_role`
SET permissions = JSON_ARRAY('ops.notice', 'ops.banner', 'ops.mall', 'dashboard', 'user.ban', 'log.view')
WHERE name = '运营';
