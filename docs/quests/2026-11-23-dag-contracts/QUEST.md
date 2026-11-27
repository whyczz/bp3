---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# dag-contracts: typed node flavors (`code | direct | research | explore | human-gate`) and protected-file locks

TL;DR
Upgrade `bp3`'s DAG from one-size-fits-all code commits to **five explicit node flavors** (`code | direct | research | explore | human-gate`) plus a lightweight protected-file lock on `handoff`, built on top of `2026-11-23-dag-fsm-v2`. Replace `Store.plan_knobs_from_text`'s 3-knob substring parser with a real OCaml `node_kind` variant so:
- **`code`** (default) runs handoff + cold AI grade -> landed,
- **`direct`** lands fast verified commits directly with no AI grade,
- **`research`** searches the web/repo, commits a sourced report, and may refine downstream `todo` `NODE.md` / `QUEST.md` specs (docs-only, never touches `src/`),
- **`explore`** runs bounded hands-on experiments (`--target`, `--max-iterations`), commits artifacts + `REPORT.md` under `docs/quests/<q>/explores/<node>/` (isolated from prod code, and may update downstream `todo` `NODE.md` / `QUEST.md` followed by a `human-gate`), and closes with `--outcome hit | missed | inconclusive`, and
- **`human-gate`** pauses cleanly in the DAG for `BP3_DECIDER=human approve` in interactive `/induct` — or lets `/induct-yolo` decide and keep moving via `BP3_DECIDER=human-approved-llm-yolo approve --reason "..."` (recording `decider: "human-approved-llm-yolo"` honestly in the ledger, surfaced in `bp3 q r` `yolo_approvals`, and justified in `LOG.md` + the final check-in report) instead of stalling or abusing `block`/`resume`.

A small `E_PROTECTED_FILE` check on `handoff` mechanically blocks silent edits to `GRADING.md`, `CONSTRAINTS.md`, `scripts/receipt`, `scripts/red-first`, or a node's own `NODE.md` unless `--allow-protected` is passed. *(Owner killed `--owns` globs and `parallel_batches` on 2026-11-25 — parallelism happens across quests via `v0.6.0`–`v0.10.0` desks + Tiered CAS, not intra-quest `/swarm`.)*

ELI5
Today every task in a quest — whether it's a web-research pass, a bounded 15-minute experiment, a quick doc fix, or a human sign-off checkpoint — is crammed into the exact same heavy code-commit pipeline, and stopping an agent from editing `GRADING.md` or its own `NODE.md` relies on asking politely in a prompt. This quest teaches `bp3` five crisp flavors of nodes (`code`, `direct`, `research`, `explore`, `human-gate`) and enforces protected-file locks in OCaml instead of vibes.

## Context

Framed on 2026-11-23 during the post-`warden-v0` DAG engine review, and reshaped on 2026-11-25 at the owner's call:
- **Killed `--owns` / `parallel_batches` (owner, 2026-11-25):** *"let's kill owns... i dont really use swarm huh, we parallelize over quests."* Cross-quest parallelism is already solved by `v0.6.0`–`v0.10.0` (central desks, Tiered CAS `merge-tree`, auto-cleanup, session-scoped statusline); inside a quest, work is mostly linear or light DAG BFS.
- **Renamed `spike` -> `explore` with explicit targets & iteration bounds (owner, 2026-11-25/26):** *"change spike to explore, terminology wise... experiments and reports, with a time or iteration bound, and a ideal target/direction to hit."* Settled on `--max-iterations` only (no wall-clock `--budget-min`, immune to laptop sleep / API stalls; tokens stay post-hoc via `bp3 q metrics scrape`), allowed to update downstream `todo` `NODE.md` / `QUEST.md` followed by a `human-gate`. Warden evaluates explorations for quality/edge-cases/lessons rather than policing exploration token counts.
- **Added `research` node (owner, 2026-11-25):** searches web/repo, produces a sourced report, and is allowed to update downstream `todo` nodes' `NODE.md` specs.
- **Renamed `gate` -> `human-gate` with explicit `/induct-yolo` decider env var (owner, 2026-11-25/26):** avoids colliding with "Acceptance gates" / "`make check-full` gate", and under `/induct-yolo` the LLM decides, passes the gate honestly via `BP3_DECIDER=human-approved-llm-yolo` (logged as `decider: "human-approved-llm-yolo"` — no new CLI flag, never spoofing `BP3_DECIDER=human`, and rejected by `bp3 release` / `resume` / `delete`), keeps moving, and justifies its call in `LOG.md` and the final check-in report.

