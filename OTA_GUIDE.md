# OTA updates with `flutter_patcher` + GitHub (learning guide)

This guide sets up the flow below in the `learn_ota` project.

```
 dev branch ──(PR + merge)──► main branch
                                 │  push to main
                                 ▼
                    GitHub Actions: "OTA patch"
                    1. builds a patch vs. the released app (baseline)
                    2. uploads  <versionCode>-arm64-v8a.fptc + patches.json
                       to the gh-pages branch (GitHub Pages)
                                 │
                                 ▼
   App ► Update screen ► pull to refresh ► sees the new patch
       ► tap "Download & install" ► restart app ► new UI is live
```

> Based on `flutter_patcher` **1.1.1** (Nov 2026). The package is young and its API
> can change, so keep its docs open:
> <https://github.com/xuelinger2333/flutter_patcher/tree/main/doc> (`getting-started.md`,
> `cli.md`, `api-reference.md`, `advanced.md`).

---

## 0. Know the rules first

| Rule | Why it matters to you |
|---|---|
| **Flutter 3.47.0 – 3.47.9 only** | This project is pinned to **3.47.5** (Step 1). Local and CI must use the **same exact** version. |
| Patch = Dart code + assets only | UI and logic changes ✅. New plugins, native code, `android/`, `ios/`, Flutter upgrades ❌ need a new store release. |
| Patch applies on the **next cold start** | After install, the user must fully close and reopen the app. |
| Android: **arm64-v8a**, Android **9+** | Test on a real arm64 phone (or an arm64 emulator). Android 7–8 run unpatched. |
| Only **release hosts built by `flutter_patcher build`** accept patches | `flutter run` / `flutter build apk` apps are never patched. Debug mode cannot test OTA. |
| Every patch is relative to a **baseline** | The baseline is saved when the host is built. CI needs it to make patches, so we store it in a `baselines` branch. |
| Patch server must **not redirect** | GitHub *Release* download links redirect, so they fail. **GitHub Pages** serves files directly, so we use that. |
| Newer patch = higher sequence (seal time) | Devices only install a patch newer than the one they have. Older patches cannot be re-installed. The app's list shows history, and only the latest can be installed. |
| Keep `version:` in `pubspec.yaml` fixed between patches | The patch file name contains the build number (`1-arm64-v8a.fptc` for `1.0.0+1`). Bump it **only** for a new store release. |

iOS works too (needs an Apple Silicon Mac + Xcode signing). This guide covers **Android** only, which is simpler for learning.

---

## 1. Flutter version: 3.47.5 (pinned)

This project is pinned to **Flutter 3.47.5** (Dart 3.13.4):

```yaml
# pubspec.yaml
environment:
  sdk: ^3.13.4
  flutter: 3.47.5
```

Both workflows use `FLUTTER_VERSION: "3.47.5"`. If you upgrade Flutter, change all three places
and make a **new store release**, because patches must use the same Flutter as the host.

---

## 2. Put the project on GitHub with `main` and `dev`

```bash
cd ~/StudioProjects/learn_ota
git init -b main
git add .
git commit -m "Initial Flutter project"
git remote add origin https://github.com/souravbarman01/learn_ota.git
git push -u origin main

git switch -c dev
git push -u origin dev
git switch main
```

On GitHub → **Settings → Branches**, add a rule for `main` with **Require a pull request before merging** (optional, but it enforces the flow).

---

## 3. Add the packages

```bash
flutter pub add flutter_patcher:1.1.1 http
```

Pin the exact version, because a host built with 1.1.1 must be patched with 1.1.1.
Upgrading the plugin later counts as a native change, so it needs a new store release.

---

## 4. Initialise flutter_patcher and turn on signing

```bash
dart run flutter_patcher init
```

This creates `flutter_patcher.yaml` and a signing key pair.
Edit **`flutter_patcher.yaml`** and keep the generated `trust.patch` value as it is:

```yaml
# Where the app looks for patches. `build` bakes this URL into the app.
url: https://souravbarman01.github.io/learn_ota/patches

trust:
  enabled: true          # was false. Only accept patches signed with our key.
  patch: "<generated public key – do not edit>"
```

Check the setup:

```bash
dart run flutter_patcher doctor --project .
dart run flutter_patcher keys status
```

### 4.1 Give CI the private key

```bash
dart run flutter_patcher keys export --base64
```

Copy the output. On GitHub → **Settings → Secrets and variables → Actions → New repository secret**:

- Name: `FLUTTER_PATCHER_KEYS`
- Value: the base64 text

Also make a backup file of the key and store it safely (password manager / private drive), then delete the local copy:

