#!/usr/bin/env bash
# Opens Social Studio: stage the simulator (scene, fixture overrides, status
# bar, notifications, lock screen), capture stills and video, compose them
# into social-media posts under a file-size budget. Needs a Debug build of
# Oscar° on the simulator (any Xcode run, or the fastlane derived-data build).

set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app}"
exec python3 fastlane/social-studio/server.py "$@"
