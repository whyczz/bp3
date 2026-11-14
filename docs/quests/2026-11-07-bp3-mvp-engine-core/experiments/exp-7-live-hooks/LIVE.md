# Exp 7 — Live hooks evidence (author record, submit Run)

Run: `20261114T065602Z-submit-muse-code-muse-wonder-1.0-c1`
Harness/model: muse-code / muse-wonder-1.0. Cycle 1.

## Step 1 — delivery confirmed

- `.muse/hooks.json` exists at the repo root and names
  `./bin/bp3 q hooks` for all nine events: SessionStart,
  PreToolUse, PostToolUse, PostToolUseFailure, PostLLMCall,
  SubagentStart, SubagentStop, Stop, SessionEnd (9 command
  entries, verified by grep).
- `.claude/hooks.json` and the merged `.claude/settings.json`
  carry the same nine (Exp 6 delivery, commit `adc2a1d`).
- The emitter itself answers: a `SessionStart` payload piped
  to `./bin/bp3 q hooks` returned
  `{"ok":true,"event_line":null,"reason":"no stale bindings"}`
  with exit 0. The binary is built and fail-open.

## Step 2 — live witness check (while this Run is live)

- This session's first shell commands carried the env preset
  (`BP3_RUN_ID=20261114T065602Z-submit-muse-code-muse-wonder-1.0-c1
  BP3_QUEST=2026-11-07-bp3-mvp-engine-core BP3_EXP=exp-7-live-hooks`),
  and a later dedicated prefixed probe command ran after the
  run folder existed.
- Result: **absent.** The exp ledger on
  `bp3/exp/2026-11-07-bp3-mvp-engine-core/exp-7-live-hooks`
  still holds only its `create` line; the Demo grep
  `grep -c '"event"'` returns **0** (the "before" count).
- No binding exists for this session: the registry at
  `.git/bp3-run-registry.json` reads `{"sessions":{}}`
  (the file itself was created by the emitter probe above,
  which also proves the emitter runs when invoked).
- Run ids seen in this ledger: none. `run_started` for this
  Run's id: not present. No event line was typed by hand;
  the hook path was never invoked synthetically for this
  Run, because that would fabricate the evidence this exp
  exists to produce.

## Reading

Delivery is correct and the emitter is sound (Exp 6
fixtures green), but the Muse host did not fire
`.muse/hooks.json` for this workflow child's tool calls:
no PreToolUse witness, no registry binding, no ledger
event. This matches the Exp 6 live limit in kind (a tier
present on disk, a host that does not call it on this
path), now observed on the Muse tier inside an
`induct-exp` child instead of a headless main session.

## What would close this exp

A Run whose host actually executes the project hooks —
then `run_started` lands on the exp branch mid-Run and
`usage_recorded` + `run_settled` land at settle, and the
Demo grep after landing reads N >= 6 across submit,
review, and check. Until such a Run, the Acceptance table
stays red on its first three rows; the state fold is
unaffected (`bp3 q r` reads this exp `todo`, cycle 1).
