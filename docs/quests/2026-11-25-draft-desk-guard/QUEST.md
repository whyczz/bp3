---
status: proposed
home_repo: bp3
date: 2026-11-25
bump: minor
depends_on: 2026-11-25-central-desks-dir
---

# draft-desk-guard: plain-Git draft desks and Tiered CAS landing so `master` stays clean and continuously fresh

TL;DR
Replace single-writer `master` friction with a two-tier CAS model that keeps `master` **both clean and continuously fresh** across 5+ parallel worktrees:
1. **Draft desks (`draft.1`):** add `bp3 harness desk prepare|release|land --draft <slug>` under `~/.bp3/desks/<repo>-<hash8>/drafts/<slug>` (branch `draft/<slug>`), where `land --draft` runs a fast rebase + atomic CAS retry loop (max 3 attempts) onto `master` — **never blocked by active quests** — plus add `target_branch` / `target_dirty` to `bp3 harness desk list`, fix `Worktree.do_remove` to anchor on `main_root ()`, and ignore `*.red-ink.md` / `*.2b-reviewed.md*` in `.gitignore`.
2. **CAS merge-tree promotion (`release.1`):** upgrade `bp3 release` so fast-forward remains the instant fast path when `master` didn't move, and when `master` *did* move concurrently, `bp3 release` runs in-memory `git merge-tree --write-tree` + tiered verification (fast lint for doc-only drift, ephemeral detached-worktree gate for code drift) + a 2-parent plumbing merge commit (preserving every graded commit SHA in `ledger.jsonl` verbatim) + atomic CAS retry loop (max 3 attempts), with `--ff-only` to opt into strict fast-forward.
3. **Planning skill guards (`skills.1`):** update `skills/{icebox,quest,red-ink}/SKILL.md`, `RELEASING.md`, and `AGENTS.md`/`CLAUDE.md`: `/icebox` writes + commits directly on `master` whenever `master` is clean (zero ceremony, zero starvation) or uses a draft desk if dirty; multi-turn `/quest` and `/red-ink` always draft in `bp3 harness desk prepare --draft ...` and land immediately via `land --draft`.

ELI5
When you run 5 quests in parallel while also framing new quests and dropping `/icebox` notes, freezing `master` causes starvation (drafts wait forever) and strict fast-forward causes retry storms (every finished quest hits `E_NOT_FAST_FORWARD` whenever anything lands first). This quest splits the problem cleanly: multi-turn planning edits happen in isolated `draft/<slug>` worktrees so `master` is never dirty (`E_DIRTY_TREE`), drafts land immediately via a 50ms CAS rebase loop so `master` stays fresh, and `bp3 release` automatically computes an in-memory 3-way merge (`git merge-tree --write-tree`) + deterministic verification whenever `master` moved ahead — keeping every graded node commit SHA intact and only bouncing back on real git conflicts or failing checks.

## Context

Owner decisions settled at framing (2026-11-25):
- **Scope:** CLI draft desk (`bp3 harness desk prepare|release|land --draft <slug>`) + Tiered CAS `merge-tree` promotion in `bp3 release` + skill guards (`icebox`, `quest`, `red-ink`) + `.gitignore` + `AGENTS.md`/`CLAUDE.md`.
- **Fresh `master` without starvation:** *"i want master to be fresh, i don't want 5 worktrees for different quests all blocked from landing because quests are constantly being added, worked, and promoted"* -> `"yep this is much better"`. Neither drafts nor parallel quests block each other unless they actually conflict or fail verification.
- **Direct-on-`master` bypass:** Allow immediate write + commit on `master` only for single-turn `/icebox` when `master` is clean (`target_dirty == false`); multi-turn `/quest` and `/red-ink` (and dirty-master `/icebox`) always use a `draft/<slug>` worktree.
- **Sequencing:** Depends on `2026-11-25-central-desks-dir` (`--depends-on 2026-11-25-central-desks-dir` at `bp3 q c`), so draft desks live natively at `<repo_desks_dir>/drafts/<slug>` sibling to `quests/` and `runs/`.

