---
status: proposed
home_repo: bp3
date: 2026-11-23
bump: minor
---

# dag-fsm-v2: leaner node FSM (`todo -> handed_off -> landed`) and git-bound dependency ancestry

TL;DR
Tighten `bp3`'s core per-node FSM and dependency integrity without touching quest promotion (already owned by `2026-11-23-quest-promote-release`). First, collapse the unused standalone `verify` edge and the 1-second phantom `approved` state so a passing `grade --verdict ship` lands the node directly (`todo -> handed_off -> landed`), while keeping read-side backward compatibility in `Store.fold_ledger` for all pre-v2 ledgers and keeping `land: manual` optional in plans. Second, enforce real git commit ancestry on `handoff`: when a node depends on landed dependency nodes that carry commits, `bp3 q` verifies `git merge-base --is-ancestor <dep_commit> <commit>` and refuses stale/diverged commits with `E_MISSING_ANCESTOR`. Sequenced after `2026-11-23-quest-promote-release` and `2026-11-23-codebase-diet`, and before `2026-11-23-dag-contracts`.

ELI5
Right now every node pays three ceremonies to land (`handoff -> grade --verify-verdict pass -> land`) even though nobody runs `verify` separately anymore and `approved` only lasts one second before `land` runs right after. Worse, if Node B depends on Node A, `bp3` only checks that Node A's ledger says `landed` — it never checks whether Node B's git commit actually contains Node A's code! This quest trims the node state machine to `todo -> handed_off -> landed` and makes `handoff` check real git ancestry against landed dependencies.

## Context

Framed on 2026-11-23 during the post-`warden-v0` DAG engine review, split cleanly from `2026-11-23-dag-contracts` (node `owns` globs and typed node kinds) so contracts wire onto the lean FSM instead of the legacy 2-bit `grade_ok`/`verify_ok` handshake.

Sequencing:
- **After** `docs/quests/2026-11-23-quest-promote-release/` (which already owns quest exit / atomic CAS promotion via `bp3 release <quest>` — explicitly out of scope here).
- **After** `docs/quests/2026-11-23-codebase-diet/` (which cleans `src/quest/store.ml`, `src/quest/names.ml`, and `skills/induct*` so this quest avoids merge churn).
- **Before** `docs/quests/2026-11-23-dag-contracts/` (which layers `owns` globs and `code|direct|spike|gate` kinds onto this FSM).

Measured ground (read 2026-11-23 from `src/quest/store.ml`, `src/quest/main.ml`, `src/quest/gitx.ml`, `plans/default.yaml`):
- `Store.node_state` (`src/quest/store.ml:142-143`) carries two mutable bits (`grade_ok`, `verify_ok`), and `Main.do_update` (`src/quest/main.ml:251-304`) handles both `grade` and standalone `verify` edges plus `--verify-verdict pass|fail`, landing in an intermediate `approved` state (`src/quest/store.ml:399`) that immediately requires a separate `land` call (`src/quest/main.ml:305-352`).
- On `handoff`, `Main.do_update` (`src/quest/main.ml:235-243`) checks only `ds.st <> "landed" && ds.st <> "deleted"` and never calls `Gitx.is_ancestor` (`src/quest/gitx.ml:189`) against `ds.last_commit`.
- Historical ledgers in `docs/quests/` contain `verify` edges and `approved` states, so `Store.fold_ledger` must continue folding them losslessly.

## Terms

| Term | Meaning |
|---|---|
| `auto_land` | default node plan behavior (`land: auto` in `plans/*.yaml`, default when omitted): `grade --verdict ship` atomically transitions `handed_off -> landed` and advances the quest ref in one write; `land: manual` preserves the explicit `approved -> land` step |
| `E_MISSING_ANCESTOR` | typed refusal emitted by `handoff` when a landed dependency node carries a commit `dep_sha` that is not a git ancestor of the handed-off `--commit` (`not (Gitx.is_ancestor dep_sha commit)`) |
| `E_EDGE_RETIRED` | typed refusal (or `E_USAGE` — settled in Open question 1) when a caller invokes the retired standalone `verify` edge on a new quest while historical ledgers still fold cleanly |
| `landed` | terminal node state (`fin: "node_fin"`), reached directly from `grade --verdict ship` under `land: auto` or from `land` under `land: manual` |

## Inputs

| Input | Source | Precedence / Notes |
|---|---|---|
| `plans/*.yaml` (`land: auto \| manual`) | repo plan YAML, parsed by `Store.plan_knobs_from_text` | defaults to `auto` when omitted; `manual` preserves explicit `approved -> land` |
| `bp3 q <q> n <n> e handoff --commit <sha> --reason <why>` | CLI edge call | checks clean tree, dep states, and `Gitx.is_ancestor dep.commit sha` for every landed dep with a commit |
| `bp3 q <q> n <n> e grade --verdict ship\|needs_fix [--mechanical] --reason <why>` | CLI edge call | `--verify-verdict` is hard-retired (`E_USAGE`, exit `2`); all callers across `bp3` and `~/m/predictor` swept |
| historical `ledger.jsonl` | existing `refs/heads/bp3/...` refs | read-only backward compat in `Store.fold_ledger` (`verify` edges and `approved` states stay readable) |

