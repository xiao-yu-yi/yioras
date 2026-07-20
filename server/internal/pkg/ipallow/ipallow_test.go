package ipallow

import "testing"

func TestParseAndAllowed(t *testing.T) {
	cases := []struct {
		name string
		spec string
		addr string
		want bool
	}{
		{"empty spec allows all", "", "8.8.8.8:1234", true},
		{"bare ip match", "203.0.113.7", "203.0.113.7:5000", true},
		{"bare ip miss", "203.0.113.7", "203.0.113.8:5000", false},
		{"cidr match", "10.0.0.0/8", "10.20.30.40:80", true},
		{"cidr miss", "10.0.0.0/8", "11.0.0.1:80", false},
		{"multi rules second hits", "192.168.1.1, 172.16.0.0/12", "172.31.255.254:9", true},
		{"xff first hop", "1.2.3.4", "1.2.3.4, 5.6.7.8", true},
		{"xff first hop miss", "5.6.7.8", "1.2.3.4, 5.6.7.8", false},
		{"ipv6 loopback", "::1", "[::1]:8080", true},
		{"garbage addr rejected", "10.0.0.0/8", "not-an-ip", false},
		{"no port plain ip", "10.0.0.0/8", "10.1.1.1", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			l, err := Parse(c.spec)
			if err != nil {
				t.Fatalf("parse %q: %v", c.spec, err)
			}
			if got := l.Allowed(c.addr); got != c.want {
				t.Fatalf("Allowed(%q) with spec %q = %v, want %v", c.addr, c.spec, got, c.want)
			}
		})
	}
}

func TestParseInvalid(t *testing.T) {
	for _, spec := range []string{"not-an-ip", "10.0.0.0/99", "1.2.3.4/abc"} {
		if _, err := Parse(spec); err == nil {
			t.Fatalf("Parse(%q) expected error", spec)
		}
	}
}
