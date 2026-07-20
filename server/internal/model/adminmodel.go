package model

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

type (
	AdminUser struct {
		ID           int64  `db:"id"`
		Username     string `db:"username"`
		PasswordHash string `db:"password_hash"`
		RoleID       int64  `db:"role_id"`
		Status       int64  `db:"status"`
		TotpSecret   string `db:"totp_secret"`
		TotpEnabled  int64  `db:"totp_enabled"`
	}

	AuditItem struct {
		ID            int64     `db:"id"`
		BizType       int64     `db:"biz_type"`
		BizID         int64     `db:"biz_id"`
		MachineResult int64     `db:"machine_result"`
		MachineDetail string    `db:"machine_detail"`
		Status        int64     `db:"status"`
		CreatedAt     time.Time `db:"created_at"`
	}

	AdminModel struct{ conn sqlx.SqlConn }
)

func NewAdminModel(conn sqlx.SqlConn) *AdminModel { return &AdminModel{conn: conn} }

const adminUserCols = "id, username, password_hash, role_id, status, totp_secret, totp_enabled"

func (m *AdminModel) FindByUsername(ctx context.Context, username string) (*AdminUser, error) {
	var a AdminUser
	err := m.conn.QueryRowCtx(ctx, &a,
		"SELECT "+adminUserCols+" FROM `admin_user` WHERE username = ? LIMIT 1", username)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

func (m *AdminModel) FindAdminByID(ctx context.Context, id int64) (*AdminUser, error) {
	var a AdminUser
	err := m.conn.QueryRowCtx(ctx, &a,
		"SELECT "+adminUserCols+" FROM `admin_user` WHERE id = ? LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// EnableTotp 落库启用二步验证:写 secret + 重建恢复码(哈希),同事务。
func (m *AdminModel) EnableTotp(ctx context.Context, adminID int64, secret string, codeHashes []string) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := s.ExecCtx(ctx,
			"UPDATE `admin_user` SET totp_secret = ?, totp_enabled = 1 WHERE id = ?", secret, adminID); err != nil {
			return fmt.Errorf("enable totp: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"DELETE FROM `admin_recovery_code` WHERE admin_id = ?", adminID); err != nil {
			return fmt.Errorf("clear recovery codes: %w", err)
		}
		for _, h := range codeHashes {
			if _, err := s.ExecCtx(ctx,
				"INSERT INTO `admin_recovery_code` (admin_id, code_hash) VALUES (?, ?)", adminID, h); err != nil {
				return fmt.Errorf("insert recovery code: %w", err)
			}
		}
		return nil
	})
}

// DisableTotp 解绑二步验证并清空恢复码。
func (m *AdminModel) DisableTotp(ctx context.Context, adminID int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := s.ExecCtx(ctx,
			"UPDATE `admin_user` SET totp_secret = '', totp_enabled = 0 WHERE id = ?", adminID); err != nil {
			return fmt.Errorf("disable totp: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"DELETE FROM `admin_recovery_code` WHERE admin_id = ?", adminID); err != nil {
			return fmt.Errorf("clear recovery codes: %w", err)
		}
		return nil
	})
}

