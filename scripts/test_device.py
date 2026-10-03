#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
"""Run Android tunnel tests and verify forwarding while the app is backgrounded."""

import argparse
import os
import re
import subprocess
import threading
from pathlib import Path

from test_cross_device import stop_process


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="ADB device ID")
    args = parser.parse_args()
    adb = os.environ.get("ADB", "adb")
    root = Path(__file__).resolve().parents[1]
    package_match = re.search(
        r'applicationId\s*=\s*"([^"]+)"',
        (root / "android/app/build.gradle.kts").read_text(),
    )
    if package_match is None:
        raise ValueError("Cannot determine Android application ID")
    package = package_match.group(1)
    command = [adb, "-s", args.device, "shell", "am", "start"]
    cancel = threading.Event()
    background: threading.Thread | None = None
    errors: list[Exception] = []

    def check_background() -> None:
        try:
            subprocess.run(
                [
                    *command,
                    "-a",
                    "android.intent.action.MAIN",
                    "-c",
                    "android.intent.category.HOME",
                ],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            if cancel.wait(3):
                return
            state = subprocess.run(
                [
                    adb,
                    "-s",
                    args.device,
                    "shell",
                    "dumpsys",
                    "activity",
                    "services",
                    package,
                ],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            if "isForeground=true" not in state:
                raise RuntimeError("Foreground service flag missing while backgrounded")
            print("HOST: foreground service remains active in background", flush=True)
            cancel.wait(5)
        except (OSError, subprocess.SubprocessError, RuntimeError) as error:
            errors.append(error)
        finally:
            subprocess.run(
                [*command, "-n", f"{package}/.MainActivity"],
                check=False,
                stdout=subprocess.DEVNULL,
            )

    process = subprocess.Popen(
        [
            "flutter",
            "test",
            "integration_test/tunnel_test.dart",
            "-d",
            args.device,
            "--reporter",
            "expanded",
        ],
        cwd=root,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    assert process.stdout is not None
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            if "TAILTAP_BACKGROUND_WINDOW" in line and background is None:
                background = threading.Thread(target=check_background)
                background.start()
        status = process.wait()
    finally:
        cancel.set()
        stop_process(process)
        if background:
            background.join()
        process.stdout.close()
    for error in errors:
        print(f"HOST: {error}", flush=True)
    return status if status else int(bool(errors) or background is None)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
