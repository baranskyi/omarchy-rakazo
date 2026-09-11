import QtQuick
import qs.Commons

// Rakazo mark: a round face with two pill eyes, as in the app's wordmark.
// It blinks now and then, and bobs while any bot is working or waiting.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color eyeColor: Color.background
  property bool lively: false
  property bool alarming: false

  property real blink: 0
  property real look: 0
  property real bob: 0

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Rectangle {
    id: face
    anchors.centerIn: parent
    anchors.verticalCenterOffset: root.bob
    width: root.iconSize * 0.92
    height: width
    radius: width / 2
    color: root.color
  }

  Row {
    anchors.centerIn: face
    anchors.horizontalCenterOffset: root.look * root.iconSize * 0.07
    spacing: Math.max(1, root.iconSize * 0.1)

    Repeater {
      model: 2
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(2, root.iconSize * 0.16)
        height: Math.max(1, root.iconSize * 0.36 * (1 - 0.85 * root.blink))
        radius: width / 2
        color: root.eyeColor
      }
    }
  }

  SequentialAnimation on bob {
    running: root.lively && !root.alarming
    loops: Animation.Infinite
    NumberAnimation { to: -1.0; duration: 420; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine }
  }

  onLivelyChanged: if (!lively) bob = 0

  SequentialAnimation {
    id: blinkAnim
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 70; easing.type: Easing.OutQuad }
    PauseAnimation { duration: 50 }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 120; easing.type: Easing.OutCubic }
  }

  NumberAnimation {
    id: lookAnim
    target: root
    property: "look"
    duration: 360
    easing.type: Easing.InOutCubic
  }

  Timer {
    id: idleTimer
    interval: 3200
    repeat: true
    running: !root.alarming
    onTriggered: {
      if (Math.random() < 0.6) {
        blinkAnim.restart()
      } else {
        lookAnim.to = root.look === 0 ? (Math.random() < 0.5 ? -1 : 1) : 0
        lookAnim.restart()
      }
      interval = 2400 + Math.round(Math.random() * 3200)
    }
  }
}
