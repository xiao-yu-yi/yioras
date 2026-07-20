package model

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// 装扮类型(decoration.kind);气泡商城已按需求裁剪,仅保留头像框
const (
	DecoKindAvatarFrame = 1
)

// 兑换记录类型(exchange_record.kind)
const (
	ExchangeKindDeco     = 1
	ExchangeKindPrettyNo = 2
	ExchangeKindLottery  = 3
)

// 奖品类型(lottery_pool.kind)
const (
	PrizeKindYouzhu = 1
	PrizeKindDeco   = 2
)

var (
	// ErrAlreadyOwned 已拥有该装扮(未过期)。
	ErrAlreadyOwned = errors.New("decoration already owned")
	// ErrSkuSoldOut 靓号已售出或下架。
	ErrSkuSoldOut = errors.New("pretty no sold out")
	// ErrNoConflict 靓号与现有编号冲突。
	ErrNoConflict = errors.New("display no conflict")
	// ErrPoolEmpty 奖池为空。
	ErrPoolEmpty = errors.New("lottery pool empty")
)

type (
	Decoration struct {
		ID           int64     `db:"id"`
		Kind         int64     `db:"kind"`
		Name         string    `db:"name"`
		Preview      string    `db:"preview"`
		Price        int64     `db:"price"`
		DurationDays int64     `db:"duration_days"`
		Sort         int64     `db:"sort"`
		Status       int64     `db:"status"`
		CreatedAt    time.Time `db:"created_at"`
	}

	UserDecoration struct {
		ID           int64        `db:"id"`
		UserID       int64        `db:"user_id"`
		DecorationID int64        `db:"decoration_id"`
		ExpireAt     sql.NullTime `db:"expire_at"`
		Worn         int64        `db:"worn"`
		CreatedAt    time.Time    `db:"created_at"`
	}

	PrettyNoSku struct {
		ID     int64  `db:"id"`
		No     string `db:"no"`
		Rarity int64  `db:"rarity"`
		Price  int64  `db:"price"`
		Status int64  `db:"status"`
	}

	LotteryPrize struct {
		ID     int64  `db:"id"`
		Name   string `db:"name"`
		Kind   int64  `db:"kind"`
		RefID  int64  `db:"ref_id"`
		Amount int64  `db:"amount"`
		Weight int64  `db:"weight"`
		Stock  int64  `db:"stock"`
	}

	ExchangeRecord struct {
		ID        int64     `db:"id"`
		UserID    int64     `db:"user_id"`
		Kind      int64     `db:"kind"`
		RefID     int64     `db:"ref_id"`
		Name      string    `db:"name"`
		Cost      int64     `db:"cost"`
		CreatedAt time.Time `db:"created_at"`
	}

	MallModel struct{ conn sqlx.SqlConn }
)

func NewMallModel(conn sqlx.SqlConn) *MallModel { return &MallModel{conn: conn} }

// ---- 装扮商城 ----

