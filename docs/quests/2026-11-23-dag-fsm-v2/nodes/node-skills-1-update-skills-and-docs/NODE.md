---
node: skills.1
---

# skills.1 - update-skills-and-docs

TL;DR
Update conducting skills, rendered `.{agents,claude,pi}/skills/`, `AGENTS.md`/`CLAUDE.md`, shell completions, and tests to reflect the 2-edge happy path (`handoff -> grade`) and `E_MISSING_ANCESTOR`.

## Acceptance gates

Design trace:

```text
$ BP3_COMPLETIONS_DIR="$(mktemp -d)" ./bin/bp3 skills install --harness=all
$ ./bin/bp3 skills check
-> ok (zero drift)
$ cmp -s CLAUDE.md AGENTS.md
-> rc 0
$ ./test/skills.sh && ./test/completion.sh && make check-full
-> rc 0 (zero references to mandatory standalone `verify` or post-ship `land` on default plans)
```

Runnable goal block:
- **objective:** Keep every skill, doc, completion, and test synced with the v2 FSM and `E_MISSING_ANCESTOR`.
- **prove by:** `./bin/bp3 skills check`, `cmp -s CLAUDE.md AGENTS.md`, `./test/skills.sh`, `./test/completion.sh`, `make check-full`.
- **done when:** All checks exit `0` and no conducting skill instructs calling `--verify-verdict pass` or a redundant `land` after `grade --verdict ship` on default plans.

## Diagram

```text
skills/{induct*,using-bp3,quest}/SKILL.md + AGENTS.md/CLAUDE.md + completions/
  --> bp3 skills install --harness=all (with temp BP3_COMPLETIONS_DIR)
  --> .{agents,claude,pi}/skills/ synced
  --> test/skills.sh + test/completion.sh + make check-full GREEN
```

## Pseudocode

```python
def sync_skills_and_docs():
    update_skill_sources(["induct*", "using-bp3", "quest"])
    sync_identical("AGENTS.md", "CLAUDE.md")
    update_completions(["completions/_bp3", "completions/bp3.bash"])
    run("BP3_COMPLETIONS_DIR=$(mktemp -d) ./bin/bp3 skills install --harness=all")
    assert run("./bin/bp3 skills check") == 0
    assert run("make check-full") == 0
```

## Tables

| Field | Value |
|---|---|
| Intent | Dedicated skill-change node (per `quest/SKILL.md` step 6.6) syncing all agent instructions and completions to the lean FSM. |
| Lane | micro |
| Output | Updated `skills/*/SKILL.md`, rendered `.{agents,claude,pi}/skills/`, `AGENTS.md`, `CLAUDE.md`, `completions/{_bp3,bp3.bash}`, `test/{skills,completion}.sh`. |
| Acceptance | Fails today: conducting skills still instruct casting `grade --verdict ship --verify-verdict pass` followed by a separate `land` edge. |
| Depends on | `ancestry.1 - enforce-dep-commit-ancestry` |

## Prose

Per `quest/SKILL.md` step 6.6, skill edits always ride in their own node with their own verification gate. Keeping `AGENTS.md` and `CLAUDE.md` byte-identical (`cmp -s`) and protecting global zsh completion via `BP3_COMPLETIONS_DIR=$(mktemp -d)` are mandatory repo invariants.
