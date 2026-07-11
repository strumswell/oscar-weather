#!/usr/bin/env bash
# Opens the Frame Studio visual editor for the App Store screenshot layout:
# drag the device and captions, tweak fonts/sizes/colors per scene and locale,
# then render with the real compositor from inside the editor.

set -euo pipefail
cd "$(dirname "$0")/.."

bin/frame-compose.sh --build-only
exec python3 fastlane/frame-studio/server.py "$@"
