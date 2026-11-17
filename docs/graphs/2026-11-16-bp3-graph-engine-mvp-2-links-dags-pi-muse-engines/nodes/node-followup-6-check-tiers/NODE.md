---
date: 2026-11-17
graph: ../GRAPH.md
exp: followup.6
status: proposed
---

# followup.6 - check-tiers: test the change, not the world

## TL;DR

Owner ask (2026-11-17): the full `make check`
takes ~10 min (serial suites, wall-clock
harness fixtures, full OCaml rebuild), and
authors pay it every cycle. Split verification
into tiers: a fast tier for per-cycle work, a
change-scoped selector that runs only the
suites a diff touches, and the unchanged full
`make check` reserved for grade/land gates.
Explicit acceptance below; timings measured,
never asserted from hope.

## Demo (design trace)

```text
before: author cycle -> make check (all suites, ~10 min) -> handoff
after:  author cycle -> make check-changed (suites for this diff)
        grade/land   -> make check (full, unchanged)
        unsure path  -> fast tier (fail-safe, never "run nothing")
```

## Diagram

```text
changed paths ─► selector (path->suite table) ─► suites named by the diff
      │                                              │
      ├─ unknown path ─► check-fast (all non-wall-clock suites)
      └─ gate (grade/land) ─► make check (full, byte-identical target)
```

## Pseudocode

```python
SUITES = {  # path prefix -> suites; single source in Makefile/scripts
  "skills/": ["check-skills", "test/skills.sh", "workflow node tests"],
  "src/": ["dune build", "test/g.sh", "test/harness.sh(fast-safe parts)"],
  ".agents/workflows/ renders": ["bp3 skills check", "workflow node tests"],
  "test/": ["the changed suite itself"],
}
def check_changed(paths):
    suites = union(SUITES[p] for p in paths if matched(p)) or FAST_TIER
    return run(sorted(suites))   # unknown never means none
```

| Field | Value |
|---|---|
| Intent | verification cost proportional to the change; gates keep full rigor |
| Lane | standard |
| Output | `check-fast` + `check-changed` make targets, path->suite table, workflow/skill text naming the tiers |
| Depends on | followup.3 (final file layout; Makefile and tests renamed there first) |

## Acceptance

| Case | Expected |
|---|---|
| fast tier exists | `make check-fast` runs lint + skills checks + unit/workflow tests with zero wall-clock timer fixtures (no `harness.sh` sleep/watch cases); wall time measured and quoted in the run notes, target under 120s on this machine |
| full tier unchanged | `make check` target runs exactly today's suite list; a full run quoted green at this node's grade |
| selector maps skills | a diff touching only `skills/**` runs skills checks + workflow tests and does NOT run `test/harness.sh` (command list quoted) |
| selector maps src | a diff touching only `src/**` builds and runs the binary/unit suites for the touched area, not the skills suites |
| selector maps renders | a diff touching only `.agents/workflows/*.js` runs `bp3 skills check` + the matching `test/*.test.mjs`, nothing else |
| unknown path fails safe | a diff with an unmapped path (e.g. `docs/**` excluded by name, anything else) runs the fast tier, never zero suites; the chosen suites are printed before running |
| cycle discipline text | author-facing workflow/skill text says: per cycle run `check-changed` (or fast), full `make check` only when the record's acceptance names it or at handoff if the conductor asks; grade/land gates unchanged |
| no suite weakened | no existing test is deleted, skipped, or given a shorter timeout to make a tier pass; tier membership is by suite, listed in one table |
| regression | `make check` full green; selector fixtures cover the four mapping cases above |

## Acceptance test (goal block)

- **Objective:** a one-file change costs a
  one-suite verification, and gates lose nothing.
- **Prove by:** quoted suite lists per mapping
  case + measured fast-tier wall time + one
  full green `make check`.
- **Done when:** an author cycle in this graph
  runs check-changed end to end and the grade
  still sees a full check.

## Tests

Selector fixtures (path lists -> expected suite
lists); fast-tier suite-list assertion; one
timed fast run; one full `make check`.

## Context

Warden catalog row #8 (icebox
2026-11-13-session-log-mining): authors re-ran
the full wall-clock suite per cycle
(followup.3 author ~20 min). Owner: "the full
make check takes a while, is there a way to
test only the changes?" — this node is the
answer, with fail-safe defaults.
