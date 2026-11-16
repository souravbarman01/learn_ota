#!/usr/bin/env bash
# Usage: keep-pubspec-lock-fresh.sh <command...>
#
# Runs <command> (a flutter_patcher build/patch) and, meanwhile, works around
# two flutter_patcher 1.1.1 issues on Linux CI:
#
# 1. Keeps pubspec.yaml OLDER than pubspec.lock inside flutter_patcher's
#    isolated build copies (~/.flutter_patcher/builds/*/project).
#    flutter_patcher injects a `dynamic_modules` package into the copy's
#    .dart_tool/package_config.json, then runs `flutter build apk`. Flutter
#    skips its own `pub get` only when pubspec.yaml is older than pubspec.lock.
#    On Linux the copy gets fresh timestamps, so pubspec.yaml can end up newer;
#    Flutter then re-runs pub get, the injected package disappears and the
#    release compile fails with "Couldn't resolve the package 'dynamic_modules'".
#
# 2. Gives every package in flutter_patcher's pub cache a lib/ directory.
#    `patch` lists lib/ of every pure-Dart package without checking it exists;
#    asset-only packages such as cupertino_icons 1.0.9 have none, and patch
#    fails with "Directory listing failed: .../cupertino_icons-1.0.9/lib/".
#    An empty lib/ adds no files, so package contents and hashes are unchanged.
set -u

fix_once() {
  for d in "$HOME"/.flutter_patcher/builds/*/project; do
    [ -f "$d/pubspec.yaml" ] && [ -f "$d/pubspec.lock" ] || continue
    if [ ! "$d/pubspec.lock" -nt "$d/pubspec.yaml" ]; then
      touch -t 200001010000 "$d/pubspec.yaml"
      echo "[keep-pubspec-lock-fresh] backdated $d/pubspec.yaml"
    fi
  done
  for pkg in "$HOME"/.flutter_patcher/pub-cache/hosted/*/*/; do
    [ -f "$pkg/pubspec.yaml" ] && [ ! -d "$pkg/lib" ] || continue
    mkdir -p "$pkg/lib"
    echo "[keep-pubspec-lock-fresh] added empty lib/ to $pkg"
  done
}

watch_copies() {
  while :; do
    fix_once
    sleep 0.5
  done
}

fix_once
watch_copies &
watcher=$!
trap 'kill "$watcher" 2>/dev/null' EXIT

"$@"
