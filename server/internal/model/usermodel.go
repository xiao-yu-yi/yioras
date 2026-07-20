package model

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

var ErrNotFound = sqlx.ErrNotFound

type (
	User struct {
		ID        int64          `db:"id"`
		DisplayNo sql.NullString `db:"display_no"`
		Nickname  string         `db:"nickname"`
		Avatar    string         `db:"avatar"`
		Cover     string         `db:"cover"`
		Signature string         `db:"signature"`
		Gender    int64          `db:"gender"`
		Birthday  sql.NullTime   `db:"birthday"`
		Level     int64          `db:"level"`
		Exp       int64          `db:"exp"`
		Status    int64          `db:"status"`
		TeenMode  int64          `db:"teen_mode"`
		PushPrefs int64          `db:"push_prefs"`
		CreatedAt time.Time      `db:"created_at"`
		UpdatedAt time.Time      `db:"updated_at"`
	}

	UserAuth struct {
		ID           int64        `db:"id"`
		UserID       int64        `db:"user_id"`
		Email        string       `db:"email"`
		PasswordHash string       `db:"password_hash"`
		LastLoginAt  sql.NullTime `db:"last_login_at"`
		LastLoginIP  string       `db:"last_login_ip"`
		CreatedAt    time.Time    `db:"created_at"`
		UpdatedAt    time.Time    `db:"updated_at"`
	}

	UserModel struct {
		conn sqlx.SqlConn
	}
)

func NewUserModel(conn sqlx.SqlConn) *UserModel { return &UserModel{conn: conn} }

// CreateWithEmail 同事务创建 user + user_auth,并回填 display_no = "N"+id。
// 邮箱唯一性由 uk_email 兜底,并发重复注册以约束冲突为准。
func (m *UserModel) CreateWithEmail(ctx context.Context, nickname, email, passwordHash string) (int64, error) {
	var uid int64
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx, "INSERT INTO `user` (nickname) VALUES (?)", nickname)
		if err != nil {
			return fmt.Errorf("insert user: %w", err)
		}
		uid, err = r.LastInsertId()
		if err != nil {
			return fmt.Errorf("last insert id: %w", err)
		}
		if _, err = s.ExecCtx(ctx, "UPDATE `user` SET display_no = CONCAT('N', id) WHERE id = ?", uid); err != nil {
			return fmt.Errorf("backfill display_no: %w", err)
		}
		if _, err = s.ExecCtx(ctx,
			"INSERT INTO `user_auth` (user_id, email, password_hash) VALUES (?, ?, ?)",
			uid, email, passwordHash); err != nil {
			return fmt.Errorf("insert user_auth: %w", err)
		}
		return nil
	})
	return uid, err
}

