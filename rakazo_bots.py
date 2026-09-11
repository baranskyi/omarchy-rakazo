#!/usr/bin/env python3
"""Rakazo Bots helper for the Omarchy bar plugin.

Talks to a self-hosted Rakazo over its HTTP API (/rpc/*, /api/auth/*) with a
session token kept in the keyring (secret-tool). Prints bounded JSON for the
QML side. Never prints, logs, passes on argv, or writes the token to disk.

  status [--fetch]     stack, account and update state (--fetch asks ghcr.io)
  inbox [--focus ID]   bot roster, plus the focused bot's last messages
  watch [--focus ID]   the inbox as one JSON line per change, for an open panel
  login | logout       create or end the session (login prompts in a terminal)
  open [--bot ID]      start the stack if needed, then open or focus the app
  update               pull the edge images and restart the stack

RAKAZO_BOTS_FIXTURE_DIR switches every API call to files under <dir>/api for
tests: no network, keyring, Hyprland, Docker, or notifications.
"""

from __future__ import annotations

import argparse
import getpass
import ipaddress
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

CLIENT = "m0sthatedman.rakazo"
ROOT = Path(__file__).resolve().parent
DEFAULT_URL = "http://127.0.0.1:5173"
DEFAULT_STACK_DIR = "~/rakazo"
KEYRING_SERVICE = "rakazo-bots"
GITHUB_URL = "https://github.com/elie222/rakazo"
GHCR_REPO = "elie222/rakazo/app"
FIXTURES = os.environ.get("RAKAZO_BOTS_FIXTURE_DIR", "")
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
MAX_STDOUT_BYTES = 256 * 1024
MAX_BOTS = 24
MAX_MESSAGES = 8
MAX_TEXT = 160
MAX_FIELD = 140
WATCH_SECONDS = 1.0
ACTIVE = {"queued", "leased", "running"}
WAITING = {"waiting_input", "waiting_takeover"}
TEXT_BLOCKS = {
    "text", "ask", "progress", "meta", "computer", "handoff",
    "channel_message", "bot_message_sent", "bot_message_received",
}
COMPUTER_LABELS = {"docker": "Docker", "e2b": "E2B", "daytona": "Daytona", "box": "Box", "none": "None"}
ID_RE = re.compile(r"^[A-Za-z0-9._:-]{1,80}$")
COLOR_RE = re.compile(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")


class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def clip(value, n: int = MAX_FIELD, ellipsis: bool = False) -> str:
    text = " ".join(str(value if value is not None else "").split())
    text = "".join(ch for ch in text if ord(ch) >= 32 and ord(ch) != 127)
    if len(text) <= n:
        return text
    return text[: n - 1] + "…" if ellipsis else text[:n]


def safe_id(value) -> str:
    text = str(value or "")
    return text if ID_RE.match(text) else ""


def safe_color(value) -> str:
    text = str(value or "")
    return text if COLOR_RE.match(text) else "#8B5CF6"


def emit(obj: dict) -> None:
    raw = json.dumps(obj, ensure_ascii=True, separators=(",", ":"))
    if len(raw) > MAX_STDOUT_BYTES:
        raw = json.dumps({"ok": False, "client": CLIENT, "error": "Output too large"})
    sys.stdout.write(raw + "\n")
    sys.stdout.flush()


def now_seconds() -> float:
    try:
        return float(os.environ["RAKAZO_BOTS_NOW"])
    except (KeyError, ValueError):
        return time.time()


def parse_iso(value) -> float:
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except (TypeError, ValueError):
        return 0.0


def relative_time(stamp: float, now: float) -> str:
    if stamp <= 0:
        return ""
    delta = max(0, int(now - stamp))
    if delta < 60:
        return "now"
    if delta < 3600:
        return f"{delta // 60}m"
    if delta < 86400:
        return f"{delta // 3600}h"
    days = delta // 86400
    return f"{days}d" if days < 14 else f"{days // 7}w"


def ago_text(stamp) -> str:
    try:
        seconds = max(0, int(now_seconds() - float(stamp)))
    except (TypeError, ValueError):
        return ""
    if float(stamp or 0) <= 0:
        return ""
    if seconds < 45:
        return "just now"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 172800:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def plugin_version() -> str:
    try:
        return clip(json.loads((ROOT / "manifest.json").read_text("utf-8")).get("version"), 32)
    except (OSError, ValueError):
        return ""


def base_url(raw: str) -> str:
    url = (raw or DEFAULT_URL).strip().rstrip("/")
    parts = urllib.parse.urlsplit(url)
    host = parts.hostname or ""
    if parts.scheme not in ("http", "https") or not host or parts.username or parts.password or parts.query or parts.fragment:
        raise ValueError("Rakazo URL must look like http://host:port")
    if parts.scheme == "http" and not private_host(host):
        raise ValueError("Plain http is allowed only for loopback and private addresses")
    return f"{parts.scheme}://{parts.netloc}{parts.path}"


def private_host(host: str) -> bool:
    if host == "localhost" or host.endswith(".localhost"):
        return True
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return (ip.is_loopback or ip.is_private) and not ip.is_link_local


def origin_of(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}"


def stack_dir(raw: str) -> Path:
    return Path(os.path.expanduser(raw or DEFAULT_STACK_DIR))


def state_dir() -> Path:
    raw = os.environ.get("RAKAZO_BOTS_STATE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "rakazo-bots")
    return Path(raw)


def read_cache() -> dict:
    try:
        data = json.loads((state_dir() / "latest.json").read_text("utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def write_cache(data: dict) -> None:
    folder = state_dir()
    try:
        if folder.is_symlink():
            return
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        tmp = folder / f".latest.{os.getpid()}.tmp"
        tmp.write_text(json.dumps(data), "utf-8")
        os.chmod(tmp, 0o600)
        os.replace(tmp, folder / "latest.json")
    except OSError:
        pass


def run(argv: list, *, timeout: float = 10, stdin: str | None = None, cwd: Path | None = None) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(argv, input=stdin, capture_output=True, text=True, timeout=timeout,
                              cwd=cwd, stdin=None if stdin is not None else subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, "", str(exc)
    return proc.returncode, proc.stdout[-65536:], proc.stderr[-65536:]


# Keyring ---------------------------------------------------------------------

def keyring_attrs(url: str) -> list:
    return ["service", KEYRING_SERVICE, "server", url]


def load_token(url: str) -> str:
    if FIXTURES:
        return "fixture" if (Path(FIXTURES) / "api" / "me.json").is_file() else ""
    code, out, _ = run(["secret-tool", "lookup", *keyring_attrs(url)], timeout=5)
    return out.strip() if code == 0 else ""


def store_token(url: str, token: str) -> bool:
    code, _, _ = run(["secret-tool", "store", "--label", f"Rakazo Bots ({url})", *keyring_attrs(url)],
                     stdin=token, timeout=60)
    return code == 0


def clear_token(url: str) -> None:
    run(["secret-tool", "clear", *keyring_attrs(url)], timeout=10)


# HTTP ------------------------------------------------------------------------

def http_json(url: str, *, method: str = "GET", body=None, headers: dict | None = None,
              timeout: float = 5, local: bool = True):
    data = None if body is None else json.dumps(body).encode("utf-8")
    all_headers = {"accept": "application/json", **(headers or {})}
    if data is not None:
        all_headers["content-type"] = "application/json"
    request = urllib.request.Request(url, data=data, method=method, headers=all_headers)
    # Never hand a Rakazo session to a proxy or follow a redirect with it.
    handlers = [urllib.request.ProxyHandler({}), _NoRedirect()] if local else []
    opener = urllib.request.build_opener(*handlers)
    try:
        with opener.open(request, timeout=timeout) as response:
            raw = response.read(MAX_RESPONSE_BYTES + 1)
            status, response_headers = response.status, response.headers
    except urllib.error.HTTPError as exc:
        raw, status, response_headers = exc.read(65536), exc.code, exc.headers
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ApiError(0, "Rakazo is not reachable") from None
    if len(raw) > MAX_RESPONSE_BYTES:
        raise ApiError(status, "Response too large")
    try:
        payload = json.loads(raw.decode("utf-8")) if raw else None
    except (UnicodeDecodeError, ValueError):
        payload = None
    return status, payload, response_headers


class Client:
    def __init__(self, url: str, token: str):
        self.url = url
        self.token = token
        self._me: tuple[float, dict] | None = None

    def rpc(self, procedure: str, payload: dict | None = None, *, auth: bool = True):
        if auth and not self.token:
            raise ApiError(401, "Not signed in")
        if FIXTURES:
            return fixture_rpc(procedure, payload)
        headers = {"authorization": f"Bearer {self.token}"} if auth else {}
        body = {} if payload is None else {"json": payload}
        status, data, _ = http_json(f"{self.url}/rpc/{procedure}", method="POST", body=body, headers=headers)
        if status == 200 and isinstance(data, dict) and "json" in data:
            return data["json"]
        message = ""
        if isinstance(data, dict) and isinstance(data.get("json"), dict):
            message = str(data["json"].get("message") or "")
        raise ApiError(status, message or f"Rakazo answered HTTP {status}")

    def me(self, max_age: float = 30) -> dict:
        if self._me and time.monotonic() - self._me[0] < max_age:
            return self._me[1]
        me = self.rpc("me")
        if not isinstance(me, dict):
            raise ApiError(500, "Unexpected /me response")
        self._me = (time.monotonic(), me)
        return me


def fixture_rpc(procedure: str, payload: dict | None):
    base = Path(FIXTURES) / "api"
    if procedure == "threads/get":
        path = base / "threads-get" / f"{safe_id((payload or {}).get('botId'))}.json"
    else:
        path = base / (procedure.replace("/", "-") + ".json")
    if not path.is_file():
        raise ApiError(0 if procedure == "health" else 404, f"No fixture for {procedure}")
    return json.loads(path.read_text("utf-8"))


def health(client: Client, detail: bool = False, local_api: bool = False) -> dict:
    """`/rpc/health` says the stack answers; `detail` adds the API's /health (revision, sandbox)."""
    try:
        data = client.rpc("health", auth=False)
    except ApiError:
        return {}
    if not (isinstance(data, dict) and data.get("ok") is True):
        return {}
    if detail:
        full = api_health(client.url, local_api)
        if full.get("ok") is True:
            return {**data, **full}
    return data


def api_health(url: str, local_api: bool = False) -> dict:
    """The full health document is served only on the API port, which the web proxy does not expose.

    A stack on this machine publishes that port on 127.0.0.1, whatever address the web UI uses;
    otherwise the web host is tried when it is a private address.
    """
    if FIXTURES:
        path = Path(FIXTURES) / "api-health.json"
        return json.loads(path.read_text("utf-8")) if path.is_file() else {}
    host = "127.0.0.1" if local_api else (urllib.parse.urlsplit(url).hostname or "")
    if not private_host(host):
        return {}
    port = os.environ.get("RAKAZO_BOTS_API_PORT", "3100")
    netloc = f"[{host}]:{port}" if ":" in host else f"{host}:{port}"
    try:
        status, body, _ = http_json(f"http://{netloc}/health", timeout=3)
    except ApiError:
        return {}
    return body if status == 200 and isinstance(body, dict) else {}


# Status ----------------------------------------------------------------------

def window_class(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    return f"chrome-{parts.hostname or ''}__{(parts.path or '/').strip('/').replace('/', '_')}-Default"


def window_open(url: str) -> bool:
    if FIXTURES:
        path = Path(FIXTURES) / "hypr-clients.json"
        raw = path.read_text("utf-8") if path.is_file() else "[]"
    else:
        code, raw, _ = run(["hyprctl", "clients", "-j"], timeout=3)
        if code != 0:
            return False
    try:
        clients = json.loads(raw)
    except ValueError:
        return False
    wanted = window_class(url)
    return any(isinstance(c, dict) and c.get("class") == wanted for c in clients or [])


def ghcr_latest() -> dict:
    if FIXTURES:
        path = Path(FIXTURES) / "ghcr.json"
        return json.loads(path.read_text("utf-8")) if path.is_file() else {}
    arch = {"x86_64": "amd64", "aarch64": "arm64", "arm64": "arm64"}.get(platform.machine().lower(), "amd64")
    base = f"https://ghcr.io/v2/{GHCR_REPO}"
    _, token_body, _ = http_json(f"https://ghcr.io/token?scope=repository:{GHCR_REPO}:pull&service=ghcr.io",
                                 timeout=10, local=False)
    auth = {"authorization": f"Bearer {(token_body or {}).get('token', '')}"}
    index_types = "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json"
    manifest_types = "application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"
    _, index, _ = http_json(f"{base}/manifests/edge", headers={**auth, "accept": index_types}, timeout=10, local=False)
    manifest = index or {}
    for entry in manifest.get("manifests") or []:
        platform_info = entry.get("platform") or {}
        if platform_info.get("os") == "linux" and platform_info.get("architecture") == arch:
            _, manifest, _ = http_json(f"{base}/manifests/{entry.get('digest')}",
                                       headers={**auth, "accept": manifest_types}, timeout=10, local=False)
            break
    digest = ((manifest or {}).get("config") or {}).get("digest")
    if not digest:
        return {}
    _, config, _ = http_json(f"{base}/blobs/{digest}", headers=auth, timeout=15, local=False)
    labels = ((config or {}).get("config") or {}).get("Labels") or {}
    return {"revision": clip(labels.get("org.opencontainers.image.revision"), 64),
            "created": clip(labels.get("org.opencontainers.image.created"), 40)}


def notify(summary: str, body: str, urgency: str = "normal") -> None:
    if FIXTURES:
        return
    run(["notify-send", "-a", "Rakazo Bots", "-u", urgency, "-i", "rakazo",
         "-h", "string:x-canonical-private-synchronous:rakazo-bots", summary, body], timeout=3)


def cmd_status(args) -> int:
    url = args.url
    stack = stack_dir(args.stack_dir)
    client = Client(url, load_token(url))
    installed = (stack / "docker-compose.images.yml").is_file()
    info = health(client, detail=True, local_api=installed)
    running = bool(info)
    revision = clip(info.get("revision"), 64)
    me: dict = {}
    error = ""
    if running and client.token:
        try:
            me = client.me()
        except ApiError as exc:
            if exc.status not in (401, 403):
                error = clip(str(exc), 80)
    signed_in = bool(me)
    cache = read_cache()
    if args.fetch:
        try:
            latest = ghcr_latest()
        except (ApiError, ValueError, KeyError, TypeError):
            latest = {}
            error = error or "Could not read ghcr.io"
        if latest.get("revision"):
            cache.update(latest)
        cache["checkedAt"] = now_seconds()
        newest = str(cache.get("revision") or "")
        if revision and newest and newest != revision and cache.get("lastNotified") != newest:
            notify(f"Rakazo {newest[:7]} is on ghcr.io", "Open the Rakazo Bots panel to update.")
            cache["lastNotified"] = newest
        write_cache(cache)
    newest = str(cache.get("revision") or "")
    update_available = bool(revision and newest and newest != revision)
    sandbox = str(me.get("sandboxProvider") or info.get("sandbox") or "")
    if not running:
        status_text = "Stack stopped" if installed else "Not installed"
    elif not signed_in:
        status_text = "Not signed in"
    elif me.get("needsModel"):
        status_text = "No model connected"
    else:
        status_text = "Connected"
    emit({
        "ok": True,
        "client": CLIENT,
        "installed": installed,
        "running": running,
        "windowOpen": window_open(url),
        "signedIn": signed_in,
        "signedInLabel": clip(me.get("email"), 64) if signed_in else "No",
        "needsModel": bool(me.get("needsModel")),
        "avatarStyle": "organic" if me.get("avatarStyle") == "organic" else "robot",
        "statusText": status_text,
        "sourceLabel": "Docker · published images" if installed else ("Rakazo server" if running else ""),
        "computerLabel": COMPUTER_LABELS.get(sandbox, clip(sandbox, 24)),
        "pluginVersion": plugin_version(),
        "appVersion": revision[:7],
        "latestVersion": newest[:7],
        "updateAvailable": update_available,
        "canSelfUpdate": update_available and installed and (stack / "install-images.sh").is_file(),
        "lastCheckText": ago_text(cache.get("checkedAt")),
        "webUrl": url,
        "githubUrl": GITHUB_URL,
        "error": error,
    })
    return 0


# Inbox -----------------------------------------------------------------------

def sanitize_bot(row: dict, now: float) -> dict | None:
    ident = safe_id(row.get("id"))
    if not ident or row.get("archivedAt"):
        return None
    status = str(row.get("status") or "idle")
    busy, waiting = status in ACTIVE, status in WAITING
    stamp = parse_iso(row.get("updatedAt"))
    return {
        "id": ident,
        "name": clip(row.get("name") or "Bot", 80),
        "team": clip(row.get("title"), 40),
        "preview": clip(row.get("preview"), MAX_FIELD, ellipsis=True),
        "feed": "",
        "messages": [],
        "when": relative_time(stamp, now),
        "unread": 1 if row.get("unread") is True else 0,
        "waiting": waiting,
        "busy": busy,
        "activity": "Working" if busy else ("Waiting" if waiting else ""),
        "status": clip(status, 24),
        "color": safe_color(row.get("color")),
        "_stamp": stamp,
    }


def message_text(message: dict) -> str:
    parts = []
    for block in message.get("blocks") or []:
        if not isinstance(block, dict):
            continue
        kind = block.get("kind")
        if kind in TEXT_BLOCKS:
            parts.append(str(block.get("text") or ""))
        elif kind == "choice":
            parts.append(str(block.get("question") or ""))
        elif kind == "subagent":
            parts.append(str(block.get("progress") or block.get("task") or ""))
        elif kind in ("image", "file"):
            parts.append(f"[{block.get('name') or kind}]")
    return clip(" ".join(p for p in parts if p), MAX_TEXT, ellipsis=True)


def live_trail(snapshot: dict) -> list:
    run_info = snapshot.get("run") if isinstance(snapshot.get("run"), dict) else {}
    run_active = str(run_info.get("status") or "") in ACTIVE | WAITING
    shown = []
    for message in snapshot.get("messages") or []:
        if not isinstance(message, dict) or message.get("role") not in ("user", "bot"):
            continue
        text = message_text(message)
        ident = str(message.get("id") or "")
        streaming = run_active and ident.startswith("progress:")
        if not text and not streaming:
            continue
        shown.append({
            "id": clip(ident, 80),
            "role": "assistant" if message.get("role") == "bot" else "user",
            "text": text,
            "streaming": streaming,
        })
    return shown[-MAX_MESSAGES:]


def build_inbox(client: Client, focus: str = "", auto_focus: bool = False) -> dict:
    out = {"ok": True, "client": CLIENT, "signedIn": False, "running": False, "avatarStyle": "robot",
           "space": "", "bots": [], "focusId": "", "error": ""}
    if not health(client):
        out["error"] = "Rakazo is not running"
        return out
    out["running"] = True
    if not client.token:
        return out
    try:
        navigation = client.rpc("spaces/list")
        style = client.me().get("avatarStyle")
    except ApiError as exc:
        if exc.status not in (401, 403):
            out["error"] = clip(str(exc), 80)
        return out
    out["signedIn"] = True
    out["avatarStyle"] = "organic" if style == "organic" else "robot"
    current = (navigation or {}).get("current") or {}
    out["space"] = clip(current.get("name"), 40)
    now = now_seconds()
    bots = [b for b in (sanitize_bot(r, now) for r in current.get("bots") or [] if isinstance(r, dict)) if b]
    bots.sort(key=lambda b: (not b["waiting"], not b["busy"], b["unread"] <= 0, -b["_stamp"]))
    bots = bots[:MAX_BOTS]
    by_id = {b["id"]: b for b in bots}
    focus_id = safe_id(focus) if safe_id(focus) in by_id else ""
    if not focus_id and auto_focus and bots:
        pick = next((b for b in bots if b["busy"]), None) or next((b for b in bots if b["waiting"]), None) \
            or next((b for b in bots if b["unread"]), None) or bots[0]
        focus_id = pick["id"]
    if focus_id:
        try:
            snapshot = client.rpc("threads/get", {"botId": focus_id})
            trail = live_trail(snapshot if isinstance(snapshot, dict) else {})
        except ApiError as exc:
            trail = []
            out["error"] = clip(str(exc), 80)
        bot = by_id[focus_id]
        bot["messages"] = trail
        bot["feed"] = " · ".join(m["text"] for m in trail[:-1][-2:])
        if any(m["streaming"] for m in trail):
            bot["busy"], bot["activity"] = True, "Working"
    for bot in bots:
        bot.pop("_stamp", None)
    out["bots"] = bots
    out["focusId"] = focus_id
    return out


def cmd_inbox(args) -> int:
    emit(build_inbox(Client(args.url, load_token(args.url)), args.focus or ""))
    return 0


def cmd_watch(args) -> int:
    client = Client(args.url, load_token(args.url))
    sticky, previous, token_checked = args.focus or "", "", time.monotonic()
    try:
        while True:
            if not client.token and time.monotonic() - token_checked > 5:
                client.token, token_checked = load_token(args.url), time.monotonic()
            data = build_inbox(client, sticky, auto_focus=True)
            sticky = sticky or data.get("focusId") or ""
            line = json.dumps(data, ensure_ascii=True, separators=(",", ":"))
            if line != previous and len(line) <= MAX_STDOUT_BYTES:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
                previous = line
            time.sleep(WATCH_SECONDS)
    except (BrokenPipeError, KeyboardInterrupt):
        return 0


# Session ---------------------------------------------------------------------

def cmd_login(args) -> int:
    url = args.url
    if FIXTURES:
        print("login is disabled with fixtures", file=sys.stderr)
        return 2
    if not shutil.which("secret-tool"):
        print("secret-tool (libsecret) is required to keep the session.", file=sys.stderr)
        return 1
    print(f"Sign in to Rakazo at {url}")
    try:
        email = input("Email: ").strip()
        password = getpass.getpass("Password: ")
    except (EOFError, KeyboardInterrupt):
        print()
        return 130
    if not email or not password:
        print("Email and password are required.", file=sys.stderr)
        return 1
    try:
        status, body, headers = http_json(f"{url}/api/auth/sign-in/email", method="POST",
                                          body={"email": email, "password": password},
                                          headers={"origin": origin_of(url)}, timeout=20)
    except ApiError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        password = ""
    body = body if isinstance(body, dict) else {}
    if status != 200:
        print(f"Sign-in failed: {clip(body.get('message') or f'HTTP {status}', 120)}", file=sys.stderr)
        return 1
    token = str(body.get("token") or headers.get("set-auth-token") or "")
    if not token:
        print("Sign-in did not return a session.", file=sys.stderr)
        return 1
    if not store_token(url, token):
        print("Could not save the session in the keyring.", file=sys.stderr)
        return 1
    who = clip((body.get("user") or {}).get("email") or email, 80)
    print(f"Signed in as {who}. The session token is kept in your keyring.")
    run(["omarchy-shell", "-q", CLIENT, "refresh"], timeout=5)
    return 0


def cmd_logout(args) -> int:
    url = args.url
    if FIXTURES:
        print("logout is disabled with fixtures", file=sys.stderr)
        return 2
    token = load_token(url)
    if not token:
        print("Not signed in")
        return 0
    try:
        http_json(f"{url}/api/auth/sign-out", method="POST", body={},
                  headers={"authorization": f"Bearer {token}", "origin": origin_of(url)}, timeout=8)
    except ApiError:
        pass
    clear_token(url)
    print("Signed out")
    return 0


# Stack -----------------------------------------------------------------------

def in_stack(stack: Path, argv: list, timeout: float) -> tuple[int, str]:
    """Run argv in the stack folder, through newgrp when this session predates the docker group."""
    code, _, _ = run(["docker", "info", "--format", "{{.ServerVersion}}"], timeout=15)
    if code == 0:
        code, out, err = run(argv, timeout=timeout, cwd=stack)
    else:
        script = f"cd {shlex.quote(str(stack))} && exec {shlex.join(argv)}\n"
        code, out, err = run(["newgrp", "docker"], stdin=script, timeout=timeout)
    lines = [line for line in (out + "\n" + err).splitlines() if line.strip()]
    return code, clip(lines[-1] if lines else "", 120)


def wait_running(client: Client, seconds: float) -> bool:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if health(client):
            return True
        time.sleep(2)
    return False


def cmd_open(args) -> int:
    if FIXTURES:
        print("open is disabled with fixtures", file=sys.stderr)
        return 2
    url, stack = args.url, stack_dir(args.stack_dir)
    client = Client(url, "")
    if not health(client):
        if not (stack / "docker-compose.images.yml").is_file():
            notify("Rakazo is not running", f"No Rakazo stack in {stack}. Set the plugin's stack folder.", "critical")
            return 1
        notify("Rakazo", "Starting the Docker stack…")
        code, last = in_stack(stack, ["docker", "compose", "--env-file", ".env", "-f", "docker-compose.images.yml",
                                      "up", "-d"], timeout=600)
        if code != 0 or not wait_running(client, 180):
            notify("Rakazo did not start", last or "Check docker compose ps in the stack folder.", "critical")
            return 1
    bot = safe_id(args.bot)
    target = f"{url}/app/{bot}" if bot else url
    os.execvp("omarchy-launch-or-focus-webapp", ["omarchy-launch-or-focus-webapp", re.escape(window_class(url)), target])
    return 1


def cmd_update(args) -> int:
    if FIXTURES:
        print("update is disabled with fixtures", file=sys.stderr)
        return 2
    url, stack = args.url, stack_dir(args.stack_dir)
    if not (stack / "install-images.sh").is_file():
        print(f"No install-images.sh in {stack}", file=sys.stderr)
        return 1
    code, last = in_stack(stack, ["bash", "install-images.sh"], timeout=1100)
    if code != 0:
        print(f"Update failed: {last}", file=sys.stderr)
        notify("Rakazo update failed", last, "critical")
        return 1
    revision = clip(health(Client(url, ""), detail=True, local_api=True).get("revision"), 64)
    message = f"Rakazo updated to {revision[:7]}" if revision else "Rakazo updated"
    notify("Rakazo", message)
    print(message)
    return 0


def main(argv: list | None = None) -> int:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--url", default=os.environ.get("RAKAZO_BOTS_URL", DEFAULT_URL))
    common.add_argument("--stack-dir", default=os.environ.get("RAKAZO_BOTS_STACK_DIR", DEFAULT_STACK_DIR))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", parents=[common]).add_argument("--fetch", action="store_true")
    commands.add_parser("inbox", parents=[common]).add_argument("--focus", default="")
    commands.add_parser("watch", parents=[common]).add_argument("--focus", default="")
    commands.add_parser("login", parents=[common])
    commands.add_parser("logout", parents=[common])
    commands.add_parser("open", parents=[common]).add_argument("--bot", default="")
    commands.add_parser("update", parents=[common])
    args = parser.parse_args(argv)
    try:
        args.url = base_url(args.url)
    except ValueError as exc:
        if args.command in ("status", "inbox", "watch"):
            emit({"ok": False, "client": CLIENT, "error": str(exc)})
            return 0
        print(str(exc), file=sys.stderr)
        return 2
    handler = {
        "status": cmd_status, "inbox": cmd_inbox, "watch": cmd_watch, "login": cmd_login,
        "logout": cmd_logout, "open": cmd_open, "update": cmd_update,
    }[args.command]
    return handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
