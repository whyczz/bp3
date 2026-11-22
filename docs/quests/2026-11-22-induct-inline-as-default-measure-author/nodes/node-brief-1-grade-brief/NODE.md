---
date: 2026-11-22
quest: ../../QUEST.md
node: brief.1
status: proposed
---

# brief.1 - grade-brief: bp3 renders the grader's cold brief

## TL;DR

`bp3 q <quest> n <node> brief [--desk <path>]` prints the cold brief
for a handed-off node, built from the bound commit alone. It holds the
join line (node id and sha7, which the scrape matches), fixed grader
rules, a read-first list, the NODE.md Acceptance gates section verbatim,
the previous round's commit and diff range (from cycle 2, no reason
text), `GRADING.md` verbatim, and the verdict shape. No text the author
typed reaches it: the only caller input is a validated `--desk` path.
The author passes it on and no longer writes it.
`Brief.render` is pure, so brief.2 can render it again.

## Acceptance gates

Observed today:

```text
$ bp3 q 2026-11-21-pi-metrics n node-reader-1-pi-session brief
{"ok":false,"error":{"code":"E_USAGE",...}}
$ ls GRADING.md
ls: GRADING.md: No such file or directory
```

Design trace (test/g.sh fixture quest q1, node nd handed off at abc1234…):

```text
$ bp3 q q1 n nd brief --desk /d
{"ok":true,"quest":"q1","node":"nd","cycle":1,"commit":"abc1234…","brief":"Grade nd at abc1234 (full SHA abc1234…) in quest q1, cycle 1.\n…"}
  brief lines, in order:
    Grade nd at abc1234 (full SHA …) in quest q1, cycle 1.
    You are a fresh, independent grader. You did not write this commit. …
    Rules: no edits to tracked files, no commits, no `bp3 q` calls; experiments in a fresh mktemp -d; git status --short empty at the end;
           an edit to GRADING.md, CONSTRAINTS.md or this node's Acceptance gates is owner-class unless the node's Output names the file
    Desk: /d (check `git rev-parse HEAD` prints abc1234…)
    Read first: docs/quests/q1/nodes/nd/NODE.md, docs/quests/q1/QUEST.md, CLAUDE.md / AGENTS.md / CONSTRAINTS.md (those present), git show abc1234
    Acceptance gates (NODE.md at abc1234): <the section, verbatim>
    Repo grading rules (GRADING.md at abc1234): <verbatim>, or "No GRADING.md: run the repo's documented test gate and name it."
    Final message, exactly this shape: VERDICT / MECHANICAL / GATE / FINDINGS / CHECKED / NOT CHECKED
cycle 2 (after a needs_fix on 1111111; its --reason is never shown):
    Previous round: cycle 1 graded 1111111 needs_fix. Re-judge the gates in full; the change since is git diff 1111111..2222222.
    Other nodes' commits in that range: 3333333 (nd2), or none.
nd in todo -> {"ok":false,"error":{"code":"E_NOT_HANDED_OFF","facts":{"state":"todo","legal_edges":["handoff",…]}}}
no --desk -> no Desk: line; same text otherwise
--desk relative, missing, or holding a newline -> E_USAGE, nothing rendered
```

```yaml
objective: a grader brief comes from bp3 and the bound commit, never from the author
prove by:
  - test/unit/test_brief.ml: Brief.render known cases (cycle 1, cycle 2 with another node's commit, no GRADING.md, no Acceptance gates section)
  - test/g.sh: the verb on a fixture quest (JSON shape, Desk line, E_NOT_HANDED_OFF in todo and approved, E_USAGE for a bad --desk, reads the commit, not the working tree)
  - test/g.sh: a needs_fix cast with --reason "SENTINEL-REASON" -> the cycle-2 brief does not contain SENTINEL-REASON
  - make check-full
done when: the cases pass, and a brief rendered for this quest's own handed-off node matches its NODE.md and GRADING.md at the bound commit
```

## Diagram

```text
bp3 q q n nd brief [--desk d]
   │  state must be handed_off (bound commit)
   ├─ git show <sha>:docs/quests/q/nodes/nd/NODE.md ──> "## Acceptance gates" section
   ├─ git show <sha>:GRADING.md (optional)
   ├─ node ledger ──> cycle, previous needs_fix commit when cycle > 1 (never its reason)
   ├─ --desk ──> absolute, existing dir, one line, or E_USAGE
   ├─ quest ledgers ──> other nodes' bound commits in <prev>..<sha>
   └─ Brief.render (pure) ──> {"ok":true, …, "brief": text}
```

