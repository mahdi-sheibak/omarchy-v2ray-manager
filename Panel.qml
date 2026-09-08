import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Panel content — loaded by BarWidget.qml via Loader.
// Extends qs.Ui.Panel for IPC-backed open/close lifecycle.
Panel {
  id: root
  moduleName: "mahdi.v2ray-manager"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string focusSection: "header"
  property int modeIndex: 0
  property int profileIndex: 0
  property bool cursorActive: false
  property int backendIndex: 0
  property int groupIndex: 0

  function open() {
    root.cursorActive = false
    root.focusSection = "header"
    root.profileIndex = 0
    root.groupIndex = 0
    v2ray.refresh()
    root.controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cursorActive = false
    root.controller.hide()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    v2ray.refresh()
  }

  // Colors derived from theme tokens — never hardcoded hex.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property color subColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var modes: [
    { id: "proxy", label: "Proxy", detail: "SOCKS/HTTP on 127.0.0.1:2080" },
    { id: "tun", label: "VPN (TUN)", detail: "Route all traffic system-wide" }
  ]
  // heroMeta: geo info shown in PanelHero subtitle when connected.
  // When disconnected, shows "Disconnected"; when connecting, "Connecting…".
  readonly property string heroMeta: {
    if (!v2ray.installed) return "omarchy-v2ray CLI not found"
    if (v2ray.running) {
      var cc = (v2ray.geo && v2ray.geo.cc) ? String(v2ray.geo.cc) : ""
      var place = ""
      if (v2ray.geo && v2ray.geo.city !== "") place = String(v2ray.geo.city)
      else if (v2ray.geo && v2ray.geo.country !== "") place = String(v2ray.geo.country)
      var ip = v2ray.exitIp !== "" ? v2ray.exitIp : ""
      var parts = []
      if (cc !== "" && place !== "") parts.push("[" + cc + "] " + place)
      else if (place !== "") parts.push(place)
      else if (cc !== "") parts.push("[" + cc + "]")
      if (ip !== "") parts.push(ip)
      if (parts.length > 0) return parts.join(" · ")
      var name = v2ray.active ? String(v2ray.active.name || "") : ""
      return name !== "" ? name : "Connecting…"
    }
    return "Disconnected"
  }
  readonly property bool importFieldFocused: importSection.focusField

  function ensureCursor() {
    if (modeIndex >= root.modes.length) modeIndex = Math.max(0, root.modes.length - 1)
    // profileIndex -1 is the "Fastest" pseudo-row, valid alongside 0..N-1
    if (profileIndex >= v2ray.visibleProfiles.length) profileIndex = Math.max(0, v2ray.visibleProfiles.length - 1)
    if (backendIndex >= 2) backendIndex = 1
    if (groupIndex >= v2ray.groups.length + 1) groupIndex = v2ray.groups.length  // +1 for "All"
    if (groupIndex < 0) groupIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0 && dx === 0) return
    if (dy > 0) advanceCursor(1)
    else if (dy < 0) advanceCursor(-1)
    ensureCursor()
  }

  function sectionOrder() {
    var order = ["header"]
    if (!v2ray.busy) order.push("modes")
    if (v2ray.xrayAvailable) order.push("backend")
    if (v2ray.groups.length > 0) order.push("groups")
    order.push("profiles")
    order.push("import")
    return order
  }

  function advanceCursor(step) {
    var order = sectionOrder()
    function sectionTotal(sec) {
      if (sec === "modes") return modes.length
      if (sec === "backend") return 2
      if (sec === "groups") return v2ray.groups.length + 1   // +1 for "All"
      if (sec === "profiles") return profilesCount()
      return 1
    }
    function sectionIndex(sec) {
      if (sec === "modes") return modeIndex
      if (sec === "backend") return backendIndex
      if (sec === "groups") return groupIndex
      if (sec === "profiles") return profileIndex
      return 0
    }
    function setSectionIndex(sec, v) {
      if (sec === "modes") modeIndex = v
      else if (sec === "backend") backendIndex = v
      else if (sec === "groups") groupIndex = v
      else if (sec === "profiles") profileIndex = v
    }
    function enterSection(sec, back) {
      setSectionIndex(sec, back ? Math.max(0, sectionTotal(sec) - 1) : 0)
      focusSection = sec
    }
    ensureCursor()
    // Determine current section (fallback to profiles if somehow unset)
    var cur = focusSection
    if (order.indexOf(cur) === -1 && cur !== "header") cur = "profiles"

    if (cur === "header") {
      var first = order.length > 1 ? order[1] : "profiles"
      enterSection(first, false)
      return
    }

    var total = sectionTotal(cur)
    var idx   = sectionIndex(cur)
    var next  = idx + step

    if (next < 0) {
      // Move back to previous section
      var pi = order.indexOf(cur) - 1
      if (pi >= 0 && order[pi] !== "header") {
        var prevSec = order[pi]
        enterSection(prevSec, true)
      } else {
        focusSection = "header"
      }
      return
    }
    if (next >= total) {
      // Move forward to next section
      var ni = order.indexOf(cur) + 1
      if (ni < order.length && order[ni] !== "header") {
        enterSection(order[ni], false)
      }
      return
    }
    setSectionIndex(cur, next)
  }

  // Fastest row occupies profileIndex -1; real profiles are 0..N-1
  function profilesCount() { return v2ray.visibleProfiles.length + 1 }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") v2ray.toggle()
    else if (focusSection === "modes") setMode(modes[modeIndex].id)
    else if (focusSection === "backend") {
      var ids = ["sing-box", "xray"]
      if (backendIndex >= 0 && backendIndex < ids.length) {
        var b = ids[backendIndex]
        if (b !== "xray" || v2ray.xrayAvailable) v2ray.setBackend(b)
      }
    }
    else if (focusSection === "groups") {
      // groupIndex 0 = "All" (clear filter), 1+ = groups[groupIndex-1]
      if (groupIndex === 0) v2ray.setGroupFilter("")
      else if (groupIndex - 1 < v2ray.groups.length) v2ray.setGroupFilter(v2ray.groups[groupIndex - 1])
    }
    else if (focusSection === "profiles") {
      if (profileIndex === -1) {
        v2ray.connectFastest()
      } else if (profilesCount() > 1 && profileIndex >= 0 && profileIndex < v2ray.visibleProfiles.length) {
        connectProfile(v2ray.visibleProfiles[profileIndex].id)
      }
    } else if (focusSection === "import") {
      importField.forceActiveFocus()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    v2ray.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: v2ray
    settings: root.settings
  }

  // The bar button (BarIconButton) lives in BarWidget.qml.
  // KeyboardPanel.anchorItem is injected by BarWidget.injectPanel()
  // via panelLoader.item.anchorItem = button

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.importFieldFocused
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") v2ray.toggle()
        else if ((t === "i" || t === "I")) importField.forceActiveFocus()
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"
            function focusHero() {
              root.cursorActive = true
              root.focusSection = "header"
            }

            PanelHero {
              id: hero
              width: parent.width
              title: "V2Ray"
              meta: v2ray.actionStatus !== "" ? v2ray.actionStatus : heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: v2ray.running ? 1.0 : 0.5
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: v2ray.installed
                  checked: v2ray.running
                  busy: v2ray.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: v2ray.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: v2ray.running ? "Disconnect" : "Connect"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }

            }

          // QR button for connected profile
          Text {
            id: qrToggle
            visible: v2ray.running && v2ray.active
            width: parent.width
            text: v2ray.qrProfileId !== "" ? "Hide QR" : "QR Code"
            color: qrMouse.containsMouse ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignRight
            rightPadding: Style.space(6)

            MouseArea {
              id: qrMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: v2ray.running && v2ray.active && !v2ray.busy
              onClicked: {
                if (v2ray.qrProfileId !== "") v2ray.hideQR()
                else if (v2ray.active) v2ray.showQR(v2ray.active.id)
              }
            }

            PanelToolTip {
              visible: qrMouse.containsMouse
              text: v2ray.qrProfileId !== "" ? "Hide QR code" : "Show QR code for connected profile"
              fontFamily: root.fontFamily
            }
          }

          // Inline QR code display
          Rectangle {
            visible: v2ray.qrProfileId !== ""
            width: parent.width
            height: qrInner.implicitHeight + 24
            color: Color.popups.background
            border.color: root.dim
            border.width: 1
            radius: Style.cornerRadius

            Column {
              id: qrInner
              anchors.centerIn: parent
              spacing: 8

              Text {
                text: {
                  var name = ""
                  for (var i = 0; i < v2ray.profiles.length; i++) {
                    if (String(v2ray.profiles[i].id) === v2ray.qrProfileId) {
                      name = v2ray.profiles[i].name || v2ray.profiles[i].server
                      break
                    }
                  }
                  return name
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                width: 200
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
              }

              Image {
                source: v2ray.qrImagePath !== "" ? "file://" + v2ray.qrImagePath : ""
                width: 180; height: 180
                fillMode: Image.PreserveAspectFit
                visible: source != ""
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Text {
                text: "Scan to import"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.horizontalCenter: parent.horizontalCenter
              }
            }
          }

          Text {
            visible: v2ray.lastError !== ""
            width: parent.width
            text: v2ray.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !v2ray.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Install the omarchy-v2ray CLI to use this widget."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: v2ray.installed
            foreground: root.foreground
          }

          Column {
            visible: v2ray.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MODE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.modes
              ModeRow {
                required property var modelData
                required property int index
                width: parent.width
                mode: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: v2ray.installed
            foreground: root.foreground
          }

          Column {
            visible: v2ray.installed && v2ray.xrayAvailable
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "BACKEND"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              BackendRow {
                Layout.fillWidth: true
                backendId: "sing-box"
                label: "sing-box"
              }

              BackendRow {
                Layout.fillWidth: true
                backendId: "xray"
                label: "xray-core"
              }
            }
          }

          PanelSeparator {
            visible: v2ray.installed
            foreground: root.foreground
          }

          Column {
            visible: v2ray.installed
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "GROUPS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.fillWidth: true
              }

              PanelActionButton {
                iconText: "+"
                tooltipText: "Create group from ungrouped profiles"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !v2ray.busy
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                  createGroupDialog.visible = true
                  Qt.callLater(function() { groupNameField.forceActiveFocus() })
                }
              }

              PanelActionButton {
                iconText: "↧"
                tooltipText: "Add subscription (auto-creates a group)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !v2ray.busy
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                  addSubDialog.visible = true
                  Qt.callLater(function() { subUrlField.forceActiveFocus() })
                }
              }
            }

            // Inline create group dialog (simple: show/hide section)
            Column {
              id: createGroupDialog
              width: parent.width
              spacing: Style.space(6)
              visible: false
              property string pendingName: ""

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: groupNameField
                  Layout.fillWidth: true
                  foreground: root.foreground
                  placeholderText: "Group name"
                  text: createGroupDialog.pendingName
                  onAccepted: {
                    v2ray.createGroup(text)
                    createGroupDialog.visible = false
                    text = ""
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      createGroupDialog.visible = false
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                  onActiveFocusChanged: if (activeFocus) createGroupDialog.pendingName = text
                }

                PanelActionButton {
                  iconText: "✓"
                  tooltipText: "Create group"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: groupNameField.text.trim() !== "" && !v2ray.busy
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: {
                    v2ray.createGroup(groupNameField.text)
                    createGroupDialog.visible = false
                    groupNameField.text = ""
                  }
                }

                PanelActionButton {
                  iconText: "×"
                  tooltipText: "Cancel"
                  foreground: root.dim
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  enabled: !v2ray.busy
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: {
                    createGroupDialog.visible = false
                    groupNameField.text = ""
                  }
                }
              }
            }

            // Inline add-subscription dialog
            Column {
              id: addSubDialog
              width: parent.width
              spacing: Style.space(6)
              visible: false
              property string pendingUrl: ""
              property string pendingName: ""

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: subUrlField
                  Layout.fillWidth: true
                  foreground: root.foreground
                  placeholderText: "https://host/path/subscription"
                  text: addSubDialog.pendingUrl
                  onAccepted: {
                    v2ray.addSubscription(text, subNameField.text.trim())
                    addSubDialog.visible = false
                    text = ""
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      addSubDialog.visible = false
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                  onActiveFocusChanged: if (activeFocus) addSubDialog.pendingUrl = text
                }

                TextField {
                  id: subNameField
                  Layout.preferredWidth: Style.space(90)
                  foreground: root.foreground
                  placeholderText: "Group (opt)"
                  text: addSubDialog.pendingName
                  onAccepted: {
                    v2ray.addSubscription(subUrlField.text, text.trim())
                    addSubDialog.visible = false
                    subUrlField.text = ""
                    text = ""
                  }
                  onActiveFocusChanged: if (activeFocus) addSubDialog.pendingName = text
                }

                PanelActionButton {
                  iconText: "✓"
                  tooltipText: "Add subscription"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: subUrlField.text.trim() !== "" && !v2ray.busy
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: {
                    v2ray.addSubscription(subUrlField.text, subNameField.text.trim())
                    addSubDialog.visible = false
                    subUrlField.text = ""
                    subNameField.text = ""
                  }
                }

                PanelActionButton {
                  iconText: "×"
                  tooltipText: "Cancel"
                  foreground: root.dim
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  enabled: !v2ray.busy
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: {
                    addSubDialog.visible = false
                    subUrlField.text = ""
                    subNameField.text = ""
                  }
                }
              }

              Text {
                width: parent.width
                text: "Fetches the subscription, creates a group, imports every config. Refetch later from the group's ↻ button."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              GroupPill {
                label: "All"
                targetGroup: ""
                pillIndex: 0
              }

              Repeater {
                model: v2ray.groups
                GroupPill {
                  required property var modelData
                  required property int index
                  label: String(modelData)
                  targetGroup: String(modelData)
                  pillIndex: index + 1
                  isSubscription: v2ray.subscriptions[String(modelData)] !== undefined
                  subscriptionUrl: v2ray.subscriptions[String(modelData)] ? v2ray.subscriptions[String(modelData)].url : ""
                  subscriptionData: v2ray.subscriptions[String(modelData)] ? v2ray.subscriptions[String(modelData)] : ({})
                }
              }
            }
          }

          PanelSeparator {
            visible: v2ray.installed
            foreground: root.foreground
          }

          Column {
            id: importSection
            visible: v2ray.installed
            width: parent.width
            spacing: Style.space(8)

            property bool focusField: false

            PanelSectionHeader {
              text: "IMPORT SHARE LINKS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: importField
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "vless:// · vmess:// · ss:// · socks5://"
                onAccepted: {
                  v2ray.importLinks(text)
                  text = ""
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    importSection.focusField = false
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }
                }
                onActiveFocusChanged: if (activeFocus) importSection.focusField = true
              }

              PanelActionButton {
                id: importButton
                iconText: ""
                tooltipText: "Import links"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                  v2ray.importLinks(importField.text)
                  importField.text = ""
                }
              }
            }

            Text {
              width: parent.width
              text: v2ray.selectedGroup !== ""
                ? "New links land in group \"" + v2ray.selectedGroup + "\". Multi-link and base64 blobs work."
                : "Paste one or many links. Multi-link and base64 subscription blobs work too."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: v2ray.installed
            foreground: root.foreground
          }


          Column {
            visible: v2ray.installed
            width: parent.width
            spacing: Style.space(10)

            RowLayout {
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "PROFILES"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.fillWidth: true
              }

              PanelActionButton {
                visible: v2ray.selectedGroup !== "" && v2ray.subscriptions[v2ray.selectedGroup] !== undefined
                iconText: "↻"
                tooltipText: "Refetch subscription configs"
                foreground: root.subColor
                hoverColor: root.subColor
                fontFamily: root.fontFamily
                enabled: !v2ray.busy
                Layout.alignment: Qt.AlignVCenter
                onClicked: v2ray.updateSubscription(v2ray.selectedGroup)
              }

              PanelActionButton {
                iconText: "󰓅"
                tooltipText: "Test all profiles"
                foreground: v2ray.pingTarget !== "" ? root.dim : root.foreground
                fontFamily: root.fontFamily
                enabled: v2ray.pingTarget === ""
                Layout.alignment: Qt.AlignVCenter
                onClicked: v2ray.pingProfile("all")
              }
            }

            // Fastest: CLI pings candidates (scoped to current group) and
            // connects to the winner.
            CursorSurface {
              id: fastestRow
              readonly property bool isBusy: v2ray.connectingFastest
              readonly property bool isActive: !isBusy && v2ray.running && v2ray.active === null
              width: parent.width
              hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === -1
              current: isActive
              foreground: root.foreground
              fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
              currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
              implicitHeight: frow.implicitHeight + Style.spacing.xl

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !v2ray.busy
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                  root.cursorActive = true
                  root.focusSection = "profiles"
                  root.profileIndex = -1
                }
                onClicked: v2ray.connectFastest()
              }

              RowLayout {
                id: frow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(6)

                Text {
                  text: "󰤨"
                  color: fastestRow.isActive ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  Layout.preferredWidth: Style.space(22)
                  horizontalAlignment: Text.AlignHCenter
                  Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    Layout.fillWidth: true
                    text: "⚡ Fastest available"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: fastestRow.isActive
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: v2ray.selectedGroup !== ""
                      ? "Ping candidates in \"" + v2ray.selectedGroup + "\", connect to the quickest"
                      : "Ping every profile, connect to the quickest"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  visible: fastestRow.isBusy
                  text: "…"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.alignment: Qt.AlignVCenter
                }
              }
            }

            Text {
              visible: v2ray.visibleProfiles.length === 0
              width: parent.width
              text: v2ray.selectedGroup === "" ? "No profiles yet. Import a share link above." : "No profiles in this group."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: v2ray.visibleProfiles
              ProfileRow {
                required property var modelData
                required property int index
                width: parent.width
                profile: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator {
            visible: v2ray.installed
            foreground: root.foreground
          }

        }
      }
    }
  }

  component ModeRow: CursorSurface {
    id: modeRow
    property var mode: null
    property int rowIndex: 0
    readonly property bool isCurrent: mode && v2ray.mode === mode.id
    hasCursor: root.cursorActive && root.focusSection === "modes" && root.modeIndex === index
    current: isCurrent
    foreground: root.foreground
    fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
    implicitHeight: row.implicitHeight + Style.spacing.xl

    Row {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: modeRow.isCurrent ? "󰒃" : "󰅂"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: modeRow.mode ? modeRow.mode.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: modeRow.isCurrent
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: modeRow.mode ? modeRow.mode.detail : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !v2ray.busy   // no silent drops while an action is in flight
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "modes"
        root.modeIndex = index
      }
      onClicked: if (modeRow.mode) v2ray.setMode(modeRow.mode.id)
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    property var profile: null
    property int rowIndex: 0
    readonly property bool isActive: profile && v2ray.active && String(v2ray.active.id) === String(profile.id || "")
    readonly property var ping: profile ? v2ray.pingResult(profile.id) : null
    readonly property bool testing: profile && v2ray.pingTarget !== "" && (v2ray.pingTarget === "all" || v2ray.pingTarget === String(profile.id))
    readonly property string pingText: {
      if (testing) return "…"
      if (!ping) return ""
      if (ping.ms !== null && ping.ms !== undefined) return ping.ms + " ms"
      return "unreachable"
    }
    readonly property color pingColor: {
      if (testing || !ping) return root.dim
      if (ping.ms === null || ping.ms === undefined) return root.urgent
      return ping.ms < 300 ? root.foreground : root.dim
    }
    hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === rowIndex
    current: isActive
    foreground: root.foreground
    fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
    implicitHeight: prow.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !v2ray.busy && !profileRow.testing
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "profiles"
        root.profileIndex = rowIndex
      }
      onClicked: if (profileRow.profile && !profileRow.testing) v2ray.connectProfile(profileRow.profile.id)
    }

    RowLayout {
      id: prow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(6)

      Text {
        text: profileRow.isActive ? "󰄬" : "󰅂"
        color: profileRow.isActive ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: profile ? String(profile.name || profile.server) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: profileRow.isActive
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: profile ? ((profile.proto || "").toUpperCase() + " · " + profile.server + ":" + profile.server_port) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: profileRow.pingText !== ""
        text: profileRow.pingText
        color: profileRow.pingColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      // Latency trend sparkline (last N pings). Nulls (failed probes) draw
      // as gaps; the line is drawn in dim color so it never shouts.
      Sparkline {
        id: spark
        values: profileRow.profile ? v2ray.sparklineData(profileRow.profile.id) : []
        lineColor: root.dim
        sparkW: 34
        sparkH: 14
        Layout.preferredWidth: 34
        Layout.preferredHeight: 14
        Layout.alignment: Qt.AlignVCenter
        Connections {
          target: v2ray
          function onPingsChanged() { spark.requestPaint() }
          function onPingHistoryChanged() { spark.requestPaint() }
        }
        Component.onCompleted: requestPaint()
      }

      PanelActionButton {
        iconText: "󰓅"
        tooltipText: "Test connection"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !profileRow.testing
        opacity: profileRow.testing ? 0.4 : 1.0
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (profileRow.profile) v2ray.pingProfile(profileRow.profile.id)
      }

      PanelActionButton {
        iconText: "×"
        tooltipText: "Remove profile"
        foreground: root.dim
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (profileRow.profile) v2ray.removeProfile(profileRow.profile.id)
      }
    }
  }

  // Helper: count profiles belonging to a given group
  function groupCountFor(name) {
    var c = 0
    for (var i = 0; i < v2ray.profiles.length; i++) {
      if (String(v2ray.profiles[i].group || "") === name) c++
    }
    return c
  }

  component GroupPill: CursorSurface {
    id: groupPill
    property string label: ""
    property string targetGroup: ""
    property int pillIndex: 0
    property bool isSubscription: false
    property string subscriptionUrl: ""
    property var subscriptionData: ({})
    readonly property bool isCurrent: root.cursorActive && root.focusSection === "groups" && root.groupIndex === pillIndex
    property bool hovered: false
    function groupCountFor(name) {
      var c = 0
      for (var i = 0; i < v2ray.profiles.length; i++) {
        if (String(v2ray.profiles[i].group || "") === name) c++
      }
      return c
    }
    function lastRefetchedText() {
      if (!isSubscription || !subscriptionData || !subscriptionData.updated_at) return ""
      var ts = subscriptionData.updated_at * 1000
      var now = Date.now()
      var diffMs = now - ts
      var diffMin = Math.floor(diffMs / 60000)
      var diffHr = Math.floor(diffMs / 3600000)
      if (diffMin < 1) return "now"
      if (diffMin < 60) return diffMin + "m"
      if (diffHr < 24) return diffHr + "h"
      return Math.floor(diffHr / 24) + "d"
    }
    hasCursor: isCurrent || hovered
    current: v2ray.selectedGroup === targetGroup
    foreground: root.foreground
    fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
    implicitHeight: pillContent.implicitHeight + Style.space(14)
    implicitWidth: pillContent.implicitWidth + Style.space(22) + (isSubscription ? Style.space(26) : 0)

    // Thin accent bar so subscription pills read differently at a glance
    Rectangle {
      visible: isSubscription
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 3
      radius: 1.5
      color: root.subColor
    }

    Row {
      id: pillContent
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        visible: isSubscription
        text: "↻"
        color: (groupPill.current || hovered) ? root.foreground : root.subColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        id: pillText
        text: groupPill.label + (groupPill.targetGroup !== "" ? "  " + groupCountFor(groupPill.targetGroup) : "") + (isSubscription && lastRefetchedText() !== "" ? " · " + lastRefetchedText() : "")
        color: (groupPill.current || hovered) ? root.foreground : (isSubscription ? root.subColor : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: groupPill.current || isSubscription
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: !v2ray.busy
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        groupPill.hovered = true
        root.cursorActive = true
        root.focusSection = "groups"
        root.groupIndex = groupPill.pillIndex
      }
      onExited: groupPill.hovered = false
      onClicked: v2ray.setGroupFilter(groupPill.targetGroup)
    }

    // Action buttons (top-right): refetch (subscriptions) + delete
    Row {
      visible: groupPill.targetGroup !== ""
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: -Style.space(4)
      anchors.rightMargin: -Style.space(4)
      spacing: Style.space(2)

      PanelActionButton {
        iconText: "×"
        tooltipText: isSubscription ? "Remove subscription (and its configs)" : "Delete group (ungroup profiles)"
        foreground: root.dim
        hoverColor: root.urgent
        fontSize: Style.font.tiny
        size: Style.space(16)
        fontFamily: root.fontFamily
        enabled: !v2ray.busy
        onClicked: isSubscription ? v2ray.removeSubscription(groupPill.targetGroup) : v2ray.deleteGroup(groupPill.targetGroup)
      }
    }

    PanelToolTip {
      visible: isSubscription && mouseArea.containsMouse
      text: (groupPill.subscriptionUrl !== "" ? groupPill.subscriptionUrl + "\n" : "") + "Subscription · last refetch " + lastRefetchedText() + (v2ray.subscriptionRefetchMin > 0 ? " · auto every " + v2ray.subscriptionRefetchMin + "m" : "")
      fontFamily: root.fontFamily
    }
  }

  component BackendRow: CursorSurface {
    id: backendRow
    property string backendId: ""
    property string label: ""
    readonly property bool isCurrent: v2ray.backend === backendRow.backendId
    readonly property bool available: backendRow.backendId === "xray" ? v2ray.xrayAvailable : true
    hasCursor: root.cursorActive && root.focusSection === "backend"
    current: isCurrent
    foreground: root.foreground
    fill: root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
    currentFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
    implicitHeight: backendRowLayout.implicitHeight + Style.spacing.xl

    Row {
      id: backendRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: backendRow.isCurrent ? "󰒃" : "󰅂"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: backendRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: backendRow.isCurrent
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: backendRow.available ? (backendRow.isCurrent ? "Active" : "Available") : "Not installed"
          color: backendRow.available ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: !v2ray.busy
      cursorShape: backendRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "backend"
      }
      onClicked: if (backendRow.available) v2ray.setBackend(backendRow.backendId)
    }
  }
}
