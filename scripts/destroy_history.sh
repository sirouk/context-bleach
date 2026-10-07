#!/usr/bin/env bash
# destroy_history.sh - step 6 of context-bleach: leave only the `reset` branch, with nothing
# of the old history left in the object store, linked worktrees, or .git/config.
#
# Run it from the project root, on branch `reset`, AFTER the single orphan commit exists.
# It refuses to run otherwise. It never touches a remote and never pushes or fetches.
# It deletes linked worktrees (folder and all), every ref except refs/heads/reset, stashes,
# branch sections in .git/config, ORIG_HEAD/FETCH_HEAD, reflogs, and unreachable objects.
set -euo pipefail

top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "REFUSED: not in a git repository" >&2; exit 2; }
cd "$top"
git_dir="$(git rev-parse --absolute-git-dir)"

branch="$(git symbolic-ref -q --short HEAD || true)"
[ "$branch" = "reset" ] || { echo "REFUSED: current branch is '${branch:-detached}', not reset" >&2; exit 2; }
[ "$(git rev-list --count reset)" = "1" ] || { echo "REFUSED: reset must be exactly one (orphan) commit first" >&2; exit 2; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "REFUSED: tracked files have uncommitted changes" >&2; exit 2; }

# 1. linked worktrees: remove folder and record
git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r w; do
  [ "$(cd "$w" 2>/dev/null && pwd -P || echo "$w")" = "$(pwd -P)" ] && continue
  git worktree remove --force --force "$w" 2>/dev/null || rm -rf "$w"
done
git worktree prune
rm -rf "$git_dir/worktrees"

# 2. every ref except reset (branches, tags, notes, remote-tracking, stash, anything else)
git for-each-ref --format='%(refname)' | grep -vx 'refs/heads/reset' | while IFS= read -r ref; do
  git update-ref -d "$ref"
done
git stash clear 2>/dev/null || true

# 3. branch sections and leftovers that name old history. Remote URLs stay.
git config --name-only --get-regexp '^branch\.' 2>/dev/null | sed -E 's/^(branch\..*)\.[^.]+$/\1/' | sort -u |
  while IFS= read -r sec; do git config --remove-section "$sec" 2>/dev/null || true; done
rm -f "$git_dir/ORIG_HEAD" "$git_dir/FETCH_HEAD" "$git_dir/MERGE_HEAD" "$git_dir/COMMIT_EDITMSG" \
      "$git_dir/packed-refs.old" "$git_dir/gc.log"
rm -rf "$git_dir/logs" "$git_dir/refs/original" "$git_dir/rr-cache"

# 4. drop every unreachable object
git reflog expire --expire=now --all
git repack -a -d -q
git gc --prune=now -q

# 5. prove it
bad=0
refs="$(git for-each-ref --format='%(refname)')"
[ "$refs" = "refs/heads/reset" ] || { echo "FAIL refs: $refs"; bad=1; }
[ "$(git log --all --oneline | wc -l | tr -d ' ')" = "1" ] || { echo "FAIL: git log --all shows more than one commit"; bad=1; }
[ "$(git worktree list | wc -l | tr -d ' ')" = "1" ] || { echo "FAIL: linked worktrees remain"; bad=1; }
total="$(git cat-file --batch-all-objects --batch-check | wc -l | tr -d ' ')"
reach="$(git rev-list --objects reset | wc -l | tr -d ' ')"
[ "$total" = "$reach" ] || { echo "FAIL objects: total=$total reachable=$reach"; bad=1; }
[ -z "$(git config --name-only --get-regexp '^branch\.' 2>/dev/null)" ] || { echo "FAIL: branch sections remain in .git/config"; bad=1; }
for d in lfs modules; do
  if [ -d "$git_dir/$d" ] && [ -n "$(ls -A "$git_dir/$d" 2>/dev/null)" ]; then
    echo "WARN: .git/$d is not empty; objects from old history may remain there (not removed: they may be needed)"
  fi
done
echo "refs: $refs"
echo "objects: total=$total reachable=$reach"
echo "worktrees: $(git worktree list | wc -l | tr -d ' ')"
if [ "$bad" = 0 ]; then echo "HISTORY_DESTROYED"; else echo "HISTORY_NOT_CLEAN"; exit 1; fi
