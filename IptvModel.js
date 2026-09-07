// Pure helpers for the IPTV plugin. No network, no Qt imports —
// testable with plain JS. All parsing/normalization lives here;
// bin/iptv-sync owns fetching, QML owns rendering.
function filterChannels(channels, query, group) {
  var q = String(query || "").toLowerCase();
  return (channels || []).filter(function (c) {
    if (group && group !== "All" && c.group !== group) return false;
    if (!q) return true;
    return String(c.name || "").toLowerCase().indexOf(q) !== -1;
  });
}

function groups(channels) {
  var seen = {};
  var out = ["All"];
  (channels || []).forEach(function (c) {
    var g = c.group || "Ungrouped";
    if (!seen[g]) {
      seen[g] = true;
      out.push(g);
    }
  });
  return out;
}

// epg entries: [{start, end (epoch sec), title, desc}]. Returns
// {now, next} relative to `at` (epoch sec).
function nowNext(programs, at) {
  var now = null;
  var next = null;
  (programs || []).forEach(function (p) {
    if (p.start <= at && at < p.end) now = p;
    else if (p.start > at && (!next || p.start < next.start)) next = p;
  });
  return { now: now, next: next };
}

function fmtTime(epochSec) {
  if (!epochSec) return "";
  var d = new Date(epochSec * 1000);
  var h = d.getHours();
  var m = d.getMinutes();
  return (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m);
}

function progress(p, at) {
  if (!p || p.end <= p.start) return 0;
  return Math.min(1, Math.max(0, (at - p.start) / (p.end - p.start)));
}

// Favorites: refs are {kind, id, name}; joined against live data so
// stored refs never carry credential-bearing stream URLs.
function favKey(kind, id) {
  return String(kind) + ":" + String(id);
}

function toggleFavList(favs, kind, item) {
  var k = favKey(kind, item.id);
  var found = false;
  var next = (favs || []).filter(function (f) {
    if (favKey(f.kind, f.id) === k) {
      found = true;
      return false;
    }
    return true;
  });
  if (!found) next.push({ kind: kind, id: item.id, name: item.name || String(item.id) });
  return next;
}

function isFavInList(favs, kind, id) {
  var k = favKey(kind, id);
  return (favs || []).some(function (f) { return favKey(f.kind, f.id) === k; });
}

// Resolve fav refs of one kind against a data pool. Stale ids are kept
// with available:false so the UI greys them instead of dropping them.
function resolveFavs(favs, kind, pool) {
  var byId = {};
  (pool || []).forEach(function (c) { byId[String(c.id)] = c; });
  var out = [];
  (favs || []).forEach(function (f) {
    if (f.kind !== kind) return;
    var hit = byId[String(f.id)];
    if (hit) out.push(hit);
    else out.push({ id: f.id, name: f.name, url: "", available: false });
  });
  return out;
}
