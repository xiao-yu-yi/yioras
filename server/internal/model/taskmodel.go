package model

import (
	"context"
	"fmt"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 任务类型(task.type)
const (
	TaskTypeDaily  = 1
	TaskTypeNewbie = 2
)

// 任务进度状态(user_task_log.status)
const (
	TaskStatusDoing   = 0
	TaskStatusDone    = 1 // 可领取
	TaskStatusClaimed = 2
	newbieDaySentinel = "1970-01-01"
	taskDayLayout     = "2006-01-02"
)

type (
	Task struct {
		ID           int64  `db:"id"`
		Name         string `db:"name"`
		Type         int64  `db:"type"`
		Action       string `db:"action"`
		TargetCount  int64  `db:"target_count"`
		RewardYouzhu int64  `db:"reward_youzhu"`
		RewardExp    int64  `db:"reward_exp"`
		Sort         int64  `db:"sort"`
	}

	UserTaskLog struct {
		ID       int64  `db:"id"`
		UserID   int64  `db:"user_id"`
		TaskID   int64  `db:"task_id"`
		Day      string `db:"day"`
		Progress int64  `db:"progress"`
		Status   int64  `db:"status"`
	}

	SignInLog struct {
		ID         int64     `db:"id"`
		UserID     int64     `db:"user_id"`
		Day        time.Time `db:"day"`
		Continuous int64     `db:"continuous"`
		Reward     int64     `db:"reward"`
	}

	TaskModel struct{ conn sqlx.SqlConn }
)

func NewTaskModel(conn sqlx.SqlConn) *TaskModel { return &TaskModel{conn: conn} }

// taskDay 任务归属日:每日任务=今天,新手任务=固定哨兵日。
func taskDay(taskType int64, now time.Time) string {
	if taskType == TaskTypeNewbie {
		return newbieDaySentinel
	}
	return now.Format(taskDayLayout)
}

// TaskFull 后台视角任务行(含启停)。
type TaskFull struct {
	Task
	Status int64 `db:"status"`
}

// ListTasksAdmin 后台任务列表(含停用)。
func (m *TaskModel) ListTasksAdmin(ctx context.Context) ([]*TaskFull, error) {
	var rows []*TaskFull
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, type, action, target_count, reward_youzhu, reward_exp, sort, status FROM `task` ORDER BY type, sort, id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// SaveTask 新建/更新任务配置。历史进度按 task_id 关联,改奖励只影响未领取的结算。
func (m *TaskModel) SaveTask(ctx context.Context, t *TaskFull) (int64, bool, error) {
	if t.ID > 0 {
		if _, err := m.conn.ExecCtx(ctx,
			"UPDATE `task` SET name = ?, type = ?, action = ?, target_count = ?, reward_youzhu = ?, reward_exp = ?, sort = ?, status = ? WHERE id = ?",
			t.Name, t.Type, t.Action, t.TargetCount, t.RewardYouzhu, t.RewardExp, t.Sort, t.Status, t.ID); err != nil {
			return 0, false, fmt.Errorf("update task: %w", err)
		}
		var n int
		if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `task` WHERE id = ?", t.ID); err != nil {
			return 0, false, err
		}
		return t.ID, n > 0, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `task` (name, type, action, target_count, reward_youzhu, reward_exp, sort, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		t.Name, t.Type, t.Action, t.TargetCount, t.RewardYouzhu, t.RewardExp, t.Sort, t.Status)
	if err != nil {
		return 0, false, fmt.Errorf("insert task: %w", err)
	}
	id, err := r.LastInsertId()
	return id, true, err
}

// ListEnabled 启用中的任务配置。
func (m *TaskModel) ListEnabled(ctx context.Context) ([]*Task, error) {
	var rows []*Task
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, type, action, target_count, reward_youzhu, reward_exp, sort FROM `task` WHERE status = 1 ORDER BY type, sort, id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// Progresses 用户当期任务进度,返回 taskID -> log。
func (m *TaskModel) Progresses(ctx context.Context, uid int64, now time.Time) (map[int64]*UserTaskLog, error) {
	var rows []*UserTaskLog
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, user_id, task_id, DATE_FORMAT(day, '%Y-%m-%d') AS day, progress, status FROM `user_task_log` WHERE user_id = ? AND day IN (?, ?)",
		uid, now.Format(taskDayLayout), newbieDaySentinel)
	if err != nil {
		return nil, err
	}
	out := make(map[int64]*UserTaskLog, len(rows))
	for _, r := range rows {
		out[r.TaskID] = r
	}
	return out, nil
}

// IncrProgress 行为埋点:action 命中的启用任务进度 +1(封顶 target),达标自动置可领取。
// 失败只影响任务进度不阻塞业务主流程,由调用方记日志。
func (m *TaskModel) IncrProgress(ctx context.Context, uid int64, action string, now time.Time) error {
	tasks, err := m.ListEnabled(ctx)
	if err != nil {
		return fmt.Errorf("list tasks: %w", err)
	}
	for _, t := range tasks {
		if t.Action != action {
			continue
		}
		if _, err := m.conn.ExecCtx(ctx,
			`INSERT INTO user_task_log (user_id, task_id, day, progress, status)
			 VALUES (?, ?, ?, 1, IF(1 >= ?, 1, 0))
			 ON DUPLICATE KEY UPDATE
			   progress = LEAST(progress + 1, ?),
			   status = IF(status = 2, 2, IF(LEAST(progress, ?) >= ?, 1, 0))`,
			uid, t.ID, taskDay(t.Type, now), t.TargetCount,
			t.TargetCount, t.TargetCount, t.TargetCount); err != nil {
			return fmt.Errorf("task %d progress: %w", t.ID, err)
		}
	}
	return nil
}

// Claim 领取奖励:仅可领取(1)→已领取(2)一次生效,防并发重复领取。
func (m *TaskModel) Claim(ctx context.Context, uid, taskID int64, day string) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"UPDATE `user_task_log` SET status = ? WHERE user_id = ? AND task_id = ? AND day = ? AND status = ?",
		TaskStatusClaimed, uid, taskID, day, TaskStatusDone)
	if err != nil {
		return false, fmt.Errorf("claim task: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// SignIn 签到落库:唯一键防重复;continuous 由调用方按昨日快照算好传入。
// 返回 false 表示今天已签过。
func (m *TaskModel) SignIn(ctx context.Context, uid int64, day string, continuous, reward int64) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"INSERT IGNORE INTO `sign_in_log` (user_id, day, continuous, reward) VALUES (?, ?, ?, ?)",
		uid, day, continuous, reward)
	if err != nil {
		return false, fmt.Errorf("sign in: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// FindSign 某日签到记录。
func (m *TaskModel) FindSign(ctx context.Context, uid int64, day string) (*SignInLog, error) {
	var s SignInLog
	err := m.conn.QueryRowCtx(ctx, &s,
		"SELECT id, user_id, day, continuous, reward FROM `sign_in_log` WHERE user_id = ? AND day = ? LIMIT 1", uid, day)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// TaskDayOf 对外暴露任务归属日计算(logic 层组装领取幂等键用)。
func TaskDayOf(taskType int64, now time.Time) string { return taskDay(taskType, now) }