Measured ground (audited 2026-11-25 on `master` `e60eb8a`, `git version 2.56.0`):

| Fact | Source |
|---|---|
| `Release_io.run` currently rejects any `target_tip` not an ancestor of `source_tip` (`E_NOT_FAST_FORWARD`) even when changes are completely disjoint, and already uses pure git plumbing (`plumbing_commit`, `plumbing_mktag`, `atomic_cas_update`) | `src/quest/release_io.ml:246-303,543-549` |
| `git --version` is `2.56.0` (supports `git merge-tree --write-tree`, introduced in Git 2.38, computing 3-way merges purely in the object store with zero working-tree mutation) | local `git --version` (2026-11-25) |
| `Worktree.run` supports `prepare --quest <q>` and `release --quest <q>` (plus `<q> <n> --run`), and refuses `prepare --draft` (`E_USAGE`) and `land` (`unknown worktree verb: land`) | `src/quest/worktree.ml:504-537` |
| `Worktree.do_remove` checks `git_out ["rev-parse"; "--show-toplevel"]` against `abs` to guard `E_MAIN_WORKTREE`, which falsely rejects removing a linked worktree when invoked from inside that worktree | `src/quest/worktree.ml:140-146` |
| `docs/quests/2026-11-25-central-desks-dir/QUEST.md` establishes central `<desks_base>/<repo_key>/{quests,runs,.meta}` anchored on `git_common_dir` | `docs/quests/2026-11-25-central-desks-dir/QUEST.md:32-45` |
| `test/release-door.sh:145-180` tests parallel `q1`/`q2` off `M0` with disjoint files (`work-q1.txt` vs `work-q2.txt`) expecting `E_NOT_FAST_FORWARD` today | `test/release-door.sh:145-180` |
| `.gitignore` has 6 lines and does not ignore `*.red-ink.md`, `*.2b-reviewed.md`, or `*.2b-reviewed.md.snapshot` | `.gitignore:1-6` |
| `skills/icebox/SKILL.md`, `skills/quest/SKILL.md`, and `skills/red-ink/SKILL.md` have no worktree guard (`icebox` leaves files uncommitted on `master`) | `skills/icebox/SKILL.md:68-69`, `skills/quest/SKILL.md:65-81`, `skills/red-ink/SKILL.md:24-44` |
| `completions/_bp3` and `completions/bp3.bash` list `harness desk` verbs without `land` and `release` flags without `--ff-only` | `completions/_bp3:106-107,137-140`, `completions/bp3.bash:110-111,141-144` |

## Terms

| Term | Meaning |
|---|---|
| `draft_branch_kind` | `"draft"` in `src/quest/layout.ml`; `Layout.draft_branch slug` produces `"draft/" ^ slug` |
| `draft_desk_dir` | `<repo_desks_dir>/drafts/<slug>` — central draft worktree path (`Layout.draft_desk_dir`), sibling to `quests/` and `runs/`, never nested inside either |
| `draft_run_id` | `"draft-" ^ slug` — metadata key for `.meta/draft-<slug>.json` (mirrors `quest-<quest>`), with `quest = slug` and `node = "(draft)"` |
| `target_dirty` | live-derived bool on `bp3 harness desk list`: `true` iff any git worktree checked out on `refs/heads/<target>` (`master` then `main`) has non-empty `git status --porcelain` |
| `drift_kind` | pure classification (`Release.classify_drift`) of files changed in `merge_base..target_tip` when `bp3 release` merges over concurrent target commits: `None_drift` (fast-forward), `Doc_only` (every drifted file is strictly under `docs/icebox/`, `docs/dossiers/`, or `docs/quests/<other>/`), or `Code` (anything else) |
| `strategy` | verdict field on `bp3 release`: `"fast_forward"` (linear, single parent) or `"merge"` (plumbing `git merge-tree --write-tree` 2-parent merge commit `[old_target_tip; source_tip]`) |
| `E_MERGE_CONFLICT` | typed error code in `src/quest/names.ml` emitted when `git merge-tree --write-tree` reports conflicting paths (`facts.conflicts`) or a draft rebase conflicts (after clean `rebase --abort`) |
| `E_VERIFY_FAILED` | typed error code in `src/quest/names.ml` emitted when the merged-tree verification gate fails in the ephemeral detached worktree (`master` untouched, ephemeral desk removed) |
| `BP3_RELEASE_VERIFY_CMD` | optional env override for the verification command run on a code-drift merged tree in `bp3 release` (defaults to `make check-full` when `repo_mode () = "self"` or `Makefile` defines `check-full:`, `make lint` on `doc_only` drift when `Makefile` defines `lint:`, else skipped in minimal host repos) |

