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

- Nothing recoverable survives the run: no backups, no archives, no "moved to /old", no trash. Delete means gone.
- Do not commit to any existing branch, except `reset` when it already exists from an earlier run.
- Do not push.
- Do not delete or rewrite anything on the remote.
- Do not write notes, plans, reports, or memories to disk at any point. Report in chat only.
- Never run `git clean -x` or any ignore-based cleanup. Many secrets are gitignored and untracked.
- Do not touch anything outside SCOPE.

## Invocation

The user's message may carry `include:` and `exclude:` lines after the skill name.

- An `include:` line adds a named datastore, host, or path to scope.
- An `exclude:` line removes one that the rules would otherwise take.
- When there are none, the ownership rules below decide.

## Phase 0: discovery and manifest

Do read-only discovery first. Change nothing.

Then print **one scope manifest** and **continue without waiting**. Do not put questions in the manifest.

### Ownership rules

- **Root**: the git top level of the directory where this was invoked.
  - If the directory is not inside a git repository, stop without acting and say so.
  - If that top level is a home directory, a filesystem root, or contains other projects' repositories, stop without acting and say so.
- **Processes**: a process belongs to the project if its working directory, script path, or command line is under the root. This includes paths under the root that have since been deleted. It also belongs if a PM2, systemd, cron, or compose entry points into the root.
  - Agent harnesses, editors and their servers, and the agent's own process tree never belong, even when running inside the root.
  - Anything that cannot be linked is left and listed.
- **Containers, images, volumes**: they belong if built from a Dockerfile or compose file in the root.
  - A container is a datastore only if it runs a database, cache, or queue engine. Any other container is an application process: stop it in step 1, remove it in step 4.
  - Remove images and volumes if they can be rebuilt from that code and hold no KEEP data or secrets. Otherwise leave them and list them.
- **Datastores**: local files and loopback services that the project's code or env files create or connect to are in scope, wherever they sit on disk.
  - Resolve the paths from the code, not only from env files.
  - A datastore on another host is skipped and listed, unless named at invocation.
  - State held by external services is never touched. This includes exchange orders and positions and hosted accounts. List what the code is able to create there.
  - Never show credentials. Name datastores by host and name only.
- **Harness stores**: open every harness and editor store on the machine before ruling on it. Use [references/harness-locations.md](references/harness-locations.md) as a search guide. Search the real machine; do not trust the list.
  - A session whose working directory was the root is deleted whole.
  - A session from another project that only mentions this one is left and listed.
  - In global memory, remove only the entries that mention this project.
  - Editor workspace storage and local history keyed to the root are in scope.

### Manifest and report layout

The manifest and the final report use the same layout: short labelled sections, one plain sentence per item, verdict first.

- Sections: **root**, **datastores**, **containers**, **processes**, **harness stores**.
- Each item gets a verdict (`in scope`, `left alone`, or `skipped`) and a one-clause reason.
- There is no "problems to decide" section. Everything uncertain goes in a single **left alone** list.
- The final report is the manifest sections followed by the DONE checks. Each check is one plain sentence followed by the command output that proves it.