## Pseudocode

```python
def inputs(quest, node, upto):          # shared: the verb (upto = the bound handoff) and brief.2's scrape
    cycle, commit = handoff_at(quest, node, upto)
    prev = last_needs_fix_commit(quest, node, before=upto)
    others = other_bound_commits(quest, node, prev, commit, before=upto)   # (sha, node) inside prev..commit
    return cycle, commit, git_show(commit, node_md_path(quest, node)), git_show_opt(commit, "GRADING.md"), prev, others

def render(quest, node, cycle, commit, node_md, grading, prev, others, desk=None):   # pure
    parts = [f"Grade {node} at {commit[:7]} (full SHA {commit}) in quest {quest}, cycle {cycle}.",
             PREAMBLE, RULES]
    if desk: parts.append(f"Desk: {desk} (check `git rev-parse HEAD` prints {commit})")
    parts.append(read_first(quest, node, commit))
    parts.append("Acceptance gates (NODE.md at %s):\n%s" % (commit[:7], section(node_md, "Acceptance gates") or "(none: a finding)"))
    if prev: parts.append(previous_round(prev, commit, others))     # prev = the last needs_fix's commit; no reason text
    parts.append(grading_part(grading, commit))                     # verbatim, or the "No GRADING.md" line
    parts.append(VERDICT_SHAPE)
    return "\n\n".join(parts)
```

## Tables

