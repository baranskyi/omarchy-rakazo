#!/usr/bin/env python3
"""Unit tests for rakazo_bots.py against recorded Rakazo API fixtures."""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
HELPER = ROOT / "rakazo_bots.py"
SCOUT = "cmf3k9x2q0001bot7h2k4d8s"
LEDGER = "cmf3k9x2q0002bot8j3l5e9t"
NOW = str(datetime(2026, 9, 10, 18, 0, tzinfo=timezone.utc).timestamp())

sys.path.insert(0, str(ROOT))
import rakazo_bots  # noqa: E402


class HelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="rakazo-bots-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.fixtures = self.tmp / "fixtures"
        shutil.copytree(FIXTURES, self.fixtures)
        self.stack = self.tmp / "stack"
        self.stack.mkdir()
        (self.stack / "docker-compose.images.yml").write_text("name: rakazo\n")
        (self.stack / "install-images.sh").write_text("#!/bin/bash\n")

    def helper(self, *args, check=True):
        env = os.environ.copy()
        env.update({
            "RAKAZO_BOTS_FIXTURE_DIR": str(self.fixtures),
            "RAKAZO_BOTS_STATE": str(self.tmp / "state"),
            "RAKAZO_BOTS_NOW": NOW,
        })
        proc = subprocess.run([sys.executable, str(HELPER), *args], env=env, capture_output=True, text=True, timeout=30)
        if check:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc

    def json(self, *args):
        return json.loads(self.helper(*args).stdout)

    def test_status_signed_in(self):
        data = self.json("status", "--stack-dir", str(self.stack))
        manifest = json.loads((ROOT / "manifest.json").read_text())
        self.assertEqual(data["client"], "m0sthatedman.rakazo")
        self.assertTrue(data["running"] and data["signedIn"] and data["installed"])
        self.assertEqual(data["statusText"], "Connected")
        self.assertEqual(data["signedInLabel"], "test@example.com")
        self.assertEqual(data["avatarStyle"], "organic")
        self.assertEqual(data["appVersion"], "ef63e35")
        self.assertEqual(data["computerLabel"], "Docker")
        self.assertEqual(data["pluginVersion"], manifest["version"])
        self.assertFalse(data["updateAvailable"])

    def test_fetch_finds_a_newer_edge_image(self):
        (self.fixtures / "ghcr.json").write_text(json.dumps({"revision": "b5e87ca373c9e8397fd3f47da495dff5709c4f84"}))
        data = self.json("status", "--fetch", "--stack-dir", str(self.stack))
        self.assertEqual(data["latestVersion"], "b5e87ca")
        self.assertTrue(data["updateAvailable"] and data["canSelfUpdate"])
        self.assertEqual(data["lastCheckText"], "just now")
        cache = self.tmp / "state" / "latest.json"
        self.assertEqual(stat.S_IMODE(cache.stat().st_mode), 0o600)
        again = self.json("status", "--stack-dir", str(self.tmp / "missing"))
        self.assertTrue(again["updateAvailable"])
        self.assertFalse(again["canSelfUpdate"], "no stack folder, nothing to update")

    def test_signed_out(self):
        (self.fixtures / "api" / "me.json").unlink()
        status = self.json("status", "--stack-dir", str(self.stack))
        self.assertTrue(status["running"])
        self.assertFalse(status["signedIn"])
        self.assertEqual(status["statusText"], "Not signed in")
        inbox = self.json("inbox")
        self.assertTrue(inbox["running"])
        self.assertFalse(inbox["signedIn"])
        self.assertEqual(inbox["bots"], [])

    def test_stack_down(self):
        (self.fixtures / "api" / "health.json").unlink()
        self.assertEqual(self.json("status", "--stack-dir", str(self.stack))["statusText"], "Stack stopped")
        self.assertEqual(self.json("status", "--stack-dir", str(self.tmp / "none"))["statusText"], "Not installed")
        inbox = self.json("inbox")
        self.assertFalse(inbox["running"])
        self.assertEqual(inbox["error"], "Rakazo is not running")

    def test_inbox_roster(self):
        data = self.json("inbox")
        self.assertEqual(data["space"], "Personal")
        self.assertEqual(data["focusId"], "")
        names = [b["name"] for b in data["bots"]]
        self.assertEqual(names, ["Ledger", "Scout", "Muse", "Quiet"], "waiting, working, unread, then recent; archived hidden")
        by = {b["name"]: b for b in data["bots"]}
        self.assertEqual((by["Ledger"]["waiting"], by["Ledger"]["unread"], by["Ledger"]["when"]), (True, 1, "20m"))
        self.assertEqual((by["Scout"]["busy"], by["Scout"]["activity"], by["Scout"]["when"]), (True, "Working", "now"))
        self.assertEqual((by["Muse"]["unread"], by["Muse"]["when"]), (1, "1d"))
        self.assertEqual(by["Quiet"]["when"], "3h")
        self.assertEqual(by["Muse"]["preview"], "Draft two is ready. Shall I tighten the intro?")
        self.assertEqual(by["Scout"]["color"], "#3EC5A8")
        self.assertTrue(all(b["messages"] == [] for b in data["bots"]), "no thread reads without a focus")

    def test_focused_trail(self):
        data = self.json("inbox", "--focus", SCOUT)
        scout = next(b for b in data["bots"] if b["id"] == SCOUT)
        trail = scout["messages"]
        self.assertEqual([m["role"] for m in trail], ["user", "assistant", "assistant", "assistant"], "system lines are skipped")
        self.assertEqual(trail[1]["text"], "On it. I'll check three sources. [screenshot.png]")
        self.assertEqual(len(trail[2]["text"]), 160)
        self.assertTrue(trail[2]["text"].endswith("…"))
        self.assertTrue(trail[3]["streaming"])
        self.assertFalse(any(m["streaming"] for m in trail[:3]))
        self.assertEqual(scout["feed"], trail[1]["text"] + " · " + trail[2]["text"])

    def test_unknown_focus_reads_no_thread(self):
        data = self.json("inbox", "--focus", "not-a-bot")
        self.assertEqual(data["focusId"], "")

    def test_revision_comes_from_the_api_port(self):
        (self.fixtures / "api-health.json").unlink()
        data = self.json("status", "--stack-dir", str(self.stack))
        self.assertTrue(data["running"], "/rpc/health alone still means the stack answers")
        self.assertEqual(data["appVersion"], "")
        self.assertEqual(data["computerLabel"], "Docker", "signed in, /me still names the computer provider")

    def test_watch_picks_the_working_bot(self):
        env = os.environ.copy()
        env.update({"RAKAZO_BOTS_FIXTURE_DIR": str(self.fixtures), "RAKAZO_BOTS_NOW": NOW})
        proc = subprocess.Popen([sys.executable, str(HELPER), "watch"], env=env, stdout=subprocess.PIPE, text=True)
        try:
            line = proc.stdout.readline()
        finally:
            proc.kill()
            proc.wait(timeout=5)
            proc.stdout.close()
        data = json.loads(line)
        self.assertEqual(data["focusId"], SCOUT)
        self.assertEqual(len(next(b for b in data["bots"] if b["id"] == SCOUT)["messages"]), 4)

    def test_session_and_stack_commands_refuse_fixtures(self):
        for command in ("login", "logout", "open", "update"):
            self.assertEqual(self.helper(command, check=False).returncode, 2, command)

    def test_bad_url_is_reported_not_raised(self):
        data = json.loads(self.helper("status", "--url", "http://example.com").stdout)
        self.assertFalse(data["ok"])
        self.assertIn("Plain http", data["error"])


