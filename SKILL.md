---
name: context-bleach
description: "Irreversibly reset a project to its working code only: purge all docs, comments, agent context (memories, transcripts, instruction files), dead code, caches, data, and local git history into one orphan commit, and rename biased internal names. Always starts as a read-only dry run that prints a report and a token; the real run needs that token. Destructive, no backups. Use ONLY when the user explicitly names it: \"context-bleach\", \"bleach this project\", or \"fresh mind body and soul\". Never use it implicitly."
---

# Context Bleach

Reset one project to only the code it needs to work. Remove every trace of its past: docs, comments, agent memory, transcripts, caches, data, and local git history.

This skill is **destructive and irreversible**. There are no backups, no archives, no "moved to /old", and no trash. Delete means gone.

Use it only when the user explicitly asks for it by name. Never start it from a loose request like "clean up this repo".

This skill works with any coding agent. It needs a shell, file access, and git. Where it says "subagent", see [Doubt](#doubt).

## Freshness

Run the updater once, at the start, before discovery. Never run it again later in the job.

```bash
<skill-directory>/scripts/update_check.sh --apply
```

Find `<skill-directory>` from the path of this `SKILL.md`, not from the project.

The updater changes only the skill's own install folder, never the project. It is allowed in a dry run. In execute mode, never use `--apply` (see the [Execute gate](#execute-gate)). **Exception:** if the skill folder is inside the project root, run it without `--apply` (check only). An update there would change the working tree and break the token.

- `UP_TO_DATE`: continue.
- `UPDATED`: read the new `SKILL.md` and `references/` again in full, then continue.
- `UPDATE_AVAILABLE` (check only, or `--apply` could not finish): continue with the installed copy and say a newer version exists.
- `LOCAL_DIRTY`: keep the installed copy, do not use `--force`, and continue.
- `DISABLED`, `UNMANAGED`, `ERROR`, or a missing script: continue with the installed copy.

Say nothing about freshness unless the result is `UPDATED`, `UPDATE_AVAILABLE`, or `LOCAL_DIRTY`.

Read this whole file and [references/harness-locations.md](references/harness-locations.md) before you change anything. Step 4 or the cleanup may delete project-level agent folders. If this skill was installed inside the project, it may disappear mid-run. Do not depend on re-reading it.

## Modes

The dry run always comes first. The real run never starts without a token from a dry run of the same state.

| The user says | Mode | What happens |
| --- | --- | --- |
| `context-bleach` | **dry run** (default) | Read-only. Prints the full report and a token, then stops. |
| `context-bleach execute <token>` | **execute** | Recomputes the token. If it matches, runs the full procedure. If not, stops and changes nothing. |

A mismatched token ends with a fresh dry-run report and nothing else. The fresh report carries a new token for the user to send; printing it is fine, using it yourself is not. It never leads into execute mode by itself.

Execute mode has exactly the same rules, steps, KEEP list, and DONE checks as before. The dry run only adds a gate in front of it. Nothing is relaxed.

A token is exactly 16 lowercase hex characters. If the user says `execute` with no token, or with anything else, treat it as a dry run and tell them a token is needed.

**The token must come from the user's own message.** Never supply, guess, or reuse a token yourself, even one you printed earlier in the same turn. Never chain a dry run into execute mode on your own. A stray trigger of this skill can therefore only produce a read-only report.

## Hard rules

- Nothing recoverable survives the run: no backups, no archives, no "moved to /old", no trash. Delete means gone.
- Do not commit to any existing branch, except `reset` when it already exists from an earlier run.
- Do not push.
- Do not delete or rewrite anything on the remote.
- Do not write notes, plans, reports, or memories to disk at any point. Report in chat only.
- Never run `git clean -x` or any ignore-based cleanup. Many secrets are gitignored and untracked.
- Do not touch anything outside SCOPE.
- **A dry run changes nothing** in the project or on the machine. No branch, no file, no stopped process, no baseline run, no dependency install. The one allowed write is the skill updater changing the skill's own install folder (see [Freshness](#freshness)).

## Invocation

The user's message may carry `include:` and `exclude:` lines after the skill name.

- An `include:` line adds a named datastore, host, or path to scope.
- An `exclude:` line removes one that the rules would otherwise take.
- When there are none, the ownership rules below decide.

## Phase 0: discovery and manifest

Do read-only discovery first. Change nothing.

Then print **one scope manifest**. Do not put questions in the manifest.

- In **dry-run** mode, go on to [Dry run report](#dry-run-report) and stop.
- In **execute** mode, pass the [Execute gate](#execute-gate), then continue without waiting.

### Ownership rules

- **Root**: the git top level of the directory where this was invoked.
  - If the directory is not inside a git repository, stop without acting and say so.
  - If that top level is a home directory, a filesystem root, or contains other projects' repositories, stop without acting and say so. Check for nested repos with `find <root> -mindepth 2 -name .git -not -path '*/node_modules/*'`, then drop submodules (`git submodule status`) and any path git ignores (`git check-ignore`). Only a full separate repo counts.
- **Processes**: a process belongs to the project if its working directory, script path, or command line is under the root. This includes paths under the root that have since been deleted. It also belongs if a PM2, systemd, cron, or compose entry points into the root.
  - Agent harnesses, editors and their servers, and the agent's own process tree never belong, even when running inside the root.
  - Your own tree is your shell, your agent process, and their parents and children. A process whose parent chain (`ps -o ppid=`) leads to your agent runtime (the program that launched you), including its other REPL or tool processes, is yours. Anything else under the root that you cannot tie to the project is left and listed, not stopped.
  - Anything that cannot be linked is left and listed.
  - How to check: `ps` for command lines and `ls -l /proc/*/cwd` (Linux) or `lsof -d cwd` (macOS) for working directories under the root, including `(deleted)` ones; plus PM2, systemd, cron, and compose definitions.
- **Containers, images, volumes**: they belong if built from a Dockerfile or compose file in the root.
  - Proof of ownership: `docker inspect` shows a bind mount, a compose `working_dir` or project label, or an image build context under the root. Check every container with one command, for example `docker ps -aq | xargs -r docker inspect | grep -c '<root>'`. This is cheap; do not skip it because the root has no Dockerfile. No match means not linked: leave it and list the count.
  - A container is a datastore only if it runs a database, cache, or queue engine. Any other container is an application process: stop it in step 1, remove it in step 4.
  - Remove images and volumes if they can be rebuilt from that code and hold no KEEP data or secrets. Otherwise leave them and list them.
- **Datastores**: local files and loopback services that the project's code or env files create or connect to are in scope, wherever they sit on disk.
  - Resolve the paths from the code, not only from env files.
  - A datastore on another host is skipped and listed, unless named at invocation.
  - State held by external services is never touched. This includes exchange orders and positions and hosted accounts. List what the code is able to create there.
  - Never show credentials. Name datastores by host and name only. For secret files, print the path only: no contents and no key names.
- **Harness stores**: open every harness and editor store on the machine before ruling on it. Use [references/harness-locations.md](references/harness-locations.md) as a search guide. Search the real machine, one harness home at a time, with a timeout. Never grep the whole home directory. Do not trust the list.
  - A session whose working directory was the root is deleted whole.
  - A session from another project that only mentions this one is left and listed.
  - In global memory, remove only the entries that mention this project.
  - Name this live session's own transcript path under **left alone** in the dry run too.
  - Editor workspace storage and local history keyed to the root are in scope.

### Manifest and report layout

The manifest and the final report use the same layout: short labelled sections, one plain sentence per item, verdict first.

- Sections: **root**, **datastores**, **containers**, **processes**, **harness stores**.
- Each item gets a verdict (`in scope`, `left alone`, or `skipped`) and a one-clause reason.
- There is no "problems to decide" section. Everything uncertain goes in a single **left alone** list.
- The final report is the manifest sections followed by the DONE checks. Each check is one plain sentence followed by the command output that proves it.

## Dry run report

After the manifest, print these sections. Everything is a plan, not an action. Never print secret contents; print secret paths only.

1. **Baseline**: the entrypoints and the command that would prove the project works, and what it would and would not exercise. Say whether it would load prompts, job names, serialized type names, Dockerfiles, CI, or cron definitions. Do **not** run it. If you cannot find a baseline, say **BLOCKED: no baseline**. Execute mode will not start without one.
2. **KEEP**: the secret, key, wallet, certificate, and env file paths that would be kept. Mark any that are tracked by git (they would be untracked in step 2).
3. **Would delete**: docs files, agent-context paths, logs and caches and artifacts, dead-code candidates (with how you decided they are unreachable), and sample or fixture files nothing reads. Give counts and the full paths. Count the files that carry comments to strip. Every path listed here becomes a `delete|` line in the token inputs.
4. **Would rename**: each biased or overfit internal name, old to new, with the role the new name states. Name the external contract names you will not rename. Every old name listed here becomes a `rename|` line in the token inputs (old name only).
5. **Would stop**: the processes, workers, cron jobs, and schedulers from step 1.
6. **Git**: current branch and HEAD, whether the tree is dirty (if so, list every changed and untracked file: uncommitted work in the root is folded into the single commit and the report must show it), whether `reset` already exists. List every local branch (the current one included), tag, stash, note, and remote-tracking ref. List every linked worktree with its path, every uncommitted or untracked file in it, and every gitignored file in it (possible secrets). Uncommitted work in a linked worktree is deleted with the worktree: it is not folded into the single commit. Show it in the report so the user sees it. All are destroyed except `reset`, which is replaced by the orphan commit. Show the `git ls-remote` output, or "no remote".
7. **Data**: the in-scope tables that would be truncated and the tables kept, and the cache, queue, and vector-store keys that would be flushed. Each becomes a `truncate|` line in the token inputs.
8. **Left alone**: one list of everything uncertain, not linked, or skipped, each with a reason.
9. **Token inputs, token, and command**: the exact lines fed to `fingerprint.sh`, the token, and the exact line the user sends to proceed.

Compute the token like this (see [Token](#token)):

```bash
printf '%s\n' "datastore|host/name" "harness|/abs/path" ... | <skill-directory>/scripts/fingerprint.sh <root>
```

End the report with:

> Read this report. To run it for real, send: `context-bleach execute <token>` (repeat any include:/exclude: lines). Nothing has been changed.

Then stop. Do not start step 1.

### Token

`fingerprint.sh` builds in, with no input: the root, HEAD, branch, all refs, stashes, remotes, the installed skill commit, a hash of the **contents** of every tracked and untracked (non-ignored) file, and the same for every linked worktree of this repo. Editing any of those files changes the token. It does **not** hash gitignored files (secrets, `node_modules`, datastore contents) or global files outside the root; those change too often or are too large. The plan lines below pin what gets deleted, truncated, or edited there.

You feed it the plan, one line per item, as `<section>|<stable id>`. Use exactly these rules so a second run finds the same lines:

- `datastore|<host>/<name>` for each in-scope datastore, or `datastore|<absolute path>` for a local file.
- `container|<container name>` for each container in scope.
- `process|<absolute path of its script or working directory>` for each process to stop.
- `harness|<absolute path>` for each in-scope store **outside the root** that is deleted whole: the store directory (for example `~/.claude/projects/<slug>`), not individual transcript files. A global file that only loses lines gets `line|` lines instead. Files inside the root are covered by the built-in contents hash.
- `delete|<absolute path>` for each file or folder the plan deletes. For a whole folder, list the folder, not its files. Worktrees, branches, tags, and stashes need no lines: the built-in hash of the refs and worktrees covers them.
- `rename|<old name>` for each internal name the plan renames. **Do not include the new name.** Agents choose new names differently between runs, and that would break the token.
- `truncate|<store>/<table>` for each table the plan truncates or key prefix it flushes. A datastore file deleted whole gets a `datastore|` line and a `delete|` line, and no `truncate|` lines.
- `line|<absolute path>|<exact line text>` for each line the plan removes from a global file that stays (global instructions or memory). Global files are not content-hashed: they change whenever other sessions run. These lines pin which lines go.
- `keep|<absolute path>` for each secret, key, wallet, certificate, and env file the plan keeps. Execute mode checks staged paths against exactly this list, so it must not be rebuilt later.
- `include|<line>` and `exclude|<line>` for each invocation line, verbatim.
- Never use PIDs, timestamps, counts, or the live session's own transcript.

Print the exact lines you fed in as a **Token inputs** block in the report.

Usage: `printf '%s\n' "<line>" "<line>" | <skill-directory>/scripts/fingerprint.sh <root>` prints the token. Add `--lines` after the root to print the canonical lines instead. With no plan lines, use `fingerprint.sh <root> </dev/null`.

## Execute gate

In execute mode, before step 1:

1. **Freeze the skill.** Run `update_check.sh` **without** `--apply` (check only). Never update the skill between the report and the run: the token pins the installed skill commit. If the check says a newer version exists, continue with the installed copy and say so once, in the manifest.
2. Run discovery and the manifest again, with the same `include:` and `exclude:` lines.
3. **Replay the plan.** If the dry-run report is in this conversation, take its `keep`, `delete`, `rename`, `truncate`, `line`, `datastore`, `container`, `process`, and `harness` lines from the **Token inputs** block verbatim. Do not re-derive them. If the report is not in this conversation, or its **Token inputs** block is no longer there word for word (a new session, or it was compacted away), do not guess and do not re-derive: run a new dry run and stop. The user then sends `execute` with the new token.
4. Recompute the token with `scripts/fingerprint.sh <root>`, feeding those lines. Do this now: the skill folder may be inside the project and be deleted later.
5. Compare it with the user's token.
   - **Match**: print the manifest and continue to ORDER. Do not ask.
   - **Mismatch, or the script is missing**: stop. Change nothing. Say what differs: print `fingerprint.sh <root> --lines` and `git status --short` for the root and each linked worktree, then print a **full fresh dry-run report** (all nine sections, with a Token inputs block that includes any new files as `delete|` lines) and its new token, and wait for a new `execute`.
6. If the dry run said **BLOCKED: no baseline**, stop.

**Act only on the plan.** In execute mode, delete, rename, and truncate only targets that are in the token. Anything newly found goes to **left alone**.

In execute mode, set SCOPE from the manifest and proceed. Do not ask, except for the secret-or-wallet case in [Doubt](#doubt).

## SCOPE

Anything outside this is not yours to touch.

- **Project root**: the git top level ruled in by the ownership rules.
- **Databases and stores**: the datastores ruled in scope.
- **Git remote**: leave the remote and its URL. The only remote contact allowed is the read-only `git ls-remote` (in both modes). If it cannot reach the remote, record that as the result and continue. Do not fetch, push, force-push, or delete remote branches, tags, or PRs. Remote history stays until a human decides otherwise. Local remote-tracking refs are in scope and will be deleted.
- **Linked worktrees**: every linked worktree of this repo is in scope, even one that sits outside the root. List each in the dry run with its path and its uncommitted and ignored files. They are removed in step 6, except that possible secrets inside them are moved to the root first.
- **Working branch**: create and check out local branch `reset` from the current HEAD before any purge. If `reset` already exists from an earlier run, continue on it. It is the one existing branch you may commit to. All edits and the history rewrite happen only on `reset`.
- **Agent harnesses**: the stores ruled in scope.

When a step's precondition does not exist, record that as the step's result and continue. No commits means `reset` starts unborn. No remote means the recorded state is "no remote", and the final check is that there is still none.

## ORDER

Execute mode only.

1. **Stop** every application process, worker, cron job, and scheduler that the ownership rules assign to this project. Leave its datastores running. Leave harnesses, editors, and this agent's process tree running. Keep the list; you must report it.
2. **Record and checkpoint.**
   - Record the current branch and HEAD.
   - Run `git ls-remote` and keep its output in context, or record "no remote".
   - Create local branch `reset` from that HEAD and check it out, or continue on it if it already exists.
   - Before any commit, confirm every secret file (the first KEEP item) is ignored by git. Add an ignore rule if one is not. Untrack any that is already tracked, without deleting the file.
   - Commit the starting tree to `reset` so later edits can be diffed and reverted. If the tree is clean there is nothing to commit: skip the commit and say so (`reset` then points at the starting HEAD, which is the checkpoint). If git has no identity configured, pass one with `-c user.name=... -c user.email=...` for this commit only. Do not change git config. No secret may enter any commit, including the final one. Before every commit, check that `git diff --cached --name-only` shares no path with the `keep|` secret list from the token inputs. If it does, unstage that path and stop the commit.
   - Do not delete branches, tags, stashes, or remote-tracking refs yet.
3. **Baseline.** Find the entrypoints and the command that proves the project works. Entrypoints are: manifest scripts and bins, Dockerfile and compose commands, process-manager and service definitions, CI workflow commands, cron entries, Makefile targets, and whatever was running in step 1. Code reachable from any of them is not dead. Then find the command (tests, build, or smoke run). Reinstall dependencies from the lockfile, or from the dependency manifest if there is no lockfile, if the baseline needs them. If no test or build command exists, use the smallest smoke run that imports and calls the entrypoint; the dry run states which. Run it. You may adapt the interpreter or runner name to what exists on this machine (for example `python3` for `python`) without changing what the command tests. This baseline is the only definition of "necessary code". Failures that exist before the purge are recorded, not fixed. The bar is no new failures.
4. **Purge and rename** on `reset`. See [KEEP](#keep), [RENAME](#rename-internal-only-after-the-baseline-is-known), and [PURGE](#completely-purge).
5. **Proof.** Reinstall dependencies the same way if the baseline needs them. Re-run the baseline, then delete whatever it generated, including those dependencies. This run is the proof. Do not run the baseline again after the history rewrite or the final cleanup.
   - If it shows new failures, fix forward using the step 2 checkpoint. Do not start step 6 until there are none.
   - If that cannot be done, stop with history intact and report.
6. **Destroy local history**, on `reset` only:
   - create a single orphan commit with a neutral message and a **neutral author and committer identity** (for example `git -c user.name=reset -c user.email=reset@localhost commit`). Do not use the user's name or email: that is a trace
   - make `reset` point at it (for example `git checkout --orphan tmp`, commit, then `git branch -M reset`)
   - then run `<skill-directory>/scripts/destroy_history.sh` from the project root. If the skill folder is inside the project, copy this script to a temporary file outside the project **before step 4** (the purge deletes project-level agent folders), run it from there, and delete the copy right after. It removes every linked worktree (folder included), every ref except `refs/heads/reset`, stashes, the branch sections in `.git/config`, `ORIG_HEAD` and `FETCH_HEAD`, reflogs, and every unreachable object. It keeps the remote URL, and it refuses to run unless the branch is `reset` with one commit
   - if it refuses because a linked worktree holds gitignored files, treat each one as a possible secret: move real secrets to the same relative path under the root (if the root has none there; otherwise stop and list it under **left alone**), delete the rest, then run it again. Never delete a possible secret to get past this
   - it prints `HISTORY_DESTROYED` and the proof. Show that output. It may also print `WARN` lines for Git LFS objects or submodule stores it cannot safely remove: list each under **left alone**
   - if it prints `HISTORY_NOT_CLEAN` or refuses, stop and report
   - the step 2 checkpoint does not survive this step
   - do not push
   - no secret may enter this commit
7. **Verify and report** in chat only. Do not run the baseline again.

## KEEP

- All keys, secrets, wallets, keypairs, certificates, env files, and yaml/toml/json files used for auth. Most are gitignored and untracked. **If you cannot tell whether a file is a secret, it is a secret.** A secret stays even if no code reads it.
- Code reachable from the entrypoints. Delete the rest.
- Schema and migrations, the migration-tracking table, and the seed or lookup rows the code needs to boot.
- Lockfiles, dependency manifests (`requirements.txt`, `package.json`, `go.mod`, and the like), and LICENSE files.
- CI workflows (`.github/workflows`, `.gitlab-ci.yml`, and the like), `CODEOWNERS`, and deploy and service definitions (Dockerfiles, compose files, systemd units, Procfiles, Helm charts, and the like). Strip their comments; keep the files.
- `SPDX-License-Identifier` lines, copyright headers, and license notices in source files.
- Generated code that is tracked and imported by kept code.
- Ignore files that keep secrets out of commits (`.gitignore`, `.dockerignore`). Keep the rules, strip only the comments. Drop a rule only if it names an agent folder or file you purged and nothing else in the repo needs it.
- Comments the toolchain executes: shebangs, build tags, pragmas, type and lint directives, encoding lines.
- Text that is runtime behavior even if it looks like docs: prompts, skill and agent definition files, templates, and docstrings read at runtime for CLI help, API schemas, or tool descriptions. Do not edit the text of prompts, templates, or runtime-read docstrings. Only remove code comments around them.
- Every externally visible contract name: env var names, config keys, table and column names, routes, CLI flags, payload fields, and any name a migration or external client already depends on. Do not rename these.

## RENAME (internal only, after the baseline is known)

- Rename identifiers, types, modules, and files whose names are overfit or biased. Examples: persona labels, moral framing, mythology, a single historical incident, a temporary hypothesis, or a name that asserts a conclusion the code does not enforce.
- The new name must say the specific role: what it stores, computes, checks, or returns.
- Banned replacements: `data`, `info`, `item`, `thing`, `helper`, `util`, `manager`, `handler`, `processor`, `common`, `misc`, `temp`, `foo`, and any name vaguer than the one it replaced.
- Do not rename a symbol just to look neutral. If the current name is already the precise technical role, leave it.
- Update every reference in the same change. This includes strings and non-code files: dynamic imports, reflection, task and job names, serialized type names, package manifests, Dockerfiles, CI, and service or cron definitions.
- Do not rename the root directory, the repo name, or the git remote. They are outside the purge of identifiers.
- A rename that does not leave the baseline passing is not done.

## COMPLETELY PURGE

- **All documentation**: READMEs, docs folders, changelogs, ADRs, roadmaps, plans, TODO files, notes, diagrams, wikis.
- **All comments and docstrings not in KEEP**, including commented-out code and TODO/FIXME. This covers comments in config, SQL, shell, Dockerfiles, and CI files.
- **Agent context ruled in scope**: instruction files (`CLAUDE.md`, `AGENTS.md`, rules files), project-level agent folders, sessions whose working directory was the root, plans, todo lists, scratchpads, code graphs, indexes, embeddings, and editor workspace storage and local history keyed to the root.
  - In global memory, remove only entries that mention this project.
  - Leave other projects' sessions, and list any that mention this one.
  - Do not claim this live session's transcript is empty. Print its path instead.
- **Local git history and refs** other than `reset`: one orphan commit with a neutral message, no other local branches, tags, stashes, worktrees, notes, or remote-tracking refs, reflog expired, `gc --prune=now`. The remote itself stays.
- **Logs, build artifacts, generated files, caches, temp files, coverage, virtualenvs, `node_modules`.** Also this project's Docker images, build cache, and volumes that hold no KEEP data or secrets and can be rebuilt from the root, and CI caches and artifacts.
- **Data**: truncate every in-scope table not in KEEP. Never use `CASCADE`. If a KEEP table references a table due for truncation, leave that table and list it under **left alone**. Find the migration-tracking table from the migration tool the repo uses (names like `schema_migrations`, `alembic_version`, `django_migrations`, and `_prisma_migrations` are examples, not the list). A datastore file that the code recreates on start is deleted whole, with its `-wal` and `-shm` files. Flush this project's keys in in-scope caches, queues, vector stores, and object storage.
- **Dead code** and **unused files**: dead means nothing reachable from the entrypoints uses it, and removing it keeps the baseline green. Code that reads an env var, config key, or route keeps its contract name: if unsure, leave it and list it under **left alone**.
- Also remove unused dependencies, obsolete scripts, duplication, and sample or fixture files nothing reads.
- Directories left empty by the purge (git does not track them, so they would linger on disk).
- **Any trace of this job.** Write no notes, plans, reports, or memories to disk at any point.

## Doubt

Do not pause and do not ask.

If you are unsure about a file or a rule:

1. If your agent can start a helper with a **blank context**, ask one such helper. Give it only these instructions and the specific question.
2. If it cannot, decide yourself with this default: **KEEP for secrets, PURGE for everything else.**

Ask only if doubt about a secret or wallet remains after that.

## DONE

A dry run is done when the report and token are printed. For execute mode, DONE means all of these, **shown with command output, not asserted**. The final report is the manifest sections followed by these checks, each as one plain sentence followed by the command output that proves it:

- The current branch is `reset`. The step 5 baseline run passed with no new failures. It was not re-run after cleanup.
- A list of every process, worker, cron job, and scheduler stopped in step 1.
- A statement of what the baseline does and does not exercise. Say whether it loads prompts, job names, serialized type names, Dockerfiles, CI, or cron definitions.
- A search that finds zero comments or docs outside KEEP. Pick the comment syntax for each language in the repo (`#`, `//`, `/* */`, `--`, `<!-- -->`, docstrings) and search every tracked file for it. Show the command and its output; every hit must be a KEEP item.
- Biased or overfit internal names found before the rename are gone, and no banned vague replacement remains.
- `git for-each-ref` lists only `refs/heads/reset`. `git log --all` shows one commit. `git worktree list` prints one line. `git cat-file --batch-all-objects --batch-check | wc -l` equals `git rev-list --objects reset | wc -l`. (`destroy_history.sh` prints all of these.) `git ls-remote` output matches step 2, or there is still no remote. If the remote differs, report the difference and do nothing.
- No logs, caches, or artifacts remain. In-scope tables outside KEEP report zero rows.
- This project's in-scope memory and transcript locations are empty, except this session's own transcript. Print its path so the user can delete it after the session closes.
- A single **left alone** list of anything not reached, not linked, or not deleted.

Print the summary in chat only, then stop. The user will close the session. You will not see this project again.
