package llm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNewDisabled(t *testing.T) {
	if c := New(Config{}); c != nil {
		t.Fatal("empty BaseURL should return nil client")
	}
}

func TestChatOK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer test-key" {
			t.Errorf("missing auth header")
		}
		var req chatRequest
		_ = json.NewDecoder(r.Body).Decode(&req)
		if len(req.Messages) != 2 || req.Messages[0].Role != "system" {
			t.Errorf("system message not first: %+v", req.Messages)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{{"message": map[string]string{"role": "assistant", "content": "  hi there  "}}},
		})
	}))
	defer srv.Close()

	c := New(Config{BaseURL: srv.URL, APIKey: "test-key", Model: "m"})
	got, err := c.Chat(context.Background(), "you are a bot", []Message{{Role: "user", Content: "hello"}})
	if err != nil || got != "hi there" {
		t.Fatalf("got %q err %v", got, err)
	}
}

func TestChatErrors(t *testing.T) {
	// HTTP 500
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer srv.Close()
	c := New(Config{BaseURL: srv.URL, Model: "m"})
	if _, err := c.Chat(context.Background(), "", []Message{{Role: "user", Content: "x"}}); err == nil {
		t.Fatal("500 should error")
	}

	// 超时降级
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(2 * time.Second)
	}))
	defer slow.Close()
	c2 := New(Config{BaseURL: slow.URL, Model: "m", TimeoutSec: 1})
	if _, err := c2.Chat(context.Background(), "", []Message{{Role: "user", Content: "x"}}); err == nil {
		t.Fatal("timeout should error")
	}
}
