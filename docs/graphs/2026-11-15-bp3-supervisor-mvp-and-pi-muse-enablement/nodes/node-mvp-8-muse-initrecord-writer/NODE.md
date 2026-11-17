---
date: 2026-11-15
goal: ../GRAPH.md
exp: mvp.8
status: proposed
---

# mvp.8 - muse-initrecord-writer: who writes InitRecord for muse?

## TL;DR

Red-chair RC1: mvp.2 lookup is InitRecord-first, but
the passive muse supervisor spawns nobody. Name and
prove the writer (induct workflow launcher) so every
Muse workflow child has an InitRecord before it
starts — or the lookup degrades honestly.

## Demo (design trace)

```text
induct-exp launches child C for run R
  -> InitRecord(R) appended before child starts
  -> bp3 harness find-tape --run-id R resolves tape
```

## Diagram

```text
induct workflow ──writes──► InitRecord ──► find-tape ──► fold
child (never writes proof)
```

## Pseudocode

```python
def launch(run):
    append_init_record(run)      # launcher, before spawn
    spawn_child(run)
```

| Field | Value |
|---|---|
| Intent | close the InitRecord ownership hole for the passive engine |
| Lane | standard |
| Output | named writer in the induct path + coverage proof over real child launches |
| Depends on | mvp.4 |

## Acceptance (fails today: writer unnamed)

| Case | Expected |
|---|---|
| muse workflow child launch | InitRecord exists before child's first tape entry |
| launch killed mid-spawn | InitRecord present, lifecycle can go `orphaned`, never invisible |
| child with no InitRecord (legacy run) | lookup reports typed miss, no guessed binding |
| env-set run-id (owner ruling from mvp.1) | `BP3_RUN_ID` arrives via environment and bp3 stamps it into verdicts and ledger lines. Grade evidence is that stamped ledger line; the hooks registry witness does not gate this exp |

## Acceptance test (goal block)

- **Objective:** every muse Run is lookup-able from birth.
- **Prove by:** instrumented induct-exp launches incl. one killed mid-spawn.
- **Done when:** InitRecord precedes first tape entry in all launches; legacy miss is typed.

## Context

From the post-adoption red-chair (RC1). The child
must never write its own proof; the launcher is the
only actor present before the child exists.

## Tests

Known cases: Acceptance table; env-set run-id is
stamped by bp3 into the submit verdict and ledger
line (the mvp.1 mechanism). Property-based: for
any launch order/interleaving, InitRecord timestamp
<= first tape entry timestamp for that run-id.
