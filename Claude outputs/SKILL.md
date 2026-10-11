---
name: ship-direct
description: Build, notarize and publish the direct-download (Developer ID + Sparkle) macOS build — DMG to downloads.screenshotbro.app, appcast to screenshotbro.app
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

Where things are published:
- **DMGs** go to the download server, never into git: `/data/downloads/screenshotbro` on the
  Coolify host, served read-only by the Coolify service `screenshotbro-downloads` (nginx) at
  `https://downloads.screenshotbro.app/`. Uploading needs no site rebuild or redeploy.
  - `ScreenshotBro-<V>-<B>.dmg`: one file per release, cached for a year (immutable).
  - `ScreenshotBro.dmg`: a symlink to the latest release, the permanent download link
    (`no-cache`, so it always revalidates).
- **The appcast** stays in the site repo (`public/appcast.xml`). Coolify deploys it on push.
  Its enclosures point at the versioned DMG on the download server.

Shared values:
- ASC API key: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8`, key id `4KK2B86XC6`, issuer `69a6de84-a676-47e3-e053-5b8c7c11a4d1`.
- Sparkle EdDSA private key: login Keychain, account `screenshot-bro`. The public key is
  `SUPublicEDKey` in `ScreenshotBro-Direct-Info.plist`. **Never regenerate it.** Every
  installed copy would then reject all future updates.
- Sparkle tools: `SourcePackages/artifacts/sparkle/Sparkle/bin/` under this project's DerivedData.
- Site repo: `/Users/taras/repo/experiments/screnshot-mac-site`. Appcast `public/appcast.xml`.
- Download server: SSH `taras@213.130.24.18`, port **2222** (key auth only). The IP is used
  because `*.screenshotbro.app` is proxied by Cloudflare, which doesn't pass SSH.

```bash
KEY=(-authenticationKeyPath "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8" -authenticationKeyID 4KK2B86XC6 -authenticationKeyIssuerID 69a6de84-a676-47e3-e053-5b8c7c11a4d1)
NOTARY=(--key "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8" --key-id 4KK2B86XC6 --issuer 69a6de84-a676-47e3-e053-5b8c7c11a4d1)
SPARKLE=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData/screenshot-*/SourcePackages/artifacts/sparkle -name sign_update -path '*/bin/*' | head -1)")
SITE=/Users/taras/repo/experiments/screnshot-mac-site
DL_HOST=taras@213.130.24.18
DL_PORT=2222
DL_DIR=/data/downloads/screenshotbro
DL_URL=https://downloads.screenshotbro.app
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
DMG="ScreenshotBro-$V-$B.dmg"
rm -rf build/dmg && mkdir build/dmg && cp -R "build/direct/Screenshot Bro.app" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "Screenshot Bro" -srcfolder build/dmg -format UDZO -ov "build/direct/$DMG"
# Sign the DMG only if a local "Developer ID Application" identity exists (security find-identity -v -p codesigning)
xcrun notarytool submit "build/direct/$DMG" "${NOTARY[@]}" --wait
xcrun stapler staple "build/direct/$DMG"
```
Staple **before** anything below. Stapling changes the bytes, and the Sparkle signature and the
uploaded file must both be of the final, stapled DMG.

## 5. Update the appcast (locally — don't push yet)
```bash
mkdir -p build/appcast && cp "$SITE/public/appcast.xml" build/appcast/ 2>/dev/null; cp "build/direct/$DMG" build/appcast/
"$SPARKLE/generate_appcast" --account screenshot-bro --download-url-prefix "$DL_URL/" \
  --link https://screenshotbro.app --maximum-deltas 0 build/appcast
```
`generate_appcast` signs the new item with the Keychain key and keeps the existing items.
Check the new `<item>`:
- `sparkle:version` = `$B`, `sparkle:shortVersionString` = `$V`, and an `sparkle:edSignature` are present.
- The enclosure `url` is `https://downloads.screenshotbro.app/ScreenshotBro-$V-$B.dmg`, the
  **versioned** file. Never point it at `ScreenshotBro.dmg`: that name changes on every release,
  so a Sparkle signature over it goes stale.

Older items may still point at `https://screenshotbro.app/releases/…`. Leave them alone, since
Sparkle only installs the newest item.

## 6. Upload dSYMs to Sentry
```bash
sentry-cli debug-files upload -o nineva-studios -p screenshot-bro build/screenshot-direct.xcarchive
```
The release name is the same as the App Store one (`xyz.tleskiv.screenshot@V+B`), so `/ship`'s
Sentry release already covers it. Crashes are told apart by the `distribution` tag.

