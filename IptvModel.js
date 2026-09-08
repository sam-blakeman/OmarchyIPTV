function filterChannels(channels, query, group) {
  var q = String(query || "").toLowerCase();
  // A category name is a search shortcut only while no group is picked; inside
  // a group every row would trivially match its own group name.
  var wide = !group || group === "All";
  return (channels || []).filter(function (c) {
    if (!wide && c.group !== group) return false;
    if (!q) return true;
    if (String(c.name || "").toLowerCase().indexOf(q) !== -1) return true;
    return wide && String(c.group || "Ungrouped").toLowerCase().indexOf(q) !== -1;
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
