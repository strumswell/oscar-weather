#!/usr/bin/env bash
# Builds (if stale) and runs the Frame Studio compositor, which renders the
# framed App Store screenshots from fastlane/frame-studio/layout.json.
# All arguments are passed through (--scene, --locale, --out); --build-only
# just compiles.

set -euo pipefail
cd "$(dirname "$0")/.."

src=fastlane/frame-studio/compose.swift
out=fastlane/frame-studio/.build/compose

if [ ! -x "$out" ] || [ "$src" -nt "$out" ]; then
  mkdir -p "$(dirname "$out")"
  echo "Compiling compositor…"
  swiftc -O -o "$out" "$src"
fi

[ "${1:-}" = "--build-only" ] || exec "$out" "$@"
