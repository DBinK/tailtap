# 第三方开源声明

本文件记录 TailTap Go 二进制使用的第三方组件。许可证原文与版权声明保存在 [third_party_licenses](third_party_licenses/) 中；应用随包分发时应一并保留。Go 依赖清单按 `core/cmd/tailtap`、`core/engine` 和 `core/mobile` 的构建依赖扫描，包含：

| 许可证 | 组件 |
| --- | --- |
| BSD 3-Clause | [tailcat](https://github.com/tailscale/tailcat/tree/v0.7.0)、[filippo.io/edwards25519](https://github.com/FiloSottile/edwards25519)、[creachadair/msync](https://github.com/creachadair/msync)、[go-json-experiment/json](https://github.com/go-json-experiment/json)、[ed25519consensus](https://github.com/hdevalence/ed25519consensus)、[kr/fs](https://github.com/kr/fs)、[gliderssh](https://github.com/tailscale/gliderssh)、[hujson](https://github.com/tailscale/hujson)、[peercred](https://github.com/tailscale/peercred)、[web-client-prebuilt](https://github.com/tailscale/web-client-prebuilt)、[u-root termios](https://github.com/u-root/u-root)、[go4.org/netipx](https://github.com/go4org/netipx)、[golang.org/x/crypto](https://cs.opensource.google/go/x/crypto)、[golang.org/x/exp](https://cs.opensource.google/go/x/exp)、[golang.org/x/net](https://cs.opensource.google/go/x/net)、[golang.org/x/sync](https://cs.opensource.google/go/x/sync)、[golang.org/x/sys](https://cs.opensource.google/go/x/sys)、[golang.org/x/term](https://cs.opensource.google/go/x/term)、[golang.org/x/text](https://cs.opensource.google/go/x/text)、[golang.org/x/time](https://cs.opensource.google/go/x/time)、[Tailscale](https://github.com/tailscale/tailscale)、[klauspost/compress internal/snapref](https://github.com/klauspost/compress/tree/v1.19.1/internal/snapref) |
| MIT | [go-shlex](https://github.com/anmitsu/go-shlex)、[creack/pty](https://github.com/creack/pty)、[fxamacker/cbor](https://github.com/fxamacker/cbor)、[gaissmai/bart](https://github.com/gaissmai/bart)、[mitchellh/go-ps](https://github.com/mitchellh/go-ps)、[Tailscale certstore](https://github.com/tailscale/certstore)、[Tailscale wireguard-go](https://github.com/tailscale/wireguard-go)、[x448/float16](https://github.com/x448/float16)、[klauspost/compress internal xxhash](https://github.com/klauspost/compress/tree/v1.19.1/zstd/internal/xxhash) |
| Apache 2.0 | [golang/groupcache](https://github.com/golang/groupcache)、[google/btree](https://github.com/google/btree)、[klauspost/compress](https://github.com/klauspost/compress)、[pires/go-proxyproto](https://github.com/pires/go-proxyproto)、[go4.org/mem](https://github.com/go4org/mem)、[gVisor](https://github.com/google/gvisor) |
| ISC | [coder/websocket](https://github.com/coder/websocket) |
| BSD 2-Clause | [pkg/sftp](https://github.com/pkg/sftp) |

## tailcat

TailTap 使用 Tailscale Inc. 与贡献者开发的 [tailcat v0.7.0](https://github.com/tailscale/tailcat/tree/v0.7.0)。tailcat 根据 BSD 3-Clause 许可证提供。

```text
BSD 3-Clause License

Copyright (c) 2020 Tailscale Inc & contributors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Flutter/Dart package license texts are bundled and shown in the application's “关于与开源许可” page; the dependency graph was checked against `pubspec.lock` using `flutter pub deps`. Go module versions are in `core/go.mod` and `core/go.sum`. The Go license inventory and license files were generated with google/go-licenses v1.6.0 from the three Go build packages named above.
