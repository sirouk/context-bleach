#!/usr/bin/env bash
# install.sh - install the "context-bleach" skill for any coding agent.
#
#   curl -fsSL https://raw.githubusercontent.com/sirouk/context-bleach/main/install.sh | bash
#
# The skill is plain SKILL.md + scripts + references. It installs into the skills
# directory of each verified agent found on the machine, plus the shared
# ~/.agents/skills (read by Codex and other agents). Gemini, OpenCode and Cursor
# paths are best effort and install only when you name them in CONTEXT_BLEACH_TARGETS.
#
# Env overrides:
#   CONTEXT_BLEACH_TARGETS  comma list: auto (default), all, or any of
#                           claude,codex,agents,prime,hermes   (verified)
#                           gemini,opencode,cursor              (best effort, opt-in only)
#   CONTEXT_BLEACH_DEST     explicit install directory (the skill folder itself);
#                           overrides TARGETS. Project scope example:
#                           CONTEXT_BLEACH_DEST=$PWD/.claude/skills/context-bleach
#   CONTEXT_BLEACH_SOURCE   git source URL recorded for update checks
#                           (default: https://github.com/sirouk/context-bleach.git)
#   CONTEXT_BLEACH_REF      ref recorded for update checks (default: main)
#   CONTEXT_BLEACH_COMMIT   exact 40-hex commit to install (pinned or manual installs)
#   CONTEXT_BLEACH_RAW      raw base URL (default: derived from source and commit)
#   CODEX_SKILLS_HOME (default ~/.agents/skills), CLAUDE_HOME, HERMES_HOME, GEMINI_HOME
#
# Re-running the same command updates the skill.
# Uninstall: curl -fsSL .../install.sh | bash -s -- --uninstall
set -euo pipefail

SOURCE="${CONTEXT_BLEACH_SOURCE:-https://github.com/sirouk/context-bleach.git}"
REF="${CONTEXT_BLEACH_REF:-main}"
RAW="${CONTEXT_BLEACH_RAW:-}"
NAME="context-bleach"
META=".context-bleach-install.json"
FILES=(
  SKILL.md
  agents/openai.yaml
  references/harness-locations.md
  scripts/update_check.sh
  scripts/fingerprint.sh
  scripts/destroy_history.sh
  LICENSE
)

MODE="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE="uninstall" ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null; exit 0 ;;
    *) echo "ERROR: unknown option '$arg'" >&2; exit 2 ;;
  esac
done

# Local checkout next to this script? Install from it instead of the network.
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || d=""
  [ -n "$d" ] && [ -f "$d/SKILL.md" ] && SRC="$d"
fi
HAVE_GIT=0; command -v git >/dev/null 2>&1 && HAVE_GIT=1
IS_CHECKOUT=0; [ -n "$SRC" ] && [ "$HAVE_GIT" = 1 ] && [ -e "$SRC/.git" ] && IS_CHECKOUT=1

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
is_full_sha() { [[ "${1:-}" =~ ^[0-9a-fA-F]{40}$ ]]; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
github_repo() { printf '%s' "$1" | sed -nE 's#^(https://github.com/|git@github.com:)([^/]+/[^/.]+)(\.git)?$#\2#p'; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else return 1; fi
}

remote_commit() {
  local commit="" repo
  if is_full_sha "$REF"; then lower "$REF"; return 0; fi
  if [ "$HAVE_GIT" = 1 ]; then
    commit="$(GIT_TERMINAL_PROMPT=0 git ls-remote "$SOURCE" "$REF" 2>/dev/null | awk 'NR == 1 {print $1}')"
  fi
  if is_full_sha "$commit"; then lower "$commit"; return 0; fi
  repo="$(github_repo "$SOURCE")"
  if [ -n "$repo" ] && command -v curl >/dev/null 2>&1; then
    commit="$(curl -fsSL "https://api.github.com/repos/$repo/commits/$REF" 2>/dev/null |
      sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",[[:space:]]*$/\1/p' | head -n 1)"
    if is_full_sha "$commit"; then lower "$commit"; return 0; fi
  fi
  return 1
}

target_path() {
  case "$1" in
    claude)   echo "${CLAUDE_HOME:-$HOME/.claude}/skills/$NAME" ;;
    codex)    echo "${CODEX_SKILLS_HOME:-$HOME/.agents/skills}/$NAME" ;;
    agents)   echo "$HOME/.agents/skills/$NAME" ;;
    prime)    echo "$HOME/.prime/agent/skills/$NAME" ;;
    gemini)   echo "${GEMINI_HOME:-$HOME/.gemini}/skills/$NAME" ;;
    opencode) echo "$HOME/.config/opencode/skills/$NAME" ;;
    cursor)   echo "$HOME/.cursor/skills/$NAME" ;;
    hermes)   echo "${HERMES_HOME:-$HOME/.hermes}/skills/software-development/$NAME" ;;
    *) echo "ERROR: unknown target '$1'" >&2; exit 2 ;;
  esac
}

agent_home() {
  case "$1" in
    claude)   echo "${CLAUDE_HOME:-$HOME/.claude}" ;;
    codex)    echo "${CODEX_SKILLS_HOME:-$HOME/.agents/skills}" ;;
    agents)   echo "$HOME/.agents" ;;
    prime)    echo "$HOME/.prime/agent" ;;
    gemini)   echo "${GEMINI_HOME:-$HOME/.gemini}" ;;
    opencode) echo "$HOME/.config/opencode" ;;
    cursor)   echo "$HOME/.cursor" ;;
    hermes)   echo "${HERMES_HOME:-$HOME/.hermes}" ;;
  esac
}

ALL_TARGETS="claude agents prime hermes gemini opencode cursor"
AUTO_TARGETS="claude agents prime hermes"

