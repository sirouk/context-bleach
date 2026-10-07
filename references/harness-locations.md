# Where agent harnesses keep project traces

A search guide for Phase 0, question 3. It is not a complete list. Search the real machine. Tools change their layout, and new tools appear.

Two kinds of trace exist:

- **Inside the project root**: instruction files and agent folders. Safe to find with `find`.
- **In the user's home directory**: per-project memories, transcripts, plans, todos, indexes. These are keyed by the project path, by a hash of it, or by a slug of it.

## How to find them

1. Get the absolute project root, and its path with `/` replaced by `-`, `_`, or `%2F`. Also get the repo name and the git remote URL.
2. For each home directory below, grep for those strings. Search file names and file contents.

```bash
# names that embed the path
find ~ -maxdepth 6 \( -name "*<slug>*" -o -name "*<repo-name>*" \) -not -path "<project-root>/*" 2>/dev/null
# contents that mention the path
grep -rIl --exclude-dir=node_modules --exclude-dir=.git "<project-root>" <harness-home> 2>/dev/null
```

Do not follow symlinks out of the harness home. Do not match on a short repo name alone if it is common. Confirm the match.

## Inside the project root

| Kind | Typical paths |
| --- | --- |
| Instruction files | `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules`, `CONVENTIONS.md`, `.github/copilot-instructions.md`, `.junie/guidelines.md`, `.rules` |
| Agent folders | `.claude/`, `.codex/`, `.agents/`, `.cursor/`, `.windsurf/`, `.gemini/`, `.opencode/`, `.aider*`, `.continue/`, `.cline/`, `.roo/`, `.kilocode/`, `.prime/`, `.hermes/`, `.goose/`, `.amazonq/`, `.augment/`, `.zed/`, `.trae/` |
| Plans and scratch | `PLAN.md`, `TODO.md`, `NOTES.md`, `SCRATCH*`, `.deep-solve/`, `.deep-solve-prep/` |
| Indexes | `.serena/`, `.code-graph*`, `.codegraph/`, `.sourcegraph/`, `.aider.tags.cache*`, embeddings or vector files |

Project-level agent folders may hold a copy of this skill. It is a trace too, but read this skill fully first (see SKILL.md).

## In the home directory

| Harness | Where it usually keeps project state |
| --- | --- |
| Claude Code | `~/.claude/projects/<path-slug>/` (transcripts, per-project memory), `~/.claude/todos/`, `~/.claude/plans/`, `~/.claude/shell-snapshots/`, `~/.claude/file-history/`, `~/.claude/ide/`, project entries in `~/.claude.json` |
| Codex CLI | `~/.codex/sessions/`, `~/.codex/history.jsonl`, `~/.codex/memories/`, project trust entries in `~/.codex/config.toml` |
| Gemini CLI | `~/.gemini/tmp/<project-hash>/`, `~/.gemini/history/` |
| Prime Agent | `~/.prime/agent/sessions/`, `~/.prime/agent/harness/` (memories and notes), `~/.prime/agent/session-artifacts/` |
| Hermes | `~/.hermes/sessions/`, `~/.hermes/memories/` |
| OpenCode | `~/.local/share/opencode/`, `~/.config/opencode/` |
| Cursor | `~/.cursor/`, workspace storage under `~/.config/Cursor/User/workspaceStorage/` (Linux) or `~/Library/Application Support/Cursor/User/workspaceStorage/` (macOS) |
| Windsurf, Cline, Roo, Continue, Kilo | extension storage under the editor's `User/globalStorage/` and `workspaceStorage/`, and `~/.continue/` |
| Aider | `.aider.chat.history.md`, `.aider.input.history` (in the project or a parent directory) |
| Copilot, Zed, JetBrains | editor `workspaceStorage`, `~/.config/zed/`, `.idea/` local history |
| Generic | `~/.agents/`, `~/.config/*/`, `~/.local/share/*/`, `~/.cache/*/` entries that name the project |

## Global files

Global instruction files (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, global memories) stay. Remove only the lines, entries, or memory items that mention this project. Do not touch other projects' entries.

## The live session

The running agent's own transcript cannot be emptied while it is open. Print its path in the final report so the user can delete it after the session closes. If you cannot tell which file it is, say so and list the newest candidates.
