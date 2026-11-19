---
date: 2026-11-18
quest: ../../QUEST.md
node: js.1
status: proposed
---

# js.1 - fake-bp3: one JS style, no real launches in the unit tier

## TL;DR

Every JS test moves to `node:test` with `node:assert/strict`. Today
six files use a hand-rolled `ok`/`fails` counter, one uses node:test,
and one uses assert/strict alone. The bp3-pi extension tests run
against `test/fake-bp3/`, a stand-in executable that replays
transcripts recorded from the real binary. `check-full` re-records
the transcripts and fails on drift. `pi-tree` stays a real
process-tree proof in the slow tier.

## Acceptance gates

Observed today (2026-11-18):

```text
node:test + assert/strict : extensions/bp3-pi/test/bp3-pi.test.mjs
assert/strict only        : test/pi-discovery.mjs
custom ok/fails counter   : node-loop, induct-node, induct-grade, induct-land,
                            induct-conduct, pi-tree
bp3-pi.test.mjs           : 22.42s, real bp3 launches
```

Design trace:

```text
$ node --test test/js/ extensions/bp3-pi/test/
# tests 61  pass 61  fail 0   duration_ms 1840
$ scripts/record-transcripts --check
transcripts: 37 re-recorded, drift 0
```

```yaml
objective: run JS unit tests in seconds with one assertion style and a fake bp3 that cannot drift silently
prove by:
  - grep -L 'node:test' test/*.test.mjs extensions/bp3-pi/test/*.mjs   # 6 files today
  - time node --test over the unit-tier JS files
  - BP3_BIN pointed at a counting shim during the unit-tier run
  - edit one recorded transcript by hand, run scripts/record-transcripts --check
done when:
  - every JS test file imports node:test and node:assert/strict; no hand-rolled counters remain
  - unit-tier JS runs in under 3s and the counting shim records 0 real bp3 launches
  - the hand-edited transcript fails the check, naming the argv that drifted
  - pi-tree runs only in the slow tier, through run-suites
```

## Diagram

```text
real bp3 ──record──► test/fake-bp3/transcripts/*.jsonl ──replay──► fake-bp3 ──► dispatcher tests
   ▲                                                                       (unit tier)
   └── check-full: record again, diff against checked-in ──► drift = FAIL
```

## Pseudocode

```python
# test/fake-bp3/bp3 (executable)
def main(argv, stdin):
    row = TRANSCRIPTS.get((tuple(argv), normalize(stdin)))
    if row is None:
        die(f"fake-bp3: no transcript for {argv}", code=97)   # loud, never a guess
    write(stdout, row.stdout); exit(row.exit)

# scripts/record-transcripts --check
for case in CASES:                              # the argv list the tests use
    fresh = run_real_bp3(case, in_temp_repo())
    assert normalize(fresh) == checked_in[case], f"drift: {case.argv}"
```

| Field | Value |
|---|---|
| Intent | fast, uniform JS tests whose fake cannot lie about the CLI |
| Lane | standard |
| Output | JS tests ported to node:test; `test/fake-bp3/`; `scripts/record-transcripts`; transcripts |
| Acceptance | goal block above; fails today (mixed styles, 22s real launches) |
| Depends on | seam.2 (listRuns stops blocking before its tests are recorded) |
| Tests | known cases: dispatcher and workflow logic against fake-bp3; property-based: none, by decision: fake replay is deterministic over a fixed argv set; fixture: the transcript drift check in check-full |

## Prose

The five induct workflow tests already run against a mock host in
0.16s total. They need only the style port. The bp3-pi extension
tests are the expensive ones because they launch the real binary
and git.

Transcripts must be normalized before comparison: run-ids,
timestamps, temp paths and SHAs vary per run. The normalizer
replaces them with stable placeholders, and it is the part most
likely to hide drift, so the hand-edit acceptance check targets it.

A fake that answers an argv it has never seen would hide drift, so
it exits 97 instead. A missing transcript is a loud failure that
tells the author to record one.
