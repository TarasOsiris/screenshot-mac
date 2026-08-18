#!/bin/sh
# Runs SwiftLint if it is installed. Absent SwiftLint is not an error: the project builds
# without it, and this script is wired into the app target's build phases.
set -e

if command -v swiftlint >/dev/null 2>&1; then
    exec swiftlint lint --quiet "$@"
fi

if [ -x /opt/homebrew/bin/swiftlint ]; then
    exec /opt/homebrew/bin/swiftlint lint --quiet "$@"
fi

echo "note: SwiftLint not installed — skipping lint. Install with: brew install swiftlint"
