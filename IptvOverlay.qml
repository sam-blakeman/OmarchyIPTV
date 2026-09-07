import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "IptvModel.js" as Model

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.sam-blakeman.iptv"
  readonly property var svc: {
    if (service && service.playChannel) return service
    var map = shell && shell._services
    return (map && map[root.pluginId]) || null
  }

  property bool opened: false
  property string tab: "live"
  property string filterText: ""
  property string group: "All"
  property int selectedIndex: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  readonly property color mutedText: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)

  readonly property string favGroup: "★ Favorites"
  readonly property var sourceGroups: {
    var g = root.tab === "vod"
      ? (svc && svc.vodGroups ? svc.vodGroups : ["All"])
      : (svc && svc.liveGroups ? svc.liveGroups : Model.groups(svc ? svc.channels : []))
    return g && g.length ? g : ["All"]
  }
  readonly property var groupList: [root.favGroup].concat(sourceGroups.filter(function(g) { return g !== root.favGroup }))
  readonly property var livePool: root.group === root.favGroup && svc ? svc.favItems("live") : (svc ? svc.channels : [])
  readonly property var rows: root.tab === "vod"
    ? (root.group === root.favGroup && svc ? svc.favItems("vod") : (svc ? svc.vod : []))
    : Model.filterChannels(livePool, filterText, root.group === root.favGroup ? "All" : group)
  readonly property var selected: rows.length > 0 ? rows[Math.min(root.selectedIndex, rows.length - 1)] : null
  readonly property bool vodNeedsQuery: root.tab === "vod" && root.group !== root.favGroup && root.group === "All" && String(root.filterText).trim() === ""

  onRowsChanged: if (root.selectedIndex > rows.length - 1) root.selectedIndex = Math.max(0, rows.length - 1)
  onTabChanged: root.maybeRequestVod()
  onGroupChanged: root.maybeRequestVod()
  onFilterTextChanged: root.maybeRequestVod()

  function maybeRequestVod() {
    if (root.tab !== "vod" || !svc || !svc.requestVod) return
    if (root.group === root.favGroup) return
    svc.requestVod(root.group, root.filterText)
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.group = "All"
    root.selectedIndex = 0
    root.maybeRequestVod()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() {
    root.opened = false
  }
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }
  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setGroup(g) {
    root.group = g
    root.selectedIndex = 0
    var i = root.groupList.indexOf(g)
    if (i >= 0) groupStrip.positionViewAtIndex(i, ListView.Contain)
  }
  function cycleGroup(d) {
    var list = root.groupList
    if (list.length === 0) return
    var i = list.indexOf(root.group)
    if (i < 0) i = 0
    root.setGroup(list[(i + d + list.length) % list.length])
  }
  function setTab(t) {
    root.tab = t
    root.group = "All"
    root.selectedIndex = 0
  }
  function setFilter(t) {
    root.filterText = t
    root.selectedIndex = 0
  }
  function move(d) {
    if (rows.length === 0) return
    var n = root.selectedIndex + d
    if (n < 0) n = 0
    if (n >= rows.length) n = rows.length - 1
    root.selectedIndex = n
    channelList.positionViewAtIndex(n, ListView.Contain)
  }
  function activateCurrent() {
    var it = root.selected
    if (!it || !it.id || it.available === false || !svc) return
    svc.playChannel(it)
  }
  function favCurrent() {
    var it = root.selected
    if (!it || !it.id || !svc || !svc.toggleFav) return
    svc.toggleFav(root.tab, it)
  }
  function isFav(id) {
    return svc && svc.isFav ? svc.isFav(root.tab, id) : false
  }
  function nowFor(item) {
    return svc && svc.epgText ? svc.epgText(item) : (item && item.epg_now ? item.epg_now : "")
  }
  function nextFor(item) {
    return svc && svc.epgNextText ? svc.epgNextText(item) : (item && item.epg_next ? item.epg_next : "")
  }
  function subtitleFor(item) {
    var now = root.nowFor(item)
    if (!now) return item.group || ""
    var next = root.nextFor(item)
    return next ? now + "  ▸ " + next : now
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-iptv"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(880), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.popupPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.move(-10)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.move(10)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.cycleGroup(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.cycleGroup(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateCurrent()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.setTab(root.tab === "live" ? "vod" : "live")
            event.accepted = true
          } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            root.favCurrent()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(12)
          Text {
            textFormat: Text.PlainText
            text: "IPTV"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: svc ? svc.statusLine : ""
            color: root.mutedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Item { width: 1; height: 1 }
          ButtonGroup {
            anchors.verticalCenter: parent.verticalCenter
            value: root.tab
            focusable: false
            foreground: root.foreground
            fontFamily: root.fontFamily
            options: [
              { value: "live", label: "Live" },
              { value: "vod", label: "VOD" }
            ]
            onChanged: function(v) { root.setTab(v) }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.filterText !== "" ? "Filter: " + root.filterText + "  (" + rows.length + ")" : "Type to filter  (" + rows.length + ")"
          color: root.mutedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        ListView {
          id: groupStrip
          width: parent.width
          height: Style.spacing.controlHeight
          orientation: ListView.Horizontal
          spacing: Style.space(6)
          clip: true
          model: root.groupList
          delegate: Button {
            required property string modelData
            text: modelData
            tooltipText: modelData
            selected: root.group === modelData
            fontFamily: root.fontFamily
            onClicked: root.setGroup(modelData)
          }
        }

        Text {
          visible: root.vodNeedsQuery || rows.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: root.vodNeedsQuery ? "Pick a group or type to search VOD." : (rows.length === 0 ? "No matches." : "")
          color: root.mutedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: channelList
          width: parent.width
          height: parent.height - y - footer.height - parent.spacing
          clip: true
          model: root.rows
          currentIndex: root.selectedIndex
          delegate: Item {
            required property var modelData
            required property int index
            width: ListView.view ? ListView.view.width : 800
            height: Style.space(56)
            Rectangle {
              anchors.fill: parent
              radius: root.cornerRadius
              color: index === root.selectedIndex ? root.selectedBackground : "transparent"
            }
            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)
              Text {
                width: Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.isFav(modelData.id) ? "★" : "☆"
                color: root.isFav(modelData.id) ? Color.accent : root.mutedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
              }
              Column {
                width: parent.width - Style.space(48)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: index === root.selectedIndex ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.subtitleFor(modelData)
                  color: index === root.selectedIndex ? root.selectedText : root.mutedText
                  opacity: index === root.selectedIndex ? 0.85 : 1.0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = index
              onClicked: {
                root.selectedIndex = index
                root.activateCurrent()
              }
            }
          }
        }

        Text {
          id: footer
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "↑↓ move · ←→ group · Enter play · Ctrl+F favorite · Tab Live/VOD · type to filter · Esc close"
          color: root.mutedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
