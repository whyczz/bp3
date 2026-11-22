---
date: 2026-11-21
quest: ../../QUEST.md
node: usage.1
status: proposed
---

# usage.1 - author-usage: an author window bp3 can't fully read writes nothing

## TL;DR

A grade whose transcript holds a usage-less line is `mismatched` and
writes nothing (`Claude_tx.checks`). An author window gets no such
check: `parse_session` counts `s_bad_usage`, and nothing reads it, so
an undercounted window is written as if it were whole. After this node,
a window holding a bad usage line writes no samples, lands in a new
`author_bad_usage` bucket, and the scrape exits 1.

## Acceptance gates

Observed today:

```text
$ git grep -n 's_bad_usage' src/quest/metrics_io.ml    # rc=1: the count is never read
```

Design trace:

```text
$ ./test/metrics.sh     # new fixture: q1/na's author session gains one assistant line inside the window with "usage" missing output_tokens
  scrape -> na tally {"handoffs":1,"authored":0,"author_bad_usage":1}, no author.* samples for that cycle, exit 1
  same line moved outside every window -> authored 1, exit 0
```

```yaml
objective: no author number is written from a window with an unreadable usage line
prove by:
  - test/metrics.sh fixture case above (in and out of the window)
  - test/unit/test_metrics.ml: parse_session keeps bad lines' timestamps; buckets_add_up holds with author_bad_usage
  - make check-full
done when: the in-window case writes nothing and exits 1, the out-of-window case writes and exits 0
```

## Diagram

```text
session.jsonl -> parse_session -> s_msgs (good lines) + s_bad_at (timestamps of usage-less lines)
                                       |
author_spans -> windows -> assign (first window holding a line, for good and bad lines alike)
                                       |
              bad lines in window > 0 ? -> author_bad_usage += 1, no samples
                                       : -> author.* samples, authored += 1
```

## Pseudocode

```python
def author_pass(q, edges, sessions):
    for node, span, claimed in windows(edges, sessions):
        if one(claimed):
            msgs, bad = assign(span, session)        # bad: usage-less lines first held by this window
            if bad:   tally.author_bad_usage += 1    # like a mismatched grade: never written
            elif not msgs: tally.author_missing += 1
            else:     write(author_samples(msgs)); tally.authored += 1

def buckets_add_up(t):
    return (t.authored + t.author_missing + t.author_ambiguous + t.author_bad_usage == t.handoffs
            and ...)                                 # grade side unchanged

exit_code = 1 if any(t.mismatched or t.author_bad_usage for t in tallies) else 0
```

## Tables

| Field | Value |
|---|---|
| Intent | the grade rule (unreadable means unwritten) applies to author windows |
| Lane | standard |
| Output | `src/quest/claude_tx.ml` (`s_bad_at`), `src/quest/metrics.ml` (tally field, law, `tally_json`), `src/quest/metrics_io.ml` (`author_pass`, `scrape_view` exit), tests |
| Acceptance | the in-window fixture exits 1 with no samples; fails today (it writes and exits 0) |
| Depends on | none |

| Window holds | Today | After |
|---|---|---|
| good lines only | written, `authored` | same |
| a bad line, any number of good | written as whole, `authored` | nothing written, `author_bad_usage`, exit 1 |
| no lines | `author_missing` | same |

## Prose

The scrape's rule for grades is that a number bp3 can't check is never
written: `checks cut r = cut.bad_usage = 0 && agrees ...`. Author
windows have no harness report to check against, so the bad-line count
is the only check they can have. Real data so far has no bad lines
(scratch-clone scrapes, 2026-11-21), so this guards against a harness
format change, not a known undercount.

Edge cases: a bad line before the window's start or after its handoff
belongs to no window and changes nothing. `assign` already hands each
good line to the first window that holds it; bad lines follow the same
rule, so one line can't fail two windows.

## Tests

Known cases: the in-window and out-of-window fixture pair, and a unit
case for `parse_session` keeping a bad line's timestamp. Property-based:
the existing tally law gains the new bucket. The QCheck generator for
tallies adds `author_bad_usage`, and `buckets_add_up` must still hold
for every scrape.
