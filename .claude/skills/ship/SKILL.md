---
name: ship
description: Bump version and upload to App Store Connect
disable-model-invocation: true
---

# Ship to App Store Connect

Bump the app version, build an archive, and upload to App Store Connect.

## Step 1: Determine version bump

Read the current version from `project.pbxproj`:
- `MARKETING_VERSION` (e.g. `2.0`) — the user-facing version
- `CURRENT_PROJECT_VERSION` (e.g. `2`) — the build number

Always increment `CURRENT_PROJECT_VERSION` by 1.

If `$ARGUMENTS` is provided, use it as the new `MARKETING_VERSION` (e.g. `/ship 2.1`).
If no argument, keep `MARKETING_VERSION` unchanged and only bump the build number.

## Step 2: Update versions in project.pbxproj

Use the Edit tool to update ALL occurrences of both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `screenshot.xcodeproj/project.pbxproj`. There are multiple occurrences (Debug/Release for main target and UI tests target) — update them all using `replace_all`.

## Step 3: Verify the build compiles

```bash
xcodebuild -scheme screenshot -destination 'platform=macOS' build
```

If the build fails, stop and report the error. Do not proceed.

## Step 4: Create archive

```bash
xcodebuild -scheme screenshot -destination 'platform=macOS,arch=arm64' -archivePath build/screenshot.xcarchive archive
```

## Step 5: Upload to App Store Connect

`ExportOptions.plist` already exists with `method: app-store-connect` and `destination: export`. To upload:

1. Temporarily change `destination` from `export` to `upload` in `ExportOptions.plist`
2. Run the upload:
```bash
xcodebuild -exportArchive -archivePath build/screenshot.xcarchive -exportPath build/upload -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```
3. Revert `ExportOptions.plist` back to `destination: export`

## Step 6: Commit, tag, and push

Stage and commit the version changes, create a git tag, then push both the commit and the tag:
```
git add screenshot.xcodeproj/project.pbxproj
git commit -m "Bump version to <MARKETING_VERSION> (<CURRENT_PROJECT_VERSION>)"
git tag v<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>
git push && git push --tags
```

`git push --tags` is mandatory — local-only tags from prior ships should never be left behind.

## Step 7: Report

Print a summary:
- Previous version and build number
- New version and build number
- Upload status
