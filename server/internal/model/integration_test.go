//go:build integration

// 忧珠账务并发安全集成测试(真 MySQL 8,testcontainers 拉起)。
// 运行: go test -tags integration ./internal/model/ -run TestIntegration -v -count=1
// 本机 Docker Hub 不可达时需先准备本地 mysql:8.0 镜像(见 README 镜像源说明)。
package model

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"github.com/testcontainers/testcontainers-go"
	tcmysql "github.com/testcontainers/testcontainers-go/modules/mysql"
	"github.com/zeromicro/go-zero/core/stores/sqlx"
)

// itEnv 集成测试环境:容器 + 各 model。
type itEnv struct {
	conn   sqlx.SqlConn
	youzhu *YouzhuModel
	paid   *PaidModel
	mall   *MallModel
	raw    *sql.DB
}

func setupIT(t *testing.T) *itEnv {
	t.Helper()
	ctx := context.Background()

	container, err := tcmysql.Run(ctx, "mysql:8.0",
		tcmysql.WithDatabase("yiora"),
		tcmysql.WithUsername("root"),
		tcmysql.WithPassword("it123"),
		testcontainers.WithEnv(map[string]string{"MYSQL_ROOT_HOST": "%"}),
	)
	if err != nil {
		t.Fatalf("start mysql container: %v", err)
	}
	t.Cleanup(func() { _ = container.Terminate(context.Background()) })

	dsn, err := container.ConnectionString(ctx, "charset=utf8mb4", "parseTime=true", "loc=Local", "multiStatements=true")
	if err != nil {
		t.Fatalf("dsn: %v", err)
	}
	raw, err := sql.Open("mysql", dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	raw.SetMaxOpenConns(50)
	t.Cleanup(func() { _ = raw.Close() })

	// 执行仓库迁移建表(001-005;去掉 CREATE DATABASE/USE,容器已建库)
	for _, f := range []string{"001_m2_schema.sql", "002_m3_software.sql", "003_m3_youzhu.sql", "004_m4_mall.sql", "005_m4_paid_ai.sql"} {
		b, err := os.ReadFile("../../sql/" + f)
		if err != nil {
			t.Fatalf("read %s: %v", f, err)
		}
		lines := make([]string, 0, 64)
		for _, line := range strings.Split(string(b), "\n") {
			l := strings.TrimSpace(line)
			if strings.HasPrefix(l, "USE ") || strings.HasPrefix(l, "CREATE DATABASE") {
				continue
			}
			lines = append(lines, line)
		}
		if _, err := raw.ExecContext(ctx, strings.Join(lines, "\n")); err != nil {
			t.Fatalf("migrate %s: %v", f, err)
		}
	}

	// 关闭 go-zero 内建熔断器(声明一切错误可接受):本组压测故意制造死锁(1213)、余额不足、
	// 幂等重放等密集"失败",在慢 CI 机上会把熔断器打开,后续请求被 drop 成
	// "circuit breaker is open",withDeadlockRetry 因错误类型改变而放弃重试(CI 偶发红的根因)。
	// 专属容器库无需熔断保护,测试要的是原始错误本身。
	conn := sqlx.NewSqlConnFromDB(raw, sqlx.WithAcceptable(func(error) bool { return true }))
	return &itEnv{
		conn:   conn,
		youzhu: NewYouzhuModel(conn),
		paid:   NewPaidModel(conn),
		mall:   NewMallModel(conn),
		raw:    raw,
	}
}

// reconcileOrFail 全库对账:任何账户余额 != 流水合计即失败。
func (e *itEnv) reconcileOrFail(t *testing.T, stage string) {
	t.Helper()
	diffs, err := e.youzhu.Reconcile(context.Background(), 100)
	if err != nil {
		t.Fatalf("%s reconcile: %v", stage, err)
	}
	for _, d := range diffs {
		t.Errorf("%s MISMATCH uid=%d balance=%d logSum=%d", stage, d.UserID, d.Balance, d.LogSum)
	}
}

func TestIntegrationYouzhuConcurrency(t *testing.T) {
	env := setupIT(t)
	ctx := context.Background()

	t.Run("SameBizKeyOnlyOnce", func(t *testing.T) {
		// 40 并发重放同一个幂等键:只能入账一次
		const uid, amount = int64(11), int64(7)
		var wg sync.WaitGroup
		applied := make(chan bool, 40)
		for i := 0; i < 40; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				ok, err := env.youzhu.Change(ctx, uid, YouzhuBizOps, "it:same-key", amount, "replay")
				if err != nil {
					t.Errorf("change: %v", err)
					return
				}
				applied <- ok
			}()
		}
		wg.Wait()
		close(applied)
		n := 0
		for ok := range applied {
			if ok {
				n++
			}
		}
		if n != 1 {
			t.Fatalf("applied %d times, want exactly 1", n)
		}
		balance, _ := env.youzhu.Balance(ctx, uid)
		if balance != amount {
			t.Fatalf("balance = %d, want %d", balance, amount)
		}
		env.reconcileOrFail(t, "same-key")
	})

	t.Run("MixedCreditDebitNeverNegative", func(t *testing.T) {
		// 初始 100,并发 30 笔扣 10:最多成功 10 笔,余额恒 >= 0,账实相符
		const uid = int64(12)
		if _, err := env.youzhu.Change(ctx, uid, YouzhuBizOps, "it:seed-12", 100, "seed"); err != nil {
			t.Fatalf("seed: %v", err)
		}
		var wg sync.WaitGroup
		var okCount, insufficient int64
		var mu sync.Mutex
		for i := 0; i < 30; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				_, err := env.youzhu.Change(ctx, uid, YouzhuBizExchange, fmt.Sprintf("it:debit-12-%d", i), -10, "debit")
				mu.Lock()
				defer mu.Unlock()
				switch {
				case err == nil:
					okCount++
				case errors.Is(err, ErrInsufficientBalance):
					insufficient++
				default:
					t.Errorf("debit: %v", err)
				}
			}(i)
		}
		wg.Wait()
		if okCount != 10 || insufficient != 20 {
			t.Fatalf("ok=%d insufficient=%d, want 10/20", okCount, insufficient)
		}
		balance, _ := env.youzhu.Balance(ctx, uid)
		if balance != 0 {
			t.Fatalf("balance = %d, want 0", balance)
		}
		env.reconcileOrFail(t, "mixed")
	})
}

