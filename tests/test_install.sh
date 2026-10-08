#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2181
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
check "metadata hashes every file" test "$(grep -c '": "[0-9a-f]\{64\}"' "$S/.context-bleach-install.json")" -eq 7

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

# 10. token covers file contents, linked worktrees, and the skill commit
G="$T/fc"; git init -q -b main "$G"; printf 'a\n' > "$G/app.txt"; git -C "$G" add -A; git -C "$G" -c user.name=t -c user.email=t@t commit -q -m a
c0="$("$F" "$G" </dev/null)"
echo v1 > "$G/untracked.txt"; c1="$("$F" "$G" </dev/null)"; echo v2 > "$G/untracked.txt"; c2="$("$F" "$G" </dev/null)"
[ "$c0" != "$c1" ] && [ "$c1" != "$c2" ] && ok "token changes when an untracked file's content changes" || bad "untracked content ($c0 $c1 $c2)"
echo m1 >> "$G/app.txt"; d1="$("$F" "$G" </dev/null)"; echo m2 >> "$G/app.txt"; d2="$("$F" "$G" </dev/null)"
[ "$d1" != "$d2" ] && ok "token changes on a second edit of a modified file" || bad "modified content"
git -C "$G" checkout -q -- app.txt; rm "$G/untracked.txt"; e0="$("$F" "$G" </dev/null)"
[ "$e0" = "$c0" ] && ok "token returns when contents return" || bad "token restore ($e0 $c0)"
git -C "$G" branch plan; git -C "$G" worktree add -q "$T/fcwt" plan
w1="$("$F" "$G" </dev/null)"; echo edit > "$T/fcwt/x.txt"; w2="$("$F" "$G" </dev/null)"
[ "$w1" != "$w2" ] && [ "$w1" != "$c0" ] && ok "token covers linked worktrees" || bad "worktree ($c0 $w1 $w2)"
"$F" "$G" --lines </dev/null | grep -Eq '^skill\|unmanaged:[0-9a-f]{64}$' && ok "unmanaged copy still hashes its own skill files" || bad "skill line"
"$S/scripts/fingerprint.sh" "$G" --lines </dev/null | grep -Eq '^skill\|[0-9a-f]{40}:[0-9a-f]{64}$' && ok "installed copy pins its skill commit and files" || bad "installed skill commit"

