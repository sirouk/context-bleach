---
name: context-bleach
description: "Irreversibly reset a project to its working code only: purge all docs, comments, agent context (memories, transcripts, instruction files), dead code, caches, data, and local git history into one orphan commit, and rename biased internal names. Destructive, no backups. Use ONLY when the user explicitly names it: \"context-bleach\", \"bleach this project\", or \"fresh mind body and soul\". Never use it implicitly."
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

- `UP_TO_DATE`: continue.
- `UPDATED`: read the new `SKILL.md` and `references/` again in full, then continue.
- `LOCAL_DIRTY`: keep the installed copy, do not use `--force`, and continue.
- `ERROR` or a missing script: continue with the installed copy.

Say nothing about freshness unless the result is `UPDATED` or `LOCAL_DIRTY`.

Read this whole file and [references/harness-locations.md](references/harness-locations.md) before you change anything. Step 4 or the cleanup may delete project-level agent folders. If this skill was installed inside the project, it may disappear mid-run. Do not depend on re-reading it.

## Hard rules

- Everything here is intentional and irreversible on this machine.
- Do not commit to any existing branch.
- Do not push.
- Do not delete or rewrite anything on the remote.
- Do not write notes, plans, reports, or memories to disk at any point. Report in chat only.
- Never run `git clean -x` or any ignore-based cleanup. Many secrets are gitignored and untracked.
- Do not touch anything outside SCOPE.

## Phase 0: discovery and the gate

Do read-only discovery first. Change nothing.

Then show the user these three things and **wait**. Do not start step 1 until the user has answered all three. This overrides any standing instruction not to ask questions.

1. **Project root**: the path you found. Refuse and ask again if it is `/`, the home directory, or a directory with no sign of being one project.
2. **Databases and stores**: every datastore the project's env files connect to, by host and name only. Never show credentials. Ask whether any are out of scope and whether any others are in.
3. **Agent harnesses**: every agent tool with traces of this project, and where each keeps them. Use [references/harness-locations.md](references/harness-locations.md) as a search guide. Search the real machine. Do not trust the list.

