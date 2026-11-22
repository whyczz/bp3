---
date: 2026-11-21
quest: ../../QUEST.md
node: scrape.1
status: proposed
---

# scrape.1 - pi-grades: the scrape measures pi graders

## TL;DR

`bp3 q <quest> metrics scrape` reads pi sessions as well as Claude Code
subagent transcripts. The grade join stays as it is: a transcript names
the node id and the commit's first 7 characters in its first prompt,
inside [handoff, grade+1s). It now runs over Claude and pi transcripts
together, so a grade two transcripts claim is `ambiguous` wherever they
came from. A pi grade that passes its self-check is written, as
`self_checked`; one that fails is `mismatched`, which writes nothing and
exits 1.

## Acceptance gates

Observed today:

```text
$ bp3 q 2026-11-21-metric-followups metrics scrape --pi-dir /nonexistent
{"ok":false,"code":"E_USAGE","detail":"unknown metrics scrape argument: --pi-dir"}
```

Design trace (test/metrics.sh, synthetic pi sessions):

```text
q3/pa: handoff, then a pi session (first prompt "Grade pa at <sha7>.") inside the window, then grade
  scrape --claude-dir <empty> --pi-dir <dir> -> pa {grades 1, self_checked 1}, 7 grade.* samples, run "pi:<id>", model gpt-6.1-sol
q3/pb: one pi session and one Claude transcript both name pb -> pb.ambiguous 1, nothing written
q3/pc: a pi session whose total is off by one -> pc.mismatched 1, nothing written, scrape exit 1
default dirs: ~/.pi/agent/sessions/--<repo>-- and --<repo>-.bp3-worktrees-<slug>-- scanned; a sibling repo's never
dogfood: bp3 q 2026-11-21-pi-metrics metrics scrape -> every grade of this quest self_checked, run pi:*
```

```yaml
objective: a pi grade is measured like a Claude one, and never claimed as more checked than it is
prove by:
  - test/metrics.sh pi cases above
  - test/unit: tally law with self_checked
  - the dogfood scrape of this quest (real pi sessions)
  - make check-full
done when: the fixture cases pass, and this quest's own grades read back self_checked with run pi:*
```

## Diagram

```text
grade edges ──┐
claude dirs ──┼─> candidates = claude txs ∪ pi txs ─> names node+sha7, first_ts in window?
pi dirs ──────┘                                          0 -> owner_graded | 2+ -> ambiguous | 1 ->
                                    claude: report? checks -> checked/mismatched : unchecked
                                    pi:     self_checks    -> self_checked       : mismatched
```

## Pseudocode

```python
def grade_pass(q, node, edges, claude_txs, pi_txs):
    for span in grade_spans(edges):
        cands = [t for t in claude_txs + pi_txs if names_grade(t, node, span.sha) and in_window(t, span)]
        if not cands: tally.owner_graded += 1
        elif len(cands) > 1: tally.ambiguous += 1
        elif is_pi(cands[0]):
            if Pi_tx.self_checks(cands[0]): write(samples(cands[0], run="pi:" + id)); tally.self_checked += 1
            else: tally.mismatched += 1
        else: ...                                     # Claude path unchanged

def pi_default_dirs(repo):    # pi's rule: drop the leading /, then / \ : -> -
    return [d for d in ls(HOME/.pi/agent/sessions)
            if d in (slug(repo), ) or d.startswith(slug(repo)[:-2] + "-.bp3-worktrees-")]   # logical and real paths
```

## Tables

| Field | Value |
|---|---|
| Intent | pi grader sessions reach the sink through the same join as Claude's |
| Lane | standard |
| Output | `src/quest/metrics_io.ml` (pi dirs, join, flag), `src/quest/metrics.ml` (tally `self_checked`), `src/quest/main.ml` (help), `test/metrics.sh`, unit tests |
| Acceptance | `--pi-dir` fixture cases; fails today (E_USAGE) |
| Depends on | reader.1 |

| Flag | Meaning |
|---|---|
| `--claude-dir <dir>` | unchanged: replaces the default Claude dirs |
| `--pi-dir <dir>` | new, repeatable: replaces the default pi dirs |
| neither | both default dir sets |

## Prose

The join is harness-neutral on purpose. A grade is a grade, and the
first prompt naming the node and commit is a rule any grader runtime
can follow. The metrics stay the same `grade.*` names under the same
owning collector (one owner per metric), and the `run` prefix and the
`model` field say which harness and model did the work. Rollups count
pi and Claude grades together; a per-model split can come later from
the same samples.

Edge cases:
- A pi grader whose `--session-id` the conductor reused for a second
  grade puts two grades in one file. The first prompt names only the
  first grade, so the second is `owner_graded`. skills.1 says to mint a
  fresh id per grade.
- pi's dir name keeps dots (`-.bp3-worktrees-`), where Claude's turns
  them into dashes. The two slug rules stay separate functions.
- `/var` and `/private/var`: logical and real paths both, as the Claude
  dirs do.

## Tests

Known cases: the trace above (self_checked, ambiguous across harnesses,
mismatched), plus default dirs and a sibling repo left out.
Property-based: the tally law gains `self_checked`, and the unit
generator for tallies covers it.

## Build notes (2026-11-21)

- `Metrics_io.grader` is `Claude of path * Claude_tx.tx | Pi of path *
  Pi_tx.tx`. `joins` applies the shared rules, which now live in
  `Claude_tx.prompt_names_grade` and `Claude_tx.span_in_window`
  (`names_grade` and `in_window` call them). `grade_pass` filters every
  candidate: one Claude hit is checked as before; one pi hit is
  `self_checked` if `Pi_tx.self_checks` passes, else `mismatched`; two or
  more are `ambiguous`, whatever harness they came from.
- `pi_slug` and `default_pi_dirs`: the repo's dir and
  `--<repo>-.bp3-worktrees-<slug>--`, logical and real paths. A
  `-.bp3-worktreesX--` dir and a sibling repo's dir are both left out
  (tested). `pi_run_of_path` takes the header id, else the id in the
  file name. The scrape JSON gains `pi_dirs`; `--pi-dir` and
  `--claude-dir` each replace only their own default set.
- `Metrics.tally.self_checked` is counted by `buckets_add_up` and
  `tally_json`.
- test/metrics.sh (60 assertions), q3:
  - pa is self_checked with 7 samples (`run pi:grade-pa-1`, model
    gpt-6.1-sol, tool_calls 1, tokens 220/15/40, context_end 165, wall
    0.7);
  - pb is claimed by both harnesses and reads ambiguous;
  - pc has a total off by one, reads mismatched, and the scrape exits 1;
  - the default pi dirs case passes.
- Mutants:
  - writing pi grades without their self-check fails metrics.sh
    ("a bad total exits 1: want 1, got 0");
  - dropping pi from the candidates fails it too.
  An earlier run of the second mutant didn't compile (an unused
  variable), so the run reported was redone with one that compiles.
- Dogfood: a scrape of this quest finds reader.1's real pi grader
  session (`pi:grade-node-reader-1-pi-session-c1-1795319246`) as
  self_checked. Wall 150.563 s (152 s from outside), 20 tool calls,
  tokens 63,918 / 2,979 / 602,240 / 0, context_end 49,500. pi's RPC
  `get_session_stats` on that file gives the same calls and tokens. pi's
  dollar cost for the grade: $0.218.
- Also here, from reader.1's grader (minor): test_pi_tx gains the
  absent-usage case its Tests section named.