// UseRecoveryCode 消费恢复码(CAS 置 used_at,一次性)。返回 true=命中有效码。
func (m *AdminModel) UseRecoveryCode(ctx context.Context, adminID int64, codeHash string) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"UPDATE `admin_recovery_code` SET used_at = NOW(3) WHERE admin_id = ? AND code_hash = ? AND used_at IS NULL LIMIT 1",
		adminID, codeHash)
	if err != nil {
		return false, fmt.Errorf("use recovery code: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// RecoveryCodesLeft 剩余可用恢复码数(安全设置页展示)。
func (m *AdminModel) RecoveryCodesLeft(ctx context.Context, adminID int64) (int64, error) {
	var n int64
	err := m.conn.QueryRowCtx(ctx, &n,
		"SELECT COUNT(1) FROM `admin_recovery_code` WHERE admin_id = ? AND used_at IS NULL", adminID)
	return n, err
}

// UpdateAdminPassword 管理员改密。
func (m *AdminModel) UpdateAdminPassword(ctx context.Context, adminID int64, hash string) error {
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `admin_user` SET password_hash = ? WHERE id = ?", hash, adminID); err != nil {
		return fmt.Errorf("update admin password: %w", err)
	}
	return nil
}

// AdminAccountRow 账号管理列表行。
type AdminAccountRow struct {
	ID          int64        `db:"id"`
	Username    string       `db:"username"`
	RoleID      int64        `db:"role_id"`
	RoleName    string       `db:"role_name"`
	Status      int64        `db:"status"`
	LastLoginAt sql.NullTime `db:"last_login_at"`
}

func (m *AdminModel) ListAdmins(ctx context.Context) ([]*AdminAccountRow, error) {
	var rows []*AdminAccountRow
	err := m.conn.QueryRowsCtx(ctx, &rows,
		`SELECT a.id, a.username, a.role_id, COALESCE(r.name, '') AS role_name, a.status, a.last_login_at
		 FROM admin_user a LEFT JOIN admin_role r ON r.id = a.role_id ORDER BY a.id`)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// CreateAdmin 新建后台账号。用户名撞唯一键返回 ErrAdminExists。
func (m *AdminModel) CreateAdmin(ctx context.Context, username, hash string, roleID int64) (int64, error) {
	r, err := m.conn.ExecCtx(ctx,
		"INSERT IGNORE INTO `admin_user` (username, password_hash, role_id) VALUES (?, ?, ?)",
		username, hash, roleID)
	if err != nil {
		return 0, fmt.Errorf("create admin: %w", err)
	}
	if n, _ := r.RowsAffected(); n == 0 {
		return 0, ErrAdminExists
	}
	return r.LastInsertId()
}

// ErrAdminExists 后台用户名已存在。
var ErrAdminExists = fmt.Errorf("admin username exists")

// UpdateAdmin 调整角色/启停/重置密码(hash 非空时置强制改密)。零值参数跳过对应列。
func (m *AdminModel) UpdateAdmin(ctx context.Context, id, roleID, status int64, hash string) error {
	sets, args := []string{}, []any{}
	if roleID > 0 {
		sets = append(sets, "role_id = ?")
		args = append(args, roleID)
	}
	if status >= 0 {
		sets = append(sets, "status = ?")
		args = append(args, status)
	}
	if hash != "" {
		sets = append(sets, "password_hash = ?")
		args = append(args, hash)
	}
	if len(sets) == 0 {
		return nil
	}
	args = append(args, id)
	q := "UPDATE `admin_user` SET " + strings.Join(sets, ", ") + " WHERE id = ?"
	if _, err := m.conn.ExecCtx(ctx, q, args...); err != nil {
		return fmt.Errorf("update admin: %w", err)
	}
	return nil
}

// AdminRoleRow 角色行。
type AdminRoleRow struct {
	ID          int64  `db:"id"`
	Name        string `db:"name"`
	Permissions string `db:"permissions"`
}

func (m *AdminModel) ListRoles(ctx context.Context) ([]*AdminRoleRow, error) {
	var rows []*AdminRoleRow
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, permissions FROM `admin_role` ORDER BY id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// RolePerms 角色权限码列表(JSON 数组,含 "*" 为超管)。
func (m *AdminModel) RolePerms(ctx context.Context, roleID int64) ([]string, error) {
	var raw string
	err := m.conn.QueryRowCtx(ctx, &raw,
		"SELECT permissions FROM `admin_role` WHERE id = ? LIMIT 1", roleID)
	if err != nil {
		return nil, err
	}
	var perms []string
	if err := json.Unmarshal([]byte(raw), &perms); err != nil {
		return nil, fmt.Errorf("parse perms: %w", err)
	}
	return perms, nil
}

func (m *AdminModel) TouchLogin(ctx context.Context, adminID int64) {
	_, _ = m.conn.ExecCtx(ctx, "UPDATE `admin_user` SET last_login_at = NOW(3) WHERE id = ?", adminID)
}

// AddOpLog 敏感操作留痕(需求 3.12)。
func (m *AdminModel) AddOpLog(ctx context.Context, adminID int64, action, target, detail, ip string) error {
	var detailJSON any
	if detail != "" {
		detailJSON = detail
	}
	if _, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `admin_op_log` (admin_id, action, target, detail, ip) VALUES (?, ?, ?, ?, ?)",
		adminID, action, target, detailJSON, ip); err != nil {
		return fmt.Errorf("insert op log: %w", err)
	}
	return nil
}

// OpLogs 操作日志列表。
type OpLog struct {
	ID        int64     `db:"id"`
	AdminID   int64     `db:"admin_id"`
	Action    string    `db:"action"`
	Target    string    `db:"target"`
	IP        string    `db:"ip"`
	CreatedAt time.Time `db:"created_at"`
}

func (m *AdminModel) OpLogs(ctx context.Context, offset, limit int) ([]*OpLog, error) {
	var rows []*OpLog
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, admin_id, action, target, ip, created_at FROM `admin_op_log` ORDER BY id DESC LIMIT ?, ?", offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// PendingAudits 待人审队列。bizType=0 不筛。
func (m *AdminModel) PendingAudits(ctx context.Context, bizType int64, offset, limit int) ([]*AuditItem, error) {
	cond, args := "status = 0", []any{}
	if bizType > 0 {
		cond += " AND biz_type = ?"
		args = append(args, bizType)
	}
	args = append(args, offset, limit)
	var rows []*AuditItem
	q := fmt.Sprintf(
		"SELECT id, biz_type, biz_id, machine_result, COALESCE(machine_detail, '') AS machine_detail, status, created_at FROM `audit_queue` WHERE %s ORDER BY id LIMIT ?, ?", cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

func (m *AdminModel) FindAudit(ctx context.Context, id int64) (*AuditItem, error) {
	var a AuditItem
	err := m.conn.QueryRowCtx(ctx, &a,
		"SELECT id, biz_type, biz_id, machine_result, COALESCE(machine_detail, '') AS machine_detail, status, created_at FROM `audit_queue` WHERE id = ? LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// DecidePost 帖子人审落地:过审=发布+圈子/话题计数补记,驳回=状态+原因。返回作者(通知用)。
func (m *AdminModel) DecidePost(ctx context.Context, auditID, postID, adminID int64, approve bool, reason string) (authorID int64, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if err := claimAudit(ctx, s, auditID, adminID, approve, reason); err != nil {
			return err
		}
		var row struct {
			UserID   int64 `db:"user_id"`
			Status   int64 `db:"status"`
			CircleID int64 `db:"circle_id"`
		}
		if err := s.QueryRowCtx(ctx, &row,
			"SELECT user_id, status, circle_id FROM `post` WHERE id = ? LIMIT 1 FOR UPDATE", postID); err != nil {
			return fmt.Errorf("load post: %w", err)
		}
		authorID = row.UserID
		if row.Status != PostStatusPending {
			return nil // 已被其他动作处理(作者删除等),仅结单
		}
		if approve {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `post` SET status = ? WHERE id = ?", PostStatusPublished, postID); err != nil {
				return fmt.Errorf("approve post: %w", err)
			}
			if _, err := s.ExecCtx(ctx,
				"UPDATE `circle` SET post_count = post_count + 1 WHERE id = ?", row.CircleID); err != nil {
				return fmt.Errorf("circle count: %w", err)
			}
			if _, err := s.ExecCtx(ctx,
				`UPDATE topic t JOIN post_topic pt ON pt.topic_id = t.id
				 SET t.post_count = t.post_count + 1 WHERE pt.post_id = ?`, postID); err != nil {
				return fmt.Errorf("topic count: %w", err)
			}
			return nil
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `post` SET status = ?, reject_reason = ? WHERE id = ?", PostStatusRejected, reason, postID); err != nil {
			return fmt.Errorf("reject post: %w", err)
		}
		return nil
	})
	return authorID, err
}

// DecideComment 评论人审落地:过审=发布+对象计数/楼层回复数补记,驳回=违规屏蔽。
func (m *AdminModel) DecideComment(ctx context.Context, auditID, commentID, adminID int64, approve bool, reason string) (authorID int64, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if err := claimAudit(ctx, s, auditID, adminID, approve, reason); err != nil {
			return err
		}
		var row struct {
			UserID  int64 `db:"user_id"`
			Status  int64 `db:"status"`
			BizType int64 `db:"biz_type"`
			BizID   int64 `db:"biz_id"`
			RootID  int64 `db:"root_id"`
		}
		if err := s.QueryRowCtx(ctx, &row,
			"SELECT user_id, status, biz_type, biz_id, root_id FROM `comment` WHERE id = ? LIMIT 1 FOR UPDATE", commentID); err != nil {
			return fmt.Errorf("load comment: %w", err)
		}
		authorID = row.UserID
		if row.Status != 0 {
			return nil
		}
		if approve {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `comment` SET status = 1 WHERE id = ?", commentID); err != nil {
				return fmt.Errorf("approve comment: %w", err)
			}
			table := "post"
			if row.BizType == CommentBizSoftware {
				table = "software"
			}
			if _, err := s.ExecCtx(ctx,
				fmt.Sprintf("UPDATE `%s` SET comment_count = comment_count + 1 WHERE id = ?", table), row.BizID); err != nil {
				return fmt.Errorf("comment count: %w", err)
			}
			if row.RootID > 0 {
				if _, err := s.ExecCtx(ctx,
					"UPDATE `comment` SET reply_count = reply_count + 1 WHERE id = ?", row.RootID); err != nil {
					return fmt.Errorf("reply count: %w", err)
				}
			}
			return nil
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `comment` SET status = 2 WHERE id = ?", commentID); err != nil {
			return fmt.Errorf("reject comment: %w", err)
		}
		return nil
	})
	return authorID, err
}

// DecideSoftware 软件/版本人审落地:
// kind=software 过审=软件上架+首版本发布+latest_version_id 回填;kind=version 过审=版本发布+latest_version_id 前移。
func (m *AdminModel) DecideSoftware(ctx context.Context, auditID, softwareID, versionID, adminID int64, kind string, approve bool, reason string) (authorID int64, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if err := claimAudit(ctx, s, auditID, adminID, approve, reason); err != nil {
			return err
		}
		var row struct {
			UserID int64 `db:"user_id"`
			Status int64 `db:"status"`
		}
		if err := s.QueryRowCtx(ctx, &row,
			"SELECT user_id, status FROM `software` WHERE id = ? LIMIT 1 FOR UPDATE", softwareID); err != nil {
			return fmt.Errorf("load software: %w", err)
		}
		authorID = row.UserID
		if approve {
			if versionID > 0 {
				if _, err := s.ExecCtx(ctx,
					"UPDATE `software_version` SET status = ? WHERE id = ? AND software_id = ?",
					VersionStatusPublished, versionID, softwareID); err != nil {
					return fmt.Errorf("approve version: %w", err)
				}
			}
			if kind == "software" {
				if _, err := s.ExecCtx(ctx,
					"UPDATE `software` SET status = ?, latest_version_id = ? WHERE id = ?",
					SoftwareStatusOnline, versionID, softwareID); err != nil {
					return fmt.Errorf("approve software: %w", err)
				}
			} else if versionID > 0 {
				if _, err := s.ExecCtx(ctx,
					"UPDATE `software` SET latest_version_id = ? WHERE id = ?", versionID, softwareID); err != nil {
					return fmt.Errorf("bump latest version: %w", err)
				}
			}
			return nil
		}
		if kind == "software" {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `software` SET status = ?, reject_reason = ? WHERE id = ?",
				SoftwareStatusRejected, reason, softwareID); err != nil {
				return fmt.Errorf("reject software: %w", err)
			}
		}
		if versionID > 0 {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `software_version` SET status = ?, reject_reason = ? WHERE id = ? AND software_id = ?",
				VersionStatusRejected, reason, versionID, softwareID); err != nil {
				return fmt.Errorf("reject version: %w", err)
			}
		}
		return nil
	})
	return authorID, err
}

