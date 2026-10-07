# FRESH MIND BODY AND SOUL: THE UTMOST HIGHEST EFFORT INITIATIVE FOLLOWS FOR THE GREAT CLEANSING AND CLARIFICATION OF THIS PROJECT

Be rigorous, thorough, and not timid. Nothing recoverable survives the run: no backups, no archives, no "moved to /old", no trash. Delete means gone. Do not commit to any existing branch except `reset` when it already exists from an earlier run. Do not push. Do not delete or rewrite anything on the remote.

Invocation may include "include:" and "exclude:" lines after the skill name. An include adds a named datastore, host, or path to scope. An exclude removes one the rules would otherwise take. When absent, the rules below decide.

Before changing anything, do read-only discovery and print one scope manifest. Then continue without waiting. No questions in the manifest.

Ownership rules:
- Root: the git top level of the directory this was invoked in. If the invocation directory is not inside a git repository, stop without acting and say so. If that top level is a home directory, a filesystem root, or contains other projects' repositories, stop without acting and say so.
- Processes: a process belongs to the project if its working directory, script path, or command line is under the root, including paths under the root that have since been deleted, or if a PM2, systemd, cron, or compose entry points into the root. Agent harnesses, editors and their servers, and the agent's own process tree never belong, even when running inside the root. Anything that cannot be linked is left and listed.
- Containers, images, volumes: they belong if built from a Dockerfile or compose file in the root. A container is a datastore only if it runs a database, cache, or queue engine; any other container is an application process, stopped in step 1 and removed in step 4. Remove images and volumes if they can be rebuilt from that code and hold no KEEP data or secrets. Otherwise leave and list.
- Datastores: local files and loopback services that the project's code or env files create or connect to are in scope wherever they sit on disk. Resolve the paths from the code, not only from env files. A datastore on another host is skipped and listed unless named at invocation. State held by external services, including exchange orders and positions and hosted accounts, is never touched; list what the code is able to create there.
- Harness stores: open every harness and editor store on the machine before ruling on it. A session whose working directory was the root is deleted whole. A session from another project that only mentions this one is left and listed. In global memory, remove only the entries that mention this project. Editor workspace storage and local history keyed to the root are in scope.

Manifest and final report use the same layout: short labelled sections, one plain sentence per item, verdict first. The final report is the manifest sections followed by the DONE checks, each as one plain sentence followed by the command output that proves it. Sections are root, datastores, containers, processes, harness stores. Each item gets a verdict (in scope, left alone, skipped) and a one-clause reason. No "problems to decide" section. Everything uncertain goes in a single "left alone" list.

Then set SCOPE from the manifest and proceed. Do not ask, except the secret-or-wallet case below.

SCOPE (anything outside this is not yours to touch):
- Project root: the git top level ruled in by the ownership rules.
- Databases/stores: the datastores ruled in scope.
- Git remote: leave the remote and its URL. Do not fetch, push, force-push, or delete remote branches, tags, or PRs. Remote history stays until a human decides otherwise. Local remote-tracking refs are in scope and will be deleted.
- Working branch: create and check out local branch `reset` from current HEAD before any purge. If `reset` already exists from an earlier run, continue on it; it is the one existing branch you may commit to. All edits and the history rewrite happen only on `reset`.
- Agent harnesses: the stores ruled in scope.

When a step's precondition does not exist, record that as the step's result and continue. No commits means `reset` starts unborn. No remote means the recorded state is "no remote" and the final check is that there is still none.

