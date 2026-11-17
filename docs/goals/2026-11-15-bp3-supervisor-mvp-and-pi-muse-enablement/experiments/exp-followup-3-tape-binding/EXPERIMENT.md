---
date: 2026-11-15
goal: ../GOAL.md
exp: followup.3
status: proposed
---

# followup.3 - tape-binding: binding a workflow Run to its session tape

## TL;DR

dogfood.1 live finding: a Muse workflow Run derives
`init` forever and can never reach `finished`. Two
mechanical causes. (1) The launcher writes the
InitRecord before the child exists, so it cannot name
the child's session tape — the only tape whose tail
carries Muse finish evidence; the run-folder
`tape.log` has no closing entry, so the fold derives
`orphaned` at best. (2) `tape_evidence` reads only
the last whole tape line, but real Muse child tapes
end with a `task` entry after the `run` terminal
entry, so even a correctly pointed fold misses the
finish. Bind the tape after the child finishes
(launcher, never the child), and make the tail scan
find the close among trailing task entries.

## Demo (design trace)

```text
record-init (pre-spawn, create-only, no tape named)
author run: submits, session tape closes
  ... runtime run terminal, then task completed
launcher bind step: bind-tape --run-id R --tape-path <session tape>
supervisor tick -> observation lifecycle=finished
```

## Diagram

```text
launcher ── record-init ──► InitRecord (no tape yet)
author ──── work ─────────► session tape (closes)
launcher ── bind-tape ────► binding row (pointer only)
supervisor fold ──────────► finished, pointer + digest
```

## Pseudocode

```python
def fold(run):
    tape = init.tape_path or latest_binding(run).tape_path
    ev = finish_evidence(tape)   # scan tail: skip task entries,
                                 # run terminal / session.end closes
    return finished if ev and not pid_alive else derive(...)
```

| Field | Value |
|---|---|
| Intent | make live Muse workflow Runs derivable to `finished` by the supervisor |
| Lane | standard |
| Output | post-spawn tape binding (new harness verb + fold honor) and tail-scan finish evidence |
| Depends on | mvp.2 (find-tape), mvp.4 (supervisor fold), mvp.8 (record-init), followup.2 (finish evidence) |

## Acceptance (fails today: live Muse run stuck at init/orphaned)

| Case | Expected |
|---|---|
| bound workflow Run | InitRecord without a tape path + a launcher binding row → supervisor derives `finished` from the session tape, with the tape pointer on the observation row |
| real Muse tail shape | a tape ending `run` terminal then `task` entries still yields finish evidence; a marker named mid-tape is still content, never an ending |
| torn tail still blind | a torn final entry (unterminated or unparseable) finishes nothing and warns `W_TORN_TAIL`, with or without a binding |
| no binding, no tape path | lifecycle stays `init` with `W_SUPERVISOR_BLIND` on probe — no guessed binding, ever |
| binding discipline | binding rows are pointer-only (tape path, no tape content), appended as one write by the launcher's bind step; the author child writes no InitRecord, binding, or observation |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Binding resolution (how the launcher finds the tape)

The author child cannot name its session tape before
it exists, and workflow JS learns no session identity
from a child result (`{ref, summary, text}` only —
probed). So the bind step runs after the author
returns, as a launcher child: it resolves the tape
mechanically (session store scan keyed on the
run-id/session binding the tape itself carries, or
`bp3 harness find-tape` once resolution is
unambiguous for the bound session) and calls the
bind verb. A resolution that is not unique refuses —
typed, never a guess.

## Acceptance test (goal block)

- **Objective:** a completed Muse workflow Run is
  derivable to `finished` from files alone.
- **Prove by:** harness fixtures in the real closing
  shape (terminal entry + trailing task entries),
  a bound InitRecord folded by the supervisor, and
  the launcher bind step exercised in the workflow
  tests.
- **Done when:** every Acceptance case derives the
  named lifecycle and `make check` is green.

## Context

Found live at dogfood.1 cycles 3–4: fixtures all
passed while real Runs derived `init`/`orphaned`.
The pointer the launcher could set pre-spawn
(run-folder `tape.log`, induct-exp fix `c7437b1` +
`17a7679`) stays — it names where the child's own
transcript lands — but it is not finish evidence.
This exp binds the harness session tape, where the
close actually is.

## Tests

Known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). New fixtures must copy
the real Muse closing shape (entries after the
terminal entry), not the truncated fixture shape
that hid this. Property-based: with a live pid, no
tail shape and no binding ever derives `finished`.
