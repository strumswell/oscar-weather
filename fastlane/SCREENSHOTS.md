# App Store screenshots

Localized (de-DE, en-US, tr) App Store screenshots, captured with fastlane
snapshot and framed by the in-repo **Frame Studio** compositor on the brand
gradient (`#3AA0FF → #0067DF`) with white captions in SeriouslyNostalgic.

## Run

```sh
bin/screenshots.sh                     # capture (all scenes × locales) + frame
bin/screenshots.sh de-DE               # one locale (keeps the other locales' captures)
bin/screenshots.sh de-DE --skip-build  # skip even the incremental build (no code changes since)
bin/screenshots.sh frame               # re-frame existing captures (~20 s)
bin/frame-studio.sh                    # visual editor for the frame layout
```

The app is built exactly **once** per run: the script does an incremental
`build-for-testing` into a persistent derived-data path
(`fastlane/derived_data`, gitignored), and every language pass reuses those
products — the Snapfile sets `test_without_building`, so snapshot never
invokes the build phase itself. The app also stays installed across language
passes (`reinstall_app` is off; re-enable it if the permission-prompting
notifications scene comes back). `--skip-build` skips even the up-front
incremental build — right for retakes (better weather, different daylight) or
extra locale passes, wrong after any code change, including fixture edits
(fixtures are compiled in).

The Snapfile pins `ios_version` to the **stable** runtime: snapshot shuts all
simulators down before every language run, and beta runtimes pay 10–20 min of
silent device preparation per cold boot (that once turned a run into 82 min).
Bump the pin when a new stable runtime lands.

Requirements: `brew install fastlane`, Xcode-beta at
`/Applications/Xcode-beta.app`.

## Framing (Frame Studio)

