package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"net"
	"sync/atomic"
	"tailscale.com/net/netmon"
)

var interfaceSnapshot atomic.Value

func init() {
	interfaceSnapshot.Store([]netmon.Interface{})
	// Android app UIDs cannot enumerate interfaces with Go's netlink API.
	// Kotlin supplies LinkProperties through JNI instead.
	netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) { return interfaceSnapshot.Load().([]netmon.Interface), nil })
}

//export SetInterfaces
func SetInterfaces(raw *C.char) *C.char {
	var configs []struct {
		Name      string   `json:"name"`
		Index     int      `json:"index"`
		MTU       int      `json:"mtu"`
		Loopback  bool     `json:"loopback"`
		Addresses []string `json:"addresses"`
	}
	if err := json.Unmarshal([]byte(C.GoString(raw)), &configs); err != nil {
		return C.CString("网络接口数据无效")
	}
	interfaces := make([]netmon.Interface, 0, len(configs))
	for _, c := range configs {
		flags := net.FlagUp | net.FlagRunning
		if c.Loopback {
			flags |= net.FlagLoopback
		}
		addrs := make([]net.Addr, 0, len(c.Addresses))
		for _, a := range c.Addresses {
			ip, subnet, err := net.ParseCIDR(a)
			if err != nil {
				return C.CString("网络接口地址无效")
			}
			subnet.IP = ip
			addrs = append(addrs, subnet)
		}
		interfaces = append(interfaces, netmon.Interface{Interface: &net.Interface{Name: c.Name, Index: c.Index, MTU: c.MTU, Flags: flags}, AltAddrs: addrs})
	}
	interfaceSnapshot.Store(interfaces)
	return C.CString("")
}