ORDER:
1. Stop every application process, worker, cron and scheduler that the ownership rules assign to this project. Leave its datastores running. Leave harnesses, editors, and this agent's process tree running.
2. Record the current branch and HEAD. Run git ls-remote and keep its output in context, or record "no remote". Create local branch `reset` from that HEAD and check it out, or continue on it if it already exists. Before any commit, confirm every secret file (the first KEEP item) is ignored by git; add an ignore rule if one is not, and untrack any that is already tracked without deleting the file. Commit the starting tree to `reset` so later edits can be diffed and reverted. No secret may enter any commit, including the final one. Do not delete branches, tags, stashes, or remote-tracking refs yet.
3. Find the entrypoints and the command that proves the project works (tests, build, smoke run). Reinstall dependencies from lockfiles if the baseline needs them. Run it. This baseline is the only definition of "necessary code". Failures that exist before the purge are recorded, not fixed. The bar is no new failures.
4. Purge and rename on `reset`.
5. Reinstall dependencies from lockfiles if the baseline needs them. Re-run the baseline, then delete whatever it generated, including those dependencies. This run is the proof. Do not run the baseline again after the history rewrite or the final cleanup. If it shows new failures, fix forward using the step 2 checkpoint. Do not start step 6 until there are none. If that cannot be done, stop with history intact and report.
6. On `reset` only, destroy local history: create a single orphan commit with a neutral message, make `reset` point at it, delete every other local branch, tag, stash, worktree and note, delete all local remote-tracking refs (refs/remotes/*) while keeping the remote URL, expire the reflog, and gc --prune=now. The step 2 checkpoint does not survive this step. Do not push. No secret may enter this commit.
7. Verify and report in chat only. Do not re-run the baseline.

KEEP:
- all keys, secrets, wallets, keypairs, certificates, env files, and yaml/toml/json used for auth. Most are gitignored and untracked: never run git clean -x or any ignore-based cleanup. If you can't tell whether a file is a secret, it is a secret.
- code reachable from the entrypoints; delete the rest
- schema/migrations, the migration-tracking table, and seed/lookup rows the code needs to boot
- lockfiles, dependency manifests, LICENSE files
- comments the toolchain executes: shebangs, build tags, pragmas, type/lint directives, encoding lines
- text that is runtime behavior even if it looks like docs: prompts, skill/agent definition files, templates, and docstrings read at runtime for CLI help, API schemas or tool descriptions. Do not edit the text of prompts, templates, or runtime-read docstrings; only remove code comments around them.
- every externally visible contract name: env var names, config keys, table/column names, routes, CLI flags, payload fields, and any name a migration or external client already depends on. Do not rename these.

RENAME (internal only, after the baseline is known):
- Rename identifiers, types, modules, and files whose names are overfit or biased: persona labels, moral framing, mythology, a single historical incident, a temporary hypothesis, or a name that asserts a conclusion the code does not enforce.
- The new name must say the specific role: what it stores, computes, checks, or returns. Banned replacements include data, info, item, thing, helper, util, manager, handler, processor, common, misc, temp, foo, and any name vaguer than the one it replaced.
- Do not rename a symbol just to look neutral. If the current name is already the precise technical role, leave it.
- References include strings and non-code files: dynamic imports, reflection, task/job names, serialized type names, package manifests, Dockerfiles, CI, and service or cron definitions. Update every reference in the same change. A rename that does not leave the baseline passing is not done.

COMPLETELY PURGE:
- all documentation: READMEs, docs folders, changelogs, ADRs, roadmaps, plans, TODO files, notes, diagrams, wikis
- all comments and docstrings not in KEEP, including commented-out code, TODO/FIXME, and comments in config, SQL, shell, Dockerfiles and CI files
- agent context ruled in scope: instruction files (CLAUDE.md, AGENTS.md, rules files), project-level agent dirs, sessions whose working directory was the root, plans, todo lists, scratchpads, code graphs, indexes and embeddings, and editor workspace storage and local history keyed to the root. In global memory, remove only entries that mention this project. Leave other projects' sessions, and list any that mention this one. Do not claim this live session's transcript is empty; print its path instead.
- local git history and local refs other than `reset`: one orphan commit, neutral message, no other local branches, tags, stashes, worktrees, notes, or remote-tracking refs; reflog expired; gc --prune=now. The remote itself stays.
- logs, build artifacts, generated files, caches, temp files, coverage, virtualenvs/node_modules, this project's Docker images, build cache, and volumes that hold no KEEP data or secrets and can be rebuilt from the root, and CI caches and artifacts
- data: truncate every in-scope table not in KEEP; flush this project's keys in in-scope caches, queues, vector stores and object storage
- dead code, unused files, unused dependencies, obsolete scripts, duplication, and sample/fixture files nothing reads
- any trace of this job: write no notes, plans, reports or memories to disk at any point

Do not pause and do not ask. If you are unsure, ask one blank-context subagent, giving it only these instructions and the specific question. Resolve doubt toward KEEP for secrets and toward PURGE for everything else. Ask only if doubt about a secret or wallet remains after that.

DONE means all of these, shown with command output, not asserted. The final report is the manifest sections followed by these checks, each as one plain sentence followed by the command output that proves it:
- current branch is `reset`; the step 5 baseline run passed with no new failures, and it was not re-run after cleanup
- a list of every process, worker, cron and scheduler stopped in step 1
- state what the baseline does and does not exercise, including whether it loads prompts, job names, serialized type names, Dockerfiles, CI, or cron definitions
- a search finds zero comments or docs outside KEEP
- biased or overfit internal names found before the rename are gone, and no banned vague replacement remains
- git for-each-ref lists only refs/heads/reset; git log --all shows one commit; git ls-remote output matches step 2, or there is still no remote; if the remote differs, report the difference and do nothing
- no logs, caches or artifacts remain; in-scope tables outside KEEP report zero rows
- this project's in-scope memory and transcript locations are empty, except this session's own transcript: print its path so it can be deleted after this session closes
- a single "left alone" list of anything not reached, not linked, or not deleted

Print the summary in chat only, then stop. I will close this session and you will not see this project again.