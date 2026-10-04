package engine

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/pkg/sftp"
	"github.com/tailscale/tailcat"
	"golang.org/x/crypto/ssh"
)

const fileServicePort = 2222

func runFileTask(ctx context.Context, c Config, emit func(map[string]any), commands <-chan Command) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	if c.StopAfterSeconds > 0 {
		var timeout context.CancelFunc
		ctx, timeout = context.WithTimeout(ctx, time.Duration(c.StopAfterSeconds)*time.Second)
		defer timeout()
	}
	emit(map[string]any{"state": "starting"})
	if c.Mode == "share" {
		server := &tailcat.Server{}
		server.OnTCP = func(port uint16) func(net.Conn) {
			if port != fileServicePort {
				return nil
			}
			return server.SSHConnHandler(tailcat.SSHOptions{Files: &tailcat.FileService{Dir: c.FilesDir, Mode: tailcat.FileServeRO}})
		}
		if err := server.Start(); err != nil {
			return err
		}
		defer server.Close()
		emit(map[string]any{"state": "sharing", "address": string(server.TailcatAddr()), "path": "等待设备连接"})
		for {
			select {
			case <-ctx.Done():
				emit(map[string]any{"state": "stopped"})
				return nil
			case command, ok := <-commands:
				if ok && command.Action == "check" {
					emit(map[string]any{"diagnostic": "文件分享服务运行正常"})
				}
			}
		}
	}

	client := &tailcat.Client{Server: tailcat.Addr(c.Address)}
	defer client.Close()
	dialCtx, dialCancel := context.WithTimeout(ctx, 20*time.Second)
	conn, err := client.DialTCPPort(dialCtx, fileServicePort)
	dialCancel()
	if err != nil {
		return fmt.Errorf("无法连接文件分享：%w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))
	sshConn, channels, requests, err := ssh.NewClientConn(conn, "tailtap", &ssh.ClientConfig{
		User: "tailtap", HostKeyCallback: ssh.InsecureIgnoreHostKey(), Timeout: 20 * time.Second,
	})
	if err != nil {
		conn.Close()
		return fmt.Errorf("无法建立文件传输会话：%w", err)
	}
	sshClient := ssh.NewClient(sshConn, channels, requests)
	defer sshClient.Close()
	// SFTP reads can block on the network. Close the SSH transport when the
	// task is stopped so cancellation does not wait indefinitely for a packet.
	go func() {
		<-ctx.Done()
		_ = sshClient.Close()
	}()
	_ = conn.SetDeadline(time.Time{})
	sftpClient, err := sftp.NewClient(sshClient)
	if err != nil {
		return fmt.Errorf("无法读取分享文件：%w", err)
	}
	defer sftpClient.Close()
	entries, err := sftpClient.ReadDir(".")
	if err != nil {
		return fmt.Errorf("无法读取文件清单：%w", err)
	}
	files := make([]map[string]any, 0, len(entries))
	valid := make(map[string]bool)
	for _, entry := range entries {
		name := entry.Name()
		if !entry.Mode().IsRegular() || !safeSharedName(name) {
			continue
		}
		files = append(files, map[string]any{"name": name, "size": entry.Size()})
		valid[name] = true
	}
	emit(map[string]any{"state": "running", "files": files, "diagnostic": fmt.Sprintf("已读取 %d 个文件", len(files))})
	for {
		select {
		case <-ctx.Done():
			emit(map[string]any{"state": "stopped"})
			return nil
		case command, ok := <-commands:
			if !ok {
				return nil
			}
			if command.Action != "download" {
				continue
			}
			if command.Directory == "" || len(command.Files) == 0 {
				emit(map[string]any{"error": "请选择保存位置和文件"})
				continue
			}
			if err := os.MkdirAll(command.Directory, 0o700); err != nil {
				emit(map[string]any{"error": "无法创建保存目录"})
				continue
			}
			for _, name := range command.Files {
				if !valid[name] || !safeSharedName(name) {
					emit(map[string]any{"fileError": name, "error": "分享清单已变化，请重新载入"})
					continue
				}
				if err := downloadSharedFile(ctx, sftpClient, command.Directory, name, emit); err != nil {
					emit(map[string]any{"fileError": name, "error": "文件下载失败：" + err.Error()})
				}
			}
			emit(map[string]any{"downloadDone": true})
		}
	}
}

func safeSharedName(name string) bool {
	return name != "" && name != "." && name != ".." && filepath.Base(name) == name && !strings.ContainsAny(name, "/\\\x00")
}

func downloadSharedFile(ctx context.Context, client *sftp.Client, directory, name string, emit func(map[string]any)) error {
	remote, err := client.Open(name)
	if err != nil {
		return err
	}
	defer remote.Close()
	info, err := remote.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("不是普通文件")
	}
	localPath := filepath.Join(directory, name)
	local, err := os.OpenFile(localPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	complete := false
	defer func() {
		_ = local.Close()
		if !complete {
			_ = os.Remove(localPath)
		}
	}()
	buffer := make([]byte, 128*1024)
	var copied int64
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		n, readErr := remote.Read(buffer)
		if n > 0 {
			written, writeErr := local.Write(buffer[:n])
			copied += int64(written)
			emit(map[string]any{"fileProgress": map[string]any{"name": name, "copied": copied, "size": info.Size(), "directory": directory}})
			if writeErr != nil {
				return writeErr
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return readErr
		}
	}
	if err := local.Close(); err != nil {
		return err
	}
	if copied != info.Size() {
		return fmt.Errorf("文件长度校验失败")
	}
	complete = true
	emit(map[string]any{"fileComplete": name, "fileProgress": map[string]any{"name": name, "copied": copied, "size": info.Size(), "directory": directory}})
	return nil
}