## Outputs

| Output | Shape |
|---|---|
| lean happy-path FSM | `todo -> handed_off -> landed` (2 edges instead of 3 on default plans), with `grade --verdict ship` returning `{"ok": true, "state": "landed", "fin": "node_fin", ...}` |
| `E_MISSING_ANCESTOR` verdict | `{"ok": false, "error": {"code": "E_MISSING_ANCESTOR", "facts": {"missing": [{"node": "...", "commit": "..."}], "commit": "..."}, "guidance": "..."}}`, exit `1` |
| backward-compatible ledger fold | every historical quest in `docs/quests/` and `test/unit/test_store.ml` still folds identically |
| updated skills, completions, tests | conducting skills drop the redundant `land` + `--verify-verdict pass` ceremony |

## Acceptance gates

Observed today (2026-11-23):

```text
$ rg -n "verify_ok|grade_ok|approved" src/quest/store.ml src/quest/main.ml | wc -l
      29
$ rg -n "is_ancestor" src/quest/main.ml
323:      if is_ancestor qtip node_tip then begin
# (zero is_ancestor calls inside the handoff branch at main.ml:223-250!)
```

Design trace (after quest lands):

```text
fsm.1      bp3 q demo c n1 && bp3 q demo n n1 e handoff --commit $C1 --reason "ready"
             -> state: "handed_off", legal_edges: ["grade", "block", "delete"]
           bp3 q demo n n1 e grade --verdict ship --reason "clean"
             -> state: "landed", fin: "node_fin", legal_edges: []   (quest ref advanced atomically)
           plan with `land: manual` -> grade returns state: "approved", then `land` -> "landed"
           historical ledger containing `verify` + `approved` -> Store.fold_ledger reads identically
ancestry.1 bp3 q demo c n2 --depends-on n1
           on branch NOT containing $C1:
             bp3 q demo n n2 e handoff --commit $C_DIVERGED --reason "try"
             -> exit 1, E_MISSING_ANCESTOR naming n1 and $C1
           after rebasing/merging $C1 onto branch ($C2 descends from $C1):
             bp3 q demo n n2 e handoff --commit $C2 --reason "rebased"
             -> ok: true, state: "handed_off"
skills.1   skills/ + rendered .{agents,claude,pi}/skills/ + AGENTS.md/CLAUDE.md match new FSM;
           make check-full rc 0
```

## Goal and why

Keep `bp3`'s DAG engine sharp and trustworthy as `/swarm` parallel branches become routine. Removing the dead `verify` / `approved` hop simplifies every node lifecycle and cuts redundant CLI/CAS writes; adding real git ancestry checks on `handoff` closes a real correctness hole where a parallel child branch could land without integrating its landed parent node's commits.

## Success picture

- Default node lifecycle is 2 happy-path edges (`handoff -> grade`), not 3 (`handoff -> grade --verify-verdict -> land`), while `land: manual` plans and historical ledgers stay 100% supported.
- No `Code` node with a landed dependency can `handoff` a commit missing that dependency's landed commit (`E_MISSING_ANCESTOR`).
- `make check-full` passes with new unit + fixture tests covering auto-land, `land: manual`, legacy ledger folds, and `E_MISSING_ANCESTOR` rejection/recovery.

## Scope

| In | Out |
|---|---|
| Auto-land on `grade --verdict ship` under default `land: auto` plan + optional `land: manual` (`fsm.1`) | Quest exit / promotion / tagging (`2026-11-23-quest-promote-release`, already active) |
| Deprecating standalone `verify` edge while preserving `Store.fold_ledger` read-side compat (`fsm.1`) | Node `owns` file globs & parallel-safe batch calculation (`2026-11-23-dag-contracts`) |
| `Gitx.is_ancestor` check on `handoff` against all landed deps carrying a commit (`ancestry.1`) | Typed node kinds `code\|direct\|spike\|gate` (`2026-11-23-dag-contracts`) |
| Updating skills, renders, completions, `AGENTS.md`/`CLAUDE.md` (`skills.1`) | Replacing per-node git refs with a single quest state ref (Open question 2 — defer unless settled in `/red-ink`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** Zero new languages, libraries, or CLI surfaces. All code lives in existing OCaml `bp3_quest` (`stdlib`, `unix`, `str`, `yojson`, `ounit2`, `qcheck`) behind `bp3 q`.
- **Common-sense pass (`CONTEXT.md`):**
  - *Small steps (`CONTEXT.md:76`)* and *Gall's law (`CONTEXT.md:80`)*: trim vestigial FSM states (`verify`, `approved`) before adding new node kinds in `dag-contracts`.
  - *Deterministic checks beat model judgment (`CONTEXT.md:96`)*: git ancestry on `depends_on` is a 10ms `git merge-base --is-ancestor` check, eliminating an entire class of parallel-branch integration bugs without burning grader tokens.

## Human touchpoints

| When | Owner |
|---|---|
| Settle Open questions 1–2 during `/red-ink` and approve frame | owner |
| Promote via `bp3 release` / `/warden` at `goal_fin` | owner |

## Nodes

### Milestone: fsm

| Node | TL;DR |
|---|---|
| [fsm.1 - collapse-verify-and-auto-land](nodes/node-fsm-1-collapse-verify-and-auto-land/NODE.md) | add `land: auto\|manual` (default `auto`), auto-land on `grade --verdict ship`, retire standalone `verify` write path while keeping legacy ledger folds intact |

### Milestone: ancestry

| Node | TL;DR |
|---|---|
| [ancestry.1 - enforce-dep-commit-ancestry](nodes/node-ancestry-1-enforce-dep-commit-ancestry/NODE.md) | check `Gitx.is_ancestor dep.commit commit` on `handoff` for every landed dependency carrying a commit; refuse with `E_MISSING_ANCESTOR` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - update-skills-and-docs](nodes/node-skills-1-update-skills-and-docs/NODE.md) | update conducting skills, renders, completions, `AGENTS.md`/`CLAUDE.md`, and skill/completion tests for the 2-edge happy path and `E_MISSING_ANCESTOR` |

