# context-bleach 🧪🫧

> ## ⚠️ CAUTION
>
> **Use at your own risk.** The real run deletes files, agent memory, transcripts, data, and local git history. There are no backups, no trash, and no undo.
>
> It always starts as a **read-only dry run**. The real run needs a token from that dry run and refuses to start if anything changed since. It never pushes and never touches the remote, so GitHub keeps its history until you decide otherwise.
>
> Read the dry-run report before you send the token. Try it on a throwaway repo first.

sometimes a project needs to be forgotten.

The symptom: progress just stops, and you can't say why. Old docs, old comments, old agent memory, and old history keep pulling the agent back.

context-bleach is an agent-agnostic skill that resets a project to only the code it needs to work.

```text
dry run → report → token → execute
docs, comments, agent memory, transcripts, local history → gone
secrets stay
```

It purges docs, comments, agent memory and transcripts, caches, data, and local git history (one orphan commit). It also renames biased internal names. Secrets, keys, wallets, env files, lockfiles, and anything the code needs to run stay.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/context-bleach/main/install.sh | bash
```

The skill is plain `SKILL.md` + `scripts/` + `references/`. Any agent that reads skill folders can use it. The installer writes to every agent home it finds:

| Agent | Path |
| --- | --- |
| Shared / Codex / generic | `~/.agents/skills/context-bleach` (always; `CODEX_SKILLS_HOME` overrides) |
| Claude Code | `~/.claude/skills/context-bleach` (if `~/.claude` exists) |
| Prime Agent | `~/.prime/agent/skills/context-bleach` (if present) |
| Hermes | `~/.hermes/skills/software-development/context-bleach` (if present) |
| Gemini CLI, OpenCode, Cursor | best effort, **opt-in only**: `CONTEXT_BLEACH_TARGETS=gemini,opencode,cursor` |

The skill stays visible to the agent, so plain `context-bleach` works. The safety rails are the dry run, the token that only you can send, and the description that says to use it only when named. A stray trigger can only produce a read-only report.

Options (environment variables):

```bash
# only some agents
curl -fsSL .../install.sh | CONTEXT_BLEACH_TARGETS=claude,codex bash
# one explicit folder, for example project scope
curl -fsSL .../install.sh | CONTEXT_BLEACH_DEST="$PWD/.claude/skills/context-bleach" bash
# pin an exact commit
curl -fsSL .../install.sh | CONTEXT_BLEACH_COMMIT=<40-hex-sha> bash
# uninstall
curl -fsSL .../install.sh | bash -s -- --uninstall
```

For an agent without a skills folder, paste `SKILL.md` into its prompt. It needs a shell, file access, and git.

Restart or refresh the agent after install. Then say `context-bleach` for a dry run.

| Agent | Invoke |
| --- | --- |
| Claude Code | `/context-bleach` or plain `context-bleach` |
| Codex | `$context-bleach` (explicit mention; implicit use is off in `agents/openai.yaml`) |
| Prime Agent | `/skill:context-bleach` or plain `context-bleach` |
| Others | name the skill, or paste `SKILL.md` into the prompt |

## Use

**1. Dry run.** In the project, say:

```text
context-bleach
include: sqlite at ~/data/app.db
exclude: redis on localhost:6379
```

(`include:` and `exclude:` lines are optional.) The agent changes nothing. It prints:

- the scope manifest: root, datastores, containers, processes, harness stores, each `in scope`, `left alone`, or `skipped`
- the baseline command (not run), KEEP paths, every file it would delete, every rename, the git refs it would destroy, the tables it would truncate
- one `left alone` list
- a **token**

**2. Read the report.** Fix scope with `include:` and `exclude:` and dry-run again if it is wrong.

**3. Execute.** Send the token back:

```text
context-bleach execute 3f9a1c2b7d4e8a10
```

The agent recomputes the token. If the repo, refs, working tree, or scope changed, it stops and prints a new report. If it matches, it runs the full procedure with no further questions: stop processes, make or reuse branch `reset`, checkpoint, baseline, purge and rename, prove the baseline, rewrite local history to one orphan commit, report in chat, stop. It asks only about an unclear secret or wallet.

The root is the git top level of the current directory. It stops if that is not a git repo, a home directory, a filesystem root, or a folder with other projects' repos.

## Updates

Every run (dry or execute) starts with:

```bash
~/.claude/skills/context-bleach/scripts/update_check.sh --apply
```

(Use the path of the copy your agent loaded.)

| Output | Meaning |
| --- | --- |
| `UP_TO_DATE` | Nothing to do. |
| `UPDATED` | A new payload was fetched and swapped in. The agent rereads `SKILL.md`. |
| `LOCAL_DIRTY` | You edited the installed copy. It is kept. `--force` overwrites it (user approval only). |
| `UNMANAGED` | No install metadata. No self-update. |
| `ERROR reason=...` | Check failed (offline, rate limit). The installed copy is used. |

The installer records the source, ref, commit, and a SHA-256 of every file in `.context-bleach-install.json`. The updater compares the installed commit with `git ls-remote` (falls back to the GitHub API), then re-runs the installer pinned to the latest commit. The swap is staged, so a failed fetch leaves the old copy in place.

Set `CONTEXT_BLEACH_NO_UPDATE=1` to turn the check off. Re-running the install command also updates.

## Layout

```text
SKILL.md                      the procedure (single source of truth)
references/harness-locations.md   where agents keep per-project traces
scripts/update_check.sh       version check and self-update
scripts/fingerprint.sh        token for the dry-run to execute gate
agents/openai.yaml            Codex metadata (implicit invocation off)
install.sh                    curl | bash installer
tests/test_install.sh         sandbox tests for install and update
```

## Test

```bash
bash tests/test_install.sh
```

## License

MIT