## Inputs

| Input | Source & precedence |
|---|---|
| `--draft <slug>` | CLI flag on `bp3 harness desk prepare\|release\|land`; validated with `Store.check_creatable` (on `prepare`) / `Store.check_slug` (on `release`/`land`) |
| `--target <branch>` | optional flag on `bp3 harness desk land --draft <slug>` and `bp3 release`; defaults to `master` then `main` |
| `--force` | optional flag on `bp3 harness desk release --draft <slug>` (allows removing a dirty draft worktree; never accepted by `land`) |
| `--ff-only` | optional flag on `bp3 release` forcing strict fast-forward refusal (`E_NOT_FAST_FORWARD`) even when a clean 3-way merge is possible |
| `BP3_RELEASE_VERIFY_CMD` | optional env override for `bp3 release`'s merged-tree verification command |
| `BP3_DESKS_DIR` / `HOME` | central desks base directory inherited from `2026-11-25-central-desks-dir` |

## Outputs

| Output | Shape |
|---|---|
| `bp3 harness desk prepare --draft <slug>` | `{"ok":true,"run_id":"draft-<slug>","quest":"<slug>","node":"(draft)","path":"<repo_desks_dir>/drafts/<slug>","ref":"draft/<slug>","detached":false,"created_ts":<int>}` (+ `"existing":true` on idempotent reuse) |
| `bp3 harness desk release --draft <slug> [--force]` | `{"ok":true,"released":true,"removed":true|false,"run_id":"draft-<slug>",...}` (refuses `E_DIRTY_TREE` without `--force`; leaves `draft/<slug>` branch intact) |
| `bp3 harness desk land --draft <slug> [--target <branch>]` | `{"ok":true,"draft":"<slug>","branch":"draft/<slug>","target":"<branch>","commit":"<sha>","rebased":true|false,"attempts":<int>,"landed":true,"released":true,"branch_deleted":true,"conductor_path":"<main_root>"}` (CAS retry loop up to 3 attempts; refusals: `E_NOT_FOUND`, `E_DIRTY_TREE`, `E_NOT_READY`, `E_MERGE_CONFLICT`, `E_STALE_WORLD`) |
| `bp3 harness desk list [--quest <q>]` | existing `{"ok":true,"worktrees":[...]}` **plus** live-derived `"target_branch":"master"|"main"|null`, `"target_dirty":bool` |
| `bp3 release <quest> [--ff-only] [--dry-run] ...` | existing verdict JSON **plus** `"strategy":"fast_forward"|"merge"`, `"drift_kind":"none"|"doc_only"|"code"`, `"verified_merged":"none"|"lint"|"full"|"custom"|"skipped_no_gate"`, `"attempts":<int>`; refusals on diverged merge failure: `E_MERGE_CONFLICT` (`facts.conflicts`), `E_VERIFY_FAILED` (`facts.detail`), `E_NOT_FAST_FORWARD` (only with `--ff-only`), `E_STALE_WORLD` (after 3 CAS retries) |
| `.gitignore` | ignores `*.red-ink.md`, `*.2b-reviewed.md`, and `*.2b-reviewed.md.snapshot` |
| `skills/{icebox,quest,red-ink}/SKILL.md` (+ renders), `RELEASING.md`, `AGENTS.md`/`CLAUDE.md` | clean-runway worktree guard + Tiered CAS release contract |

## Acceptance gates

Observed today (2026-11-25, `master` `e60eb8a`):

