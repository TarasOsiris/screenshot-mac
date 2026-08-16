---
name: ship
description: Bump version and upload to App Store Connect
disable-model-invocation: true
---

# Ship to App Store Connect

Bump the app version, build archives, and upload to App Store Connect. The app is
multiplatform (macOS + iOS), so each ship targets one or both platforms.

## Step 1: Ask which platforms to ship

Always ask the user which platform(s) to ship this run, using the AskUserQuestion
tool (multi-select). Options: **macOS**, **iOS**. Default recommendation: both.

Skip the question only if the invocation already names the platform(s) unambiguously
(e.g. `/ship ios`, `/ship mac`, `/ship both`) — then proceed with that selection.

Note: a platform word in the arguments (`ios`, `mac`, `macos`, `both`) selects the
platform — it is **not** a marketing version. Only treat an argument as a marketing
version if it looks like one (e.g. `2.1`, `3.3`).

## Step 2: Determine version bump

Read the current version from `project.pbxproj`:
- `MARKETING_VERSION` (e.g. `2.0`) — the user-facing version
- `CURRENT_PROJECT_VERSION` (e.g. `2`) — the build number

Always increment `CURRENT_PROJECT_VERSION` by 1.

If a marketing version is provided as an argument, use it as the new `MARKETING_VERSION`.
If no version argument, keep `MARKETING_VERSION` unchanged and only bump the build number.

`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` are shared by both platforms in
`project.pbxproj`, so one bump covers whichever platforms are selected.

### Step 2b: Verify the marketing version against App Store Connect FIRST

**Do this before archiving.** `MARKETING_VERSION` is baked into the archive, so discovering
a closed train at upload time (Step 7) costs a full re-archive of every selected platform.
Ask App Store Connect up front instead — it's one command per platform:

```bash
asc versions list --app 6760177675 --platform MAC_OS --limit 5
asc versions list --app 6760177675 --platform IOS --limit 5
```

(`6760177675` is Screenshot Bro's App Store Connect app id. `asc` authenticates on its own —
see `asc doctor` if it errors.) Read `attributes.versionString` and `attributes.appStoreState`
of the newest entry for **each selected platform** — the two platforms have independent
version trains, but share one `MARKETING_VERSION` in `project.pbxproj`, so the chosen version
must be free on *all* of them:

- Newest version **equals** the intended `MARKETING_VERSION` and is in an editable state
  (`PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`) →
  the train is open. Keep the version; only the build number bumps.
- Newest version **equals** the intended `MARKETING_VERSION` and is `READY_FOR_SALE` (or any
  other released state) → **the train is closed**. Bump `MARKETING_VERSION` to the next free
  value above it (e.g. `4.0` released → ship `4.1`) without prompting.
- Newest version is **lower** than the intended `MARKETING_VERSION` → nothing to do.

This is the same rejection Step 7 would otherwise return as error `90186`
("train version … is closed for new build submissions") / `90062`
(`CFBundleShortVersionString` must be higher). Step 7 keeps its recovery path as a fallback,
but with this check it should rarely fire.

## Step 3: Update versions in project.pbxproj

Use the Edit tool to update ALL occurrences of both `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `screenshot.xcodeproj/project.pbxproj`. There are multiple
occurrences (Debug/Release for main target and UI tests target) — update them all using
`replace_all`.

## Step 4: Verify the build compiles

Verify each selected platform compiles before archiving:

```bash
# macOS
xcodebuild -scheme screenshot -destination 'platform=macOS' build
# iOS
xcodebuild -scheme screenshot -destination 'generic/platform=iOS' build
```

If a build fails, stop and report the error. Do not proceed.

## Step 5: Create archive(s)

Archive each selected platform to its own archive path:

```bash
# macOS
xcodebuild -scheme screenshot -destination 'platform=macOS,arch=arm64' -archivePath build/screenshot-macos.xcarchive archive
# iOS
xcodebuild -scheme screenshot -destination 'generic/platform=iOS' -archivePath build/screenshot-ios.xcarchive archive
```

## Step 6: Upload dSYMs to Sentry

Upload debug symbols for each archived platform so crash reports symbolicate:

```bash
# macOS
sentry-cli debug-files upload -o nineva-studios -p screenshot-bro build/screenshot-macos.xcarchive
# iOS
sentry-cli debug-files upload -o nineva-studios -p screenshot-bro build/screenshot-ios.xcarchive
```

- Auth comes from `~/.sentryclirc` (outside the repo, same convention as the `.p8`). Never put a
  Sentry token in the repo.
- `-p screenshot-bro` is mandatory — the CLI's default project is `captions-bro`.
- If an upload fails, **report it as a warning and continue**. The App Store upload is the critical
  path; missing dSYMs only cost symbolication and can be uploaded later from the same archive.

## Step 7: Upload to App Store Connect

`ExportOptions.plist` already exists with `method: app-store-connect` and
`destination: export`. Authenticate with the App Store Connect API key (the
signed-in-Xcode-account path fails with "Failed to Use Accounts" in automated/
headless contexts — always pass the key):
- Key file: `/Users/taras/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8`
- Key ID: `4KK2B86XC6`
- Issuer ID: `69a6de84-a676-47e3-e053-5b8c7c11a4d1`

The `.p8` lives in iCloud (outside the repo) — never copy it into the repo.

1. Temporarily change `destination` from `export` to `upload` in `ExportOptions.plist`
2. Run the upload for each selected platform (its own `-exportPath`), passing the API key:
```bash
# macOS
xcodebuild -exportArchive -archivePath build/screenshot-macos.xcarchive -exportPath build/upload-macos -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath "/Users/taras/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8" -authenticationKeyID 4KK2B86XC6 -authenticationKeyIssuerID 69a6de84-a676-47e3-e053-5b8c7c11a4d1
# iOS
xcodebuild -exportArchive -archivePath build/screenshot-ios.xcarchive -exportPath build/upload-ios -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates -authenticationKeyPath "/Users/taras/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8" -authenticationKeyID 4KK2B86XC6 -authenticationKeyIssuerID 69a6de84-a676-47e3-e053-5b8c7c11a4d1
```
3. Revert `ExportOptions.plist` back to `destination: export`

**If App Store Connect rejects the version** (e.g. "train version is closed for new
build submissions" / `CFBundleShortVersionString` must be higher), auto-bump
`MARKETING_VERSION` to the next free version without prompting, re-archive the affected
platform(s) (the version is embedded in the archive), and re-upload. iOS and macOS track
build numbers per-platform, so the same build number can be used across platforms.

Step 2b should have caught this already — if it fires here, the pre-check missed a case, so
say so in the Step 9 report. Re-archiving both platforms is the expensive path this exists to
avoid. Note the re-archived binaries have new dSYM UUIDs, so **re-run Step 6** for every
platform you re-archived before re-uploading.

## Step 8: Commit, tag, and push

Stage and commit the version changes, create a git tag, then push both the commit and
the tag:
```
git add screenshot.xcodeproj/project.pbxproj
git commit -m "Bump version to <MARKETING_VERSION> (<CURRENT_PROJECT_VERSION>)"
git tag v<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>
git push && git push --tags
```

`git push --tags` is mandatory — local-only tags from prior ships should never be left
behind.

## Step 9: Report

Print a summary:
- Platform(s) shipped
- Previous version and build number
- New version and build number
- Upload status (per platform)
- Sentry dSYM upload status (per platform)
