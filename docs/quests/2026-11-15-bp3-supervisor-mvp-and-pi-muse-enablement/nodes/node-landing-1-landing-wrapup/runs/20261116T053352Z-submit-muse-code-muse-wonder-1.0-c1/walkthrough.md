# landing.1 — owner walkthrough (run in this Run, not scheduled)

This is the landing-demo input for `quest_fin`. Every step below was
executed in Run `20261116T053352Z-submit-muse-code-muse-wonder-1.0-c1`;
verbatim output is in this folder's `tape.log`. Steps are read-only and
runnable from the record in order.

## Settled picture

```text
child (muse / pi) ──► tape (harness WAL)
                          │  supervisor fold: InitRecord + tape tail + pid
                          ▼
              init / active / finished / orphaned
                          │  bp3 q ledger owns exp state
                          ▼
              grader: artifacts → derivations → raw tape (ladder)
```

## Step 1 — the ledger tells the truth (observed)

```text
$ ./bin/bp3 q 2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement r
{"ok":true,"quest":"...","state":"proposed", 17 exps landed/exp_fin,
 exp-landing-1-landing-wrapup: todo (this Run submits it), "rollup":"active"}
```

## Step 2 — blindness surfaces at startup, never mid-Run (observed)

```text
$ ./bin/bp3 harness init-check --engine muse-code
{"ok":true,"checks":[{"harness":"muse-code","tape_source":"/Users/whycz/.local/share/muse/sessions","present":true}]}
$ ./bin/bp3 harness init-check --engine pi
{"ok":true,"checks":[{"harness":"pi","tape_source":"/Users/whycz/.pi/sessions","present":false}],"warnings":["W_SUPERVISOR_BLIND"]}
```

The pi warning is the honest current state on this host (see
scorecard's named exceptions and disposition D8), not a failure:
work proceeds, observability degraded.

## Step 3 — a pi Run derived finished (observed, dogfood.3 artifact)

`exp-dogfood-3-pi-toy-quest/runs/20261116T050144Z-...-c1/pi-derivation.json`
records pi Run `20261116T050354Z-demo-pi-gpt-6.1-sol-c1` with
`lifecycle: finished`, `pid_alive: false`, and its `flappy.html`
(6289 bytes, sha256 in the same file) built by the pi child.

## Step 4 — pointer resolution, not whole-tape reads (runnable)

```text
$ ./bin/bp3 harness find-tape --run-id <any landed Run id>
$ ./bin/bp3 harness find-tape --run-id <id> --entry <entry-id>
```

`--entry` returns the one digest-verified tape entry; the grader
never ingests a whole tape by default (QUEST grader ladder, rung 5
only when blocked).

## Deliberately open (owner answers at `quest_fin`)

- D8: align the probed pi tape source with the host's actual
  `/Users/whycz/.pi/agent/sessions` layout, or leave warn-only.
- D9 (RC5): pointer digests vs harness tape compaction — measure
  via backtests; ladder fallback is the current answer.
- Checkpoint: promote the quest, or another pass.
