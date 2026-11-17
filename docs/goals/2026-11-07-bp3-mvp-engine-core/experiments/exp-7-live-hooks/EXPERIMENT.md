---
date: 2026-11-14
goal: ../GOAL.md
exp: 7
status: proposed
---

# Exp 7 — Live hooks evidence

## TL;DR

Prove the Exp 6 hooks emitter fires in a real `induct-exp`
run: with `.muse/hooks.json` installed at the repo root
(commit `adc2a1d`), this exp's own Runs must leave past-tense
event lines (`run_started`, `usage_recorded`, `run_settled`)
in this exp's ledger, written by the hooks themselves — never
typed by a child or a human.

Status: **proposed, not implemented.** Fails today: the grep
in the Acceptance test returns zero event lines for every
real ledger in this quest.

## Demo (design trace)

```text
$ git show bp3/exp/<quest>/exp-7-live-hooks:.../exp-7-live-hooks/ledger.jsonl \
    | grep -c '"event"'
0        <- today, every exp
N >= 6   <- after this exp: at least run_started + run_settled
            for the submit, review, and check Runs of cycle 1
```

## Work

| Step | What |
|---|---|
| 1 | Author: confirm `.muse/hooks.json` exists at repo root and names `./bin/bp3 q hooks` for all nine events; confirm your own session is being witnessed (your first command carried the env preset) |
| 2 | Author: while your Run is live, read the exp ledger via `git log`/`git show` on the exp branch: your `run_started` line should already be committed there by the hook. Record what you found (present/absent, run_id match) in your run `notes.md` and in `LIVE.md` in this exp folder (the authored artifact this exp commits) |
| 3 | Review + check: verify from the ledger — not from prose — that event lines exist for the submit Run, each carries `ts` + `run_id`, none carries `edge`/`from`/`to`, and the exp state still folds correctly (`bp3 q r` agrees) |
| 4 | Land: after landing, the ledger read in the Demo is the final evidence |

## Acceptance (fails today)

| Case | Expected |
|---|---|
| submit Run live | `run_started` + `run_settled` for its run_id in this ledger |
| review/check Runs live | same pair each; parallel Runs do not mark each other `run_unsettled` |
| usage | one `usage_recorded` per settled Run, real token fields |
| any event line | `ts` + `run_id`, no `edge`/`from`/`to`; `bp3 q r` state unaffected |
| authored record | `LIVE.md` quotes the grep count before (>0) and the run_ids seen |

## Acceptance test (goal block)

- **Objective:** produce the first real-ledger hook event
  lines in this quest, from this exp's own Runs.
- **Prove by:** the Demo grep against the exp branch ledger
  after landing; `LIVE.md` contents; `bp3 q r` still reads
  `landed`.
- **Done when:** grep count > 0 with all three kinds present
  and `make check` green.

## Context

Exp 6 built the emitter and passed every fixture case, but
delivery went to the Claude Code tier only, so Muse runs
never fired it; the landing diligence gate failed exp-6 on
exactly this. Option A (owner, 2026-11-14): install the
`.muse` tier and run one live pass. This exp is that pass.