// claimAudit 结单(CAS 防并发重复审核)。
func claimAudit(ctx context.Context, s sqlx.Session, auditID, adminID int64, approve bool, reason string) error {
	to := 1
	if !approve {
		to = 2
	}
	r, err := s.ExecCtx(ctx,
		"UPDATE `audit_queue` SET status = ?, reason = ?, auditor_id = ?, audited_at = NOW(3) WHERE id = ? AND status = 0",
		to, reason, adminID, auditID)
	if err != nil {
		return fmt.Errorf("claim audit: %w", err)
	}
	if n, _ := r.RowsAffected(); n != 1 {
		return ErrAuditDone
	}
	return nil
}

// ErrAuditDone 审核单已被处理。
var ErrAuditDone = fmt.Errorf("audit already decided")

// PendingCerts 待审认证。
func (m *AdminModel) PendingCerts(ctx context.Context, offset, limit int) ([]*Certification, error) {
	var rows []*Certification
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, user_id, kind, material, status, reason, created_at, updated_at FROM `certification` WHERE status = 0 ORDER BY id LIMIT ?, ?", offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// DecideCert 认证过审/驳回(CAS)。返回申请者。
func (m *AdminModel) DecideCert(ctx context.Context, certID int64, approve bool, reason string) (userID, kind int64, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var row struct {
			UserID int64 `db:"user_id"`
			Kind   int64 `db:"kind"`
		}
		if err := s.QueryRowCtx(ctx, &row,
			"SELECT user_id, kind FROM `certification` WHERE id = ? LIMIT 1 FOR UPDATE", certID); err != nil {
			return err
		}
		userID, kind = row.UserID, row.Kind
		to := CertStatusApproved
		if !approve {
			to = CertStatusRejected
		}
		r, err := s.ExecCtx(ctx,
			"UPDATE `certification` SET status = ?, reason = ? WHERE id = ? AND status = 0", to, reason, certID)
		if err != nil {
			return fmt.Errorf("decide cert: %w", err)
		}
		if n, _ := r.RowsAffected(); n != 1 {
			return ErrAuditDone
		}
		return nil
	})
	return userID, kind, err
}

