#!/usr/bin/env bash
#
# Apple Watch App Store screenshots. Boots a stable-runtime watch simulator,
# installs the watch app (built as part of the Oscar°Screenshots scheme),
# launches each page against the fixture server (compiled into the watch
# target) and captures native-resolution PNGs into the locale folders.
#
# Usage:
#   bin/watch-screenshots.sh              # de-DE + en-US, 4 pages each
#   bin/watch-screenshots.sh de-DE        # one locale
#
# The Series 11 46mm simulator captures at 416×496 px, which App Store Connect
# accepts as-is — watch screenshots are delivered raw (bare UI, no frames),
# so the frame compositor deliberately skips these files.

set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app}"

WATCH_NAME="Apple Watch Series 11 (46mm)"
WATCH_OS="watchOS 26.5"
APP="fastlane/derived_data/Build/Products/Debug-watchsimulator/Oscar°Watch Watch App.app"
BUNDLE_ID="cloud.bolte.Oscar.watchkitapp"
PAGES=(now radar hourly daily)
# Fixture story per page: the radar page runs the heavy-rain scene so its
# nowcast chart has a curve; everything else shows the sunny summer day.
SCENES=(nowForecast nowRain nowForecast nowForecast)

if [ $# -gt 0 ]; then locales=("$@"); else locales=(de-DE en-US); fi

# The watch app is built as a byproduct of the iPhone screenshot build.
if [ ! -d "$APP" ]; then
  echo "Watch app not built yet — building the screenshot scheme…"
  xcodebuild build-for-testing -scheme "Oscar°Screenshots" -project "./Oscar°.xcodeproj" \
    -derivedDataPath ./fastlane/derived_data \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5" -quiet
fi

udid=$(xcrun simctl list devices available | awk -v os="-- $WATCH_OS --" -v name="$WATCH_NAME" '
  $0 ~ os {f=1; next} /^--/ {f=0}
  f && index($0, name) {match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit}')
if [ -z "$udid" ]; then
  echo "No '$WATCH_NAME' simulator on $WATCH_OS found." >&2
  exit 1
fi

echo "Booting $WATCH_NAME ($udid)…"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$APP"
# No permission sheet may cover the captures.
xcrun simctl privacy "$udid" grant location "$BUNDLE_ID" 2>/dev/null || true

for locale in "${locales[@]}"; do
  lang="${locale%%-*}"
  apple_locale="${locale//-/_}"
  mkdir -p "fastlane/screenshots/$locale"
  for i in "${!PAGES[@]}"; do
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$udid" "$BUNDLE_ID" \
      -screenshotScene "${SCENES[$i]}" -watchPage "$i" \
      -AppleLanguages "($lang)" -AppleLocale "$apple_locale" >/dev/null
    sleep 12
    out="fastlane/screenshots/$locale/$WATCH_NAME-w$((i + 1))_${PAGES[$i]}.png"
    xcrun simctl io "$udid" screenshot --type png "$out" >/dev/null
    echo "captured $out"
  done
done

echo "Done. Watch screenshots are uploaded raw by deliver (detected by resolution)."
