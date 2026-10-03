package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"context"
	"dev.tailtap/core/engine"
	"encoding/json"
	"sync"
	"time"
	"unsafe"
)

type task struct {
	cancel context.CancelFunc
	done   chan struct{}
}

var mu sync.Mutex
var tasks = map[string]*task{}
var events []string

func emit(id string, v map[string]any) {
	v["id"] = id
	b, _ := json.Marshal(v)
	mu.Lock()
	events = append(events, string(b))
	if len(events) > 1000 {
		events = events[len(events)-1000:]
	}
	mu.Unlock()
}

//export StartTask
func StartTask(idRaw, configRaw *C.char) *C.char {
	id := C.GoString(idRaw)
	var c engine.Config
	if err := json.Unmarshal([]byte(C.GoString(configRaw)), &c); err != nil {
		return C.CString("无效配置")
	}
	if err := engine.Validate(c); err != nil {
		return C.CString(err.Error())
	}
	ctx, cancel := context.WithCancel(context.Background())
	t := &task{cancel: cancel, done: make(chan struct{})}
	mu.Lock()
	if _, exists := tasks[id]; exists {
		mu.Unlock()
		cancel()
		return C.CString("任务已存在")
	}
	tasks[id] = t
	mu.Unlock()
	go func() {
		defer close(t.done)
		err := engine.Run(ctx, c, func(v map[string]any) {
			if ctx.Err() == nil {
				emit(id, v)
			}
		})
		if err != nil && ctx.Err() == nil {
			emit(id, map[string]any{"state": "failed", "error": err.Error()})
		}
	}()
	return C.CString("")
}

//export StopTask
func StopTask(idRaw *C.char) C.int {
	id := C.GoString(idRaw)
	mu.Lock()
	t := tasks[id]
	mu.Unlock()
	if t == nil {
		return 1
	}
	t.cancel()
	select {
	case <-t.done:
		mu.Lock()
		delete(tasks, id)
		mu.Unlock()
		return 1
	case <-time.After(10 * time.Second):
		return 0
	}
}

//export PollEvents
func PollEvents() *C.char {
	mu.Lock()
	pending := events
	events = nil
	mu.Unlock()
	if pending == nil {
		pending = []string{}
	}
	b, _ := json.Marshal(pending)
	return C.CString(string(b))
}

//export FreeString
func FreeString(p *C.char) { C.free(unsafe.Pointer(p)) }
func main()                {}
