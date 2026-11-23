---
date: 2026-11-23
quest: ../../QUEST.md
node: grade.1
status: proposed
---

# grade.1 - delta-brief: scoped GRADING.md, severity gate, delta cycle 2+

## TL;DR

Update `GRADING.md` and `src/quest/brief.ml` to kill the three measured grading time sinks: (1) replace manual multi-mutant planting with `./scripts/receipt` + **one** targeted adversarial probe, (2) restrict `needs_fix` strictly to `critical` or `major` findings (`[minor]` ships as a non-blocking follow-up note), and (3) make cycle 2+ briefs **delta-only** over `git diff <prev7>..<sha7>` (still zero author-typed `--reason` text).

## Acceptance gates

Observed today:

```text
$ rg -n "plant the bug in a scratch copy" GRADING.md
28:plant the bug in a scratch copy and watch the check go red.
$ rg -n "Re-judge the gates in full" src/quest/brief.ml
85:        [ "Previous round: " ^ p7 ^ " was graded needs_fix. Re-judge the gates in full; \
```

Design trace:

```text
$ bp3 q q1 n nd brief --desk /d    # cycle 1
  - Rules include: "Only critical or major findings cast needs_fix; minor findings ship as follow-ups."
  - Rules include: "Unjustified deletion or weakening of existing tests is a critical finding."
  - GRADING.md instructs: run `./scripts/receipt` (check-full + red-first) and ONE targeted adversarial probe;
    no instruction to manually plant mutants per check.
  - Verdict shape includes FOLLOW-UPS line for non-blocking minors.

$ bp3 q q1 n nd brief --desk /d    # cycle 2 (after needs_fix on 1111111 with --reason "SENTINEL")
  - Previous round says: "Delta re-grade: inspect `git diff 1111111..2222222` (ignoring other nodes' commits below),
    re-run `./scripts/receipt`, and re-verify only the Acceptance gates touched by that diff."
  - Does NOT contain "Re-judge the gates in full" and does NOT contain "SENTINEL".
```

```yaml
objective: cut grader cycles and wall time via deterministic receipt, severity gate, and delta cycle-2 briefs without leaking author rationale
prove by:
  - test/unit/test_brief.ml: cycle 1 brief includes severity gate & FOLLOW-UPS; cycle 2 brief includes delta wording, omits "Re-judge the gates in full", omits SENTINEL-REASON; Brief.is_verbatim still round-trips cleanly
  - test/g.sh: updated brief assertions pass on fixture quest
  - make check-full
done when: test_brief.ml, test/g.sh, and make check-full pass, and GRADING.md no longer mandates manual mutant planting
```

## Diagram

```text
Brief.render(inputs, desk)
   │
   ├─ cycle == 1 ──► Full scoped brief:
   │                   1. Run ./scripts/receipt (gate + red-first + test delta)
   │                   2. Check Acceptance gates vs git show <sha7>
   │                   3. Run ONE targeted adversarial probe
   │                   4. Severity gate: critical/major -> needs_fix; minor -> ship + FOLLOW-UPS
   │
   └─ cycle >= 2 ──► Delta brief (zero --reason text):
                       1. Run ./scripts/receipt
                       2. Review git diff <prev7>..<sha7> (skip other nodes' commits)
                       3. Re-verify ONLY gates touched by that diff + confirm no test weakening
                       4. Severity gate: critical/major -> needs_fix; minor -> ship + FOLLOW-UPS
```

## Pseudocode

```python
def render_rules():
    return [
        "Make no edits to tracked files, no commits, and no `bp3 q` calls.",
        "Put any scratch probe in `mktemp -d`; `git status --short` must be empty at the end.",
        "Severity gate: cast `needs_fix` ONLY for [critical] or [major] findings (broken gate, proven bug, weakened/deleted test, vacuous test, or CONSTRAINTS.md violation). [minor] nits (wording, note counts, style) go under FOLLOW-UPS and the verdict is `ship`.",
        "An edit to GRADING.md, CONSTRAINTS.md, or this node's Acceptance gates is owner-class unless the node's Output names the file.",
    ]

def render_previous(prev, commit, others):
    return (
        f"Previous round: {prev[:7]} was graded needs_fix. Delta re-grade: run `./scripts/receipt`, "
        f"review `git diff {prev[:7]}..{commit[:7]}` (ignoring other nodes' commits below), "
        f"and re-verify only the Acceptance gates touched by that diff plus any test deletions.\n"
        f"Other nodes' commits in that range: {fmt_others(others)}."
    )
```

## Tables

| Field | Value |
|---|---|
| Intent | stop wasting 6-11 min per grade on manual mutant hunting, minor-only bounces, and full re-audits on cycle 2+ |
| Lane | standard |
| Output | `GRADING.md`, `src/quest/brief.ml`, `test/unit/test_brief.ml`, `test/g.sh` |
| Acceptance | fails today (`GRADING.md` mandates manual mutant planting; `brief.ml` says "Re-judge the gates in full"); passes when unit + fixture tests pass |
| Depends on | `verify.2 - receipt` |
| Must not touch | `skills/*`, `bin/bp3`, `src/quest/metrics*.ml`, `CONSTRAINTS.md` |

## Prose

Note on `GRADING.md` editing rule: this node's `Output` explicitly names `GRADING.md`, so the grader rule ("an edit to GRADING.md is owner-class unless the node's Output names the file") cleanly authorizes the change once this quest is approved.

Note on `Brief.is_verbatim` backward compatibility (`test/metrics.sh` / old quests): `brief.2` re-renders historical quests using the current `Brief.render` function; changing `Brief.render` text means older quests from before this commit would read `brief_edited` if re-scraped, which is already documented as evidence-only (and historical quests are already scraped and landed). Verify `test/metrics.sh` still passes cleanly since its fixture renders through the current `bp3 q ... brief` verb!

Edge case for skill/docs-only nodes (`GRADING.md`): explicitly tell the grader that for Markdown/docs/skill-only commits (`red-first: n/a`), verify the gate (`make check-full`, `check-skills`, `check-retired-terms`) and acceptance criteria directly without demanding regex-pinning of every prose sentence.