| Field | Value |
|---|---|
| Intent | the brief is data bp3 owns; the author passes it on and doesn't write it |
| Lane | standard |
| Output | `src/quest/names.ml` (new: the `brief` verb, `--desk`, the refusal code), `src/quest/store.ml` (`brief` in `reserved_slugs`), `src/quest/brief.ml` (new: `Brief.render` pure, `Brief.inputs` shared with brief.2), `src/quest/main.ml` (verb, help), `test/unit/test_brief.ml`, `test/unit/dune`, `test/g.sh`, `GRADING.md` (new), `CLAUDE.md` and `AGENTS.md` (one Commands line) |
| Acceptance | the verb answers JSON with the brief; fails today (`E_USAGE`) |
| Depends on | none |
| Must not touch | `src/quest/claude_tx.ml`, `src/quest/metrics*.ml`, `test/metrics.sh` (measure.1's files) |

| Brief part | Source |
|---|---|
| join line | quest, node, cycle, bound commit (the scrape's join: node id and sha7) |
| rules, preamble, verdict shape | fixed text in `Brief` |
| Acceptance gates | NODE.md at the bound commit, from its `## Acceptance gates` heading to the next `## ` |
| previous round | the node ledger's last `needs_fix` grade line: the commit it judged, never its `--reason` (the author-conductor typed it) |
| other nodes' commits | the quest's node ledgers: bound commits of other nodes inside `<prev>..<sha>` |
| repo rules | `GRADING.md` at the bound commit, verbatim |
| Desk line | `--desk`, the only input from the caller: an absolute path to an existing directory, one line, else `E_USAGE` |

`GRADING.md` (bp3's, new): the gate (`make check-full`, quote its rc and
last lines), plus the rules this repo's hand-written briefs carried:
build with `dune build --root .`; never `rm -rf` a variable path; never
`bp3 init` or `bp3 skills install` unless `BP3_COMPLETIONS_DIR` points at
a fresh scratch dir; never `metrics scrape` a real quest; and "a finding
is a false claim, a broken gate, or a test that can't fail".

## Prose

Today the author writes every grader brief by hand. The briefs have
been good, but each one is a place where the author could say "look
here, not there". CONTEXT.md:104 says reviewers shouldn't be told who
wrote the code. This goes a step further: the author can't word the
brief at all. Everything the grader judges against was written before
the commit (NODE.md's gates, framed and approved) or is a fact on the
ledger.

The author could still change NODE.md's gates or `GRADING.md` inside
the commit. The brief reads both at the bound commit, as written, and
its fixed rules tell the grader that such an edit is owner-class unless
the node's Output names the file. The grader checks with `git diff`.

The previous-round part holds only engine facts: the commit the last
`needs_fix` judged, and the diff range since. The `--reason` on that
line is left out on purpose (red-ink round 2, owner: "A"). In inline
mode the author-conductor typed it, so quoting it would hand the pen
back ("only re-check row 3"). The cycle-2 grader re-judges the gates in
full, as rounds do today. A real delta brief, one that quotes the
previous grader's own output, is the fast-grader icebox's job. Listing
other nodes' commits inside the range matters once grades run in the
background (skills.1): a fix can sit on top of another node's commit,
and the grader should judge only its own node's change.

`--desk` is the one caller input, and brief.2's comparison skips its
line, so it must not be able to carry steering text. It must be an
absolute path to an existing directory, on one line, or the verb
refuses with `E_USAGE`.

Every new spelling lives once, in `src/quest/names.ml` (red-ink round 6,
owner: "constants in the BP3 binary, the skills stay where they are").
The dispatch, the help text and the verdict use `Names.*`, never a
literal. A rename edits that file and seds the skills. `brief` joins
`Store.reserved_slugs`, so no node can be named after the verb. Moving
the older verbs there is `docs/icebox/2026-11-22-names-constants.md`.

Outside `handed_off` the verb refuses with a new code,
`E_NOT_HANDED_OFF`, with facts `{state, legal_edges}` (red-ink round 6,
owner: "A"). `E_ILLEGAL_EDGE` would say an edge was tried, and a brief
is a read. "No bound commit" would be false, because a node back in
todo after a `needs_fix` still holds its old bound commit. The
precondition is the state.

## Tests

Known cases: the trace above. Rendering reads git, not the working
tree: g.sh edits NODE.md in the working tree after handoff, and the
brief still shows the committed text. Property-based: for generated
NODE.md text, the rendered gates part equals the section, and the
first line always names the node id and `commit[:7]`.

## Build notes (2026-11-22)

- `src/quest/names.ml` (new): `verb_brief`, `flag_desk`,
  `e_not_handed_off`. The dispatch, the help line and the refusal use
  them; `Store.reserved_slugs` gains `Names.verb_brief`.
- `src/quest/brief.ml` (new): `section`, `render` (pure) and `inputs`
  (ledgers and git as of a stamp; `~upto:None` for the verb).
  The previous round is the last grade or verify line that sent the node
  to todo or blocked, and its commit; the reason is never read. Other
  nodes' commits are their handoff commits inside `git rev-list
  <prev>..<commit>`.
- `src/quest/main.ml`: `do_brief`, dispatched as `q <quest> n <node>
  brief [--desk <path>]` ahead of the edge door; one help line in
  `help_q`.
- `GRADING.md` (new): the gate and the rules the hand-written briefs
  carried, plus "a check must be seen to fail on the bug it guards".
- CLAUDE.md and AGENTS.md: one Commands line each (still identical).
- Tests:
  - `test/unit/test_brief.ml`: 5 cases and 1 law, 300 runs;
  - `test/g.sh` brief block: JSON shape, join line, gates verbatim
    (the next section left out), GRADING.md, the Desk line, three bad
    desks (`E_USAGE`), the working tree ignored, todo and approved
    refused (`E_NOT_HANDED_OFF`), the cycle-2 range and other node,
    `SENTINEL-REASON` absent, and `brief` reserved.
  The g.sh block sits before the version-guard section, which stamps
  the fixture repo MAJOR-ahead, and stages the files earlier sections
  leave untracked (a handoff needs a clean tree).
- Mutants, each red then restored (`cmp` against the kept copy):
  - desk validation off: g.sh "bad --desk accepted: rel";
  - others never listed: g.sh "brief others";
  - state check off: g.sh "brief in approved accepted";
  - `section` past the next heading: test_brief's law fails.
- `make check-full`: rc 0, 28/28 suites, 37 s.
- The order changed: brief.1 went first (first in `ready`). The quest's
  first stacked land is therefore brief.1's, cast after measure.1's
  handoff, so the probe runs before measure.1's handoff.
- Cycle 2 (the grader's mechanical fix). The working-tree probe could not
  fail: the edit landed after `## Diagram`, outside the gates, and the
  probe never checked the brief was non-empty. It now rewrites NODE.md
  with `EDITED-AFTER-HANDOFF` inside the gates and asserts `GATE-ROW-ONE`
  first. Planted mutant (`Brief.inputs` reads the working tree instead
  of `git show`): g.sh red, "brief read the working tree"; restored
  (`cmp`), g.sh green, `make check` rc 0.