```bash
dart run flutter_patcher keys export --out flutter_patcher_keys.bundle
# move flutter_patcher_keys.bundle somewhere safe, outside the project
```
**If you lose the key, you cannot patch existing installs. You would need a new store release.**

### 4.2 `.gitignore`

Append:

```gitignore
# flutter_patcher local state (baselines live in the `baselines` branch)
.flutter_patcher/
*.fptc
flutter_patcher_keys.bundle
```

**Do** commit `flutter_patcher.yaml`, because it only holds the public key.

---

## 5. App code (already in this project)

| File | What it does |
|---|---|
| [lib/main.dart](lib/main.dart) | `FlutterPatcher.init()` before `runApp`. Home has a centered **"Hello Patch 1"** button and an **OTA icon** (`Icons.system_update`) in the app bar that opens the OTA screen. |
| [lib/ota/ota_config.dart](lib/ota/ota_config.dart) | `kPatchBaseUrl`. **Replace `souravbarman01`.** It must equal `url:` in `flutter_patcher.yaml`. |
| [lib/ota/patch_service.dart](lib/ota/patch_service.dart) | Downloads `patches.json` (patch history from CI) and filters it to this build number. |
| [lib/ota/ota_screen.dart](lib/ota/ota_screen.dart) | Pull-to-refresh or the refresh icon → `checkUpdate()`. If an update exists → **Install** → *Accept* dialog → `applyPatch()` with progress → automatic restart. |
| [lib/ota/app_restart.dart](lib/ota/app_restart.dart) + [MainActivity.kt](android/app/src/main/kotlin/com/example/learn_ota/MainActivity.kt) | Method channel `learn_ota/app_restart`: kills the process and relaunches the app, so the patch loads on this cold start. On iOS (not implemented) the screen asks the user to reopen the app. |

> The restart code is **native**, so it must be in the store build (host). It is, as long as you
> build the host after this commit. Native changes can't be shipped as a patch later.

Commit everything to `main`:

```bash
git add . && git commit -m "Add flutter_patcher OTA" && git push
```

---

## 6. Create the two helper branches (one time)

Do this in a **throwaway clone**, so your project folder and local `.flutter_patcher/` (which may hold your key) are never touched:

```bash
cd /tmp && rm -rf ota-branches
git clone https://github.com/souravbarman01/learn_ota.git ota-branches && cd ota-branches

# gh-pages: hosts the patches
git switch --orphan gh-pages
git rm -rf --quiet .
mkdir patches && echo '[]' > patches/patches.json && touch .nojekyll
git add .nojekyll patches/patches.json
git commit -m "Init GitHub Pages"
git push -u origin gh-pages

# baselines: stores the release baseline that CI needs
git switch --orphan baselines
git rm -rf --quiet . 2>/dev/null; rm -rf patches .nojekyll
git commit --allow-empty -m "Init baselines"
git push -u origin baselines

cd /tmp && rm -rf ota-branches
```

Then on GitHub:

- **Settings → Pages** → Source: *Deploy from a branch* → `gh-pages` / `(root)` → Save.
  Check that `https://souravbarman01.github.io/learn_ota/patches/patches.json` shows `[]`.
- **Settings → Actions → General → Workflow permissions** → *Read and write permissions*.

---

## 7. GitHub Actions workflows

Set `FLUTTER_VERSION` to the **exact** version from Step 1 in **both** files.

### 7.1 `.github/workflows/release-host.yml`: build the "store" app (manual)

Run this once per store release. It builds the host APK, saves its baseline into the `baselines` branch, and attaches the APK to a GitHub Release.

```yaml
name: Release host (store build)

on:
  workflow_dispatch:

permissions:
  contents: write

env:
  FLUTTER_VERSION: "3.47.5"   # ← exact version, same as local

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          ref: main

      - name: Checkout baselines branch
        uses: actions/checkout@v5
        with:
          ref: baselines
          path: .flutter_patcher/baselines

      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: "17"

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - name: Cache flutter_patcher engines/tools
        uses: actions/cache@v4
        with:
          path: ~/.flutter_patcher
          key: fp-${{ runner.os }}-${{ env.FLUTTER_VERSION }}-${{ hashFiles('pubspec.lock') }}

      - run: flutter pub get
      - run: dart run flutter_patcher doctor --project .

      - name: Build release host + baseline
        env:
          FLUTTER_PATCHER_KEYS: ${{ secrets.FLUTTER_PATCHER_KEYS }}
        run: dart run flutter_patcher build android --out build/host

      - name: Show flutter_patcher build log (on failure)
        if: failure()
        run: |
          B=~/.flutter_patcher/builds
          ls -la "$B" 2>/dev/null || { echo "no $B"; exit 0; }
          find "$B" -type f -size -5M | while read -r f; do
            echo "::group::$f"; tail -n 300 "$f"; echo "::endgroup::"
          done
          echo "===== Likely cause ====="
          grep -rhn -A15 -E "What went wrong|FAILURE: Build failed" "$B" 2>/dev/null | head -80 || true

      - name: Upload flutter_patcher build log (on failure)
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: flutter-patcher-build-log
          path: ~/.flutter_patcher/builds/
          if-no-files-found: ignore

      - name: Save baseline to `baselines` branch
        working-directory: .flutter_patcher/baselines
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -m "Baseline for $(grep '^version:' ../../pubspec.yaml)" || echo "nothing new"
          git push origin HEAD:baselines

      - uses: actions/upload-artifact@v4
        with:
          name: host-build
          path: build/host

      - name: Create GitHub Release with the APK
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
          APKS=$(find build/host -name '*.apk')
          gh release create "v$VERSION" $APKS --title "v$VERSION" --notes "Store build $VERSION" --target main
```

