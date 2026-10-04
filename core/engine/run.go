package engine

import (
	"context"
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tailscale/tailcat"
)

type Config struct {
	Kind             string `json:"kind"`
	FilesDir         string `json:"filesDir"`
	StopAfterSeconds int    `json:"stopAfterSeconds"`
	Mode             string `json:"mode"`
	Host             string `json:"host"`
	Port             int    `json:"port"`
	LocalPort        int    `json:"localPort"`
	Address          string `json:"address"`
	LAN              bool   `json:"lan"`
}

func Validate(c Config) error {
	if c.Mode != "share" && c.Mode != "connect" {
		return fmt.Errorf("无效任务类型")
	}
	if c.Kind == "file" {
		if c.Port != 2222 {
			return fmt.Errorf("文件服务端口无效")
		}
		if c.Mode == "share" && c.FilesDir == "" {
			return fmt.Errorf("没有可分享的文件")
		}
		if c.Mode == "connect" {
			if _, err := tailcat.ParseAddr(tailcat.Addr(c.Address)); err != nil {
				return fmt.Errorf("连接地址无效")
			}
		}
		return nil
	}
	if c.Port < 1 || c.Port > 65535 || c.LocalPort < 0 || c.LocalPort > 65535 {
		return fmt.Errorf("端口范围为 1–65535")
	}
	if c.Mode == "share" && c.Host == "" {
		return fmt.Errorf("请输入目标地址")
	}
	if c.Mode == "connect" {
		_, err := tailcat.ParseAddr(tailcat.Addr(c.Address))
		if err != nil {
			return fmt.Errorf("连接地址无效")
		}
		return nil
	}
	return nil
}

type Command struct {
	Action    string   `json:"action"`
	Visible   bool     `json:"visible"`
	Files     []string `json:"files"`
	Directory string   `json:"directory"`
}

func Run(ctx context.Context, c Config, emit func(map[string]any)) error {
	return RunControlled(ctx, c, emit, nil)
}

