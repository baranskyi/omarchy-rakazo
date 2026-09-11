import QtQuick
import Quickshell
import Quickshell.Io

// Bot roster and the focused bot's live trail, read from the Rakazo API by
// rakazo_bots.py. While the panel is open a `watch` helper streams one JSON
// line per change; while it is closed the roster is re-read on a timer.
Item {
  id: root

  property var settings: ({})

  property var bots: []
  property int stamp: 0
  property alias botsModel: botList
  property alias chatModel: chatList
  property bool hasSnapshot: false
  property bool signedIn: false
  property bool running: false
  property string avatarStyle: "robot"
  property string spaceName: ""
  property string lastError: ""
  property bool refreshing: false
  property bool live: false
  property bool _pending: false
  property string focusedId: ""
  property string focusedName: ""

  ListModel {
    id: botList
  }

  ListModel {
    id: chatList
  }

  readonly property int maxInboxBytes: 262144
  readonly property int maxBots: 24
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 3, 3600)
  readonly property string webUrl: String(setting("webUrl", "") || "http://127.0.0.1:5173")

  readonly property int botCount: bots.length
  readonly property int unreadCount: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && Number(bots[i].unread || 0) > 0) n++
    return n
  }
  readonly property int unreadBots: unreadCount
  readonly property int waitingCount: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && bots[i].waiting) n++
    return n
  }
  readonly property int busyCount: {
    var n = 0
    for (var i = 0; i < bots.length; i++)
      if (bots[i] && bots[i].busy) n++
    return n
  }
  readonly property var attentionBots: {
    var out = []
    var ids = ""
    function add(b) {
      if (!b || !b.id || out.length >= 8)
        return
      if (ids.indexOf("|" + b.id + "|") >= 0)
        return
      ids += "|" + b.id + "|"
      out.push(b)
    }
    for (var i = 0; i < bots.length; i++) {
      var b = bots[i]
      if (b && (b.waiting || Number(b.unread || 0) > 0 || b.busy))
        add(b)
    }
    for (var j = 0; j < bots.length; j++)
      add(bots[j])
    return out
  }
  readonly property bool lively: waitingCount > 0 || busyCount > 0

  property string _inboxOutput: ""
  property string _inboxError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function localPath(name) {
    return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
  }

  function helperCommand(mode) {
    var argv = ["python3", localPath("rakazo_bots.py"), mode, "--url", webUrl]
    if (live && focusedId !== "")
      argv = argv.concat(["--focus", focusedId])
    return argv
  }

  function clip(s, n) {
    s = String(s || "")
    var out = ""
    for (var i = 0; i < s.length && out.length < n; i++) {
      var c = s.charCodeAt(i)
      if (c < 32 || c === 127 || c === 0x2028 || c === 0x2029)
        continue
      out += s.charAt(i)
    }
    return out
  }

  function allowIdent(s, maxLen) {
    s = clip(String(s || "").trim(), maxLen)
    if (s.length < 1)
      return ""
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      var ok = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch === "." || ch === "_" || ch === "-" || ch === ":"
      if (!ok)
        return ""
    }
    return s
  }

  function allowColor(s) {
    s = clip(String(s || "").trim(), 24)
    if (s.length !== 4 && s.length !== 7)
      return "#8B5CF6"
    if (s.charAt(0) !== "#")
      return "#8B5CF6"
    for (var i = 1; i < s.length; i++) {
      var ch = s.charAt(i).toLowerCase()
      var ok = (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")
      if (!ok)
        return "#8B5CF6"
    }
    return s
  }

  function allowStyle(s) {
    return String(s || "") === "organic" ? "organic" : "robot"
  }

  function sanitizeBots(arr) {
    var out = []
    if (!arr || arr.length === undefined)
      return out
    var n = Math.min(arr.length, root.maxBots)
    for (var i = 0; i < n; i++) {
      var b = arr[i]
      if (!b || typeof b !== "object")
        continue
      var id = root.allowIdent(b.id, 80)
      if (id === "")
        continue
      out.push({
        id: id,
        name: root.clip(b.name, 80) || "Bot",
        team: root.clip(b.team, 40),
        preview: root.clip(b.preview, 140),
        feed: root.clip(b.feed, 200),
        messages: root.sanitizeMessages(b.messages),
        when: root.clip(b.when, 16),
        unread: b.unread === true || Number(b.unread || 0) > 0 ? 1 : 0,
        waiting: b.waiting === true,
        busy: b.busy === true,
        activity: root.clip(b.activity, 40),
        color: root.allowColor(b.color),
        identity: id
      })
    }
    return out
  }

  function sanitizeMessages(arr) {
    var out = []
    if (!arr || arr.length === undefined)
      return out
    var n = Math.min(arr.length, 8)
    for (var i = 0; i < n; i++) {
      var m = arr[i]
      if (!m || typeof m !== "object")
        continue
      var text = root.clip(m.text, 160)
      if (text === "" && m.streaming !== true)
        continue
      out.push({
        id: root.allowIdent(m.id, 80) || ("m" + i),
        role: String(m.role || "") === "assistant" ? "assistant" : "user",
        text: text,
        streaming: m.streaming === true
      })
    }
    return out
  }

  function botById(id) {
    id = String(id || "")
    if (id === "")
      return null
    for (var i = 0; i < root.bots.length; i++) {
      if (String(root.bots[i].id) === id)
        return root.bots[i]
    }
    return null
  }

  function pickChatBot() {
    var focused = root.botById(root.focusedId)
    if (focused)
      return focused
    var keys = ["busy", "waiting"]
    for (var k = 0; k < keys.length; k++) {
      for (var i = 0; i < root.bots.length; i++) {
        if (root.bots[i][keys[k]])
          return root.bots[i]
      }
    }
    for (var u = 0; u < root.bots.length; u++) {
      if (Number(root.bots[u].unread || 0) > 0)
        return root.bots[u]
    }
    return root.bots.length > 0 ? root.bots[0] : null
  }

  function focusBot(bot) {
    if (!bot || !bot.id)
      return
    var changed = root.focusedId !== String(bot.id)
    root.focusedId = String(bot.id)
    root.focusedName = String(bot.name || "Bot")
    root.syncChat(bot)
    root.stamp = root.stamp + 1
    if (changed && root.live)
      root.restartWatch()
  }

  function syncChat(bot) {
    var msgs = (bot && bot.messages) ? bot.messages : []
    var name = bot && bot.name ? bot.name : ""
    var color = bot && bot.color ? bot.color : "#8B5CF6"
    var identity = bot && bot.identity ? bot.identity : ""
    var same = chatList.count === msgs.length
    if (same) {
      for (var i = 0; i < msgs.length; i++) {
        if (String(chatList.get(i).msgId) !== String(msgs[i].id)) {
          same = false
          break
        }
      }
    }
    if (!same) {
      chatList.clear()
      for (var j = 0; j < msgs.length; j++) {
        chatList.append({
          msgId: msgs[j].id,
          role: msgs[j].role,
          line: msgs[j].text,
          streaming: msgs[j].streaming === true,
          botName: name,
          faceColor: color,
          faceIdentity: identity
        })
      }
      return
    }
    for (var k = 0; k < msgs.length; k++) {
      chatList.setProperty(k, "line", msgs[k].text)
      chatList.setProperty(k, "streaming", msgs[k].streaming === true)
      chatList.setProperty(k, "botName", name)
      chatList.setProperty(k, "faceColor", color)
      chatList.setProperty(k, "faceIdentity", identity)
    }
  }

  function clearAll(error) {
    root.refreshing = false
    root.lastError = root.clip(error, 120)
    root.hasSnapshot = false
    root.bots = []
    root.syncModel([])
    chatList.clear()
    root.stamp = root.stamp + 1
  }

  function applyInbox(text) {
    root.refreshing = false
    if (String(text || "").length > root.maxInboxBytes) {
      root.clearAll("inbox snapshot too large")
      return
    }
    var data
    try {
      data = JSON.parse(text)
    } catch (e) {
      root.clearAll("Could not read Rakazo inbox")
      return
    }
    if (!data || data.ok !== true || data.client !== "m0sthatedman.rakazo") {
      root.clearAll(data && data.error ? data.error : "Could not read Rakazo inbox")
      return
    }
    root.signedIn = data.signedIn === true
    root.running = data.running === true
    root.avatarStyle = root.allowStyle(data.avatarStyle)
    root.spaceName = root.clip(data.space, 40)
    root.bots = root.sanitizeBots(data.bots)
    root.syncModel(root.bots)
    root.stamp = root.stamp + 1
    var suggested = root.allowIdent(data.focusId, 80)
    if (root.focusedId !== "" && !root.botById(root.focusedId))
      root.focusedId = ""
    if (root.focusedId === "" && suggested !== "" && root.botById(suggested))
      root.focusedId = suggested
    var chatBot = root.pickChatBot()
    if (chatBot) {
      if (root.focusedId === "")
        root.focusedId = String(chatBot.id)
      root.focusedName = String(chatBot.name || "Bot")
    } else {
      root.focusedName = ""
    }
    root.syncChat(chatBot)
    root.hasSnapshot = true
    root.lastError = root.clip(data.error || "", 120)
  }

  function syncModel(arr) {
    var keys = ["id", "name", "team", "preview", "feed", "when", "unread", "waiting", "busy", "activity", "color", "identity"]
    while (botList.count > arr.length)
      botList.remove(botList.count - 1)
    for (var i = 0; i < arr.length; i++) {
      var b = arr[i]
      if (i >= botList.count) {
        var row = {}
        for (var a = 0; a < keys.length; a++)
          row[keys[a]] = b[keys[a]]
        botList.append(row)
        continue
      }
      for (var k = 0; k < keys.length; k++) {
        var key = keys[k]
        var val = b[key]
        if (val === undefined)
          val = (key === "unread" ? 0 : ((key === "waiting" || key === "busy") ? false : ""))
        botList.setProperty(i, key, val)
      }
    }
  }

  function refresh(force) {
    if (root.live && watchProc.running && force !== true)
      return
    if (inboxProcess.running) {
      root._pending = true
      return
    }
    root.refreshing = true
    root._inboxOutput = ""
    root._inboxError = ""
    inboxProcess.command = ["bash", localPath("bin/run-capped"), "--max-seconds", "20"].concat(root.helperCommand("inbox"))
    inboxProcess.running = true
  }

  function restartWatch() {
    watchProc.running = false
    if (!root.live)
      return
    watchProc.command = root.helperCommand("watch")
    Qt.callLater(function() { watchProc.running = root.live })
  }

  onLiveChanged: {
    if (live)
      restartWatch()
    else
      watchProc.running = false
  }

  Process {
    id: inboxProcess
    running: false
    command: []
    stdout: StdioCollector { id: inboxStdout; waitForEnd: true; onStreamFinished: root._inboxOutput = text }
    stderr: StdioCollector { id: inboxStderr; waitForEnd: true; onStreamFinished: root._inboxError = text }
    onExited: function(exitCode) {
      var stdout = String(inboxStdout.text || root._inboxOutput || "")
      var stderr = String(inboxStderr.text || root._inboxError || "")
      if (exitCode === 0 && stdout.trim() !== "")
        root.applyInbox(stdout)
      else
        root.clearAll(stderr || "Could not read Rakazo inbox")
      if (root._pending && !root.live) {
        root._pending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: watchProc
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        var s = String(line || "").trim()
        if (s !== "")
          root.applyInbox(s)
      }
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: !watchProc.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
