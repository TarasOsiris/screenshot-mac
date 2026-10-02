---
name: ship-direct
description: Run /ship first, then build, notarize and publish the direct-download (Developer ID + Sparkle) macOS build — DMG to downloads.screenshotbro.app, appcast to screenshotbro.app
disable-model-invocation: true
---

# Ship the direct-download build

The `screenshot Direct` target is the copy sold outside the Mac App Store. It is signed with
Developer ID, updates through Sparkle, and sells Pro through a RevenueCat Web Purchase Link
(Stripe). Pro unlocks through a redemption link on the `rc-6cc0af703b://` scheme. It shares the
bundle id, iCloud container and version numbers with the App Store build.

**Always run the `ship` skill first, every time, as step 0** — invoking `/ship-direct` means
"ship both". `ship` bumps, tags and pushes the version; this skill then builds that same version.
Never skip it because the current version "looks unshipped": the other machine may already have
published it, and a published versioned DMG can never be overwritten. Don't bump versions here —
after `ship` finishes, read `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from the
`screenshot Direct` target in `project.xcproj`, and before archiving confirm
`$DL_URL/ScreenshotBro-$V-$B.dmg` returns 404.

Shared values:
- ASC API key: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8`, key id `4KK2B86XC6`, issuer `69a6de84-a676-47e3-e053-5b8c7c11a4d1`.
- Sparkle EdDSA private key: login Keychain, account `screenshot-bro`. The public key is
  `SUPublicEDKey` in `ScreenshotBro-Direct-Info.plist`. A backup is in 1Password (account my.1password.com, vault Personal, item "Sparkle EdDSA key — Screenshot Bro (direct download)"). On a new Mac, restore it with `generate_keys --account screenshot-bro -f <file>`. **Never regenerate it.** Every
  installed copy would then reject all future updates.
- Sparkle tools: `SourcePackages/artifacts/sparkle/Sparkle/bin/` under this project's DerivedData.
- Site repo: `/Users/taras/repo/experiments/screnshot-mac-site`. `public/appcast.xml` is the input to step 5 and the output of step 7d; Coolify deploys it on push. DMGs are **never** committed to any repo.
- Download server: the Coolify service `screenshotbro-downloads` (nginx:alpine) serves the host folder
  `/data/downloads/screenshotbro` read-only at https://downloads.screenshotbro.app/. Uploading needs no
  site rebuild or redeploy. Reach it over SSH/scp at `taras@213.130.24.18`, port 2222, key auth only.
  Use the IP: `*.screenshotbro.app` is proxied by Cloudflare, which doesn't pass SSH. Note `scp -P`, but `ssh -p`.
  - `ScreenshotBro-<V>-<B>.dmg`: one file per release, served `Cache-Control: public, max-age=31536000, immutable`.
  - `ScreenshotBro.dmg`: symlink to the latest versioned file, the permanent public download link, served `no-cache`.
  - `healthcheck.txt`: leave it alone.
  - nginx returns 404 for `*.new`, `*.part`, `*.tmp` and dotfiles, which is what makes upload-then-rename safe.

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
DMG="ScreenshotBro-$V-$B.dmg"
rm -rf build/dmg && mkdir build/dmg && cp -R "build/direct/Screenshot Bro.app" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "Screenshot Bro" -srcfolder build/dmg -format UDZO -ov "build/direct/$DMG"
codesign -s "Developer ID Application: Taras Leskiv (XW3GM347XY)" --timestamp "build/direct/$DMG"
xcrun notarytool submit "build/direct/$DMG" "${NOTARY[@]}" --wait
xcrun stapler staple "build/direct/$DMG"
```

## 5. Update the appcast
```bash
mkdir -p build/appcast && cp "$SITE/public/appcast.xml" build/appcast/ 2>/dev/null; cp "build/direct/$DMG" build/appcast/
"$SPARKLE/generate_appcast" --account screenshot-bro --download-url-prefix "$DL_URL/" \
  --link https://screenshotbro.app --maximum-deltas 0 build/appcast
grep -q "url=\"$DL_URL/$DMG\"" build/appcast/appcast.xml && echo "enclosure OK" || echo "ENCLOSURE WRONG — stop"
```
`generate_appcast` signs the new item with the Keychain key and keeps the existing items.
Check that the new `<item>` has `sparkle:version` = `$B`, `sparkle:shortVersionString` = `$V` and an `sparkle:edSignature`.
Its enclosure url must be `https://downloads.screenshotbro.app/ScreenshotBro-$V-$B.dmg`: the
**versioned** file, never `ScreenshotBro.dmg`, because the Sparkle signature has to cover bytes that
never change. Older items that point at `https://screenshotbro.app/releases/…` can stay as they are.
Generate the appcast locally only. **Don't push it in this step**: it goes live in step 7d, once the DMG is verified on the server.

