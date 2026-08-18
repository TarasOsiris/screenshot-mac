#!/bin/sh
# Runs SwiftLint over the app and test sources (paths come from .swiftlint.yml).
#
# This is not an Xcode build phase: the project sets ENABLE_USER_SCRIPT_SANDBOXING = YES, and
# the script sandbox denies SwiftLint read access to the source tree and even to
# .swiftlint.yml. Wiring it into the build would mean turning that setting off project-wide,
# so lint runs here and from the pre-commit hook instead (see tools/install-hooks.sh).
set -e

SWIFTLINT=$(command -v swiftlint || echo /opt/homebrew/bin/swiftlint)
if [ ! -x "$SWIFTLINT" ]; then
    echo "note: SwiftLint not installed — skipping lint. Install with: brew install swiftlint"
    exit 0
fi

cd "$(dirname "$0")/.."
exec "$SWIFTLINT" lint --quiet "$@"
