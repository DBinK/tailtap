#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
"""Run both Flutter apps against real tunnels; ADB carries coordination only."""

import argparse
import json
import os
import selectors
import shlex
import shutil
import signal
import subprocess
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Coordinator:
    def __init__(self) -> None:
        self.values: dict[str, dict] = {}
        self.lock = threading.Lock()

    def handler(self, *, target: bool = False) -> type[BaseHTTPRequestHandler]:
        coordinator = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:
                # Connection cards contain credentials. Do not log request data.
                pass

            def do_GET(self) -> None:
                if target:
                    self.respond(b"TAILTAP_MAC_TARGET")
                else:
                    with coordinator.lock:
                        value = coordinator.values.get(self.path.removeprefix("/"), {})
                    self.respond(json.dumps(value).encode())

            def do_POST(self) -> None:
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                    if not 0 < length <= 65536:
                        raise ValueError("Invalid body size")
                    value = json.loads(self.rfile.read(length))
                    if not isinstance(value, dict):
                        raise TypeError("Expected an object")
                except (ValueError, TypeError, UnicodeError):
                    self.send_error(400, "Invalid coordination request")
                    return
                key = self.path.removeprefix("/")
                with coordinator.lock:
                    coordinator.values[key] = value
                if key.endswith("-pass"):
                    print(f"PASS: {key}", flush=True)
                self.respond(json.dumps(value).encode())

            def respond(self, body: bytes) -> None:
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                try:
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        return Handler


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    for sig, timeout in ((signal.SIGINT, 5), (signal.SIGTERM, 5), (signal.SIGKILL, 5)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=timeout)
            return
        except subprocess.TimeoutExpired:
            continue


def serve(stack: ExitStack, handler: type[BaseHTTPRequestHandler]) -> int:
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def close() -> None:
        server.shutdown()
        server.server_close()
        thread.join()

    stack.callback(close)
    return server.server_port


def termux_target(stack: ExitStack, host: str) -> dict:
    code = (
        'const http=require("node:http");'
        'const s=http.createServer((req,res)=>res.end("TAILTAP_ANDROID_TARGET"));'
        's.listen(0,"127.0.0.1",()=>console.log(JSON.stringify({port:s.address().port})));'
        'process.stdin.resume();process.stdin.on("end",()=>s.close(()=>process.exit(0)));'
    )
    process = subprocess.Popen(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=8",
            host,
            f"node -e {shlex.quote(code)}",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    def close() -> None:
        if process.stdin:
            process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            stop_process(process)
        if process.stdout:
            process.stdout.close()

    stack.callback(close)
    assert process.stdout is not None
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        if not selector.select(timeout=10):
            raise TimeoutError("Termux HTTP target did not become ready")
        value = json.loads(process.stdout.readline())
    if not isinstance(value, dict) or not isinstance(value.get("port"), int):
        raise TypeError("Termux returned invalid target metadata")
    print("Termux independent HTTP target is ready", flush=True)
    return value


def discard_copy(path: Path) -> None:
    # Keep removal reversible, including temporary build checkouts.
    trash = shutil.which("trash")
    if trash:
        subprocess.run([trash, str(path)], check=True)
    else:
        print(f"Temporary build retained: {path}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="ADB device ID")
    args = parser.parse_args()
    adb = os.environ.get("ADB", "adb")
    root = Path(__file__).resolve().parents[1]
    processes: list[subprocess.Popen] = []
    process_lock = threading.Lock()
    failed = threading.Event()

    def stop_all() -> None:
        with process_lock:
            running = list(processes)
        for process in running:
            stop_process(process)

    with ExitStack() as stack:
        copy = Path(tempfile.mkdtemp(prefix="tailtap-cross-android-"))
        stack.callback(discard_copy, copy)
        shutil.copytree(
            root,
            copy,
            dirs_exist_ok=True,
            ignore=shutil.ignore_patterns(
                ".git", "build", ".dart_tool", ".gradle", ".kotlin", "Pods"
            ),
        )
        coordinator = Coordinator()
        coordinator.values["host-target"] = {
            "port": serve(stack, coordinator.handler(target=True))
        }
        port = serve(stack, coordinator.handler())
        if host := os.environ.get("TERMUX_HOST"):
            coordinator.values["termux-target"] = termux_target(stack, host)
        reverse = [adb, "-s", args.device, "reverse"]
        subprocess.run(
            [*reverse, f"tcp:{port}", f"tcp:{port}"],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        stack.callback(
            subprocess.run, [*reverse, "--remove", f"tcp:{port}"], check=False
        )
        stack.callback(stop_all)

        def run(name: str, directory: Path, device: str) -> int:
            with process_lock:
                if failed.is_set():
                    return 1
                process = subprocess.Popen(
                    [
                        "flutter",
                        "test",
                        "integration_test/cross_device_test.dart",
                        "-d",
                        device,
                        "--reporter",
                        "expanded",
                        f"--dart-define=TAILTAP_COORDINATOR_PORT={port}",
                    ],
                    cwd=directory,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    start_new_session=True,
                )
                processes.append(process)
            assert process.stdout is not None
            try:
                for line in process.stdout:
                    print(f"{name}: {line}", end="", flush=True)
                status = process.wait()
            finally:
                process.stdout.close()
            if status:
                failed.set()
                stop_all()
            return status

        pool = ThreadPoolExecutor(max_workers=2)
        try:
            jobs = [
                pool.submit(run, "Mac", root, "macos"),
                pool.submit(run, "Android", copy, args.device),
            ]
            statuses = [job.result() for job in jobs]
            return 0 if all(status == 0 for status in statuses) else 1
        finally:
            failed.set()
            stop_all()
            pool.shutdown(wait=True, cancel_futures=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
