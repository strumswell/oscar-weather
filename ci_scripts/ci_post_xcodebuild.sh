#!/bin/bash
set -euo pipefail

if [ ! -d "${CI_ARCHIVE_PATH:-}" ]; then
    echo "Archive does not exist, skipping Sentry upload"
    exit 0
fi

# sentry-cli installs into the current directory (ci_scripts) on Xcode Cloud
export INSTALL_DIR="$PWD"
CLI="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is not set}/ci_scripts/sentry-cli"

if [ ! -x "$CLI" ]; then
    if command -v sentry-cli >/dev/null 2>&1; then
        CLI="$(command -v sentry-cli)"
    else
        echo "Installing Sentry CLI"
        curl -sL https://sentry.io/get-cli/ | bash
    fi
fi

echo "Authenticate to Sentry"
"$CLI" login --auth-token "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN is not set}"

echo "Uploading dSYM to Sentry"
"$CLI" debug-files upload --include-sources -o 'philipp-bolte' -p 'oscar' "$CI_ARCHIVE_PATH"
