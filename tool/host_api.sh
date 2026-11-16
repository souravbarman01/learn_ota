#!/usr/bin/env bash
# Usage: tool/host_api.sh <ClassName> [<ClassName> ...]
#
# Shows which members of a Flutter/Dart class a PATCH may call on the store
# build (host) that matches the current `version:` in pubspec.yaml.
# A patch can only call what the host exposes (its "dynamic interface");
# anything else fails CI with PATCH_UNSAFE "Cannot invoke member ...".
#
# Reads the baseline from the `baselines` branch on GitHub (needs `gh` login).
# Example: tool/host_api.sh MainAxisSize Column ListTile
set -euo pipefail
[ $# -ge 1 ] || { sed -n '2,10p' "$0"; exit 2; }

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
VC=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
CACHE=".dart_tool/host_api/$VC"
IFACE="$CACHE/dynamic_interface.yaml"

fetch() { gh api "repos/$REPO/contents/$1?ref=baselines" -H "Accept: application/vnd.github.raw"; }

if [ ! -f "$IFACE" ]; then
  mkdir -p "$CACHE"
  echo "Downloading baseline for build $VC from $REPO (baselines branch)…" >&2
  fetch "release-default-$VC-arm64-v8a.tar.gz" > "$CACHE/release.tgz" \
    || { echo "No baseline for build $VC. Run the 'Release host' workflow first." >&2; exit 1; }
  tar -xzf "$CACHE/release.tgz" -C "$CACHE" release.manifest.json
  FP=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["compile"]["fingerprint"])' "$CACHE/release.manifest.json")
  fetch "compile-$FP.tar.gz" > "$CACHE/compile.tgz"
  tar -xzf "$CACHE/compile.tgz" -C "$CACHE" dynamic_interface.yaml
  rm -f "$CACHE/release.tgz" "$CACHE/compile.tgz"
fi

python3 - "$IFACE" "$VC" "$@" <<'EOF'
import json, sys
iface, vc, classes = sys.argv[1], sys.argv[2], sys.argv[3:]
data = json.load(open(iface))
print(f"Host build {vc}: what a patch may call")
for cls in classes:
    rows = [r for r in data.get("callable", []) if r.get("class") == cls]
    if not rows:
        print(f"  ✗ {cls}: NOT exposed. A patch cannot use it on this build.")
        continue
    if any("member" not in r for r in rows):
        print(f"  ✓ {cls}: whole class is callable")
        continue
    members = sorted({r["member"] or "(unnamed constructor)" for r in rows})
    print(f"  ~ {cls}: only these members: {', '.join(members)}")
EOF
