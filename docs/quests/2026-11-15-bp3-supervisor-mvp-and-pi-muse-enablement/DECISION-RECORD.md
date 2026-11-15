# Decision record

Forked from:
`docs/quests/2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement/QUEST.md`
(original preserved in git history and in a local
snapshot taken before adoption)

Working copy (adopted over the original by owner
word, 2026-11-15):
`docs/quests/2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement/red-ink/`

Lens: `expert-cli`. Shadow decisions below are from
the auto-red-ink pass; owner decisions from the
manual red-ink walk are in their own table and win
where they disagree.

## Owner corrections folded in during the walk

| Correction | Design consequence |
|---|---|
| Muse workflows exit naturally | no active Muse supervisor loop; Muse runtime keeps completion authority, supervisor only derives lifecycle/events |
| Supervisor can still derive lifecycle for Muse | passive supervisor is shared across engines; active spawn/watch/kill is Pi/raw-process only |
| Burden of proof must leave the child | InitRecord + tape fold + pid evidence; child produces work, supervisor produces proof |
| Grader = reviewer | evidence ladder: code/artifacts -> parsed events -> raw tape only when needed |
| Add acceptance + unit-test hardening | [TEST-HARDENING.md](TEST-HARDENING.md), plus an addendum in every exp record |

## Owner decisions (manual red-ink)