# 11. destroy_history: refuses unsafe states, leaves nothing behind
H="$T/hist"; git init -q -b main "$H"; export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
echo "OLDMARKER-readme" > "$H/README.md"; echo code > "$H/app.txt"; echo SECRETFILE > "$H/.env"; echo .env > "$H/.gitignore"
git -C "$H" add -A; git -C "$H" commit -q -m one; git -C "$H" tag v1; git -C "$H" branch plan
git -C "$H" worktree add -q "$T/histwt" plan; echo "OLDMARKER-plan" > "$T/histwt/plan.md"; git -C "$T/histwt" add -A; git -C "$T/histwt" commit -q -m plan
git -C "$H" remote add origin "$T/remote.git"; git -C "$H" config branch.main.remote origin; git -C "$H" config branch.main.merge refs/heads/main
git -C "$H" stash list >/dev/null
D="$ROOT/scripts/destroy_history.sh"
(cd "$H" && "$D" >/dev/null 2>&1); [ $? -eq 2 ] && ok "destroy_history refuses off the reset branch" || bad "off-reset refusal"
git -C "$H" checkout -q -b reset; git -C "$H" rm -q README.md; git -C "$H" commit -q -m two
(cd "$H" && "$D" >/dev/null 2>&1); [ $? -eq 2 ] && ok "destroy_history refuses without a single commit" || bad "multi-commit refusal"
git -C "$H" checkout -q --orphan tmp; git -C "$H" add -A; git -C "$H" commit -q -m "Initial commit"; git -C "$H" branch -M reset
out="$(cd "$H" && "$D" 2>&1)"; has "$out" 'HISTORY_DESTROYED' && ok "destroy_history reports clean" || bad "destroy_history ($out)"
check "only refs/heads/reset remains" test "$(git -C "$H" for-each-ref --format='%(refname)')" = "refs/heads/reset"
check "linked worktree folder is gone" test ! -e "$T/histwt"
check "removal of the worktree is announced" bash -c "echo '$out' | grep -q 'removed worktree'"
check "branch sections removed from .git/config" test -z "$(git -C "$H" config --name-only --get-regexp '^branch\.' 2>/dev/null)"
check "remote URL kept" test "$(git -C "$H" remote get-url origin)" = "$T/remote.git"
check "old history text not found anywhere under .git" test -z "$(grep -rIl --binary-files=text 'OLDMARKER' "$H/.git" 2>/dev/null)"
check "old commit objects not in the object store" bash -c "cd '$H' && [ \"\$(git cat-file --batch-all-objects --batch-check | wc -l)\" = \"\$(git rev-list --objects reset | wc -l)\" ]"
mkdir -p "$H/.git/lfs/objects"; echo big > "$H/.git/lfs/objects/x"
out2="$(cd "$H" && "$D" 2>&1)"; has "$out2" 'WARN: .git/lfs' && has "$out2" 'HISTORY_DESTROYED' && ok "destroy_history warns about LFS and still reports" || bad "lfs warn ($out2)"
# a linked worktree holding an ignored (possible secret) file blocks the wipe until it is dealt with
W="$T/wtsec"; git init -q -b main "$W"; echo a > "$W/a.txt"; echo .env > "$W/.gitignore"; git -C "$W" add -A; git -C "$W" commit -q -m one
git -C "$W" branch side; git -C "$W" worktree add -q "$T/wtsec-wt" side; echo KEY=1 > "$T/wtsec-wt/.env"
git -C "$W" checkout -q --orphan tmp; git -C "$W" add -A; git -C "$W" commit -q -m "Initial commit"; git -C "$W" branch -M reset
out4="$(cd "$W" && "$D" 2>&1)"; rc4=$?
[ "$rc4" -eq 2 ] && has "$out4" 'REFUSED: linked worktree' && ok "destroy_history refuses a worktree holding ignored files" || bad "worktree secret refusal ($rc4 $out4)"
check "refusal names the worktree it blocked on" bash -c "echo '$out4' | grep -q wtsec-wt"
check "worktree and its ignored file untouched after refusal" test -f "$T/wtsec-wt/.env"
mv "$T/wtsec-wt/.env" "$W/.env"
out5="$(cd "$W" && "$D" 2>&1)"; has "$out5" 'HISTORY_DESTROYED' && ok "destroy_history proceeds once the secret is in the root" || bad "after move ($out5)"
check "the moved secret survives" test "$(cat "$W/.env")" = "KEY=1"

# repo that never had branch config sections or a remote (the common case)
N="$T/plain"; git init -q -b main "$N"; echo a > "$N/a.txt"; git -C "$N" add -A; git -C "$N" commit -q -m one
git -C "$N" checkout -q --orphan tmp; git -C "$N" add -A; git -C "$N" commit -q -m "Initial commit"; git -C "$N" branch -M reset
out3="$(cd "$N" && "$D" 2>&1)"; has "$out3" 'HISTORY_DESTROYED' && ok "destroy_history works with no branch config or remote" || bad "plain repo ($out3)"
check "ignored secret file untouched" test "$(cat "$H/.env")" = "SECRETFILE"

