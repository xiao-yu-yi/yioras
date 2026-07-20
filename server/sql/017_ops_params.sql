-- ============================================================
-- 运营参数收编第二批(需求各处"后台可配"落地)+ 帖子运营字段(红标题/下沉)
-- ============================================================

SET NAMES utf8mb4;
USE yiora;

-- 默认值与既有硬编码一致,升级不改变现网行为
INSERT INTO `app_config` (`k`, `v`, `remark`) VALUES
  ('sign.ladder',       '5,5,10,10,15,15,30', '连签阶梯忧珠奖励(7 档循环,逗号分隔)'),
  ('paid.fee_percent',  '10',   '付费帖平台抽成百分比(0-50)'),
  ('paid.min_price',    '1',    '付费帖最低定价(忧珠)'),
  ('paid.max_price',    '1000', '付费帖最高定价(忧珠)'),
  ('im.stranger_daily', '3',    '未互关私信每日条数上限'),
  ('im.recall_sec',     '120',  '私信可撤回窗口(秒)'),
  ('lottery.cost',      '10',   '单次抽奖消耗忧珠');

ALTER TABLE `post`
  ADD COLUMN `is_red_title` TINYINT NOT NULL DEFAULT 0 COMMENT '1=红色标题(运营帖高亮,需求 3.2)' AFTER `is_essence`,
  ADD COLUMN `is_sink`      TINYINT NOT NULL DEFAULT 0 COMMENT '1=下沉(热度重算强制 0 分,需求 3.12)' AFTER `is_red_title`;
