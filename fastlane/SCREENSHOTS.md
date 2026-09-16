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
invokes the build phase itself. The app is reinstalled per language pass
(`reinstall_app`): the lock-screen notifications scene needs the permission
prompt, which only a fresh install shows. `--skip-build` skips even the up-front
incremental build — right for retakes (better weather, different daylight) or
extra locale passes, wrong after any code change, including fixture edits
(fixtures are compiled in).

The Snapfile pins `ios_version` to the **stable** runtime: snapshot shuts all
simulators down before every language run, and beta runtimes pay 10–20 min of
silent device preparation per cold boot (that once turned a run into 82 min).
Bump the pin when a new stable runtime lands.

Requirements: `brew install fastlane`, Xcode at
`/Applications/Xcode.app`.

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
  registered at launch in screenshot runs only. It answers the forecast (single
  and batched), geocoding, air-quality, alert, ensemble, climate-archive,
  notification, and all radar endpoints (frames, value grids, raster tiles,
  motion, cells, series) from `ScreenshotFixtures`; basemap tiles pass through
  live. No prod view or model contains screenshot logic — the only marks in
  product code are accessibility identifiers the tests navigate by.
- The fixture story: heavy rain right now in Leipzig (with a severe-weather
  alert), clearing into a warm week. The forecast scene instead shows a sunny
  12-day summer stretch. Times anchor to the launch hour.

## Scenes

### Deliverables (framed, uploaded)

| # | Name | Content |
|---|------|---------|
| 01 | now_rain | Heavy rain, alert banner, radar chart |
| 02 | forecast | Hourly + daily forecast (multi-model caption) |
| 03 | map_radar | Fullscreen map, live radar + storm cells |
| 04 | map_temp | Temperature layer + isobars (wind/pressure composed in) |
| 05 | ensemble | Ensemble detail (temperature spread) |
| 06 | air_quality | Environment detail, air-quality section |
| 07 | klima | Climate detail (warming stripes) |
| 08 | now_clear | Calm summer sky, same hero |
| 09 | widgets | Radar + daily-forecast widget gallery |
| 90/91 | map_wind / map_pressure | Composition sources for 04 |

Captions live in `screenshots/<locale>/title.strings`.

### Library (source-only)

App Store Connect takes ten shots, so everything below is captured but marked
`hidden` in `frame-studio/layout.json`: it gets no framed export and deliver
skips it. These are the docs / release-notes / press set — promote any of them
to a deliverable with the ★ toggle in Frame Studio.

| # | Name | Content |
|---|------|---------|
| 20 | hourly_detail | Hourly deck, part-cloudy day with an afternoon shower block |
| 21 | map_layers | Kartenebenen sheet (layer tiles) |
| 22 | map_layer_settings | Same sheet at .large, display toggles |
| 23 | alert_detail | Warning sheet from the Now alert badge |
| 24 | settings | Settings root, member card with stickers |
| 25 | settings_notifications | Alerts detail, all three types on |
| 26 | settings_forecast | Vorhersage with DWD ICON forced + Tageswerte begrenzen |
| 27 | member_card_dock | Member card with the sticker dock open |
| 28–33 | onboarding_* | welcome, features, location, city, notifications, finale |
| 34 | places | Orte list: Mein Standort, Leipzig, Essen (Essen rains) |
| 37 | lock_notifications | Lock screen, rain alert + weather warning |
| 38 | lock_live_activity | Lock screen, running rain Live Activity |

Three fixture stories feed these: the heavy-rain set (default), the sunny
summer set (`nowForecast`, `nowClear`) and a part-cloudy set with an afternoon
shower block (`hourlyDetail`) — see `byStory` in ScreenshotFixtures.swift.

### Scene notes

- **Orte** seeds its cities from scratch on every launch (the simulator is not
  wiped between runs, so appending would leak places into later captures), pins
  the GPS row to Berlin so it isn't a second Leipzig, and answers the batched
  conditions request with an *array* — the single-location forecast fixture does
  not decode there. The radar series is served per coordinate: only Essen rains,
  so exactly one card shows the animated precipitation backdrop.
- **Onboarding** is entered with `-hasCompletedOnboarding NO` plus
  `-onboardingStep <case>`, which drops the flow straight onto one screen. No
  permission prompt is involved; the city step's geocoder hits come from the
  fixture server, so what the test types cannot change what the shot shows.
- **Settings** scenes stage their preferences on `SettingService` /
  `NotificationSettingsManager` rather than as launch arguments: those values
  live in the app-group defaults, which the launch-argument domain never
  reaches. `refreshAuthorizationStatus()` is a no-op in a screenshot run, so the
  staged "authorized" footer survives the view's `.task`.
- **Lock screen** scenes lock the device with `XCUIDevice`'s private
  `pressLockButton` selector — XCUIDevice exposes no lock button, and simctl has
  no lock command. They run last (`test80` / `test81`) and unlock again
  afterwards. Three simulator facts shape them: the lock screen exposes NO
  accessibility elements to XCTest (its tree is bare windows), so everything
  there is a screen-coordinate tap; after the lock press the backlight stays
  off — neither an arriving notification nor a touch lights it — and SpringBoard
  drops every touch while it is off, so a second lock-button press lights the
  lock screen before any tap; and unlocking is a drag up from the bottom edge,
  because a swipe from mid-screen scrolls the notifications into Notification
  Center instead. The notifications are LOCAL ones replaying oscar-server's
  push copy verbatim (`rainNotification` `.start(.upcoming)` and `alertCopy`'s
  DWD branch), so no device token, APNs or backend is involved. iOS collapses an
  app's lock-screen notifications behind a count badge, so the stack gets one
  tap to fan both cards out. The Live Activity is `startPreview(phase:
  .raining)`; the first card an app ever posts carries ActivityKit's own
  consent question inside itself ("Erlauben" at the card's lower right), which
  the test taps by position. The notification permission prompt exists only
  on a fresh install, which is why the Snapfile reinstalls the app per
  language pass; the consent is liveactivitiesd's own record and survives the
  uninstall, so `bin/screenshots.sh` clears it (`com.apple.liveactivitiesd`
  defaults) before every pass — a fastlane retry pass inside one language
  finds it answered and the tap opens the app instead; re-run that locale by
  hand. The script also sets the simulator's SYSTEM language per pass:
  snapshot only hands the language to the app, and the lock screen and the
  keyboard follow the system one. The card is ended when the app comes back to the foreground after the
  unlock, and any leftover card or delivered notification is cleared on every
  staged launch: while an activity is alive, liveactivitiesd relaunches the
  app WITHOUT launch arguments whenever its process dies or the simulator
  boots, and that instance (real network, onboarding) races the next test's
  own launch — which is how a retry pass once shipped the onboarding welcome
  as `01_now_rain`; delivered notifications would push the Live Activity card
  up, off the coordinates its test taps. The lock screen's big clock DOES
  follow the 9:41 status-bar override, so the notification copy carries times
  pinned to it (10:05 / 11:20 / 18:00) instead of real-clock ones.

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
  re-add it to the Snapfile `languages` to re-enable.
- CI: Xcode Cloud is a poor fit for simulator-fleet screenshot jobs; a GitHub
  Actions macOS job running `bin/screenshots.sh` + `upload_screenshots` is the
  suggested route.