// PublishNotice 公告落库并群发系统通知(单 SQL 扇出;十万级以上用户改 MQ 分批,见需求 4.2)。
func (m *AdminModel) PublishNotice(ctx context.Context, adminID int64, title, content string) (int64, error) {
	var noticeID int64
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT INTO `notice` (title, content, created_by) VALUES (?, ?, ?)", title, content, adminID)
		if err != nil {
			return fmt.Errorf("insert notice: %w", err)
		}
		if noticeID, err = r.LastInsertId(); err != nil {
			return fmt.Errorf("notice id: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			fmt.Sprintf(`INSERT INTO notification (user_id, type, content)
			 SELECT id, %d, ? FROM user WHERE status = 1 AND id != %d`, NotifyTypeSystem, BotUID),
			title); err != nil {
			return fmt.Errorf("fanout notice: %w", err)
		}
		return nil
	})
	return noticeID, err
}

// 全站处置(user.status):1正常 2禁言 3封禁
const (
	UserStatusNormal = 1
	UserStatusMuted  = 2
	UserStatusBanned = 3
)

// AdminUserRow 后台用户列表行(含登录凭证侧信息,仅 user.ban 权限可见)。
type AdminUserRow struct {
	ID          int64        `db:"id"`
	DisplayNo   string       `db:"display_no"`
	Nickname    string       `db:"nickname"`
	Avatar      string       `db:"avatar"`
	Level       int64        `db:"level"`
	Status      int64        `db:"status"`
	CreatedAt   time.Time    `db:"created_at"`
	Email       string       `db:"email"`
	LastLoginAt sql.NullTime `db:"last_login_at"`
}

// SearchUsers 后台用户搜索:昵称/展示编号/邮箱模糊 + 状态筛选,新注册在前。
// keyword 为空则全量翻页;status=0 不筛。机器人账号不出现在处置列表。
func (m *AdminModel) SearchUsers(ctx context.Context, keyword string, status int64, offset, limit int) (int64, []*AdminUserRow, error) {
	cond := fmt.Sprintf("u.id != %d", BotUID)
	args := []any{}
	if status > 0 {
		cond += " AND u.status = ?"
		args = append(args, status)
	}
	if keyword != "" {
		p := escapeLike(keyword)
		cond += " AND (u.nickname LIKE ? OR u.display_no LIKE ? OR a.email LIKE ?)"
		args = append(args, p, p, p)
	}
	from := "FROM `user` u LEFT JOIN `user_auth` a ON a.user_id = u.id WHERE " + cond

	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) "+from, args...); err != nil {
		return 0, nil, fmt.Errorf("count users: %w", err)
	}
	var rows []*AdminUserRow
	q := `SELECT u.id, COALESCE(u.display_no, '') AS display_no, u.nickname, u.avatar, u.level, u.status,
		u.created_at, COALESCE(a.email, '') AS email, a.last_login_at ` + from + " ORDER BY u.id DESC LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("search users: %w", err)
	}
	return total, rows, nil
}

// AdminContentRow 后台内容检索行(帖子/评论统一形态,便于前端同表渲染)。
type AdminContentRow struct {
	ID         int64     `db:"id"`
	UserID     int64     `db:"user_id"`
	Nickname   string    `db:"nickname"`
	Title      string    `db:"title"`
	Content    string    `db:"content"`
	Status     int64     `db:"status"`
	CircleID   int64     `db:"circle_id"`
	BizType    int64     `db:"biz_type"`
	BizID      int64     `db:"biz_id"`
	IsTop      int64     `db:"is_top"`
	IsEssence  int64     `db:"is_essence"`
	LikeCount  int64     `db:"like_count"`
	ViewCount  int64     `db:"view_count"`
	FirstImage string    `db:"first_image"`
	CreatedAt  time.Time `db:"created_at"`
}

// SearchPostsAdmin 后台帖子检索:标题/正文模糊 + 全状态筛选(status<0 不筛),新帖在前。
func (m *AdminModel) SearchPostsAdmin(ctx context.Context, keyword string, status int64, offset, limit int) (int64, []*AdminContentRow, error) {
	cond, args := "1 = 1", []any{}
	if status >= 0 {
		cond += " AND p.status = ?"
		args = append(args, status)
	}
	if keyword != "" {
		p := escapeLike(keyword)
		cond += " AND (p.title LIKE ? OR p.content LIKE ?)"
		args = append(args, p, p)
	}
	from := "FROM `post` p JOIN `user` u ON u.id = p.user_id WHERE " + cond

	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) "+from, args...); err != nil {
		return 0, nil, fmt.Errorf("count posts: %w", err)
	}
	var rows []*AdminContentRow
	q := `SELECT p.id, p.user_id, u.nickname, p.title, p.content, p.status, p.circle_id,
		0 AS biz_type, 0 AS biz_id, p.is_top, p.is_essence, p.like_count, p.view_count,
		COALESCE((SELECT url FROM post_image i WHERE i.post_id = p.id ORDER BY i.sort LIMIT 1), '') AS first_image,
		p.created_at ` + from + " ORDER BY p.id DESC LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("search posts admin: %w", err)
	}
	return total, rows, nil
}

// SearchCommentsAdmin 后台评论检索:内容模糊 + 状态筛选(status<0 不筛)。
func (m *AdminModel) SearchCommentsAdmin(ctx context.Context, keyword string, status int64, offset, limit int) (int64, []*AdminContentRow, error) {
	cond, args := "1 = 1", []any{}
	if status >= 0 {
		cond += " AND c.status = ?"
		args = append(args, status)
	}
	if keyword != "" {
		cond += " AND c.content LIKE ?"
		args = append(args, escapeLike(keyword))
	}
	from := "FROM `comment` c JOIN `user` u ON u.id = c.user_id WHERE " + cond

	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) "+from, args...); err != nil {
		return 0, nil, fmt.Errorf("count comments: %w", err)
	}
	var rows []*AdminContentRow
	q := `SELECT c.id, c.user_id, u.nickname, '' AS title, c.content, c.status, 0 AS circle_id,
		c.biz_type, c.biz_id, 0 AS is_top, 0 AS is_essence, c.like_count, 0 AS view_count,
		'' AS first_image, c.created_at ` + from + " ORDER BY c.id DESC LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("search comments admin: %w", err)
	}
	return total, rows, nil
}

// TakedownPostByAdmin 后台下架帖(不限定圈子,区别于圈主 Takedown):
// 已发布→下架,清圈顶/加精标记,回减圈子与话题计数。返回作者;hit=false 表示当前状态不可下架。
func (m *AdminModel) TakedownPostByAdmin(ctx context.Context, postID int64) (authorID int64, hit bool, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		row, err := lockPost(ctx, s, postID)
		if err != nil || row == nil || row.Status != PostStatusPublished {
			return err
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `post` SET status = ?, circle_top = 0, is_essence = 0 WHERE id = ?", PostStatusTakenDown, postID); err != nil {
			return fmt.Errorf("takedown post: %w", err)
		}
		if err := bumpPostCounters(ctx, s, postID, row.CircleID, -1); err != nil {
			return err
		}
		authorID, hit = row.UserID, true
		return nil
	})
	return authorID, hit, err
}

// RestorePostByAdmin 后台恢复下架帖:下架→已发布,回补圈子与话题计数。
func (m *AdminModel) RestorePostByAdmin(ctx context.Context, postID int64) (authorID int64, hit bool, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		row, err := lockPost(ctx, s, postID)
		if err != nil || row == nil || row.Status != PostStatusTakenDown {
			return err
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `post` SET status = ? WHERE id = ?", PostStatusPublished, postID); err != nil {
			return fmt.Errorf("restore post: %w", err)
		}
		if err := bumpPostCounters(ctx, s, postID, row.CircleID, 1); err != nil {
			return err
		}
		authorID, hit = row.UserID, true
		return nil
	})
	return authorID, hit, err
}

type lockedPost struct {
	UserID   int64 `db:"user_id"`
	Status   int64 `db:"status"`
	CircleID int64 `db:"circle_id"`
}

func lockPost(ctx context.Context, s sqlx.Session, postID int64) (*lockedPost, error) {
	var row lockedPost
	err := s.QueryRowCtx(ctx, &row,
		"SELECT user_id, status, circle_id FROM `post` WHERE id = ? LIMIT 1 FOR UPDATE", postID)
	if err != nil {
		if IsNotFound(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("load post: %w", err)
	}
	return &row, nil
}

// bumpPostCounters 帖子可见性变化时同步圈子/话题发帖计数(delta=±1)。
func bumpPostCounters(ctx context.Context, s sqlx.Session, postID, circleID, delta int64) error {
	if _, err := s.ExecCtx(ctx,
		"UPDATE `circle` SET post_count = GREATEST(post_count + ?, 0) WHERE id = ?", delta, circleID); err != nil {
		return fmt.Errorf("circle post count: %w", err)
	}
	if _, err := s.ExecCtx(ctx,
		`UPDATE topic t JOIN post_topic pt ON pt.topic_id = t.id
		 SET t.post_count = GREATEST(t.post_count + ?, 0) WHERE pt.post_id = ?`, delta, postID); err != nil {
		return fmt.Errorf("topic post count: %w", err)
	}
	return nil
}

// TakedownCommentByAdmin 后台屏蔽评论:正常→屏蔽,回减对象评论数与楼层回复数。
func (m *AdminModel) TakedownCommentByAdmin(ctx context.Context, commentID int64) (authorID int64, hit bool, err error) {
	return m.setCommentStatus(ctx, commentID, 1, 2, -1)
}

// RestoreCommentByAdmin 后台恢复评论:屏蔽→正常,回补计数。
func (m *AdminModel) RestoreCommentByAdmin(ctx context.Context, commentID int64) (authorID int64, hit bool, err error) {
	return m.setCommentStatus(ctx, commentID, 2, 1, 1)
}

func (m *AdminModel) setCommentStatus(ctx context.Context, commentID, from, to, delta int64) (authorID int64, hit bool, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var row struct {
			UserID  int64 `db:"user_id"`
			Status  int64 `db:"status"`
			BizType int64 `db:"biz_type"`
			BizID   int64 `db:"biz_id"`
			RootID  int64 `db:"root_id"`
		}
		err := s.QueryRowCtx(ctx, &row,
			"SELECT user_id, status, biz_type, biz_id, root_id FROM `comment` WHERE id = ? LIMIT 1 FOR UPDATE", commentID)
		if err != nil {
			if IsNotFound(err) {
				return nil
			}
			return fmt.Errorf("load comment: %w", err)
		}
		if row.Status != from {
			return nil
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `comment` SET status = ? WHERE id = ?", to, commentID); err != nil {
			return fmt.Errorf("set comment status: %w", err)
		}
		table := "post"
		if row.BizType == CommentBizSoftware {
			table = "software"
		}
		if _, err := s.ExecCtx(ctx,
			fmt.Sprintf("UPDATE `%s` SET comment_count = GREATEST(comment_count + ?, 0) WHERE id = ?", table),
			delta, row.BizID); err != nil {
			return fmt.Errorf("comment count: %w", err)
		}
		if row.RootID > 0 {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `comment` SET reply_count = GREATEST(reply_count + ?, 0) WHERE id = ?", delta, row.RootID); err != nil {
				return fmt.Errorf("reply count: %w", err)
			}
		}
		authorID, hit = row.UserID, true
		return nil
	})
	return authorID, hit, err
}

// AdminReportRow 后台举报单行(join 举报人昵称)。
type AdminReportRow struct {
	ID         int64          `db:"id"`
	UserID     int64          `db:"user_id"`
	Nickname   string         `db:"nickname"`
	TargetType int64          `db:"target_type"`
	TargetID   int64          `db:"target_id"`
	Category   int64          `db:"category"`
	Reason     string         `db:"reason"`
	Images     sql.NullString `db:"images"`
	Status     int64          `db:"status"`
	HandledBy  int64          `db:"handled_by"`
	HandledAt  sql.NullTime   `db:"handled_at"`
	CreatedAt  time.Time      `db:"created_at"`
}

// ListReports 举报列表:状态(status<0 不筛)+目标类型筛选,待处理按最早优先,其余最新在前。
func (m *AdminModel) ListReports(ctx context.Context, status, targetType int64, offset, limit int) (int64, []*AdminReportRow, error) {
	cond, args := "1 = 1", []any{}
	if status >= 0 {
		cond += " AND r.status = ?"
		args = append(args, status)
	}
	if targetType > 0 {
		cond += " AND r.target_type = ?"
		args = append(args, targetType)
	}
	from := "FROM `report` r JOIN `user` u ON u.id = r.user_id WHERE " + cond

	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) "+from, args...); err != nil {
		return 0, nil, fmt.Errorf("count reports: %w", err)
	}
	order := "r.id DESC"
	if status == 0 {
		order = "r.id" // 待处理先进先出
	}
	var rows []*AdminReportRow
	q := `SELECT r.id, r.user_id, u.nickname, r.target_type, r.target_id, r.category, r.reason,
		r.images, r.status, r.handled_by, r.handled_at, r.created_at ` + from +
		" ORDER BY " + order + " LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("list reports: %w", err)
	}
	return total, rows, nil
}

// HandleReport 举报结单(CAS 防并发重复处理):action 1已处理 2驳回。返回举报人(通知用)。
func (m *AdminModel) HandleReport(ctx context.Context, reportID, adminID, action int64) (reporterID int64, hit bool, err error) {
	err = m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if err := s.QueryRowCtx(ctx, &reporterID,
			"SELECT user_id FROM `report` WHERE id = ? LIMIT 1 FOR UPDATE", reportID); err != nil {
			if IsNotFound(err) {
				return nil
			}
			return fmt.Errorf("load report: %w", err)
		}
		r, err := s.ExecCtx(ctx,
			"UPDATE `report` SET status = ?, handled_by = ?, handled_at = NOW(3) WHERE id = ? AND status = 0",
			action, adminID, reportID)
		if err != nil {
			return fmt.Errorf("handle report: %w", err)
		}
		n, _ := r.RowsAffected()
		hit = n == 1
		return nil
	})
	return reporterID, hit, err
}

// TargetBrief 举报目标摘要(text 语义随类型:标题/内容/昵称;status 语义随目标表)。
type TargetBrief struct {
	ID     int64  `db:"id"`
	Text   string `db:"text"`
	Status int64  `db:"status"`
}

// TargetBriefs 按目标类型批量拉摘要,规避逐单回查的 N+1。
func (m *AdminModel) TargetBriefs(ctx context.Context, targetType int64, ids []int64) (map[int64]*TargetBrief, error) {
	out := make(map[int64]*TargetBrief, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	var tpl string
	switch targetType {
	case ReportTargetPost:
		tpl = "SELECT id, IF(title = '', LEFT(content, 60), title) AS text, status FROM `post` WHERE id IN (%s)"
	case ReportTargetComment:
		tpl = "SELECT id, LEFT(content, 60) AS text, status FROM `comment` WHERE id IN (%s)"
	case ReportTargetUser:
		tpl = "SELECT id, nickname AS text, status FROM `user` WHERE id IN (%s)"
	case ReportTargetMessage:
		tpl = "SELECT id, LEFT(content, 60) AS text, status FROM `message` WHERE id IN (%s)"
	case 5: // 软件(M3)
		tpl = "SELECT id, name AS text, status FROM `software` WHERE id IN (%s)"
	default:
		return out, nil
	}
	q, args := inQuery(tpl, ids)
	var rows []*TargetBrief
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, fmt.Errorf("target briefs: %w", err)
	}
	for _, r := range rows {
		out[r.ID] = r
	}
	return out, nil
}

// SetUserStatus 用户处置落库(恢复/禁言/封禁)。注销号(4)不可操作。
func (m *AdminModel) SetUserStatus(ctx context.Context, uid, status int64) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"UPDATE `user` SET status = ? WHERE id = ? AND status != 4", status, uid)
	if err != nil {
		return false, fmt.Errorf("set user status: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// ---- Banner 配置 ----

// BannerFull 后台视角的完整 Banner 行。
type BannerFull struct {
	ID        int64        `db:"id"`
	Title     string       `db:"title"`
	Image     string       `db:"image"`
	LinkType  int64        `db:"link_type"`
	LinkValue string       `db:"link_value"`
	Sort      int64        `db:"sort"`
	Status    int64        `db:"status"`
	StartAt   sql.NullTime `db:"start_at"`
	EndAt     sql.NullTime `db:"end_at"`
}

func (m *AdminModel) ListBanners(ctx context.Context) ([]*BannerFull, error) {
	var rows []*BannerFull
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, title, image, link_type, link_value, sort, status, start_at, end_at FROM `banner` ORDER BY sort, id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

func (m *AdminModel) SaveBanner(ctx context.Context, b *BannerFull) (int64, error) {
	if b.ID > 0 {
		if _, err := m.conn.ExecCtx(ctx,
			"UPDATE `banner` SET title = ?, image = ?, link_type = ?, link_value = ?, sort = ?, status = ?, start_at = ?, end_at = ? WHERE id = ?",
			b.Title, b.Image, b.LinkType, b.LinkValue, b.Sort, b.Status, b.StartAt, b.EndAt, b.ID); err != nil {
			return 0, fmt.Errorf("update banner: %w", err)
		}
		return b.ID, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `banner` (title, image, link_type, link_value, sort, status, start_at, end_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		b.Title, b.Image, b.LinkType, b.LinkValue, b.Sort, b.Status, b.StartAt, b.EndAt)
	if err != nil {
		return 0, fmt.Errorf("insert banner: %w", err)
	}
	return r.LastInsertId()
}

func (m *AdminModel) DeleteBanner(ctx context.Context, id int64) error {
	if _, err := m.conn.ExecCtx(ctx, "DELETE FROM `banner` WHERE id = ?", id); err != nil {
		return fmt.Errorf("delete banner: %w", err)
	}
	return nil
}

// DashboardStats 数据看板核心指标(需求 3.12 仪表盘)。
type DashboardStats struct {
	Users         int64 `db:"users"`
	TodayUsers    int64 `db:"today_users"`
	TodayActive   int64 `db:"today_active"`
	Posts         int64 `db:"posts"`
	TodayPosts    int64 `db:"today_posts"`
	Software      int64 `db:"software"`
	PendingAudits int64 `db:"pending_audits"`
	YouzhuIssued  int64 `db:"youzhu_issued"`
	YouzhuBurned  int64 `db:"youzhu_burned"`
}

func (m *AdminModel) Dashboard(ctx context.Context) (*DashboardStats, error) {
	var s DashboardStats
	err := m.conn.QueryRowCtx(ctx, &s, fmt.Sprintf(`SELECT
		(SELECT COUNT(1) FROM user WHERE id != %d) AS users,
		(SELECT COUNT(1) FROM user WHERE id != %d AND created_at >= CURDATE()) AS today_users,`, BotUID, BotUID)+`
		(SELECT COUNT(1) FROM user_auth WHERE last_login_at >= CURDATE()) AS today_active,
		(SELECT COUNT(1) FROM post WHERE status = 1) AS posts,
		(SELECT COUNT(1) FROM post WHERE created_at >= CURDATE()) AS today_posts,
		(SELECT COUNT(1) FROM software WHERE status = 1) AS software,
		(SELECT COUNT(1) FROM audit_queue WHERE status = 0) AS pending_audits,
		(SELECT CAST(COALESCE(SUM(amount), 0) AS SIGNED) FROM youzhu_log WHERE amount > 0) AS youzhu_issued,
		(SELECT CAST(COALESCE(SUM(-amount), 0) AS SIGNED) FROM youzhu_log WHERE amount < 0) AS youzhu_burned`)
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// TrendPoint 单日聚合值。
type TrendPoint struct {
	Day   string `db:"d"`
	Value int64  `db:"v"`
}

// youzhuTrendRow 忧珠单日发放/消耗。
type youzhuTrendRow struct {
	Day    string `db:"d"`
	Issued int64  `db:"issued"`
	Burned int64  `db:"burned"`
}

// DashboardTrend 近 N 日趋势:注册/发帖/忧珠发放与消耗,按日补零对齐。
func (m *AdminModel) DashboardTrend(ctx context.Context, days int) (dates []string, users, posts, issued, burned []int64, err error) {
	const layout = "2006-01-02"
	start := time.Now().AddDate(0, 0, -(days - 1))
	startDay := start.Format(layout)

	idx := make(map[string]int, days)
	dates = make([]string, days)
	users, posts = make([]int64, days), make([]int64, days)
	issued, burned = make([]int64, days), make([]int64, days)
	for i := 0; i < days; i++ {
		day := start.AddDate(0, 0, i).Format(layout)
		dates[i], idx[day] = day, i
	}

	var rows []*TrendPoint
	if err = m.conn.QueryRowsCtx(ctx, &rows, fmt.Sprintf(
		"SELECT DATE_FORMAT(created_at, '%%Y-%%m-%%d') AS d, COUNT(1) AS v FROM `user` WHERE created_at >= ? AND id != %d GROUP BY d", BotUID),
		startDay); err != nil {
		return nil, nil, nil, nil, nil, fmt.Errorf("trend users: %w", err)
	}
	for _, r := range rows {
		if i, ok := idx[r.Day]; ok {
			users[i] = r.Value
		}
	}

	rows = rows[:0]
	if err = m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS d, COUNT(1) AS v FROM `post` WHERE created_at >= ? GROUP BY d", startDay); err != nil {
		return nil, nil, nil, nil, nil, fmt.Errorf("trend posts: %w", err)
	}
	for _, r := range rows {
		if i, ok := idx[r.Day]; ok {
			posts[i] = r.Value
		}
	}

	var yz []*youzhuTrendRow
	if err = m.conn.QueryRowsCtx(ctx, &yz,
		`SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS d,
			CAST(COALESCE(SUM(IF(amount > 0, amount, 0)), 0) AS SIGNED) AS issued,
			CAST(COALESCE(SUM(IF(amount < 0, -amount, 0)), 0) AS SIGNED) AS burned
		 FROM youzhu_log WHERE created_at >= ? GROUP BY d`, startDay); err != nil {
		return nil, nil, nil, nil, nil, fmt.Errorf("trend youzhu: %w", err)
	}
	for _, r := range yz {
		if i, ok := idx[r.Day]; ok {
			issued[i], burned[i] = r.Issued, r.Burned
		}
	}
	return dates, users, posts, issued, burned, nil
}

// SoftwareCategoryFull 后台分类行(含停用)。
type SoftwareCategoryFull struct {
	ID     int64  `db:"id"`
	Type   int64  `db:"type"`
	Name   string `db:"name"`
	Sort   int64  `db:"sort"`
	Status int64  `db:"status"`
}

func (m *AdminModel) ListCategoriesAdmin(ctx context.Context) ([]*SoftwareCategoryFull, error) {
	var rows []*SoftwareCategoryFull
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, type, name, sort, status FROM `software_category` ORDER BY type, sort, id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// ErrCategoryExists 同类型下分类重名(uk_type_name)。
var ErrCategoryExists = fmt.Errorf("software category exists")

// SaveCategory 新建/更新软件分类。分类被软件引用,不物理删,用 status 停用。
func (m *AdminModel) SaveCategory(ctx context.Context, c *SoftwareCategoryFull) (int64, bool, error) {
	if c.ID > 0 {
		if _, err := m.conn.ExecCtx(ctx,
			"UPDATE `software_category` SET type = ?, name = ?, sort = ?, status = ? WHERE id = ?",
			c.Type, c.Name, c.Sort, c.Status, c.ID); err != nil {
			if IsDupKey(err) {
				return 0, false, ErrCategoryExists
			}
			return 0, false, fmt.Errorf("update category: %w", err)
		}
		var n int
		if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `software_category` WHERE id = ?", c.ID); err != nil {
			return 0, false, err
		}
		return c.ID, n > 0, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `software_category` (type, name, sort, status) VALUES (?, ?, ?, ?)",
		c.Type, c.Name, c.Sort, c.Status)
	if err != nil {
		if IsDupKey(err) {
			return 0, false, ErrCategoryExists
		}
		return 0, false, fmt.Errorf("insert category: %w", err)
	}
	id, err := r.LastInsertId()
	return id, true, err
}

// AdminCircleRow 后台圈子行(全状态)。
type AdminCircleRow struct {
	ID          int64  `db:"id"`
	Name        string `db:"name"`
	Icon        string `db:"icon"`
	Cover       string `db:"cover"`
	Intro       string `db:"intro"`
	Description string `db:"description"`
	MemberCount int64  `db:"member_count"`
	PostCount   int64  `db:"post_count"`
	IsOfficial  int64  `db:"is_official"`
	Pinned      int64  `db:"pinned"`
	Sort        int64  `db:"sort"`
	Status      int64  `db:"status"`
}

// ListCirclesAdmin 后台圈子列表(含隐藏/解散),名称模糊。
func (m *AdminModel) ListCirclesAdmin(ctx context.Context, keyword string, offset, limit int) (int64, []*AdminCircleRow, error) {
	cond, args := "1 = 1", []any{}
	if keyword != "" {
		cond += " AND name LIKE ?"
		args = append(args, escapeLike(keyword))
	}
	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) FROM `circle` WHERE "+cond, args...); err != nil {
		return 0, nil, fmt.Errorf("count circles: %w", err)
	}
	var rows []*AdminCircleRow
	q := `SELECT id, name, icon, cover, intro, description, member_count, post_count, is_official, pinned, sort, status
		FROM ` + "`circle`" + ` WHERE ` + cond + " ORDER BY pinned DESC, sort, id LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("list circles admin: %w", err)
	}
	return total, rows, nil
}

// ErrCircleExists 圈子重名(uk_name)。
var ErrCircleExists = fmt.Errorf("circle name exists")

// SaveCircleAdmin 新建/更新圈子。解散(3)用状态标记,不物理删。
func (m *AdminModel) SaveCircleAdmin(ctx context.Context, c *AdminCircleRow) (int64, bool, error) {
	if c.ID > 0 {
		if _, err := m.conn.ExecCtx(ctx,
			`UPDATE `+"`circle`"+` SET name = ?, icon = ?, cover = ?, intro = ?, description = ?,
			 is_official = ?, pinned = ?, sort = ?, status = ? WHERE id = ?`,
			c.Name, c.Icon, c.Cover, c.Intro, c.Description, c.IsOfficial, c.Pinned, c.Sort, c.Status, c.ID); err != nil {
			if IsDupKey(err) {
				return 0, false, ErrCircleExists
			}
			return 0, false, fmt.Errorf("update circle: %w", err)
		}
		var n int
		if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `circle` WHERE id = ?", c.ID); err != nil {
			return 0, false, err
		}
		return c.ID, n > 0, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		`INSERT INTO `+"`circle`"+` (name, icon, cover, intro, description, is_official, pinned, sort, status)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		c.Name, c.Icon, c.Cover, c.Intro, c.Description, c.IsOfficial, c.Pinned, c.Sort, c.Status)
	if err != nil {
		if IsDupKey(err) {
			return 0, false, ErrCircleExists
		}
		return 0, false, fmt.Errorf("insert circle: %w", err)
	}
	id, err := r.LastInsertId()
	return id, true, err
}

// SetPostOps 帖子运营位:首页置顶(is_top)/加精(is_essence),-1 不变。仅已发布帖可操作。
func (m *AdminModel) SetPostOps(ctx context.Context, postID, isTop, isEssence int64) (bool, error) {
	sets, args := []string{}, []any{}
	if isTop >= 0 {
		sets = append(sets, "is_top = ?")
		args = append(args, isTop)
	}
	if isEssence >= 0 {
		sets = append(sets, "is_essence = ?")
		args = append(args, isEssence)
	}
	if len(sets) == 0 {
		return true, nil
	}
	args = append(args, postID, PostStatusPublished)
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `post` SET "+strings.Join(sets, ", ")+" WHERE id = ? AND status = ?", args...); err != nil {
		return false, fmt.Errorf("set post ops: %w", err)
	}
	// RowsAffected=0 可能是值未变化,用存在性判断
	var n int
	if err := m.conn.QueryRowCtx(ctx, &n,
		fmt.Sprintf("SELECT COUNT(1) FROM `post` WHERE id = ? AND status = %d", PostStatusPublished), postID); err != nil {
		return false, err
	}
	return n > 0, nil
}

