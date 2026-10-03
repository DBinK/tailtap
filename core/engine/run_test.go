package engine

import (
	"context"
	"fmt"
	"net"
	"sync"
	"testing"
)

func TestValidate(t *testing.T) {
	for _, c := range []Config{{Mode: "share", Host: "127.0.0.1", Port: 0}, {Mode: "share", Host: "", Port: 80}, {Mode: "exec", Port: 80}, {Mode: "connect", Address: "tcinvalid", Port: 80}, {Mode: "share", Host: "localhost", Port: 80, LocalPort: 65536}} {
		if Validate(c) == nil {
			t.Errorf("accepted invalid Config: %+v", c)
		}
	}
	if err := Validate(Config{Mode: "share", Host: "localhost", Port: 8022}); err != nil {
		t.Fatal(err)
	}
}

func TestPortConflict(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	c := Config{Mode: "connect", Port: 80, LocalPort: ln.Addr().(*net.TCPAddr).Port, Address: "tcomFwWCCcjS5nKNqAod034nWoJZW0LZqDhhC8U_dKdnDRYQ8uNGFpGQEu"}
	var conflict bool
	err = Run(context.Background(), c, func(e map[string]any) {
		if e["state"] == "conflict" {
			conflict = true
		}
	})
	if err != nil || !conflict {
		t.Fatalf("expected conflict, got %v", err)
	}
}
func TestCancellationReleasesListener(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	var port int
	var mu sync.Mutex
	err := Run(ctx, Config{Mode: "connect", Port: 80, Address: "tcomFwWCCcjS5nKNqAod034nWoJZW0LZqDhhC8U_dKdnDRYQ8uNGFpGQEu"}, func(e map[string]any) {
		mu.Lock()
		defer mu.Unlock()
		if e["localPort"] != nil {
			port = e["localPort"].(int)
			cancel()
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Fatalf("port not released: %v", err)
	}
	ln.Close()
}