| Round | Slice | Decision (owner's call) |
|---|---|---|
| 1 | Output | A: `run-lifecycle-derivations/` is the sole persisted supervisor output. `<run-id>.jsonl` is authoritative; `<run-id>.json` is a disposable, fingerprint-checked cache. No second persisted store. |
| 2 | Inputs | A: the door is `bp3 harness`. Owner-added verb: `bp3 harness init-check` probes, per harness, that tapes exist, consumed fields line up, and the adapter parses — blindness surfaces as `W_SUPERVISOR_BLIND` at startup, not mid-Run. U1 closed. |
| 3 | Inputs | C: engine is derived from the run-id's InitRecord wherever a Run exists; stated only for `supervisor`/`init-check`. Engine word is `muse-code` (not `muse`). Contradiction with the record is a usage error. U2 closed. |
| 4 | Inputs | C: quest is a positional (`bp3 harness supervisor <quest>`), `--run-id` stays flagged, and every harness verb gets a tested single-letter alias (`i/s/f/w/d`), door-scoped. U6 closed. |
| 5 | Inputs | Durations carry the unit in the flag name: `--silence-seconds`, `--timeout-seconds`, `--grace-seconds`, bare positive integers; `0`/negative/suffixed are usage errors. U3 closed; S11's named-input ruling kept. |
| 6 | Data | A: derivation rows store pointers only — tape path, entry id, byte range, digest, pid probe; never session content. Rationale (owner): whole tapes must never be slammed into a grader LLM; the ladder reads cited entries. Tapes and derivations are both uncommitted, local, near-term evidence. Amended (owner): pointers resolve only through `bp3 harness find-tape --run-id <R> --entry <id>` (digest verified; `--before-entries/--after-entries <n>` widen the window) — hardened in bp3, not left to skill memory. Owned by mvp.2. |
| 6b | Data (follow-up) | New exp mvp.7 - grader-evidence-ladder (owner): ladder wired into grader instructions + `induct-grade`; depends on mvp.2 + mvp.4; lying-fixture acceptance. Grader ladder in QUEST.md rewritten to owner's five rungs. |
| 7 | Names | `W_SENTINEL_BLIND` renamed `W_SUPERVISOR_BLIND` (owner), swept across the working copy (11 sites, 0 old spellings left). Code rename owed wherever the old spelling lands. |
| 8 | Names | The derived store is named `run-lifecycle-derivations` (owner: "call it run-lifecycle-derivations"; "i like the term"): `<git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl` + `<run-id>.json`. Round 1's decision updated, not reopened (18 sites swept). |
| 9 | State | A: no fifth lifecycle word. Blind probes append observation rows with `W_SUPERVISOR_BLIND` and empty evidence data; lifecycle keeps deriving from pid + InitRecord. U10's fifth-word question closed. |
| 10 | Names | "authority" renamed "owner" (owner's word): the split table is now `Owners` with completion/control, lifecycle/proof, and experiment-state owner columns. Swept across QUEST, TEST-HARDENING, exp records; shadow-history rows left as written. |
| 11 | Functions | B: exit 0 only for `settled`. `watchdog_killed`=terminal, `timeout`=retryable, `human_gate`=needs-human; exact integers adopt the binary's existing exit classes at mvp.1. U11 closed. |
| 12 | Names | A: `sentinel` killed. One actor — supervisor, passive (muse-code) / active (pi). Term `tape` replaces "session log" everywhere (definition carries the explanation); verb `find-session-log` renamed `find-tape`, exp mvp.2 renamed to match, dogfood.2 renamed pi-supervisor-rethink. Code/CLI renames owed. U9 closed. |
| 13 | Names/state | Lifecycle vocabulary is `init / active / finished / orphaned` (owner). `finished` is the lifecycle value; `settled` remains the call outcome/verdict predicate, so the two axes no longer share one word. |
| 14 | Names/code | The rename binds implementation, not just prose: new OCaml code/tests use `init_record` and the four lifecycle strings; `SpawnRecord` and the old lifecycle synonyms are retired. Current `src/` has no `SpawnRecord` identifier — the legacy hooks `binding` record is separate legacy machinery, deleted by mvp.5 rather than cosmetically renamed. |
| 15 | Names | The section formerly called "Burden split" is `Owners / responsibility`; the grader's output is a `grade`, not "judgment". The argv term "judgment inputs" became "decision inputs" to keep `grade` unambiguous. |
| 16 | Adoption | Owner: "adopt design". The red-ink copy replaces the original quest design (QUEST.md, experiments/, plus DECISION-RECORD.md and TEST-HARDENING.md at quest root). This adopts the design only; the quest is not created in bp3 and not promoted. |

## Settled shadow decisions

| # | Decision | Evidence that forced it | Copy change |
|---|---|---|---|
| S1 | One CLI grammar must exist; final spelling stays unsettled | the draft used three engine-selector spellings in one argv slot | demos normalized to a provisional door token; U1/U2 remain |
| S2 | Long verbs stream NDJSON lifecycle changes and end with one JSON verdict | existing `print_verdict` law; prose stdout is unparseable | QUEST CLI verdict contract; mvp.1/mvp.3 addenda |
| S3 | `outcome`, `settled`, and `lifecycle` are different fields | `killed` was both fate and state; exit 0 was ambiguous | contract in QUEST; mvp.3 tests split them |
| S4 | `W_SUPERVISOR_BLIND` is `warnings[]` only | bp3 already has one warnings channel | Terms + mvp.3 blindness tests |
| S5 | Run-id is the sole key; session-id is reverse lookup only | canceled quest settled this after four blocks; session-keyed registry is the failure in code | mvp.2/mvp.3 identity rules + conflict tests |
| S6 | Records are inlined; no dangling contract authority | `docs/engine-contract/` does not exist | InitRecord/event/trace records named in QUEST |
| S7 | No target `run-events` store; "run event" is only an internal normalized record type | tape + derivation log + copied run events would be three versions of one story | Terms removed; legacy per-Run event logs are read-only imports only |
| S8 | Lifecycle derives from files + pid, never memory | in-memory live set orphans all children after restart | derivation table in QUEST |
| S9 | A settle row alone never settles; closed children get settling grace | parent-context settle bug and kill-while-settling race in inspected code | mvp.3 closed-but-not-exited case |
| S10 | Tick = tell -> watch -> judge (`bp3 q r`) -> finalize; watch is sole killer | process exit is evidence, not an FSM verdict; two killers race | mvp.1 phases + legality/guards |
| S11 | Named duration/grace inputs; invalid values are usage errors | 900s/5s prior art; `--silence 0` otherwise means two opposite things | mvp.3 input tests |
| S12 | Env never implicitly selects a Run; `BP3_THINKING` is actually set | a child could otherwise watch itself; witness read a never-set field | mvp.2/dogfood.2 env tests |
| S13 | Usage-error surface is enumerated per verb | existing binary exit classes already define the grammar | Inputs tables required in mvp.1-mvp.6 |
| S14 | Desk migration covers all nine verbs with golden fixtures | parity claim covered only 3 of 9 and used the wrong verdict shape | mvp.6 rewritten scope |
| S15 | Creation refuses reserved door/verb slugs | creatable quests can become unaddressable today | mvp.6 tests |
| S16 | Trace kinds are enumerated mechanical facts; fold preserves sequence | scope said both "extract refusals" and "never parse content"; first-wins fold deleted facts | QUEST scope + backtest tests |
| S17 | Railway dependencies and acceptance honesty are repaired | loop depended on later verbs; backtests passed at 0%; fixes had no home; Pi drive had no build exp | exp summaries + addenda |
| S18 | Muse gets passive derivation, not a second supervisor | owner correction during walk; Muse runtime already completes/wakes | authority split in QUEST |
| S19 | mvp.5 deletion pass is its own MVP step | registry/prefix machinery is live in code, workflows, and tests, so deletion needs inventory + parity + cutover, not a footnote | mvp.5 record + QUEST railway |
| S20 | Derived logs live under the Git common dir | linked worktrees share a common dir; a worktree `.git` is only a pointer file (verified with `git rev-parse`) | only `<git-common-dir>/bp3/run-lifecycle-derivations/{<run-id>.jsonl,<run-id>.json}`; `.json` is a disposable cache |

## Pi extension sketch (fleshed out)

```text
A. bp3-pi extension (in child): face selection,
   session_start binding row, optional throttled
   heartbeat, shutdown hint. Fail-open. Never mints,
   settles, kills, spawns, or calls bp3 q u.
B. Dispatcher (in conductor): validates + refuses
   hostile keys by name, mints run-id, loads role,
   prepares desk, spawns pi, and hands spawn/exit
   facts to the supervisor store.
C. supervisor/supervisor (bp3 OCaml): find-tape,
   watch (sole killer), lifecycle fold, blind probe,
   sole writer of run-lifecycle-derivations. Neither A nor B
   duplicates C.
```

Full function-level sketch and NEVER list are in
dogfood.2's auto-red-ink addendum.

## Unsettled — owner required

| # | Question | Options / consequence |
|---|---|---|
| U1 | Final door name | keep `bp3 harness` with disambiguation prose, or rename (`bp3 supervisor`, `bp3 run`, `bp3 desk`) and sweep callers |
| U2 | Engine grammar + vocabulary | `--engine muse|pi` flag vs positional engine; `muse` vs `muse-code`; admit `pi` to identity enum or not |
| U3 | Duration grammar | bare seconds (existing bp3 style) vs suffixed durations (new grammar everywhere) |
| U4 | Model/thinking surface | per-run flags, per-role flags, or role-files-only with flags refused for MVP |
| U5 | General env vs flag precedence | beyond the settled "env never selects a Run" rule |
| U6 | Aliases + quest handle | letter aliases for harness verbs vs long-only exemption; `<quest>` positional vs `--quest` |
| U7 | Existing reserved-name collisions | rename, grandfather, or escape spelling |
| U8 | Do supervisor warnings veto landing? | decide at dogfood.1's seeded blind Run: veto vs warn-only |
| U9 | Survivor words | tape vs tape; supervisor defined vs deleted; watch vs `await_runs`; supervisor serves vs replaces conductor |
| U10 | Lifecycle edges | Muse freshness window; 5th `blind/unknown` word vs reusing `spawned`; kill cause on row vs return only |
| U11 | Exit class for timeout/human gate | fate-as-data exit 0 vs distinct non-zero class |
| U12 | Desk cut | alias old spelling vs hard cut; quest-desk level survives or drops |
| U13 | Pi mechanisms | explicit face env vs presence inference; pulse source; Muse find mechanism after backtest.1; Pi adapter TS sidecar vs OCaml port; fix gating; orphaned-desk release rule |

## Proposed experiment changes

No new quest is proposed here. Inside this copy:
mvp.1 splits proof into door/verdict skeleton and
deferred live loop; mvp.4 gains substep mvp.4b (run
derivations migration); new mvp.5 deletes redundant
witness machinery after shadow parity; a
findings-fix step must sit between owner disposition
(backtest.1-2) and the live drives if any finding is
marked "fixed"; dogfood.3 gains a port/re-verify
substep before its drive. Final numbering is the
owner's at adoption.

## Red-chair pass (post-adoption, owner-ordered)

Lens: engineering. Target survived the walk; three
major concerns became follow-up exps, none left as
prose:

| # | Severity | Finding | Disposition |
|---|---|---|---|
| RC1 | major | Muse InitRecord writer is unowned: the passive supervisor does not spawn, so "written before the child starts" names nobody. mvp.2 lookup is InitRecord-first; without a writer, muse lookup fails on the primary engine | mvp.8 (promoted into MVP by owner) |
| RC2 | major | Derivation store concurrency unspecified: parallel supervisors/desks can append the same `.jsonl` and race the `.json` temp+rename; parallel Runs are the core case | followup.1 |
| RC3 | major | `finished` requires tape closed, but muse tapes may have no close marker; exited Runs could sit `active`/`orphaned` forever | followup.2 |
| RC4 | minor | Exit-class integers deferred to mvp.1 mapping; existing-class claim (S13) unverified | mvp.1 Tests sweep line |
| RC5 | minor | Pointer digests rot if a harness compacts its tape before grade time | deliberately open; grader ladder falls back a rung, backtests measure it |
