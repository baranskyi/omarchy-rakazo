import QtQuick
import Quickshell
import "plugin" as Plugin

// Harness: CountBubble shows a count, a waiting pip, or nothing.
ShellRoot {
  id: shell

  property var failures: []

  function check(name, ok) {
    if (!ok)
      failures.push(name)
  }

  Plugin.CountBubble { id: none; count: 0 }
  Plugin.CountBubble { id: some; count: 3 }
  Plugin.CountBubble { id: pipOnly; count: 0; pip: true }
  Plugin.CountBubble { id: pipAndCount; count: 2; pip: true }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      shell.check("zero count hides the bubble", !none.showCount && !none.showPip)
      shell.check("positive count shows the bubble", some.showCount && !some.showPip)
      shell.check("pip shows when nothing is unread", pipOnly.showPip && !pipOnly.showCount)
      shell.check("count wins over pip", pipAndCount.showCount && !pipAndCount.showPip)
      shell.check("pip is smaller than a count pill", pipOnly.implicitWidth < some.implicitWidth)
      if (shell.failures.length === 0)
        console.log("RAKAZO_BOTS_TESTS_PASSED count-bubble 5 checks")
      else
        console.log("RAKAZO_BOTS_TESTS_FAILED " + shell.failures.join("; "))
      Qt.quit()
    }
  }
}
