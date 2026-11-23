---
date: 2026-11-23
quest: ../../QUEST.md
node: skills.1
status: proposed
---

# skills.1 - agy-induct-inline: fast receipts, severity gate, agy tiering & /swarm parallel mode

## TL;DR

Update `skills/induct-inline/SKILL.md` (and `skills/induct-inline-yolo/SKILL.md` where needed) and re-render all harnesses so the default quest workflow uses `./scripts/receipt` before handoff, enforces the read-only severity-gated grader (no `[minor]` bounces), and adds first-class `agy` execution: lane-based `invoke_subagent` model tiering (`flash`/`pro`) plus `/swarm` parallel `ready`-node authoring (`fork: "coordinator"` + `workspace: "share"`, cold non-forked graders, coordinator as sole `bp3 q` writer).

## Acceptance gates

Observed today:

```text
$ rg -n "receipt|swarm|invoke_subagent|flash" skills/induct-inline/SKILL.md || echo "none"
none
```

Design trace:

```text
skills/induct-inline/SKILL.md carries:
  - Author runs `./scripts/receipt` on the clean commit before handoff and passes its output as `--reason`.
  - Read-only grader; ONLY `[critical]`/`[major]` findings cast `needs_fix`; `[minor]` ships with follow-ups logged.
  - `agy` subagent tiering: `invoke_subagent` with `Model: "flash"` for `micro`/docs/skill nodes, `"flash"` or `"inherit"` for `standard`, `"pro"` or `"inherit"` for `high-blast-radius`.
  - `agy` `/swarm` parallel mode (optional, when >=2 independent `ready` nodes have disjoint file boundaries):
      * Coordinator reads quest + codebase once, then forks warm `@coder-*` workers (`fork: "coordinator"`, `workspace: "share"`).
      * Graders are strictly cold (NEVER forked), running in detached grade desks.
      * Coordinator is the sole `bp3 q` writer and serial merger (workers never call `bp3 q` -> avoids `.git/` sandbox `EPERM` and verdict races).
  - Re-rendered cleanly across `.pi/skills`, `.claude/skills`, `.agents/skills` (including `agy` `.agents/hooks.json`).
```

```yaml
objective: codify the fast receipt loop and agy multiagent patterns in induct-inline and re-render all harness copies
prove by:
  - test/skills.sh: asserts induct-inline carries receipt, severity gate, agy invoke_subagent model tiering, and /swarm coordinator-only bp3 q rule; renders match source
  - test/mode.sh: CORE_SKILLS / DEV_SKILLS parity green
  - ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
  - make check-full
done when: skills.sh, mode.sh, check-skills, and make check-full pass with zero stale renders
```

## Diagram

```text
induct-inline (agy)
   │
   ├─ 1 ready node ──► warm main session authors -> ./scripts/receipt -> handoff
   │                   -> cold invoke_subagent grader (flash/pro by Lane) in grade desk
   │
   └─ >=2 disjoint ready nodes ──► /swarm parallel mode:
        coordinator (warm, sole bp3 q writer)
          ├── fork + share -> @coder-A (edits, make check, clean commit)
          ├── fork + share -> @coder-B (edits, make check, clean commit)
          └── cold (NO fork) -> @grader (detached grade desk, receipt + 1 probe)
```

## Pseudocode

```python
def induct_inline_step(quest):
    state = bp3_q_r(quest)
    ready_todo = [n for n in state.ready if n.state == "todo"]
    if harness == "agy" and len(ready_todo) >= 2 and disjoint_files(ready_todo):
        spawn_swarm_coders(ready_todo, fork="coordinator", workspace="share")
        # coders commit cleanly on their share branch, run ./scripts/receipt, report SHA
        # coordinator merges/tracks commits, runs `e handoff`, spawns COLD grader in grade desk
    else:
        author_inline(ready_todo[0])
        receipt = run("./scripts/receipt")
        bp3_handoff(ready_todo[0], sha, reason=receipt)
        spawn_cold_grader(ready_todo[0], model=model_for_lane(ready_todo[0].lane))
```

## Tables

| Field | Value |
|---|---|
| Intent | update the default conducting skill so `agy` runs quests fast and in parallel without hitting sandbox or cold-start walls |
| Lane | micro |
| Output | `skills/induct-inline/SKILL.md`, `.pi/skills/induct-inline/SKILL.md`, `.claude/skills/induct-inline/SKILL.md`, `.agents/skills/induct-inline/SKILL.md`, `.agents/hooks.json`, `test/skills.sh` |
| Acceptance | fails today (no `receipt`, `invoke_subagent`, `flash`, or `/swarm` in `induct-inline`); passes when `skills.sh`, `mode.sh`, and `make check-full` pass |
| Depends on | `grade.1 - delta-brief`, `agy.1 - tx-core-and-scrape`, `agy.2 - cli-hooks-and-install` |
| Must not touch | `src/quest/*`, `scripts/*`, `GRADING.md`, `CONSTRAINTS.md` |

## Prose

Rule 6.6 of `skills/quest/SKILL.md`: skill changes ride as their own node, never bundled into code nodes.

Also ensure `test/skills.sh` tests only the **semantic invariants** (receipt step, severity gate, cold non-forked grader, coordinator-only `bp3 q`, model-tier table) — not fragile word-for-word regexes of every prose sentence, directly addressing the 23.5-minute `skills.2-inline-yolo` prose-grep waste measured on `2026-11-22`.

Remember `GRADING.md`: when running `./bin/bp3 skills install`, set `BP3_COMPLETIONS_DIR` to a scratch temp directory so the owner's global zsh completions aren't modified during builds/tests.
