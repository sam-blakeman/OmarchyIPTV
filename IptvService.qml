import QtQuick
import Quickshell
import Quickshell.Io
import "IptvModel.js" as Model

Item {
  id: root

  property var shell: null

  readonly property string pluginId: "io.github.sam-blakeman.iptv"
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy-iptv"
  readonly property string favPath: configDir + "/favorites.json"

  property var channels: []
  property var vod: []
  property var liveGroups: ["All"]
  property var vodGroups: ["All"]
  property var favRows: []
  property var epgNow: []
  property var epgMap: ({})
  property bool epgLoaded: false
  property string statusLine: "IPTV"
  property string lastError: ""
  property bool syncing: false
  property bool savingProvider: false
  property string vodGroup: "All"
  property string vodQuery: ""
  property int vodLimit: 400

  property var status: ({})
  readonly property real syncedAtMs: status && status.synced_at ? status.synced_at * 1000 : 0
  readonly property bool providerConfigured: !!(status && status.provider)
  property int syncIntervalMs: 24 * 3600 * 1000

  property var favorites: []

  readonly property bool playing: playProc.running

  property int epgRefreshMs: 5 * 60 * 1000

  function fileFromUrl(u) {
    var s = String(u || "")
    if (s.indexOf("file://") === 0) s = s.substring(7)
    if (s.charAt(0) !== "/") {
      var i = s.indexOf("/")
      if (i >= 0) s = s.substring(i)
    }
    try { return decodeURIComponent(s) } catch (e) { return s }
  }
  function helperPath() {
    return fileFromUrl(Qt.resolvedUrl("bin/iptv-sync").toString())
  }
  function playHelperPath() {
    return fileFromUrl(Qt.resolvedUrl("bin/iptv-play").toString())
  }

  Component.onCompleted: loadAll()

  function loadAll() {
    if (!dumpChannelsProc.running) dumpChannelsProc.running = true
    if (!dumpLiveGroupsProc.running) dumpLiveGroupsProc.running = true
    if (!dumpVodGroupsProc.running) dumpVodGroupsProc.running = true
    refreshEpg()
    refreshStatus()
    refreshFavRows()
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function maybeAutoSync() {
    if (root.syncing || !root.providerConfigured) return
    if (Date.now() - root.syncedAtMs > root.syncIntervalMs) root.resync()
  }

  function redact(text, url) {
    var s = String(text || "")
    if (url) s = s.split(url).join("<stream>")
    return s.replace(/https?:\/\/\S+/g, "<url>")
  }

  function refreshEpg() {
    if (!dumpEpgProc.running) dumpEpgProc.running = true
  }

  function resync() {
    if (syncProc.running) return
    root.syncing = true
    root.lastError = ""
    root.statusLine = "Syncing…"
    syncProc.running = true
  }

  function play(id, title) {
    if (!id) return
    var cmd = [root.playHelperPath(), "--id", String(id), "--title", title || "IPTV"]
    root.statusLine = title || "Playing"
    if (playProc.running) {
      playProc.pendingCommand = cmd
      playProc.stopRequested = true
      playProc.running = false
    } else {
      playProc.currentTitle = title || "IPTV"
      playProc.command = cmd
      playProc.running = true
    }
  }

  function stop() {
    playProc.pendingCommand = null
    playProc.stopRequested = true
    playProc.running = false
  }

  function playChannel(ch) {
    if (ch && ch.id && ch.available !== false) root.play(ch.id, ch.name)
  }

  function requestVod(group, query) {
    root.vodGroup = group || "All"
    root.vodQuery = query || ""
    vodDebounce.restart()
  }

  function dumpVodNow() {
    if (dumpVodProc.running) dumpVodProc.running = false
    dumpVodProc.running = true
  }

  function saveProvider(cfg) {
    if (!cfg || saveProvProc.running) return
    var cmd = [root.helperPath(), "--write-provider", "--type", String(cfg.type || "")]
    if (cfg.host) { cmd.push("--host"); cmd.push(String(cfg.host)) }
    if (cfg.username) { cmd.push("--username"); cmd.push(String(cfg.username)) }
    if (cfg.url) { cmd.push("--url"); cmd.push(String(cfg.url)) }
    if (cfg.epg) { cmd.push("--epg"); cmd.push(String(cfg.epg)) }
    if (cfg.user_agent) { cmd.push("--user-agent"); cmd.push(String(cfg.user_agent)) }
    saveProvProc.form = cfg
    saveProvProc.command = cmd
    root.savingProvider = true
    root.lastError = ""
    saveProvProc.running = true
  }

  function epgText(item) {
    if (!item) return ""
    if (!root.epgLoaded) return item.epg_now || ""
    var e = root.epgMap[String(item.id)]
    return e ? e.now : ""
  }
  function epgNextText(item) {
    if (!item) return ""
    if (!root.epgLoaded) return item.epg_next || ""
    var e = root.epgMap[String(item.id)]
    return e ? e.next : ""
  }

  function isFav(kind, id) {
    return Model.isFavInList(root.favorites, kind, id)
  }

  function toggleFav(kind, item) {
    if (!item || !item.id) return
    root.favorites = Model.toggleFavList(root.favorites, kind, item)
    saveFavorites()
    refreshFavRows()
  }

  function saveFavorites() {
    favFile.setText(JSON.stringify(root.favorites) + "\n")
  }

  function favItems(kind) {
    return Model.resolveFavs(root.favorites, kind, root.favRows)
  }

  function refreshFavRows() {
    var ids = []
    var favs = root.favorites || []
    for (var i = 0; i < favs.length; i++)
      if (favs[i] && favs[i].id) ids.push(String(favs[i].id))
    if (!ids.length) {
      root.favRows = []
      return
    }
    dumpFavProc.command = [root.helperPath(), "--dump-ids", ids.join(",")]
    if (!dumpFavProc.running) dumpFavProc.running = true
  }

  function updateStatus() {
    if (root.playing) return
    var n = (root.channels || []).length
    root.statusLine = n > 0 ? n + " channels" : "No channels — see Setup"
  }

  Process {
    id: playProc
    running: false
    command: []
    property var pendingCommand: null
    property bool stopRequested: false
    property string currentTitle: ""
    stderr: StdioCollector { id: playErr; waitForEnd: true }
    onExited: function(code, status) {
      var failed = !stopRequested && status === 0 && code !== 0 && code !== 4
      if (failed) {
        var lines = String(playErr.text || "").trim().split("\n").filter(function(l) { return l.trim() !== "" })
        var why = lines.length ? lines[lines.length - 1] : ("mpv exit " + code)
        root.lastError = "Playback failed (" + currentTitle + "): " + root.redact(why, "")
        root.statusLine = "Stream failed: " + currentTitle
      }
      stopRequested = false
      if (pendingCommand) {
        command = pendingCommand
        currentTitle = pendingCommand[4] || "IPTV"
        pendingCommand = null
        running = true
      } else if (!failed) {
        root.updateStatus()
      }
    }
  }

  Process {
    id: dumpChannelsProc
    running: false
    command: [root.helperPath(), "--dump-channels"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.channels = JSON.parse(text || "[]")
        } catch (e) { root.channels = [] }
        root.updateStatus()
      }
    }
  }

  Process {
    id: dumpLiveGroupsProc
    running: false
    command: [root.helperPath(), "--dump-groups", "live"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var g = JSON.parse(text || "[]")
          root.liveGroups = Array.isArray(g) && g.length ? g : ["All"]
        } catch (e) { root.liveGroups = ["All"] }
      }
    }
  }

  Process {
    id: dumpVodGroupsProc
    running: false
    command: [root.helperPath(), "--dump-groups", "vod"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var g = JSON.parse(text || "[]")
          root.vodGroups = Array.isArray(g) && g.length ? g : ["All"]
        } catch (e) { root.vodGroups = ["All"] }
      }
    }
  }

  Process {
    id: dumpVodProc
    running: false
    command: {
      var cmd = [root.helperPath(), "--dump-vod", "--limit", String(root.vodLimit)]
      if (root.vodGroup && root.vodGroup !== "All") {
        cmd.push("--group")
        cmd.push(root.vodGroup)
      }
      if (root.vodQuery) {
        cmd.push("--query")
        cmd.push(root.vodQuery)
      }
      return cmd
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.vod = JSON.parse(text || "[]") } catch (e) { root.vod = [] }
      }
    }
  }

  Timer {
    id: vodDebounce
    interval: 180
    repeat: false
    onTriggered: root.dumpVodNow()
  }

  Process {
    id: dumpFavProc
    running: false
    command: [root.helperPath(), "--dump-ids", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var rows = JSON.parse(text || "[]")
          root.favRows = Array.isArray(rows) ? rows : []
        } catch (e) { root.favRows = [] }
      }
    }
  }

  Process {
    id: dumpEpgProc
    running: false
    command: [root.helperPath(), "--dump-epg-now"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        try { list = JSON.parse(text || "[]") } catch (e) { list = [] }
        var map = ({})
        for (var i = 0; i < list.length; i++)
          map[String(list[i].channel_id)] = { now: list[i].now || "", next: list[i].next || "" }
        root.epgNow = list
        root.epgMap = map
        root.epgLoaded = true
      }
    }
  }

  Process {
    id: statusProc
    running: false
    command: [root.helperPath(), "--dump-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.status = JSON.parse(text || "{}") } catch (e) { root.status = ({}) }
        root.maybeAutoSync()
      }
    }
  }

  Process {
    id: saveProvProc
    running: false
    stdinEnabled: true
    property var form: ({})
    command: [root.helperPath(), "--write-provider", "--type", "xtream"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: saveErr; waitForEnd: true }
    onStarted: {
      write(String((form && form.password) || "") + "\n")
      form = ({})
    }
    onExited: function(code) {
      root.savingProvider = false
      if (code === 0) {
        root.lastError = ""
        root.resync()
      } else {
        var lines = String(saveErr.text || "").trim().split("\n")
        root.lastError = "Save failed: " + (lines.length ? lines[lines.length - 1] : ("exit " + code))
      }
    }
  }

  Process {
    id: syncProc
    running: false
    command: [root.helperPath(), "--sync"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: syncErr; waitForEnd: true }
    onExited: function(code) {
      root.syncing = false
      if (code === 0) {
        root.statusLine = "Synced"
      } else {
        var lines = String(syncErr.text || "").trim().split("\n")
        root.lastError = "Sync failed: " + (lines.length ? lines[lines.length - 1] : ("exit " + code))
        root.statusLine = "Sync failed — see Setup"
      }
      root.loadAll()
    }
  }

  Timer {
    interval: root.epgRefreshMs
    running: true
    repeat: true
    onTriggered: root.refreshEpg()
  }

  Timer {
    interval: 3600 * 1000
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  FileView {
    id: favFile
    path: root.favPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var v = JSON.parse(text() || "[]")
        root.favorites = Array.isArray(v) ? v : []
      } catch (e) { root.favorites = [] }
      root.refreshFavRows()
    }
  }
}