expand_targets() {
  local raw out="" t
  raw="$(printf '%s' "${CONTEXT_BLEACH_TARGETS:-auto}" | tr ',' ' ')"
  for t in $raw; do
    case "$t" in
      all) out="$out $ALL_TARGETS" ;;
      auto)
        for a in $AUTO_TARGETS; do
          if [ "$a" = agents ] || [ -d "$(agent_home "$a")" ]; then out="$out $a"; fi
        done ;;
      claude|codex|agents|prime|gemini|opencode|cursor|hermes) out="$out $t" ;;
      *) echo "ERROR: unknown target '$t'" >&2; exit 2 ;;
    esac
  done
  printf '%s\n' "$out"
}

list_dests() {
  if [ -n "${CONTEXT_BLEACH_DEST:-}" ]; then echo "$CONTEXT_BLEACH_DEST"; return; fi
  local seen="" t d
  for t in $(expand_targets); do
    d="$(target_path "$t")"
    case " $seen " in *" $d "*) continue ;; esac
    seen="$seen $d"; echo "$d"
  done
}

# Validate targets here: exit inside $(...) would not stop the script.
if [ -z "${CONTEXT_BLEACH_DEST:-}" ]; then
  for t in $(printf '%s' "${CONTEXT_BLEACH_TARGETS:-auto}" | tr ',' ' '); do
    case "$t" in
      auto|all|claude|codex|agents|prime|gemini|opencode|cursor|hermes) ;;
      *) echo "ERROR: unknown target '$t'" >&2; exit 2 ;;
    esac
  done
fi

if [ "$MODE" = "uninstall" ]; then
  list_dests | while IFS= read -r d; do
    if [ -f "$d/$META" ]; then rm -rf "$d"; echo "removed $d"
    elif [ -e "$d" ]; then echo "skipped $d (not installed by this tool)"; fi
  done
  exit 0
fi

# Resolve what we are installing.
if [ "$IS_CHECKOUT" = 1 ]; then
  COMMIT="$(lower "${CONTEXT_BLEACH_COMMIT:-$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)}")"
  b="$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$b" ] && [ "$b" != HEAD ] && REF="$b"
  o="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
  [ -n "$o" ] && SOURCE="$o"
  DIRTY=false
  [ -n "$(git -C "$SRC" status --porcelain 2>/dev/null || true)" ] && DIRTY=true
else
  COMMIT="$(lower "${CONTEXT_BLEACH_COMMIT:-$(remote_commit || true)}")"
  DIRTY=false
fi
is_full_sha "$COMMIT" || { echo "ERROR: could not resolve a full 40-hex commit for $SOURCE $REF (got '$COMMIT')" >&2; exit 1; }
if [ -z "$RAW" ]; then
  repo="$(github_repo "$SOURCE")"
  [ -n "$repo" ] && RAW="https://raw.githubusercontent.com/$repo/$COMMIT"
fi

if [ -n "$SRC" ]; then echo "Installing from local source: $SRC"
else
  [ -n "$RAW" ] || { echo "ERROR: no raw URL; set CONTEXT_BLEACH_RAW" >&2; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }
  echo "Installing from: $RAW"
fi

populate() {
  local dest="$1" f
  for f in "${FILES[@]}"; do
    mkdir -p "$dest/$(dirname "$f")" || return 1
    if [ -n "$SRC" ]; then cp "$SRC/$f" "$dest/$f" || return 1
    else curl -fsSL "$RAW/$f" -o "$dest/$f" || return 1; fi
  done
  chmod +x "$dest/scripts/update_check.sh" "$dest/scripts/fingerprint.sh" "$dest/scripts/destroy_history.sh"
  write_meta "$dest"
}

write_meta() {
  local dest="$1" f h sep="" files=""
  for f in "${FILES[@]}"; do
    if h="$(sha256_of "$dest/$f")"; then
      files="$files$sep    \"$f\": \"$h\""; sep=$',\n'
    fi
  done
  cat > "$dest/$META" <<EOF
{
  "schema": 1,
  "skill": "$NAME",
  "source": "$(json_escape "$SOURCE")",
  "ref": "$(json_escape "$REF")",
  "commit": "$COMMIT",
  "dirty": $DIRTY,
  "installed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "files": {
$files
  }
}
EOF
}

install_one() {
  local dest="$1" parent base stage backup=""
  parent="$(dirname "$dest")"; base="$(basename "$dest")"
  mkdir -p "$parent"
  stage="$(mktemp -d "$parent/.$base.stage.XXXXXX")"
  if ! populate "$stage"; then
    rm -rf "$stage"
    echo "ERROR: could not assemble payload for $dest; existing install left unchanged." >&2
    return 1
  fi
  if [ -e "$dest" ]; then
    backup="$(mktemp -d "$parent/.$base.old.XXXXXX")"; rmdir "$backup"
    mv "$dest" "$backup" || { rm -rf "$stage"; echo "ERROR: cannot replace $dest" >&2; return 1; }
  fi
  if ! mv "$stage" "$dest"; then
    [ -n "$backup" ] && [ ! -e "$dest" ] && mv "$backup" "$dest" || true
    rm -rf "$stage"; echo "ERROR: could not install $dest" >&2; return 1
  fi
  [ -z "$backup" ] || rm -rf "$backup"
  echo "  -> $dest"
}

echo "Installed context-bleach @ ${COMMIT:0:12}:"
rc=0
while IFS= read -r d; do
  install_one "$d" || rc=1
done < <(list_dests)

echo "Restart or refresh your agent, then say \"context-bleach\" for a dry run (changes nothing)."
echo "WARNING: \"context-bleach execute <token>\" deletes data irreversibly. It needs a token from a dry run."
exit "$rc"
