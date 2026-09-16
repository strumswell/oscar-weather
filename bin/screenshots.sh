#!/usr/bin/env bash
#
# Localized App Store screenshots: fastlane snapshot (UI tests, fixture data)
# followed by Frame Studio framing.
#
# Usage:
#   bin/screenshots.sh                     # all locales (de-DE, en-US) + frame
#   bin/screenshots.sh de-DE               # one locale + frame (keeps other locales' captures)
#   bin/screenshots.sh de-DE --skip-build  # skip even the incremental build check
#   bin/screenshots.sh frame               # re-frame existing captures only    (~1 min)
#
# The app is built exactly ONCE per run: an incremental build-for-testing into
# the persistent derived-data path, which every language pass then reuses
# (the Snapfile sets test_without_building, so snapshot never builds). The
# same build products also feed bin/watch-screenshots.sh. --skip-build skips
# even the up-front incremental build — fine for retakes with zero code
# changes, wrong after ANY code change (fixtures are compiled in). The
# remaining time is the UI tests themselves: the map and widget scenes wait
# 7 s each for basemap tiles — the radar data itself is synthetic and
# deterministic.

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app}"

command -v fastlane >/dev/null 2>&1 || {
  echo "fastlane not found. Install with: brew install fastlane" >&2
  exit 1
}

# Keep in sync with ios_version / devices in fastlane/Snapfile (stable runtime, not beta).
IOS_VERSION="26.5"
SIM_NAME="iPhone 17 Pro Max"

arg=""
build=1
for a in "$@"; do
  case "$a" in
    --skip-build)
      build=0
      ;;
    *)
      arg="$a"
      ;;
  esac
done

build_for_testing() {
  echo "Building Oscar°Screenshots (incremental)…"
  xcodebuild build-for-testing -project "./Oscar°.xcodeproj" \
    -scheme "Oscar°Screenshots" \
    -derivedDataPath ./fastlane/derived_data \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max,OS=$IOS_VERSION" \
    -quiet
}

# The Live Activity consent ("Live-Aktivitäten von Oscar° erlauben?") is
# liveactivitiesd's own record, not the app's: it survives the per-language
# uninstall, so a later pass would find it answered and test81's tap on the
# consent button would open the app instead. Cleared before every pass, on the
# booted simulator (the daemon caches its records, so it is restarted too).
reset_live_activity_consent() {
  local udid pid
  udid=$(xcrun simctl list devices "iOS $IOS_VERSION" | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1)
  [ -n "$udid" ] || return 0
  xcrun simctl bootstatus "$udid" -b >/dev/null
  for key in AppAuthorizationRecords FirstResponseRecords SecondResponseRecords; do
    xcrun simctl spawn "$udid" defaults delete com.apple.liveactivitiesd "$key" >/dev/null 2>&1 || true
  done
  # Simulator daemons are host processes; launchd brings it back on demand.
  pid=$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null | awk '$3 == "com.apple.liveactivitiesd" { print $1 }')
  [ -n "$pid" ] && [ "$pid" != "-" ] && kill "$pid" 2>/dev/null || true
}

# snapshot only hands the LANGUAGE to the app (launch arguments); SpringBoard
# and the keyboard keep the simulator's system language, which the lock-screen
# and city-search captures show. Set it to match; snapshot reboots the
# simulator before the pass, which is when SpringBoard picks it up.
set_simulator_language() {
  local udid lang locale keyboard
  udid=$(xcrun simctl list devices "iOS $IOS_VERSION" | grep "$SIM_NAME (" | grep -oE '[0-9A-F-]{36}' | head -1)
  [ -n "$udid" ] || return 0
  lang="$1"                      # de-DE
  locale="${lang/-/_}"           # de_DE
  case "$lang" in
    de-*) keyboard="de_DE@sw=QWERTZ-German;hw=German" ;;
    tr*)  keyboard="tr_TR@sw=Turkish-QWERTY;hw=Automatic" ;;
    *)    keyboard="en_US@sw=QWERTY;hw=Automatic" ;;
  esac
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleLanguages -array "$lang"
  xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleLocale -string "$locale"
  xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboards -array "$keyboard" "emoji@sw=Emoji"
}

capture_locale() {
  set_simulator_language "$1"
  reset_live_activity_consent
  fastlane snapshot --languages "$1" --clear_previous_screenshots false
}

case "$arg" in
  ""|screenshots)
    # Full run: every locale from the Snapfile, one snapshot pass each (the
    # consent reset has to happen between passes), then frame.
    if [ "$build" = 1 ]; then build_for_testing; fi
    rm -f fastlane/screenshots/*/*.png
    for lang in $(grep -E '^languages' fastlane/Snapfile | grep -oE '[a-z]{2}-[A-Z]{2}'); do
      capture_locale "$lang"
    done
    bin/frame-compose.sh
    ;;
  frame)
    bin/frame-compose.sh
    ;;
  *)
    # Treat the argument as a single locale (e.g. de-DE) for fast iteration:
    # capture just that language, then frame everything present. Clearing is
    # disabled because snapshot's clear wipes ALL locales' captures, not just
    # the one being rerun; same-named scenes overwrite anyway.
    if [ "$build" = 1 ]; then build_for_testing; fi
    capture_locale "$arg"
    bin/frame-compose.sh
    ;;
esac