Sequencing (refreshed 2026-11-25 against `v0.10.0`):
- **After** `docs/quests/2026-11-23-dag-fsm-v2/` (so all 5 flavors wire straight onto the lean `todo -> handed_off -> landed` FSM with git ancestry already enforced).
- Closes the surviving Goodhart finding from `docs/dossiers/2026-11-23-harness-advice.md` (`CONTEXT.md:100`): `brief.ml:49` asks the grader in prose to flag edits to `GRADING.md`, `CONSTRAINTS.md`, or Acceptance gates, whereas `handoff` enforces it deterministically in milliseconds.

Measured ground (re-verified 2026-11-25 on `v0.10.0` from `src/quest/store.ml`, `src/quest/render.ml`, `src/quest/brief.ml`):
- `Store.plan_knobs_from_text` (`src/quest/store.ml:73-102`) parses YAML via `contains_sub` for only 3 booleans (`max_cycles`, `grade_required`, `verify_required`); there is no `Research`, `Explore`, or `Human_gate` node lifecycle.
- `Render.commit_changes` (`src/quest/render.ml:9`) already extracts the exact changed file list of any commit via `git diff-tree --no-commit-id --name-status -r <sha>`.
- `brief.ml:49` relies on grader prose to flag edits to `GRADING.md`, `CONSTRAINTS.md`, or Acceptance gates.

## Terms

