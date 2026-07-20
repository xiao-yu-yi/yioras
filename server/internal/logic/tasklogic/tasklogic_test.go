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
		if got := ladderReward(c.continuous); got != c.want {
			t.Fatalf("ladderReward(%d) = %d, want %d", c.continuous, got, c.want)
		}
	}
}
