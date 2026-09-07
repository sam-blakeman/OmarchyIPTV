# omarchy-iptv

Lightweight single-provider IPTV browser for Omarchy Quattro.

* **One provider**: m3u playlist **or** Xtream Codes (Live + VOD)
* **EPG**: XMLTV (`epg` url for m3u, `xmltv.php` for Xtream), now/next only — no week-long grids in memory
* **Themed**: zero hardcoded colors; every surface uses `Color` / `Style` / `Border` shell tokens, so theme switches apply live
* **Light**: QML is browser-only; playback is an external `mpv` window. Stream URLs stay out of the shell. VOD is searched on demand rather than loaded in full.

## Authorized use

This plugin is a player. It does not provide, sell, or host any streams. You must only connect playlists and Xtream accounts you are authorized to use (your own provider subscription, officially redistributable public lists, etc.).

Unauthorized access to copyrighted broadcasts is your responsibility, not the authors'. The software is provided as-is; see `LICENSE`.

## Install

```sh
omarchy plugin add https://github.com/sam-blakeman/OmarchyIPTV.git --enable
omarchy pkg add mpv
```

Requires `mpv` for playback. `python` (stdlib only) and `secret-tool` (libsecret) are used for sync and the Xtream password.

## Configure

Open the IPTV panel → **Setup**. Pick Xtream or M3U, fill the fields, **Save & sync**.

The Xtream password is stored in the keyring (`secret-tool`), not in `provider.json`. Leave the password blank on later saves to keep the current one.

Advanced: `~/.config/omarchy-iptv/provider.json` (mode 600) still works if you prefer files.

```json
{"type": "xtream", "host": "http://host:8080", "username": "myuser"}
```

```json
{"type": "m3u", "url": "https://example.com/playlist.m3u", "epg": "https://example.com/xmltv.xml"}
```

Optional `"user_agent"` key if the provider whitelists a player UA.

Then press 󰑓, or:

```sh
~/.config/omarchy/plugins/io.github.sam-blakeman.iptv/bin/iptv-sync --sync
```

## Use

* Left click bar icon: quick-browse panel (Live / VOD / Guide / Setup)
* Middle click bar icon: stop mpv
* Right click bar icon: re-sync provider + EPG
* ⛶ in the panel, or `omarchy-shell shell summon io.github.sam-blakeman.iptv`: fullscreen TV mode
* Click / Enter on a row: play in external mpv
* Guide rows play the live channel
* VOD: pick a group or type to search (the full VOD catalogue is not loaded into the shell)
* Group picker is searchable
* Sync errors show in Setup (secrets redacted)
* A stream mpv cannot open reports "Stream failed" in the bar and the mpv error in Setup
* Setup shows cache age and EPG coverage; the provider re-syncs automatically once a day

### Favorites

☆/★ per row (or `Ctrl+F` in fullscreen). Stored as `{kind, id, name}` refs in
`~/.config/omarchy-iptv/favorites.json` — no stream URLs. Pinned under
★ Favorites.

### Fullscreen TV mode

Keyboard-first: ↑↓ move · ←→ group · Enter play · Ctrl+F favorite ·
Tab Live/VOD · type to filter · Esc back out. Now/next refreshes from the
cache every 5 minutes. Themed with the `[menu]` surface tokens.

## Layout

```
manifest.json   # kinds: [bar-widget, overlay, service], keepLoaded
BarWidget.qml   # bar button + quick panel loader
Panel.qml       # Live/VOD/Guide/Setup
IptvOverlay.qml # fullscreen 10-foot browser
IptvService.qml # shared singleton: data, mpv playback, favorites
IptvModel.js    # filter/favorites helpers
bin/iptv-sync   # python3 stdlib: m3u/Xtream fetch, XMLTV → sqlite, JSON dumps
bin/iptv-play   # mpv wrapper (looks up stream URL by id)
```

Cache: `~/.cache/omarchy-iptv/` (`channels.json`, `vod.json`, `epg.db`, mode 600).
Stream URLs never leave that cache into QML.

## Remove

```sh
omarchy plugin remove io.github.sam-blakeman.iptv
rm -rf ~/.config/omarchy-iptv ~/.cache/omarchy-iptv
```

## Future (out of scope)

Series (`get_series`/`get_series_info`), full EPG grid, multi-provider.
