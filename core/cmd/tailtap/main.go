package main

import (
	"bufio"
	"context"
	"dev.tailtap/core/engine"
	"encoding/json"
	"os"
	"os/signal"
	"sync"
)

var outputMu sync.Mutex

func emit(v map[string]any) {
	outputMu.Lock()
	defer outputMu.Unlock()
	_ = json.NewEncoder(os.Stdout).Encode(v)
}
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return
	}
	var c engine.Config
	if err := json.Unmarshal(scanner.Bytes(), &c); err != nil {
		emit(map[string]any{"state": "failed", "error": "无效配置"})
		return
	}
	if err := engine.Validate(c); err != nil {
		emit(map[string]any{"state": "failed", "error": err.Error()})
		return
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	go func() {
		for scanner.Scan() {
		}
		cancel()
	}()
	if err := engine.Run(ctx, c, emit); err != nil && ctx.Err() == nil {
		emit(map[string]any{"state": "failed", "error": err.Error()})
		return
	}
	if ctx.Err() != nil {
		emit(map[string]any{"state": "stopped"})
	}
}
