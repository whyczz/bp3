---
date: 2026-11-21
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - stale-rules: the skills describe the engine that exists (skill node)

## TL;DR

Three stale spots. induct-yolo's Rules say "`bp3 q u` is the only
writer", but it runs induct's procedure, whose step 5 scrapes. using-bp3
step 4 lists a `cancel` edge that doesn't exist and never says a
`--mechanical` `needs_fix` never blocks. test/skills.sh's gate grep
matches its own file names (`induct-grade.js`, `induct-land.js`), so
any plain `make check` line in those files trips it, whatever the line
says.

## Acceptance gates

Observed today:

```text
$ grep -n 'only' skills/induct-yolo/SKILL.md | grep writer   # 139: "`bp3 q u` is the only"
$ grep -n 'cancel' skills/using-bp3/SKILL.md                 # 36: "`land`, `block`, `cancel`."
$ grep -n 'mechanical' skills/using-bp3/SKILL.md             # rc=1
```

Design trace:

```text
$ ./test/skills.sh
  induct-yolo Rules name the scrape as the one write that moves no edge (as induct's do)
  using-bp3 step 4 lists handoff, grade, verify, land, block, and resume/delete as human-only; names --mechanical
  no source skill names a `cancel` edge
  a planted `make check` line in a scratch copy of induct-grade.js that names no gate -> gate grep passes
    (today: fails, because the file name holds "grade")
  renders in .claude, .pi, .agents match their sources
```

```yaml
objective: skill text matches Store.legal_edges and induct's write rule, and the gate grep reads content only
prove by:
  - test/skills.sh new assertions (install checked with BP3_COMPLETIONS_DIR in scratch)
  - make check-full
done when: the new assertions pass, and the planted-line case fails on master's test
```

## Diagram

```text
skills/induct-yolo/SKILL.md  Rules   -> mirror induct's Rules bullet (scrape: one write, no edge)
skills/using-bp3/SKILL.md    step 4  -> edges from Store.legal_edges; --mechanical never blocks
test/skills.sh               gate grep -> grep -h (content only, no file names)
bp3 skills install           -> .claude, .pi, .agents renders
```

## Pseudocode

```python
edges = {"todo": ["handoff", "block", "delete"], "handed_off": ["grade", "verify", "block", "delete"],
         "approved": ["land", "block", "delete"], "blocked": ["resume", "delete"]}   # Store.legal_edges
gate_lines = [l for l in grep_h(r"make check([^-]|$)", skill_files)   # -h: the line, not "path:line"
              if re.search("grade|land|handoff|gate", l, re.I)]
assert not gate_lines
```

## Tables

| Field | Value |
|---|---|
| Intent | skills say what the engine does |
| Lane | micro (skill node: its own gate per the quest skill, step 6.6) |
| Output | `skills/induct-yolo/SKILL.md`, `skills/using-bp3/SKILL.md`, `test/skills.sh`, renders |
| Acceptance | test/skills.sh new assertions; the planted-line case fails today |
| Depends on | none |

## Prose

`cancel` was a quest-status word (`canceled`) that leaked into the edge
list. The real terminal move is `delete`, and it's human-only, like
`resume`. The `--mechanical` flag came with pure-grade (followup.5):
a named mechanical fix returns the node to todo at any cycle and never
blocks. using-bp3 is the skill that teaches single edges, so it should
say so.

The gate grep has a false positive: `grep -n` over several files
prefixes each hit with its path, and the paths hold "grade" and "land".
The fix is `-h`, so the filter sees only the line. A repo path holding
"gate" or "land" (for example `~/island/bp3`) would trip every hit today
for the same reason.

## Tests

Known cases: the assertions above, including the planted-line case in a
scratch copy. Property-based: omitted, since skill text has no input
space.