## Scorecard

| Row | Baseline (2026-11-23) | Target | Read from |
|---|---|---|---|
| Happy-path node edges (`default` plan) | 3 (`handoff`, `grade`, `land`) | **2** (`handoff`, `grade`) | `bp3 q <q> n <n> r` |
| Unchecked dep ancestry on `handoff` | 0 checks (diverged commit accepted) | **100%** checked (`E_MISSING_ANCESTOR`) | `test/unit/test_store.ml` + fixture test |
| Legacy ledger fold compat | green | **100%** preserved | `make check-full` |

## Risks and red chair

- **Strongest attack (breaking existing scripts/skills/tests that call `grade --verify-verdict pass` then `land`):** "Existing fixture tests and downstream repos still call `verify` or `grade ...` followed by `land`. Hard-breaking `land` or `--verify-verdict` overnight breaks backward compatibility."
  - **Settled in design:** `plans/default.yaml` switches to `land: auto` (explicit `land` on an already-landed node fails cleanly with `E_ILLEGAL_EDGE`), `plans/*.yaml` supports `land: manual` for callers that need a separate `approved -> land` step, `--verify-verdict` stays accepted as an optional deprecated flag on `grade` (never required), and `Store.fold_ledger` continues folding every historical `verify` and `approved` line losslessly.
- **Second attack (git ancestry check false-positive when a dependency was squashed/rebased or had no code commit):** "If a dep node was `deleted` or had `commit = None` (e.g., future `Spike`/`Gate` node), requiring `is_ancestor` would wrongly block downstream nodes."
  - **Settled in design:** `ancestry.1` checks ancestry ONLY for dependencies with `ds.st = "landed"` AND `ds.last_commit = Some dep_sha`. Deleted deps and commit-less deps (`None`) are skipped cleanly, so future `Spike`/`Gate` nodes in `dag-contracts` work out of the box.
- **Attack on source (splitting B from `quest-promote-release` and `dag-contracts`):** "Is B worth its own quest if quest exit is already in `quest-promote-release`?"
  - **Settled:** Yes — `fsm.1` + `ancestry.1` + `skills.1` is a crisp, 3-node foundational quest (~1 day) that directly protects `/swarm` parallel branches and keeps `dag-contracts` focused strictly on contracts (`owns` + node kinds).

## Open questions

_(None currently open; remaining slices to walk in red-ink: Inputs, Internals, Plan.)_

## Settled in red-ink

- **Round 1 (Shape — owner call: Option 1):** Lock the 2-edge happy path (`todo -> handed_off -> landed` under default `land: auto`) + `E_MISSING_ANCESTOR` on `handoff`, keeping per-node git refs (`refs/heads/bp3/nodes/...`) for zero storage migration. On a state-ref `merge-tree` conflict during auto-land, preserve the `ship` verdict by stopping in `state: "approved"` with `facts.land_conflict: true` and `legal_edges: ["land", "block", "delete"]` (retryable via `land`) instead of throwing away the verdict back to `todo`. (Resolves former Open questions 2 & 3.)
- **Round 2 (Output — owner call: Option 1):** Calling the retired standalone `verify` edge returns `E_EDGE_RETIRED` (exit `2`, usage-class) with `facts: {"edge": "verify", "replacement": "grade"}` and guidance pointing to `grade`. (Resolves former Open question 1.)
- **Round 3 (Inputs — owner call: Option 2 + sweep):** Hard-retire `--verify-verdict` (`E_USAGE`, exit `2`) and delete it from `cli.ml` / `main.ml`; sweep all callers across `bp3` and `~/m/predictor` (only external consumer). Legacy `verify:` lines in existing `plans/*.yaml` remain tolerated (ignored), and `Store.fold_ledger` keeps lossless read-side compatibility for historical `verify`/`approved`/`verify_verdict` ledger lines.

## Node diagram

```text
(after 2026-11-23-quest-promote-release + 2026-11-23-codebase-diet)

fsm.1 (collapse verify + auto-land) ──► ancestry.1 (dep commit ancestry on handoff) ──► skills.1 (skills + docs + tests)
```
