---
date: 2026-11-22
quest: ../../QUEST.md
node: brief.2
status: proposed
---

# brief.2 - brief-check: the scrape says whether the brief was edited

## TL;DR

For every grade it joins (Claude or pi), the scrape renders the brief
again with `Brief.render`, using the state at that handoff, and compares
it with the grader's first prompt, setting the `Desk:` line aside. Equal
counts as `brief_verbatim`, anything else as `brief_edited`. Both are
evidence: the grade's samples are written either way.

## Acceptance gates

Observed today:

```text
$ grep -rn 'brief_verbatim\|brief_edited' src/ | wc -l
0
```

Design trace (test/metrics.sh, quest q4):

```text
q4/va: grader first prompt = Brief.render(...) with "Desk: /x"                 -> va {brief_verbatim 1}, grade samples written
q4/vb: grader first prompt = the render plus one line "focus on parse"         -> vb {brief_edited 1}, grade samples written
q4/vc: cycle 2: first prompt = the cycle-2 render (previous round included)    -> vc {brief_verbatim 1}
q4/vd: owner-graded (no transcript)                                            -> neither count
scrape exit unchanged: brief_edited never sets exit 1
```

```yaml
objective: a grade whose brief the author changed is visible in the scrape
prove by:
  - test/metrics.sh q4 cases above
  - test/unit: the comparison (Desk line aside, trailing newline tolerant, nothing else)
  - make check-full
done when: the cases pass, and this quest's own grades cast after brief.1 read brief_verbatim
```

## Diagram

```text
grade span (handoff h, grade g) + joined transcript t
   └─ state at h: cycle, previous needs_fix, other nodes' commits, NODE.md and GRADING.md at h.commit
        └─ Brief.render ──> r
             strip_desk(t.first_prompt) == strip_desk(r) ?  brief_verbatim += 1 : brief_edited += 1
```

## Pseudocode

```python
def brief_check(q, node, span, tx):
    r = Brief.render(q, node, *Brief.inputs(q, node, upto=span.handed_at), desk=None)   # the verb's own inputs
    same = strip_desk(tx.first_prompt).rstrip("\n") == strip_desk(r).rstrip("\n")
    return "brief_verbatim" if same else "brief_edited"
```

## Tables

| Field | Value |
|---|---|
| Intent | prove the brief was bp3's, without trusting the author's word |
| Lane | standard |
| Output | `src/quest/metrics_io.ml` (check in `grade_pass`), `src/quest/metrics.ml` (tally fields, `tally_json`), `test/metrics.sh`, unit tests |
| Acceptance | the tally fields exist and count; fail today (absent) |
| Depends on | brief.1 (`Brief.render`), measure.1 (the same files; serial avoids a merge) |

| Case | Result |
|---|---|
| prompt equals render, Desk line aside | `brief_verbatim` |
| any other difference, a single line included | `brief_edited` |
| no transcript (owner-graded) or ambiguous | neither |
| mismatched Claude grade or failed pi self-check | neither: nothing is written for it anyway |
| a grade cast before brief.1 existed | `brief_edited` (hand-written briefs); expected for old quests, and the readout says so |

## Prose

brief.1 takes the pen from the author, and this node checks that the
pen stayed taken. The comparison is exact on purpose. "Close enough"
would let one added sentence of steering through, and that sentence is
the whole risk.

The tally fields are counts beside the outcome buckets, not buckets.
A grade is still checked, self-checked or mismatched on its own terms,
and `buckets_add_up` doesn't change. The scrape's exit code doesn't
change either: like the rest of the scrape, this is evidence, and
whether `brief_edited` should ever block is the owner's Open question 3.

Re-rendering needs the state as it was at the handoff, not as it is
now: the cycle, the last `needs_fix` before it, and the commits other
nodes had bound by then. `Brief.render` takes all of these as
arguments, which is why brief.1 keeps it pure.

## Tests

Known cases: the trace above, plus a pi grader (the prompt is the `-p`
argument) and a Claude subagent (the Agent prompt). Property-based: for
generated briefs, a prompt equal to the render with any `Desk:` line
is verbatim, and inserting any non-empty line makes it edited.