// AdminTopicRow 后台话题行。
type AdminTopicRow struct {
	ID        int64     `db:"id"`
	Name      string    `db:"name"`
	PostCount int64     `db:"post_count"`
	HotScore  int64     `db:"hot_score"`
	Status    int64     `db:"status"`
	CreatedAt time.Time `db:"created_at"`
}

// ListTopicsAdmin 后台话题列表(含封禁),名称模糊 + 状态筛选。
func (m *AdminModel) ListTopicsAdmin(ctx context.Context, keyword string, status int64, offset, limit int) (int64, []*AdminTopicRow, error) {
	cond, args := "1 = 1", []any{}
	if keyword != "" {
		cond += " AND name LIKE ?"
		args = append(args, escapeLike(keyword))
	}
	if status > 0 {
		cond += " AND status = ?"
		args = append(args, status)
	}
	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) FROM `topic` WHERE "+cond, args...); err != nil {
		return 0, nil, fmt.Errorf("count topics: %w", err)
	}
	var rows []*AdminTopicRow
	q := "SELECT id, name, post_count, hot_score, status, created_at FROM `topic` WHERE " + cond +
		" ORDER BY hot_score DESC, id DESC LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("list topics admin: %w", err)
	}
	return total, rows, nil
}

// UpdateTopicAdmin 话题封禁/恢复与热度调整(status=0 或 hotScore<0 表示不变)。
func (m *AdminModel) UpdateTopicAdmin(ctx context.Context, id, status, hotScore int64) (bool, error) {
	sets, args := []string{}, []any{}
	if status > 0 {
		sets = append(sets, "status = ?")
		args = append(args, status)
	}
	if hotScore >= 0 {
		sets = append(sets, "hot_score = ?")
		args = append(args, hotScore)
	}
	if len(sets) == 0 {
		return true, nil
	}
	args = append(args, id)
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `topic` SET "+strings.Join(sets, ", ")+" WHERE id = ?", args...); err != nil {
		return false, fmt.Errorf("update topic: %w", err)
	}
	var n int
	if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `topic` WHERE id = ?", id); err != nil {
		return false, err
	}
	return n > 0, nil
}

