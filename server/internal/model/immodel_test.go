package model

import (
	"context"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

func newMockIM(t *testing.T) (*IMModel, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return NewIMModel(sqlx.NewSqlConnFromDB(db)), mock
}

// TestAppendMessageSeq 验证发消息事务:seq 原子递增、消息按取到的 seq 落库、双方成员行维护。
func TestAppendMessageSeq(t *testing.T) {
	m, mock := newMockIM(t)

	const convID, sender, peer, nextSeq = int64(7), int64(1), int64(2), int64(5)

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE `conversation` SET last_msg_seq = last_msg_seq \\+ 1").
		WithArgs("你好", convID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT last_msg_seq FROM `conversation` WHERE id = \\?").
		WithArgs(convID).
		WillReturnRows(sqlmock.NewRows([]string{"last_msg_seq"}).AddRow(nextSeq))
	mock.ExpectExec("INSERT INTO `message`").
		WithArgs(convID, nextSeq, sender, int64(1), "你好").
		WillReturnResult(sqlmock.NewResult(100, 1))
	// 发送方成员行:已读推进到本条
	mock.ExpectExec("INSERT INTO `conversation_member`").
		WithArgs(convID, sender, nextSeq, nextSeq).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery("SELECT id, user_min, user_max").
		WithArgs(convID).
		WillReturnRows(sqlmock.NewRows(
			[]string{"id", "user_min", "user_max", "last_msg_seq", "last_preview", "last_msg_at", "created_at", "updated_at"}).
			AddRow(convID, sender, peer, nextSeq, "你好", nil, testTime(), testTime()))
	// 接收方成员行:deleted 复位
	mock.ExpectExec("INSERT INTO `conversation_member`").
		WithArgs(convID, peer).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	msg, err := m.AppendMessage(context.Background(), convID, sender, 1, "你好", "你好")
	if err != nil {
		t.Fatalf("AppendMessage: %v", err)
	}
	if msg.Seq != nextSeq {
		t.Fatalf("seq = %d, want %d", msg.Seq, nextSeq)
	}
	if msg.ID != 100 || msg.ConversationID != convID || msg.SenderID != sender {
		t.Fatalf("unexpected message: %+v", msg)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestAppendMessageConvNotFound 会话不存在时事务回滚,不落任何消息。
func TestAppendMessageConvNotFound(t *testing.T) {
	m, mock := newMockIM(t)

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE `conversation` SET last_msg_seq = last_msg_seq \\+ 1").
		WithArgs("hi", int64(404)).
		WillReturnResult(sqlmock.NewResult(0, 0)) // 0 行命中
	mock.ExpectRollback()

	if _, err := m.AppendMessage(context.Background(), 404, 1, 1, "hi", "hi"); err == nil {
		t.Fatal("会话不存在应返回错误")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}