class PureFunctionTest(unittest.TestCase):
    def test_base_url(self):
        ok = ["http://127.0.0.1:5173", "http://localhost:5173/", "http://192.168.1.20:5173", "https://rakazo.example.com"]
        for url in ok:
            self.assertTrue(rakazo_bots.base_url(url).startswith(("http://", "https://")), url)
        for url in ["http://example.com", "http://169.254.1.1", "ftp://127.0.0.1", "http://u:p@127.0.0.1", "http://127.0.0.1/?q=1"]:
            with self.assertRaises(ValueError, msg=url):
                rakazo_bots.base_url(url)

    def test_window_class_matches_chromium_app_windows(self):
        self.assertEqual(rakazo_bots.window_class("http://127.0.0.1:5173"), "chrome-127.0.0.1__-Default")

    def test_clip(self):
        self.assertEqual(rakazo_bots.clip("a\n\tb\x07c d"), "a bc d")
        self.assertEqual(rakazo_bots.clip("abcdef", 4, ellipsis=True), "abc…")
        self.assertEqual(rakazo_bots.safe_color("red"), "#8B5CF6")
        self.assertEqual(rakazo_bots.safe_id("../etc"), "")

    def test_token_never_reaches_output(self):
        source = HELPER.read_text()
        for line in source.splitlines():
            if re.search(r"\b(print|emit|notify)\(", line):
                self.assertNotRegex(line, r"\{\s*token|self\.token|,\s*token\b", line)
        self.assertNotIn("capture_output=False", source)


if __name__ == "__main__":
    unittest.main()
