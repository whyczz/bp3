---
status: active
home_repo: bp3
date: 2026-11-23
bump: minor
---

# fast-agy-induct: sub-3-minute grades, parallel agy coders, first-class agy harness

TL;DR
Cut quest wall time by ~60-70% and make Gemini/Antigravity (`agy`) a first-class harness in `bp3`. Deterministic scripts (`scripts/red-first` + `scripts/receipt`) prove `BASE_FAIL_HEAD_PASS` and gate exit codes before any LLM grader spawns, replacing manual 9-15-mutant LLM scratching. Graders stay strictly read-only, bounce `needs_fix` only on `critical`/`major` findings (`[minor]` ships as a follow-up note), and run delta-only checks on cycle 2+. On `agy`, `induct-inline` gains lane-based model tiering (`flash` for micro/docs/prose, `pro`/`inherit` for engine nodes) and parallel authoring for independent `ready` nodes via `/swarm` (`fork: "coordinator"` + `workspace: "share"`, with the coordinator as the sole `bp3 q` writer and cold non-forked graders). `bp3` gains a shared `Tx` core + `Agy_tx` transcript reader for `metrics scrape`, `bin/bp3` `--harness=agy` + `.agents/hooks.json`, and `agy`/`claude`/`pi` in `Store.identity`.

ELI5
On the last 5-node quest, writing code took 57 minutes and waiting on graders took 111 minutes — 16 grades across 5 nodes, and 10 of 11 rejections were minor wording nits or vacuous tests that a 20-second script could have caught. Now a script proves your tests fail on parent code before handoff, graders stop hand-planting 15 mutants every round, cycle 2 only checks the new diff, and `agy` can fork warm coders into parallel worktrees for independent nodes while measuring every `agy` run in `metrics scrape`.

## Context

Promoted from `docs/icebox/2026-11-19-fast-grader.md` (trigger fired: owner framed the next induct-loop quest on 2026-11-23, and grades hit 11.2 min max / 6.3 min median across 16 rounds on `2026-11-22`), copied verbatim to [ICEBOX.md](ICEBOX.md). Supersedes the on-hold draft `docs/quests/2026-11-19-fast-grader/QUEST.md` (which proposed role-swap; settled 2026-11-23 with owner to keep graders strictly read-only).

Measured ground (read 2026-11-23 from `bp3 q 2026-11-22-induct-inline-as-default-measure-author metrics r` and node ledgers):

| Fact | Source |
|---|---|
| 5 nodes took 16 grades (3.2 cycles/node): `grade_wall_s` sum **6,675s (111.3 min)**, median **377s (6.3 min)**, max **674s (11.2 min)** | `bp3 q 2026-11-22-induct-inline-as-default-measure-author metrics r` |
| `author_wall_s` sum **3,411s (56.9 min)** (`active_s` 3,292s); grading was **66%** of compute and burned **494,746** grader output tokens vs **204,522** author output tokens | same |
| Of 11 `needs_fix` bounces: **1** real prod bug (`brief.2` c1), **4** vacuous tests (`can't fail`), **4** `[minor]`-only bounces (e.g. error-message wording `'no whitespace'`, build-note window count), **2** `skills.sh` prose-grep nits (`skills.2-inline-yolo` took 4 cycles / 23.5 min for a 71-line Markdown file) | `git show refs/heads/bp3/node/2026-11-22-induct-inline-as-default-measure-author/<n>:.../ledger.jsonl` |
| `GRADING.md:27-29` instructs every grader to hand-plant mutants in a scratch copy on every round (`"15 mutants red"`, `"9 mutants red"`); `brief.ml:85` tells cycle 2+ `"Re-judge the gates in full"` | `GRADING.md`, `src/quest/brief.ml` |
| `Store.identity` (`src/quest/store.ml:59-61`) allows only `["muse-code"; "codex"; "muse"; "human"]` — `claude`, `pi`, and `agy` fail `E_IDENTITY` | `src/quest/store.ml` |
| `bin/bp3:83-91` knows `pi`, `claude`, `codex`, `muse` (no `agy` target, no `.agents/hooks.json`); `src/quest/hooks.ml` reads snake_case (`tool_input.command`) only, not `agy` camelCase (`conversationId`, `toolCall.args.CommandLine`) | `bin/bp3`, `src/quest/hooks.ml`, `agy-customizations/docs/hooks.md` |
| `src/quest/metrics_io.ml` scans only `~/.claude/projects` and `~/.pi/agent/sessions`; `pi_tx.ml` imports `Claude_tx` internals directly (`usage`, `cost`, `seconds`, `paired`) | `src/quest/metrics_io.ml`, `src/quest/pi_tx.ml` |
| `agy` writes JSONL transcripts to `~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl` with `step_index`, `type` (`USER_INPUT`, `PLANNER_RESPONSE`, `GENERIC`), `created_at`, `model`, `input_tokens`, `cache_read_tokens`, `output_tokens`, `tool_calls` | inspected live `transcript.jsonl` (2026-11-23) |
| `agy`'s default terminal sandbox returns `EPERM` on writes to `.git/bp3/` (observed running `./bin/bp3 config`); keeping workers off `bp3 q` and making the coordinator the sole `bp3 q` writer avoids sandbox friction in parallel `/swarm` runs | observed live (2026-11-23) |
| Pending input: `docs/learn/get-good-harness-engineering.md` (Grok report, in progress) will be folded in during red-ink before approval | owner (2026-11-23) |