| Term | Meaning |
|---|---|
| `node_kind` | typed OCaml variant `Code \| Direct \| Research \| Explore \| Human_gate` declared via `--kind` at node creation (default `Code`), stored in the node create ledger line |
| `Research` | docs-only node (`--kind research`): searches web/repo, commits a sourced report (`docs/quests/<q>/research/<node>/` or `docs/dossiers/`), and may edit `QUEST.md`, `LOG.md`, and downstream `todo` `NODE.md` files; refuses code edits (`E_DOC_ONLY_NODE`) |
| `Explore` | bounded experiment node (`--kind explore --target "..." [--max-iterations N]`): commits reproducible experiments + `REPORT.md` under `docs/quests/<q>/explores/<node>/` (refuses prod code edits with `E_DOC_ONLY_NODE`; may update downstream `todo` `NODE.md` / `QUEST.md` followed by a `human-gate`), tracks iterations via `e iterate` (hard stop at `max_iterations`), and closes with `--outcome hit \| missed \| inconclusive` |
| `Human_gate` | generic human decision checkpoint (`--kind human-gate`): takes `approve` gated by `BP3_DECIDER=human` (`decider: "human"`) or `BP3_DECIDER=human-approved-llm-yolo` (`decider: "human-approved-llm-yolo"`, for unattended `/induct-yolo`, surfaced in `bp3 q r` `yolo_approvals` and justified in the final report); unset/other `BP3_DECIDER` refuses with `E_HUMAN_REQUIRED`; lands with `commit = None`, never trips Warden `human_steer` |
| `protected_files` | built-in lock list (`GRADING.md`, `CONSTRAINTS.md`, `scripts/receipt`, `scripts/red-first`, and the node's own `NODE.md`, plus any non-`todo` `NODE.md` on `Research`) refused on `handoff` with `E_PROTECTED_FILE` unless `--allow-protected` is explicitly passed |
| `E_DOC_ONLY_NODE` | typed refusal on `handoff` when a `Research` or `Explore` commit touches a non-`docs/` path (e.g. `src/`, `bin/`, `scripts/`) |
| `E_EXPLORE_BOUND` | typed refusal on `e iterate` when an `Explore` node has already reached `max_iterations` (guiding the caller to write `REPORT.md` and close with `handoff --outcome ...`) |

## Inputs

| Input | Source | Precedence / Notes |
|---|---|---|
| `--kind code\|direct\|research\|explore\|human-gate` | `bp3 q <q> c <n>` | defaults to `code`; replaces ad-hoc `plans/node-*.yaml` hacks for common node shapes |
| `--target <text>` | `bp3 q <q> c <n> --kind explore` | required direction / hypothesis / metric threshold for an `Explore` node |
| `--max-iterations <int>` | `bp3 q <q> c <n> --kind explore` | optional deterministic stop cap on `e iterate` (hard stop -> `E_EXPLORE_BOUND`; no wall-clock `--budget-min` or live token cap) |
| `e iterate --note <text>` | `bp3 q <q> n <n> e iterate` | optional append-only iteration log for `Explore` nodes; refuses past `max_iterations` with `E_EXPLORE_BOUND` |
| `--outcome hit\|missed\|inconclusive` | `bp3 q <q> n <n> e handoff` (for `Explore`) | required on `Explore` handoff; all three outcomes land cleanly (`node_fin`) |
| `--allow-protected` | `bp3 q <q> n <n> e handoff` | explicit opt-in to bypass `E_PROTECTED_FILE` when a node intentionally updates a governance/gate file |
| `BP3_DECIDER=human` or `BP3_DECIDER=human-approved-llm-yolo` | env var on `Human_gate` `approve` edge (`src/quest/store.ml:50`) | unset/other values refuse with `E_HUMAN_REQUIRED`; `human` logs `decider: "human"`; `human-approved-llm-yolo` (for `/induct-yolo`) logs `decider: "human-approved-llm-yolo"` so the LLM can decide, keep moving, and justify the decision in `LOG.md` + the final check-in report. Strictly scoped to `human-gate` `approve`: `bp3 release`, `resume`, and `delete` of blocked nodes remain strictly `BP3_DECIDER=human` |

## Outputs

| Output | Shape |
|---|---|
| `kind` (+ `explore` / `human-gate` metadata) on `bp3 q <q> n <n> r` and `bp3 q r <q>` | `"kind": "explore", "explore": {"target": "...", "max_iterations": 3, "iterations": 2, "outcome": "hit"}`; quest rollup lists `yolo_approvals: [{"node": "g1", "decider": "human-approved-llm-yolo", "reason": "..."}]` |
| `E_PROTECTED_FILE` / `E_DOC_ONLY_NODE` / `E_EXPLORE_BOUND` | typed refusals naming offending paths or iteration cap |
| 5 clean node lifecycles | `Code` (handoff + cold grade), `Direct` (handoff -> landed), `Research` (docs-only report + downstream `todo` `NODE.md` updates -> landed), `Explore` (bounded experiments + report + outcome -> landed), `Human_gate` (`BP3_DECIDER=human` or `BP3_DECIDER=human-approved-llm-yolo` `approve` -> landed) |

## Acceptance gates

Observed today (re-verified 2026-11-25 on `v0.10.0`):

```text
$ rg -n "contains_sub text" src/quest/store.ml
90:    if contains_sub text "required: false" && contains_sub text "grade:" then false
# (3-knob substring parser; zero --kind code|direct|research|explore|human-gate, zero E_PROTECTED_FILE)
```

Design trace (after quest lands):

```text
kinds.1    bp3 q demo c c1   # --kind defaults to code
           handoff c1 with commit editing GRADING.md -> exit 1, E_PROTECTED_FILE
           handoff c1 --allow-protected --commit $C_GRADING -> ok: true
           bp3 q demo c d1 --kind direct
           handoff d1 --commit $C_DOC -> ok: true, state: "landed" (no AI grade)
           bp3 q demo c g1 --kind human-gate --depends-on d1
           approve g1 with BP3_DECIDER unset -> exit 1, E_HUMAN_REQUIRED
           BP3_DECIDER=human bp3 q demo n g1 e approve --reason "go with option B" -> state: "landed", decider: "human"
           bp3 q demo c g2 --kind human-gate --depends-on g1
           BP3_DECIDER=human-approved-llm-yolo bp3 q demo n g2 e approve --reason "chose B: faster, reversible" -> state: "landed", decider: "human-approved-llm-yolo" (listed in bp3 q r yolo_approvals)
           BP3_DECIDER=human-approved-llm-yolo bp3 release demo -> exit 1, E_HUMAN_REQUIRED (release stays strictly human)

research.1 bp3 q demo c r1 --kind research
           handoff r1 touching src/quest/main.ml -> exit 1, E_DOC_ONLY_NODE
           handoff r1 touching docs/quests/demo/research/r1/REPORT.md + downstream todo c2/NODE.md -> ok: true, state: "landed"
           handoff r1 touching already-landed d1/NODE.md -> exit 1, E_PROTECTED_FILE
           bp3 q demo c ex1 --kind explore --target "p99 < 50ms" --max-iterations 2
           bp3 q demo n ex1 e iterate --note "try 1: 80ms" -> ok: true (iterations: 1/2)
           bp3 q demo n ex1 e iterate --note "try 2: 42ms" -> ok: true (iterations: 2/2)
           bp3 q demo n ex1 e iterate --note "try 3" -> exit 1, E_EXPLORE_BOUND
           handoff ex1 touching src/quest/main.ml -> exit 1, E_DOC_ONLY_NODE
           handoff ex1 --commit $C_EXPLORE_REPORT --outcome hit --reason "42ms verified" -> ok: true, state: "landed"

skills.1   skills/{quest,induct,induct-yolo,using-bp3}/SKILL.md + local DEV_SKILLS (.{agents,claude,pi}/skills/) + AGENTS.md/CLAUDE.md + completions synced;
           make check-full rc 0
```

## Goal and why

Let quests express real engineering workflows natively in the DAG — web/codebase research that sharpens downstream node specs (`research`), bounded hands-on experiments with an explicit target and stop cap (`explore`), human sign-off checkpoints (`human-gate`), fast doc/chore commits (`direct`), and cold-graded code nodes (`code`) — while mechanically enforcing `E_PROTECTED_FILE` so agents cannot silently weaken grading or acceptance gates.

## Success picture

- `Research` nodes can search, write sourced reports, and update downstream `todo` `NODE.md` specs in one clean docs-only commit without touching `src/` or already-landed nodes.
- `Explore` nodes carry an explicit `--target` + `--max-iterations` cap, isolate throwaway experiments + `REPORT.md` under `docs/quests/<q>/explores/<node>/`, may update downstream `todo` `NODE.md` specs (followed by a `human-gate`), and land cleanly with `hit | missed | inconclusive`.
- `Human_gate` nodes sit cleanly in the DAG (`BP3_DECIDER=human approve`) — zero more fake `block`/`resume` cycles that trip Warden `human_steer`.
- No node commit can silently modify `GRADING.md`, `CONSTRAINTS.md`, `scripts/receipt`, `scripts/red-first`, or its own `NODE.md` without passing `--allow-protected`.

## Scope

| In | Out |
|---|---|
| Typed `node_kind` (`Code \| Direct \| Research \| Explore \| Human_gate`), clean plan parsing, `Human_gate` `approve` edge, and `E_PROTECTED_FILE` + `--allow-protected` (`kinds.1`) | Per-node `--owns` file globs & `parallel_batches` (killed 2026-11-25 — YAGNI; parallelism is across quests, not intra-quest `/swarm`) |
| `Research` & `Explore` docs-only + downstream `todo` `NODE.md` update rules, and `Explore` `--target` / `--max-iterations` / `e iterate` / `--outcome` (`research.1`) | Lean 2-edge FSM & dep git ancestry (`2026-11-23-dag-fsm-v2`, prerequisite) |
| `skills/` sources, local `DEV_SKILLS` renders (`v0.7.0`), completions, `AGENTS.md`/`CLAUDE.md` (`skills.1`) | Quest exit / promotion (`2026-11-23-quest-promote-release`, landed `v0.4.0`; Tiered CAS `v0.8.0`); external YAML library |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** Zero new languages, libraries, or CLI surfaces. All logic stays pure OCaml (`stdlib`/`str`/`yojson`) inside `src/quest/`.
- **Common-sense pass (`CONTEXT.md`):**
  - *Goodhart's law (`CONTEXT.md:81`, `CONTEXT.md:100`)*: "if a change can modify the check that judges it, the check is broken" — enforced mechanically at `handoff` via `E_PROTECTED_FILE`.
  - *Plan to throw one away (`CONTEXT.md:74`)*: "spike nodes that never land [prod code]" — real in the engine as bounded `--kind explore`.
  - *Humans decide options (`CONTEXT.md:52`)*: first-class `--kind human-gate` instead of abusing `block`/`resume`.
  - *YAGNI (`CONTEXT.md:78`)*: deleted `--owns` / `parallel_batches` before writing a single line of it.

## Human touchpoints

| When | Owner |
|---|---|
| Confirm any remaining edge cases before starting `kinds.1` | owner |
| Promote via `bp3 release` / `/warden` at `goal_fin` | owner |

## Nodes

### Milestone: kinds

| Node | TL;DR |
|---|---|
| [kinds.1 - typed-node-kinds](nodes/node-kinds-1-typed-node-kinds/NODE.md) | typed `Code \| Direct \| Research \| Explore \| Human_gate` node kinds (`--kind`), clean plan parsing, `Human_gate` `approve` edge, `Direct` auto-land, and `E_PROTECTED_FILE` (+ `--allow-protected`) |

### Milestone: research

| Node | TL;DR |
|---|---|
| [research.1 - research-and-explore-nodes](nodes/node-research-1-research-and-explore-nodes/NODE.md) | `Research` & `Explore` docs-only + downstream `todo` `NODE.md` allowlist (`E_DOC_ONLY_NODE`), and `Explore` `--target` / `--max-iterations` / `e iterate` (`E_EXPLORE_BOUND`) / `--outcome` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - contracts-skills-and-completions](nodes/node-skills-1-contracts-skills-and-completions/NODE.md) | update `skills/{quest,induct,induct-yolo,using-bp3}/SKILL.md`, local `DEV_SKILLS` renders (`v0.7.0`), `AGENTS.md`/`CLAUDE.md`, completions, and skill/completion tests |

