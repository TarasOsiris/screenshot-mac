#!/bin/zsh
# Captures the Debug build's main window (plus any sheet or popover over it) to a PNG and prints its path.
usage() {
  cat <<'EOF'
Usage: tools/capture-app.sh [--relaunch] [--app <path/to/Screenshot Bro.app>] [--allow-stale] [output.png]
  --relaunch     gracefully quit the Debug build (saves flush) and launch it again first
  --app          use this .app instead of the scheme's default DerivedData build
  --allow-stale  capture even if sources changed after the build
EOF
}
set -euo pipefail

cd "$(dirname "$0")/.."
# xcode-select points at CommandLineTools on the main dev Mac, which has no xcodebuild.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

relaunch=0 allow_stale=0 app="" out=""
while (( $# )); do
  case "$1" in
    --relaunch) relaunch=1 ;;
    --allow-stale) allow_stale=1 ;;
    --app) (( $# > 1 )) || { usage >&2; exit 2; }; shift; app="$1" ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "capture-app: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) [[ -z "$out" ]] || { echo "capture-app: more than one output path" >&2; exit 2; }; out="$1" ;;
  esac
  shift
done
out="${out:-/tmp/screenshot-bro-$(date +%Y%m%d-%H%M%S).png}"

cache="${TMPDIR:-/tmp}/screenshot-bro-capture"
mkdir -p "$cache"

if [[ -z "$app" ]]; then
  # DerivedData's path is stable per checkout, so resolve it once; -showBuildSettings takes seconds.
  products_cache="$cache/products-$(pwd | shasum -a 256 | cut -c1-16)"
  products=$(cat "$products_cache" 2>/dev/null || true)
  if [[ -z "$products" || ! -d "$products/Screenshot Bro.app" ]]; then
    if ! settings=$(xcodebuild -scheme screenshot -destination 'platform=macOS' -showBuildSettings 2>&1); then
      echo "capture-app: xcodebuild -showBuildSettings failed:" >&2
      print -r -- "$settings" | tail -5 >&2
      exit 1
    fi
    products=$(print -r -- "$settings" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -n1)
    print -r -- "$products" > "$products_cache"
  fi
  app="$products/Screenshot Bro.app"
fi
[[ -d "$app" ]] || { echo "capture-app: no build at $app — build macOS first (or pass --app)" >&2; exit 1; }

exe="$app/Contents/MacOS/Screenshot Bro"
if (( ! allow_stale )); then
  # Xcode itself rewrites the string catalog and per-user state after a build, so those never mean stale.
  newer=$(find screenshot screenshot.xcodeproj -type f ! -name .DS_Store ! -name '*.xcstrings' ! -path '*/xcuserdata/*' \
    -newer "$exe" -print -quit 2>/dev/null || true)
  if [[ -n "$newer" ]]; then
    echo "capture-app: $app is older than $newer — rebuild first (a build with another -derivedDataPath needs --app), or pass --allow-stale" >&2
    exit 1
  fi
fi

helper_src=tools/capture-app-helper.swift
helper="$cache/helper-$(shasum -a 256 "$helper_src" | cut -c1-16)"
if [[ ! -x "$helper" ]]; then
  xcrun swiftc -O -o "$helper.tmp" "$helper_src" >&2
  mv "$helper.tmp" "$helper"
fi

"$helper" "$app" "$relaunch" "$out"
