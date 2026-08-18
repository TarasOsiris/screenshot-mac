#!/bin/sh
# Installs the repo's git hooks. Run once per clone:  ./tools/install-hooks.sh
set -e

cd "$(dirname "$0")/.."
HOOKS=$(git rev-parse --git-path hooks)

cat > "$HOOKS/pre-commit" <<'HOOK'
#!/bin/sh
# Lints only the Swift files in this commit.
#
# Deliberately scoped: the tree still carries a few hundred warnings (mostly force_unwrapping),
# and printing all of them on every commit would train everyone to ignore the hook. Errors in
# touched files block; warnings in touched files are shown. `git commit --no-verify` bypasses.
set -e
ROOT=$(git rev-parse --show-toplevel)

SWIFTLINT=$(command -v swiftlint || echo /opt/homebrew/bin/swiftlint)
[ -x "$SWIFTLINT" ] || exit 0

FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)
[ -n "$FILES" ] || exit 0

cd "$ROOT"
OUTPUT=$(echo "$FILES" | xargs "$SWIFTLINT" lint --quiet --force-exclude 2>/dev/null || true)
[ -n "$OUTPUT" ] || exit 0

echo "$OUTPUT"
if echo "$OUTPUT" | grep -q ": error:"; then
    echo
    echo "SwiftLint errors in staged files — commit blocked (use --no-verify to override)."
    exit 1
fi
HOOK

chmod +x "$HOOKS/pre-commit"
echo "installed pre-commit hook -> $HOOKS/pre-commit"
