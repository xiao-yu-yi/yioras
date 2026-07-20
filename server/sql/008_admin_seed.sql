-- ============================================================
-- Yiora 管理后台迁移:初始管理员账号
-- 初始账号 admin / admin123(bcrypt),首次登录后必须改密(后台前端引导)
-- 角色表 001 已建,超级管理员(id=1, permissions=["*"])已有种子
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

INSERT INTO `admin_user` (`username`, `password_hash`, `role_id`)
SELECT 'admin', '$2a$10$ZhCQV.pW8YeGEoDGbNHrWujUGjBYHxKunSD70uW0B7LbutEjed7vK', 1
WHERE NOT EXISTS (SELECT 1 FROM `admin_user` WHERE username = 'admin');
