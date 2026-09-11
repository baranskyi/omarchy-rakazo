import QtQuick
import Quickshell
import "plugin" as Plugin

// Harness: Service and Inbox read the recorded Rakazo API through the real
// helper, then the live trail follows the focused bot.
ShellRoot {
  id: shell

  property var failures: []
  property int checks: 0
  property int phase: 0
  property int waited: 0

  function check(name, ok) {
    checks++
    if (!ok)
      failures.push(name)
  }

  function finish() {
    if (failures.length === 0)
      console.log("RAKAZO_BOTS_TESTS_PASSED panel-data " + checks + " checks")
    else
      console.log("RAKAZO_BOTS_TESTS_FAILED " + failures.join("; "))
    Qt.quit()
  }

  Plugin.Service {
    id: service
    settings: ({ webUrl: "http://127.0.0.1:5173", stackDir: "/nonexistent-rakazo-stack", refreshIntervalSec: 3600 })
  }

  Plugin.Inbox {
    id: inbox
    settings: ({ webUrl: "http://127.0.0.1:5173", refreshIntervalSec: 3600 })
  }

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      shell.waited += 100
      if (shell.waited > 25000) {
        shell.failures.push("timed out in phase " + shell.phase + " (inbox error: " + inbox.lastError + ")")
        shell.finish()
        return
      }
      if (shell.phase === 0 && inbox.hasSnapshot && service.checked) {
        shell.check("service is signed in", service.signedIn && service.running)
        shell.check("service status is Connected", service.statusText === "Connected")
        shell.check("service shows the running revision", service.appVersion === "ef63e35")
        shell.check("no stack folder means no self-update", !service.installed && !service.canSelfUpdate)
        shell.check("four visible bots", inbox.botCount === 4)
        shell.check("two unread bots", inbox.unreadCount === 2)
        shell.check("one bot waiting, one working", inbox.waitingCount === 1 && inbox.busyCount === 1)
        shell.check("waiting bot leads the bar", inbox.attentionBots.length === 4 && inbox.attentionBots[0].name === "Ledger")
        shell.check("organic faces from /me", inbox.avatarStyle === "organic")
        shell.check("space name", inbox.spaceName === "Personal")
        shell.check("model rows carry identity for faces", inbox.botsModel.get(1).identity === inbox.botsModel.get(1).id)
        shell.phase = 1
        inbox.live = true
      } else if (shell.phase === 1 && inbox.chatModel.count > 0) {
        shell.check("watch focuses the working bot", inbox.focusedName === "Scout")
        shell.check("trail has the last four lines", inbox.chatModel.count === 4)
        shell.check("trail starts with the user", inbox.chatModel.get(0).role === "user")
        shell.check("trail ends streaming", inbox.chatModel.get(3).streaming === true)
        shell.phase = 2
        inbox.focusBot(inbox.botById("cmf3k9x2q0002bot8j3l5e9t"))
      } else if (shell.phase === 2 && inbox.focusedName === "Ledger" && inbox.lastError !== "") {
        shell.check("switching focus clears the old trail", inbox.chatModel.count === 0)
        shell.check("focus stays on the chosen bot", inbox.focusedId === "cmf3k9x2q0002bot8j3l5e9t")
        inbox.live = false
        shell.finish()
      }
    }
  }
}
