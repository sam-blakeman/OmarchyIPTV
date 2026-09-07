import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "IptvModel.js" as Model

Panel {
  id: root
  moduleName: "io.github.sam-blakeman.iptv"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var service: hostWidget && hostWidget.svc ? hostWidget.svc : null

  property string tab: "live"
  property string query: ""
  property string group: "All"

  readonly property var channels: service ? service.channels : []
  readonly property var vod: service ? service.vod : []
  readonly property var epgNow: service ? service.epgNow : []
  readonly property string statusLine: service ? service.statusLine : "IPTV"
  readonly property string lastError: service ? service.lastError : ""
  readonly property var syncStatus: service && service.status ? service.status : ({})
  readonly property bool providerConfigured: !!(syncStatus && syncStatus.provider)

  property string formType: "xtream"
  property string formHost: ""
  property string formUser: ""
  property string formPassword: ""
  property string formUrl: ""
  property string formEpg: ""
  property string formUa: ""

  function ago(ms) {
    if (!ms) return "never"
    var m = Math.round((Date.now() - ms) / 60000)
    if (m < 1) return "just now"
    if (m < 60) return m + " min ago"
    if (m < 48 * 60) return Math.round(m / 60) + " h ago"
    return Math.round(m / 1440) + " d ago"
  }
  function statusSummary() {
    var s = root.syncStatus
    if (!s || !s.provider) return "No provider configured."
    var out = s.provider + " · synced " + root.ago(service ? service.syncedAtMs : 0)
      + " · " + (s.channels || 0) + " live, " + (s.vod || 0) + " vod"
    if (s.has_epg) {
      out += " · EPG " + (s.epg_programmes || 0) + " programmes"
      if (s.epg_until) out += ", until " + new Date(s.epg_until * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat)
    } else out += " · no EPG source"
    return out + " · auto re-sync daily"
  }
  readonly property bool syncing: service ? service.syncing === true : false
  readonly property bool savingProvider: service ? service.savingProvider === true : false

  readonly property string favGroup: "★ Favorites"
  readonly property var sourceGroups: {
    var g = root.tab === "vod"
      ? (service && service.vodGroups ? service.vodGroups : ["All"])
      : (service && service.liveGroups ? service.liveGroups : Model.groups(root.channels))
    return g && g.length ? g : ["All"]
  }
  readonly property var groupList: [root.favGroup].concat(sourceGroups.filter(function(g) { return g !== root.favGroup }))
  readonly property var livePool: root.group === root.favGroup && service ? service.favItems("live") : root.channels
  readonly property var visibleChannels: Model.filterChannels(livePool, query, root.group === root.favGroup ? "All" : group)
  readonly property var visibleVod: root.group === root.favGroup && service ? service.favItems("vod") : root.vod
  readonly property bool vodNeedsQuery: root.tab === "vod" && root.group !== root.favGroup && root.group === "All" && String(root.query).trim() === ""
  readonly property string emptyHint: {
    if (root.tab === "setup") return ""
    if (!root.providerConfigured) return "Add a provider in Setup."
    if (root.syncing) return "Syncing…"
    if (root.tab === "vod" && root.vodNeedsQuery) return "Pick a group or type to search VOD."
    if (root.tab === "live" && root.visibleChannels.length === 0) return "No channels match."
    if (root.tab === "vod" && root.visibleVod.length === 0) return "No titles match."
    if (root.tab === "epg" && root.epgNow.length === 0) return "No guide data yet. Sync from Setup."
    return ""
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  onTabChanged: {
    if (root.groupList.indexOf(root.group) === -1) root.group = "All"
    if (root.tab === "setup") root.fillForm()
    root.maybeRequestVod()
  }
  onGroupChanged: {
    groupPicker.value = root.group
    root.maybeRequestVod()
  }
  onQueryChanged: root.maybeRequestVod()

  function maybeRequestVod() {
    if (root.tab !== "vod" || !service || !service.requestVod) return
    if (root.group === root.favGroup) return
    service.requestVod(root.group, root.query)
  }

  function fillForm() {
    var s = root.syncStatus || ({})
    if (s.provider) root.formType = s.provider
    root.formHost = s.host || ""
    root.formUser = s.username || ""
    root.formUrl = s.url || ""
    root.formEpg = s.epg || ""
    root.formUa = s.user_agent || ""
    root.formPassword = ""
    if (hostField) hostField.text = root.formHost
    if (userField) userField.text = root.formUser
    if (passwordField) passwordField.text = ""
    if (urlField) urlField.text = root.formUrl
    if (epgField) epgField.text = root.formEpg
    if (uaField) uaField.text = root.formUa
  }

  function saveForm() {
    if (!service || !service.saveProvider) return
    service.saveProvider({
      type: root.formType,
      host: root.formHost,
      username: root.formUser,
      password: root.formPassword,
      url: root.formUrl,
      epg: root.formEpg,
      user_agent: root.formUa
    })
    root.formPassword = ""
  }

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
    if (!ch || !ch.id || ch.available === false) return
    if (service && service.playChannel) service.playChannel(ch)
  }
  function playById(id, name) {
    if (!id || !service || !service.play) return
    service.play(id, name)
  }
  function toggleFav(kind, item) {
    if (service && service.toggleFav) service.toggleFav(kind, item)
  }
  function isFav(kind, id) {
    return service && service.isFav ? service.isFav(kind, id) : false
  }
  function nowFor(item) {
    return service && service.epgText ? service.epgText(item) : (item && item.epg_now ? item.epg_now : "")
  }
  function nextFor(item) {
    return service && service.epgNextText ? service.epgNextText(item) : (item && item.epg_next ? item.epg_next : "")
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
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        RowLayout {
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
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.syncing ? "syncing…" : (root.savingProvider ? "saving…" : root.statusLine)
            color: Color.muted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
          PanelActionButton {
            iconText: "⛶"
            tooltipText: "Fullscreen TV mode"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.openOverlay()
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)
          TextField {
            id: searchField
            Layout.fillWidth: true
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

        ButtonGroup {
          width: parent.width
          value: root.tab
          focusable: false
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          options: [
            { value: "live", label: "Live" },
            { value: "vod", label: "VOD" },
            { value: "epg", label: "Guide" },
            { value: "setup", label: "Setup" }
          ]
          onChanged: function(v) { root.tab = v }
        }

        RowLayout {
          visible: root.tab === "live" || root.tab === "vod"
          width: parent.width
          spacing: Style.space(8)
          Text {
            textFormat: Text.PlainText
            text: "Group"
            color: Color.muted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
          SearchableDropdown {
            id: groupPicker
            Layout.fillWidth: true
            showLabel: false
            placeholderText: "Search groups…"
            fontFamily: root.contentFontFamily
            options: root.groupList
            Component.onCompleted: value = root.group
            onChanged: function(v) { root.group = v }
          }
        }

        Text {
          visible: root.emptyHint !== "" && root.tab !== "setup"
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.emptyHint
          color: Color.muted
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          visible: root.tab === "live"
          width: parent.width
          height: parent.height - y
          clip: true
          model: root.visibleChannels
          delegate: channelDelegate
        }

        ListView {
          visible: root.tab === "vod"
          width: parent.width
          height: parent.height - y
          clip: true
          model: root.visibleVod
          delegate: vodDelegate
        }

        ListView {
          visible: root.tab === "epg"
          width: parent.width
          height: parent.height - y
          clip: true
          model: root.epgNow
          delegate: epgDelegate
        }

        Flickable {
          visible: root.tab === "setup"
          width: parent.width
          height: parent.height - y
          clip: true
          contentWidth: width
          contentHeight: setupCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: setupCol
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.statusSummary()
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: root.lastError !== ""
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.lastError
              color: Color.urgent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            ButtonGroup {
              width: parent.width
              value: root.formType
              focusable: false
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              options: [
                { value: "xtream", label: "Xtream" },
                { value: "m3u", label: "M3U" }
              ]
              onChanged: function(v) { root.formType = v }
            }

            TextField {
              id: hostField
              visible: root.formType === "xtream"
              width: parent.width
              placeholderText: "Host (http://host:port)"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formHost = text
            }
            TextField {
              id: userField
              visible: root.formType === "xtream"
              width: parent.width
              placeholderText: "Username"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formUser = text
            }
            TextField {
              id: passwordField
              visible: root.formType === "xtream"
              width: parent.width
              password: true
              placeholderText: (root.syncStatus && root.syncStatus.has_password) ? "Password (unchanged)" : "Password"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formPassword = text
            }
            TextField {
              id: urlField
              visible: root.formType === "m3u"
              width: parent.width
              placeholderText: "Playlist URL"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formUrl = text
            }
            TextField {
              id: epgField
              visible: root.formType === "m3u"
              width: parent.width
              placeholderText: "EPG URL (optional)"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formEpg = text
            }
            TextField {
              id: uaField
              width: parent.width
              placeholderText: "User-Agent (optional)"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formUa = text
            }

            Button {
              text: root.savingProvider ? "Saving…" : "Save & sync"
              tooltipText: "Write provider and re-sync"
              enabled: !root.savingProvider && !root.syncing
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.saveForm()
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "★ " + (service ? service.favorites.length : 0) + " favorites · Playback in external mpv · Password stays in the keyring"
              color: Color.muted
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Use only playlists and accounts you are authorized to access. This plugin does not provide streams. Unauthorized use is your responsibility."
              color: Color.muted
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

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
          text: modelData.name + (root.nowFor(modelData) ? " — " + root.nowFor(modelData) : "")
          color: modelData.available === false ? Color.muted : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          width: Style.space(110)
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: root.nextFor(modelData) ? "▸ " + root.nextFor(modelData) : ""
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
        onClicked: root.playChannel(modelData)
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
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.playById(modelData.channel_id, modelData.name)
      }
    }
  }
}
