---
date: 2026-11-19
quest: ../../QUEST.md
node: grade.1
status: proposed
---

# grade.1 - narrow-brief: three jobs, a scoped verdict, role swap

## TL;DR

`induct-inline` gets the fast loop: the author hands off with the
receipt as the reason; one fresh grader runs three jobs (re-run the
receipt, one check the author missed, claims against evidence) in
about five minutes; `needs_fix` only for a failing acceptance row or a
proven bug; on `needs_fix` the grader writes the fix and the author
grades it. CLAUDE.md and AGENTS.md drop the "fix edge" that never
existed.

## Acceptance gates

Observed today:

```text
$ grep -c 'scripts/receipt' skills/induct-inline/SKILL.md
0
$ grep -n 'fix edge' CLAUDE.md
56:takes a fix edge and produces a new commit; verdicts always bind
$ grep -n '"handoff"; "grade"' src/quest/main.ml
185:  if not (List.mem edge ["handoff"; "grade"; "verify"; "land"; "block"; "resume"]) then
```

Design trace (one node, one round of fix):

```text
author:  commit a1 -> ./scripts/receipt (rc 0)
         e handoff --commit a1 --reason "<receipt>"
grader:  job 1 receipt rc 0, same red-first line
         job 2 "budget at exactly N s" -> probe red: over_budget fires early
         -> needs_fix (bug, repro attached); writes fix f1 + test, receipt rc 0
author:  e grade --verdict needs_fix --reason "<grader reason verbatim>"
         e handoff --commit f1 --reason "<grader's receipt>"
         grades f1 (it did not write f1): 3 jobs -> ship
         e grade --verdict ship --verify-verdict pass ; e land
```

```yaml
objective: induct-inline runs the narrow grade, scoped verdicts and the role swap
prove by:
  - test/skills.sh assertions on skills/induct-inline/SKILL.md and its
    three rendered copies (bp3 skills install), one per rule below
  - grep 'fix edge' CLAUDE.md AGENTS.md
done when:
  - each rule in the table below has a passing assertion, and each
    assertion fails on today's skill text
  - CLAUDE.md and AGENTS.md are identical and name no fix edge
  - make check-full green
```

## Diagram

```text
todo ─► author: change, make check, commit, scripts/receipt
          └─► handoff --reason "<receipt>"
handed_off ─► grader (fresh, cold, ~5 min, blocks)
          ├─ job 1  re-run receipt at <sha>
          ├─ job 2  one check the author missed (test-only: break the code)
          └─ job 3  commit claims ⊆ receipt + diff + job 2
          ▼
   ship ─────────► grade ship ─► land
   needs_fix ────► grader commits fix f + test ─► author grades f
   incomplete ───► no cast; report (yolo: park)
   follow-ups ───► listed in the reason; never block
```

## Pseudocode

```python
def grade(sha, node, receipt):                    # the grader, cold
    r = run("./scripts/receipt")                  # job 1, in the quest desk at sha
    probe = likeliest_missed_bug(diff(sha))       # job 2
    unbacked = claims(msg(sha)) - backed(r, diff(sha), probe)   # job 3
    if not ran_all(r, probe): return Incomplete(why)
    if failing_row(node, r) or probe.proved_bug:
        fix = commit_fix_with_test(probe)         # role swap
        return NeedsFix(reason, fix_sha=fix, receipt=run("./scripts/receipt"))
    return Ship(follow_ups=unbacked + probe.notes)
```

## Tables

| Field | Value |
|---|---|
| Intent | a grade measured in minutes, that cannot widen scope |
| Lane | standard (skill change, its own node per quest step 6.6) |
| Output | `skills/induct-inline/SKILL.md` and its renders, `test/skills.sh`, `CLAUDE.md` and `AGENTS.md` |
| Acceptance | one `test/skills.sh` assertion per rule; each fails today |
| Depends on | verify.2 - receipt |

| Rule the skill states | Assertion greps for |
|---|---|
| author hands off with `--reason "$(./scripts/receipt)"`, and receipt must exit 0 | `scripts/receipt` |
| grader runs exactly three jobs, target about five minutes | `three jobs` |
| test-only commits: job 2 breaks the covered code and sees red | `test-only` |
| `needs_fix` only for a failing acceptance row or a proven bug | `failing acceptance row` |
| anything else is a follow-up, listed in the reason, never blocking | `follow-up` |
| on `needs_fix` the grader commits the fix; the author grades it | `role swap` |
| a grader that could not run a job returns incomplete; nothing is cast | `incomplete` |
| the desk is clean at the graded sha when the grader returns | `clean at` |
| commit Verification lists commands and exit codes only | `exit codes only` |

## Prose

The test-pyramid run measured 25 grades: median about 11 minutes,
78k-198k tokens each, 16 of them re-grades. tier.1's acceptance never
named signals, yet four rounds (3c43d05, c89ab19, 331c272, 889a0f8)
were signal fixes: the grader graded "is it robust?" instead of "do
the rows pass?". The owner settled the new shape on 2026-11-19: keep a
grader, make it narrow and blocking ("but doesnt take 10 min"), and
let it write the fix itself ("can the grader apply the fix").

Why the role swap needs no engine change: `needs_fix` below the cap
returns the node to `todo`, and the engine does not record who
authors the next commit. Every commit is still judged by someone who
did not write it. A second `needs_fix` (the author rejects the
grader's fix) swaps again; the cap (`max_cycles: 3`) still blocks to
the owner.

Why no parallel fix branch: `handoff` refuses while a dependency is
unlanded (`E_DEPENDENCY`, `src/quest/main.ml:216`), and the last
quest's nodes shared gate files, so a merge-back stream buys about
three minutes and costs a rebase.

Out of this node: the `induct` workflow grader
(`skills/induct/workflows/induct-grade.js`, 1022 lines, pure grade
plus fix ledger) keeps its own contract. Aligning or retiring it is an
open question in the quest.
