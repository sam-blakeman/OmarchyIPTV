import QtQuick
import Quickshell
import Quickshell.Io

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
  property var epgNow: []
  property string statusLine: "IPTV"
  property bool syncing: false

  property var favorites: []

  readonly property bool playing: playProc.running

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
    if (!dumpEpgProc.running) dumpEpgProc.running = true
  }

  function resync() {
    if (syncProc.running) return
    root.syncing = true
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
      playProc.running = false
    } else {
      playProc.command = cmd
      playProc.running = true
    }
  }

  function stop() {
    playProc.pendingCommand = null
    playProc.running = false
    root.updateStatus()
  }

  function playChannel(ch) {
    if (ch && ch.url) root.play(ch.url, ch.name)
  }

  // ---- favorites ---------------------------------------------------------
  function favKey(kind, id) {
    return String(kind) + ":" + String(id)
  }

  function isFav(kind, id) {
    var k = root.favKey(kind, id)
    for (var i = 0; i < root.favorites.length; i++)
      if (root.favKey(root.favorites[i].kind, root.favorites[i].id) === k) return true
    return false
  }

  function toggleFav(kind, item) {
    if (!item || !item.id) return
    var k = root.favKey(kind, item.id)
    var next = []
    var found = false
    for (var i = 0; i < root.favorites.length; i++) {
      if (root.favKey(root.favorites[i].kind, root.favorites[i].id) === k) found = true
      else next.push(root.favorites[i])
    }
    if (!found) next.push({ kind: kind, id: item.id, name: item.name || String(item.id) })
    root.favorites = next
    saveFavorites()
  }

  function saveFavorites() {
    favFile.setText(JSON.stringify(root.favorites) + "\n")
  }

  // Join favorite refs against live data; stale ids surface with
  // available:false so the UI can grey them instead of dropping them.
  function favItems(kind) {
    var pool = kind === "vod" ? root.vod : root.channels
    var byId = {}
    for (var i = 0; i < pool.length; i++) byId[String(pool[i].id)] = pool[i]
    var out = []
    for (var j = 0; j < root.favorites.length; j++) {
      var f = root.favorites[j]
      if (f.kind !== kind) continue
      var hit = byId[String(f.id)]
      if (hit) out.push(hit)
      else out.push({ id: f.id, name: f.name, url: "", available: false })
    }
    return out
  }

  function epgFor(channelId) {
    for (var i = 0; i < (root.epgNow || []).length; i++)
      if (root.epgNow[i].channel_id === channelId) return root.epgNow[i]
    return null
  }

  function updateStatus() {
    var n = (root.channels || []).length
    if (n > 0 && !root.playing) root.statusLine = n + " channels"
    else if (n === 0 && !root.playing) root.statusLine = "No channels — see Setup"
  }

  // ---- processes -----------------------------------------------------------
  Process {
    id: playProc
    running: false
    command: []
    property var pendingCommand: null
    onExited: {
      if (pendingCommand) {
        command = pendingCommand
        pendingCommand = null
        running = true
      } else {
        // Natural exit (mpv window closed, or manual stop) — status back
        // to the channel count. updateStatus is a no-op while playing,
        // so a queued switch can't clobber the new title.
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
        try { root.epgNow = JSON.parse(text || "[]") } catch (e) { root.epgNow = [] }
        root.updateStatus()
      }
    }
  }

  Process {
    id: syncProc
    running: false
    command: [root.helperPath(), "--sync"]
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      root.syncing = false
      root.statusLine = code === 0 ? "Synced" : "Sync failed — see Setup"
      root.loadAll()
    }
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