```text
$ ./bin/bp3 harness desk prepare --draft demo
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"worktree prepare needs --run <run-id>"},"guidance":"Fix the call: worktree prepare needs --run <run-id>"}}
$ ./bin/bp3 harness desk land --draft demo
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"unknown worktree verb: land"},"guidance":"Fix the call: unknown worktree verb: land"}}
$ ./bin/bp3 release --help | grep -c -- '--ff-only' || true
0
$ grep -n 'red-ink\.md\|2b-reviewed\.md' .gitignore || echo "0 matches"
0 matches
$ grep -n -- '--draft' skills/icebox/SKILL.md skills/quest/SKILL.md skills/red-ink/SKILL.md || echo "0 matches"
0 matches
```

Design trace (after quest lands):

```text
draft.1    # Drafts land immediately via CAS rebase loop, even while 5 quest desks are open:
           BP3_DESKS_DIR=/tmp/d ./bin/bp3 harness desk prepare --draft quest-foo
             -> {"ok":true,"run_id":"draft-quest-foo","node":"(draft)","path":"/tmp/d/bp3-<8hex>/drafts/quest-foo","ref":"draft/quest-foo",...}
           # commit docs/quests/foo/QUEST.md in draft desk; meanwhile another commit lands on master
           (cd "$draft_path" && BP3_DESKS_DIR=/tmp/d "$repo/bin/bp3" harness desk land --draft quest-foo)
             -> rebases onto new master, atomic CAS ff-updates refs/heads/master, syncs clean master checkout,
                removes draft desk + .meta/draft-quest-foo.json, deletes draft/quest-foo branch
             -> {"ok":true,"draft":"quest-foo","rebased":true,"attempts":1,"landed":true,"released":true,"branch_deleted":true,"conductor_path":"<main_root>"}
           # rebase conflict -> clean `git rebase --abort` -> E_MERGE_CONFLICT, draft desk intact

release.1  # Parallel quests q1 and q2 both branch off M0 (disjoint files); q1 promotes first (v0.1.0):
           BP3_DECIDER=human ./bin/bp3 release q1 -> {"ok":true,"tag":"v0.1.0","strategy":"fast_forward","drift_kind":"none",...}
           # q2 promotes right after WITHOUT manual rebase — in-memory merge-tree + verify + 2-parent merge commit:
           BP3_DECIDER=human ./bin/bp3 release q2 -> {"ok":true,"tag":"v0.2.0","strategy":"merge","drift_kind":"code","verified_merged":"...",...}
           # git rev-parse HEAD^2 == quest/q2's exact graded commit SHA (zero SHA rewriting!)
           # doc-only drift on master (docs/icebox/*.md) -> strategy="merge", drift_kind="doc_only", verified_merged="lint" (or "skipped_no_gate")
           # real merge conflict -> E_MERGE_CONFLICT {conflicts: [...]}, master untouched
           # merged tree fails verify gate -> E_VERIFY_FAILED, master untouched, ephemeral desk deleted
           # --ff-only on diverged master -> E_NOT_FAST_FORWARD

skills.1   skills/{icebox,quest,red-ink}/SKILL.md + .agents/.claude/.pi renders + RELEASING.md + AGENTS.md/CLAUDE.md
           ./bin/bp3 skills check -> {"ok":true,...}
           ./test/skills.sh && make check-full -> rc 0
```

## Goal and why

Keep `master` **clean** (zero `E_DIRTY_TREE` blocks from planning edits) AND **continuously fresh** (zero starvation or manual-rebase retry storms across 5+ parallel quests). Putting multi-turn planning in central `draft/<slug>` desks isolates the human's scratchpad from `master`, while upgrading `bp3 release` to in-memory `git merge-tree --write-tree` + tiered verification + atomic CAS means parallel quests and drafts never block each other unless they genuinely conflict or fail verification — and graded node commit SHAs in `ledger.jsonl` are never rewritten.

## Success picture

