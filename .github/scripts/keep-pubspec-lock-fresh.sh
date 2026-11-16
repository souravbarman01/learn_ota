#!/usr/bin/env bash
# Usage: keep-pubspec-lock-fresh.sh <command...>
#
# Runs <command> (a flutter_patcher build/patch) and, meanwhile, keeps
# pubspec.yaml OLDER than pubspec.lock inside flutter_patcher's isolated
# build copies (~/.flutter_patcher/builds/*/project).
#
# Why: flutter_patcher injects a `dynamic_modules` package into the copy's
# .dart_tool/package_config.json, then runs `flutter build apk`. Flutter skips
# its own `pub get` only when pubspec.yaml is older than pubspec.lock. On Linux
# the copy gets fresh timestamps in directory order, so pubspec.yaml can end up
# newer; Flutter then re-runs pub get, the injected package disappears and the
# release compile fails with "Couldn't resolve the package 'dynamic_modules'".
set -u

watch_copies() {
  while :; do
    for d in "$HOME"/.flutter_patcher/builds/*/project; do
      [ -f "$d/pubspec.yaml" ] && [ -f "$d/pubspec.lock" ] || continue
      if [ ! "$d/pubspec.lock" -nt "$d/pubspec.yaml" ]; then
        touch -t 200001010000 "$d/pubspec.yaml"
        echo "[keep-pubspec-lock-fresh] backdated $d/pubspec.yaml"
      fi
    done
    sleep 0.5
  done
}

watch_copies &
watcher=$!
trap 'kill "$watcher" 2>/dev/null' EXIT

"$@"
