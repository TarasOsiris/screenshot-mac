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

## Step 5: Export for App Store

```bash
xcodebuild -exportArchive -archivePath build/screenshot.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist
```

If `ExportOptions.plist` does not exist, create it first:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>XW3GM347XY</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

## Step 6: Upload to App Store Connect

```bash
xcrun altool --upload-app --type macos --file "build/export/Screenshot Bro.pkg" --apiKey "$APP_STORE_API_KEY" --apiIssuer "$APP_STORE_API_ISSUER" 2>&1 || \
xcrun notarytool submit "build/export/Screenshot Bro.pkg" --keychain-profile "AC_PASSWORD" --wait 2>&1
```

If `altool` and `notarytool` both fail, try the newer `xcodebuild` upload approach:

```bash
xcodebuild -exportArchive -archivePath build/screenshot.xcarchive -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

The `-exportOptionsPlist` with `destination: upload` and `method: app-store-connect` should handle the upload directly.

## Step 7: Commit version bump

Stage and commit the version changes:
```
git add screenshot.xcodeproj/project.pbxproj
git commit -m "Bump version to <MARKETING_VERSION> (<CURRENT_PROJECT_VERSION>)"
```

## Step 8: Report

Print a summary:
- Previous version and build number
- New version and build number
- Upload status
