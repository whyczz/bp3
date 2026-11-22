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

## Build notes (2026-11-22)

- `Brief.is_verbatim prompt inputs`: the comparison is exact after the
  render. The one caller part, the Desk paragraph, is read back only in
  its rendered form and place (paragraph 4, one line, naming the bound
  commit). The brief is rendered again with that desk and compared
  whole, so a second Desk paragraph or any added line reads as edited.
  The one slack is trailing newlines.
- `Metrics_io.brief_check`: a joined grade that is written (checked,
  unchecked, self_checked) renders its brief with
  `Brief.inputs ~upto:(Some handed_at)` and counts `brief_verbatim` or
  `brief_edited`. Mismatched, ambiguous and owner-graded grades count
  neither. The counts sit beside the buckets in `Metrics.tally`;
  `buckets_add_up` and the exit code are unchanged.
- Found while building, fixed in `Brief.inputs`: the previous round was
  cut by stamp (`e_ts <= upto`). A needs_fix cast in the same second as
  the handoff then joined that round's render and read as edited.
  `Brief.before_handoff` cuts in ledger order at the handoff that bound
  the commit. Real grades take minutes, but stamps are whole seconds.
- Tests:
  - `test_brief.ml`: `case_is_verbatim_takes_the_render_and_nothing_else`
    (desk and no desk, trailing newline, an added line, a second Desk
    paragraph, a Desk naming another commit, a dropped previous round),
    `law_is_verbatim_exact` (300 runs: any absolute one-line desk is
    verbatim; any added paragraph is edited), and
    `case_previous_round_is_cut_at_the_bound_handoff` (the same-second
    needs_fix);
  - metrics.sh q4, 72 assertions: va verbatim with a desk; vb one added
    line → edited, 8 samples still written; vc both rounds verbatim,
    each rendered as of its own handoff; vd owner → neither; scrape
    rc 0.
- Mutants, each red then restored (`cmp`):
  - always verbatim: unit case, law, metrics.sh vb;
  - never verbatim: unit case, law, metrics.sh va;
  - desk never read back: unit case, law, metrics.sh va;
  - no cut at the bound handoff: the same-second unit case. metrics.sh vc
    catches it only when the cast shares the handoff's second, which is
    timing luck, so the unit case is the guard.
- Dogfood:
  - this quest's scrape reads 5 of 5 grades `brief_verbatim`. Every
    Agent prompt was copied from `bp3 … brief` by hand, and none slipped;
  - pi-metrics in the scratch clone (hand-written briefs) reads 3 of 3
    `brief_edited`, as the table says for old quests.