### 7.2 `.github/workflows/ota-patch.yml`: patch on every merge to `main`

```yaml
name: OTA patch

on:
  push:
    branches: [main]
    paths:
      - "lib/**"
      - "assets/**"
      - "pubspec.yaml"
      - "pubspec.lock"
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: ota-patch
  cancel-in-progress: false

env:
  FLUTTER_VERSION: "3.47.5"   # ← exact version, same as release-host.yml

jobs:
  patch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Checkout baselines
        uses: actions/checkout@v5
        with:
          ref: baselines
          path: .flutter_patcher/baselines

      - name: Checkout gh-pages
        uses: actions/checkout@v5
        with:
          ref: gh-pages
          path: site

      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: "17"

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - uses: actions/cache@v4
        with:
          path: ~/.flutter_patcher
          key: fp-${{ runner.os }}-${{ env.FLUTTER_VERSION }}-${{ hashFiles('pubspec.lock') }}

      - run: flutter pub get

      - name: Build patch
        env:
          FLUTTER_PATCHER_KEYS: ${{ secrets.FLUTTER_PATCHER_KEYS }}
        run: |
          mkdir -p build/patch
          dart run flutter_patcher patch android --out build/patch | tee build/patch-result.json

      - name: Show flutter_patcher build log (on failure)
        if: failure()
        run: |
          B=~/.flutter_patcher/builds
          ls -la "$B" 2>/dev/null || { echo "no $B"; exit 0; }
          find "$B" -type f -size -5M | while read -r f; do
            echo "::group::$f"; tail -n 300 "$f"; echo "::endgroup::"
          done
          echo "===== Likely cause ====="
          grep -rhn -A15 -E "What went wrong|FAILURE: Build failed" "$B" 2>/dev/null | head -80 || true

      - name: Upload flutter_patcher build log (on failure)
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: flutter-patcher-build-log
          path: ~/.flutter_patcher/builds/
          if-no-files-found: ignore

      - name: Publish to GitHub Pages
        run: |
          FILE=$(find build/patch -name '*.fptc' | head -n1)
          if [ -z "$FILE" ]; then
            echo "::error::No .fptc produced (see patch-result.json above)"; exit 1
          fi
          NAME=$(basename "$FILE")
          VC=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
          # merge commits keep the PR title in the body; fall back to subject
          TITLE=$(git log -1 --pretty=%b | head -n1)
          [ -z "$TITLE" ] && TITLE=$(git log -1 --pretty=%s)

          mkdir -p site/patches
          cp "$FILE" "site/patches/$NAME"
          [ -f site/patches/patches.json ] || echo '[]' > site/patches/patches.json

          ENTRY=$(jq -n \
            --arg id "${GITHUB_SHA::7}" \
            --arg title "$TITLE" \
            --arg file "$NAME" \
            --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --argjson vc "$VC" \
            '{id:$id, title:$title, file:$file, createdAt:$date, versionCode:$vc}')
          jq --argjson e "$ENTRY" '[$e] + .' site/patches/patches.json > /tmp/p.json
          mv /tmp/p.json site/patches/patches.json

          cd site
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -m "OTA patch ${GITHUB_SHA::7}: $TITLE"
          git push origin HEAD:gh-pages
```

Commit both workflows on `main`. Adding them doesn't trigger a patch, because `.github/` is not in `paths`.

```bash
git add .github && git commit -m "Add OTA workflows" && git push
git switch dev && git merge main && git push && git switch main
```

---

## 8. First release (the "store" app)

1. GitHub → **Actions → Release host (store build) → Run workflow**.
2. When it is green, open **Releases → v1.0.0+1** and download the APK.
   You can also download the `host-build` artifact.
