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
`screenshot Direct` target in `project.xcproj`, and before archiving confirm the file isn't on
the server with `ssh -p "$DL_PORT" "$DL_HOST" "test ! -e '$DL_DIR/ScreenshotBro-$V-$B.dmg'"`.
**Never `curl` a versioned URL before step 7b**: Cloudflare caches the 404 under the immutable
one-year header, and that edge then serves 404 after the upload (4.19 (154) hit this).

Shared values:
- ASC API key: `$HOME/Library/Mobile Documents/com~apple~CloudDocs/Files/AuthKey_4KK2B86XC6_BRO.p8`, key id `4KK2B86XC6`, issuer `69a6de84-a676-47e3-e053-5b8c7c11a4d1`.
- Sparkle EdDSA private key: login Keychain, account `screenshot-bro`. The public key is
  `SUPublicEDKey` in `ScreenshotBro-Direct-Info.plist`. A backup is in 1Password (account my.1password.com, vault Personal, item "Sparkle EdDSA key — Screenshot Bro (direct download)"). On a new Mac, restore it with `generate_keys --account screenshot-bro -f <file>`. **Never regenerate it.** Every
  installed copy would then reject all future updates.
- Sparkle tools: `SourcePackages/artifacts/sparkle/Sparkle/bin/` under this project's DerivedData.
- Site repo: `TarasOsiris/screenshot-bro-site`, checked out at a different path on each Mac, so `$SITE` below
  finds it by its remote instead of a fixed path. If it finds nothing, ask where the clone is rather than
  guessing. `git pull` it before step 5. `public/appcast.xml` is the input to step 5 and the output of
  step 7d; Coolify deploys it on push. DMGs are **never** committed to any repo.
- Signing certificate: `$CERT` below is the SHA-1 of the Developer ID certificate that is **both** in this
  Mac's keychain **and** in the `Screenshot Bro Developer ID` profile. Never sign by name. A Mac can hold
  several "Developer ID Application: Taras Leskiv" identities (Xcode can create another one during an
  archive with `-allowProvisioningUpdates`), and then the name is ambiguous: export picks one the profile
  doesn't list ("doesn't include signing certificate"), and `codesign -s <name>` refuses to choose. If
  `$CERT` is empty, this Mac is missing the private key or the profile (see step 2), so stop.
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
SITE=$(for d in "$PWD/../screenshot-bro-site" "$HOME/Documents/repo/experiments/screenshot-bro-site" \
  "$HOME/repo/experiments/screenshot-bro-site" "$HOME/repo/experiments/screnshot-mac-site"; do
  git -C "$d" remote get-url origin 2>/dev/null | grep -q 'TarasOsiris/screenshot-bro-site' && { (cd "$d" && pwd -P); break; }
done)
CERT=$(for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.provisionprofile; do
  p=$(security cms -D -i "$f" 2>/dev/null) || continue
  [ "$(plutil -extract Name raw - <<<"$p")" = "Screenshot Bro Developer ID" ] || continue
  n=$(plutil -extract DeveloperCertificates raw - <<<"$p")
  for i in $(seq 0 $((n - 1))); do
    plutil -extract "DeveloperCertificates.$i" raw - <<<"$p" | base64 -d | shasum -a 1 | cut -d' ' -f1 | tr a-f A-F
  done
done | grep -xF -f <(security find-identity -v -p codesigning | awk '/"Developer ID Application/ {print $2}') | head -1)
echo "SITE=$SITE CERT=$CERT"   # both must be non-empty
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
cp ExportOptions-Direct.plist build/ExportOptions-Direct.plist
plutil -replace signingCertificate -string "$CERT" build/ExportOptions-Direct.plist
xcodebuild -exportArchive -archivePath build/screenshot-direct.xcarchive -exportPath build/direct \
  -exportOptionsPlist build/ExportOptions-Direct.plist -allowProvisioningUpdates "${KEY[@]}"
mv "build/direct/Screenshot Bro Direct.app" "build/direct/Screenshot Bro.app"
```
Export signs **manually**: the `$CERT` identity in the login Keychain (the committed plist names
the certificate generically; the `build/` copy pins it for this Mac), plus the `Screenshot Bro Developer ID` profile (`MAC_APP_DIRECT`, ASC id `YWP82Y5YX2`).
Automatic signing can't make that profile with this API key, and the iCloud and keychain entitlements need it. The
profile expires with the certificate on 2027-02-01. To renew: create a new Developer ID
certificate in Xcode, then run `asc profiles create --profile-type MAC_APP_DIRECT --bundle D84N5TYZ2V --certificate <cert id>`,
then download the profile into `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`
on **every** Mac that ships. A Mac needs the certificate's private key too: export it from Keychain Access
as a .p12 on a Mac that has it, and import it on the other.

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
./tools/dmg/make-dmg.sh "build/direct/Screenshot Bro.app" "build/direct/$DMG"
codesign -s "$CERT" --timestamp "build/direct/$DMG"
xcrun notarytool submit "build/direct/$DMG" "${NOTARY[@]}" --wait
xcrun stapler staple "build/direct/$DMG"
```
`make-dmg.sh` lays out the drag-to-Applications window (background from `tools/dmg/make-background.swift`,
icon positions) by scripting Finder, so it needs a GUI session and Automation access to Finder for the
terminal; it ejects any mounted "Screenshot Bro" volume first. Open the result once and check the window
before signing.

### 4b. Send the DMG to Telegram
As soon as the stapled DMG exists, send it to the user's Telegram chat, if the helper is set up on
this Mac:
```bash
TG_DOC="$HOME/.claude/hooks/tg_document.py"
DMG_SENT=no
if [ -x "$TG_DOC" ]; then
  "$TG_DOC" "build/direct/$DMG" "<b>Screenshot Bro $V ($B)</b> — direct-download DMG (notarized, not yet published)" \
    && DMG_SENT=yes
fi
```
- The helper prints `sent`, or exits **2** with `too large` because the Bot API caps uploads at
  50 MB, which the DMG is usually just over. In that case step 7c sends the download link instead.
- Any other failure (no helper, no credentials, network) is a warning, never a stop. Telegram is a
  convenience, not part of the release.

## 5. Update the appcast
```bash
mkdir -p build/appcast && cp "$SITE/public/appcast.xml" build/appcast/ 2>/dev/null; cp "build/direct/$DMG" build/appcast/
"$SPARKLE/generate_appcast" --account screenshot-bro --download-url-prefix "$DL_URL/" \
  --link https://screenshotbro.app --maximum-deltas 0 build/appcast
grep -q "url=\"$DL_URL/$DMG\"" build/appcast/appcast.xml && echo "enclosure OK" || echo "ENCLOSURE WRONG — stop"
```
`generate_appcast` signs the new item with the Keychain key. It keeps only the newest few items and
drops older ones, which is harmless: Sparkle only offers the newest.
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

If step 4b couldn't attach the DMG (`DMG_SENT=no`), send the verified link now. Skip this if the
helper isn't set up on this Mac:
```bash
[ "$DMG_SENT" = yes ] || [ ! -x "$HOME/.claude/hooks/tg_message.py" ] || "$HOME/.claude/hooks/tg_message.py" <<MSG
<b>Screenshot Bro $V ($B)</b> — direct-download DMG ($(du -h "build/direct/$DMG" | cut -f1 | tr -d ' '), too big to attach)
$DL_URL/$DMG
MSG
```

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