func (m *MallModel) ListDecorations(ctx context.Context, kind int64) ([]*Decoration, error) {
	cond, args := "status = 1", []any{}
	if kind > 0 {
		cond += " AND kind = ?"
		args = append(args, kind)
	}
	var rows []*Decoration
	q := fmt.Sprintf("SELECT id, kind, name, preview, price, duration_days, sort, status, created_at FROM `decoration` WHERE %s ORDER BY kind, sort, id", cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

func (m *MallModel) FindDecoration(ctx context.Context, id int64) (*Decoration, error) {
	var d Decoration
	err := m.conn.QueryRowCtx(ctx, &d,
		"SELECT id, kind, name, preview, price, duration_days, sort, status, created_at FROM `decoration` WHERE id = ? AND status = 1 LIMIT 1", id)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// MyDecorations 我的仓库(含装扮快照)。
type MyDecoration struct {
	UserDecoration
	Kind    int64  `db:"kind"`
	Name    string `db:"name"`
	Preview string `db:"preview"`
}

func (m *MallModel) MyDecorations(ctx context.Context, uid, kind int64) ([]*MyDecoration, error) {
	cond, args := "ud.user_id = ?", []any{uid}
	if kind > 0 {
		cond += " AND d.kind = ?"
		args = append(args, kind)
	}
	var rows []*MyDecoration
	q := fmt.Sprintf(
		`SELECT ud.id, ud.user_id, ud.decoration_id, ud.expire_at, ud.worn, ud.created_at, d.kind, d.name, d.preview
		 FROM user_decoration ud JOIN decoration d ON d.id = ud.decoration_id
		 WHERE %s ORDER BY ud.worn DESC, ud.id DESC`, cond)
	if err := m.conn.QueryRowsCtx(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	return rows, nil
}

// ExchangeDecoration 兑换装扮:扣款+发放+兑换记录单事务。
// 拥有权即幂等:已拥有未过期直接 ErrAlreadyOwned(不扣款);限时过期后可再兑换续期。
func (m *MallModel) ExchangeDecoration(ctx context.Context, uid int64, d *Decoration) error {
	return withDeadlockRetry(func() error { return m.exchangeDecoTx(ctx, uid, d) })
}

func (m *MallModel) exchangeDecoTx(ctx context.Context, uid int64, d *Decoration) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var owned UserDecoration
		err := s.QueryRowCtx(ctx, &owned,
			"SELECT id, user_id, decoration_id, expire_at, worn, created_at FROM `user_decoration` WHERE user_id = ? AND decoration_id = ? LIMIT 1 FOR UPDATE",
			uid, d.ID)
		exists := err == nil
		if err != nil && !errors.Is(err, sqlx.ErrNotFound) {
			return fmt.Errorf("check owned: %w", err)
		}
		if exists && (!owned.ExpireAt.Valid || owned.ExpireAt.Time.After(time.Now())) {
			return ErrAlreadyOwned
		}
		// 兑换轮次:历史兑换次数+1,同轮客户端重试由 biz_key 重放兜底
		var cycle int64
		if err := s.QueryRowCtx(ctx, &cycle,
			"SELECT COUNT(1) FROM `exchange_record` WHERE user_id = ? AND kind = ? AND ref_id = ?",
			uid, ExchangeKindDeco, d.ID); err != nil {
			return fmt.Errorf("exchange cycle: %w", err)
		}
		bizKey := fmt.Sprintf("deco:%d:%d:%d", uid, d.ID, cycle+1)
		applied, err := youzhuChangeIn(ctx, s, uid, YouzhuBizExchange, bizKey, -d.Price, "兑换装扮 "+d.Name)
		if err != nil {
			return err
		}
		if !applied { // 同轮重放:此前已扣款并发放,按成功返回
			return nil
		}
		var expire any
		if d.DurationDays > 0 {
			expire = time.Now().AddDate(0, 0, int(d.DurationDays))
		}
		if _, err := s.ExecCtx(ctx,
			`INSERT INTO user_decoration (user_id, decoration_id, expire_at) VALUES (?, ?, ?)
			 ON DUPLICATE KEY UPDATE expire_at = VALUES(expire_at)`,
			uid, d.ID, expire); err != nil {
			return fmt.Errorf("grant decoration: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"INSERT INTO `exchange_record` (user_id, kind, ref_id, name, cost) VALUES (?, ?, ?, ?, ?)",
			uid, ExchangeKindDeco, d.ID, d.Name, d.Price); err != nil {
			return fmt.Errorf("exchange record: %w", err)
		}
		return nil
	})
}

// Wear 佩戴:同 kind 先全部卸下再佩戴目标;装扮须在有效期内。
func (m *MallModel) Wear(ctx context.Context, uid, decorationID int64) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var row struct {
			ID       int64        `db:"id"`
			Kind     int64        `db:"kind"`
			ExpireAt sql.NullTime `db:"expire_at"`
		}
		err := s.QueryRowCtx(ctx, &row,
			`SELECT ud.id, d.kind, ud.expire_at FROM user_decoration ud JOIN decoration d ON d.id = ud.decoration_id
			 WHERE ud.user_id = ? AND ud.decoration_id = ? LIMIT 1 FOR UPDATE`, uid, decorationID)
		if err != nil {
			return err
		}
		if row.ExpireAt.Valid && row.ExpireAt.Time.Before(time.Now()) {
			return sqlx.ErrNotFound // 已过期按未拥有处理
		}
		if _, err := s.ExecCtx(ctx,
			`UPDATE user_decoration ud JOIN decoration d ON d.id = ud.decoration_id
			 SET ud.worn = 0 WHERE ud.user_id = ? AND d.kind = ?`, uid, row.Kind); err != nil {
			return fmt.Errorf("take off same kind: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `user_decoration` SET worn = 1 WHERE id = ?", row.ID); err != nil {
			return fmt.Errorf("wear: %w", err)
		}
		return nil
	})
}

