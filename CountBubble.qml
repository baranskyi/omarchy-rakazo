import QtQuick
import qs.Commons

// Small chat bubble with a count. Used on bar faces and inbox rows.
Item {
  id: root

  property int count: 0
  property color fill: "#ffffff"
  property color ink: "#000000"
  property string fontFamily: Style.font.family
  property bool tail: true
  property bool pip: false

  readonly property bool showCount: count > 0
  readonly property bool showPip: pip && count <= 0

  visible: showCount || showPip
  implicitWidth: showCount ? Math.max(Style.space(14), pill.implicitWidth) : Style.space(8)
  implicitHeight: showCount ? (pill.implicitHeight + (tail ? Style.space(3) : 0)) : Style.space(8)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: pipDot
    visible: root.showPip
    width: Style.space(7)
    height: Style.space(7)
    radius: width / 2
    color: root.fill
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.28)
    anchors.centerIn: parent
  }

  Rectangle {
    id: pill
    visible: root.showCount
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    implicitWidth: label.implicitWidth + Style.space(8)
    implicitHeight: Style.space(13)
    radius: height / 2
    color: root.fill
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.28)

    Text {
      id: label
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.count > 99 ? "99" : String(root.count)
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Rectangle {
    visible: root.tail && root.showCount
    width: Style.space(5)
    height: Style.space(5)
    rotation: 45
    color: root.fill
    anchors.horizontalCenter: pill.horizontalCenter
    anchors.top: pill.bottom
    anchors.topMargin: -Style.space(3)
  }
}