3. Install it on an **arm64 Android 9+** phone:
   ```bash
   adb install -r path/to/app-release.apk
   ```
4. Open the app → **Updates**. It should say *OTA patching: ON* and *No patches yet*.

> In a real project, this is the build you upload to Play Store. The patch flow is the same.

---

## 9. Daily flow: ship a UI change over the air

```bash
git switch dev
# edit lib/main.dart: 'Hello Patch 1' → 'Hello Patch 2' (both the button and the snackbar)
git commit -am "Hello Patch 2"
git push
```

1. GitHub → **Pull requests → New** → base `main` ← compare `dev` → title e.g. *"Hello Patch 2"* → **Merge**.
2. **Actions → OTA patch** runs automatically (about 5–10 min on the first run, faster once cached).
3. When green, `https://souravbarman01.github.io/learn_ota/patches/patches.json` lists the patch.
   GitHub Pages may take **1–10 minutes** to serve it.
4. On the phone: tap the **OTA icon** (top right) → **pull to refresh**. *"Hello Patch 2"* appears with **Install**.
5. Tap **Install** → **Accept**. The patch downloads and the app restarts by itself.
6. The button now says **Hello Patch 2**.

Next change: same steps. The new patch replaces the old file on Pages, and the old entry shows as *Superseded*.

### When a patch is NOT enough (new store release)

You added a plugin, changed `android/`, upgraded Flutter or `flutter_patcher`, or removed an asset.
In that case the **OTA patch** workflow fails with an error like `PATCH_NATIVE_CHANGE`. Then:

1. Bump the build number in `pubspec.yaml` (`1.0.0+1` → `1.0.1+2`) and merge to `main`.
   The patch workflow fails here, which is expected.
2. Run **Release host** again and ship the new APK.
3. Later merges produce `2-arm64-v8a.fptc`. Old installs (`+1`) filter those patches out of their list.

### Roll back a bad patch

- Quick fix: revert the commit on `dev` and merge again. That creates a newer patch with the old code.
- On-device: `FlutterPatcher.rollback()` removes the installed patch.
- `flutter_patcher` also has crash protection. If a patch crashes on boot (`init(maxCrashCount: 1)`), it is blacklisted and the app runs the store code.

---

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| OTA screen says *OTA patching disabled* | You are running `flutter run` / debug, or an APK not built by `flutter_patcher build`. Install the APK from the Release workflow. |
| `BASELINE_NOT_FOUND` in CI | Release host was never run for this `version`, or the build number changed. Run **Release host**. |
| `PATCH_BASELINE_INCOMPATIBLE` | `FLUTTER_VERSION` in CI ≠ the version used for the host build. |
| `PATCH_NATIVE_CHANGE` | A native, plugin or Flutter change. Make a new store release (Step 9). |
| `"file": null` / no `.fptc` | `FLUTTER_PATCHER_KEYS` secret is missing or wrong (`KEYS_MISMATCH`). |
| App lists the patch but `hasUpdate` is false | Pages cache (wait ~10 min), or this device already has it. |
| `applyPatch` → `signatureInvalid` | The host was built with a different public key than CI signs with. Rebuild the host. |
| `applyPatch` → `invalidArgs` | The patch is not newer than the installed one (sequence rule). |
| Pages URL 404 | Pages not enabled on `gh-pages`, wrong repo name in `url`, or `.nojekyll` missing. |
| Push from workflow rejected | Set Actions **Read and write permissions** (Step 6). |
| Phone is 32-bit / Android 8 | Not supported. The app runs, but patches never apply. |

Useful commands:

```bash
dart run flutter_patcher doctor --project .
dart run flutter_patcher keys status
curl -I https://souravbarman01.github.io/learn_ota/patches/1-arm64-v8a.fptc   # must be 200, no redirect
```

---

## 11. Checklist

- [ ] Flutter 3.47.5 locally, in `pubspec.yaml`, and in both workflows
- [ ] `flutter_patcher: 1.1.1` + `http` added
- [ ] `flutter_patcher.yaml`: `url` = Pages URL, `trust.enabled: true`
- [ ] `FLUTTER_PATCHER_KEYS` secret added, key backed up
- [ ] `.flutter_patcher/` in `.gitignore`
- [ ] `souravbarman01` replaced in `ota_config.dart` and `flutter_patcher.yaml`
- [ ] `gh-pages` + `baselines` branches created, Pages enabled, Actions write permission on
- [ ] Workflows committed on `main`
- [ ] Release host run, APK installed on an arm64 phone (Android 9+)
- [ ] dev → PR → merge → patch appears → install → restart → new UI ✅

> **Store policy note:** Google Play and the App Store limit downloading executable code.
> Read the current policies before using OTA patches in a published app. This setup is for learning.
