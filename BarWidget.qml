import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "mahdi.v2ray-manager"

  // Colors derived from theme tokens — never hardcoded.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property color subColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): string { root.refresh(); return "ok" }
    function connect(): string {
      var p = panelLoader.item
      if (p && p.v2ray) p.v2ray.connectProfile("")
      return "ok"
    }
    function disconnect(): string {
      var p = panelLoader.item
      if (p && p.v2ray) p.v2ray.disconnect()
      return "ok"
    }
    function ping(id: string): string {
      var p = panelLoader.item
      if (p && p.v2ray) p.v2ray.pingProfile(id === "" ? "all" : id)
      return "ok"
    }
    function status(): string {
      var p = panelLoader.item
      if (!p || !p.v2ray || !p.v2ray.running) return "disconnected"
      var svc = p.v2ray
      var flag = (svc.geo && svc.geo.flag) ? String(svc.geo.flag) : ""
      var place = ""
      if (svc.geo && svc.geo.city !== "") place = String(svc.geo.city)
      else if (svc.geo && svc.geo.country !== "") place = String(svc.geo.country)
      var ip = svc.exitIp !== "" ? svc.exitIp : ""
      var parts = []
      if (flag !== "" || place !== "") parts.push(((flag !== "" ? flag + " " : "") + place).trim())
      if (ip !== "") parts.push(ip)
      if (parts.length > 0) return parts.join(" \u00b7 ")
      var name = svc.active ? String(svc.active.name || "") : ""
      return name !== "" ? name : "connecting"
    }
    function setBackend(name: string): string {
      var p = panelLoader.item
      if (p && p.v2ray) p.v2ray.setBackend(name)
      return "ok"
    }
    function showQR(id: string): string {
      var p = panelLoader.item
      if (p && p.v2ray) {
        if (id !== "") p.v2ray.showQR(id)
        else if (p.v2ray.active) p.v2ray.showQR(p.v2ray.active.id)
      }
      return "ok"
    }
    function hideQR(): string {
      var p = panelLoader.item
      if (p && p.v2ray) p.v2ray.hideQR()
      return "ok"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      var p = panelLoader.item
      if (p && p.v2ray && p.v2ray.running) return "󰌾"
      return "󰌋"
    }
    foreground: {
      var p = panelLoader.item
      if (p && p.v2ray && p.v2ray.running) return root.foreground
      return root.dim
    }
    onPressed: function(buttonCode) {
      var p = panelLoader.item
      if (buttonCode === Qt.RightButton) {
        if (p && p.v2ray) p.v2ray.toggle()
      } else if (buttonCode === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.togglePanel()
      }
    }
  }
}