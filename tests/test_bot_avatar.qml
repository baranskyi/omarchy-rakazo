import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/avatar-shape.js" as AvatarShape

// Harness: BotAvatar picks the app's style, shape and motion for each bot.
ShellRoot {
  id: shell

  property var failures: []
  property int checks: 0

  function check(name, ok) {
    checks++
    if (!ok)
      failures.push(name)
  }

  Plugin.BotAvatar {
    id: organicIdle
    iconSize: 28
    color: "#3EC5A8"
    identity: "cmf3k9x2q0001bot7h2k4d8s"
    avatarStyle: "organic"
  }
  Plugin.BotAvatar {
    id: organicBusy
    iconSize: 16
    compact: true
    color: "#F5A03C"
    identity: "cmf3k9x2q0002bot8j3l5e9t"
    avatarStyle: "organic"
    working: true
  }
  Plugin.BotAvatar {
    id: compactIdle
    iconSize: 16
    compact: true
    color: "#9B5CF6"
    identity: "cmf3k9x2q0005botbl6o8h2w"
    avatarStyle: "organic"
  }
  Plugin.BotAvatar {
    id: robotIdle
    iconSize: 28
    color: "#6A6BF5"
    identity: "cmf3k9x2q0003bot9k4m6f0u"
    avatarStyle: "robot"
  }
  Plugin.BotAvatar {
    id: robotBusy
    iconSize: 28
    color: "#D9508A"
    identity: "cmf3k9x2q0004botak5n7g1v"
    avatarStyle: "robot"
    working: true
  }
  Plugin.BotAvatar {
    id: unknownStyle
    avatarStyle: "sparkly"
    color: "#3B82F6"
  }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      shell.check("organic seed follows the bot id", organicIdle.seed === AvatarShape.identitySeed("cmf3k9x2q0001bot7h2k4d8s"))
      shell.check("organic body starts as the Rakazo shape", organicIdle.bodyPath === AvatarShape.organicPath(organicIdle.seed))
      shell.check("unknown style falls back to robot", !unknownStyle.organic)
      shell.check("idle panel faces animate", organicIdle.ticking && robotIdle.ticking)
      shell.check("idle bar faces hold still", !compactIdle.ticking)
      shell.check("working bar faces animate", organicBusy.ticking)
      shell.check("working motion follows the shape family", organicBusy.motion === AvatarShape.workingMotion(organicBusy.seed))
      shell.check("idle motion is idle", organicIdle.motion === "idle")

      robotBusy.tick(700)
      shell.check("robot ring turns with the CSS spin", Math.abs(robotBusy.ringAngle - 210) < 0.5)
      shell.check("robot working eyes follow keyframes", Math.abs(robotBusy.eyes[1] - 4) < 0.001 && Math.abs(robotBusy.eyes[3] - 0.92) < 0.001)

      organicBusy.tick(1000)
      shell.check("organic eyes sample five values", organicBusy.eyes.length === 5)
      shell.check("organic body samples six values", organicBusy.body.length === 6)

      for (var i = 0; i < 3; i++)
        organicIdle.tick(1234 + i * 33)
      shell.check("panel organic face morphs its outline", organicIdle.bodyPath !== "" && organicIdle.bodyPath.indexOf("M") === 0)

      organicBusy.working = false
      shell.check("a bar face that stops working resets", !organicBusy.ticking && organicBusy.body[4] === 1 && organicBusy.eyes[4] === 1)

      if (shell.failures.length === 0)
        console.log("RAKAZO_BOTS_TESTS_PASSED bot-avatar " + shell.checks + " checks")
      else
        console.log("RAKAZO_BOTS_TESTS_FAILED " + shell.failures.join("; "))
      Qt.quit()
    }
  }
}
