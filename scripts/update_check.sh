#!/usr/bin/env bash
# update_check.sh [--apply] [--force] - check or update the installed context-bleach skill.
#
# Default: print one status line and change nothing.
#   UP_TO_DATE    installed commit equals the latest commit and no local edits
#   UPDATE_AVAILABLE
#   LOCAL_DIRTY   local edits or a dirty source checkout; the copy is not replaced
#   UNMANAGED     no install metadata; the copy is not self-updated
#   ERROR         the check failed; keep using the installed copy
# --apply: fetch the latest payload for the recorded source/ref, stage it, then
#   swap it into place. Restart or refresh the agent afterwards.
# --force: with --apply, overwrite a dirty copy. Only with explicit user approval.
# Set CONTEXT_BLEACH_NO_UPDATE=1 to skip everything (offline or air-gapped use).
set -uo pipefail

ACTION="check"
FORCE="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) ACTION="apply" ;;
    --force) FORCE="1" ;;
    *) echo "usage: update_check.sh [--apply] [--force]" >&2; exit 2 ;;
  esac
  shift
done

if [ -n "${CONTEXT_BLEACH_NO_UPDATE:-}" ]; then
  echo "DISABLED update_check=skipped"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
META="$SKILL_DIR/.context-bleach-install.json"
NET_TIMEOUT="${CONTEXT_BLEACH_NET_TIMEOUT:-10}"

fail() {
  echo "ERROR reason=$*"
  exit 2
}

[ -f "$META" ] || { echo "UNMANAGED update_check=skipped"; exit 0; }
command -v python3 >/dev/null 2>&1 || fail "python3_not_found"

meta_get() {
  python3 - "$META" "$1" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
value = data.get(sys.argv[2], "")
print(("true" if value else "false") if isinstance(value, bool) else value)
PY
}

# Prints "clean" or "dirty" by comparing files on disk with the recorded hashes.
payload_state() {
  python3 - "$SKILL_DIR" "$META" <<'PY'
import hashlib, json, os, sys
root, meta = sys.argv[1], sys.argv[2]
files = json.load(open(meta, encoding="utf-8")).get("files")
if not isinstance(files, dict):
    print("clean"); sys.exit(0)
seen = {}
for base, dirs, names in os.walk(root):
    dirs[:] = [d for d in dirs if d not in ("__pycache__", ".git")]
    for name in names:
        path = os.path.join(base, name)
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        if rel == ".context-bleach-install.json":
            continue
        seen[rel] = hashlib.sha256(open(path, "rb").read()).hexdigest()
print("clean" if seen == files else "dirty")
PY
}

is_full_sha() { [[ "${1:-}" =~ ^[0-9a-fA-F]{40}$ ]]; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

github_repo() {
  printf '%s' "$1" | sed -nE 's#^(https://github.com/|git@github.com:)([^/]+/[^/.]+)(\.git)?$#\2#p'
}

with_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout "$NET_TIMEOUT" "$@"; else "$@"; fi
}

remote_commit() {
  local source_url="$1" ref="$2" commit="" repo
  if is_full_sha "$ref"; then lower "$ref"; return 0; fi
  if command -v git >/dev/null 2>&1; then
    commit="$(GIT_TERMINAL_PROMPT=0 with_timeout git ls-remote "$source_url" "$ref" 2>/dev/null | awk 'NR == 1 {print $1}')"
  fi
  if is_full_sha "$commit"; then lower "$commit"; return 0; fi
  repo="$(github_repo "$source_url")"
  if [ -n "$repo" ] && command -v curl >/dev/null 2>&1; then
    commit="$(curl -fsSL --max-time "$NET_TIMEOUT" "https://api.github.com/repos/$repo/commits/$ref" 2>/dev/null |
      sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",[[:space:]]*$/\1/p' | head -n 1)"
    if is_full_sha "$commit"; then lower "$commit"; return 0; fi
  fi
  return 1
}

SOURCE="$(meta_get source)" || fail "invalid_metadata"
REF="$(meta_get ref)"
INSTALLED="$(lower "$(meta_get commit)")"
SRC_DIRTY="$(meta_get dirty)"
[ -n "$SOURCE" ] && [ -n "$REF" ] || fail "invalid_metadata"
is_full_sha "$INSTALLED" || fail "invalid_metadata"

PAYLOAD="$(payload_state)"
DIRTY="false"
{ [ "$SRC_DIRTY" = "true" ] || [ "$PAYLOAD" = "dirty" ]; } && DIRTY="true"

if [ "$DIRTY" = "true" ] && [ "$FORCE" != "1" ]; then
  echo "LOCAL_DIRTY installed=$INSTALLED payload_dirty=$([ "$PAYLOAD" = dirty ] && echo true || echo false) source_dirty=$SRC_DIRTY"
  exit 0
fi

LATEST="$(remote_commit "$SOURCE" "$REF")" || fail "latest_commit_unavailable"

if [ "$INSTALLED" = "$LATEST" ] && [ "$DIRTY" != "true" ]; then
  echo "UP_TO_DATE commit=$INSTALLED"
  exit 0
fi

echo "UPDATE_AVAILABLE installed=$INSTALLED latest=$LATEST ref=$REF source=$SOURCE"
[ "$ACTION" = "apply" ] || exit 0

command -v curl >/dev/null 2>&1 || fail "curl_not_found"
REPO="$(github_repo "$SOURCE")"
[ -n "$REPO" ] || fail "raw_url_unavailable"
RAW="https://raw.githubusercontent.com/$REPO/$LATEST"

LOCK="$(dirname "$SKILL_DIR")/.$(basename "$SKILL_DIR").update.lock"
mkdir "$LOCK" 2>/dev/null || fail "update_locked"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rmdir "$LOCK" 2>/dev/null' EXIT

curl -fsSL --max-time 30 "$RAW/install.sh" -o "$TMP/install.sh" || fail "installer_download_failed"
head -c 2 "$TMP/install.sh" | grep -q '^#!' || fail "installer_download_invalid"

if CONTEXT_BLEACH_DEST="$SKILL_DIR" \
   CONTEXT_BLEACH_SOURCE="$SOURCE" \
   CONTEXT_BLEACH_REF="$REF" \
   CONTEXT_BLEACH_COMMIT="$LATEST" \
   CONTEXT_BLEACH_RAW="$RAW" \
   CONTEXT_BLEACH_SOURCE_DIRTY=false \
   bash "$TMP/install.sh" >"$TMP/out.log" 2>&1; then
  echo "UPDATED commit=$LATEST"
else
  fail "apply_failed_$(tail -n 1 "$TMP/out.log" | tr -c 'A-Za-z0-9._-' '_')"
fi
