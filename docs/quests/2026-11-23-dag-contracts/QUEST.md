---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# dag-contracts: first-class node `owns` globs (parallel-safe `/swarm`) and typed node kinds (`code | direct | spike | gate`)

TL;DR
Upgrade `bp3`'s DAG from prose conventions to machine-checked contracts on top of `2026-11-23-dag-fsm-v2`. First, add first-class `--owns <glob,glob>` file boundaries to nodes so `bp3 q r <quest>` deterministically computes **`parallel_batches`** (ready nodes with provably disjoint `owns` sets, safe for `/swarm`) and `handoff` mechanically enforces scope + protected-file locks (`E_SCOPE_VIOLATION`, `E_PROTECTED_FILE` for undeclared edits to `GRADING.md`, `CONSTRAINTS.md`, or Acceptance gates). Second, replace `Store.plan_knobs_from_text`'s 3-knob substring parser with four explicit **node kinds** (`code | direct | spike | gate`), so throwaway spikes never land code and human sign-off gates sit cleanly in the DAG instead of abusing `block`/`resume`.

ELI5
Right now, deciding whether two ready tasks are safe to run in parallel (`/swarm`) relies on an AI reading prose in `NODE.md`, and stopping an AI from editing `GRADING.md` or `CONSTRAINTS.md` relies on asking the grader politely in a prompt. And every task in a quest — even a 5-minute spike or a human approval checkpoint — is forced through the exact same heavy code-commit pipeline. This quest puts file ownership (`--owns`) and node kinds (`code`, `direct`, `spike`, `gate`) straight into the DAG engine so parallel safety, anti-cheating locks, spikes, and human gates are enforced by OCaml code, not prose.

## Context

Framed on 2026-11-23 during the post-`warden-v0` DAG engine review, cleanly separated from `2026-11-23-dag-fsm-v2` (lean 2-edge FSM + git ancestry).

Sequencing:
- **After** `docs/quests/2026-11-23-dag-fsm-v2/` (so `code | direct | spike | gate` and `owns` enforcement wire straight into the lean `todo -> handed_off -> landed` FSM with git ancestry already enforced).
- Directly closes two findings that survived the 2026-11-23 `/red-chair` of `docs/dossiers/2026-11-23-harness-advice.md`:
  1. **Goodhart / test-locking in code, not prose (`CONTEXT.md:100`):** `brief.ml:48` asks the grader to flag edits to `GRADING.md`, `CONSTRAINTS.md`, or Acceptance gates, whereas `handoff` can enforce it deterministically in milliseconds.
  2. **Parallel-writer safety (`get-good-harness-engineering.md:209`):** Zechner, Ronacher, and Cognition all warn that parallel writers break when file/design boundaries overlap; `owns` makes disjointness machine-checkable in `bp3 q r`.

Measured ground (read 2026-11-23 from `src/quest/store.ml`, `src/quest/render.ml`, `src/quest/brief.ml`):
- `Store.sched_waves` (`src/quest/store.ml:534-546`) computes ready waves purely from `depends_on`; `Render.quest_view` (`src/quest/render.ml:110-119`) emits `ready` and `ready_set_waves` with zero file-overlap metadata.
- `Store.plan_knobs_from_text` (`src/quest/store.ml:95-122`) parses YAML via `contains_sub` for only 3 booleans (`max_cycles`, `grade_required`, `verify_required`); there is no `Spike` or `Gate` node lifecycle.
- `Render.commit_changes` (`src/quest/render.ml:9-24`) already extracts the exact changed file list of any commit via `git diff-tree --no-commit-id --name-status -r <sha>`.

## Terms

