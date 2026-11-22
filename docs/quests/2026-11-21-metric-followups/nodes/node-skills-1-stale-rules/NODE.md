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

## Build notes (2026-11-21)

- induct-yolo Rules match induct's bullet: `bp3 q` is the only edge
  writer, and the one other write is induct step 5's `metrics scrape`,
  which moves no edge.
- using-bp3 step 4 lists edges by state as `Store.legal_edges` gives
  them, cast through `n <node> e`. It also names the combined
  `--verify-verdict`, says `resume` is human-only and `delete` is the
  owner's call, and says `--mechanical` never blocks.
- Wider than framed, same intent ("the skills describe the engine that
  exists"). using-bp3 steps 1–2 named `q show`, `q list` and
  `q create --engine`, which all answer `E_USAGE` today (probed), and
  claimed quest create scaffolds files into the working tree, when it
  writes to `bp3/quest/` and `bp3/node/` branches. It pointed at a
  `bp3-writer` skill that doesn't exist, and its Rules named a "fix edge"
  that `Store.legal_edges` doesn't have. All fixed.
- test/skills.sh: `gate_grep` uses `grep -h`, so the filter sees lines,
  not file names. Planted in a scratch `induct-grade.js`: a plain
  `make check` line passes, and a line that grades with plain
  `make check` still fails. The old pipeline flags the plain line
  (observed). New assertions cover the sources and every render.
- Fails today: the new skills.sh run against master's tree (dd67808)
  fails at `metrics.jsonl samples and moves no edge` in induct-yolo.
- Renders: `bp3 skills install --harness=all` with `BP3_COMPLETIONS_DIR`
  in scratch. The global `_bp3` was untouched (Nov 20 16:26 before and
  after).
- Left: CLAUDE.md = AGENTS.md still say "A reviewer who refactors takes
  a fix edge". It isn't a skill, so it's out of this node.

## Round 2 (2026-11-21)

The cycle-1 grader found `needs_fix`, mechanical, with three findings,
all in using-bp3:
- Step 5 claimed `handoff` exempts quest folders from the dirty check
  and checks commit ancestry. It does neither (probed).
- Step 3 said dependencies live in `fsm.yaml`. They're on the ledger's
  create line, and node dependencies were left out.
- Step 4 said only judgment moves need `--reason`. Every move does,
  `d` included.

Applied the grader's named text, plus its optional note that the engine
requires a human only to delete a blocked node, and dropped `fsm.yaml`
from step 1. Added the skills.sh guard it named against the four stale
phrases, then re-rendered.

## Round 3 (2026-11-21)

The cycle-2 grader found `needs_fix`, mechanical, with three findings:
- `--reason` isn't the move's commit message. It goes on the ledger
  line, and the commit says `bp3: <node>` (probed). This text predated
  the quest; neither earlier round caught it.
- Dependencies are satisfied by `deleted` as well as `landed`.
- The planted-line case passed one file to grep, and grep prints no file
  name for a single file, so the old pipeline passed it too. The case
  couldn't fail.

Applied the grader's text, with the quest-dependency clause made exact
from `Store.dep_satisfied`: the quest has nodes, all landed or deleted,
and isn't deleted itself. Also named the `dep` verb. The planted case
now adds `/dev/null` as a second file, and the old pipeline flags the
plain line (1 hit, against 0 for the new one). Added a guard for
"move's commit message".