func TestIntegrationUnlockConcurrency(t *testing.T) {
	env := setupIT(t)
	ctx := context.Background()
	const author, postID, price, fee = int64(500), int64(9001), int64(20), int64(10)

	// 付费段落库(直接建段即可,Unlock 不读 post 表)
	if _, err := env.raw.ExecContext(ctx,
		"INSERT INTO post_paid_content (post_id, price, content) VALUES (?, ?, 'secret')", postID, price); err != nil {
		t.Fatalf("seed paid: %v", err)
	}

	// 串行前置诊断:单买家解锁一次,作者必须立刻到账(隔离逻辑缺陷与并发缺陷)
	if _, err := env.youzhu.Change(ctx, 599, YouzhuBizOps, "it:seed-599", 100, "seed"); err != nil {
		t.Fatalf("seed 599: %v", err)
	}
	if _, err := env.paid.Unlock(ctx, 599, author, postID, price, fee); err != nil {
		t.Fatalf("serial unlock: %v", err)
	}
	if b, _ := env.youzhu.Balance(ctx, author); b != price*(100-fee)/100 {
		t.Fatalf("serial author balance = %d, want %d", b, price*(100-fee)/100)
	}

	// 10 个买家、每人并发重试 3 次:每人只扣一次,作者分成 = 10*18
	var wg sync.WaitGroup
	for buyer := int64(600); buyer < 610; buyer++ {
		if _, err := env.youzhu.Change(ctx, buyer, YouzhuBizOps, fmt.Sprintf("it:seed-%d", buyer), 100, "seed"); err != nil {
			t.Fatalf("seed buyer: %v", err)
		}
		for retry := 0; retry < 3; retry++ {
			wg.Add(1)
			go func(b int64) {
				defer wg.Done()
				_, err := env.paid.Unlock(ctx, b, author, postID, price, fee)
				if err != nil && !errors.Is(err, ErrAlreadyUnlocked) {
					t.Errorf("unlock: %v", err)
				}
			}(buyer)
		}
	}
	wg.Wait()

	var unlockCount int64
	_ = env.raw.QueryRowContext(ctx, "SELECT COUNT(1) FROM post_unlock_record WHERE post_id = ?", postID).Scan(&unlockCount)
	if unlockCount != 11 { // 10 并发买家 + 1 串行诊断买家
		t.Fatalf("unlock records = %d, want 11", unlockCount)
	}
	authorBalance, _ := env.youzhu.Balance(ctx, author)
	if want := int64(11) * price * (100 - fee) / 100; authorBalance != want {
		t.Fatalf("author balance = %d, want %d", authorBalance, want)
	}
	for buyer := int64(600); buyer < 610; buyer++ {
		b, _ := env.youzhu.Balance(ctx, buyer)
		if b != 100-price {
			t.Fatalf("buyer %d balance = %d, want %d", buyer, b, 100-price)
		}
	}
	env.reconcileOrFail(t, "unlock")
}

