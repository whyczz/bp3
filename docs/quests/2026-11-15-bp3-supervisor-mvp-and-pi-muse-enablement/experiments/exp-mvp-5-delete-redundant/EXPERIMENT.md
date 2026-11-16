---
date: 2026-11-15
quest: ../QUEST.md
exp: mvp.5
status: proposed
---

# mvp.5 - delete-redundant: remove superseded witness plumbing

## TL;DR

After mvp.4 replaces the witness mechanism, delete
the machinery it made redundant — in evidence order,
not enthusiasm order. The headline target is the
session-keyed shared map (`.git/bp3-run-registry.json`,
and its renamed sibling `.git/bp3-run-events.json`):
one writer rewriting one whole file for every Run.
Also on the block: the child-typed prefix ritual,
registry-shaped consumers in grades and tests, and
— only if tape parity is proven — the hook
telemetry that the supervisor fold replaces.

Nothing is deleted because it looks old. Every item
needs an inventory row: owner, live callers,
replacement, proof, and disposition.

## Demo (design trace)

```text
inventory -> candidate: save_registry (callers: hooks finish)
shadow fold: 110 stored bindings -> 110 per-Run logs, 0 critical diffs
cutover: new hook event writes <run_id>.jsonl only; shared map hash unchanged
verify: grep -R "bp3-run-registry" src test skills -> no live references
dispose: snapshot hash recorded; local shared map removed
```

## Diagram

```text
candidate machinery
      |
inventory (owner, callers, replacement, evidence)
      |
      +-- no replacement --------> keep; record why
      |
shadow parity (old read vs new fold; diffs named)
      |
write cutover -> read cutover -> negative grep/tests
      |
snapshot hash -> delete code -> dispose local data
```

## Pseudocode

```python
for item in inventory:
    assert item.owner and item.replacement
    diffs = shadow_compare(item.old_path, item.new_path)
    if critical(diffs):
        keep(item, reason=diffs); continue
    cutover_writes(item); cutover_reads(item)
    assert absent(item.spelling, live_surfaces)
    snapshot_hash(item.data); delete(item)
```

| Field | Value |
|---|---|
| Intent | shrink the witness surface to one mechanism after replacement is proven |
| Lane | high-blast-radius |
| Output | deletion manifest, migrated consumers, removed code/data paths, negative tests |
| Depends on | mvp.2, mvp.3, mvp.4 (mvp.4b run-lifecycle-derivations migration) |
| Consumer gate | backtest.1 evidence is required before Stage B hook retirement |

## Red-chair inspection (2026-11-15)

| Finding | Evidence | Consequence |
|---|---|---|
| The shared map is still a live consumer path, not dead code | `load_registry`/`save_registry` run around hook handling in [hooks.ml](/Users/whycz/m/bp3/src/quest/hooks.ml:242); the grade workflow instructs its auditor to quote `.git/bp3-run-registry.json` in [induct-grade.js](/Users/whycz/m/bp3/skills/induct/workflows/induct-grade.js:298); [induct-grade.test.mjs](/Users/whycz/m/bp3/test/induct-grade.test.mjs:185) pins that spelling | deleting the file or code first creates unwitnessed Runs and red tests; cut readers and writers over in one verified pass |
| The map is local evidence, not tracked truth | `.git/bp3-run-registry.json` is not a git path; the ledger remains the state truth | code deletion and local-data disposal are separate steps; snapshot/convert before removing either local map |
| Three telemetry stores overlap | tapes, the shared binding map, and hook event rows appended to each exp ledger by `append_event`/`emit` in [hooks.ml](/Users/whycz/m/bp3/src/quest/hooks.ml:183) | deleting only the map leaves duplicate lifecycle writers; the sole persisted supervisor output is `run-lifecycle-derivations`, and raw facts stay in harness tapes |
| The registry struct carries behavior, not just bytes | it aggregates usage, tracks `emitted` dedupe, and holds settled/unsettled flags used by settle and sweep branches in [hooks.ml](/Users/whycz/m/bp3/src/quest/hooks.ml:300) | remove the struct only after the fold owns usage, dedupe, and lifecycle derivation |
| Pi duplicates live on the canceled branch | the child witness writes a second `run_started` in [witness.ts](/Users/whycz/m/bp3/.bp3/worktrees/2026-11-15-pi-engine-conductor/extensions/bp3-pi/src/witness.ts:1), and the dispatcher already writes one in [spawn.ts](/Users/whycz/m/bp3/.bp3/worktrees/2026-11-15-pi-engine-conductor/extensions/bp3-pi/src/spawn.ts:212) | do not delete canceled prior art now; mark it "do not port" for dogfood.2 unless the port proves a distinct need |

## Deletion manifest (initial; the exp completes it)

