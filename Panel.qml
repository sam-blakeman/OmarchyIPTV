import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "IptvModel.js" as Model

// Quick-browse panel: Live + VOD + EPG + Setup. All state comes from the
// shared IptvService (injected as `service`); this file only renders.
// Star buttons toggle favorites; the ★ Favorites group pins them on top.
// All colors/type come from shell tokens (Color/Style) so the active
// Omarchy theme applies live.
Panel {
  id: root
  moduleName: "user.iptv"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  property string tab: "live" // live | vod | epg | setup
  property string query: ""
  property string group: "All"

  readonly property var channels: service ? service.channels : []
  readonly property var vod: service ? service.vod : []
  readonly property var epgNow: service ? service.epgNow : []
  readonly property string statusLine: service ? service.statusLine : "IPTV"
  readonly property bool syncing: service ? service.syncing === true : false

  readonly property string favGroup: "★ Favorites"
  readonly property var livePool: root.group === root.favGroup && service ? service.favItems("live") : root.channels
  readonly property var vodPool: root.group === root.favGroup && service ? service.favItems("vod") : root.vod
  readonly property var visibleChannels: Model.filterChannels(livePool, query, root.group === root.favGroup ? "All" : group)
  readonly property var visibleVod: Model.filterChannels(vodPool, query, root.group === root.favGroup ? "All" : group)
  readonly property var groupList: [root.favGroup].concat(Model.groups(tab === "vod" ? vod : channels))

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.close() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function resync() {
    if (service && service.resync) service.resync()
  }
  function playChannel(ch) {
    if (!ch || !ch.url || ch.available === false) return
    if (service && service.playChannel) service.playChannel(ch)
  }
  function playItem(it) {
    if (!it || !it.url || it.available === false) return
    if (service && service.play) service.play(it.url, it.name)
  }
  function toggleFav(kind, item) {
    if (service && service.toggleFav) service.toggleFav(kind, item)
  }
  function isFav(kind, id) {
    return service && service.isFav ? service.isFav(kind, id) : false
  }
  function openOverlay() {
    if (hostWidget && hostWidget.openOverlay) hostWidget.openOverlay()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        // Header
        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            text: "IPTV"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.syncing ? "syncing…" : root.statusLine
            color: Color.muted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
          Item { width: 1; height: 1 } // spacer
          PanelActionButton {
            iconText: "⛶"
            tooltipText: "Fullscreen TV mode"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.openOverlay()
          }
        }

        // Search + resync
        Row {
          width: parent.width
          spacing: Style.space(8)
          TextField {
            id: searchField
            width: parent.width - resyncBtn.width - Style.space(8)
            placeholderText: "Search channels / VOD…"
            foreground: root.contentForeground
            font.family: root.contentFontFamily
            onTextChanged: root.query = text
          }
          PanelActionButton {
            id: resyncBtn
            iconText: "󰑓"
            tooltipText: "Re-sync provider + EPG"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.resync()
          }
        }

        // Tabs
        Row {
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: ["live", "vod", "epg", "setup"]
            Button {
              required property string modelData
              text: modelData
              tooltipText: modelData
              selected: root.tab === modelData
              fontFamily: root.contentFontFamily
              onClicked: root.tab = modelData
            }
          }
        }

        // Group filter (live/vod)
        Row {
          visible: root.tab === "live" || root.tab === "vod"
          width: parent.width
          spacing: Style.space(4)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Group:"
            color: Color.muted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.groupList.slice(0, 8)
            Button {
              required property string modelData
              text: modelData.length > 14 ? modelData.slice(0, 13) + "…" : modelData
              tooltipText: modelData
              selected: root.group === modelData
              fontFamily: root.contentFontFamily
              onClicked: root.group = modelData
            }
          }
        }

        // Live list
        ListView {
          visible: root.tab === "live"
          width: parent.width
          height: Style.space(330)
          clip: true
          model: root.visibleChannels
          delegate: channelDelegate
        }

        // VOD list
        ListView {
          visible: root.tab === "vod"
          width: parent.width
          height: Style.space(330)
          clip: true
          model: root.visibleVod
          delegate: vodDelegate
        }

        // EPG now/next
        ListView {
          visible: root.tab === "epg"
          width: parent.width
          height: Style.space(330)
          clip: true
          model: root.epgNow
          delegate: epgDelegate
        }

        // Setup
        Column {
          visible: root.tab === "setup"
          width: parent.width
          spacing: Style.space(6)
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Single provider. Edit ~/.config/omarchy-iptv/provider.json then press 󰑓.\n\nm3u: {\"type\":\"m3u\",\"url\":\"…m3u\",\"epg\":\"…xmltv\"}\nxtream: {\"type\":\"xtream\",\"host\":\"http://h:8080\",\"username\":\"u\"} + secret-tool store --label iptv application user.iptv username <user>"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "★ " + (service ? service.favorites.length : 0) + " favorites (stored in ~/.config/omarchy-iptv/favorites.json) • Cache: ~/.cache/omarchy-iptv/ • Playback: external mpv via bin/iptv-play"
            color: Color.muted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // --- Delegates (theme-only colors) ---------------------------------------
  Component {
    id: channelDelegate
    Item {
      required property var modelData
      width: ListView.view ? ListView.view.width : 600
      height: Style.space(40)
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(4)
        spacing: Style.space(4)
        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.isFav("live", modelData.id) ? "★" : "☆"
          tooltipText: root.isFav("live", modelData.id) ? "Remove favorite" : "Add favorite"
          foreground: root.isFav("live", modelData.id) ? Color.accent : root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.toggleFav("live", modelData)
        }
        Text {
          width: parent.width - Style.space(150)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: modelData.name + (modelData.epg_now ? " — " + modelData.epg_now : "")
          color: modelData.available === false ? Color.muted : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          width: Style.space(110)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: modelData.epg_next ? "▸ " + modelData.epg_next : ""
          color: Color.muted
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      MouseArea {
        anchors.fill: parent
        anchors.leftMargin: Style.space(30)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.playChannel(modelData)
      }
    }
  }

  Component {
    id: vodDelegate
    Item {
      required property var modelData
      width: ListView.view ? ListView.view.width : 600
      height: Style.space(34)
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(4)
        spacing: Style.space(4)
        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.isFav("vod", modelData.id) ? "★" : "☆"
          tooltipText: root.isFav("vod", modelData.id) ? "Remove favorite" : "Add favorite"
          foreground: root.isFav("vod", modelData.id) ? Color.accent : root.contentForeground
          fontFamily: root.contentFontFamily
          onClicked: root.toggleFav("vod", modelData)
        }
        Text {
          width: parent.width - Style.space(34)
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: modelData.name
          color: modelData.available === false ? Color.muted : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      MouseArea {
        anchors.fill: parent
        anchors.leftMargin: Style.space(30)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.playItem(modelData)
      }
    }
  }

  Component {
    id: epgDelegate
    Item {
      required property var modelData
      width: ListView.view ? ListView.view.width : 600
      height: Style.space(44)
      Column {
        anchors.fill: parent
        anchors.leftMargin: Style.space(4)
        spacing: 0
        Text {
          textFormat: Text.PlainText
          text: modelData.name
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          textFormat: Text.PlainText
          text: (modelData.now ? modelData.now + "  " : "—  ") + (modelData.next ? "▸ " + modelData.next : "")
          color: Color.muted
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }
  }
}
