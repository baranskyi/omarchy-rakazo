import QtQuick
import QtQuick.Shapes
import qs.Commons
import "avatar-shape.js" as AvatarShape
import "avatar-motion.js" as Motion

// A Rakazo bot face drawn the way the app draws it: "organic" is a seeded blob
// with two eyes, "robot" a glossy orb with a dark visor. Geometry comes from
// avatar-shape.js, motion from Rakazo's CSS keyframes in avatar-motion.js.
Item {
  id: root

  property real iconSize: Style.space(22)
  property string color: "#8B5CF6"
  property string identity: ""
  property string avatarStyle: "robot"
  property bool working: false
  // Bar-sized faces skip the glow and ring and hold still while idle.
  property bool compact: false
  property bool animated: true

  readonly property bool organic: avatarStyle === "organic"
  readonly property int seed: AvatarShape.identitySeed(identity !== "" ? identity : color)
  readonly property int colorSeed: AvatarShape.identitySeed(color !== "" ? color : "#8B5CF6")
  readonly property string motion: working ? AvatarShape.workingMotion(seed) : "idle"
  readonly property bool ticking: animated && visible && (working || !compact)
  readonly property string shapeA: AvatarShape.organicPath(seed)

  property var eyes: [0, 0, 0, 1, 1]
  property var body: [0, 0, 0, 0, 1, 1]
  property real ringAngle: 0
  property string bodyPath: shapeA
  property int _frame: 0

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  onShapeAChanged: bodyPath = shapeA
  onTickingChanged: if (!ticking) reset()

  function reset() {
    eyes = [0, 0, 0, 1, 1]
    body = [0, 0, 0, 0, 1, 1]
    bodyPath = shapeA
  }

  function tick(nowMs) {
    var now = nowMs === undefined ? Date.now() : nowMs
    _frame++
    if (organic) {
      var pattern = seed % 4
      var eyeTiming = working ? Motion.organicEyesWorkingTiming[pattern] : Motion.eyesIdleTiming[pattern]
      var eyeFrames = working ? Motion.organicEyesWorking[pattern] : Motion.eyesIdle[pattern]
      eyes = Motion.sample(eyeFrames, Motion.progress(now, eyeTiming[0], eyeTiming[1]))
      body = Motion.sample(Motion.body[motion], Motion.progress(now, Motion.bodySeconds[motion], 0))
      // The app morphs between two phases of the same shape; redraw at ~10 fps.
      if (!compact && _frame % 3 === 0) {
        var loop = Motion.progress(now, 4.8 + (seed % 24) / 10, 0) / 100
        bodyPath = AvatarShape.organicPath(seed, 0.42 * (1 - Math.cos(loop * Math.PI * 2)) / 2)
      }
    } else if (working) {
      eyes = Motion.sample(Motion.robotEyesWorking, Motion.progress(now, 1.4, 0))
      ringAngle = Motion.progress(now, 1.2, 0) * 3.6
    } else {
      var seconds = 4.2 + ((colorSeed * 7) % 28) / 10
      var delay = -(((colorSeed * 13) % 45) / 10)
      eyes = Motion.sample(Motion.eyesIdle[colorSeed % 4], Motion.progress(now, seconds, delay))
    }
  }

  Timer {
    interval: 33
    repeat: true
    running: root.ticking
    onTriggered: root.tick()
  }

  // Organic: drawn in Rakazo's -60..60 viewBox around the avatar's center.
  Item {
    id: organicFace
    visible: root.organic
    x: root.width / 2
    y: root.height / 2
    width: 0
    height: 0
    transform: Scale { xScale: root.width / 120; yScale: root.height / 120 }

    Shape {
      visible: root.working && !root.compact
      opacity: 0.35
      preferredRendererType: Shape.CurveRenderer
      transform: Scale { xScale: 1.16; yScale: 1.16 }
      ShapePath {
        fillColor: root.color
        strokeWidth: -1
        PathSvg { path: root.shapeA }
      }
    }

    Shape {
      preferredRendererType: Shape.CurveRenderer
      transform: [
        Scale { xScale: root.body[4]; yScale: root.body[5] },
        Rotation { angle: root.body[3]; origin.y: root.motion === "ring" ? -36 : 0 },
        Translate { x: root.body[1]; y: root.body[2] }
      ]
      ShapePath {
        fillColor: root.color
        strokeWidth: -1
        PathSvg { path: root.bodyPath }
      }
    }

    Item {
      rotation: (root.seed % 9) - 4
      transform: [
        Scale { xScale: root.eyes[3]; yScale: root.eyes[4] },
        Translate { x: root.eyes[1]; y: root.eyes[2] }
      ]
      Rectangle { x: -14; y: -12; width: 7; height: 24; radius: 3.5; color: "#101014" }
      Rectangle { x: 7; y: -12; width: 7; height: 24; radius: 3.5; color: "#101014" }
    }
  }

  // Robot: glossy orb, spinning ring while working, dark visor with eyes.
  Item {
    id: robotFace
    visible: !root.organic
    anchors.fill: parent

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
          centerX: root.width * 0.35
          centerY: root.height * 0.26
          centerRadius: root.width * 0.985
          focalX: root.width * 0.35
          focalY: root.height * 0.26
          GradientStop { position: 0.0; color: AvatarShape.adjustColor(root.color, 35) }
          GradientStop { position: 0.55; color: root.color }
          GradientStop { position: 1.0; color: AvatarShape.adjustColor(root.color, -40) }
        }
        PathAngleArc {
          centerX: root.width / 2
          centerY: root.height / 2
          radiusX: root.width / 2
          radiusY: root.height / 2
          startAngle: 0
          sweepAngle: 360
        }
      }
    }

    Shape {
      id: ring
      readonly property real side: root.width * (1 + 8 / 38)
      visible: root.working && !root.compact
      anchors.centerIn: parent
      width: side
      height: side
      rotation: root.ringAngle
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"
        strokeColor: AvatarShape.adjustColor(root.color, 45)
        strokeWidth: Math.max(1.5, root.width * 0.07)
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: ring.side / 2
          centerY: ring.side / 2
          radiusX: ring.side / 2 - root.width * 0.05
          radiusY: ring.side / 2 - root.width * 0.05
          startAngle: -90
          sweepAngle: 130
        }
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.round(root.width * 0.68)
      height: Math.round(root.height * 0.44)
      radius: height * 0.52
      border.width: root.width >= 24 ? 1 : 0
      border.color: Qt.rgba(1, 1, 1, 0.14)
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#101014" }
        GradientStop { position: 1.0; color: "#030305" }
      }

      Row {
        id: robotEyes
        anchors.centerIn: parent
        spacing: Math.max(1, root.width * 0.1)
        transform: [
          Scale {
            origin.x: robotEyes.width / 2
            origin.y: robotEyes.height / 2
            xScale: root.eyes[3]
            yScale: root.eyes[4]
          },
          Translate { x: root.eyes[1] * root.width / 38; y: root.eyes[2] * root.width / 38 }
        ]

        Repeater {
          model: 2
          Rectangle {
            width: Math.max(1.5, root.width * 0.14)
            height: Math.max(3, root.width * 0.22)
            radius: width / 2
            color: "#FFFFFF"
          }
        }
      }
    }
  }
}