// AdminYouzhuLogRow 后台流水行(join 昵称)。
type AdminYouzhuLogRow struct {
	ID           int64     `db:"id"`
	UserID       int64     `db:"user_id"`
	Nickname     string    `db:"nickname"`
	BizType      int64     `db:"biz_type"`
	BizKey       string    `db:"biz_key"`
	Amount       int64     `db:"amount"`
	BalanceAfter int64     `db:"balance_after"`
	Remark       string    `db:"remark"`
	CreatedAt    time.Time `db:"created_at"`
}

// ListYouzhuLogsAdmin 后台流水查询:用户/业务类型筛选,最新在前。
func (m *AdminModel) ListYouzhuLogsAdmin(ctx context.Context, uid, bizType int64, offset, limit int) (int64, []*AdminYouzhuLogRow, error) {
	cond, args := "1 = 1", []any{}
	if uid > 0 {
		cond += " AND l.user_id = ?"
		args = append(args, uid)
	}
	if bizType > 0 {
		cond += " AND l.biz_type = ?"
		args = append(args, bizType)
	}
	from := "FROM `youzhu_log` l JOIN `user` u ON u.id = l.user_id WHERE " + cond

	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) "+from, args...); err != nil {
		return 0, nil, fmt.Errorf("count youzhu logs: %w", err)
	}
	var rows []*AdminYouzhuLogRow
	q := `SELECT l.id, l.user_id, u.nickname, l.biz_type, l.biz_key, l.amount, l.balance_after,
		COALESCE(l.remark, '') AS remark, l.created_at ` + from + " ORDER BY l.id DESC LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("list youzhu logs admin: %w", err)
	}
	return total, rows, nil
}

