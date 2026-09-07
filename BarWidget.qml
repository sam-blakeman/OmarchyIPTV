import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.sam-blakeman.iptv"

  readonly property var svc: {
    var sh = bar && bar.shell
    if (!sh) return null
    var map = sh._services
    if (map && map[root.moduleName]) return map[root.moduleName]
    return typeof sh.serviceFor === "function" ? sh.serviceFor(root.moduleName) : null
  }
  readonly property string statusText: svc ? svc.statusLine : "IPTV"
  readonly property bool playing: svc ? svc.playing === true : false
  readonly property int favCount: svc ? svc.favorites.length : 0

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }
  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }
  function resync() {
    if (svc && svc.resync) svc.resync()
  }
  function stopPlayback() {
    if (svc && svc.stop) svc.stop()
  }
  function openOverlay() {
    if (root.bar && root.bar.shell) root.bar.shell.toggle(root.moduleName, "{}")
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onSvcChanged: injectPanel()

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
    target: "io.github.sam-blakeman.iptv"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function overlay(): void { root.openOverlay() }
    function resync(): void { root.resync() }
    function stop(): void { root.stopPlayback() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.playing ? "󰑈 ●" : "󰑈"
    tooltipText: root.statusText
      + (root.favCount > 0 ? " · ★" + root.favCount : "")
      + " — click browse · middle stop · right sync"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.resync()
      else if (b === Qt.MiddleButton) root.stopPlayback()
      else root.togglePanel()
    }
  }
}