// TakeOff 卸下指定装扮。
func (m *MallModel) TakeOff(ctx context.Context, uid, decorationID int64) error {
	_, err := m.conn.ExecCtx(ctx,
		"UPDATE `user_decoration` SET worn = 0 WHERE user_id = ? AND decoration_id = ?", uid, decorationID)
	return err
}

// ---- 靓号商城 ----

func (m *MallModel) ListPrettyNo(ctx context.Context, offset, limit int) ([]*PrettyNoSku, error) {
	var rows []*PrettyNoSku
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, no, rarity, price, status FROM `pretty_no_sku` WHERE status = 1 ORDER BY rarity DESC, price DESC, id LIMIT ?, ?",
		offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// ExchangePrettyNo 兑换靓号:SKU 行锁防超卖,扣款+替换展示编号+记录单事务。
// biz_key 用 skuID(一个号码只能售出一次,天然幂等)。
func (m *MallModel) ExchangePrettyNo(ctx context.Context, uid, skuID int64) (no string, err error) {
	err = withDeadlockRetry(func() error { return m.exchangeNoTx(ctx, uid, skuID, &no) })
	return no, err
}

func (m *MallModel) exchangeNoTx(ctx context.Context, uid, skuID int64, noOut *string) error {
	return m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		var sku PrettyNoSku
		if err := s.QueryRowCtx(ctx, &sku,
			"SELECT id, no, rarity, price, status FROM `pretty_no_sku` WHERE id = ? LIMIT 1 FOR UPDATE", skuID); err != nil {
			return err
		}
		if sku.Status != 1 {
			return ErrSkuSoldOut
		}
		applied, err := youzhuChangeIn(ctx, s, uid, YouzhuBizExchange,
			fmt.Sprintf("pno:%d", skuID), -sku.Price, "兑换靓号 "+sku.No)
		if err != nil {
			return err
		}
		if !applied {
			return ErrSkuSoldOut // biz_key 已用:该 SKU 已被兑换过
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `pretty_no_sku` SET status = 2, sold_to = ?, sold_at = NOW(3) WHERE id = ?", uid, skuID); err != nil {
			return fmt.Errorf("mark sold: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"UPDATE `user` SET display_no = ? WHERE id = ?", sku.No, uid); err != nil {
			if IsDupKey(err) { // 号码与现有 display_no 冲突(如恰为他人默认 N+uid)
				return ErrNoConflict
			}
			return fmt.Errorf("update display no: %w", err)
		}
		if _, err := s.ExecCtx(ctx,
			"INSERT INTO `exchange_record` (user_id, kind, ref_id, name, cost) VALUES (?, ?, ?, ?, ?)",
			uid, ExchangeKindPrettyNo, skuID, sku.No, sku.Price); err != nil {
			return fmt.Errorf("exchange record: %w", err)
		}
		*noOut = sku.No
		return nil
	})
}

// ---- 后台运营配置(装扮/奖池) ----