Then set SCOPE from the answers and proceed. Do not ask again, except for the secret-or-wallet case in [Doubt](#doubt).

## SCOPE

Anything outside this is not yours to touch.

- **Project root**: the path the user gave.
- **Databases and stores**: the list the user confirmed.
- **Git remote**: leave the remote and its URL. Do not fetch, push, force-push, or delete remote branches, tags, or PRs. Remote history stays until a human decides otherwise. Local remote-tracking refs are in scope and will be deleted.
- **Working branch**: create and check out local branch `reset` from the current HEAD before any purge. All edits and the history rewrite happen only on `reset`.
- **Agent harnesses** that have worked here: the list the user confirmed.

## ORDER

1. **Stop** every application process, worker, cron job, and scheduler that belongs to this project. Leave its datastores running. Keep the list; you must report it.
2. **Record** the current branch and HEAD. Run `git ls-remote` and keep its output in context. Create local branch `reset` from that HEAD and check it out. Do not delete branches, tags, stashes, or remote-tracking refs yet.
3. **Baseline.** Find the entrypoints and the command that proves the project works (tests, build, or smoke run). Run it. This baseline is the only definition of "necessary code".
4. **Purge and rename** on `reset`. See [KEEP](#keep), [RENAME](#rename-internal-only-after-the-baseline-is-known), and [PURGE](#completely-purge).
5. **Proof.** Run the baseline again. Then delete whatever it generated. This run is the proof. Do not run the baseline again after the history rewrite or the final cleanup.
6. **Destroy local history**, on `reset` only:
   - create a single orphan commit with a neutral message
   - make `reset` point at it
   - delete every other local branch, tag, stash, worktree, and note
   - delete all local remote-tracking refs (`refs/remotes/*`) but keep the remote URL
   - expire the reflog
   - run `git gc --prune=now`
   - do not push
7. **Verify and report** in chat only. Do not run the baseline again.

## KEEP

- All keys, secrets, wallets, keypairs, certificates, env files, and yaml/toml/json files used for auth. Most are gitignored and untracked. **If you cannot tell whether a file is a secret, it is a secret.**
- Code reachable from the entrypoints. Delete the rest.
- Schema and migrations, the migration-tracking table, and the seed or lookup rows the code needs to boot.
- Lockfiles, dependency manifests, and LICENSE files.
- Comments the toolchain executes: shebangs, build tags, pragmas, type and lint directives, encoding lines.
- Text that is runtime behavior even if it looks like docs: prompts, skill and agent definition files, templates, and docstrings read at runtime for CLI help, API schemas, or tool descriptions. Do not edit the text of prompts, templates, or runtime-read docstrings. Only remove code comments around them.
- Every externally visible contract name: env var names, config keys, table and column names, routes, CLI flags, payload fields, and any name a migration or external client already depends on. Do not rename these.

## RENAME (internal only, after the baseline is known)

- Rename identifiers, types, modules, and files whose names are overfit or biased. Examples: persona labels, moral framing, mythology, a single historical incident, a temporary hypothesis, or a name that asserts a conclusion the code does not enforce.
- The new name must say the specific role: what it stores, computes, checks, or returns.
- Banned replacements: `data`, `info`, `item`, `thing`, `helper`, `util`, `manager`, `handler`, `processor`, `common`, `misc`, `temp`, `foo`, and any name vaguer than the one it replaced.
- Do not rename a symbol just to look neutral. If the current name is already the precise technical role, leave it.
- Update every reference in the same change. This includes strings and non-code files: dynamic imports, reflection, task and job names, serialized type names, package manifests, Dockerfiles, CI, and service or cron definitions.
- A rename that does not leave the baseline passing is not done.

## COMPLETELY PURGE

- **All documentation**: READMEs, docs folders, changelogs, ADRs, roadmaps, plans, TODO files, notes, diagrams, wikis.
- **All comments and docstrings not in KEEP**, including commented-out code and TODO/FIXME. This covers comments in config, SQL, shell, Dockerfiles, and CI files.
- **Agent context in every harness in scope**: instruction files (`CLAUDE.md`, `AGENTS.md`, rules files), project-level agent folders, per-project memories, session transcripts, plans, todo lists, scratchpads, code graphs, indexes, and embeddings.
  - Project-specific only. Leave global instructions and other projects' memories intact, but remove any lines in them that mention this project.
  - Do not claim this live session's transcript is empty. Print its path instead.
- **Local git history and refs** other than `reset`: one orphan commit with a neutral message, no other local branches, tags, stashes, worktrees, notes, or remote-tracking refs, reflog expired, `gc --prune=now`. The remote itself stays.
- **Logs, build artifacts, generated files, caches, temp files, coverage, virtualenvs, `node_modules`, editor state and local history.** Also this project's Docker images, build cache, and volumes that hold no KEEP data or secrets, and CI caches and artifacts.
- **Data**: truncate every table not in KEEP. Flush this project's keys in caches, queues, vector stores, and object storage in scope.
- **Dead code**, unused files, unused dependencies, obsolete scripts, duplication, and sample or fixture files nothing reads.
- **Any trace of this job.** Write no notes, plans, reports, or memories to disk at any point.

## Doubt

After the three SCOPE answers, do not pause and do not ask the user.

If you are unsure about a file or a rule:

1. If your agent can start a helper with a **blank context**, ask one such helper. Give it only these instructions and the specific question.
2. If it cannot, decide yourself with this default: **KEEP for secrets, PURGE for everything else.**

Ask the user only if doubt about a secret or wallet remains after that.

## DONE

DONE means all of these, **shown with command output, not asserted**:

- The current branch is `reset`. The step 5 baseline run passed. It was not re-run after cleanup.
- A list of every process, worker, cron job, and scheduler stopped in step 1.
- A statement of what the baseline does and does not exercise. Say whether it loads prompts, job names, serialized type names, Dockerfiles, CI, or cron definitions.
- A search that finds zero comments or docs outside KEEP.
- Biased or overfit internal names found before the rename are gone, and no banned vague replacement remains.
- `git for-each-ref` lists only `refs/heads/reset`. `git log --all` shows one commit. `git ls-remote` output matches step 2. If it differs, report the difference and do nothing.
- No logs, caches, or artifacts remain. Tables outside KEEP report zero rows.
- This project's memory and transcript locations are empty, except this session's own transcript. Print its path so the user can delete it after the session closes.
- A list of anything you could not reach or delete.

Print the summary in chat only, then stop. The user will close the session. You will not see this project again.
