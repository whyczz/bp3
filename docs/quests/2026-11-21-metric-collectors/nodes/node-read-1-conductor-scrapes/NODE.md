---
date: 2026-11-21
quest: ../../QUEST.md
node: read.1
status: proposed
---

# read.1 - conductor-scrapes: the conductor scrapes after each grade (skill node)

## TL;DR

`induct` and `induct-inline` run `bp3 q <quest> metrics scrape`
right after casting a grade verdict, and report a `mismatched` grade
instead of hiding it. Grader briefs name the node id and the commit
SHA, spelled as `bp3 q` spells them. `using-bp3`, CLAUDE.md and
AGENTS.md name `metrics r`, `metrics scrape` and the new GENERATED
`metrics.jsonl`.

## Acceptance gates

Observed today:

```text
$ git grep -n 'metrics scrape' skills/ CLAUDE.md AGENTS.md      # rc=1, no hits (2026-11-21)
```

Design trace:

```text
$ ./test/skills.sh
skills tests: ok (<n + new> assertions)    # new: induct and induct-inline say "metrics scrape" after the grade cast;
                                            # their grader brief names the node id and the SHA; using-bp3 lists metrics r;
                                            # CLAUDE.md = AGENTS.md section names metrics.jsonl as GENERATED;
                                            # renders in .claude, .pi, .agents match their sources
```

```yaml
objective: conductors collect cost as they go, and every reader knows metrics.jsonl is generated
prove by:
  - test/skills.sh new assertions (render and install checked with BP3_COMPLETIONS_DIR in scratch)
  - make check-full
done when:
  - each assertion above fails on today's skills and passes after
  - the renders under .claude, .pi and .agents are regenerated from the sources, not hand-edited
```

## Diagram

```text
grader returns verdict -> conductor casts e grade -> conductor runs metrics scrape
                                                        | mismatched -> report it; never blocks the land
                                                        v
                                                 next node
```

## Pseudocode

```python
def after_grade(quest, node, verdict):
    cast("grade", verdict)
    out = bp3_q(quest, "metrics", "scrape")
    if out["nodes"][node]["mismatched"]: report(f"cost mismatch on {node}: harness report and transcript disagree")
    # scraping is evidence, not a gate: a failed scrape never changes the verdict or blocks land
```

## Tables

| Field | Value |
|---|---|
| Intent | metrics arrive without anyone remembering to grep |
| Lane | standard (skill change, quest step 6.6) |
| Output | `skills/induct/SKILL.md`, `skills/induct-inline/SKILL.md`, `skills/using-bp3/SKILL.md`, renders, CLAUDE.md, AGENTS.md, `test/skills.sh` |
| Acceptance | the assertions above; none hold today |
| Depends on | derive.1 - node-cost |

## Prose

This is a separate node because skills are how children behave
(quest skill, step 6.6). A conductor that scrapes is a behavior
change and gets the same gate as code.

The scrape is evidence, never a gate. A mismatch is news about the
scraper or the harness, not about the work, so it never changes the
verdict.

Open question 1, a `SubagentStop` hook that scrapes on its own,
would make this rule unnecessary. It stays open until this node has
run on a real quest.
