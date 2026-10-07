# context-bleach

An agent-agnostic skill that resets a project to only the code it needs to work.

It purges docs, comments, agent memory and transcripts, caches, data, and local git history (one orphan commit). It also renames biased internal names.

> **This is destructive and irreversible.** No backups. No trash. The skill runs only when you name it (`context-bleach`). It pauses once, for three scope questions, before it changes anything. It never pushes and never touches the remote.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sirouk/context-bleach/main/install.sh | bash
```

The skill is plain `SKILL.md` + `scripts/` + `references/`. Any agent that reads skill folders can use it. The installer writes to every agent home it finds:

| Agent | Path |
| --- | --- |
| Claude Code | `~/.claude/skills/context-bleach` |
| Codex CLI | `~/.codex/skills/context-bleach` |
| Shared / generic | `~/.agents/skills/context-bleach` (always) |
| Prime Agent | `~/.prime/agent/skills/context-bleach` |
| Gemini CLI | `~/.gemini/skills/context-bleach` |
| OpenCode | `~/.config/opencode/skills/context-bleach` |
| Cursor | `~/.cursor/skills/context-bleach` |
| Hermes | `~/.hermes/skills/software-development/context-bleach` |

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

Restart or refresh the agent after install. Then say `context-bleach` (Codex: `$context-bleach`).

## Use

Open the agent in the project and say:

```text
context-bleach this project
```

Flow:

1. The agent does read-only discovery.
2. It shows you three things and waits: the project root, the datastores, the agent harnesses with traces.
3. You answer. Scope is now fixed. It does not ask again, except for an unclear secret or wallet.
4. It stops processes, makes branch `reset`, runs a baseline, purges and renames, proves the baseline again, then rewrites local history to one orphan commit.
5. It prints the report in chat only and stops.

## Updates

Every run starts with:

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
