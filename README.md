# Rakazo Bots for Omarchy

An Omarchy bar roster for a self-hosted [Rakazo](https://github.com/elie222/rakazo). It puts a compact
Rakazo hub on the bar, reveals your bots when you hover it, marks who is working, waiting on you, or
unread, and shows a live trail of the last messages for one bot.

It is a remake of [Grok Bots for Omarchy](https://github.com/glorics/omarchy-grok-bots) by glorics,
for Rakazo instead of the Grok Bot client. It is not an official Rakazo plugin.

## The tray

- The black round face is Rakazo itself. Its eyes follow the pointer while you move across the
  widget, and its bubble counts bots with unread messages.
- The widget stays collapsed to that one hub face. Hover it to roll out up to **eight** colored bots;
  move the pointer away and they fold back in. Bots that are waiting on you come first, then working,
  then unread.
- Faces are drawn like Rakazo draws them: `organic` blobs or `robot` orbs, depending on the avatar style
  in your Rakazo settings, from each bot's color and id. Working and waiting faces move the way they do
  in the app. A white dot means unread or waiting on you.
- The hub turns the urgent color when the stack is stopped, you are signed out, or an update is available.

| Click | What happens |
|---|---|
| A bot face | The panel opens on that bot's live trail |
| The hub | Opens or closes the panel |
| Right-click | Opens or focuses Rakazo, starting the stack first if it is down |
| Middle-click | Checks ghcr.io for a newer `edge` image |

## The panel

- **Live trail:** the last eight messages of the focused bot, newest at the bottom, each clipped to
  160 characters. Your lines are dimmer. A line still being worked on is marked with `·`.
- **Roster:** every bot in the current space with its title, last activity, and preview.
  Working bots say `Working ·`, bots that asked you something say `Waiting ·`.
- **Status:** stack state, computer provider, account, plugin version, running Rakazo revision,
  latest `edge` revision, and when it was checked.
- **Actions:** Open / Focus / Start Rakazo, Sign in or Sign out, Check for updates, Update now,
  Open Rakazo on GitHub.

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move between bots (the trail follows) |
| `Enter` | Open Rakazo on the selected bot |
| `r` | Refresh |
| `u` / `Shift+U` | Check for updates / Update now |
| `s` | Sign in |
| `o` | Open Rakazo |
| `g` | Open Rakazo on GitHub |
| `Tab` / `Esc` | Next bar panel / Close |

Opening a bot starts Rakazo at `/app/<botId>`. If the Rakazo window is already open, it is focused
as it is: a running Chromium app window cannot be pointed at another page from outside.

## How it works

Rakazo keeps its state in Postgres inside Docker, so there is no local snapshot to read like Grok Bot
has. The plugin talks to the Rakazo API instead, through `rakazo_bots.py` (Python standard library only):

1. `POST /rpc/health` tells whether the stack answers and which revision runs.
2. `POST /rpc/me` and `POST /rpc/spaces/list` return your account, avatar style, and bots:
   name, title, color, `unread`, `preview`, and run `status` (`running`, `waiting_input`, …).
3. While the panel is open, `rakazo_bots.py watch` also reads `POST /rpc/threads/get` for the focused
   bot about once a second and prints a JSON line when something changed. The Rakazo web app
   itself polls `spaces/list` every three seconds.
4. While the panel is closed, the roster is re-read every `refreshIntervalSec` seconds.
5. **Check for updates** reads the `org.opencontainers.image.revision` label of
   `ghcr.io/elie222/rakazo/app:edge` anonymously and compares it with the running revision.
   **Update now** runs `install-images.sh` in the stack folder.

Helper output is bounded by `bin/run-capped` and every string is clipped again in QML.

### Signing in

Rakazo has no API keys, so the plugin signs in the way the Rakazo mobile app does. **Sign in** opens a
floating terminal that asks for your Rakazo email and password and calls
`POST /api/auth/sign-in/email`. The returned session token is stored in the Secret Service keyring
with `secret-tool` (attributes `service=rakazo-bots`, `server=<Rakazo URL>`). It is never printed,
logged, put on a command line, or written to a file. Rakazo sessions last seven days and renew while
the widget uses them. **Sign out** ends the session on the server and removes it from the keyring.

## Requirements

- Omarchy 4 (omarchy-shell with Quickshell)
- A self-hosted Rakazo, for example from the published images
- `python3`, `secret-tool` (libsecret) and a running Secret Service such as gnome-keyring
- Docker with the Compose plugin, to start or update a local stack from the widget

## Install

Link the checkout into the plugin folder and enable the bar widget:

```bash
ln -s ~/Personal-Super-Agent/Projects/omarchy-rakazo ~/.config/omarchy/plugins/m0sthatedman.rakazo
omarchy-shell shell rescanPlugins
omarchy plugin enable m0sthatedman.rakazo
omarchy bar set m0sthatedman.rakazo stackDir '~/Work/rakazo'
```

Then open the panel and press `s` to sign in.

Remove it with `omarchy plugin disable m0sthatedman.rakazo` and delete the link. Sign out first if you
also want the session gone from the server and the keyring.

## Settings

Settings live on the widget's entry in `~/.config/omarchy/shell.json`.

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `10` | How often the closed widget re-reads status and bots |
| `webUrl` | `http://127.0.0.1:5173` | Rakazo web URL. Plain `http` only for loopback and private addresses |
| `stackDir` | `~/rakazo` | Folder with `docker-compose.images.yml` and `install-images.sh` |

Numbers need `--json`: `omarchy bar set m0sthatedman.rakazo refreshIntervalSec 20 --json`.

IPC: `omarchy-shell m0sthatedman.rakazo <open|close|toggle|refresh|launch|signin|update|status|unread>`.

## Project structure

```text
manifest.json        plugin manifest (bar-widget, settings schema)
Panel.qml            bar cluster, popup, keys, IPC
Service.qml          stack, account and update status; open, sign in/out, update
Inbox.qml            roster and live trail models; one-shot reads and the watch process
BotAvatar.qml        Rakazo bot faces (organic and robot) with the app's motion
RakazoMark.qml       the Rakazo hub face
CountBubble.qml      count / dot bubble (from Grok Bots)
avatar-shape.js      port of Rakazo's avatar-shape.ts
avatar-motion.js     Rakazo's avatar CSS keyframes
rakazo_bots.py       API helper: status, inbox, watch, login, logout, open, update
bin/run-capped       bounds helper output and runtime (from Grok Bots)
tests/               unit tests, offscreen QML harnesses, API fixtures
```

## Development

```bash
bash tests/smoke.sh
```

It runs the helper unit tests against recorded API fixtures, the QML harnesses in offscreen
Quickshell processes, the `run-capped` limits, and `omarchy plugin validate`.
`tests/test_avatar_shape.qml` checks `avatar-shape.js` against paths generated from Rakazo's own
TypeScript (`tests/fixtures/organic-avatar-paths.json`); regenerate that file when Rakazo changes its
avatar code.

## License

MIT. Portions derived from Grok Bots for Omarchy, Copyright (c) 2026 glorics. Avatar geometry and
motion follow Rakazo (Apache-2.0 or its current license; see the Rakazo repository).
