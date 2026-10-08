#!/bin/bash
# UserPromptSubmit hook: fast-forward the current branch to its upstream before any work starts.
# Never blocks the prompt; anything it can't do safely is reported to the agent via stdout.

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

git_dir=$(git rev-parse --git-dir)
if [ -e "$git_dir/MERGE_HEAD" ] || [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
  exit 0
fi

branch=$(git symbolic-ref --quiet --short HEAD) || exit 0
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || exit 0

# A hook has no terminal: fail fast instead of hanging on a credential or passphrase prompt.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

if ! fetch_err=$(git fetch --quiet "${upstream%%/*}" 2>&1); then
  echo "git-pull hook: could not fetch $upstream, working on possibly stale $branch. ${fetch_err}"
  exit 0
fi

behind=$(git rev-list --count "HEAD..@{u}")
[ "$behind" -eq 0 ] && exit 0
ahead=$(git rev-list --count "@{u}..HEAD")

if [ "$ahead" -gt 0 ]; then
  echo "git-pull hook: $branch has diverged from $upstream ($ahead local, $behind remote commits). Not pulled — rebase or merge before relying on the tree."
  exit 0
fi

# --ff-only refuses on its own if an incoming change would overwrite an uncommitted edit.
if merge_out=$(git merge --ff-only --quiet "@{u}" 2>&1); then
  echo "git-pull hook: fast-forwarded $branch by $behind commit(s) from $upstream:"
  git log --oneline -n "$behind" | head -20
else
  echo "git-pull hook: $branch is $behind commit(s) behind $upstream but could not fast-forward (uncommitted changes conflict). ${merge_out}"
fi
exit 0