## Scorecard

| Row | Baseline (2026-11-25) | Target | Read from |
|---|---|---|---|
| Supported node flavors | 1 (`code` via 3-knob `contains_sub`) | **5** (`code`, `direct`, `research`, `explore`, `human-gate`) | `test_store.ml` + fixture test |
| Protected-file lock enforcement | grader prompt (`brief.ml:49`) | **100% deterministic** (`E_PROTECTED_FILE`) | `test_store.ml` + fixture test |
| Bounded experiment discipline (`Explore`) | ad-hoc prose, no cap or outcome | **structured** (`target`, `max_iterations`, `outcome`) | `bp3 q <q> n <n> r` + fixture test |

## Risks and red chair

- **Strongest attack (`Research` updating downstream `NODE.md` weakens Goodhart protection):** "If a `Research` node can edit downstream `NODE.md` files, could an agent weaken a downstream coding node's acceptance gates?"
  - **Settled in design:** `Research` may edit only downstream `NODE.md` files still in `todo` state (never its own `NODE.md`, never `handed_off`/`landed` nodes, never `GRADING.md`/`CONSTRAINTS.md`/`scripts/receipt`/`scripts/red-first`), every edited `NODE.md` appears in the `Research` node's `changes` diff, and pairing `Research -> Human_gate -> Code` lets the owner approve rewritten specs before code starts.
