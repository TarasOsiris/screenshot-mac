#!/bin/bash
# Stop hook: after a Swift change, send the agent through /code-review high --fix and /simplify once.
#   review-gate.sh         hook mode (reads hook JSON on stdin)
#   review-gate.sh --mark  record the current Swift diff as reviewed
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

MIN_LINES=20
MARKER=.claude/state/reviewed-diff-hash
PATHS=(screenshot screenshotTests)

untracked() { git ls-files --others --exclude-standard -- "${PATHS[@]}" | grep '\.swift$' || true; }

diff_hash() {
  {
    git diff HEAD -- "${PATHS[@]/%//*.swift}"
    untracked | while read -r f; do echo "+++ $f"; cat "$f"; done
  } | shasum | cut -d' ' -f1
}

changed_lines() {
  local tracked new
  tracked=$(git diff HEAD --numstat -- "${PATHS[@]/%//*.swift}" | awk '{n += $1 + $2} END {print n + 0}')
  new=$(untracked | while read -r f; do cat "$f"; done | wc -l | tr -d ' ')
  echo $((tracked + new))
}

if [[ "${1:-}" == "--mark" ]]; then
  mkdir -p "$(dirname "$MARKER")"
  diff_hash > "$MARKER"
  echo "Marked current Swift diff as reviewed."
  exit 0
fi

cat > /dev/null

[[ $(changed_lines) -ge $MIN_LINES ]] || exit 0
[[ -f "$MARKER" && "$(cat "$MARKER")" == "$(diff_hash)" ]] && exit 0

jq -n --arg reason "Swift changes in this turn haven't been through review yet. Unless the user asked to skip review, do this before finishing: 1) run the code-review skill with args \"high --fix\" and make sure every confirmed finding is fixed; 2) then run the simplify skill; 3) rebuild macOS with xcodebuild (and the iOS Simulator build if anything platform-conditional changed) and fix any errors; 4) finally run .claude/hooks/review-gate.sh --mark. If those skills aren't available in this harness, review the diff yourself for bugs, then for simplifications, before marking. If the user asked to skip review, or the change isn't a feature (e.g. pure revert), just run the mark command." \
  '{decision: "block", reason: $reason}'