func TestIntegrationDrawConcurrency(t *testing.T) {
	env := setupIT(t)
	ctx := context.Background()
	const cost = int64(10)

	// 受控奖池:清掉种子,只放 限量5的装扮(引用种子装扮ID=2) + 不限量忧珠
	if _, err := env.raw.ExecContext(ctx, "DELETE FROM lottery_pool"); err != nil {
		t.Fatalf("clear pool: %v", err)
	}
	if _, err := env.raw.ExecContext(ctx,
		`INSERT INTO lottery_pool (name, kind, ref_id, amount, weight, stock) VALUES
		 ('it-youzhu', 1, 0, 5, 50, -1), ('it-deco', 2, 2, 0, 50, 5)`); err != nil {
		t.Fatalf("seed pool: %v", err)
	}

	// 4 个用户并发各抽 10 次(共 40 次):限量奖品发放 ≤5,余额/流水/库存全部对账
	var wg sync.WaitGroup
	for uid := int64(700); uid < 704; uid++ {
		if _, err := env.youzhu.Change(ctx, uid, YouzhuBizOps, fmt.Sprintf("it:seed-%d", uid), 100, "seed"); err != nil {
			t.Fatalf("seed: %v", err)
		}
		for i := 0; i < 10; i++ {
			wg.Add(1)
			go func(u int64) {
				defer wg.Done()
				if _, err := env.mall.Draw(ctx, u, cost); err != nil {
					t.Errorf("draw: %v", err)
				}
			}(uid)
		}
	}
	wg.Wait()

	var decoAwarded, stock int64
	_ = env.raw.QueryRowContext(ctx, "SELECT COUNT(1) FROM lottery_log WHERE kind = 2").Scan(&decoAwarded)
	_ = env.raw.QueryRowContext(ctx, "SELECT stock FROM lottery_pool WHERE name = 'it-deco'").Scan(&stock)
	if decoAwarded > 5 {
		t.Fatalf("limited prize awarded %d times, stock oversold", decoAwarded)
	}
	if stock != 5-decoAwarded {
		t.Fatalf("stock = %d, want %d", stock, 5-decoAwarded)
	}
	var draws int64
	_ = env.raw.QueryRowContext(ctx, "SELECT COUNT(1) FROM lottery_log").Scan(&draws)
	if draws != 40 {
		t.Fatalf("draws = %d, want 40", draws)
	}
	env.reconcileOrFail(t, "draw")

	// 限量奖发完后继续抽:只能中不限量奖
	deadline := time.Now().Add(10 * time.Second)
	for stockLeft := stock; stockLeft > 0 && time.Now().Before(deadline); {
		if _, err := env.mall.Draw(ctx, 700, cost); err != nil {
			if errors.Is(err, ErrInsufficientBalance) {
				break
			}
			t.Fatalf("drain draw: %v", err)
		}
		_ = env.raw.QueryRowContext(ctx, "SELECT stock FROM lottery_pool WHERE name = 'it-deco'").Scan(&stockLeft)
	}
}