## 7. Upload the DMG to the download server
Upload under a `.new` name. nginx returns 404 for `*.new`, so nobody can download a partial file.
```bash
scp -P "$DL_PORT" "build/direct/$DMG" "$DL_HOST:$DL_DIR/$DMG.new"
```
If the upload is interrupted, just run it again; it overwrites the `.new` file.

## 8. Publish atomically
`mv` within the same folder is an atomic rename. The symlink is swapped the same way
(`ln` to a temp name, then `mv -T`), so `ScreenshotBro.dmg` always points at a complete file.
```bash
ssh -p "$DL_PORT" "$DL_HOST" "set -e; cd '$DL_DIR'
  test ! -e '$DMG' || { echo '$DMG already published, refusing to overwrite'; exit 1; }
  chmod 644 '$DMG.new'
  mv '$DMG.new' '$DMG'
  ln -sfn '$DMG' .latest.tmp
  mv -T .latest.tmp ScreenshotBro.dmg
  ls -la"
```
- `chmod 644` is required: `scp` keeps the local mode (often `600`), and nginx runs as another
  user, so it would answer 403.
- The refuse-to-overwrite guard exists because versioned files are cached by Cloudflare for a year.
  Replacing one in place would serve stale bytes that fail the Sparkle signature. If a build has to
  be redone, bump `CURRENT_PROJECT_VERSION` and ship it under a new name.

## 9. Verify the download before announcing it
```bash
LOCAL=$(shasum -a 256 "build/direct/$DMG" | cut -d' ' -f1)
VERS=$(curl -fsS "$DL_URL/$DMG" | shasum -a 256 | cut -d' ' -f1)
LATEST=$(curl -fsS "$DL_URL/ScreenshotBro.dmg" | shasum -a 256 | cut -d' ' -f1)
echo "local=$LOCAL"; echo "vers =$VERS"; echo "latest=$LATEST"
[ "$LOCAL" = "$VERS" ] && [ "$LOCAL" = "$LATEST" ] && echo OK || echo MISMATCH
curl -sSI "$DL_URL/ScreenshotBro.dmg" | grep -iE '^(HTTP|content-length|content-type|cache-control)'
```
All three hashes must match, and the response must be `HTTP/2 200` with
`content-type: application/x-apple-diskimage`. **Stop on a mismatch.** Don't push the appcast,
or Sparkle will offer an update whose signature fails.

## 10. Publish the appcast
Only now, with the DMG verified, ship the appcast:
```bash
cp build/appcast/appcast.xml "$SITE/public/appcast.xml"
git -C "$SITE" add public/appcast.xml
git -C "$SITE" commit -m "Appcast: direct-download build $V ($B)"
git -C "$SITE" push
```
Coolify deploys the site on push. Don't copy DMGs into `$SITE/public/releases/` any more.
After the deploy, check that the live appcast lists the new item:
```bash
curl -fsS https://screenshotbro.app/appcast.xml | grep -c "ScreenshotBro-$V-$B.dmg"   # must be ≥ 1
```

## 11. Prune old DMGs (optional)
Keep the current and the previous release; Sparkle only needs the newest. List what's there and
remove older versioned files by hand:
```bash
ssh -p "$DL_PORT" "$DL_HOST" "ls -la '$DL_DIR'"
ssh -p "$DL_PORT" "$DL_HOST" "rm '$DL_DIR/ScreenshotBro-<old V>-<old B>.dmg'"
```
Never delete the file `ScreenshotBro.dmg` currently points to, and never delete `healthcheck.txt`.

## 12. Report
Give the version, the notarization ids, the DMG size and SHA-256, and the appcast item. Remind the
user to smoke-test: download `https://downloads.screenshotbro.app/ScreenshotBro.dmg` on a clean
account, open it (Gatekeeper must not complain), then use **Check for Updates…** from the
previous version.

## Rollback
To point the permanent link back at the previous build (the file must still be on the server):
```bash
ssh -p "$DL_PORT" "$DL_HOST" "cd '$DL_DIR' && ln -sfn 'ScreenshotBro-<prev V>-<prev B>.dmg' .latest.tmp && mv -T .latest.tmp ScreenshotBro.dmg"
```
Sparkle can't downgrade. To stop an update from spreading, revert the appcast commit in the
site repo and push.