`bin/frame-studio.sh` opens a local visual editor (http://127.0.0.1:8765).
The sidebar has three tabs: **iOS** lists the deliverable layouts (one per
App Store screenshot — composition sources don't appear here), **watchOS**
reviews the raw watch captures (they ship undecorated), and **Library** holds
every capture and uploaded image with one-click adding to the current layout
(and the source-only ★/☆ toggle). On a layout: drag the device and captions,
double-click any caption to edit its text right on the stage (Escape or a
click elsewhere ends editing),
tweak font, size, color, alignment, line height and letter spacing per scene,
add extra text blocks and images, resize via corner handles, rotate via the
top knob, reorder layers, and give any element a shadow. **Render preview**
checks the shot with the real compositor; **Render all** rebuilds every
deliverable.

Positions are shared across languages by default. Tick "position for
<locale> only" on the device or caption to let one language diverge;
"Sync positions across languages" collapses everything back to the current
view. Uploaded images land in `fastlane/frame-studio/images/` (committed).
The device inspector's "screen radius" rounds the screenshot's corners under
the bezel — 180 fits the Pro Max squircle; the raw captures are square.

- Layout lives in `fastlane/frame-studio/layout.json`. Style cascade per key:
  per-locale override → per-scene override → defaults; the locale level wins
  so tr keeps Georgia Bold (SeriouslyNostalgic has no Turkish glyphs).
- Caption text stays in `screenshots/<locale>/title.strings`; the editor
  edits it in place.
- The compositor is `fastlane/frame-studio/compose.swift` (CoreGraphics/
  CoreText, compiled on demand by `bin/frame-compose.sh`). Device frame art
  in `fastlane/frame-studio/frames/` comes from fastlane's frameit assets.
- frameit is retired (its Framefile.json is deleted). It could not do
  per-screenshot layouts, took ~8 min per run, and silently never framed tr:
  it resolved the Framefile's absolute font path relative to the screenshots
  folder.

Preview the **framed** deliverables at `fastlane/screenshots/framed.html`.
(snapshot also writes `screenshots.html`, but that shows the *raw*, unframed
captures — open `framed.html` for the actual output.)

The run captures in the simulator's **dark** appearance (Oscar° is dark-only;
the fullscreen map's UIKit glassy overlays follow the device trait, so a light
simulator renders them wrong). The status bar is forced to 9:41 with a full
white battery.

All data is deterministic fixture data — including the radar: the map scenes
and the widget composite render a synthetic precipitation field (a SW→NE
frontal band over Leipzig, `SyntheticRadar` in ScreenshotFixtures.swift). Only
basemap tiles and colormaps load live.

## How it works

- `Oscar°UITests/ScreenshotTests.swift` — one test per screenshot. Launches the
  app with `-screenshotScene <name>` and navigates through the real UI.
- `Oscar°/Debug/ScreenshotFixtureServer.swift` — a `URLProtocol` fake server
  registered at launch in screenshot runs only. It answers the forecast,
  air-quality, alert, ensemble, climate-archive, notification, and all radar
  endpoints (frames, value grids, raster tiles, motion, cells, series) from
  `ScreenshotFixtures`; basemap tiles pass through live. No prod view or model
  contains screenshot logic.
- The fixture story: heavy rain right now in Leipzig (with a severe-weather
  alert), clearing into a warm week. The forecast scene instead shows a sunny
  12-day summer stretch. Times anchor to the launch hour.

## Scenes

| # | Name | Content |
|---|------|---------|
| 01 | now_rain | Heavy rain, alert banner, radar chart |
| 02 | forecast | Hourly + daily forecast (multi-model caption) |
| 03 | map_radar | Fullscreen map, live radar + storm cells |
| 04 | map_temp | Temperature layer + isobars |
| 05 | ensemble | Ensemble detail (temperature spread) |
| 06 | air_quality | Environment detail, air-quality section |
| 07 | klima | Climate detail (warming stripes) |
| 08 | customization | Member card with stickers, settings incl. app icons |
| 09 | widgets | Radar + daily-forecast widget gallery |
| 10 | notifications | Notification settings, all alerts enabled |

Captions live in `screenshots/<locale>/title.strings`.

## Apple Watch

`bin/watch-screenshots.sh` captures the four watch pages (now, radar, hourly,
daily) per locale on the Series 11 46mm simulator (416×496 px — an accepted
ASC size). It runs on plain `simctl` + `xcodebuild`, no fastlane: the watch
app comes out of the same derived-data build the phone run produces (it only
builds itself if those products are missing — after watch code changes, run
`bin/screenshots.sh` first or delete the built `.app` to force a rebuild). Data is fixture-fed per page (sunny story everywhere, the rain
story on the radar page so its chart has a curve); pages are preselected via
the `-watchPage` launch argument, no watch UI tests needed. watchOS runs
URLSession loading out of process, so the URLProtocol fixture server never
fires there — the fixtures ride in through `APIClient`'s staging seams
(middleware + fetch hook) instead. Watch screenshots ship raw (bare UI, no
frames, per Apple's spec) — the compositor and the editor skip any capture
with "Watch" in the filename, and deliver assigns them by resolution.

Known limitation: the watch corner clock shows real time. `simctl status_bar`
is unsupported on watchOS simulators, and a TZ override shifts the app's
internal clock without touching the system-rendered corner clock (verified
both) — there is currently no way to pin it to 9:41.

## Upload (manual for now)

```sh
export ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/keys/AuthKey_….p8
fastlane ios upload_screenshots
```

Create a Team API key (App Manager role) under App Store Connect → Users and
Access → Integrations. deliver prefers the `*_framed` variants automatically
(once framed files exist in a locale folder, only `*framed*`/`*watch*` files
upload — raw captures and the 90/91 composition sources are skipped).

The upload lane mirrors the en-US set to the other English storefronts
(en-GB, en-CA, en-AU) via a staged temp copy; deliver creates any missing
version localizations itself. Edit `english_storefronts` in the Fastfile to
change the list.

## Follow-ups

- iPad Pro 13" device pass (required size for iPad-capable apps; ASC currently
  scales the iPhone set).
- tr locale is parked (title.strings + the Georgia Bold layout override stay);
  re-add it to the Snapfile `languages` to re-enable. Scenes 08 customization
  and 10 notifications are parked too (`skipped_` test prefix).
- CI: Xcode Cloud is a poor fit for simulator-fleet screenshot jobs; a GitHub
  Actions macOS job running `bin/screenshots.sh` + `upload_screenshots` is the
  suggested route.
