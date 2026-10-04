package engine

import (
	"context"
	"github.com/tailscale/tailcat"
	"io"
	"sync/atomic"
	"time"
)

type countWriter struct {
	io.Writer
	count *atomic.Int64
}

func (w countWriter) Write(data []byte) (int, error) {
	n, err := w.Writer.Write(data)
	w.count.Add(int64(n))
	return n, err
}

func diagnose(ctx context.Context, client *tailcat.Client, commands <-chan Command, emit func(map[string]any)) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	visible := false
	check := func(direct bool) {
		deadline := 8 * time.Second
		if direct {
			deadline = 10 * time.Second
		}
		checkCtx, cancel := context.WithTimeout(ctx, deadline)
		defer cancel()
		for {
			result, err := client.DiscoPing(checkCtx)
			if ctx.Err() != nil {
				return
			}
			if err != nil {
				emit(map[string]any{"diagnostic": "路径检查超时，请检查网络和分享状态", "checkFailed": true})
				return
			}
			path := "中继"
			if result.Endpoint != "" {
				path = "直连"
			}
			emit(map[string]any{"path": path, "relay": result.DERPRegionCode, "latencyMs": result.LatencySeconds * 1000, "measuredAt": time.Now().UTC().Format(time.RFC3339), "checkFailed": false})
			if !direct || result.Endpoint != "" {
				emit(map[string]any{"diagnostic": "路径检查完成"})
				return
			}
			select {
			case <-checkCtx.Done():
				emit(map[string]any{"diagnostic": "当前通过中继连接，未建立直连"})
				return
			case <-time.After(time.Second):
			}
		}
	}
	check(false)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if visible {
				check(false)
			}
		case command := <-commands:
			switch command.Action {
			case "visible":
				visible = command.Visible
			case "check":
				check(false)
			case "direct":
				check(true)
			}
		}
	}
}
