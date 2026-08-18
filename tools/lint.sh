#!/bin/sh
# Runs SwiftLint over the app *and* test sources (paths come from .swiftlint.yml).
#
# The same check runs as a Debug-only Xcode build phase, except that the phase drops
# /screenshotTests/ from its output so the suite's ~300 force-unwrap warnings don't drown the
# app's handful. This script is the by-hand entry point and covers both; so does the pre-commit
# hook (see tools/install-hooks.sh).
#
# The build phase is also why ENABLE_USER_SCRIPT_SANDBOXING is NO: the script sandbox otherwise
# denies SwiftLint read access to the source tree and to .swiftlint.yml itself.
#
# Needs a full Xcode, not the Command Line Tools: SwiftLint loads sourcekitdInProc from the
# active developer dir and dies with "Loading sourcekitdInProc.framework failed" without it.
# Either `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` or prefix with
# DEVELOPER_DIR=. Xcode sets it for the build phase, so only CLI runs hit this.
set -e

SWIFTLINT=$(command -v swiftlint || echo /opt/homebrew/bin/swiftlint)
if [ ! -x "$SWIFTLINT" ]; then
    echo "note: SwiftLint not installed — skipping lint. Install with: brew install swiftlint"
    exit 0
fi

cd "$(dirname "$0")/.."
exec "$SWIFTLINT" lint --quiet "$@"
