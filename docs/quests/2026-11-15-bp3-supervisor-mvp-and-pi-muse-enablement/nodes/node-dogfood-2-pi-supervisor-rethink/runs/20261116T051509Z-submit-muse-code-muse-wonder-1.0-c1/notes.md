# Run notes — exp-dogfood-2-pi-supervisor-rethink c1 (design)

## What was decided

- Completed EXPERIMENT.md as a decided design: three-component pi MVP (bp3-pi extension, dispatcher, OCaml supervisor), with keep/replace/drop for every canceled-quest component, all 8 settled defects, and backtest.2 F1–F4 consumed by name.
- Key calls: binding/await replaced by record-init + bind-tape + watch; witness writer, events.ts store/fold, dispatcher watchdog, stored lifecycle, and tape-copy all dropped. Supervisor (C) already exists and needs no new code for the MVP; only extension + dispatcher (A+B) remain to build for a full drive.
- dogfood.3 needed no delta: its landed demo (pi Run derived `finished`, flappy.html, node --check pass) is the cold-reader proof the MVP core runs as written.

## Lessons

- The canceled quest's inventory is fully enumerable from its QUEST.md; the supervisor contract already answers most of it, so the design work is mostly deletion, not invention.
- Owner gate must stay honest: this record claims no owner nod. The demo ran under the owner's demo-as-experiment ruling, but a full pi drive still waits for approval of this design in the quest record.
- F1 (pi tapes bind sessions, never Runs) is the load-bearing finding: it forces InitRecord-first binding and explains both the backtest 0/5 exact match and dogfood.3's find-tape scan miss.

## Verification

- Design exp, no code changed: verified by re-reading the canceled quest, backtest.2 findings, dogfood.3 derivation/notes, and harness.ml's live pi surface (record-init/bind-tape/fold present; no bp3-pi extension exists yet). No test suite run — no code to gate; stated, not implied.
