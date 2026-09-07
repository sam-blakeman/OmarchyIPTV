import QtQuick
import Quickshell
import Quickshell.Io
import "IptvModel.js" as Model

// Shared singleton for the IPTV plugin (service kind). Owns everything
// both the quick panel and the fullscreen overlay need: provider data,
// mpv playback, and favorites. BarWidget reaches it via
// bar.shell.serviceFor("user.iptv"); the overlay gets it injected as
// `service` by the shell panel loader.
//
// Favorites store only {kind, id, name} — stream URLs stay in the
// mode-600 sync cache and are re-joined at render/play time, so no
// credential-bearing URL ever lands in the favorites file.
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy-iptv"
  readonly property string favPath: configDir + "/favorites.json"

  property var channels: []
  property var vod: []
  property var epgNow: []          // [{channel_id, name, now, next}] for the EPG tab
  property var epgMap: ({})        // channel_id -> {now, next}, refreshed on a timer
  property bool epgLoaded: false
  property string statusLine: "IPTV"
  property string lastError: ""    // last sync or playback failure, secrets redacted
  property bool syncing: false

  // From --dump-status: cache freshness for the Setup tab and auto re-sync.
  property var status: ({})
  readonly property real syncedAtMs: status && status.synced_at ? status.synced_at * 1000 : 0
  readonly property bool providerConfigured: !!(status && status.provider)
  // Re-sync once a day so the EPG window (now-2h..now+24h) never runs dry;
  // checked hourly and once at startup so a laptop that was asleep catches up.
  property int syncIntervalMs: 24 * 3600 * 1000

  property var favorites: []

  readonly property bool playing: playProc.running

  // Now/next is computed at dump time, so re-read it periodically or the
  // guide freezes at whatever was on when the shell started. Only the
  // small EPG map is reloaded — channel rows stay put, so open lists keep
  // their scroll position.
  property int epgRefreshMs: 5 * 60 * 1000

  function helperPath() {
    return Qt.resolvedUrl("bin/iptv-sync").toString().replace(/^file:\/\//, "")
  }
  function playHelperPath() {
    return Qt.resolvedUrl("bin/iptv-play").toString().replace(/^file:\/\//, "")
  }

  Component.onCompleted: loadAll()

  function loadAll() {
    if (!dumpChannelsProc.running) dumpChannelsProc.running = true
    if (!dumpVodProc.running) dumpVodProc.running = true
    refreshEpg()
    refreshStatus()
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function maybeAutoSync() {
    if (root.syncing || !root.providerConfigured) return
    if (Date.now() - root.syncedAtMs > root.syncIntervalMs) root.resync()
  }

  // Stream URLs carry the Xtream password; never let one reach a label.
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

  function play(url, title) {
    var cmd = [root.playHelperPath(), url, "--title", title || "IPTV"]
    root.statusLine = title || "Playing"
    if (playProc.running) {
      // Re-setting command on a running Process is a no-op — stop first
      // and let onExited launch the new stream once mpv is actually gone.
      playProc.pendingCommand = cmd
      playProc.stopRequested = true
      playProc.running = false
    } else {
      playProc.currentUrl = url
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
    if (ch && ch.url) root.play(ch.url, ch.name)
  }

  // ---- EPG -----------------------------------------------------------------
  // Rows carry epg_now/epg_next baked in at load; once the live map has
  // arrived it wins, so a programme that ended is not shown as current.
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

  // ---- favorites (logic lives in IptvModel.js) ----------------------------
  function isFav(kind, id) {
    return Model.isFavInList(root.favorites, kind, id)
  }

  function toggleFav(kind, item) {
    if (!item || !item.id) return
    root.favorites = Model.toggleFavList(root.favorites, kind, item)
    saveFavorites()
  }

  function saveFavorites() {
    favFile.setText(JSON.stringify(root.favorites) + "\n")
  }

  // Join favorite refs against live data; stale ids surface with
  // available:false so the UI can grey them instead of dropping them.
  function favItems(kind) {
    return Model.resolveFavs(root.favorites, kind, kind === "vod" ? root.vod : root.channels)
  }

  function updateStatus() {
    if (root.playing) return
    var n = (root.channels || []).length
    root.statusLine = n > 0 ? n + " channels" : "No channels — see Setup"
  }

  // ---- processes -----------------------------------------------------------
  Process {
    id: playProc
    running: false
    command: []
    property var pendingCommand: null
    property bool stopRequested: false
    property string currentUrl: ""
    property string currentTitle: ""
    stderr: StdioCollector { id: playErr; waitForEnd: true }
    onExited: function(code, status) {
      // mpv: 0 ok, 2 file could not be played, 4 quit by user/signal.
      var failed = !stopRequested && status === 0 && code !== 0 && code !== 4
      if (failed) {
        var lines = String(playErr.text || "").trim().split("\n").filter(function(l) { return l.trim() !== "" })
        var why = lines.length ? lines[lines.length - 1] : ("mpv exit " + code)
        root.lastError = "Playback failed (" + currentTitle + "): " + root.redact(why, currentUrl)
        root.statusLine = "Stream failed: " + currentTitle
      }
      stopRequested = false
      if (pendingCommand) {
        command = pendingCommand
        currentUrl = pendingCommand[1]
        currentTitle = pendingCommand[3] || "IPTV"
        pendingCommand = null
        running = true
      } else if (!failed) {
        // Natural exit (mpv window closed, or manual stop) — status back
        // to the channel count.
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
    id: dumpVodProc
    running: false
    command: [root.helperPath(), "--dump-vod"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.vod = JSON.parse(text || "[]") } catch (e) { root.vod = [] }
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
        // iptv-sync redacts secrets before printing, so the last stderr
        // line is safe to show in the Setup tab.
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
    onTriggered: root.refreshStatus() // -> maybeAutoSync once the dump lands
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
    }
  }
}
