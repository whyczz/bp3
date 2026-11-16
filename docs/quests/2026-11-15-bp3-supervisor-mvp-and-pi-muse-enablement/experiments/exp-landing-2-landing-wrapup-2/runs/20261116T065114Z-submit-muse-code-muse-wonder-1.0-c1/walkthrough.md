# landing.2 — owner walkthrough (run in this Run, not scheduled)

This is the landing-demo input for the owner's `quest_fin` review of
the pi-extension arc. Every step below was executed in Run
`20261116T065114Z-submit-muse-code-muse-wonder-1.0-c1`; verbatim
output is in this folder's `tape.log`. Steps are read-only and
runnable from the record in order. Steps 1–3 close the arc; step 4
is the owner's checkpoint.

## Settled picture

```text
pi conductor (bp3-pi loaded)
  spawn_run ─► dispatcher: record-init (live pid) ─► pi child ─► tape
  await_runs ─► bp3 harness watch ──sole TERM/KILL──► child
  list_runs ─► supervisor fold (run-lifecycle-derivations)
        init / active / finished / orphaned
roles/*.md ─► effective BP3_MODEL + BP3_THINKING (override > role > conductor)
bp3 q ledger owns experiment state throughout
```

What is now true that was not true at landing.1: the launcher is the
product. A pi conductor drives real work through the extension's four
tools with no hand-played `record-init` / `bind-tape` and no
shell-spawned pi, and the OCaml supervisor still writes every proof.

## Step 1 — the ledger tells the truth (observed)

```text
$ ./bin/bp3 q 2026-11-15-bp3-supervisor-mvp-and-pi-muse-enablement r
ok: True, quest state: proposed, rollup: active
21 exps landed/exp_fin (incl. followup.5 7a92e59, followup.6 89f683e,
dogfood.4 18ad6c5); exp-landing-2-landing-wrapup-2: todo (this Run)
```

## Step 2 — blindness surfaces at startup, never mid-Run (observed)

```text
$ ./bin/bp3 harness init-check --engine muse-code
{"ok":true,"checks":[{"harness":"muse-code","tape_source":"/Users/whycz/.local/share/muse/sessions","present":true}]}
$ ./bin/bp3 harness init-check --engine pi
{"ok":true,"checks":[{"harness":"pi","tape_source":"/Users/whycz/.pi/sessions","present":false}],"warnings":["W_SUPERVISOR_BLIND"]}
```

The pi warning is the honest current state on this host (scorecard
exceptions, disposition P5), not a failure: work proceeds,
observability degraded. A muse Run resolves through the same door:

```text
$ ./bin/bp3 harness find-tape --run-id 20261116T053352Z-submit-muse-code-muse-wonder-1.0-c1
{"ok":true,"harness":"muse-code","tape_path":"/Users/whycz/.local/share/muse/sessions/.../session.jsonl"}
```

while the dogfood.4 pi child refuses `E_NOT_FOUND` from this desk
for the same path reason — its `finished` evidence is the committed
derivation, next step.

## Step 3 — the extension drove real work, the supervisor proved it (observed)

Committed drive (dogfood.4 c1): the pi conductor called `spawn_run`
once, then `await_runs`, then `list_runs` (`drive.jsonl`, 425
lines). The child Run `20261116T064322Z-demo-pi-openai-gpt-6-1-sol-c1`
derived `finished` in the shared store — re-read live in this Run:

```text
{"run_id":"20261116T064322Z-demo-pi-openai-gpt-6-1-sol-c1","harness":"pi",
 "lifecycle":"finished","warnings":[],"pid_alive":false}
```

The child built `flappy.html` (8439 bytes, three.js) in its own Run
folder; its extracted module (7059 bytes) passes `node --check`,
re-run in this Run (exit 0). The mechanism gates were re-run fresh
in this Run, not read about: `node --test
extensions/bp3-pi/test/bp3-pi.test.mjs` → 11/11 pass (four tools
only, hostile-input refusal, spawn path, role routing, thin await,
hung child `orphaned` never `finished`, closed-not-exited, dirty
desk refused, dispatcher never signals a pid, dispatcher writes no
proof); `./test/harness.sh` → all checks passed.

`--entry` pointer resolution (`find-tape --run-id <id> --entry
<entry-id>`) remains the grader's one-entry read; the ladder never
ingests a whole tape by default (QUEST grader ladder, rung 5 only
when blocked).

## Deliberately open (owner answers at `quest_fin`)

- P4: run a real hung-pi drive, or accept the fake-pi + OCaml watch
  proof as the mechanism evidence.
- P5: align the probed pi tape source with this host's actual
  `/Users/whycz/.pi/agent/sessions` layout, or leave warn-only.
- P6: give worktree-shaped repo roots a dispatcher fix (its own
  exp), or keep the `BP3_PI_BP3_BIN` pin as the documented drive
  shape.
- D8/D9 from landing.1 stand: pi source alignment (same item as
  P5) and pointer digests vs harness tape compaction (RC5).
- Checkpoint: promote the quest, or another pass.