check "token format is documented" grep -q 'exactly 16 lowercase hex' "$ROOT/SKILL.md"
check "gate runs a new dry run when the report is gone" grep -q 'run a new dry run and stop' "$ROOT/SKILL.md"
check "no ripgrep-only flag in the search guide" test -z "$(grep -r -e '--max-filesize' "$ROOT/SKILL.md" "$ROOT/references" || true)"
check "line| token section documented" grep -q 'line|<absolute path>|<exact line text>' "$ROOT/SKILL.md"
check "keep| token section documented" grep -q "keep|<absolute path>" "$ROOT/SKILL.md"
# 12. hardening: odd file names, linked-worktree invocation, stale worktree records, bare repos
Q="$T/quote"; git init -q -b main "$Q"; printf 'q1\n' > "$Q/"'"q".py'; printf 'z\n' > "$Q/zz.txt"; git -C "$Q" add -A; git -C "$Q" -c user.name=t -c user.email=t@t commit -q -m a
printf 'm1\n' >> "$Q/zz.txt"; q1="$("$F" "$Q" </dev/null)"; printf 'm2\n' >> "$Q/zz.txt"; q2="$("$F" "$Q" </dev/null)"
[ -n "$q1" ] && [ "$q1" != "$q2" ] && ok "token sees edits after a file named with a double quote" || bad "quoted name blinds token ($q1 $q2)"
printf 'nl\n' > "$Q/a
b.txt"; n1="$("$F" "$Q" </dev/null)"; printf 'nl2\n' > "$Q/a
b.txt"; n2="$("$F" "$Q" </dev/null)"
[ "$n1" != "$n2" ] && ok "token sees edits to a file with a newline in its name" || bad "newline name"

M="$T/mainco"; git init -q -b main "$M"; echo code > "$M/a.txt"; echo SECRET > "$M/.env"; echo .env > "$M/.gitignore"; git -C "$M" add -A; git -C "$M" commit -q -m one
git -C "$M" worktree add -q --orphan -b reset "$T/linked" 2>/dev/null; echo x > "$T/linked/f.txt"; git -C "$T/linked" add -A; git -C "$T/linked" commit -q -m "Initial commit"
out6="$(cd "$T/linked" && "$D" 2>&1)"; rc6=$?
[ "$rc6" -ne 0 ] && has "$out6" 'REFUSED: run this from the main checkout' && ok "destroy_history refuses to run from a linked worktree" || bad "linked invocation ($rc6 $out6)"
check "main checkout and its secret intact after that refusal" bash -c "test -f '$M/.env' && test -d '$M/.git'"

S1="$T/stale"; git init -q -b main "$S1"; echo a > "$S1/a"; git -C "$S1" add -A; git -C "$S1" commit -q -m one; git -C "$S1" branch side; git -C "$S1" worktree add -q "$T/stalewt" side
mv "$T/stalewt" "$T/stalewt-moved"; mkdir "$T/stalewt"; echo mine > "$T/stalewt/important.txt"
git -C "$S1" checkout -q --orphan tmp; git -C "$S1" add -A; git -C "$S1" commit -q -m "Initial commit"; git -C "$S1" branch -M reset
out7="$(cd "$S1" && "$D" 2>&1)"; has "$out7" 'HISTORY_DESTROYED' && ok "destroy_history survives a stale worktree record" || bad "stale record ($out7)"
check "unrelated folder at a stale worktree path is kept" test "$(cat "$T/stalewt/important.txt")" = "mine"

U="$T/untr"; git init -q -b main "$U"; echo a > "$U/a"; git -C "$U" add -A; git -C "$U" commit -q -m one; git -C "$U" branch side; git -C "$U" worktree add -q "$T/untrwt" side
echo keepme > "$T/untrwt/notes.txt"
git -C "$U" checkout -q --orphan tmp; git -C "$U" add -A; git -C "$U" commit -q -m "Initial commit"; git -C "$U" branch -M reset
out8="$(cd "$U" && "$D" 2>&1)"; has "$out8" 'HISTORY_DESTROYED' && has "$out8" 'LEFT in' && ok "untracked files in a worktree are listed, not deleted" || bad "untracked left ($out8)"
check "untracked worktree file still on disk" test -f "$T/untrwt/notes.txt"
check "tracked worktree files removed" test ! -f "$T/untrwt/a"

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
