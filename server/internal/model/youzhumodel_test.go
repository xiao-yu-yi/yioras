package model

import (
	"context"
	"errors"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// TestYouzhuChangeNewAccount 首笔入账(账户不存在):先查未命中→INSERT IGNORE→再锁行。
func TestYouzhuChangeNewAccount(t *testing.T) {
	m, mock := newMockYouzhu(t)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT balance FROM `youzhu_account` WHERE user_id = \\? FOR UPDATE").
		WithArgs(int64(9)).
		WillReturnRows(sqlmock.NewRows([]string{"balance"})) // 空结果 → ErrNotFound
	mock.ExpectExec("INSERT IGNORE INTO `youzhu_account`").
		WithArgs(int64(9)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectQuery("SELECT balance FROM `youzhu_account` WHERE user_id = \\? FOR UPDATE").
		WithArgs(int64(9)).
		WillReturnRows(sqlmock.NewRows([]string{"balance"}).AddRow(0))
	mock.ExpectQuery("SELECT COUNT\\(1\\) FROM `youzhu_log` WHERE biz_key = \\?").
		WithArgs("sign:9:d1").
		WillReturnRows(sqlmock.NewRows([]string{"n"}).AddRow(0))
	mock.ExpectExec("INSERT INTO `youzhu_log`").
		WithArgs(int64(9), int64(YouzhuBizSignIn), "sign:9:d1", int64(5), int64(5), "每日签到").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("UPDATE `youzhu_account` SET balance = \\?").
		WithArgs(int64(5), int64(9)).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	applied, err := m.Change(context.Background(), 9, YouzhuBizSignIn, "sign:9:d1", 5, "每日签到")
	if err != nil || !applied {
		t.Fatalf("applied=%v err=%v, want true/nil", applied, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

func newMockYouzhu(t *testing.T) (*YouzhuModel, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return NewYouzhuModel(sqlx.NewSqlConnFromDB(db)), mock
}

// TestYouzhuChangeCredit 正常入账(账户已存在):锁行→查重→写流水(带入账后余额)→更余额。
func TestYouzhuChangeCredit(t *testing.T) {
	m, mock := newMockYouzhu(t)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT balance FROM `youzhu_account` WHERE user_id = \\? FOR UPDATE").
		WithArgs(int64(1)).
		WillReturnRows(sqlmock.NewRows([]string{"balance"}).AddRow(10))
	mock.ExpectQuery("SELECT COUNT\\(1\\) FROM `youzhu_log` WHERE biz_key = \\?").
		WithArgs("sign:1:2026-07-20").
		WillReturnRows(sqlmock.NewRows([]string{"n"}).AddRow(0))
	mock.ExpectExec("INSERT INTO `youzhu_log`").
		WithArgs(int64(1), int64(YouzhuBizSignIn), "sign:1:2026-07-20", int64(5), int64(15), "每日签到").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("UPDATE `youzhu_account` SET balance = \\?").
		WithArgs(int64(15), int64(1)).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	applied, err := m.Change(context.Background(), 1, YouzhuBizSignIn, "sign:1:2026-07-20", 5, "每日签到")
	if err != nil || !applied {
		t.Fatalf("applied=%v err=%v, want true/nil", applied, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestYouzhuChangeReplay 幂等重放:biz_key 已存在,不写流水不改余额,按成功返回。
func TestYouzhuChangeReplay(t *testing.T) {
	m, mock := newMockYouzhu(t)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT balance FROM `youzhu_account` WHERE user_id = \\? FOR UPDATE").
		WithArgs(int64(1)).
		WillReturnRows(sqlmock.NewRows([]string{"balance"}).AddRow(15))
	mock.ExpectQuery("SELECT COUNT\\(1\\) FROM `youzhu_log` WHERE biz_key = \\?").
		WithArgs("sign:1:2026-07-20").
		WillReturnRows(sqlmock.NewRows([]string{"n"}).AddRow(1)) // 已入过账
	mock.ExpectCommit()

	applied, err := m.Change(context.Background(), 1, YouzhuBizSignIn, "sign:1:2026-07-20", 5, "每日签到")
	if err != nil || applied {
		t.Fatalf("applied=%v err=%v, want false/nil (replay)", applied, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestYouzhuChangeInsufficient 余额不足:拒绝扣款并回滚。
func TestYouzhuChangeInsufficient(t *testing.T) {
	m, mock := newMockYouzhu(t)

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT balance FROM `youzhu_account` WHERE user_id = \\? FOR UPDATE").
		WithArgs(int64(1)).
		WillReturnRows(sqlmock.NewRows([]string{"balance"}).AddRow(3))
	mock.ExpectQuery("SELECT COUNT\\(1\\) FROM `youzhu_log` WHERE biz_key = \\?").
		WithArgs("exchange:1:99").
		WillReturnRows(sqlmock.NewRows([]string{"n"}).AddRow(0))
	mock.ExpectRollback()

	applied, err := m.Change(context.Background(), 1, YouzhuBizExchange, "exchange:1:99", -5, "兑换装扮")
	if !errors.Is(err, ErrInsufficientBalance) || applied {
		t.Fatalf("applied=%v err=%v, want false/ErrInsufficientBalance", applied, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}
