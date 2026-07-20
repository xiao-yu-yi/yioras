// Package tasklogic 任务中心与签到:行为任务进度/领取、连签阶梯奖励,产出走忧珠幂等记账。
package tasklogic

import (
	"context"
	"fmt"
	"time"

	"github.com/yiora/server/internal/logic/growth"
	"github.com/yiora/server/internal/model"
	"github.com/yiora/server/internal/pkg/xerr"
	"github.com/yiora/server/internal/svc"
	"github.com/yiora/server/internal/types"

	"github.com/zeromicro/go-zero/core/logx"
)

// signLadder 连签 7 天一循环的阶梯奖励(第 8 天回到档位 1)。后台可配属运营配置,M3 取产品默认值。
var signLadder = [7]int64{5, 5, 10, 10, 15, 15, 30}

func ladderReward(continuous int64) int64 {
	if continuous < 1 {
		continuous = 1
	}
	return signLadder[(continuous-1)%7]
}

const dayLayout = "2006-01-02"

type Logic struct {
	svcCtx *svc.ServiceContext
}

func New(svcCtx *svc.ServiceContext) *Logic { return &Logic{svcCtx: svcCtx} }

// List 任务中心:行为任务进度 + 签到状态。
func (l *Logic) List(ctx context.Context, uid int64) (*types.TasksResp, error) {
	now := time.Now()
	tasks, err := l.svcCtx.TaskModel.ListEnabled(ctx)
	if err != nil {
		return nil, fmt.Errorf("list tasks: %w", err)
	}
	progresses, err := l.svcCtx.TaskModel.Progresses(ctx, uid, now)
	if err != nil {
		return nil, fmt.Errorf("task progresses: %w", err)
	}
	resp := &types.TasksResp{Tasks: make([]types.TaskItem, 0, len(tasks))}
	for _, t := range tasks {
		item := types.TaskItem{
			ID: t.ID, Name: t.Name, Type: t.Type, Action: t.Action,
			Target: t.TargetCount, RewardYouzhu: t.RewardYouzhu, RewardExp: t.RewardExp,
		}
		if p := progresses[t.ID]; p != nil {
			item.Progress, item.Status = p.Progress, p.Status
		}
		resp.Tasks = append(resp.Tasks, item)
	}

	signed, cont, err := l.signState(ctx, uid, now)
	if err != nil {
		return nil, err
	}
	resp.SignedToday, resp.Continuous = signed, cont
	resp.NextReward = ladderReward(cont + 1)
	return resp, nil
}

// SignIn 签到:唯一键防重复 → 连签快照 → 阶梯奖励幂等入账。
func (l *Logic) SignIn(ctx context.Context, uid int64) (*types.SignInResp, error) {
	now := time.Now()
	today := now.Format(dayLayout)
	yesterday := now.AddDate(0, 0, -1).Format(dayLayout)

	continuous := int64(1)
	if prev, err := l.svcCtx.TaskModel.FindSign(ctx, uid, yesterday); err == nil {
		continuous = prev.Continuous + 1
	} else if !model.IsNotFound(err) {
		return nil, fmt.Errorf("find yesterday sign: %w", err)
	}
	reward := ladderReward(continuous)

	ok, err := l.svcCtx.TaskModel.SignIn(ctx, uid, today, continuous, reward)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, xerr.New(xerr.CodeTooFrequent, "今天已经签过到了")
	}
	// biz_key 幂等:签到落库成功但入账失败时,客户端重试由重放兜底不重复加钱
	if _, err := l.svcCtx.YouzhuModel.Change(ctx, uid, model.YouzhuBizSignIn,
		fmt.Sprintf("sign:%d:%s", uid, today), reward, "每日签到"); err != nil {
		return nil, fmt.Errorf("sign credit: %w", err)
	}
	// 签到经验(权重后台可配 exp.sign,受每日上限约束)
	growth.Grant(ctx, l.svcCtx, uid, growth.KindSign)
	balance, err := l.svcCtx.YouzhuModel.Balance(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("balance: %w", err)
	}
	return &types.SignInResp{Reward: reward, Continuous: continuous, Balance: balance}, nil
}

// Claim 领取任务奖励。先幂等入账再置已领取:任一步骤失败重试都不会多发。
func (l *Logic) Claim(ctx context.Context, uid, taskID int64) (*types.ClaimResp, error) {
	now := time.Now()
	tasks, err := l.svcCtx.TaskModel.ListEnabled(ctx)
	if err != nil {
		return nil, fmt.Errorf("list tasks: %w", err)
	}
	var task *model.Task
	for _, t := range tasks {
		if t.ID == taskID {
			task = t
			break
		}
	}
	if task == nil {
		return nil, xerr.New(xerr.CodeNotFound, "任务不存在")
	}
	day := model.TaskDayOf(task.Type, now)
	progresses, err := l.svcCtx.TaskModel.Progresses(ctx, uid, now)
	if err != nil {
		return nil, fmt.Errorf("task progresses: %w", err)
	}
	p := progresses[taskID]
	if p == nil || p.Status == model.TaskStatusDoing {
		return nil, xerr.New(xerr.CodeForbidden, "任务还未完成")
	}
	if p.Status == model.TaskStatusClaimed {
		return nil, xerr.New(xerr.CodeTooFrequent, "奖励已领取")
	}

	if task.RewardYouzhu > 0 {
		if _, err := l.svcCtx.YouzhuModel.Change(ctx, uid, model.YouzhuBizTask,
			fmt.Sprintf("task:%d:%d:%s", uid, taskID, day), task.RewardYouzhu, task.Name); err != nil {
			return nil, fmt.Errorf("task credit: %w", err)
		}
	}
	ok, err := l.svcCtx.TaskModel.Claim(ctx, uid, taskID, day)
	if err != nil {
		return nil, err
	}
	if !ok { // 并发领取输掉 CAS:钱由同 biz_key 保证只入一次,直接按已领取报
		return nil, xerr.New(xerr.CodeTooFrequent, "奖励已领取")
	}
	if task.RewardExp > 0 {
		// 任务经验按任务配置数值发放,不占行为经验日上限(任务本身有每日完成次数约束)
		if err := l.svcCtx.UserModel.AddExp(ctx, uid, task.RewardExp); err != nil {
			logx.WithContext(ctx).Errorf("task %d exp: %v", taskID, err)
		}
	}
	balance, err := l.svcCtx.YouzhuModel.Balance(ctx, uid)
	if err != nil {
		return nil, fmt.Errorf("balance: %w", err)
	}
	return &types.ClaimResp{Reward: task.RewardYouzhu, Balance: balance}, nil
}

// signState 今日是否已签与当前连签天数(未签今天=截至昨天)。
func (l *Logic) signState(ctx context.Context, uid int64, now time.Time) (signed bool, continuous int64, err error) {
	today := now.Format(dayLayout)
	if s, err := l.svcCtx.TaskModel.FindSign(ctx, uid, today); err == nil {
		return true, s.Continuous, nil
	} else if !model.IsNotFound(err) {
		return false, 0, fmt.Errorf("find today sign: %w", err)
	}
	yesterday := now.AddDate(0, 0, -1).Format(dayLayout)
	if s, err := l.svcCtx.TaskModel.FindSign(ctx, uid, yesterday); err == nil {
		return false, s.Continuous, nil
	} else if !model.IsNotFound(err) {
		return false, 0, fmt.Errorf("find yesterday sign: %w", err)
	}
	return false, 0, nil
}