// AdminPrettyNoRow 后台靓号行。
type AdminPrettyNoRow struct {
	ID     int64        `db:"id"`
	No     string       `db:"no"`
	Rarity int64        `db:"rarity"`
	Price  int64        `db:"price"`
	Status int64        `db:"status"`
	SoldTo int64        `db:"sold_to"`
	SoldAt sql.NullTime `db:"sold_at"`
}

// ListPrettyNosAdmin 后台靓号列表(含下架/已售)。
func (m *AdminModel) ListPrettyNosAdmin(ctx context.Context, keyword string, status int64, offset, limit int) (int64, []*AdminPrettyNoRow, error) {
	cond, args := "1 = 1", []any{}
	if keyword != "" {
		cond += " AND no LIKE ?"
		args = append(args, escapeLike(keyword))
	}
	if status >= 0 {
		cond += " AND status = ?"
		args = append(args, status)
	}
	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total, "SELECT COUNT(1) FROM `pretty_no_sku` WHERE "+cond, args...); err != nil {
		return 0, nil, fmt.Errorf("count pretty nos: %w", err)
	}
	var rows []*AdminPrettyNoRow
	q := "SELECT id, no, rarity, price, status, sold_to, sold_at FROM `pretty_no_sku` WHERE " + cond +
		" ORDER BY status, rarity DESC, price DESC, id LIMIT ?, ?"
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, append(args, offset, limit)...); err != nil {
		return 0, nil, fmt.Errorf("list pretty nos admin: %w", err)
	}
	return total, rows, nil
}

// ErrPrettyNoExists 靓号号码已存在(uk_no)。
var ErrPrettyNoExists = fmt.Errorf("pretty no exists")

// ErrPrettyNoSold 靓号已售出,不可修改。
var ErrPrettyNoSold = fmt.Errorf("pretty no sold")