// ListDecorationsAdmin 后台装扮列表(含下架)。
func (m *MallModel) ListDecorationsAdmin(ctx context.Context) ([]*Decoration, error) {
	var rows []*Decoration
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, kind, name, preview, price, duration_days, sort, status, created_at FROM `decoration` ORDER BY kind, sort, id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// SaveDecoration 新建/更新装扮。已购用户不受下架影响(user_decoration 独立存续)。
// 返回 false 表示更新目标不存在。
func (m *MallModel) SaveDecoration(ctx context.Context, d *Decoration) (int64, bool, error) {
	if d.ID > 0 {
		if _, err := m.conn.ExecCtx(ctx,
			"UPDATE `decoration` SET kind = ?, name = ?, preview = ?, price = ?, duration_days = ?, sort = ?, status = ? WHERE id = ?",
			d.Kind, d.Name, d.Preview, d.Price, d.DurationDays, d.Sort, d.Status, d.ID); err != nil {
			return 0, false, fmt.Errorf("update decoration: %w", err)
		}
		var n int
		if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `decoration` WHERE id = ?", d.ID); err != nil {
			return 0, false, err
		}
		return d.ID, n > 0, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `decoration` (kind, name, preview, price, duration_days, sort, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
		d.Kind, d.Name, d.Preview, d.Price, d.DurationDays, d.Sort, d.Status)
	if err != nil {
		return 0, false, fmt.Errorf("insert decoration: %w", err)
	}
	id, err := r.LastInsertId()
	return id, true, err
}

// LotteryPrizeFull 后台视角奖池行(含启停)。
type LotteryPrizeFull struct {
	LotteryPrize
	Status int64 `db:"status"`
}

// ListPrizesAdmin 后台奖池列表(含停用与售罄)。
func (m *MallModel) ListPrizesAdmin(ctx context.Context) ([]*LotteryPrizeFull, error) {
	var rows []*LotteryPrizeFull
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, kind, ref_id, amount, weight, stock, status FROM `lottery_pool` ORDER BY id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// SavePrize 新建/更新奖池奖品。流水存快照,改配置不影响历史记录。
func (m *MallModel) SavePrize(ctx context.Context, p *LotteryPrizeFull) (int64, bool, error) {
	if p.ID > 0 {
		if _, err := m.conn.ExecCtx(ctx,
			"UPDATE `lottery_pool` SET name = ?, kind = ?, ref_id = ?, amount = ?, weight = ?, stock = ?, status = ? WHERE id = ?",
			p.Name, p.Kind, p.RefID, p.Amount, p.Weight, p.Stock, p.Status, p.ID); err != nil {
			return 0, false, fmt.Errorf("update prize: %w", err)
		}
		var n int
		if err := m.conn.QueryRowCtx(ctx, &n, "SELECT COUNT(1) FROM `lottery_pool` WHERE id = ?", p.ID); err != nil {
			return 0, false, err
		}
		return p.ID, n > 0, nil
	}
	r, err := m.conn.ExecCtx(ctx,
		"INSERT INTO `lottery_pool` (name, kind, ref_id, amount, weight, stock, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
		p.Name, p.Kind, p.RefID, p.Amount, p.Weight, p.Stock, p.Status)
	if err != nil {
		return 0, false, fmt.Errorf("insert prize: %w", err)
	}
	id, err := r.LastInsertId()
	return id, true, err
}

// ---- 积分抽奖 ----

func (m *MallModel) ListPrizes(ctx context.Context) ([]*LotteryPrize, error) {
	var rows []*LotteryPrize
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, name, kind, ref_id, amount, weight, stock FROM `lottery_pool` WHERE status = 1 AND (stock != 0) ORDER BY id")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// Draw 抽奖:扣抽奖费 → 权重随机 → 扣奖品库存 → 发奖 → 流水+记录,全程单事务。
// 先锁账户行再取抽奖序号,同用户并发抽奖被串行化,seq 不会撞车;跨用户死锁自动重试。
func (m *MallModel) Draw(ctx context.Context, uid int64, cost int64) (*LotteryPrize, error) {
	var won *LotteryPrize
	err := withDeadlockRetry(func() error {
		won = nil
		return m.drawTx(ctx, uid, cost, &won)
	})
	if err != nil {
		return nil, err
	}
	return won, nil
}

func (m *MallModel) drawTx(ctx context.Context, uid int64, cost int64, wonOut **LotteryPrize) error {
	var won *LotteryPrize
	err := m.conn.TransactCtx(ctx, func(ctx context.Context, s sqlx.Session) error {
		if _, err := lockYouzhuAccount(ctx, s, uid); err != nil {
			return err
		}
		// 抽奖序号:该用户历史抽奖次数+1(已持有账户行锁,并发安全)
		var seq int64
		if err := s.QueryRowCtx(ctx, &seq,
			"SELECT COUNT(1) FROM `lottery_log` WHERE user_id = ?", uid); err != nil {
			return fmt.Errorf("draw seq: %w", err)
		}
		seq++
		applied, err := youzhuChangeIn(ctx, s, uid, YouzhuBizLottery,
			fmt.Sprintf("draw:%d:%d", uid, seq), -cost, "积分抽奖")
		if err != nil {
			return err
		}
		if !applied { // 同序号重放(理论不可达,事务原子:扣费与流水同回滚)
			return fmt.Errorf("draw seq %d replay without log", seq)
		}
		// 奖池普通读即可:限量奖以原子扣减为准,不锁全池(全池 FOR UPDATE 与账户行锁会交叉死锁)
		var prizes []*LotteryPrize
		if err := s.QueryRowsCtx(ctx, &prizes,
			"SELECT id, name, kind, ref_id, amount, weight, stock FROM `lottery_pool` WHERE status = 1 AND stock != 0"); err != nil {
			return fmt.Errorf("load pool: %w", err)
		}
		if len(prizes) == 0 {
			return ErrPoolEmpty
		}
		picked, err := pickByWeight(prizes)
		if err != nil {
			return err
		}
		if picked.Stock > 0 {
			r, err := s.ExecCtx(ctx,
				"UPDATE `lottery_pool` SET stock = stock - 1 WHERE id = ? AND stock > 0", picked.ID)
			if err != nil {
				return fmt.Errorf("decr stock: %w", err)
			}
			if n, _ := r.RowsAffected(); n == 0 {
				// 并发下刚售罄:降级到不限量奖池重抽,没有则视为奖池已空(整体回滚不扣费)
				unlimited := make([]*LotteryPrize, 0, len(prizes))
				for _, p := range prizes {
					if p.Stock < 0 {
						unlimited = append(unlimited, p)
					}
				}
				if len(unlimited) == 0 {
					return ErrPoolEmpty
				}
				if picked, err = pickByWeight(unlimited); err != nil {
					return err
				}
			}
		}
		r, err := s.ExecCtx(ctx,
			"INSERT INTO `lottery_log` (user_id, pool_id, prize_name, kind, amount) VALUES (?, ?, ?, ?, ?)",
			uid, picked.ID, picked.Name, picked.Kind, picked.Amount)
		if err != nil {
			return fmt.Errorf("lottery log: %w", err)
		}
		logID, err := r.LastInsertId()
		if err != nil {
			return fmt.Errorf("lottery log id: %w", err)
		}
		switch picked.Kind {
		case PrizeKindYouzhu:
			if _, err := youzhuChangeIn(ctx, s, uid, YouzhuBizLottery,
				fmt.Sprintf("prize:%d", logID), picked.Amount, "抽奖奖励 "+picked.Name); err != nil {
				return err
			}
		case PrizeKindDeco:
			// 已拥有则不重复发放(限时装扮取更晚的过期时间)
			var d Decoration
			if err := s.QueryRowCtx(ctx, &d,
				"SELECT id, kind, name, preview, price, duration_days, sort, status, created_at FROM `decoration` WHERE id = ? LIMIT 1", picked.RefID); err != nil {
				return fmt.Errorf("prize decoration: %w", err)
			}
			var expire any
			if d.DurationDays > 0 {
				expire = time.Now().AddDate(0, 0, int(d.DurationDays))
			}
			if _, err := s.ExecCtx(ctx,
				`INSERT INTO user_decoration (user_id, decoration_id, expire_at) VALUES (?, ?, ?)
				 ON DUPLICATE KEY UPDATE expire_at = IF(expire_at IS NULL, expire_at, GREATEST(expire_at, VALUES(expire_at)))`,
				uid, d.ID, expire); err != nil {
				return fmt.Errorf("grant prize decoration: %w", err)
			}
		}
		if _, err := s.ExecCtx(ctx,
			"INSERT INTO `exchange_record` (user_id, kind, ref_id, name, cost) VALUES (?, ?, ?, ?, ?)",
			uid, ExchangeKindLottery, logID, picked.Name, cost); err != nil {
			return fmt.Errorf("exchange record: %w", err)
		}
		won = picked
		return nil
	})
	if err != nil {
		return err
	}
	*wonOut = won
	return nil
}

// pickByWeight 权重随机(crypto/rand,防可预测)。
func pickByWeight(prizes []*LotteryPrize) (*LotteryPrize, error) {
	var total int64
	for _, p := range prizes {
		if p.Weight > 0 {
			total += p.Weight
		}
	}
	if total <= 0 {
		return nil, ErrPoolEmpty
	}
	n, err := rand.Int(rand.Reader, big.NewInt(total))
	if err != nil {
		return nil, fmt.Errorf("rand: %w", err)
	}
	x := n.Int64()
	for _, p := range prizes {
		if p.Weight <= 0 {
			continue
		}
		if x < p.Weight {
			return p, nil
		}
		x -= p.Weight
	}
	return prizes[len(prizes)-1], nil
}

// ---- 兑换记录 ----

func (m *MallModel) ExchangeRecords(ctx context.Context, uid int64, offset, limit int) ([]*ExchangeRecord, error) {
	var rows []*ExchangeRecord
	err := m.conn.QueryRowsCtx(ctx, &rows,
		"SELECT id, user_id, kind, ref_id, name, cost, created_at FROM `exchange_record` WHERE user_id = ? ORDER BY id DESC LIMIT ?, ?",
		uid, offset, limit)
	if err != nil {
		return nil, err
	}
	return rows, nil
}