| Term | Meaning |
|---|---|
| `owns` | optional list of repo-relative path/glob patterns attached to a node (`--owns <g1,g2>` at `create`, editable via `bp3 q <q> owns <n> --owns ... --reason ...`, logged in `ledger.jsonl`) |
| `parallel_batches` | derived field on `bp3 q r <quest>` JSON partitioning `ready` nodes into subsets whose `owns` patterns are provably disjoint (nodes with empty `owns` are treated as wildcard `*` and never parallelized automatically) |
| `protected_files` | built-in list of check/governance files (`GRADING.md`, `CONSTRAINTS.md`, and the node's own `NODE.md`) that `handoff` refuses to modify unless explicitly matched by the node's `owns` (`E_PROTECTED_FILE`) |
| `E_SCOPE_VIOLATION` | typed refusal on `handoff` when a node declares non-empty `owns` and the commit touches a path matching none of them |
| `E_PROTECTED_FILE` | typed refusal on `handoff` when a commit touches a protected file not explicitly declared in `owns` |
| `node_kind` | typed OCaml variant `Code \| Direct \| Spike \| Gate` declared via `--kind` at node creation (default `Code`), stored in the node create ledger line |

## Inputs

| Input | Source | Precedence / Notes |
|---|---|---|
| `--owns <glob,glob>` | `bp3 q <q> c <n>` / `bp3 q <q> owns <n>` | repo-relative globs (`*`, `**`, exact paths); empty = unrestricted (serialized, never auto-swarmed) |
| `--kind code\|direct\|spike\|gate` | `bp3 q <q> c <n>` | defaults to `code`; replaces ad-hoc `plans/node-*.yaml` hacks for common node shapes |
| `--artifact <path>` | `handoff` / `complete` on a `Spike` node | names the committed doc/report produced by a spike; spike refuses diffs to code paths outside `docs/` |
| `BP3_DECIDER=human` | env var on `Gate` node completion | required (`E_HUMAN_REQUIRED`) to pass a `Gate` node (`approve` / `complete` edge) |

## Outputs

| Output | Shape |
|---|---|
| `parallel_batches` in `bp3 q r <quest>` | `[["node-a", "node-b"], ["node-c"]]` — deterministic greedy/graph-colored disjoint subsets of `ready` |
| `owns` + `kind` on `bp3 q <q> n <n> r` | `"kind": "code", "owns": ["src/warden/**"]` in node JSON and `diagram` output |
| `E_SCOPE_VIOLATION` / `E_PROTECTED_FILE` | typed refusals on `handoff` naming offending paths and declared `owns` |
| 4 clean node lifecycles | `Code` (handoff + cold grade), `Direct` (handoff -> landed, no AI grade), `Spike` (artifact-only, never lands code), `Gate` (human-only sign-off node) |

## Acceptance gates

Observed today (2026-11-23):

```text
$ ./bin/bp3 q 2026-11-23-warden-v0 r | jq 'has("parallel_batches")'
false
$ rg -n "contains_sub text" src/quest/store.ml
112:    if contains_sub text "required: false" && contains_sub text "grade:" then false
# (3-knob substring parser; zero --owns, zero --kind code|direct|spike|gate)
```

Design trace (after quest lands):

```text
owns.1   bp3 q demo c a --owns "src/a/**" && bp3 q demo c b --owns "src/b/**" && bp3 q demo c c --owns "src/a/foo.ml"
         bp3 q r demo -> ready: ["a","b","c"], parallel_batches: [["a","b"], ["c"]]
         handoff a with commit editing GRADING.md -> exit 1, E_PROTECTED_FILE
         handoff a with commit editing src/b/x.ml -> exit 1, E_SCOPE_VIOLATION
         handoff a with commit editing src/a/x.ml -> ok: true

kinds.1  bp3 q demo c sp1 --kind spike
           handoff sp1 with commit touching src/quest/main.ml -> exit 1, E_SPIKE_CODE_TOUCHED
           handoff sp1 with commit touching docs/dossiers/sp1.md -> ok: true, state: "landed" (no code landed)
         bp3 q demo c g1 --kind gate --depends-on sp1
           approve g1 without BP3_DECIDER=human -> exit 1, E_HUMAN_REQUIRED
           BP3_DECIDER=human bp3 q demo n g1 e approve --reason "go with option B" -> state: "landed"
         bp3 q demo c d1 --kind direct --depends-on g1
           handoff d1 --commit $C_DOC -> state: "landed" directly (no AI grade spawned)

skills.1 quest + induct* + using-bp3 skills instruct using `parallel_batches` for /swarm and `--owns`/`--kind`;
         make check-full rc 0
```

## Goal and why

Turn `bp3`'s two most important safety rules — *"only parallelize disjoint nodes"* and *"don't touch checks/files outside your node"* — from LLM prompt reminders into deterministic OCaml checks, and let quests express real engineering workflows (throwaway spikes, human checkpoints, fast direct nodes, graded code nodes) natively in the DAG.

## Success picture

- `/swarm` no longer guesses whether two ready nodes collide: it reads `parallel_batches` directly from `bp3 q r <quest>`.
- A node commit cannot silently modify `GRADING.md`, `CONSTRAINTS.md`, its own `NODE.md` Acceptance gates, or another node's owned files without failing `handoff` deterministically.
- Spikes and human gates are first-class DAG nodes — zero more fake `block`/`resume` cycles just to pause for an owner call.

## Scope

| In | Out |
|---|---|
| Pure glob matcher + `--owns` storage + `parallel_batches` + `E_SCOPE_VIOLATION`/`E_PROTECTED_FILE` (`owns.1`) | Lean 2-edge FSM & dep git ancestry (`2026-11-23-dag-fsm-v2`, prerequisite) |
| Typed `node_kind` (`Code \| Direct \| Spike \| Gate`) + clean plan parsing (`kinds.1`) | Quest exit / promotion (`2026-11-23-quest-promote-release`, already active) |
| Skills, renders, completions, `AGENTS.md`/`CLAUDE.md` (`skills.1`) | External YAML library (stays pure OCaml stdlib/str/yojson per `CONSTRAINTS.md`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** Zero new languages, libraries, or CLI surfaces. Glob matching, overlap detection, and node kinds are pure OCaml (`stdlib`/`str`/`yojson`) inside `src/quest/`.
- **Common-sense pass (`CONTEXT.md`):**
  - *Goodhart's law (`CONTEXT.md:81`, `CONTEXT.md:100`)*: "if a change can modify the check that judges it, the check is broken" — enforced mechanically at `handoff` via `E_PROTECTED_FILE`.
  - *Plan to throw one away (`CONTEXT.md:74`)*: "spike nodes that never land" — finally real in the engine (`--kind spike`).
  - *Brooks's law / parallel writers (`CONTEXT.md:72`, `get-good-harness-engineering.md:209`)*: parallel writes allowed only when `owns` globs are provably disjoint.

## Human touchpoints

| When | Owner |
|---|---|
| Settle Open questions 1–3 during `/red-ink` and approve frame | owner |
| Promote via `bp3 release` / `/warden` at `goal_fin` | owner |

## Nodes

### Milestone: owns

| Node | TL;DR |
|---|---|
| [owns.1 - node-owns-globs-and-parallel-batches](nodes/node-owns-1-node-owns-globs-and-parallel-batches/NODE.md) | pure glob + disjointness module (`src/quest/owns.ml`), `--owns` CLI/ledger field, `parallel_batches` in `bp3 q r`, and `E_SCOPE_VIOLATION`/`E_PROTECTED_FILE` on `handoff` |

### Milestone: kinds

| Node | TL;DR |
|---|---|
| [kinds.1 - typed-node-kinds](nodes/node-kinds-1-typed-node-kinds/NODE.md) | typed `Code \| Direct \| Spike \| Gate` node kinds (`--kind`), clean plan knob parsing, spike artifact-only check, and human-gated `Gate` approval edge |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - contracts-skills-and-completions](nodes/node-skills-1-contracts-skills-and-completions/NODE.md) | update `quest`, `induct*`, `using-bp3`, renders, `AGENTS.md`/`CLAUDE.md`, completions, and skill/completion tests |

## Scorecard

| Row | Baseline (2026-11-23) | Target | Read from |
|---|---|---|---|
| Parallel-safety check for `/swarm` | LLM prose (`Output` / `Must not touch`) | **100% deterministic** (`parallel_batches`) | `bp3 q r <quest>` |
| Protected-file lock enforcement | grader prompt (`brief.ml:48`) | **100% deterministic** (`E_PROTECTED_FILE`) | `test_owns.ml` + fixture test |
| Supported node kinds | 1 (`code` via 3-knob YAML) | **4** (`code`, `direct`, `spike`, `gate`) | `test_store.ml` + fixture test |

## Risks and red chair

- **Strongest attack (glob overlap undecidability / false-disjoint parallel runs):** "Two complex globs like `src/**/foo*` and `src/quest/*bar.ml` can overlap in subtle ways; a naive intersection check could falsely mark them disjoint and cause a `/swarm` merge collision."
  - **Settled in design:** `Owns.disjoint` uses a **conservative (sound)** overlap check: exact paths vs prefixes vs wildcards — whenever overlap is uncertain (e.g., two wildcards under overlapping directory prefixes, or empty `owns`), it conservatively returns `false` (serialize!). False serialization is safe; false parallelism is impossible. Property-tested with QCheck2 (`if exists path matching both a and b, disjoint a b = false`).
- **Second attack (over-strict `owns` causing churn on `LOG.md` or `dune` files):** "Every commit in a quest might legitimately update `docs/quests/<q>/LOG.md` or a shared test registration like `test/suites.tsv`."
  - **Settled in design:** `docs/quests/<q>/LOG.md` is automatically allowed on every node of `<q>` (never triggers `E_SCOPE_VIOLATION`), and shared files like `test/suites.tsv` MUST be listed in `owns` if edited — which automatically tells `parallel_batches` to serialize two nodes that both touch `test/suites.tsv`!
- **Attack on source (`Spike` nodes vs git ancestry from `dag-fsm-v2`):** "If a `Spike` node lands a doc commit (or no commit) and a `Code` node depends on it, does `ancestry.1` break?"
  - **Settled in design:** `Spike` nodes store `commit = None` (or a doc-only commit on the quest branch); `Gate` nodes store `commit = None`. Per `dag-fsm-v2`'s `ancestry.1`, `is_ancestor` is checked only for landed deps with `commit = Some sha`, so `Gate` and commit-less `Spike` deps never falsely trigger `E_MISSING_ANCESTOR`.

## Open questions

1. Should `owns` globs be mandatory for nodes in a `/swarm`-eligible wave and optional (`[]` = serialized) otherwise, or always optional? — **owner** (recommended: always optional; empty `owns` simply means "never auto-parallelize with another node").
2. Should `protected_files` default to `["GRADING.md"; "CONSTRAINTS.md"; "<node>/NODE.md"]`, or also include `scripts/receipt` and `scripts/red-first`? — **owner** (recommended: include `scripts/receipt` and `scripts/red-first` too!).
3. For a `Spike` node, should completion take `--artifact <path>` (an existing file in `docs/` without requiring a code commit) or a doc-only `--commit <sha>`? — **owner** (recommended: doc-only `--commit <sha>` restricted to `docs/**`, keeping the "only clean commits move" invariant from `AGENTS.md`).

## Node diagram

```text
(after 2026-11-23-dag-fsm-v2)

owns.1 (globs + parallel_batches + protected locks) ──► kinds.1 (code|direct|spike|gate) ──► skills.1 (skills + completions + tests)
```
