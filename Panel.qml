import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar cluster and popup for Rakazo bots. Layout and interaction follow the
// Grok Bots plugin (glorics.grok-bots); data comes from the Rakazo API.
Panel {
  id: root
  moduleName: "m0sthatedman.rakazo"
  ipcTarget: "m0sthatedman.rakazo"
  manageIpc: false

  property int actionIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0
  property int selectedBot: 0
  readonly property var livePhrases: [
    "AI teammates",
    "Always on",
    "Their own computers",
    "Runs on this machine",
    "Persistent bots"
  ]
  readonly property var idlePhrases: [
    "Still on",
    "Bots keep going",
    "Stack's up"
  ]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: rakazo.alarming ? urgent : foreground
  readonly property color barIconColor: "#000000"
  readonly property color holeColor: bar ? (bar.background || Color.bar.background) : Color.background
  readonly property int rowH: Style.space(72)
  readonly property bool reachable: rakazo.running || inbox.running
  readonly property var actions: buildActions()
  readonly property var selectedAction: actions.length > 0 ? actions[Math.max(0, Math.min(actionIndex, actions.length - 1))] : null

  function buildActions() {
    var rows = []
    if (!rakazo.installed && !root.reachable) {
      rows.push({
        id: "install",
        label: "Get Rakazo",
        hint: "Enter",
        run: function() { rakazo.openProduct(); root.close() }
      })
    } else {
      rows.push({
        id: "open",
        label: !root.reachable ? "Start Rakazo" : (rakazo.windowOpen ? "Focus Rakazo" : "Open Rakazo"),
        hint: "Enter",
        run: function() { rakazo.launch(""); root.close() }
      })
    }
    if (root.reachable && !rakazo.signedIn) {
      rows.push({
        id: "signin",
        label: "Sign in",
        hint: "S",
        run: function() { rakazo.signIn(); root.close() }
      })
    }
    rows.push({
      id: "check",
      label: rakazo.refreshing && rakazo.actionStatus.indexOf("Checking") === 0
        ? "Checking…"
        : "Check for updates",
      hint: "U",
      run: function() { rakazo.checkForUpdates() }
    })
    if (rakazo.canSelfUpdate && rakazo.updateAvailable) {
      rows.push({
        id: "update",
        label: rakazo.updating ? "Updating…" : "Update now",
        hint: "Shift+U",
        run: function() { rakazo.updateNow() }
      })
    }
    if (rakazo.signedIn) {
      rows.push({
        id: "signout",
        label: "Sign out",
        hint: "",
        run: function() { rakazo.signOut() }
      })
    }
    rows.push({
      id: "github",
      label: "Open Rakazo on GitHub",
      hint: "G",
      run: function() { rakazo.openGitHub(); root.close() }
    })
    return rows
  }

  function selectAction(index) {
    if (actions.length === 0) return
    var wrapped = ((index % actions.length) + actions.length) % actions.length
    actionIndex = wrapped
  }

  function activateCursor() {
    if (inbox.bots.length > 0 && selectedBot >= 0 && selectedBot < inbox.bots.length) {
      openBot(inbox.bots[selectedBot])
      return
    }
    if (!selectedAction) return
    selectedAction.run()
  }

  function indexOfBot(bot) {
    if (!bot || !bot.id)
      return -1
    var id = String(bot.id)
    for (var i = 0; i < inbox.bots.length; i++) {
      if (String(inbox.bots[i].id) === id)
        return i
    }
    return -1
  }

  function showBot(bot) {
    if (!bot)
      return
    inbox.focusBot(bot)
    var idx = root.indexOfBot(bot)
    if (idx >= 0) {
      root.selectedBot = idx
      root.cursorActive = true
    }
    if (!root.opened)
      root.open()
  }

  function handleBotClick(bot) {
    root.showBot(bot)
  }

  function manualRefresh() {
    rakazo.refresh(false)
    inbox.refresh(true)
    rakazo.flash("Refreshed")
  }

  function phraseList() {
    if (rakazo.running && rakazo.signedIn) return inbox.lively ? livePhrases : idlePhrases
    return []
  }

  function heroMeta() {
    if (rakazo.updating) return "Updating"
    if (!rakazo.checked) return "Checking"
    if (!rakazo.installed && !root.reachable) return "Not installed"
    if (!root.reachable) return "Stack stopped"
    if (!rakazo.signedIn) return "Not signed in"
    if (rakazo.needsModel) return "No model connected"
    if (rakazo.updateAvailable) return "Update available"
    var phrases = phraseList()
    if (phrases.length > 0)
      return phrases[phraseIndex % phrases.length]
    return "Connected"
  }

  function heroDetail() {
    var parts = []
    parts.push(inbox.botCount + (inbox.botCount === 1 ? " bot" : " bots"))
    if (inbox.busyCount > 0)
      parts.push(inbox.busyCount + " working")
    parts.push(inbox.waitingCount + " waiting on you")
    parts.push(inbox.unreadBots + " unread")
    return parts.join(" · ")
  }

  function alertText() {
    if (!rakazo.installed && !root.reachable)
      return "Rakazo is not running here. Install it from the published images, then this widget can start it."
    if (!root.reachable)
      return "The Rakazo stack is stopped. Enter starts it and opens the app."
    if (!rakazo.signedIn)
      return "The bar signs in separately from the app window. Press S and enter your Rakazo email and password once; the session stays in your keyring."
    if (rakazo.needsModel)
      return "Connect a model in Rakazo before bots can answer."
    if (rakazo.updateAvailable)
      return "Rakazo " + rakazo.latestVersion + " is on ghcr.io (edge)."
    return ""
  }

  function emptyText() {
    if (inbox.lastError !== "")
      return inbox.lastError
    if (!root.reachable)
      return "Rakazo is not running. Start it to see your bots."
    if (!inbox.signedIn)
      return "Press S to sign in and see your bots. The app window's login is not shared with the bar."
    return "No bots yet. Create one in Rakazo."
  }

  function openBot(bot) {
    rakazo.launch(bot && bot.id ? bot.id : "")
    root.close()
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) rakazo.launch("")
    else if (button === Qt.MiddleButton) rakazo.checkForUpdates()
    else root.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    inbox.live = opened
    if (!opened)
      return
    cursorActive = false
    actionIndex = 0
    phraseIndex = 0
    var idx = -1
    if (inbox.focusedId) {
      for (var i = 0; i < inbox.bots.length; i++) {
        if (String(inbox.bots[i].id) === String(inbox.focusedId)) {
          idx = i
          break
        }
      }
    }
    if (idx >= 0) {
      selectedBot = idx
      cursorActive = true
    } else {
      selectedBot = 0
    }
    if (panelFlick) panelFlick.contentY = 0
    rakazo.refresh(false)
    inbox.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onActionsChanged: if (actionIndex >= actions.length) actionIndex = Math.max(0, actions.length - 1)

  Service {
    id: rakazo
    settings: root.settings
    onRunningChanged: root.phraseIndex = 0
    onSignedInChanged: inbox.refresh(true)
  }

  Inbox {
    id: inbox
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.manualRefresh(); return "ok" }
    function launch(): string { rakazo.launch(""); return "ok" }
    function signin(): string { rakazo.signIn(); return "ok" }
    function update(): string { rakazo.updateNow(); return "ok" }
    function status(): string { return rakazo.statusText }
    function unread(): string {
      var parts = []
      for (var i = 0; i < inbox.bots.length; i++) {
        var b = inbox.bots[i]
        parts.push(String(b.name || "Bot") + ":" + String(b.unread || 0))
      }
      return String(inbox.unreadCount) + " " + parts.join(" ")
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    pressable: true
    interactive: true
    tooltipText: "Click a face for messages · Enter opens Rakazo"
    active: rakazo.alarming || inbox.unreadBots > 0
    fixedWidth: Math.max(Style.bar.iconSlot, cluster.implicitWidth + Style.space(10))
    onPressed: function(buttonCode) { root.triggerPress(buttonCode) }

    Row {
      id: cluster
      anchors.centerIn: parent
      spacing: Style.space(2)
      height: Style.space(22)

      readonly property bool expanded: clusterHover.hovered

      Item {
        width: Style.space(18)
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter

        RakazoMark {
          anchors.centerIn: parent
          iconSize: Style.space(16)
          color: root.barIconColor
          eyeColor: root.holeColor
          lively: inbox.lively
          alarming: rakazo.alarming
          opacity: root.reachable || inbox.hasSnapshot ? 1.0 : 0.55
        }

        CountBubble {
          count: inbox.unreadCount
          fill: "#ffffff"
          ink: "#000000"
          tail: false
          fontFamily: root.fontFamily
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.rightMargin: -Style.space(5)
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: function() { root.toggle() }
        }
      }

      Item {
        id: botReveal
        width: cluster.expanded ? botFaces.implicitWidth + Style.space(3) : 0
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        opacity: cluster.expanded ? 1 : 0

        Behavior on width {
          NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Row {
          id: botFaces
          spacing: Style.space(2)
          height: parent.height

          Repeater {
            model: inbox.attentionBots
            Item {
              required property var modelData
              width: Style.space(17)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter

              BotAvatar {
                anchors.centerIn: parent
                iconSize: Style.space(16)
                color: modelData.color
                identity: modelData.identity
                avatarStyle: inbox.avatarStyle
                working: modelData.busy || modelData.waiting
                compact: true
              }

              CountBubble {
                count: 0
                pip: Number(modelData.unread || 0) > 0 || modelData.waiting === true
                fill: "#ffffff"
                ink: "#000000"
                tail: false
                fontFamily: root.fontFamily
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -Style.space(2)
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function() { root.handleBotClick(modelData) }
              }
            }
          }
        }
      }
    }

    HoverHandler { id: clusterHover }
  }

  // Omarchy underlines the bar slot when activePopout === this Panel.
  // Coordinate the popup on a nested owner so the open mark stays off.
  Item {
    id: popoutOwner
    function close() { root.close() }
    function closeForPopoutSwitch() { root.closeForPopoutSwitch() }
    property bool popoutSwitchClosing: root.popoutSwitchClosing
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: popoutOwner
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480) + Style.space(12) + Style.space(8))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))
    gap: Style.gapsOut

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        if (dy !== 0) {
          if (inbox.bots.length > 0) {
            var n = inbox.bots.length
            root.selectedBot = ((root.selectedBot + dy) % n + n) % n
            root.showBot(inbox.bots[root.selectedBot])
          } else {
            root.selectAction(root.actionIndex + dy)
          }
        }
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.manualRefresh()
        else if (t === "u") rakazo.checkForUpdates()
        else if (t === "U") rakazo.updateNow()
        else if (t === "o" || t === "O") { rakazo.launch(""); root.close() }
        else if ((t === "s" || t === "S") && root.reachable && !rakazo.signedIn) { rakazo.signIn(); root.close() }
        else if (t === "g" || t === "G") { rakazo.openGitHub(); root.close() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
          id: vScroll
          policy: ScrollBar.AsNeeded
          implicitWidth: Style.space(12)
          padding: Style.space(3)
          contentItem: Rectangle {
            implicitWidth: Style.space(5)
            radius: width / 2
            color: root.foreground
            opacity: vScroll.pressed ? 0.55 : (vScroll.hovered ? 0.38 : 0.22)
          }
          background: Item {}
        }

        Column {
          id: column
          width: panelFlick.width - Style.space(12) - Style.space(8)
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Rakazo"
            meta: root.heroMeta()
            detail: ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.reachable || inbox.hasSnapshot ? 1.0 : 0.55
            iconComponent: Component {
              RakazoMark {
                iconSize: Style.space(42)
                color: root.iconColor
                eyeColor: root.holeColor
                lively: inbox.lively
                alarming: rakazo.alarming
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh (R)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.manualRefresh()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: rakazo.actionStatus !== "" || rakazo.lastError !== "" || inbox.lastError !== ""
            width: parent.width
            text: rakazo.actionStatus !== "" ? rakazo.actionStatus : (rakazo.lastError !== "" ? rakazo.lastError : inbox.lastError)
            color: (rakazo.lastError !== "" || inbox.lastError !== "") && rakazo.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            visible: rakazo.checked && root.alertText() !== ""
            width: parent.width
            implicitHeight: alertLabel.implicitHeight + Style.spacing.xl * 2
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: alertLabel
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.alertText()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "RAKAZO · " + (inbox.spaceName !== "" ? inbox.spaceName : "inbox")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: inbox.hasSnapshot && inbox.signedIn
            text: root.heroDetail()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: inbox.focusedName !== "" && inbox.chatModel.count > 0
            textFormat: Text.PlainText
            width: parent.width
            text: String(inbox.focusedName || "").toUpperCase() + " · messages"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 0.6
          }

          ListView {
            id: liveChat
            width: parent.width
            height: inbox.chatModel.count > 0 ? Style.space(220) : 0
            visible: inbox.chatModel.count > 0
            clip: true
            spacing: Style.space(6)
            boundsBehavior: Flickable.StopAtBounds
            model: inbox.chatModel
            onCountChanged: Qt.callLater(function() { liveChat.positionViewAtEnd() })

            Connections {
              target: inbox
              function onStampChanged() { Qt.callLater(function() { liveChat.positionViewAtEnd() }) }
            }

            displaced: Transition {
              NumberAnimation { property: "y"; duration: 160; easing.type: Easing.OutQuad }
            }
            add: Transition {
              NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
            }

            delegate: Item {
              required property string botName
              required property string faceColor
              required property string faceIdentity
              required property string role
              required property string line
              required property bool streaming
              width: liveChat.width
              height: chatCol.implicitHeight

              Row {
                width: parent.width
                spacing: Style.space(8)

                BotAvatar {
                  iconSize: Style.space(18)
                  color: faceColor
                  identity: faceIdentity
                  avatarStyle: inbox.avatarStyle
                  working: streaming
                  compact: true
                  animated: root.opened
                  opacity: role === "assistant" ? 1.0 : 0.0
                }

                Column {
                  id: chatCol
                  width: parent.width - Style.space(28)
                  spacing: 1
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: (role === "assistant" ? String(botName || "") : "You") + (streaming ? " ·" : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(line || "")
                    color: role === "assistant" ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.Wrap
                  }
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: 0
            visible: inbox.bots.length > 0

            Repeater {
              model: inbox.botsModel

              Item {
                id: row
                required property int index
                required property string id
                required property string name
                required property string team
                required property string preview
                required property string feed
                required property string when
                required property int unread
                required property bool waiting
                required property bool busy
                required property string activity
                required property string color
                required property string identity
                width: parent.width
                height: root.rowH

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: (inbox.focusedId !== "" && String(inbox.focusedId) === String(row.id))
                    || (root.cursorActive && root.selectedBot === row.index)
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    : "transparent"
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursorActive = true
                    root.selectedBot = row.index
                  }
                  onClicked: function() { root.handleBotClick(inbox.bots[row.index]) }
                  onDoubleClicked: function() { root.openBot(inbox.bots[row.index]) }
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(10)

                  BotAvatar {
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    iconSize: Style.space(28)
                    color: row.color
                    identity: row.identity
                    avatarStyle: inbox.avatarStyle
                    working: row.busy || row.waiting
                    animated: root.opened
                  }

                  Column {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                      width: parent.width
                      spacing: Style.space(6)
                      Text {
                        textFormat: Text.PlainText
                        text: String(row.name || "Bot")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                      }
                      Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: String(row.team || "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                      Text {
                        textFormat: Text.PlainText
                        text: String(row.when || "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: {
                        var _tick = inbox.stamp
                        var line = String(row.preview || "No messages yet")
                        if (row.busy)
                          return "Working · " + line
                        if (row.waiting)
                          return "Waiting · " + line
                        return line
                      }
                      color: (row.waiting || row.busy) ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      visible: String(row.feed || "") !== ""
                      textFormat: Text.PlainText
                      text: String(row.feed || "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  CountBubble {
                    visible: row.unread > 0 || row.waiting
                    count: 0
                    pip: row.unread > 0 || row.waiting
                    fill: "#ffffff"
                    ink: "#000000"
                    fontFamily: root.fontFamily
                    tail: false
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                  }
                }
              }
            }
          }

          Text {
            visible: inbox.bots.length === 0
            width: parent.width
            padding: Style.space(18)
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
            text: root.emptyText()
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "Status"; value: rakazo.statusText }
            InfoPair {
              visible: rakazo.computerLabel !== ""
              label: "Computer"
              value: rakazo.computerLabel
            }
            InfoPair { label: "Signed in"; value: rakazo.signedInLabel }
            InfoPair {
              visible: rakazo.pluginVersion !== ""
              label: "Plugin"
              value: rakazo.pluginVersion
            }
            InfoPair {
              visible: rakazo.appVersion !== ""
              label: "Rakazo"
              value: rakazo.appVersion
            }
            InfoPair {
              visible: rakazo.latestVersion !== ""
              label: "Latest"
              value: rakazo.latestVersion + (rakazo.updateAvailable ? " · newer" : " · current")
            }
            InfoPair {
              visible: rakazo.lastCheckText !== ""
              label: "Checked"
              value: rakazo.lastCheckText
            }
            InfoPair {
              visible: rakazo.sourceLabel !== ""
              label: "Source"
              value: rakazo.sourceLabel
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: actionColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actions
              ActionRow {
                required property var modelData
                required property int index
                width: actionColumn.width
                action: modelData
                rowIndex: index
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            topPadding: Style.space(2)
            text: "Community plugin · self-hosted Rakazo"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  Timer {
    id: liveTimer
    interval: 800
    running: root.opened
    repeat: true
    onTriggered: inbox.refresh()
  }

  Timer {
    id: phraseTimer
    interval: 3200
    running: root.opened && rakazo.running && rakazo.signedIn && !rakazo.updating && !rakazo.alarming
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero
      property: "metaOpacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.phraseList().length
        root.phraseIndex = n > 0 ? (root.phraseIndex + 1) % n : 0
      }
    }
    PropertyAnimation {
      target: hero
      property: "metaOpacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  component InfoPair: Item {
    property string label: ""
    property string value: ""

    width: parent.width
    implicitHeight: Style.font.bodySmall + Style.space(4)
    height: implicitHeight
    clip: true

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.NoWrap
    }
    Text {
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.NoWrap
      maximumLineCount: 1
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property var action: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && inbox.bots.length === 0 && root.actionIndex === rowIndex
    foreground: root.foreground
    implicitHeight: actionInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.actionIndex = actionRow.rowIndex
      }
      onClicked: if (actionRow.action) actionRow.action.run()
    }

    Row {
      id: actionInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        width: parent.width - hint.implicitWidth - parent.spacing
        text: actionRow.action ? actionRow.action.label : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: hint
        textFormat: Text.PlainText
        text: actionRow.action ? actionRow.action.hint : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