func (m *UserModel) FindAuthByEmail(ctx context.Context, email string) (*UserAuth, error) {
	var a UserAuth
	err := m.conn.QueryRowCtx(ctx, &a,
		"SELECT id, user_id, email, password_hash, last_login_at, last_login_ip, created_at, updated_at FROM `user_auth` WHERE email = ? LIMIT 1", email)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

func (m *UserModel) FindByID(ctx context.Context, id int64) (*User, error) {
	var u User
	err := m.conn.QueryRowCtx(ctx, &u,
		"SELECT id, display_no, nickname, avatar, cover, signature, gender, birthday, level, exp, status, teen_mode, push_prefs, created_at, updated_at FROM `user` WHERE id = ? LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// FindAuthByUID 按用户 ID 取登录凭证(注销/改密的密码确认用)。
func (m *UserModel) FindAuthByUID(ctx context.Context, uid int64) (*UserAuth, error) {
	var a UserAuth
	err := m.conn.QueryRowCtx(ctx, &a,
		"SELECT id, user_id, email, password_hash, last_login_at, last_login_ip, created_at, updated_at FROM `user_auth` WHERE user_id = ? LIMIT 1", uid)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// UpdatePassword 重置密码(找回/改密共用)。
func (m *UserModel) UpdatePassword(ctx context.Context, uid int64, passwordHash string) error {
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `user_auth` SET password_hash = ? WHERE user_id = ?", passwordHash, uid); err != nil {
		return fmt.Errorf("update password: %w", err)
	}
	return nil
}

// Deactivate 注销账号(status=4);邮箱保留不释放(防止身份复用纠纷)。
// 离线推送开关位(user.push_prefs)
const (
	PushPrefDM       = 1 // 私信
	PushPrefInteract = 2 // 点赞/评论互动
	PushPrefSystem   = 4 // 系统通知
)

// SetPushPrefs 覆盖推送偏好位。
func (m *UserModel) SetPushPrefs(ctx context.Context, uid int64, prefs int64) error {
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `user` SET push_prefs = ? WHERE id = ?", prefs, uid); err != nil {
		return fmt.Errorf("set push prefs: %w", err)
	}
	return nil
}

// PushPrefs 单查偏好位(推送切面高频用,只取一列)。
func (m *UserModel) PushPrefs(ctx context.Context, uid int64) (int64, error) {
	var prefs int64
	err := m.conn.QueryRowCtx(ctx, &prefs, "SELECT push_prefs FROM `user` WHERE id = ? LIMIT 1", uid)
	return prefs, err
}

// NextLevelNeed 升到 level+1 所需累计经验;已是最高档返回 0(客户端进度条分母)。
func (m *UserModel) NextLevelNeed(ctx context.Context, level int64) (int64, error) {
	var need int64
	err := m.conn.QueryRowCtx(ctx, &need,
		"SELECT need_exp FROM `level_rule` WHERE level = ? LIMIT 1", level+1)
	if err != nil {
		if IsNotFound(err) {
			return 0, nil
		}
		return 0, err
	}
	return need, nil
}

// SetTeenMode 青少年模式开关。
func (m *UserModel) SetTeenMode(ctx context.Context, uid int64, on bool) error {
	v := 0
	if on {
		v = 1
	}
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `user` SET teen_mode = ? WHERE id = ?", v, uid); err != nil {
		return fmt.Errorf("set teen mode: %w", err)
	}
	return nil
}

func (m *UserModel) Deactivate(ctx context.Context, uid int64) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"UPDATE `user` SET status = 4 WHERE id = ? AND status != 4", uid)
	if err != nil {
		return false, fmt.Errorf("deactivate: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

func (m *UserModel) TouchLogin(ctx context.Context, uid int64, ip string) error {
	// X-Forwarded-For 可能含多个 IP,超出列宽截断,避免 strict 模式下整条 UPDATE 失败
	if len(ip) > 45 {
		ip = ip[:45]
	}
	_, err := m.conn.ExecCtx(ctx,
		"UPDATE `user_auth` SET last_login_at = NOW(3), last_login_ip = ? WHERE user_id = ?", ip, uid)
	return err
}

// profileColumns 资料编辑允许更新的列白名单(SET 子句列名只能来自这里,值全部走占位符)。
var profileColumns = map[string]bool{
	"nickname": true, "avatar": true, "cover": true,
	"signature": true, "gender": true, "birthday": true,
}

// UpdateProfile 按白名单字段更新资料。fields 为空直接返回。
func (m *UserModel) UpdateProfile(ctx context.Context, uid int64, fields map[string]any) error {
	if len(fields) == 0 {
		return nil
	}
	set := make([]string, 0, len(fields))
	args := make([]any, 0, len(fields)+1)
	for col, v := range fields {
		if !profileColumns[col] {
			return fmt.Errorf("column %q not updatable", col)
		}
		set = append(set, fmt.Sprintf("`%s` = ?", col))
		args = append(args, v)
	}
	args = append(args, uid)
	q := fmt.Sprintf("UPDATE `user` SET %s WHERE id = ?", strings.Join(set, ", "))
	if _, err := m.conn.ExecCtx(ctx, q, args...); err != nil {
		return fmt.Errorf("update profile: %w", err)
	}
	return nil
}

// AddExp 增加经验并按 level_rule 阈值重算等级,同事务。
func (m *UserModel) AddExp(ctx context.Context, uid int64, exp int64) error {
	if exp <= 0 {
		return nil
	}
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := s.ExecCtx(ctx,
			"UPDATE `user` SET exp = exp + ? WHERE id = ?", exp, uid); err != nil {
			return fmt.Errorf("add exp: %w", err)
		}
		// 单条 UPDATE 内子查询自表受限,分两步;行级无并发问题(同 uid 事务串行由 InnoDB 行锁保证)
		if _, err := s.ExecCtx(ctx,
			`UPDATE user u
			 JOIN (SELECT COALESCE(MAX(level), 0) AS lv FROM level_rule
			       WHERE need_exp <= (SELECT exp FROM (SELECT exp FROM user WHERE id = ?) t)) r
			 SET u.level = r.lv WHERE u.id = ? AND u.level != r.lv`, uid, uid); err != nil {
			return fmt.Errorf("recalc level: %w", err)
		}
		return nil
	})
}

// UserBrief 列表场景的作者/对端摘要(含佩戴中的头像框,装扮全站渲染)。
type UserBrief struct {
	ID          int64          `db:"id"`
	DisplayNo   sql.NullString `db:"display_no"`
	Nickname    string         `db:"nickname"`
	Avatar      string         `db:"avatar"`
	Level       int64          `db:"level"`
	AvatarFrame string         `db:"avatar_frame"`
}

// FindBriefs 批量取用户摘要,返回 uid -> brief。
// 子查询取佩戴中且未过期的头像框(Wear 保证同 kind 至多一件,行数不放大)。
func (m *UserModel) FindBriefs(ctx context.Context, ids []int64) (map[int64]*UserBrief, error) {
	out := make(map[int64]*UserBrief, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	q, args := inQuery(
		`SELECT u.id, u.display_no, u.nickname, u.avatar, u.level, COALESCE(f.preview, '') AS avatar_frame
		 FROM `+"`user`"+` u
		 LEFT JOIN (
		   SELECT ud.user_id, d.preview FROM user_decoration ud
		   JOIN decoration d ON d.id = ud.decoration_id AND d.kind = 1
		   WHERE ud.worn = 1 AND (ud.expire_at IS NULL OR ud.expire_at > NOW(3))
		 ) f ON f.user_id = u.id
		 WHERE u.id IN (%s)`, ids)
	var rows []*UserBrief
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.ID] = r
	}
	return out, nil
}

func IsNotFound(err error) bool { return errors.Is(err, sqlx.ErrNotFound) }