| Candidate | Delete after | Keep / replacement |
|---|---|---|
| `registry_path`, `load_registry`, `save_registry`, binding JSON round-trip, whole-file `.tmp` rewrite | derivation writer + reader parity | supervisor appends only to `run-lifecycle-derivations/<run-id>.jsonl`; fold derives the `.json` cache |
| session-keyed `find`, stored `settled`/`unsettled`, `emitted` dedupe list, in-registry usage tallies | supervisor fold derives lifecycle, dedupe, and usage from run events + tapes | derived lifecycle; no stored witness state |
| `SessionStart` stale sweep over the shared map | lifecycle derivation on read | `orphaned` is a fold result, not a mutation |
| local shared dicts (`bp3-run-registry.json`, legacy `bp3-run-events.json`) and legacy per-Run `bp3-run-events/*.jsonl` files | one-time supervisor import, snapshot hash recorded | only `<git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl` + disposable `<run-id>.json`; legacy stores are read-only inputs, never new write targets |
| grade/test references to the shared registry or legacy run events | grade reads derivation log + derived state, with raw-log escalation | grader evidence ladder: code -> parsed derivations -> raw tape |
| child-typed `BP3_RUN_ID`/`BP3_QUEST`/`BP3_EXP` command prefixes in workflow children; hook `extract_preset` binding | InitRecord/WAL association proves witnessed Runs without child compliance | run-id remains launcher/spawn context, not a child proof ritual |
| Stage B only: hook usage/refusal/lint telemetry branches, `emit`/`append_event`, and hook registration if fully duplicated | backtest.1 parity proves tapes cover usage, refusals, and lint facts | supervisor adapters; otherwise hooks remain footprint writers |

## Deletion manifest (completed by this exp, 2026-11-15)

Shadow parity (pre-deletion evidence): the mvp.4 fixtures in
`test/harness.sh` folded the shared map and the per-Run
derivations side by side — a settled legacy binding folded
`finished`, a legacy per-Run log folded `init`, and where the
map claimed a duplicate Run settled, the derived fold's
`active` won with no silent merge. No critical diff blocked
the read cutover below; lifecycle truth now comes only from
derivations.

| Candidate | Owner / live callers | Replacement | Disposition |
|---|---|---|---|
| supervisor legacy import (`legacy_views`, `get_float_opt`, `legacy_sunset`, shared-map + legacy-event reads in `src/quest/harness.ml`) | supervisor tick (`do_supervisor`) was the only caller | derivation logs + disposable cache are the sole lifecycle read path | **Deleted.** Supervisor verdicts contain no legacy-only Runs; legacy fixture files stay byte-identical (hash + mtime asserted in `test/harness.sh`); negative grep gates pin the retired spellings out of `harness.ml` |
| grade/test references to `.git/bp3-run-registry.json` (`skills/induct/workflows/induct-grade.js`, `.agents/workflows/induct-grade.js`, `test/induct-grade.test.mjs`) | audit child prompt; one mock-host test | bp3-stamped submit ledger line (mvp.1 mechanism) + per-Run derivation log corroboration; hooks registry witness does not gate (owner ruling) | **Deleted / migrated.** Auditor quotes the stamped ledger line; the test asserts the registry is never named |
| local shared dicts (`bp3-run-registry.json`, `bp3-run-events.json`) | machine-local witness data in the git common dir, outside every desk | derivation logs under `<git-common-dir>/bp3/run-lifecycle-derivations/` | **Snapshot recorded; disposal is an operator step outside this desk.** sha256 at snapshot: `bp3-run-registry.json` = `4a0f47af8dab21b408acead4ef07c21d5c26d1dfd4da26d0bf542774ba33bcfd`, `bp3-run-events.json` = `15579108105513ee99e69b17b4e8d2069e040595e904dbd47a5cdfff8f7bd1e9`. No `bp3-run-events/` dir exists locally. Supervisor fixtures prove verdicts with the maps absent/ignored; the files themselves are not a git change |
| hooks registry machinery (`registry_path`/`load_registry`/`save_registry`, session-keyed `find`, stored `settled`/`unsettled`, `emitted` dedupe, usage tallies in `src/quest/hooks.ml`) | `bp3 q hooks` emitter; `test/hooks.sh` | none yet: cross-invocation session binding still needs a store until the supervisor association (mvp.8 InitRecord writer, still `todo`) replaces it | **Kept.** Keeper reason: hooks remain the footprint writers under the Stage B gate below, and their binding store retires with them or with mvp.8 — not before a replacement binding exists |
| `SessionStart` stale sweep over the shared map | hooks emitter | `orphaned` as a fold result in the supervisor | **Kept with hooks** (same gate); the supervisor already derives `orphaned` on read for derived Runs |
| child-typed `BP3_RUN_ID`/`BP3_QUEST`/`BP3_EXP` prefixes; hook `extract_preset` binding | workflow children (`induct-exp`/`induct-grade`/`quest-land`); hooks `PreToolUse` | InitRecord/WAL association (mvp.8 owns the writer; still `todo`) | **Kept.** Missing fact: no InitRecord writer exists for muse workflow launches yet, so deleting the prefix ritual now would unwitness real Runs. This exp's own children already run env-set (`BP3_RUN_ID` exported, stamped into the ledger) per the owner ruling |
| Stage B: hook telemetry (`emit`/`append_event`, usage/refusal/lint branches) + hook registration (`.claude/`, `.muse/`, `bin/bp3`) | hooks emitter; ledger event lines | supervisor adapters over tapes | **Kept.** Stage B gate honored: retirement requires backtest.1 parity evidence that tapes cover usage, refusals, and lint facts. Missing fact named: `exp-backtest-1-muse` is still `todo` — no backtest.1 parity report exists, so no hook branch or registration was removed |

