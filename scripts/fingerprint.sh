#!/usr/bin/env bash
# fingerprint.sh <project-root> [--lines] < in-scope-items
#
# Prints a short token that identifies "this exact scope of this exact repo state".
# The dry run prints it. Execute mode recomputes it and refuses to act on a mismatch.
# Writes nothing to disk. Reads git state only (no network).
#
# Built in (no input needed): root, HEAD, branch, refs, stashes, remotes, the installed
# skill commit, the working-tree status AND a hash of the contents of every tracked and
# untracked (non-ignored) file, and the same for every linked worktree of this repo.
#
# stdin: one plan item per line, as "<section>|<stable id>".
#   sections: datastore, container, process, harness, include, exclude,
#             delete, rename, truncate, line
#   ids must be stable: absolute paths, host/name, container names, old names,
#   <store>/<table>, <file>|<exact line>. Never PIDs, timestamps, counts, or newly chosen names.
# --lines prints the canonical lines instead of the hash (use it to explain a mismatch).
set -uo pipefail

root="${1:-}"; mode="${2:-}"
[ -n "$root" ] && [ -d "$root" ] || { echo "usage: fingerprint.sh <project-root> [--lines] < items" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 2; }
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: $root is not inside a git repository" >&2; exit 2; }
top="$(cd "$top" && pwd -P)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if command -v sha256sum >/dev/null 2>&1; then HASHER=(sha256sum); else HASHER=(shasum -a 256); fi

digest() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

# tree_state <dir>: status paths plus a content hash of every non-ignored file.
tree_state() {
  local d="$1" out
  if ! out="$(
    {
      git -C "$d" status --porcelain=v1 -z --untracked-files=all || exit 1
      git -C "$d" ls-files -co --exclude-standard -z | (
        cd "$d" || exit 1
        while IFS= read -r -d '' f; do
          [ -f "$f" ] && printf '%s\0' "$f"
        done | xargs -0 -r git hash-object -- || exit 1
      ) || exit 1
    } | digest
  )"; then
    echo "HASHFAIL"
    return 0
  fi
  printf '%s\n' "$out"
}

skill_state() {
  local base m
  base="$(cd "$here/.." && pwd -P)"
  m="$(sed -n 's/^[[:space:]]*"commit":[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$base/.context-bleach-install.json" 2>/dev/null | head -n 1)"
  printf '%s:' "${m:-unmanaged}"
  # relative paths, so identical copies installed in different places give the same value
  (cd "$base" && for p in SKILL.md scripts references; do [ -e "$p" ] && find "$p" -type f -print0; done |
    LC_ALL=C sort -z | xargs -0 -r "${HASHER[@]}") | digest
}

lines() {
  echo "root|$top"
  echo "head|$(git -C "$top" rev-parse HEAD 2>/dev/null || echo unborn)"
  echo "branch|$(git -C "$top" symbolic-ref -q --short HEAD 2>/dev/null || echo detached)"
  echo "tree|$(tree_state "$top")"
  echo "refs|$(git -C "$top" for-each-ref 2>/dev/null | digest)"
  echo "stash|$(git -C "$top" stash list 2>/dev/null | digest)"
  echo "remotes|$(git -C "$top" remote -v 2>/dev/null | digest)"
  echo "skill|$(skill_state)"
  git -C "$top" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r w; do
    w="$(cd "$w" 2>/dev/null && pwd -P || echo "$w")"
    [ "$w" = "$top" ] && continue
    echo "worktree|$w|$(git -C "$w" rev-parse HEAD 2>/dev/null || echo none)|$(tree_state "$w")"
  done
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

canon="$(lines | LC_ALL=C sort -u)"
if printf '%s\n' "$canon" | grep -q 'HASHFAIL'; then
  echo "ERROR: could not hash the working tree; refusing to print a token" >&2
  exit 2
fi
if [ "$mode" = "--lines" ]; then printf '%s\n' "$canon"; exit 0; fi
printf '%s\n' "$canon" | digest | cut -c1-16
