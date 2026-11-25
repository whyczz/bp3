---
status: frozen
date: 2026-11-22
promoted: null
---

# Names as constants: one file in the binary holds every spelling

## Context

Frozen 2026-11-22, in red-ink round 6 (names) of
`docs/quests/2026-11-22-induct-inline-as-default-measure-author/`.
Owner, verbatim: "btw let's make the verbs, ideas configurable in case
we want to rename", then "uhh constants in the BP3 binary, the skills
stay where they are, if we need to rename, we can rename the skills
(e.g. sed) and change the contants file?"

Renames have happened three times so far, each patched by hand:

- `graph -> quest`: `scripts/migrate-graph-rename.sh` (117 lines) and
  the retired-term sweep `scripts/check-retired-terms.sh`.
- `submit -> handoff`, `review -> grade`, `check -> verify`,
  `submitted -> handed_off`: read-side folds `Store.fold_edge` and
  `fold_state_name` (`src/quest/store.ml:172`).
- Spellings are scattered as string literals: `src/quest/main.ml` alone
  is 825 lines, and 32 distinct `E_*` codes appear across `src/quest/`.

The quest above starts `src/quest/names.ml` with only its own new
spellings (the `brief` verb, its refusal code). This entry is
everything else.

## Sketch

```text
src/quest/names.ml     every CLI door, verb, edge, state, flag and error code, one constant each
main.ml, store.ml, …   dispatch and verdicts use Names.*, never a literal
skills/, docs          plain words, untouched (no templates)
rename                 edit one constant + sed the skills/renders + add the old spelling to the read fold
                       (ledger edges, states, metric names and error codes are stored; old ledgers still read)
```

- Not added: runtime aliases, templates in skills, a names table file
  read at runtime.
- Metric names already have one home (`Metrics.registry`), and tally
  keys have `tally_json`. They stay there; `Names` points to them
  rather than copying.

## Blockers

- `Store.reserved_slugs` must be derived from `Names`, so a new verb is
  reserved automatically.
- A test must fail on a new literal verb or code outside `names.ml`.
  How strict it is (every string, or only dispatch and `err` sites) is
  undecided.
- A rename of a stored spelling still needs its fold row. Whether that
  fold lives in `Names` too (current plus retired spellings) is
  undecided.

## Promotion trigger

The next rename of any verb, edge, state or error code, or the owner
naming this entry.

---

---
status: frozen
date: 2026-11-23
promoted: docs/quests/2026-11-23-codebase-diet/QUEST.md
---

# Rename `induct-inline` to `induct` and delete legacy conductor infra

## Context

Frozen on 2026-11-23 after the `2026-11-23-harness-advice.md` / `get-good-harness-engineering.md` research review and the landings of `2026-11-23-fast-agy-induct` and `2026-11-23-warden-v0`.

Today `bp3` ships four overlapping conducting skills (`induct`, `induct-yolo`, `induct-inline`, `induct-inline-yolo`) plus ~4,800 LOC of legacy middle-manager conductor infrastructure (`skills/induct/workflows/*.js`, `.agents/workflows/`, `extensions/bp3-pi/`, and the `supervisor` / `init-check` / `find-tape` / `watch` / `record-init` / `bind-tape` / `backtest` / `link` subsystems of `src/quest/harness.ml`). Across the last four real quests (`metric-followups`, `pi-metrics`, `induct-inline-as-default-measure-author`, `fast-agy-induct`, `warden-v0`), the legacy conductor had zero runs. Meanwhile `induct-inline` (one main session + cold background grader + optional native `/swarm` on disjoint ready nodes) and `induct-inline-yolo` cover linear quests, parallel-able DAGs, and unattended runs without a middle-manager layer.

Owner direction on 2026-11-23: rename `induct-inline` to `induct` (and `induct-inline-yolo` to `induct-yolo`), and remove the old `induct` conductor and any infrastructure that exists only to support it.