- `bp3 harness desk prepare|release|land --draft <slug>` manages isolated planning worktrees under `<repo_desks_dir>/drafts/<slug>` (branch `draft/<slug>`) and lands committed drafts immediately via a 3-attempt rebase + atomic CAS loop.
- `bp3 harness desk list` reports live-derived `target_branch` and `target_dirty`, and `Worktree.do_remove` works cleanly when invoked from inside any linked desk.
- `bp3 release` keeps strict fast-forward as its fast path (`strategy: "fast_forward"`), and on concurrent `master` drift automatically computes `git merge-tree --write-tree`, verifies the merged tree (`doc_only` -> fast lint; `code` -> full gate in an ephemeral detached worktree), preserves graded SHAs via a 2-parent plumbing merge commit, and CAS-updates `refs/heads/<target>` + `refs/tags/vX.Y.Z` atomically (with `--ff-only` opt-in for strict FF).
- `.gitignore` ignores `*.red-ink.md`, `*.2b-reviewed.md`, and `*.2b-reviewed.md.snapshot`.
- `skills/{icebox,quest,red-ink}/SKILL.md` (+ renders), `RELEASING.md`, and `AGENTS.md`/`CLAUDE.md` encode the clean-runway guard and Tiered CAS model.

## Scope

| In | Out |
|---|---|
| Central `drafts/<slug>` desks (`prepare\|release\|land --draft <slug>` with 3-attempt CAS rebase loop) + `target_branch`/`target_dirty` on `desk list` + `do_remove` `main_root ()` fix + `.gitignore` + completions (`draft.1`) | Pessimistic runway freezing / blocking drafts while quests are open (deliberately rejected to prevent N=5 starvation) |
| Tiered CAS `git merge-tree --write-tree` + ephemeral detached-worktree verification + 2-parent plumbing merge commit + `--ff-only` in `release.ml` / `release_io.ml` (`release.1`) | Background merge-queue daemon or speculative multi-PR batching (CAS loop + optional future SQLite lock is enough for 3–10 local quests) |
| `E_MERGE_CONFLICT` and `E_VERIFY_FAILED` typed constants in `src/quest/names.ml` (`draft.1` / `release.1`) | Adding any new top-level CLI door, language, or external library (`CONSTRAINTS.md` stays untouched) |
| Updating `skills/{icebox,quest,red-ink}/SKILL.md`, `RELEASING.md`, `AGENTS.md`/`CLAUDE.md`, `.{agents,claude,pi}/skills/` renders, and `test/skills.sh` (`skills.1`) | Editing external yap skills (`~/.gemini/config/skills/diff`, `red-ink-diff`) outside this repo or adopting `jj` |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Adds zero languages, zero libraries (`git merge-tree --write-tree` is built into Git 2.56.0 already on the `bash` libs line and invoked via OCaml `Unix.create_process_env`), and zero new top-level CLI surfaces (`bp3 harness desk` and `bp3 release` are already signed). No edit to `CONSTRAINTS.md`.
- **Common-sense pass (`CONTEXT.md`):**
  - Q3 Scaling (`CONTEXT.md:39,44`, checked 2026-11-19): *"A git worktree per agent or task is the mainstream isolation"* and *"Merging is its own gated step: Gas Town's Refinery bisects a merge queue, Symphony moves Human Review to Merging to Done. bp3: only the owner promotes."* Tiered CAS `merge-tree` + ephemeral verification brings merge-queue ergonomics locally while keeping `BP3_DECIDER=human` as the release gate.
  - Q1 Orchestration (`CONTEXT.md:23`, checked 2026-11-19): *"Exact work lives in deterministic scripts and judgment in the agent."* Putting rebase-abort, `merge-tree`, drift classification, and CAS retries in OCaml keeps agents out of fragile git state machines.
  - Review loops (`CONTEXT.md:98`, checked 2026-11-19): *"An approval covers one specific commit."* A 2-parent plumbing merge commit keeps parent 2 at the exact graded commit SHA (`ledger.jsonl` bindings never drift) while verifying the merged tree deterministically before CAS.
  - Q5 Learning (`CONTEXT.md:61-62`, checked 2026-11-19): *"Always-loaded context beats triggered skills."* Pairing `AGENTS.md`/`CLAUDE.md` with `.gitignore` and deterministic CLI doors avoids relying on skill prose alone.

