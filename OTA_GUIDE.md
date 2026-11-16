# OTA updates with `flutter_patcher` + GitHub

A working setup for shipping Flutter UI and logic changes **over the air** (OTA). There's no app store upload and no reinstall:

```
 dev ──(pull request + merge)──► main
                                  │ push to main (lib/, assets/, pubspec)
                                  ▼
               GitHub Actions "OTA patch" (automatic)
               1. builds a patch against the installed store build (baseline)
               2. signs it and publishes 2-arm64-v8a.fptc + patches.json
                  to GitHub Pages (gh-pages branch)
                                  │
                                  ▼
  App ► OTA icon ► pull to refresh ► "Install" ► "Accept"
      ► downloads + verifies the patch ► restarts ► new UI is live
```

**Tested with:** Flutter **3.47.5**, `flutter_patcher` **1.1.1**, Android arm64.
**Repo:** <https://github.com/souravbarman01/learn_ota>.
**Package docs:** <https://github.com/xuelinger2333/flutter_patcher/tree/main/doc>

---

## Contents

1. [How it works](#1-how-it-works)
2. [Rules and limits](#2-rules-and-limits)
3. [What's in this repo](#3-whats-in-this-repo)
4. [One-time setup](#4-one-time-setup)
5. [Daily flow: ship a patch](#5-daily-flow-ship-a-patch)
6. [Writing patchable code](#6-writing-patchable-code)
7. [New store release](#7-new-store-release)
8. [Rollback](#8-rollback)
9. [Why the app downloads patches itself](#9-why-the-app-downloads-patches-itself)
10. [CI workarounds explained](#10-ci-workarounds-explained)
11. [Troubleshooting](#11-troubleshooting)
12. [Command cheat sheet](#12-command-cheat-sheet)

---

## 1. How it works

| Term | Meaning |
|---|---|
| **Host / store build** | The APK users install (from the Play Store, or here from a GitHub Release). Built by the **Release host** workflow with `flutter_patcher build android`. |
| **Baseline** | A snapshot of the host build: compiled code and the list of APIs it exposes. Saved to the `baselines` branch. Every patch is compiled against it. |
| **Patch (`.fptc`)** | Only your changed Dart code (as bytecode) and changed assets, signed with your key. Named `<buildNumber>-arm64-v8a.fptc`, e.g. `2-arm64-v8a.fptc`. |
| **Build number** | The part after `+` in `pubspec.yaml` → `version: 1.0.0+2`. A patch only fits the host with the **same** build number. |
| **Sequence (seq)** | The time the patch was sealed. A device only installs a patch **newer** than the one it has. |
| **Dynamic interface** | The Flutter/Dart APIs the host exposes to patches. A patch can only call what's in it (see [§6](#6-writing-patchable-code)). |

---

## 2. Rules and limits

| Rule | What it means for you |
|---|---|
| Flutter **3.47.0 – 3.47.9** only | This project is pinned to **3.47.5**: `pubspec.yaml` (`environment: flutter: 3.47.5`) and `FLUTTER_VERSION` in both workflows. Change all three together, followed by a new store release. |
| Patch = **Dart code + assets** | UI/logic ✅. New plugins, `android/`/`ios/` changes, a Flutter or `flutter_patcher` upgrade, removed assets ❌. Those need a new store release. |
| Patch may only call **APIs the host exposes** | If the store build never used e.g. `MainAxisSize`, a patch can't either. Check first with `tool/host_api.sh` ([§6](#6-writing-patchable-code)). |
| Applies on the **next cold start** | The app restarts itself after install (Android). |
| Android **arm64-v8a**, Android **9+** | Older or 32-bit devices run the store code without patches. |
| Only hosts built by **Release host** accept patches | `flutter run` and debug builds show *OTA patching disabled*. |
| **Keep `version:` unchanged between patches** | Change it only for a new store release ([§7](#7-new-store-release)). |
| Only the **newest** patch can be installed | Older entries in the list show as *Superseded*. |
| Signed patches | The private key lives in the `FLUTTER_PATCHER_KEYS` secret. **Lose it and you can't patch installed apps.** |
| Store policy | Google Play and the App Store limit downloading executable code. Read their policies before using this in a published app. |

---

## 3. What's in this repo

| Path | Purpose |
|---|---|
| [lib/main.dart](lib/main.dart) | `FlutterPatcher.init()` before `runApp`. Home screen with the demo buttons and the **OTA icon** (top right). |
| [lib/ota/ota_config.dart](lib/ota/ota_config.dart) | `kPatchBaseUrl`. Must equal `url:` in `flutter_patcher.yaml`. |
| [lib/ota/patch_service.dart](lib/ota/patch_service.dart) | Checks for and downloads the patch **itself** (no gzip), judges it with `inspectPatch`, and loads `patches.json` ([§9](#9-why-the-app-downloads-patches-itself)). |
| [lib/ota/ota_screen.dart](lib/ota/ota_screen.dart) | OTA screen: status, patch list, **Install** → **Accept** → `applyPatchBytes` → restart. |
| [lib/ota/app_restart.dart](lib/ota/app_restart.dart) + [MainActivity.kt](android/app/src/main/kotlin/com/example/learn_ota/MainActivity.kt) | Native cold restart (`learn_ota/app_restart` channel). On iOS the screen asks the user to reopen the app. |
| [flutter_patcher.yaml](flutter_patcher.yaml) | Patch `url` and `trust` (public key, `enabled: true`). Safe to commit. |
| [.github/workflows/release-host.yml](.github/workflows/release-host.yml) | **Manual.** Builds the store APK and baseline, saves the baseline to `baselines`, creates GitHub Release `v<version>`. |
| [.github/workflows/ota-patch.yml](.github/workflows/ota-patch.yml) | **Automatic** on push to `main` (`lib/**`, `assets/**`, `pubspec.*`). Builds, signs and publishes the patch to `gh-pages`. |
| [.github/scripts/keep-pubspec-lock-fresh.sh](.github/scripts/keep-pubspec-lock-fresh.sh) | Wraps `flutter_patcher` in CI to work around two Linux issues ([§10](#10-ci-workarounds-explained)). |
| [tool/host_api.sh](tool/host_api.sh) | Tells you whether a patch may use a Flutter class on the current store build. |

| Branch | Purpose |
|---|---|
| `main` | Released code. Protected: changes only via pull requests. |
| `dev` | Day-to-day work. Merge into `main` with a PR. |
| `gh-pages` | GitHub Pages: `patches/<build>-arm64-v8a.fptc` + `patches/patches.json`. Written by CI only. |
| `baselines` | Store build baselines (`release-default-<build>-arm64-v8a.tar.gz`, …). Written by CI only. **Never delete.** |

---

## 4. One-time setup

Everything below has already been done for this repo. It's here so you can repeat it in another project.

### 4.1 Flutter 3.47.5

```bash
flutter --version           # must print 3.47.5
```

`pubspec.yaml`:

```yaml
environment:
  sdk: ^3.13.4
  flutter: 3.47.5
```

> Working on another project that needs a different Flutter? Switch SDKs (e.g. with FVM), and switch back to 3.47.5 for this one. CI always uses its own 3.47.5.

### 4.2 Repo, branches, protection

```bash
git init -b main && git add . && git commit -m "Initial commit"
git remote add origin https://github.com/<user>/<repo>.git
git push -u origin main
git switch -c dev && git push -u origin dev
```

GitHub → **Settings → Rules → Rulesets → New branch ruleset** on the default branch:
**Restrict deletions**, **Block force pushes**, **Require a pull request before merging** (0 approvals if you work alone).

### 4.3 Packages

```bash
flutter pub add flutter_patcher:1.1.1 http
```

Pin the exact version. Upgrading `flutter_patcher` later counts as a native change and needs a new store release.

### 4.4 Initialise flutter_patcher and signing

```bash
dart run flutter_patcher init
```

Edit `flutter_patcher.yaml` and keep the generated `trust.patch` as it is:

```yaml
url: https://<user>.github.io/<repo>/patches   # baked into the store build
trust:
  patch: <generated public key>
  enabled: true                                 # accept only signed patches
```

Set the same URL in [lib/ota/ota_config.dart](lib/ota/ota_config.dart).

### 4.5 Keys

```bash
dart run flutter_patcher keys status
dart run flutter_patcher keys export --base64                       # → GitHub secret
dart run flutter_patcher keys export --out flutter_patcher_keys.bundle  # → backup
```

- GitHub → **Settings → Secrets and variables → Actions** → secret **`FLUTTER_PATCHER_KEYS`** = the base64 output.
- Move `flutter_patcher_keys.bundle` to a password manager or private drive. **Never commit it.**
- Type the full `dart run flutter_patcher keys export …` command. A bare `export --out …` runs the shell's own `export` command and fails.

`.gitignore`:

```gitignore
.flutter_patcher/
*.fptc
flutter_patcher_keys.bundle
```

### 4.6 `gh-pages` and `baselines` branches

Run this in a throwaway clone, so your project folder (and local keys) are never touched:

```bash
cd /tmp && rm -rf ota-branches
git clone https://github.com/<user>/<repo>.git ota-branches && cd ota-branches

git switch --orphan gh-pages
git rm -rf --quiet . 2>/dev/null
mkdir patches && echo '[]' > patches/patches.json && touch .nojekyll
git add .nojekyll patches/patches.json && git commit -m "Init GitHub Pages"
git push -u origin gh-pages

git switch --orphan baselines
git rm -rf --quiet . 2>/dev/null; rm -rf patches .nojekyll
git commit --allow-empty -m "Init baselines" && git push -u origin baselines

cd /tmp && rm -rf ota-branches
```

Then:
- **Settings → Pages** → Source: `gh-pages` / root. Check that `https://<user>.github.io/<repo>/patches/patches.json` shows `[]`.
- Both workflows declare `permissions: contents: write`, so the default *read* workflow permission is fine.

### 4.7 Workflows

Copy [.github/workflows/](.github/workflows/) and [.github/scripts/](.github/scripts/) from this repo. Pushing workflow files needs a GitHub token with the `workflow` scope:

```bash
gh auth refresh -h github.com -s workflow
```

### 4.8 First store release

1. **Actions → Release host (store build) → Run workflow** (about 8 minutes), or:
   ```bash
   gh workflow run release-host.yml -R <user>/<repo>
   ```
2. It creates release **`v<version>`** with `app-release.apk`, and saves the baseline to `baselines`.
3. Install the APK on an arm64 Android 9+ phone: **Releases → v1.0.0+2 → Assets → app-release.apk**, or
   ```bash
   gh release download v1.0.0+2 -R <user>/<repo> -p app-release.apk -D ~/Downloads
   adb install -r ~/Downloads/app-release.apk
   ```
4. Open the app → OTA icon → it must say **OTA patching enabled** and **No updates available**.

---

## 5. Daily flow: ship a patch

```bash
git switch dev && git pull
# make a UI/logic change in lib/ (check new APIs with tool/host_api.sh first)
flutter analyze && flutter test
git commit -am "Describe the change"
git push
gh pr create --base main --head dev --title "Describe the change" --body "…"
```

1. **Merge the PR** on GitHub. The PR title becomes the patch title in the app.
2. **Actions → OTA patch** starts **by itself** (about 2–3 minutes). Don't also start it by hand, or you get a duplicate run.
3. When it's green, wait **1–5 minutes** for GitHub Pages. Check `https://<user>.github.io/<repo>/patches/patches.json`.
4. **On the phone:** OTA icon → **pull to refresh** → the patch appears with **Install** → **Accept**.
5. The patch downloads, is verified, and the **app restarts by itself** with the change.

Next change: same steps. The new patch replaces the old file, and older entries show as *Superseded*.

> Changes only under `.github/` don't start the OTA patch workflow. Start it by hand if you need to: **Actions → OTA patch → Run workflow**.

---

## 6. Writing patchable code

A patch runs on the **store build's** Flutter. It can only call the APIs that build exposes. Anything else fails in CI:

```
PATCH_UNSAFE: Cannot invoke member 'MainAxisSize.min' from a dynamic module.
```

**Check before you write code:**

```bash
tool/host_api.sh MainAxisSize Column FilledButton
# Host build 2: what a patch may call
#   ✗ MainAxisSize: NOT exposed. A patch cannot use it on this build.
#   ✓ Column: whole class is callable
#   ~ FilledButton: only these members: (unnamed constructor), icon
```

| Result | Meaning |
|---|---|
| ✓ whole class | Use it freely. |
| ~ only these members | Use only those constructors or members. Named *parameters* of a listed constructor are fine. |
| ✗ not exposed | Use something the host already uses, e.g. `mainAxisAlignment: MainAxisAlignment.center` instead of `mainAxisSize: MainAxisSize.min`, or make a [new store release](#7-new-store-release) that uses it. |

Tips:
- Reusing widgets and APIs your app **already** uses is always safe.
- To make future patches more flexible, use the widgets you expect to need somewhere in the store build before releasing it.
- Icons: use constant `Icons.xxx`. `IconData` built at run time isn't supported in patches. The CI notes "IconData requires complete font subsetting" are information, not errors.
- Changing an asset's contents or adding an asset is fine. **Removing** an asset needs a store release.

---

## 7. New store release

Needed for native or plugin changes, a Flutter or `flutter_patcher` upgrade, removed assets, or APIs the current store build doesn't expose.

1. On `dev`, make the change and **bump the build number**: `version: 1.0.0+2` → `1.0.1+3`.
2. Open a PR and merge it. **OTA patch** runs and **skips** with a notice ("No baseline for build 3 yet"). That's expected.
3. Run **Release host (store build)**. You get release `v1.0.1+3` and its baseline.
4. Install or ship the new APK.
5. From now on, merged changes become patches for build `3` (`3-arm64-v8a.fptc`). Phones still on build 2 don't see them; their app filters `patches.json` by build number.

---

## 8. Rollback

- **Ship a fix forward (recommended):** revert the change on `dev` and merge again. That creates a newer patch with the old code.
- **On a device:** `FlutterPatcher.rollback()` removes the installed patch. The same patch can't be re-installed afterwards (sequence rule).
- **Crash protection:** if a patch crashes on start (`FlutterPatcher.init(maxCrashCount: 1)`), it is blacklisted and the app runs the store code.

---

## 9. Why the app downloads patches itself

`flutter_patcher`'s built-in `checkUpdate()` / `applyPatch()` **don't work with GitHub Pages**:

| Request to GitHub Pages | Result |
|---|---|
| Dart default (`Accept-Encoding: gzip`) + `Range: bytes=0-145` | Pages gzips the file and applies the range to the **compressed** bytes → `206`, only **30 bytes** after unpacking → `PatcherException: FormatException: Not a patch file` |
| Same with `Accept-Encoding: identity` | `206`, 146 bytes starting with `FPTC` ✅ |
| Missing file, `identity` | `404` (with gzip, Pages answers `503`, which also throws) |

So [lib/ota/patch_service.dart](lib/ota/patch_service.dart) does it by hand:

1. `FlutterPatcher.patchTarget.fileName` → e.g. `2-arm64-v8a.fptc`.
2. `GET <url>/<file>` with `Range: bytes=0-145` and `Accept-Encoding: identity`. A `404` means no update.
3. `FlutterPatcher.inspectPatch(header)` → `fresh == true` means newer and built for this exact APK.
4. On **Install**: full `GET` with `Accept-Encoding: identity` → `FlutterPatcher.applyPatchBytes(bytes)`. This verifies the signature and installs.
5. Native restart → the patch loads on this cold start.

Build `1.0.0+1` still uses `checkUpdate()`, so it can never receive patches from GitHub Pages. Use build `1.0.0+2` or later.

---

## 10. CI workarounds explained

All of these are in the workflows already. They're listed here so you know why they exist.

| Workaround | Why it's needed |
|---|---|
| `keep-pubspec-lock-fresh.sh`: backdates `pubspec.yaml` in flutter_patcher's build copy | flutter_patcher injects a `dynamic_modules` package into the copy's `package_config.json`, then runs `flutter build apk`. Flutter skips its own `pub get` only if `pubspec.yaml` is older than `pubspec.lock`. On Linux the copy gets fresh timestamps, so `pub get` re-ran and removed the package → `Couldn't resolve the package 'dynamic_modules'`. |
| `keep-pubspec-lock-fresh.sh`: adds an empty `lib/` to packages without one | flutter_patcher 1.1.1 `patch` lists every package's `lib/` without checking it exists. `cupertino_icons` 1.0.9 has none → `Directory listing failed: …/cupertino_icons-1.0.9/lib/`. |
| `rm -rf build/patch && mkdir -p build` before `patch --out build/patch` | `--out` must be a **new** directory → otherwise `PATCH_CONFIG_INVALID: Use a new output directory`. |
| `set -o pipefail` | Without it, `… \| tee` hides a failed `patch`. |
| *Check a baseline exists* step | Skips the patch (notice, not failure) when the build number has no baseline yet ([§7](#7-new-store-release)). |
| *Show / Upload flutter_patcher build log* (on failure) | The real Gradle or compile error lives in `~/.flutter_patcher/builds/*/`, which is deleted with the runner. Download the **flutter-patcher-build-log** artifact and read `9-apk.log` / `failure.json`. |
| `dart run flutter_patcher doctor --project .` | `--project` needs a path; a bare `--project` fails with `USAGE_ERROR`. |

---

## 11. Troubleshooting

### In the app

| Symptom | Cause / fix |
|---|---|
| *OTA patching disabled* | Running a debug or `flutter run` build, or an APK not from **Release host**. Install the release APK. |
| `Not a patch file` | Build `1.0.0+1` (uses `checkUpdate()`). Install build 2 or later ([§9](#9-why-the-app-downloads-patches-itself)). |
| Patch listed, but *Up to date* / no **Install** | It's already installed, or GitHub Pages is still serving the old file (cache up to 10 minutes). Refresh later. |
| `Update check failed: HTTP 5xx` | GitHub Pages hiccup. Retry in a minute. |
| Install fails with `signatureInvalid` | The store build was made with a different key than CI signs with. Rebuild the host. |
| Install fails with `invalidArgs` | The patch is not newer than the installed one (sequence rule). |
| No restart after install | iOS, or the restart channel is missing. Close and reopen the app. |

### In CI

| Error | Cause / fix |
|---|---|
| Run stuck in **Queued** | Waiting for a GitHub runner, usually under 5 minutes. If it hangs, cancel it, or start a new run and delete the stuck one. |
| `refusing to allow an OAuth App to create or update workflow` | Run `gh auth refresh -h github.com -s workflow`. |
| `PATCH_UNSAFE … Cannot invoke member 'X' from a dynamic module` | The API isn't in the store build ([§6](#6-writing-patchable-code)). Check with `tool/host_api.sh X`. |
| `PATCH_NATIVE_CHANGE` | Native, plugin or Flutter change → [new store release](#7-new-store-release). |
| `BASELINE_NOT_FOUND` | No **Release host** run for this build number. |
| `PATCH_BASELINE_INCOMPATIBLE` | `FLUTTER_VERSION` differs from the one the host was built with. |
| `"file": null` / `KEYS_MISMATCH` | `FLUTTER_PATCHER_KEYS` secret missing or wrong. |
| `Couldn't resolve the package 'dynamic_modules'` | Helper script not used. Wrap the command with `keep-pubspec-lock-fresh.sh` ([§10](#10-ci-workarounds-explained)). |
| `Directory listing failed: …/lib/` | Same: the helper script fixes it. |
| `PATCH_CONFIG_INVALID: Use a new output directory` | Don't pre-create the `--out` folder. |
| `BUILD_STEP_FAILED … assembleRelease` | Download the **flutter-patcher-build-log** artifact and read `9-apk.log`. |
| Pages URL 404 | Pages not enabled on `gh-pages`, wrong repo name in `url`, or `.nojekyll` missing. |

---

## 12. Command cheat sheet

```bash
# Can a patch use these APIs on the current store build?
tool/host_api.sh Column Wrap ListTile

# Start workflows by hand
gh workflow run release-host.yml -R souravbarman01/learn_ota
gh workflow run ota-patch.yml    -R souravbarman01/learn_ota

# Watch the latest OTA patch run
gh run watch $(gh run list -R souravbarman01/learn_ota --workflow ota-patch.yml -L 1 --json databaseId -q '.[0].databaseId') -R souravbarman01/learn_ota

# What's published?
curl -s https://souravbarman01.github.io/learn_ota/patches/patches.json
curl -sI -H 'Accept-Encoding: identity' https://souravbarman01.github.io/learn_ota/patches/2-arm64-v8a.fptc

# Store APK
gh release download v1.0.0+2 -R souravbarman01/learn_ota -p app-release.apk -D ~/Downloads
adb install -r ~/Downloads/app-release.apk

# flutter_patcher health and keys
dart run flutter_patcher doctor --project .
dart run flutter_patcher keys status
```