Owner decisions settled during framing (2026-11-23):
1. Bundle fast grading + `agy`/parallel swarm into one quest (`fast-agy-induct`), first in a 3-quest sequence (`fast-agy-induct` -> `warden-v0` -> `codebase-diet`).
2. Keep the grader **strictly read-only**; warm inline author or warm `/swarm` `@coder` applies `critical`/`major` fixes (no role-swap).

## Terms

| Term | Meaning |
|---|---|
| `red-first` | `scripts/red-first <sha>`: runs a commit's changed tests against its parent's code in a temp detached worktree and expects red (`refactor:` expects green); prints one status line and exits 0 (ok/n/a), 1 (FAIL), or 2 (usage) |
| `receipt` | `scripts/receipt [<sha>]`: prints 4 deterministic lines for a clean commit (`sha + subject`, `check-full rc + summary`, `red-first` line, `tests:` changed/added/deleted test-file/assertion delta); exits 0 iff clean, gate green, and `red-first` not FAIL |
| delta brief | `Brief.render` on cycle 2+: scopes the grader to `scripts/receipt`, `git diff <prev7>..<sha7>` (excluding `others`), and acceptance gates touched by that diff — never quoting author-typed `--reason` |
| severity gate | grading rule in `GRADING.md` + `Brief.render`: ONLY `critical` or `major` findings (broken gate, proven bug, weakened/vacuous test, constraint violation) cast `needs_fix`; `[minor]` findings ship as non-blocking follow-ups |
| `Tx` | new shared module `src/quest/tx.ml`: harness-neutral `usage`, `cost`, `tool_event` (`name`, `cmd_head`, `is_error`, `start_s`, `end_s`, `step`), timestamp `seconds`, interval `merge`/`measure`/`inter`, `paired` spans, and join helpers used by `Claude_tx`, `Pi_tx`, `Agy_tx`, and `Warden` Layer 2 |
| `Agy_tx` | new module `src/quest/agy_tx.ml`: pure parser for `agy` `transcript.jsonl` files producing `Tx.cost` + author windows |
| `agy` | canonical harness spelling in `bin/bp3`, `Store.identity`, `metrics_io.ml`, and `CONSTRAINTS.md` (one concept, one word — never `antigravity` or `gemini-cli` in CLI flags) |
| swarm parallel mode | optional `induct-inline` mode on `agy` when >=2 independent `ready` nodes have disjoint file boundaries: coordinator forks warm `@coder-*` workers (`fork: "coordinator"`, `workspace: "share"`), spawns non-forked cold `@grader` subagents in detached grade desks, and acts as sole `bp3 q` writer & serial merger |

## Inputs