## Human touchpoints

| When | Owner |
|---|---|
| Approve quest frame (optional `/red-ink`) | owner |
| Promote & release after `2026-11-25-central-desks-dir` lands (`goal_fin`: `/warden` + `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-draft-desk-guard`) | owner |

## Nodes

### Milestone: draft

| Node | TL;DR |
|---|---|
| [draft.1 - draft-desk-cli](nodes/node-draft-1-draft-desk-cli/NODE.md) | central `drafts/<slug>` desks (`prepare\|release\|land --draft <slug>` with 3-attempt CAS rebase loop), `target_branch`/`target_dirty` on `desk list`, `do_remove` `main_root ()` fix, completions, `.gitignore`, `test_layout.ml` + `worktree.sh` + `completion.sh` |

### Milestone: release

| Node | TL;DR |
|---|---|
| [release.1 - cas-merge-release](nodes/node-release-1-cas-merge-release/NODE.md) | pure `Release.is_doc_only_path` + `classify_drift`, in-memory `git merge-tree --write-tree` + tiered ephemeral-worktree verification + 2-parent plumbing merge commit + 3-attempt CAS retry loop + `--ff-only` + `--dry-run` preview, `test_release.ml` + `release-door.sh` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - planning-worktree-guards](nodes/node-skills-1-planning-worktree-guards/NODE.md) | wire clean-runway guard into `skills/{icebox,quest,red-ink}/SKILL.md`, update `RELEASING.md` + `AGENTS.md`/`CLAUDE.md`, re-render `.{agents,claude,pi}/skills/`, lock with `test/skills.sh` |

## Scorecard

| Row | Baseline (2026-11-25, `e60eb8a`) | Target | Read from |
|---|---|---|---|
| `bp3 harness desk prepare\|release\|land --draft <slug>` | refused (`E_USAGE`) | full lifecycle with 3-attempt CAS rebase loop & clean conflict abort | `test/worktree.sh` |
| Parallel disjoint quests `q1` + `q2` promoting sequentially | `q2` refused (`E_NOT_FAST_FORWARD`) | `q2` auto-merges via `merge-tree`, verifies merged tree, preserves `q2` graded SHA as `HEAD^2`, tags `v0.2.0` | `test/release-door.sh` |
| Conflicting merge or failing merged-tree verify | manual rebase required | typed `E_MERGE_CONFLICT` / `E_VERIFY_FAILED`, `master` untouched, ephemeral desk removed | `test/release-door.sh` |
| review-scratch patterns in `.gitignore` | 0 | 3 (`*.red-ink.md`, `*.2b-reviewed.md`, `*.2b-reviewed.md.snapshot`) | `.gitignore` |
| planning skills guarded (`icebox`, `quest`, `red-ink`) + `AGENTS.md`/`CLAUDE.md` | 0/4 | 4/4 + all rendered copies in sync | `test/skills.sh`, `./bin/bp3 skills check` |

## Risks and red chair

Red chair of the plan AND the owner's prompt:

- **Attack 1 (Critical — pessimistic blocking of drafts while quests run causes permanent starvation at N = 5 parallel quests):**
  - Freezing `master` whenever any quest desk is open starves drafts whenever a factory runs continuously, and still fails when parallel quests finish out of order.
  - **Settled in `draft.1` + `release.1`:** Zero blocking on active quests. Drafts land immediately via 50ms CAS rebase loop; `bp3 release` merges over concurrent `master` drift via in-memory `git merge-tree --write-tree` + tiered verification + 2-parent merge commit + CAS retry loop.
