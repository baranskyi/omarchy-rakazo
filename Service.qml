import QtQuick
import Quickshell
import Quickshell.Io

// Stack, account, and update status for the self-hosted Rakazo, plus the
// actions that change it: open or start, sign in or out, update the images.
Item {
  id: root

  property var settings: ({})

  property bool checked: false
  property bool installed: false
  property bool running: false
  property bool windowOpen: false
  property bool signedIn: false
  property bool needsModel: false
  property bool updateAvailable: false
  property bool canSelfUpdate: false
  property bool refreshing: false
  property bool updating: false
  property string avatarStyle: "robot"
  property string statusText: "Checking…"
  property string sourceLabel: ""
  property string computerLabel: ""
  property string signedInLabel: "No"
  property string pluginVersion: ""
  property string appVersion: ""
  property string latestVersion: ""
  property string lastCheckText: ""
  property string githubUrl: "https://github.com/elie222/rakazo"
  property string productUrl: "https://rakazo.com"
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 3, 3600)
  readonly property string webUrl: String(setting("webUrl", "") || "http://127.0.0.1:5173")
  readonly property string stackDir: String(setting("stackDir", "") || "~/rakazo")
  readonly property bool busy: statusProcess.running || updateProcess.running || signOutProcess.running
  readonly property bool alarming: updateAvailable || (checked && installed && !running) || (running && !signedIn)

  property int _signInPolls: 0
  property string _statusOutput: ""
  property string _statusError: ""
  property string _updateOutput: ""
  property string _updateError: ""

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

  function helperPath() {
    return localPath("rakazo_bots.py")
  }

  function helperArgs() {
    return ["--url", webUrl, "--stack-dir", stackDir]
  }

  function capped(argv, seconds) {
    return ["bash", localPath("bin/run-capped"), "--max-seconds", String(seconds || 30)].concat(argv)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function clip(value, n) {
    var s = String(value || "")
    n = n || 160
    return s.length > n ? s.substring(0, n) : s
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  function flash(text) {
    actionStatus = clip(text, 64)
    actionStatusTimer.restart()
  }

  function refresh(fetch) {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    var argv = ["python3", helperPath(), "status"].concat(helperArgs())
    if (fetch) argv.push("--fetch")
    statusProcess.command = capped(argv, fetch ? 45 : 20)
    statusProcess.running = true
  }

  function checkForUpdates() {
    actionStatus = "Checking ghcr.io…"
    refresh(true)
  }

  function applyStatus(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      lastError = "Could not read Rakazo status"
      return
    }
    if (!data || data.ok !== true || data.client !== "m0sthatedman.rakazo") {
      lastError = clip(data && data.error ? data.error : "Could not read Rakazo status", 120)
      return
    }
    checked = true
    installed = data.installed === true
    running = data.running === true
    windowOpen = data.windowOpen === true
    signedIn = data.signedIn === true
    needsModel = data.needsModel === true
    updateAvailable = data.updateAvailable === true
    canSelfUpdate = data.canSelfUpdate === true
    avatarStyle = data.avatarStyle === "organic" ? "organic" : "robot"
    statusText = clip(data.statusText || "", 64)
    sourceLabel = clip(data.sourceLabel || "", 64)
    computerLabel = clip(data.computerLabel || "", 32)
    signedInLabel = clip(data.signedInLabel || (signedIn ? "Yes" : "No"), 64)
    pluginVersion = clip(data.pluginVersion || "", 32)
    appVersion = clip(data.appVersion || "", 32)
    latestVersion = clip(data.latestVersion || "", 32)
    lastCheckText = clip(data.lastCheckText || "", 24)
    lastError = clip(data.error || "", 120)
    if (signedIn) _signInPolls = 0
  }

  function launch(botId) {
    var argv = ["python3", helperPath(), "open"].concat(helperArgs())
    if (botId) argv = argv.concat(["--bot", String(botId)])
    Quickshell.execDetached(argv)
    if (!running)
      actionStatus = "Starting Rakazo…"
    else
      actionStatus = windowOpen ? "Focusing Rakazo" : "Opening Rakazo"
    actionStatusTimer.restart()
    delayedRefresh.restart()
  }

  function signIn() {
    var command = "python3 " + shellQuote(helperPath()) + " login --url " + shellQuote(webUrl)
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", command])
    flash("Sign in from the terminal")
    _signInPolls = 40
    signInPoll.restart()
  }

  function signOut() {
    if (signOutProcess.running) return
    signOutProcess.command = capped(["python3", helperPath(), "logout"].concat(helperArgs()), 15)
    signOutProcess.running = true
  }

  function updateNow() {
    if (updateProcess.running) return
    if (!canSelfUpdate) {
      checkForUpdates()
      return
    }
    _updateOutput = ""
    _updateError = ""
    updating = true
    actionStatus = "Pulling Rakazo edge images…"
    updateProcess.command = capped(["python3", helperPath(), "update"].concat(helperArgs()), 1200)
    updateProcess.running = true
  }

  function openGitHub() {
    Quickshell.execDetached(["omarchy-launch-browser", githubUrl])
  }

  function openProduct() {
    Quickshell.execDetached(["omarchy-launch-browser", productUrl])
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Timer {
    id: delayedRefresh
    interval: 1500
    repeat: false
    onTriggered: root.refresh(false)
  }

  // After "Sign in" opens a terminal, look for the new session for two minutes.
  Timer {
    id: signInPoll
    interval: 3000
    repeat: true
    running: false
    onTriggered: {
      if (root._signInPolls <= 0 || root.signedIn) {
        stop()
        return
      }
      root._signInPolls = root._signInPolls - 1
      root.refresh(false)
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: if (!root.updating) root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0 && stdout.trim() !== "") {
        root.applyStatus(stdout)
        if (root.actionStatus === "Checking ghcr.io…") {
          if (root.updateAvailable)
            root.actionStatus = "Update available · " + root.latestVersion
          else if (root.latestVersion !== "")
            root.actionStatus = "Up to date · " + root.latestVersion
          else
            root.actionStatus = "Could not read ghcr.io"
          actionStatusTimer.restart()
        }
      } else {
        root.lastError = root.elideStatus(stderr || stdout || "Could not read Rakazo status")
      }
    }
  }

  Process {
    id: updateProcess
    running: false
    command: []
    stdout: StdioCollector { id: updateStdout; waitForEnd: true; onStreamFinished: root._updateOutput = text }
    stderr: StdioCollector { id: updateStderr; waitForEnd: true; onStreamFinished: root._updateError = text }
    onExited: function(exitCode) {
      root.updating = false
      var stdout = String(updateStdout.text || root._updateOutput || "").trim()
      var stderr = String(updateStderr.text || root._updateError || "").trim()
      if (exitCode === 0) {
        root.lastError = ""
        root.actionStatus = root.clip(stdout !== "" ? stdout.split("\n").pop() : "Updated", 64)
      } else {
        root.lastError = root.elideStatus(stderr || stdout || "Update failed")
        root.actionStatus = root.lastError
      }
      actionStatusTimer.restart()
      root.refresh(false)
    }
  }

  Process {
    id: signOutProcess
    running: false
    command: []
    stdout: StdioCollector { id: signOutStdout; waitForEnd: true }
    stderr: StdioCollector { id: signOutStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var message = String((exitCode === 0 ? signOutStdout.text : signOutStderr.text) || "").trim()
      root.flash(message !== "" ? message : (exitCode === 0 ? "Signed out" : "Sign out failed"))
      root.refresh(false)
    }
  }
}
