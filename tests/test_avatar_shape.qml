import QtQuick
import Quickshell
import Quickshell.Io
import "plugin/avatar-shape.js" as AvatarShape

// Harness: the QML port draws the same organic faces as Rakazo's TypeScript.
ShellRoot {
  id: shell

  property var failures: []
  property int checks: 0

  function check(name, ok) {
    checks++
    if (!ok)
      failures.push(name)
  }

  function finish() {
    if (failures.length === 0)
      console.log("RAKAZO_BOTS_TESTS_PASSED avatar-shape " + checks + " checks")
    else
      console.log("RAKAZO_BOTS_TESTS_FAILED " + failures.slice(0, 6).join("; "))
    Qt.quit()
  }

  FileView {
    id: fixture
    path: String(Quickshell.env("RAKAZO_BOTS_FIXTURE_DIR") || "") + "/organic-avatar-paths.json"
    onLoaded: {
      var data = JSON.parse(fixture.text())
      var families = {}
      for (var i = 0; i < data.cases.length; i++) {
        var c = data.cases[i]
        families[c.seed % 10] = true
        if (c.identity !== null)
          shell.check("seed of " + JSON.stringify(c.identity), AvatarShape.identitySeed(c.identity) === c.seed)
        shell.check("shape A for seed " + c.seed, AvatarShape.organicPath(c.seed) === c.shapeA)
        shell.check("shape B for seed " + c.seed, AvatarShape.organicPath(c.seed, 0.42) === c.shapeB)
      }
      shell.check("fixture covers all ten shape families", Object.keys(families).length === 10)
      shell.check("lighten clamps at white", AvatarShape.adjustColor("#F5A03C", 35) === "#fff995")
      shell.check("darken clamps at black", AvatarShape.adjustColor("#F5A03C", -40) === "#8f3a00")
      shell.check("short hex expands", AvatarShape.adjustColor("#abc", 0) === "#aabbcc")
      shell.check("bad hex passes through", AvatarShape.adjustColor("tomato", 20) === "tomato")
      shell.check("family 7 rings", AvatarShape.workingMotion(17) === "ring")
      shell.finish()
    }
    onLoadFailed: function(error) {
      shell.failures.push("fixture did not load: " + error)
      shell.finish()
    }
  }
}