Then set SCOPE from the manifest and proceed. Do not ask, except for the secret-or-wallet case in [Doubt](#doubt).

## SCOPE

Anything outside this is not yours to touch.

- **Project root**: the git top level ruled in by the ownership rules.
- **Databases and stores**: the datastores ruled in scope.
- **Git remote**: leave the remote and its URL. Do not fetch, push, force-push, or delete remote branches, tags, or PRs. Remote history stays until a human decides otherwise. Local remote-tracking refs are in scope and will be deleted.
- **Working branch**: create and check out local branch `reset` from the current HEAD before any purge. If `reset` already exists from an earlier run, continue on it. It is the one existing branch you may commit to. All edits and the history rewrite happen only on `reset`.
- **Agent harnesses**: the stores ruled in scope.

When a step's precondition does not exist, record that as the step's result and continue. No commits means `reset` starts unborn. No remote means the recorded state is "no remote", and the final check is that there is still none.

## ORDER

1. **Stop** every application process, worker, cron job, and scheduler that the ownership rules assign to this project. Leave its datastores running. Leave harnesses, editors, and this agent's process tree running. Keep the list; you must report it.
2. **Record and checkpoint.**
   - Record the current branch and HEAD.
   - Run `git ls-remote` and keep its output in context, or record "no remote".
   - Create local branch `reset` from that HEAD and check it out, or continue on it if it already exists.
   - Before any commit, confirm every secret file (the first KEEP item) is ignored by git. Add an ignore rule if one is not. Untrack any that is already tracked, without deleting the file.
   - Commit the starting tree to `reset` so later edits can be diffed and reverted. No secret may enter any commit, including the final one.
   - Do not delete branches, tags, stashes, or remote-tracking refs yet.
3. **Baseline.** Find the entrypoints and the command that proves the project works (tests, build, or smoke run). Reinstall dependencies from lockfiles if the baseline needs them. Run it. This baseline is the only definition of "necessary code". Failures that exist before the purge are recorded, not fixed. The bar is no new failures.
4. **Purge and rename** on `reset`. See [KEEP](#keep), [RENAME](#rename-internal-only-after-the-baseline-is-known), and [PURGE](#completely-purge).
5. **Proof.** Reinstall dependencies from lockfiles if the baseline needs them. Re-run the baseline, then delete whatever it generated, including those dependencies. This run is the proof. Do not run the baseline again after the history rewrite or the final cleanup.
   - If it shows new failures, fix forward using the step 2 checkpoint. Do not start step 6 until there are none.
   - If that cannot be done, stop with history intact and report.
6. **Destroy local history**, on `reset` only:
   - create a single orphan commit with a neutral message
   - make `reset` point at it
   - delete every other local branch, tag, stash, worktree, and note
   - delete all local remote-tracking refs (`refs/remotes/*`) but keep the remote URL
   - expire the reflog
   - run `git gc --prune=now`
   - the step 2 checkpoint does not survive this step
   - do not push
   - no secret may enter this commit
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
- **Agent context ruled in scope**: instruction files (`CLAUDE.md`, `AGENTS.md`, rules files), project-level agent folders, sessions whose working directory was the root, plans, todo lists, scratchpads, code graphs, indexes, embeddings, and editor workspace storage and local history keyed to the root.
  - In global memory, remove only entries that mention this project.
  - Leave other projects' sessions, and list any that mention this one.
  - Do not claim this live session's transcript is empty. Print its path instead.
- **Local git history and refs** other than `reset`: one orphan commit with a neutral message, no other local branches, tags, stashes, worktrees, notes, or remote-tracking refs, reflog expired, `gc --prune=now`. The remote itself stays.
- **Logs, build artifacts, generated files, caches, temp files, coverage, virtualenvs, `node_modules`.** Also this project's Docker images, build cache, and volumes that hold no KEEP data or secrets and can be rebuilt from the root, and CI caches and artifacts.
- **Data**: truncate every in-scope table not in KEEP. Flush this project's keys in in-scope caches, queues, vector stores, and object storage.
- **Dead code**, unused files, unused dependencies, obsolete scripts, duplication, and sample or fixture files nothing reads.
- **Any trace of this job.** Write no notes, plans, reports, or memories to disk at any point.

## Doubt

Do not pause and do not ask.

If you are unsure about a file or a rule:

1. If your agent can start a helper with a **blank context**, ask one such helper. Give it only these instructions and the specific question.
2. If it cannot, decide yourself with this default: **KEEP for secrets, PURGE for everything else.**

Ask only if doubt about a secret or wallet remains after that.

## DONE

DONE means all of these, **shown with command output, not asserted**. The final report is the manifest sections followed by these checks, each as one plain sentence followed by the command output that proves it:

- The current branch is `reset`. The step 5 baseline run passed with no new failures. It was not re-run after cleanup.
- A list of every process, worker, cron job, and scheduler stopped in step 1.
- A statement of what the baseline does and does not exercise. Say whether it loads prompts, job names, serialized type names, Dockerfiles, CI, or cron definitions.
- A search that finds zero comments or docs outside KEEP.
- Biased or overfit internal names found before the rename are gone, and no banned vague replacement remains.
- `git for-each-ref` lists only `refs/heads/reset`. `git log --all` shows one commit. `git ls-remote` output matches step 2, or there is still no remote. If the remote differs, report the difference and do nothing.
- No logs, caches, or artifacts remain. In-scope tables outside KEEP report zero rows.
- This project's in-scope memory and transcript locations are empty, except this session's own transcript. Print its path so the user can delete it after the session closes.
- A single **left alone** list of anything not reached, not linked, or not deleted.

Print the summary in chat only, then stop. The user will close the session. You will not see this project again.