- **Attack 2 (Critical — semantic conflicts between textually disjoint code quests could break `master` if merged blindly):**
  - Two quests touching different files can pass `git merge-tree --write-tree` cleanly and still fail to compile or fail tests (e.g., renamed function signature).
  - **Settled in `release.1`:** `Release.classify_drift` uses a strict allowlist for `Doc_only` (`docs/icebox/**`, `docs/dossiers/**`, `docs/quests/<other>/**` with zero `..` traversal). Any other drift classifies as `Code` and **must** pass full deterministic verification (`make check-full` or `BP3_RELEASE_VERIFY_CMD`) inside an ephemeral detached worktree at the merged tree before CAS; failure emits `E_VERIFY_FAILED`, deletes the ephemeral worktree, and leaves `master` untouched. Even `Doc_only` drift runs fast `make lint` when present.
- **Attack 3 (Major — rebasing a quest branch at release time would rewrite every graded commit SHA and break `ledger.jsonl` bindings):**
  - **Settled in `release.1`:** `bp3 release` never rebases `quest/<q>`. When `master` moved ahead, it constructs a 2-parent plumbing merge commit (`-p old_target_tip -p source_tip`) over the merged tree + release files (`QUEST.md` landed, version sync), preserving `source_tip` (and every graded node commit SHA) verbatim as `HEAD^2`.
- **Attack 4 (Major — invoking `release --draft` or `land --draft` from inside the draft desk falsely triggers `E_MAIN_WORKTREE`, and a failed rebase could leave the desk in rebase limbo):**
  - `src/quest/worktree.ml:141-144` compares `abs` against `git rev-parse --show-toplevel` on `root`, falsely rejecting linked worktrees when `cwd` is inside them.
  - **Settled in `draft.1`:** `do_remove` guards against `main_root ()` and runs `git -C (main_root ()) worktree remove` + `git -C (main_root ()) branch -d`. On rebase conflict, `land --draft` runs `git -C <draft_path> rebase --abort` immediately and returns `E_MERGE_CONFLICT` with the desk clean.
- **Attack 5 (Major — `plumbing_commit` in `release_io.ml` currently reads `base_tip` and takes a single `-p base_tip`, and release file sync (`gitx.ml` version) must read from the merged tree, not stale `source_tip`):**
  - If Quest 1 bumped `src/quest/gitx.ml` to `0.5.0` on `master` and Quest 2 branched from `0.4.0`, reading `gitx.ml` from `source_tip` would read stale `0.4.0` (and `git merge-tree` might conflict on `gitx.ml` ONLY because of the `bp3_version` line!).
  - **Settled in `release.1`:** `plumbing_commit` takes `~base_tree` + `~parents` (1 parent for FF, 2 parents `[old_target_tip; source_tip]` for merge) and reads `QUEST.md` / `src/quest/gitx.ml` / `VERSION` from `base_tree` (via `git show <base_tree>:<path>`), after `merge-tree` resolves clean merges. If `gitx.ml` actually conflicted in `merge-tree`, `E_MERGE_CONFLICT` surfaces it plainly (remember quests never edit `bp3_version` — only `bp3 release` bumps it on `master`, so `source_tip` matches `merge_base` on that line and `git merge-tree` auto-takes `master`'s bumped line with zero conflict!).

## Open questions

None — all design calls settled with the owner on 2026-11-25.

## Node diagram

```text
Prerequisite (quest dep): 2026-11-25-central-desks-dir (must land first)
                             │
                             v
Wave 1: draft.1 (draft-desk-cli: Layout.draft_desk_dir + draft_branch,
                 bp3 harness desk prepare|release|land --draft <slug> [3-attempt CAS rebase],
                 desk list target_branch/target_dirty, do_remove main_root fix,
                 names.ml, completions, .gitignore, test_layout.ml + worktree.sh + completion.sh)
                             │
                             v
Wave 2: release.1 (cas-merge-release: Release.is_doc_only_path + classify_drift,
                   git merge-tree --write-tree + tiered ephemeral-worktree verification +
                   2-parent plumbing merge commit + 3-attempt CAS retry + --ff-only + --dry-run,
                   completions, test_release.ml + release-door.sh)
                             │
                             v
Wave 3: skills.1 (planning-worktree-guards: skills/{icebox,quest,red-ink}/SKILL.md,
                  RELEASING.md, AGENTS.md + CLAUDE.md sync, .{agents,claude,pi}/skills renders,
                  test/skills.sh)
```