## Kill list for the target architecture

Persist only two supervisor outputs per Run:

```text
<git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl
<git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.json  (disposable cache)
```

Kill as write targets, stores, or duplicate engines:

| Kill | Replacement |
|---|---|
| `.git/bp3-run-registry.json` session-keyed map | derivation rows keyed by run-id |
| `.git/bp3-run-events.json` shared dict | supervisor import, then disposal |
| `.git/bp3-run-events/<run-id>.jsonl` | read-only legacy import; no new writer |
| child-typed run-id prefix as proof | InitRecord + tape association |
| registry load/save and stored settled/unsettled/emitted/usage state | fold from tapes + derivation rows |
| hook ledger telemetry (`emit`, `append_event`) after WAL parity | supervisor observation rows in `run-lifecycle-derivations` |
| Pi `witness.ts` duplicate `run_started` writer | dispatcher/supervisor InitRecord; tape confirms association |
| Pi `events.ts` persistent writer/fold and TS lifecycle derivation | OCaml supervisor derivation store/fold |
| Pi dispatcher second watchdog/`awaitOne` lifecycle engine | `bp3 harness watch` as sole killer/await owner |
| duplicate option spellings (`silenceS`/`silence_s`, `graceS`/`watchdogGraceS`) | one CLI/tool spelling chosen at adoption |

## Not deletion candidates

- Ledger FSM transitions and the `Store` fold: state truth.
- Run folders, notes, tapes, and tapes: evidence.
- Spawn safety, role validation, desk guards, and the
  session parser: live behavior, however it is ported.
- Historical ledger event rows already committed:
  history is not rewritten to satisfy a cleanup.

## Acceptance (fails today: registry path and prefix ritual are live)

| Case | Expected |
|---|---|
| inventory complete | every candidate has owner, caller count, replacement, evidence, disposition |
| shadow parity | old map read and new per-Run fold agree on started/settled/usage for the fixture corpus; critical diffs block deletion and are listed |
| conversion idempotent | converting the shared map twice yields identical per-Run logs, no duplicate rows |
| derived cache disposable | deleting `<run-id>.json` changes no verdict; the next read rebuilds it from logs with matching input fingerprints |
| shared across desks | the same Run read from the main checkout and a linked desk resolves to the same common-dir files and derived state |
| write cutover | a new witnessed Run writes only its per-Run log; shared map hash unchanged |
| read cutover | grade and reports read the run event/derivation logs; no live surface names the shared registry |
| code retirement | no `registry_path`/`load_registry`/`save_registry` symbols or live `bp3-run-registry` spellings remain in `src`, `test`, or `skills` |
| local data retirement | snapshot hash recorded before disposal; new Runs still witnessed with the shared maps absent |
| child burden removed | a workflow child is witnessed without typing the run-id prefix (after mvp.4 association is live) |
| Stage B gate | hooks retire only with backtest.1 parity evidence; otherwise the manifest records them kept, with the missing fact named |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** the old witness mechanism is gone
  because the new one demonstrably covers it.
- **Prove by:** deletion manifest, shadow-parity
  report, cutover fixtures, negative grep gates,
  and `make check`.
- **Done when:** shared-map code/data paths are
  retired, consumers read per-Run evidence, and any
  item not deleted has a named keeper reason.

## Tests

known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). unit: conversion and
fold parity over fixture maps (empty, one Run,
parallel Runs, torn final row, duplicate events);
derived-state cache hit/miss by input fingerprint;
stale `.json` ignored and rebuilt. property-based:
conversion is idempotent and order-independent; no
conversion invents a settled Run. integration:
parallel hook events write separate Run files with
zero lost rows; reads from two linked worktrees
agree. negative gates: repository grep for retired
spellings, and a fixture run with shared maps absent.
Demos: shadow parity report and first post-cutover
witnessed Run, observed.

## Context

This pass exists because the new supervisor design
does not merely add a cleaner mechanism; it makes a
visible pile of older plumbing redundant. Naming
the deletion as its own exp keeps "delete a lot" as
an auditable outcome instead of a hope attached to
mvp.4. The local `.git/*.json` files themselves are
machine-local data: disposing of them is an
operational step after conversion, never a git
change pretending to delete history.
