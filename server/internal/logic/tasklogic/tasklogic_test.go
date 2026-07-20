package tasklogic

import "testing"

// TestLadderReward 连签 7 天一循环:5,5,10,10,15,15,30,第 8 天回到 5。
func TestLadderReward(t *testing.T) {
	cases := []struct {
		continuous int64
		want       int64
	}{
		{0, 5}, {1, 5}, {2, 5}, {3, 10}, {4, 10},
		{5, 15}, {6, 15}, {7, 30}, {8, 5}, {14, 30}, {15, 5},
	}
	for _, c := range cases {
		if got := ladderRewardOf(nil, c.continuous); got != c.want {
			t.Fatalf("ladderRewardOf(default, %d) = %d, want %d", c.continuous, got, c.want)
		}
	}
}

// TestParseLadder 配置解析:合法列表生效,非法回退 nil。
func TestParseLadder(t *testing.T) {
	if got := parseLadder("1, 2,3"); len(got) != 3 || got[2] != 3 {
		t.Fatalf("parseLadder valid = %v", got)
	}
	if got := parseLadder("1,x,3"); got != nil {
		t.Fatalf("parseLadder invalid should be nil, got %v", got)
	}
	if got := ladderRewardOf([]int64{7, 9}, 4); got != 9 { // 两档循环:4 → 第 2 档
		t.Fatalf("custom ladder = %d, want 9", got)
	}
}
