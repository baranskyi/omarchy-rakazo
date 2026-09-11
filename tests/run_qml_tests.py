#!/usr/bin/env python3
"""Run the QML harnesses in tests/ inside isolated, offscreen Quickshell processes.

Each harness is a small ShellRoot that imports the real plugin tree as
"plugin" and prints RAKAZO_BOTS_TESTS_PASSED (or RAKAZO_BOTS_TESTS_FAILED)
before quitting. Adapted from the QuickFile harness runner.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = Path("/usr/share/omarchy/shell")
PASSED = "RAKAZO_BOTS_TESTS_PASSED"
FAILED = "RAKAZO_BOTS_TESTS_FAILED"


def run_harness(executable: str, source: Path, timeout: float) -> bool:
    with tempfile.TemporaryDirectory(prefix="rakazo-bots-qml-test-") as temporary:
        directory = Path(temporary)
        config = directory / "config"
        config.mkdir()
        (config / "plugin").symlink_to(ROOT, target_is_directory=True)
        for module in ("Commons", "Ui"):
            if (SHELL / module).is_dir():
                (config / module).symlink_to(SHELL / module, target_is_directory=True)
        target = config / "shell.qml"
        shutil.copy2(source, target)

        runtime = directory / "runtime"
        runtime.mkdir(mode=0o700)
        environment = os.environ.copy()
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"):
            environment.pop(key, None)
        environment.update({
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QPA_PLATFORMTHEME": "",
            "QT_QUICK_CONTROLS_STYLE": "Basic",
            "QT_QUICK_BACKEND": "software",
            "QSG_RHI_BACKEND": "software",
            "QML_DISABLE_DISK_CACHE": "1",
            "XDG_RUNTIME_DIR": str(runtime),
            "XDG_CACHE_HOME": str(directory / "cache"),
            "XDG_STATE_HOME": str(directory / "state"),
            "RAKAZO_BOTS_FIXTURE_DIR": str(ROOT / "tests" / "fixtures"),
            "NO_COLOR": "1",
        })
        command = [executable, "--no-duplicate", "--no-color", "--path", str(target)]
        process = subprocess.Popen(
            command, env=environment, cwd=config, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, start_new_session=True,
        )
        timed_out = False
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                output, _ = process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                output, _ = process.communicate()
        passed = (
            not timed_out and process.returncode == 0
            and PASSED in output and FAILED not in output
        )
        print(f"{'PASS' if passed else 'FAIL'} {source.name}", flush=True)
        if passed:
            for line in output.splitlines():
                if PASSED in line:
                    print(line, flush=True)
        else:
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
            if timed_out:
                print(f"Harness exceeded {timeout:g}s timeout", flush=True)
        return passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="Harness filenames from tests/")
    parser.add_argument("--timeout", type=float, default=45)
    args = parser.parse_args()
    executable = shutil.which("qs") or shutil.which("quickshell")
    if executable is None:
        parser.error("Quickshell (qs) must be installed to run the QML harnesses")
    names = args.tests or sorted(p.name for p in (ROOT / "tests").glob("test_*.qml"))
    if not names:
        parser.error("no tests/test_*.qml harnesses found")
    failures = 0
    for name in names:
        source = ROOT / "tests" / name
        if not source.is_file():
            parser.error(f"QML harness does not exist: {source}")
        failures += not run_harness(executable, source, args.timeout)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
