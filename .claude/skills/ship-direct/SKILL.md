---
name: ship-direct
description: Build, notarize and publish the direct-download (Developer ID + Sparkle) macOS build to screenshotbro.app
disable-model-invocation: true
---

# Ship the direct-download build

The `screenshot Direct` target is the copy sold outside the Mac App Store. It is signed with
Developer ID, updates through Sparkle, and sells Pro through a RevenueCat Web Purchase Link
(Stripe). Pro unlocks through a redemption link on the `rc-6cc0af703b://` scheme. It shares the
bundle id, iCloud container and version numbers with the App Store build.

Run this **after** `/ship`, so the version is already bumped, tagged and pushed. Don't bump
versions here. If you run it standalone, read `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
from the `screenshot Direct` target in `project.xcproj`.

Shared values:
- ASC API key: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8`, key id `4KK2B86XC6`, issuer `69a6de84-a676-47e3-e053-5b8c7c11a4d1`.
- Sparkle EdDSA private key: login Keychain, account `screenshot-bro`. The public key is
  `SUPublicEDKey` in `ScreenshotBro-Direct-Info.plist`. **Never regenerate it.** Every
  installed copy would then reject all future updates.
- Sparkle tools: `SourcePackages/artifacts/sparkle/Sparkle/bin/` under this project's DerivedData.
- Site repo: `/Users/taras/repo/experiments/screnshot-mac-site`. `public/appcast.xml` is the input to step 5. DMGs are **never** committed: they go to `~/Desktop`.

```bash
KEY=(-authenticationKeyPath "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8" -authenticationKeyID 4KK2B86XC6 -authenticationKeyIssuerID 69a6de84-a676-47e3-e053-5b8c7c11a4d1)
NOTARY=(--key "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8" --key-id 4KK2B86XC6 --issuer 69a6de84-a676-47e3-e053-5b8c7c11a4d1)
SPARKLE=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData/screenshot-*/SourcePackages/artifacts/sparkle -name sign_update -path '*/bin/*' | head -1)")
SITE=/Users/taras/repo/experiments/screnshot-mac-site
```

## 1. Archive (universal, so Intel Macs can run it too)
```bash
xcodebuild -project screenshot.xcodeproj -scheme "screenshot Direct" -destination 'generic/platform=macOS' \
  -archivePath build/screenshot-direct.xcarchive -allowProvisioningUpdates "${KEY[@]}" archive
```

## 2. Export with Developer ID
```bash
xcodebuild -exportArchive -archivePath build/screenshot-direct.xcarchive -exportPath build/direct \
  -exportOptionsPlist ExportOptions-Direct.plist -allowProvisioningUpdates "${KEY[@]}"
mv "build/direct/Screenshot Bro Direct.app" "build/direct/Screenshot Bro.app"
```
Export signs **manually**: the "Developer ID Application: Taras Leskiv" identity in the login
Keychain, plus the `Screenshot Bro Developer ID` profile (`MAC_APP_DIRECT`, ASC id `YWP82Y5YX2`).
Automatic signing can't make that profile with this API key, and the iCloud and keychain entitlements need it. The
profile expires with the certificate on 2027-02-01. To renew: create a new Developer ID
certificate in Xcode, then run `asc profiles create --profile-type MAC_APP_DIRECT --bundle D84N5TYZ2V --certificate <cert id>`,
then download the profile into `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`.

The product is named `Screenshot Bro Direct` so it never collides with the App Store build in
DerivedData. Renaming the bundle folder doesn't break the signature, and `CFBundleName` is
already "Screenshot Bro".

Check that the entitlements survived. The iCloud keys and the `-spks`/`-spki` mach-lookup exceptions must be present:
```bash
codesign -d --entitlements - "build/direct/Screenshot Bro.app"
```

## 3. Notarize and staple the app
```bash
ditto -c -k --keepParent "build/direct/Screenshot Bro.app" build/direct/notarize.zip
xcrun notarytool submit build/direct/notarize.zip "${NOTARY[@]}" --wait
xcrun stapler staple "build/direct/Screenshot Bro.app"
spctl -a -vv "build/direct/Screenshot Bro.app"   # must say: source=Notarized Developer ID
```
If notarization reports `Invalid`, fetch the reason with `xcrun notarytool log <id> "${NOTARY[@]}"` and stop.

## 4. Build the DMG, then notarize and staple it
```bash
V=<MARKETING_VERSION>; B=<CURRENT_PROJECT_VERSION>
rm -rf build/dmg && mkdir build/dmg && cp -R "build/direct/Screenshot Bro.app" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "Screenshot Bro" -srcfolder build/dmg -format UDZO -ov "build/direct/ScreenshotBro-$V-$B.dmg"
codesign -s "Developer ID Application: Taras Leskiv (XW3GM347XY)" --timestamp "build/direct/ScreenshotBro-$V-$B.dmg"
xcrun notarytool submit "build/direct/ScreenshotBro-$V-$B.dmg" "${NOTARY[@]}" --wait
xcrun stapler staple "build/direct/ScreenshotBro-$V-$B.dmg"
```

## 5. Update the appcast
```bash
mkdir -p build/appcast && cp "$SITE/public/appcast.xml" build/appcast/ 2>/dev/null; cp "build/direct/ScreenshotBro-$V-$B.dmg" build/appcast/
"$SPARKLE/generate_appcast" --account screenshot-bro --download-url-prefix https://screenshotbro.app/releases/ \
  --link https://screenshotbro.app --maximum-deltas 0 build/appcast
```
`generate_appcast` signs the new item with the Keychain key and keeps the existing items.
Check that the new `<item>` has `sparkle:version` = `$B`, `sparkle:shortVersionString` = `$V` and an `sparkle:edSignature`.

## 6. Upload dSYMs to Sentry
```bash
sentry-cli debug-files upload -o nineva-studios -p screenshot-bro build/screenshot-direct.xcarchive
```
The release name is the same as the App Store one (`xyz.tleskiv.screenshot@V+B`), so `/ship`'s
Sentry release already covers it. Crashes are told apart by the `distribution` tag.

## 7. Hand off the DMG — never commit it
```bash
cp "build/direct/ScreenshotBro-$V-$B.dmg" ~/Desktop/
cp build/appcast/appcast.xml ~/Desktop/appcast-$V-$B.xml
```
**Never commit or push a DMG to any git repo.** The site's `.gitignore` excludes them. The user
uploads the DMG to `https://screenshotbro.app/releases/` themselves. Leave the appcast on the
Desktop too, and don't commit `public/appcast.xml` unless the user asks. An appcast that
points at a DMG which isn't uploaded yet breaks Sparkle updates.

## 8. Report
Give the version, the notarization ids, the DMG size, and the appcast item. Remind the user to
smoke-test: download from `/download` on a clean account, open it (Gatekeeper must not
complain), then use **Check for Updates…**.
