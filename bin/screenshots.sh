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

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app}"

command -v fastlane >/dev/null 2>&1 || {
  echo "fastlane not found. Install with: brew install fastlane" >&2
  exit 1
}

# Keep in sync with ios_version in fastlane/Snapfile (stable runtime, not beta).
IOS_VERSION="26.5"

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

case "$arg" in
  ""|screenshots)
    # Full run: all locales from the Snapfile, then frame.
    if [ "$build" = 1 ]; then build_for_testing; fi
    fastlane ios screenshots
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
    fastlane snapshot --languages "$arg" --clear_previous_screenshots false
    bin/frame-compose.sh
    ;;
esac
