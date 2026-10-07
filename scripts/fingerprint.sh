#!/usr/bin/env bash
# fingerprint.sh <project-root> [--lines] < in-scope-items
#
# Prints a short token that identifies "this exact scope of this exact repo state".
# The dry run prints it. Execute mode recomputes it and refuses to act on a mismatch.
# Writes nothing to disk. Reads git state only (no network).
#
# stdin: one in-scope item per line, as "<section>|<stable id>".
#   sections: datastore, container, process, harness, include, exclude
#   ids must be stable: absolute paths, host/name, container names, a process's
#   script or working-directory path. Never PIDs, timestamps, or per-file transcripts.
# --lines prints the canonical lines instead of the hash (use it to explain a mismatch).
set -uo pipefail

root="${1:-}"; mode="${2:-}"
[ -n "$root" ] && [ -d "$root" ] || { echo "usage: fingerprint.sh <project-root> [--lines] < items" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 2; }
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: $root is not inside a git repository" >&2; exit 2; }
top="$(cd "$top" && pwd -P)"

digest() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

lines() {
  echo "root|$top"
  echo "head|$(git -C "$top" rev-parse HEAD 2>/dev/null || echo unborn)"
  echo "branch|$(git -C "$top" symbolic-ref -q --short HEAD 2>/dev/null || echo detached)"
  echo "status|$(git -C "$top" status --porcelain=v1 -z --untracked-files=all 2>/dev/null | digest)"
  echo "refs|$(git -C "$top" for-each-ref 2>/dev/null | digest)"
  echo "stash|$(git -C "$top" stash list 2>/dev/null | digest)"
  echo "remotes|$(git -C "$top" remote -v 2>/dev/null | digest)"
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

canon="$(lines | LC_ALL=C sort -u)"
if [ "$mode" = "--lines" ]; then printf '%s\n' "$canon"; exit 0; fi
printf '%s\n' "$canon" | digest | cut -c1-16