| Input | Source |
|---|---|
| commit SHA (default `HEAD`) | author's clean commit, passed to `scripts/red-first` and `scripts/receipt` |
| `test/suites.tsv` | suite selection for `red-first` via `scripts/check-changed.sh --list` |
| `NODE.md` (`## Acceptance gates`, `Lane`), `GRADING.md` at bound commit | read via `git show <commit>:...` by `Brief.inputs` |
| `agy` transcripts | `~/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl` (override via `--agy-dir` in tests) |
| `agy` hook payload (stdin JSON) | camelCase `conversationId`, `hookEventName`, `toolCall.name`, `toolCall.args.CommandLine`, `error` |
| `BP3_HARNESS` | env var, now accepting `muse-code`, `codex`, `muse`, `human`, `claude`, `pi`, `agy` |

## Outputs

| Output | Shape |
|---|---|
| `scripts/red-first` | one line: `red-first: red (<suite>)` \| `green (refactor)` \| `n/a (<why>)` \| `FAIL (<why>)`; rc 0 / 0 / 0 / 1; usage 2 |
| `scripts/receipt` | 4 deterministic lines (sha+subject, check-full summary, red-first line, test-delta line); rc 0 pass, 1 fail, 2 usage/dirty |
| `bp3 q <q> n <n> brief` | cycle 1: full scoped brief (receipt + 1 adversarial probe, no 15-mutant hunt, severity gate); cycle 2+: delta brief over `<prev7>..<sha7>` |
| `bp3 q <q> metrics scrape` | scans `agy` transcripts alongside Claude & pi, writing `grade.*` (`self_checked`) and `author.*` (`wall_s`, `active_s`, `tool_s`, tokens) with `run: "agy:<conv-id>"` |
| `bin/bp3 skills install --harness=agy` | installs `.agents/skills/*` and `.agents/hooks.json` (named-group `agy` hook schema) |
| `skills/induct-inline/SKILL.md` (+ renders) | updated default workflow: receipt before handoff, read-only severity-gated grader, `agy` model tiering + `/swarm` parallel `ready`-node mode |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ls scripts/red-first scripts/receipt
ls: scripts/red-first: No such file or directory
ls: scripts/receipt: No such file or directory
$ BP3_HARNESS=agy ./bin/bp3 q r 2026-11-22-induct-inline-as-default-measure-author
{"ok":false,"error":{"code":"E_IDENTITY","facts":{"harness":"agy"},...}}
$ ./bin/bp3 skills install --harness=agy
unknown harness: agy
$ rg -n "plant the bug in a scratch copy" GRADING.md
28:plant the bug in a scratch copy and watch the check go red.
$ rg -n "Re-judge the gates in full" src/quest/brief.ml
85:        [ "Previous round: " ^ p7 ^ " was graded needs_fix. Re-judge the gates in full; \
```

Design trace (after quest lands):

```text
verify.1  ./scripts/red-first <commit-with-new-test> -> "red-first: red (<suite>)" rc 0 (<30s)
          ./scripts/red-first <commit-with-vacuous-test> -> "red-first: FAIL (tests passed on parent)" rc 1
          ./scripts/red-first <refactor-commit> -> "red-first: green (refactor)" rc 0
verify.2  ./scripts/receipt HEAD -> 4 lines (sha, check-full rc=0, red-first, test-delta) rc 0; dirty tree -> rc 2
grade.1   bp3 q q1 n nd brief (c1) -> no manual mutant rule, severity gate present, asks for receipt + 1 adversarial probe
          bp3 q q1 n nd brief (c2) -> delta brief over git diff <prev7>..<sha7>, no SENTINEL-REASON leak
agy.1     metrics scrape --agy-dir <fixture> -> grades self_checked=1, author authored=1, run="agy:<id>"
          BP3_HARNESS=agy bp3 q ... -> accepted (no E_IDENTITY)
agy.2     BP3_COMPLETIONS_DIR=<tmp> ./bin/bp3 skills install --harness=agy -> writes .agents/skills/* + .agents/hooks.json
          echo '{"conversationId":"c1","hookEventName":"PostToolUse","toolCall":{"name":"run_command","args":{"CommandLine":"make check"}}}' | ./bin/bp3 q hooks -> exit 0, parsed cleanly
skills.1  skills/induct-inline/SKILL.md + all renders carry receipt, severity gate, agy model tiering, and /swarm parallel mode; skills.sh + mode.sh green
dogfood.1 metrics r on this quest -> agy grades & authors measured (0 author_missing), median grade wall <= 180s, mean cycles <= 1.5/node, >=2 wave-1 nodes authored in parallel
all       make check-full rc 0
```

## Goal and why

Cut quest wall time from ~2.8 hours down to under an hour and make `agy` a native, fast harness for `bp3`. Measured data on `2026-11-22` proved that grading — specifically manual LLM mutant-planting, full re-grades on cycle 2+, and `[minor]`-only bounces — caused 66% of quest compute time and 10 of 11 `needs_fix` cycles. Replacing vacuous-test detection with a 20-second deterministic `red-first` script, scoping cycle 2+ to delta diffs, and unlocking warm forked `/swarm` coders on `agy` removes all three bottlenecks at the root while preserving `bp3`'s core invariant (cold independent verification bound to exact commits).

## Success picture

- `scripts/red-first` and `scripts/receipt` catch vacuous tests in <30s before handoff and produce the handoff reason deterministically.
- `GRADING.md` and `Brief.render` eliminate manual multi-mutant hunting and minor-only bounces; cycle 2+ reviews deltas only without leaking author rationale.
- `agy` is a full first-class harness: `bin/bp3 skills install --harness=agy`, `bp3 q hooks` camelCase support, `BP3_HARNESS=agy`, and `metrics scrape` reading `agy` transcripts through shared `Tx`.
- `induct-inline` documents `agy` model tiering (`flash`/`pro`) and `/swarm` parallel `ready`-node authoring with the coordinator as sole `bp3 q` writer.
- Dogfooding this quest on `agy` hits median grade wall <= 180s (vs 377s baseline) and mean cycles <= 1.5/node (vs 3.2 baseline), with wave-1 nodes (`verify.1`, `agy.1`, `agy.2`) authored in parallel.

## Scope

| In | Out |
|---|---|
| `scripts/red-first`, `scripts/receipt`, their fixture tests, `test/suites.tsv` rows | role-swap (grader writing fixes) — settled read-only |
| `src/quest/brief.ml`, `GRADING.md`, `src/quest/names.ml` (delta brief + severity gate) | Warden plugs / `/warden` skill (`2026-11-23-warden-v0` quest) |
| `src/quest/tx.ml`, `src/quest/agy_tx.ml`, `src/quest/claude_tx.ml`, `src/quest/pi_tx.ml`, `src/quest/metrics_io.ml`, `src/quest/store.ml` | deleting Muse JS workflows, `bp3-pi`, or `harness.ml` (`2026-11-23-codebase-diet` quest) |
| `bin/bp3` (`--harness=agy`, `.agents/hooks.json`), `src/quest/hooks.ml` (camelCase), `CONSTRAINTS.md` (`agy` sign-off row) | Python `run_workflow` scripts tracked in repo (would require Python in `CONSTRAINTS.md`; `/swarm` + `invoke_subagent` need none) |
| `skills/induct-inline/SKILL.md` (+ renders) as its own skill node | changing `bp3 q` FSM edges, plans, or owner-gated `goal_fin` |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):**
  - Languages & libs: OCaml (`stdlib`, `unix`, `str`, `yojson`, `ounit2`, `qcheck-*`) and Bash (`posix`, `git`, `jq`, `shellcheck`) — all already signed. Zero new languages or libraries.
  - Surfaces (`CONSTRAINTS.md:54`): adds **`agy`** to the driven harness CLIs line (`claude`, `pi`, `codex`, `agy`). **Requires owner sign-off row** in `CONSTRAINTS.md` before `agy.2` lands (pitch: `agy` is already the active daily harness; boring alternative is running `agy` through `codex`'s `.agents/skills` without hooks or `metrics scrape`, leaving `agy` runs unmeasured).
- **Common-sense pass (`CONTEXT.md`, claims checked 2026-11-19/20, within 90 days):**
  - Separate read-only verifier (`CONTEXT.md:93`, `94`): kept intact (dropped `fast-grader`'s experimental role-swap, which had no prior art).
  - Deterministic checks beat LLM judgment (`CONTEXT.md:96`, `100`): `scripts/red-first` + `scripts/receipt` check `BASE_FAIL_HEAD_PASS` and test-count deltas mechanically before the grader starts.
  - Delta-only re-reviews (`CONTEXT.md:99`): brings `bp3` in line with Anthropic's code review loop (eliminates full re-grades on cycle 2+).
  - No author rationale in grader brief (`CONTEXT.md:104`): delta cycle 2+ still never quotes `--reason`; scopes mechanically to `git diff <prev7>..<sha7>`.
  - Parallel only across independent nodes (`CONTEXT.md:22`, `39`): `/swarm` forks warm coders into `workspace: "share"` only for disjoint `ready` nodes; 1 writer per node.

## Human touchpoints

| When | Owner |
|---|---|
| Fold in Grok report (`docs/learn/get-good-harness-engineering.md`) + approve frame + sign `CONSTRAINTS.md` `agy` row | owner |
| Each grade | fresh cold grader subagent (read-only) |
| Promotion (`goal_fin`) | owner |

## Nodes

### Milestone: verify

| Node | TL;DR |
|---|---|
| [verify.1 - red-first](nodes/node-verify-1-red-first/NODE.md) | `scripts/red-first` proves changed tests fail on parent's code in a detached temp worktree (<30s); `refactor:` expects green |
| [verify.2 - receipt](nodes/node-verify-2-receipt/NODE.md) | `scripts/receipt` prints 4 deterministic handoff lines (sha, `check-full`, `red-first`, test-file/assertion delta) |

### Milestone: grade

| Node | TL;DR |
|---|---|
| [grade.1 - delta-brief](nodes/node-grade-1-delta-brief/NODE.md) | `GRADING.md` + `Brief.render`: drop manual mutant-planting, enforce `critical`/`major`-only `needs_fix`, make cycle 2+ delta-only over `<prev7>..<sha7>` |

### Milestone: agy

| Node | TL;DR |
|---|---|
| [agy.1 - tx-core-and-scrape](nodes/node-agy-1-tx-core-and-scrape/NODE.md) | extract shared `src/quest/tx.ml`, add `src/quest/agy_tx.ml` + `metrics_io.ml` scan for `agy` transcripts, allow `agy`/`claude`/`pi` in `Store.identity` |
| [agy.2 - cli-hooks-and-install](nodes/node-agy-2-cli-hooks-and-install/NODE.md) | add `agy` to `bin/bp3` (`.agents/skills` + `.agents/hooks.json`), camelCase parsing in `src/quest/hooks.ml`, and `agy` row in `CONSTRAINTS.md` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - agy-induct-inline](nodes/node-skills-1-agy-induct-inline/NODE.md) | update `skills/induct-inline/SKILL.md` (+ renders) for receipts, severity gate, `agy` model tiering (`flash`/`pro`), and `/swarm` parallel `ready`-node mode (skill node) |

### Milestone: dogfood

| Node | TL;DR |
|---|---|
| [dogfood.1 - benchmark-and-sandbox-check](nodes/node-dogfood-1-benchmark-and-sandbox-check/NODE.md) | prove `agy` metrics scrape (0 `author_missing`), <=180s median grade wall, <=1.5 mean cycles, and parallel wave-1 execution on this quest's own run |

## Scorecard

| Row | Baseline (`2026-11-22`) | Target | Read from |
|---|---|---|---|
| grade wall median | 377s (6.3m) | **<= 180s (3m)** | `bp3 q <q> metrics r` |
| mean cycles / node | 3.2 (16/5) | **<= 1.5** | `bp3 q <q> metrics r` (`grades / nodes`) |
| minor-only `needs_fix` | 4 / 11 | **0** | node ledgers |
| `red-first` wall time | n/a | **< 30s** | `scripts/red-first` timing |
| `agy` scrape coverage | 0% | **100%** (0 `author_missing`, 0 `owner_graded`) | `bp3 q <q> metrics scrape` |
| wave-1 parallel overlap | 0 authored in parallel | **>= 2 nodes authored concurrently** | ledger timestamps + `/swarm` |

## Risks and red chair

- **Strongest attack (engineering — delta brief weakens review):** "If cycle 2+ only inspects `git diff <prev7>..<sha7>` and never sees the prior grader's findings, how does the cycle-2 grader know whether a cycle-1 bug was actually fixed instead of swept under the rug?"
  - **Settled in design:** `grade.1` requires cycle 2+ to (1) re-run `./scripts/receipt` (proving `check-full` green, `red-first` red, and no test-count shrinkage), (2) inspect `git diff <prev7>..<sha7>` in full, and (3) verify every `NODE.md` acceptance gate touched by `<prev7>..<sha7>` — without quoting author-typed `--reason`. Any unfixed acceptance failure or weakened test is still caught directly from the gates + diff + receipt.
- **Second attack (test-weakening / Goodhart's law, `CONTEXT.md:102`):** "If we remove manual mutant-planting from `GRADING.md`, an author could delete or weaken an existing test and still pass `red-first`."
  - **Settled in design:** `verify.2` (`scripts/receipt`) prints explicit test-line/assertion delta counts (`+added / -removed` across `test/`), and `grade.1` makes any unjustified test deletion or weakening a `critical` `needs_fix` ground, plus keeps **1 targeted adversarial probe** (not 15!) per grade.
- **Third attack (sandbox `.git/` wall in `/swarm`):** "Forked `/swarm` workers on `agy` hit `EPERM` if they touch `.git/bp3/`."
  - **Settled in design:** `skills.1` explicitly restricts `/swarm` coders to editing code, running `make check` inside the sandbox, and committing on their `workspace: "share"` branch; **only the coordinator** runs `bp3 q` / `bp3 harness desk` / `git merge`.
- **Attack on source (`ICEBOX.md` + owner prompt):**
  - *Icebox assumption rejected:* `docs/icebox/2026-11-19-fast-grader.md` proposed author self-mutation notes in commit messages; replaced with deterministic `scripts/red-first` (zero token waste, mechanically verified).
  - *`agy` transcript schema drift (major concern):* `agy`'s `transcript.jsonl` is an internal format, not a public contract (`truncated_fields` may omit long prompts/commands). **Settled in `agy.1`:** `Agy_tx` checks `truncated_fields` and falls back to `transcript_full.jsonl` when `USER_INPUT` or tool args are truncated, and self-checks token fields (`bad_usage > 0` refuses writing silent zeros, matching `Pi_tx`/`Claude_tx`).
  - *Wave-1 parallelism verification (major concern):* claiming `/swarm` works with `bp3` without testing it on real nodes would be speculation. **Appended as `dogfood.1`:** explicitly proves parallel wave-1 authoring + `agy` scrape + wall-time targets on this quest itself.

## Open questions

1. Fold in findings from `docs/learn/get-good-harness-engineering.md` (Grok report) once written before owner approval — **owner + agent**.
2. Owner sign-off wording for adding `agy` to `CONSTRAINTS.md` (`Surfaces`, driven harness CLIs) — **owner**.
3. Cancel the superseded draft `docs/quests/2026-11-19-fast-grader/QUEST.md` and delete `docs/icebox/2026-11-19-fast-grader.md` at approval per icebox promotion rules — **owner**.

## Node diagram

```text
Wave 1 (parallel — disjoint files, /swarm ready):
  verify.1 (red-first) ──► verify.2 (receipt) ──► grade.1 (delta-brief) ──┐
  agy.1 (tx-core + agy_tx + Store.identity) ──────────────────────────────┼──► skills.1 (agy-induct-inline) ──► dogfood.1 (benchmark)
  agy.2 (bin/bp3 agy + camelCase hooks + CONSTRAINTS) ────────────────────┘
```
