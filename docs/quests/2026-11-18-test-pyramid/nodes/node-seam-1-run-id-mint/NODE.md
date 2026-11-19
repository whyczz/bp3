---
date: 2026-11-18
quest: ../../QUEST.md
node: seam.1
status: proposed
---

# seam.1 - run-id-mint: unique without sleeping

## TL;DR

`bp3 harness link mint` builds run-ids from `compact_ts`, which has
whole-second resolution. Two mints with the same edge, harness,
model and cycle in one second collide, and the engine sleeps 1.0s
before retrying, up to 5 times (`harness.ml:2319`). This node puts
milliseconds and a random suffix into the first field of the id and
retries at once.

## Acceptance gates

Observed today (code read, 2026-11-18):

```text
harness.ml:2319  cand = compact_ts() ^ "-" ^ edge ^ "-" ^ harness ^ "-" ^ model ^ "-c" ^ cycle
                 EEXIST -> Unix.select [] [] [] 1.0; retry (5 tries)
```

Design trace:

```text
$ for i in $(seq 50); do bp3 harness link mint ...same flags...; done
50 distinct run_ids, e.g. 20261118T110640.123a7f3Z-handoff-pi-none-c1
total 0.6s (no call waits 1s)
```

```yaml
objective: mint run-ids that do not collide within a second and never sleep on a collision
prove by:
  - two back-to-back mints with identical flags; time the second   # >= 1.0s today
  - 50 identical mints in a loop
  - dune test: fake clock frozen at one instant, 1000 mints in a temp config dir
done when:
  - 50 identical mints give 50 distinct ids in under 2s total
  - 1000 mints under a frozen fake clock give 1000 distinct ids
  - Hooks.parse_edge_cycle and Worktree.valid_run_id accept the new ids and every old-format id in the unit.4 table
  - no Unix.select or sleep remains on the mint path
```

## Diagram

```text
compact_ts (seconds) ──► "20261118T110640Z-handoff-pi-none-c1"   collision: sleep 1s
new_ts (ms + 4 hex)  ──► "20261118T110640.123a7f3Z-handoff-pi-none-c1"
                          └── field 1 carries the uniqueness; fields 2 and last unchanged
```

## Pseudocode

```python
def mint_ts(now, rand):
    t = gmtime(now)
    return f"{t:%Y%m%dT%H%M%S}.{int(now * 1000) % 1000:03d}{rand.hex(2)}Z"

def mint(edge, harness, model, cycle, tries=5):
    for _ in range(tries):
        cand = f"{mint_ts(Clock.now(), urandom)}-{edge}-{harness}-{model}-c{cycle}"
        if write_exclusive(cand): return cand        # no sleep between tries
    refuse("E_EXISTS")
```

| Field | Value |
|---|---|
| Intent | remove a 1s sleep and a per-second collision from the mint path |
| Lane | standard |
| Output | `harness.ml` mint change, unit test, timing check |
| Acceptance | goal block above; fails today (second identical mint waits 1s) |
| Depends on | unit.2 (`Clock.now` gives sub-second time; fake clock for the unit test) |
| Tests | known cases: the parser compatibility table (old and new ids); property-based: `law_minted_ids_are_unique_under_a_frozen_clock` (1000 mints), `law_minted_ids_parse_back_to_their_edge_and_cycle`; fixture: the 50-mint loop |

## Prose

Tests that mint several links quickly pay this sleep today, and
real fan-out (one child per ready node) can hit it too. The id shape
was settled at red-ink R3 (milliseconds plus 4 hex inside field 1).
The constraint behind it:
`parse_edge_cycle` reads the edge as dash field 2 and the cycle as
the last field, so the uniqueness has to sit inside field 1, and
field 1 must contain no dash. `valid_run_id` already allows `.`.

Old ids stay valid. Nothing parses the timestamp back into a time
(checked: `compact_ts` has one caller), so a longer first field
breaks no reader.
