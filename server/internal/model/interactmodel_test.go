package model

import (
	"context"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

func testTime() time.Time { return time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC) }

func newMockInteract(t *testing.T) (*InteractModel, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return NewInteractModel(sqlx.NewSqlConnFromDB(db)), mock
}

// TestLikeIdempotent 首次点赞计数+1;重复点赞 INSERT IGNORE 不命中,不得重复加计数。
func TestLikeIdempotent(t *testing.T) {
	m, mock := newMockInteract(t)
	ctx := context.Background()

	// 首次:插入命中 → 计数 +1
	mock.ExpectBegin()
	mock.ExpectExec("INSERT IGNORE INTO `like_record`").
		WithArgs(int64(1), LikeTargetPost, int64(9)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("UPDATE `post` SET like_count = GREATEST\\(like_count \\+ \\?, 0\\)").
		WithArgs(int64(1), int64(9)).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	added, err := m.Like(ctx, 1, LikeTargetPost, 9)
	if err != nil || !added {
		t.Fatalf("first like added=%v err=%v, want true/nil", added, err)
	}

	// 重复:插入 0 行 → 不应再有 UPDATE
	mock.ExpectBegin()
	mock.ExpectExec("INSERT IGNORE INTO `like_record`").
		WithArgs(int64(1), LikeTargetPost, int64(9)).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectCommit()

	added, err = m.Like(ctx, 1, LikeTargetPost, 9)
	if err != nil || added {
		t.Fatalf("repeat like added=%v err=%v, want false/nil", added, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestLikeCommentBumpsCommentTable 点赞评论时计数落在 comment 表。
func TestLikeCommentBumpsCommentTable(t *testing.T) {
	m, mock := newMockInteract(t)

	mock.ExpectBegin()
	mock.ExpectExec("INSERT IGNORE INTO `like_record`").
		WithArgs(int64(1), LikeTargetComment, int64(3)).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("UPDATE `comment` SET like_count").
		WithArgs(int64(1), int64(3)).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if _, err := m.Like(context.Background(), 1, LikeTargetComment, 3); err != nil {
		t.Fatalf("like comment: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestUnlikeOnlyDecrementsWhenDeleted 未点赞过的取消操作不动计数。
func TestUnlikeOnlyDecrementsWhenDeleted(t *testing.T) {
	m, mock := newMockInteract(t)

	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM `like_record`").
		WithArgs(int64(1), LikeTargetPost, int64(9)).
		WillReturnResult(sqlmock.NewResult(0, 0)) // 本来就没赞过
	mock.ExpectCommit()

	if err := m.Unlike(context.Background(), 1, LikeTargetPost, 9); err != nil {
		t.Fatalf("unlike: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestCreateCommentPendingSkipsCounts 转人审评论不计入对象评论数。
func TestCreateCommentPendingSkipsCounts(t *testing.T) {
	m, mock := newMockInteract(t)

	mock.ExpectBegin()
	mock.ExpectExec("INSERT INTO `comment`").
		WithArgs(int64(CommentBizPost), int64(9), int64(1), int64(0), int64(0), int64(0), "疑似内容", int64(0)).
		WillReturnResult(sqlmock.NewResult(55, 1))
	mock.ExpectCommit()

	id, err := m.CreateComment(context.Background(), &Comment{
		BizType: CommentBizPost, BizID: 9, UserID: 1, Content: "疑似内容", Status: 0,
	})
	if err != nil || id != 55 {
		t.Fatalf("create pending comment id=%d err=%v", id, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

// TestCreateSoftwareCommentBumpsSoftware 软件评论计数落 software 表。
func TestCreateSoftwareCommentBumpsSoftware(t *testing.T) {
	m, mock := newMockInteract(t)

	mock.ExpectBegin()
	mock.ExpectExec("INSERT INTO `comment`").
		WithArgs(int64(CommentBizSoftware), int64(7), int64(1), int64(0), int64(0), int64(0), "好用", int64(1)).
		WillReturnResult(sqlmock.NewResult(56, 1))
	mock.ExpectExec("UPDATE `software` SET comment_count").
		WithArgs(int64(7)).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	id, err := m.CreateComment(context.Background(), &Comment{
		BizType: CommentBizSoftware, BizID: 7, UserID: 1, Content: "好用", Status: 1,
	})
	if err != nil || id != 56 {
		t.Fatalf("create software comment id=%d err=%v", id, err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}
