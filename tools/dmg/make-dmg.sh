#!/bin/bash
# Builds the styled drag-to-Applications DMG: tools/dmg/make-dmg.sh <path/to/App.app> <out.dmg>
# Finder lays the window out (background, icon positions), so this needs a GUI session and
# Automation permission for the calling terminal to control Finder.
set -euo pipefail

APP="${1:?usage: make-dmg.sh <App.app> <out.dmg>}"
OUT="${2:?usage: make-dmg.sh <App.app> <out.dmg>}"
VOLNAME="Screenshot Bro"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="$(basename "$APP")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Finder addresses the volume by name, so an already-mounted copy would be styled instead.
if [ -d "/Volumes/$VOLNAME" ]; then
  echo "Ejecting the mounted '$VOLNAME' volume first"
  hdiutil detach "/Volumes/$VOLNAME" -quiet || hdiutil detach "/Volumes/$VOLNAME" -force -quiet
fi

mkdir -p "$WORK/stage/.background"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
swift "$HERE/make-background.swift" "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/stage/.background/background.tiff" >/dev/null 2>&1

hdiutil create -volname "$VOLNAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" -quiet
hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen -quiet
MOUNT="/Volumes/$VOLNAME"

# Coordinates match make-background.swift: 640×400 content, icon centres at (170,200) and (470,200).
osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
echo "$OUT"