- **Second attack (`Explore` wall-clock or token limits creating false-positive blocks):** "Wall-clock budgets trip on laptop sleep/API stalls and live token caps require mid-session transcript scraping."
  - **Settled in design:** Dropped `--budget-min` completely (owner, 2026-11-26). Only deterministic `--max-iterations` is enforced (`e iterate` -> `E_EXPLORE_BOUND`), and `handoff --outcome ...` is always allowed so an agent can always commit its report. Warden does NOT police token spend on explorations — its role on `explore` nodes is future learning/quality validation (edge cases, lessons, report completeness).
- **Third attack (`Human_gate` vs `dag-fsm-v2` git ancestry):** "If a `Code` node depends on a `Human_gate` node (`commit = None`), does `dag-fsm-v2`'s `is_ancestor` check break?"
  - **Settled in design:** Per `dag-fsm-v2` `ancestry.1`, `is_ancestor` checks only landed deps with `commit = Some sha`, so `Human_gate` deps (`commit = None`) are skipped cleanly.

## Open questions

None — all owner calls settled on 2026-11-26:
1. **`Explore` updating downstream `todo` `NODE.md` / `QUEST.md` (settled 2026-11-26):** Allowed (same safe docs-only rule as `Research`), with quest/induct convention to place a `human-gate` node right after it.
2. **`Explore` bound & Warden scope (settled 2026-11-26):** `--max-iterations` only (no `--budget-min`, no live token cap). Warden does not count/penalize exploration tokens; future Warden middleware on explorations should focus on learning quality (catching missing edge cases / improving future explorations).

## Node diagram

```text
(after 2026-11-23-dag-fsm-v2)

kinds.1 (5 kinds + human-gate + E_PROTECTED_FILE) ──► research.1 (research + bounded explore) ──► skills.1 (skills + completions + tests)
```
