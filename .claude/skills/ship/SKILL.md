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

## Step 6: Upload to App Store Connect

`ExportOptions.plist` already exists with `method: app-store-connect` and
`destination: export`. To upload:

1. Temporarily change `destination` from `export` to `upload` in `ExportOptions.plist`
2. Run the upload for each selected platform (its own `-exportPath`):
```bash
# macOS
xcodebuild -exportArchive -archivePath build/screenshot-macos.xcarchive -exportPath build/upload-macos -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
# iOS
xcodebuild -exportArchive -archivePath build/screenshot-ios.xcarchive -exportPath build/upload-ios -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```
3. Revert `ExportOptions.plist` back to `destination: export`

**If App Store Connect rejects the version** (e.g. "train version is closed for new
build submissions" / `CFBundleShortVersionString` must be higher), auto-bump
`MARKETING_VERSION` to the next free version without prompting, re-archive the affected
platform(s) (the version is embedded in the archive), and re-upload. iOS and macOS track
build numbers per-platform, so the same build number can be used across platforms.

## Step 7: Commit, tag, and push

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

## Step 8: Report

Print a summary:
- Platform(s) shipped
- Previous version and build number
- New version and build number
- Upload status (per platform)