// SavePrettyNoAdmin 新增/更新靓号 SKU。已售(status=2)行禁止修改,防篡改成交记录。
func (m *AdminModel) SavePrettyNoAdmin(ctx context.Context, p *AdminPrettyNoRow) (int64, bool, error) {
	if p.ID > 0 {
		r, err := m.conn.ExecCtx(ctx,
			"UPDATE `pretty_no_sku` SET no = ?, rarity = ?, price = ?, status = ? WHERE id = ? AND status != 2",
			p.No, p.Rarity, p.Price, p.Status, p.ID)
		if err != nil {
			if IsDupKey(err) {
				return 0, false, ErrPrettyNoExists
			}
			return 0, false, fmt.Errorf("update pretty no: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 0 {
			// 区分不存在与已售
			var st int64
			if err := m.conn.QueryRowCtx(ctx, &st,
				"SELECT status FROM `pretty_no_sku` WHERE id = ? LIMIT 1", p.ID); err != nil {
				if IsNotFound(err) {
					return 0, false, nil
				}
				return 0, false, err
			}
			if st == 2 {
				return 0, false, ErrPrettyNoSold
			}
		}
		return p.ID, true, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `pretty_no_sku` (no, rarity, price, status) VALUES (?, ?, ?, ?)",
		p.No, p.Rarity, p.Price, p.Status)
	if err != nil {
		if IsDupKey(err) {
			return 0, false, ErrPrettyNoExists
		}
		return 0, false, fmt.Errorf("insert pretty no: %w", err)
	}
	id, err := r.LastInsertId()
	return id, true, err
}

// AgreementRow 协议静态页。
type AgreementRow struct {
	Kind      string    `db:"kind"`
	Title     string    `db:"title"`
	Content   string    `db:"content"`
	UpdatedAt time.Time `db:"updated_at"`
}

func (m *AdminModel) GetAgreement(ctx context.Context, kind string) (*AgreementRow, error) {
	var row AgreementRow
	err := m.conn.QueryRowCtx(ctx, &row,
		"SELECT kind, title, content, updated_at FROM `agreement` WHERE kind = ? LIMIT 1", kind)
	if err != nil {
		return nil, err
	}
	return &row, nil
}

func (m *AdminModel) SaveAgreement(ctx context.Context, kind, title, content string) error {
	if _, err := m.conn.ExecCtx(ctx,
		`INSERT INTO agreement (kind, title, content) VALUES (?, ?, ?)
		 ON DUPLICATE KEY UPDATE title = VALUES(title), content = VALUES(content)`,
		kind, title, content); err != nil {
		return fmt.Errorf("save agreement: %w", err)
	}
	return nil
}

// AdminSoftwareRow 软件库管理行。
type AdminSoftwareRow struct {
	ID            int64     `db:"id"`
	UserID        int64     `db:"user_id"`
	Nickname      string    `db:"nickname"`
	Name          string    `db:"name"`
	Logo          string    `db:"logo"`
	Type          int64     `db:"type"`
	CategoryName  string    `db:"category_name"`
	Status        int64     `db:"status"`
	DownloadCount int64     `db:"download_count"`
	CommentCount  int64     `db:"comment_count"`
	CreatedAt     time.Time `db:"created_at"`
}

// ListSoftwareAdmin 软件库检索:名称/简介关键词 + 状态筛选(-1 全部)。
func (m *AdminModel) ListSoftwareAdmin(ctx context.Context, kw string, status int64, offset, limit int) ([]AdminSoftwareRow, int64, error) {
	where, args := "1=1", []any{}
	if kw != "" {
		p := "%" + strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(kw) + "%"
		where += " AND (s.name LIKE ? OR s.intro LIKE ?)"
		args = append(args, p, p)
	}
	if status >= 0 {
		where += " AND s.status = ?"
		args = append(args, status)
	}
	var total int64
	if err := m.conn.QueryRowCtx(ctx, &total,
		"SELECT COUNT(1) FROM `software` s WHERE "+where, args...); err != nil {
		return nil, 0, fmt.Errorf("count software: %w", err)
	}
	var rows []AdminSoftwareRow
	q := `SELECT s.id, s.user_id, u.nickname, s.name, s.logo, s.type, COALESCE(c.name, '') AS category_name,
	             s.status, s.download_count, s.comment_count, s.created_at
	      FROM software s
	      JOIN user u ON u.id = s.user_id
	      LEFT JOIN software_category c ON c.id = s.category_id
	      WHERE ` + where + " ORDER BY s.id DESC LIMIT ?, ?"
	args = append(args, offset, limit)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, 0, fmt.Errorf("list software admin: %w", err)
	}
	return rows, total, nil
}

// SetSoftwareStatus 软件上下架,返回作者 ID 供通知;只在上架态与下架态之间流转。
func (m *AdminModel) SetSoftwareStatus(ctx context.Context, id, status int64) (int64, error) {
	var userID int64
	if err := m.conn.QueryRowCtx(ctx, &userID,
		"SELECT user_id FROM `software` WHERE id = ? LIMIT 1", id); err != nil {
		return 0, err
	}
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `software` SET status = ? WHERE id = ?", status, id); err != nil {
		return 0, fmt.Errorf("set software status: %w", err)
	}
	return userID, nil
}

// LevelRuleRow 等级经验阈值行。
type LevelRuleRow struct {
	Level   int64 `db:"level"`
	NeedExp int64 `db:"need_exp"`
}

// ListLevelRules 全量阈值表(升序)。
func (m *AdminModel) ListLevelRules(ctx context.Context) ([]LevelRuleRow, error) {
	var rows []LevelRuleRow
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT level, need_exp FROM `level_rule` ORDER BY level")
	if err != nil {
		return nil, fmt.Errorf("list level rules: %w", err)
	}
	return rows, nil
}

// SaveLevelRules 整表替换(事务;合法性由 logic 校验,升级计算实时读表即时生效)。
func (m *AdminModel) SaveLevelRules(ctx context.Context, rules []LevelRuleRow) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := s.ExecCtx(ctx, "DELETE FROM `level_rule`"); err != nil {
			return fmt.Errorf("clear level rules: %w", err)
		}
		for _, r := range rules {
			if _, err := s.ExecCtx(ctx,
				"INSERT INTO `level_rule` (level, need_exp) VALUES (?, ?)", r.Level, r.NeedExp); err != nil {
				return fmt.Errorf("insert level rule %d: %w", r.Level, err)
			}
		}
		return nil
	})
}

// SetUserLevel 后台调整等级/经验(<0 不变)。
func (m *AdminModel) SetUserLevel(ctx context.Context, uid, level, exp int64) (bool, error) {
	sets, args := []string{}, []any{}
	if level >= 0 {
		sets = append(sets, "level = ?")
		args = append(args, level)
	}
	if exp >= 0 {
		sets = append(sets, "exp = ?")
		args = append(args, exp)
	}
	if len(sets) == 0 {
		return true, nil
	}
	args = append(args, uid)
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `user` SET "+strings.Join(sets, ", ")+" WHERE id = ? AND status != 4", args...); err != nil {
		return false, fmt.Errorf("set user level: %w", err)
	}
	var n int
	if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `user` WHERE id = ? AND status != 4", uid); err != nil {
		return false, err
	}
	return n > 0, nil
}

// GrantTitle 授予/撤销头衔(达人/开发者):直接落 certification 通过/驳回态。
func (m *AdminModel) GrantTitle(ctx context.Context, uid, kind int64, grant bool) error {
	if grant {
		if _, err := m.conn.ExecCtx(ctx,
			`INSERT INTO certification (user_id, kind, material, status) VALUES (?, ?, '后台授予', ?)
			 ON DUPLICATE KEY UPDATE status = VALUES(status), reason = ''`,
			uid, kind, CertStatusApproved); err != nil {
			return fmt.Errorf("grant title: %w", err)
		}
		return nil
	}
	if _, err := m.conn.ExecCtx(ctx,
		"UPDATE `certification` SET status = ?, reason = '后台撤销' WHERE user_id = ? AND kind = ?",
		CertStatusRejected, uid, kind); err != nil {
		return fmt.Errorf("revoke title: %w", err)
	}
	return nil
}

// DeletePrettyNoAdmin 删除靓号 SKU(仅未售出;已售保留成交记录)。返回 false=不存在或已售。
func (m *AdminModel) DeletePrettyNoAdmin(ctx context.Context, id int64) (bool, error) {
	r, err := m.conn.ExecCtx(ctx,
		"DELETE FROM `pretty_no_sku` WHERE id = ? AND status != 2", id)
	if err != nil {
		return false, fmt.Errorf("delete pretty no: %w", err)
	}
	n, _ := r.RowsAffected()
	return n == 1, nil
}

// AppointCircleRole 圈主/管理员任命(后台动作):确保成员行并设角色。
func (m *AdminModel) AppointCircleRole(ctx context.Context, circleID, uid, role int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		r, err := s.ExecCtx(ctx,
			"INSERT IGNORE INTO `circle_member` (circle_id, user_id, role) VALUES (?, ?, ?)", circleID, uid, role)
		if err != nil {
			return fmt.Errorf("ensure member: %w", err)
		}
		if n, _ := r.RowsAffected(); n == 1 {
			if _, err := s.ExecCtx(ctx,
				"UPDATE `circle` SET member_count = member_count + 1 WHERE id = ?", circleID); err != nil {
				return fmt.Errorf("member count: %w", err)
			}
			return nil
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `circle_member` SET role = ? WHERE circle_id = ? AND user_id = ?", role, circleID, uid); err != nil {
			return fmt.Errorf("set role: %w", err)
		}
		return nil
	})
}
