# omarchy-iptv

Lightweight single-provider IPTV browser for Omarchy Quattro.

* **One provider**: m3u playlist **or** Xtream Codes (Live + VOD)
* **EPG**: XMLTV (`epg` url for m3u, `xmltv.php` for Xtream), now/next only — no week-long grids in memory
* **Themed**: zero hardcoded colors; every surface uses `Color` / `Style` / `Border` shell tokens, so theme switches apply live
* **Light**: QML is browser-only; playback is an external `mpv` window launched per channel. A bad stream can never kill `omarchy-shell`

## Install

```sh
# dev checkout (or `omarchy plugin add <url>` once published)
git clone https://github.com/sam-blakeman/OmarchyIPTV.git ~/.config/omarchy/plugins/user.iptv
omarchy plugin validate ~/.config/omarchy/plugins/user.iptv
omarchy plugin enable user.iptv --section right

omarchy pkg add mpv python
```

## Configure (single provider)

Create `~/.config/omarchy-iptv/provider.json` (mode 600):

m3u:
```json
{"type": "m3u", "url": "https://example.com/playlist.m3u", "epg": "https://example.com/xmltv.xml"}
```

Xtream:
```json
{"type": "xtream", "host": "http://host:8080", "username": "myuser"}
```

Either type accepts an optional `"user_agent"` key; the sync and mpv both
send it, for providers that whitelist a player UA.
```sh
secret-tool store --label 'omarchy-iptv' application user.iptv username myuser
# else $IPTV_PASSWORD, else "password" key in provider.json (discouraged)
```

Then press the bar 󰑓 button, or:
```sh
~/.config/omarchy/plugins/user.iptv/bin/iptv-sync --sync
```

## Use

* Left click bar icon: quick-browse panel (Live / VOD / EPG / Setup tabs)
* ⛶ button in panel, or `omarchy-shell shell summon user.iptv`: fullscreen TV mode
* Click / Enter on a row: play in external mpv
* Middle click bar icon: stop mpv
* Right click bar icon: re-sync provider + EPG
* Group picker is searchable (playlists routinely carry 50-100 groups)
* Sync errors show in the Setup tab (secrets redacted before they reach the shell)
* A stream mpv cannot open reports "Stream failed" in the bar and the mpv error in Setup
* Setup shows cache age and EPG coverage; the provider re-syncs automatically once a day
  (checked hourly and at shell start)

### Favorites

☆/★ per row (or `Ctrl+F` in fullscreen). Stored as `{kind, id, name}` refs in
`~/.config/omarchy-iptv/favorites.json` — no stream URLs, so no
credential-bearing Xtream URLs touch the file. Pinned under the
★ Favorites group in both panel and fullscreen.

m3u ids are a hash of url + name + group, so they survive playlist
re-ordering and stay distinct when several streams share one `tvg-id`.

### Fullscreen TV mode

Keyboard-first: ↑↓ move · ←→ group · Enter play · Ctrl+F favorite ·
Tab Live/VOD · type to filter · Esc back out. Now/next refreshes from the
cache every 5 minutes without disturbing the list. Themed with the `[menu]` surface tokens,
so it follows the active Omarchy theme like the emoji picker.

## Layout

```
manifest.json   # kinds: [bar-widget, overlay, service], keepLoaded
BarWidget.qml   # bar button + quick panel loader (clock pattern)
Panel.qml       # Live/VOD/EPG/Setup quick browser (KeyboardPanel)
IptvOverlay.qml # fullscreen 10-foot browser (PanelWindow overlay)
IptvService.qml # shared singleton: data, mpv playback, favorites
IptvModel.js    # pure filter/now-next/favorites helpers
bin/iptv-sync   # python3 stdlib: m3u/Xtream fetch, XMLTV → sqlite, JSON dumps
bin/iptv-play   # mpv wrapper
```

Cache: `~/.cache/omarchy-iptv/` (`channels.json`, `vod.json`, `epg.db`, mode 600).
`tvg-logo` URLs are kept in the cache but dropped from the dumps the shell
parses; nothing renders them yet.
XMLTV is stream-parsed (`iterparse`), so a week-long multi-MB guide never
sits in memory as a DOM; only now-2h..now+24h is stored.
No symlinks *inside* the plugin dir (shell validation rejects them); the
plugin dir itself may be a symlink to a dev checkout.

## Remove

```sh
omarchy plugin remove user.iptv
rm -rf ~/.config/omarchy-iptv ~/.cache/omarchy-iptv
```

## Future (out of scope)

Series (`get_series`/`get_series_info`), full EPG grid, multi-provider.