Related proposed quest already on disk: `docs/quests/2026-11-23-codebase-diet/QUEST.md` (which already frames deleting `skills/induct/workflows/`, `extensions/bp3-pi/`, and dead `harness.ml` subsystems, and lists the `induct-inline` -> `induct` rename as Open question 2).

## Sketch

- **Skill consolidation & rename:**
  - Promote `skills/induct-inline/SKILL.md` -> `skills/induct/SKILL.md` and `skills/induct-inline-yolo/SKILL.md` -> `skills/induct-yolo/SKILL.md`.
  - Delete the old conductor `skills/induct/SKILL.md`, `skills/induct-yolo/SKILL.md`, `skills/induct-inline/`, `skills/induct-inline-yolo/`, and `skills/induct/workflows/*.js`.
  - Re-render all harness skill directories (`.agents/skills/`, `.claude/skills/`, `.pi/skills/`) and prune stale `induct-inline*` and `.agents/workflows/` renders.
  - Update `bin/bp3` skill install arrays, `AGENTS.md` / `CLAUDE.md`, `skills/quest/SKILL.md`, `skills/warden/SKILL.md`, and `scripts/check-retired-terms.sh`.
- **Delete conductor-only infrastructure:**
  - Delete `extensions/bp3-pi/` and all obsolete workflow/supervisor/tape/watch/backtest/link fixture suites from `test/` and `test/suites.tsv`.
  - Slim `src/quest/harness.ml` down to `bp3 harness desk` only (retiring `supervisor`, `init-check`, `find-tape`, `watch`, `record-init`, `bind-tape`, `backtest`, and `link` cleanly behind `E_USAGE` or removal).
  - Place an annotated archive tag (e.g. `archive/pre-codebase-diet`) before deleting so Chesterton's fence history stays recoverable.
- **Deliberately not added:**
  - No `firstmate`-style tmux/daemon fleet manager or cross-harness middle manager.
  - No changes to `bp3 q` FSM rules, `bp3 harness desk`, `metrics`, `warden`, or read-side `Layout.legacy_*` ledger folds (historical quests stay readable).

## Blockers

- **Overlap with `docs/quests/2026-11-23-codebase-diet/QUEST.md`:** `codebase-diet` already covers `retire.1` (Muse workflows + `bp3-pi`), `retire.2` (`harness.ml` slim-down), and `skills.1` (consolidating `induct*` skills). Decide at thaw whether to fold this entry into `codebase-diet` (settling its Open questions 1–2) or run it as a standalone quest.
- **Sequencing with `2026-11-22-bp3-is-static-across-downstream-repo-worktrees`:** That quest touches `bin/bp3`, `Makefile`, and install/release versioning; landing it first avoids merge conflicts and gives a declared version bump for retiring CLI surfaces.
- **`CONSTRAINTS.md` removal sign-off:** Removing `extensions/bp3-pi`, workflow scripts, and `@earendil-works/pi-coding-agent` (and optionally `node` if `test/pi-discovery.mjs` retires) requires an explicit dated owner-words row in `CONSTRAINTS.md`'s Sign-off log (`CONSTRAINTS.md:77`).
- **Hidden callers to settle before deleting `harness.ml`:**
  - `src/quest/claude_tx.ml` calls `Harness.epoch_of_iso` — move that helper to `Tx` or `Util` first.
  - Decide whether `bp3 n` and `bp3 e` (claimed context doors that depend on `harness link`) retire alongside `link` (`codebase-diet` Open question 1).
- **Downstream skill callers:** Any muscle memory, docs, or host-repo prompts referencing `/induct-inline` or `/induct-inline-yolo` must switch to `/induct` and `/induct-yolo` (plus updating `test/skills.sh`, `test/mode.sh`, and `completions/`).

## Promotion trigger

Thaw either when starting `/red-ink` on `docs/quests/2026-11-23-codebase-diet/QUEST.md` (folding this directly into its settled scope), or immediately after `2026-11-22-bp3-is-static-across-downstream-repo-worktrees` lands if you want to cut the old `induct` conductor and rename `induct-inline` -> `induct` first as its own focused quest.
