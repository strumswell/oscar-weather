#!/usr/bin/env bash
set -euo pipefail

defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES

echo "OPEN_METEO_API_KEY = ${OPEN_METEO_API_KEY:?OPEN_METEO_API_KEY is not set}" > "${CI_PRIMARY_REPOSITORY_PATH:?}/Config/Secrets.xcconfig"
