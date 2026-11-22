---
date: 2026-11-21
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - pi-grader: induct-inline can grade with pi (skill node)

## TL;DR

induct-inline's grade section names a second grader runtime: one
headless `pi -p` per grade, run from the desk with read and bash tools
only, a fresh `--session-id` each time, and the same cold brief. The
printed text is the verdict, cast as returned, and the scrape reads the
session back. This writes down what the quest did by hand from
reader.1 on.

## Acceptance gates

Observed today:

```text
$ grep -n 'pi -p' skills/induct-inline/SKILL.md     # rc=1
```

Design trace:

```text
$ ./test/skills.sh
  induct-inline (source and every render) names: pi -p --tools read,bash --session-id <fresh id>;
  "one session per grade"; the first prompt names the node id and the commit's first 7 characters;
  the verdict is the printed text, cast as returned
```

```yaml
objective: a conductor can run a pi grader from the skill alone, and get it measured
prove by:
  - test/skills.sh new assertions (render and install with BP3_COMPLETIONS_DIR in scratch)
  - make check-full
done when: the assertions pass and fail on master's skill text
```

## Diagram

```text
induct-inline grade:
  Agent tool / agent()  -> fresh subagent grader            (today)
  pi                    -> pi -p --tools read,bash --session-id <id> "<cold brief>"   (new)
  neither               -> the owner judges                  (today)
```

## Pseudocode

```python
def grade(node, sha):
    brief = cold_brief(node, sha)        # names node id and sha[:7] first; make check-full; CONSTRAINTS.md
    if runtime == "pi":
        verdict = run(["pi", "-p", "--tools", "read,bash", "--session-id", fresh_id(), brief], cwd=desk)
    cast(verdict, bound=sha); scrape()
```

## Tables

| Field | Value |
|---|---|
| Intent | the skill says how this quest's grades ran |
| Lane | micro (skill node: its own gate, quest skill step 6.6) |
| Output | `skills/induct-inline/SKILL.md`, renders, `test/skills.sh` |
| Acceptance | test/skills.sh assertions; fail today |
| Depends on | scrape.1 (the skill promises the scrape reads pi) |

## Prose

The rule that the author never judges holds whatever the runtime: the
pi grader is a fresh process with no authoring context. `--tools
read,bash` keeps it from editing. It can still write through bash, so
the brief keeps the "no edits, no commits, no bp3 q calls" line, and
the conductor checks that the desk is clean before casting.

## Build notes (2026-11-21)

- induct-inline's grade section gains a **pi grader** bullet: the
  command, the same cold brief whose first line names the node id and
  sha7, `--tools read,bash`, a clean desk before casting, one session per
  grade with a fresh `--session-id`, the printed text cast as returned,
  and `self_checked` in the scrape. The "how it differs" table names
  both grader runtimes.
- test/skills.sh: 5 new assertions × 4 dirs (source and renders). Each
  pattern is absent from master's induct-inline (checked one by one).
  261 assertions in total.
- Renders: `bp3 skills install --harness=all` with `BP3_COMPLETIONS_DIR`
  in scratch. The global `_bp3` was untouched (Nov 20 16:26 before and
  after).
- Also here, from scrape.1's grader (minor): scrape.1's Tests section no
  longer claims a tally generator.
- This quest followed the bullet by hand since reader.1: reader.1's and
  scrape.1's grades were headless pi runs (152 s and 110 s).