## 6. Upload dSYMs to Sentry
```bash
sentry-cli debug-files upload -o nineva-studios -p screenshot-bro build/screenshot-direct.xcarchive
```
The release name is the same as the App Store one (`xyz.tleskiv.screenshot@V+B`), so `/ship`'s
Sentry release already covers it. Crashes are told apart by the `distribution` tag.

## 7. Publish the DMG to the download server, then the appcast

Run these in this exact order. Nothing may point at the DMG until 7c has verified it.

### 7a. Upload under a temporary name
```bash
scp -P "$DL_PORT" "build/direct/$DMG" "$DL_HOST:$DL_DIR/$DMG.new"
```
nginx won't serve `*.new`, so a half-uploaded file is never public. If the upload is interrupted,
re-running it just overwrites the `.new` file.

### 7b. Publish atomically
```bash
ssh -p "$DL_PORT" "$DL_HOST" "set -e; cd '$DL_DIR'
  test ! -e '$DMG' || { echo '$DMG already published, refusing to overwrite'; exit 1; }
  chmod 644 '$DMG.new'
  mv '$DMG.new' '$DMG'
  ln -sfn '$DMG' .latest.tmp
  mv -T .latest.tmp ScreenshotBro.dmg
  ls -la"
```
- `chmod 644` is required. scp keeps the local mode (often 600), and nginx runs as a different
  user, so without it the download returns 403.
- Never overwrite a published versioned file. Cloudflare caches it for a year, so a redone build
  must get a new `CURRENT_PROJECT_VERSION`, never a re-upload under the same name.
- `mv`, and `mv -T` of the symlink, are atomic renames, so users never download a partial file.

### 7c. Verify before anything points at it
```bash
LOCAL=$(shasum -a 256 "build/direct/$DMG" | cut -d' ' -f1)
VERS=$(curl -fsS "$DL_URL/$DMG" | shasum -a 256 | cut -d' ' -f1)
LATEST=$(curl -fsS "$DL_URL/ScreenshotBro.dmg" | shasum -a 256 | cut -d' ' -f1)
echo "$LOCAL $VERS $LATEST"
curl -sSI "$DL_URL/ScreenshotBro.dmg"   # HTTP 200, content-type: application/x-apple-diskimage
```
All three hashes must match, and the HEAD request must return HTTP 200 with
`content-type: application/x-apple-diskimage`. On any mismatch, **stop and don't push the appcast**.

### 7d. Only then, publish the appcast
```bash
cp build/appcast/appcast.xml "$SITE/public/appcast.xml"
git -C "$SITE" add public/appcast.xml
git -C "$SITE" commit -m "Appcast: direct-download build $V ($B)" -- public/appcast.xml
git -C "$SITE" push
```
Commit only `public/appcast.xml`. Coolify deploys the site on push. After it has deployed, confirm:
```bash
curl -fsS https://screenshotbro.app/appcast.xml | grep -c "ScreenshotBro-$V-$B.dmg"   # must be ≥ 1
```
**Never copy DMGs into `$SITE/public/releases` again**, and never commit a DMG to any git repo.

### 7e. Prune old DMGs (optional)
Keep the current and the previous release on the server. List what's there:
```bash
ssh -p "$DL_PORT" "$DL_HOST" "ls -la '$DL_DIR'"
```
Delete older versioned files one at a time (`ssh -p "$DL_PORT" "$DL_HOST" "rm '$DL_DIR/ScreenshotBro-<old V>-<old B>.dmg'"`).
Never delete the target of `ScreenshotBro.dmg`, and never delete `healthcheck.txt`.

## Rollback
Point the permanent link back at the previous release:
```bash
ssh -p "$DL_PORT" "$DL_HOST" "cd '$DL_DIR' && ln -sfn 'ScreenshotBro-<prev V>-<prev B>.dmg' .latest.tmp && mv -T .latest.tmp ScreenshotBro.dmg"
```
Sparkle can't downgrade, so that only fixes new downloads. To stop an update from spreading to
installed copies, revert the appcast commit in the site repo and push.

## 8. Report
Give the version, the notarization ids, the DMG size and SHA-256, and the appcast item. Remind the
user to smoke-test: download https://downloads.screenshotbro.app/ScreenshotBro.dmg on a clean
account, open it (Gatekeeper must accept it), then run **Check for Updates…** from the previous version.
