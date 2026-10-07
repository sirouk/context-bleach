#!/usr/bin/env bash
# Sandbox tests for install.sh and scripts/update_check.sh. Never touches the real HOME.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude" "$HOME/.codex"
unset CLAUDE_HOME CODEX_HOME CONTEXT_BLEACH_NO_UPDATE CONTEXT_BLEACH_TARGETS CONTEXT_BLEACH_DEST
pass=0; failn=0
ok() { pass=$((pass+1)); echo "ok   - $1"; }
bad() { failn=$((failn+1)); echo "FAIL - $1"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
has() { grep -q -- "$2" <<<"$1"; }

# A bare "remote" and a working clone, so the checkout path is realistic.
git init -q --bare "$T/remote.git"
git clone -q "$ROOT" "$T/work" 2>/dev/null
git -C "$T/work" remote set-url origin "$T/remote.git"
git -C "$T/work" push -q origin HEAD:main 2>/dev/null
export CONTEXT_BLEACH_SOURCE="$T/remote.git"

# 1. install from checkout into auto-detected agents
out="$(bash "$T/work/install.sh" 2>&1)"
for d in .claude .agents; do check "installed into $d" test -f "$HOME/$d/skills/context-bleach/SKILL.md"; done
check "codex alias is not a separate copy" test ! -e "$HOME/.codex/skills/context-bleach"
check "no gemini dir created" test ! -e "$HOME/.gemini"
S="$HOME/.claude/skills/context-bleach"
check "updater is executable" test -x "$S/scripts/update_check.sh"
check "fingerprint is executable" test -x "$S/scripts/fingerprint.sh"
check "metadata has 40-hex commit" grep -Eq '"commit": "[0-9a-f]{40}"' "$S/.context-bleach-install.json"
check "metadata hashes every file" test "$(grep -c '": "[0-9a-f]\{64\}"' "$S/.context-bleach-install.json")" -eq 6

# 2. up to date
out="$(bash "$S/scripts/update_check.sh" --apply)"; has "$out" '^UP_TO_DATE' && ok "UP_TO_DATE" || bad "UP_TO_DATE ($out)"

# 3. local edit => LOCAL_DIRTY, file kept
echo "# edit" >> "$S/SKILL.md"
out="$(bash "$S/scripts/update_check.sh" --apply)"; has "$out" '^LOCAL_DIRTY' && ok "LOCAL_DIRTY" || bad "LOCAL_DIRTY ($out)"
check "dirty edit preserved" grep -q '^# edit' "$S/SKILL.md"

# 4. new upstream commit is detected (apply needs a github source, so a file URL reports the limit)
echo "x" > "$T/work/NEW.txt"; git -C "$T/work" add -A; git -C "$T/work" -c user.name=t -c user.email=t@t commit -qm new
git -C "$T/work" push -q origin HEAD:main
sed -i 's/^# edit$//' "$S/SKILL.md"; sed -i '${/^$/d}' "$S/SKILL.md"
out="$(bash "$S/scripts/update_check.sh")"; has "$out" '^UPDATE_AVAILABLE' && ok "UPDATE_AVAILABLE" || bad "UPDATE_AVAILABLE ($out)"
out="$(bash "$S/scripts/update_check.sh" --apply)"; has "$out" 'ERROR reason=raw_url_unavailable' && ok "non-GitHub source fails safe" || bad "non-GitHub apply ($out)"
check "skill intact after failed apply" test -f "$S/SKILL.md"
out="$(CONTEXT_BLEACH_RAW="file://$T/work" bash "$S/scripts/update_check.sh" --apply)"
has "$out" '^UPDATED' && ok "UPDATED via RAW override" || bad "UPDATED ($out)"
new="$(git -C "$T/work" rev-parse HEAD)"
check "metadata now at new commit" grep -q "\"commit\": \"$new\"" "$S/.context-bleach-install.json"
out="$(bash "$S/scripts/update_check.sh")"; has "$out" '^UP_TO_DATE' && ok "clean after update" || bad "clean after update ($out)"
check "no lock left behind" test -z "$(find "$HOME/.claude/skills" -maxdepth 1 -name '.*lock*')"

# 5. disabled and unmanaged
out="$(CONTEXT_BLEACH_NO_UPDATE=1 bash "$S/scripts/update_check.sh")"; has "$out" '^DISABLED' && ok "DISABLED" || bad "DISABLED"
mkdir -p "$T/u/scripts"; cp "$S/scripts/update_check.sh" "$T/u/scripts/"
out="$(bash "$T/u/scripts/update_check.sh")"; has "$out" '^UNMANAGED' && ok "UNMANAGED" || bad "UNMANAGED"

# 6. explicit dest, then reinstall overwrites cleanly, then uninstall
D="$T/proj/.claude/skills/context-bleach"
CONTEXT_BLEACH_DEST="$D" bash "$T/work/install.sh" >/dev/null 2>&1; check "explicit DEST install" test -f "$D/SKILL.md"
CONTEXT_BLEACH_DEST="$D" bash "$T/work/install.sh" >/dev/null 2>&1; check "reinstall over existing" test -f "$D/SKILL.md"
check "no stage leftovers" test -z "$(find "$T/proj" -name '.*stage*' -o -name '.*old*')"
CONTEXT_BLEACH_DEST="$D" bash "$T/work/install.sh" --uninstall >/dev/null 2>&1; check "uninstall removes managed copy" test ! -e "$D"
mkdir -p "$T/foreign"; CONTEXT_BLEACH_DEST="$T/foreign" bash "$T/work/install.sh" --uninstall >/dev/null 2>&1
check "uninstall skips unmanaged dir" test -d "$T/foreign"

# 7. targets
CONTEXT_BLEACH_TARGETS=gemini bash "$T/work/install.sh" >/dev/null 2>&1; check "explicit target gemini" test -f "$HOME/.gemini/skills/context-bleach/SKILL.md"
CONTEXT_BLEACH_TARGETS=bogus bash "$T/work/install.sh" >/dev/null 2>&1; [ $? -ne 0 ] && ok "bogus target rejected" || bad "bogus target"

# 8. skill content sanity
CONTEXT_BLEACH_TARGETS=codex CODEX_SKILLS_HOME="$T/cx" bash "$T/work/install.sh" >/dev/null 2>&1; check "codex target honors CODEX_SKILLS_HOME" test -f "$T/cx/context-bleach/SKILL.md"

# 9. fingerprint: deterministic, order-free, sensitive to scope and repo state
F="$ROOT/scripts/fingerprint.sh"
git init -q "$T/fp"; git -C "$T/fp" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
t1="$(printf 'datastore|h/a\nharness|/x\n' | "$F" "$T/fp")"
t2="$(printf 'harness|/x\n\n datastore|h/a \n' | "$F" "$T/fp")"
[ -n "$t1" ] && [ "$t1" = "$t2" ] && ok "token stable across order and whitespace" || bad "token stable ($t1 $t2)"
[ "${#t1}" -eq 16 ] && ok "token is 16 hex" || bad "token length"
t3="$(printf 'datastore|h/b\nharness|/x\n' | "$F" "$T/fp")"; [ "$t1" != "$t3" ] && ok "token changes with scope" || bad "scope change"
echo z > "$T/fp/new.txt"; t4="$(printf 'datastore|h/a\nharness|/x\n' | "$F" "$T/fp")"; [ "$t1" != "$t4" ] && ok "token changes with working tree" || bad "tree change"
rm "$T/fp/new.txt"; git -C "$T/fp" tag v1; t5="$(printf 'datastore|h/a\nharness|/x\n' | "$F" "$T/fp")"; [ "$t1" != "$t5" ] && ok "token changes with a new ref" || bad "ref change"
git -C "$T/fp" tag -d v1 >/dev/null; t6="$(printf 'datastore|h/a\nharness|/x\n' | "$F" "$T/fp")"; [ "$t1" = "$t6" ] && ok "token returns when state returns" || bad "token restore"
mkdir -p "$T/notgit"; printf '' | "$F" "$T/notgit" >/dev/null 2>&1; [ $? -eq 2 ] && ok "fingerprint refuses non-git dir" || bad "non-git"
check "fingerprint --lines prints canonical lines" bash -c "printf 'harness|/x\n' | '$F' '$T/fp' --lines | grep -q '^harness|/x'"
check "dry run left no git changes" test -z "$(git -C "$T/fp" status --porcelain)"

check "SKILL.md has name" grep -q '^name: context-bleach' "$ROOT/SKILL.md"
check "skill stays visible (no disable flag)" test -z "$(grep -m1 '^disable-model-invocation' "$ROOT/SKILL.md")"
check "agent may not supply its own token" grep -q 'Never supply, guess, or reuse a token' "$ROOT/SKILL.md"
check "frontmatter valid" python3 - "$ROOT/SKILL.md" <<'PY'
import re, sys, yaml, os
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t.split('---')[1])
assert fm['name'] == 'context-bleach' and re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', fm['name']) and len(fm['name']) <= 64
assert 0 < len(fm['description']) <= 1024, len(fm['description'])
PY
check "SKILL.md documents dry run and token" grep -q 'context-bleach execute <token>' "$ROOT/SKILL.md"
check "implicit invocation off" grep -q 'allow_implicit_invocation: false' "$ROOT/agents/openai.yaml"

echo; echo "passed=$pass failed=$failn"; [ "$failn" -eq 0 ]