func RunControlled(ctx context.Context, c Config, emit func(map[string]any), commands <-chan Command) error {
	if err := Validate(c); err != nil {
		return err
	}
	if c.Kind == "file" {
		return runFileTask(ctx, c, emit, commands)
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	if c.StopAfterSeconds > 0 {
		var timedCancel context.CancelFunc
		ctx, timedCancel = context.WithTimeout(ctx, time.Duration(c.StopAfterSeconds)*time.Second)
		defer timedCancel()
	}
	state := func(s string, fields map[string]any) {
		if fields == nil {
			fields = map[string]any{}
		}
		fields["state"] = s
		emit(fields)
	}
	defer func() {
		if ctx.Err() != nil {
			state("stopped", nil)
		}
	}()
	state("starting", nil)
	discard := func(string, ...any) {}
	var active atomic.Int64
	var up, down atomic.Int64
	var connectionsMu sync.Mutex
	connections := make(map[net.Conn]bool)
	defer func() {
		connectionsMu.Lock()
		defer connectionsMu.Unlock()
		for connection := range connections {
			connection.Close()
		}
	}()
	proxy := func(a, b net.Conn) {
		connectionsMu.Lock()
		connections[a] = true
		connections[b] = true
		connectionsMu.Unlock()
		defer func() { connectionsMu.Lock(); delete(connections, a); delete(connections, b); connectionsMu.Unlock() }()
		active.Add(1)
		defer active.Add(-1)
		defer a.Close()
		defer b.Close()
		done := make(chan struct{})
		go func() {
			_, _ = io.Copy(countWriter{b, &up}, a)
			if t, ok := b.(interface{ CloseWrite() error }); ok {
				_ = t.CloseWrite()
			}
			close(done)
		}()
		_, _ = io.Copy(countWriter{a, &down}, b)
		if t, ok := a.(interface{ CloseWrite() error }); ok {
			_ = t.CloseWrite()
		}
		select {
		case <-done:
		case <-ctx.Done():
		case <-time.After(5 * time.Second):
		}
	}
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				emit(map[string]any{"clients": active.Load(), "up": up.Load(), "down": down.Load()})
			}
		}
	}()
	if c.Mode == "share" {
		target := net.JoinHostPort(c.Host, fmt.Sprint(c.Port))
		server := &tailcat.Server{Logf: discard, OnTCP: func(port uint16) func(net.Conn) {
			if int(port) != c.Port {
				return nil
			}
			return func(remote net.Conn) {
				local, err := net.DialTimeout("tcp", target, 5*time.Second)
				if err != nil {
					remote.Close()
					return
				}
				proxy(remote, local)
			}
		}}
		// Start is not context-aware. The parent kills this isolated process if
		// startup fails to respond to cancellation within its grace period.
		if err := server.Start(); err != nil {
			return err
		}
		defer server.Close()
		if ctx.Err() != nil {
			return nil
		}
		state("sharing", map[string]any{"address": string(server.TailcatAddr()), "path": "等待设备连接"})
		report := func() {
			peers := []map[string]any{}
			direct, relay := 0, 0
			status := server.Status()
			if status != nil {
				for public, peer := range status.Peer {
					if !peer.Active {
						continue
					}
					path := "未知"
					if peer.CurAddr != "" {
						path = "直连"
						direct++
					} else if peer.Relay != "" {
						path = "中继"
						relay++
					}
					peers = append(peers, map[string]any{"public": public.String(), "path": path, "relay": peer.Relay})
				}
			}
			path := "等待设备连接"
			if len(peers) > 0 {
				path = fmt.Sprintf("%d 台设备 · %d 台直连 · %d 台中继", len(peers), direct, relay)
			}
			emit(map[string]any{"path": path, "peers": peers})
		}
		check := func() {
			s, err := net.DialTimeout("tcp", target, 2*time.Second)
			if err == nil {
				s.Close()
			}
			emit(map[string]any{"targetReady": err == nil})
		}
		check()
		report()
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-ticker.C:
				check()
				report()
			case command := <-commands:
				if command.Action == "check" || command.Action == "direct" {
					check()
					report()
					emit(map[string]any{"diagnostic": "分享端已检查目标与设备路径"})
				}
			}
		}
	}
	bind := "127.0.0.1"
	if c.LAN {
		bind = "0.0.0.0"
	}
	ln, err := net.Listen("tcp", net.JoinHostPort(bind, fmt.Sprint(c.LocalPort)))
	if err != nil {
		state("conflict", map[string]any{"error": err.Error()})
		return nil
	}
	defer ln.Close()
	client := &tailcat.Client{Server: tailcat.Addr(c.Address), Logf: discard}
	defer client.Close()
	go diagnose(ctx, client, commands, emit)
	state("waiting", map[string]any{"localPort": ln.Addr().(*net.TCPAddr).Port, "bind": bind, "path": "unknown"})
	go func() { <-ctx.Done(); ln.Close() }()
	go func() {
		check := func() {
			checkCtx, stop := context.WithTimeout(ctx, 8*time.Second)
			defer stop()
			remote, err := client.DialTCPPort(checkCtx, uint16(c.Port))
			if ctx.Err() != nil {
				return
			}
			if err != nil {
				state("waiting", map[string]any{"targetReady": nil, "error": "无法连接远端，请检查网络和分享状态"})
				return
			}
			remote.Close()
			state("running", map[string]any{"tunnelReady": true, "targetReady": nil, "error": ""})
		}
		check()
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				check()
			}
		}
	}()
	for {
		local, err := ln.Accept()
		if err != nil {
			return nil
		}
		go func() {
			dialCtx, stop := context.WithTimeout(ctx, 10*time.Second)
			defer stop()
			remote, err := client.DialTCPPort(dialCtx, uint16(c.Port))
			if err != nil {
				local.Close()
				return
			}
			proxy(local, remote)
		}()
	}
}
