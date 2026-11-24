---
node: skills.1
---

# skills.1 - contracts-skills-and-completions

TL;DR
Update `quest`, `induct*`, `using-bp3`, rendered `.{agents,claude,pi}/skills/`, `AGENTS.md`/`CLAUDE.md`, shell completions, and skill/completion tests to document `--owns`, `parallel_batches` for `/swarm`, and `--kind code|direct|spike|gate`.

## Acceptance gates

Design trace:

```text
$ BP3_COMPLETIONS_DIR="$(mktemp -d)" ./bin/bp3 skills install --harness=all
$ ./bin/bp3 skills check
-> ok (zero drift)
$ cmp -s CLAUDE.md AGENTS.md
-> rc 0
$ ./test/skills.sh && ./test/completion.sh && make check-full
-> rc 0
```

Runnable goal block:
- **objective:** Wire `parallel_batches`, `--owns`, and `--kind` into all bp3 skills, docs, and shell completions.
- **prove by:** `./bin/bp3 skills check`, `cmp -s CLAUDE.md AGENTS.md`, `./test/skills.sh`, `./test/completion.sh`, `make check-full`.
- **done when:** `make check-full` exits `0`, conducting skills read `parallel_batches` instead of guessing file disjointness from prose, and `quest` skill documents `--owns` and `--kind`.

## Diagram

```text
skills/{quest,induct*,using-bp3}/SKILL.md + AGENTS.md/CLAUDE.md + completions/
  --> bp3 skills install --harness=all (temp BP3_COMPLETIONS_DIR)
  --> .{agents,claude,pi}/skills/ synced
  --> test/skills.sh + test/completion.sh + make check-full GREEN
```

## Pseudocode

```python
def sync_contracts_skills():
    update_induct_swarm_rule_to_read_parallel_batches()
    update_quest_skill_with_owns_and_kind()
    sync_identical("AGENTS.md", "CLAUDE.md")
    update_completions(["completions/_bp3", "completions/bp3.bash"])
    run("BP3_COMPLETIONS_DIR=$(mktemp -d) ./bin/bp3 skills install --harness=all")
    assert run("./bin/bp3 skills check") == 0
    assert run("make check-full") == 0
```

## Tables

| Field | Value |
|---|---|
| Intent | Dedicated skill-change node (per `quest/SKILL.md` step 6.6) syncing all agent instructions and completions to `owns` + `node_kind`. |
| Lane | micro |
| Output | Updated `skills/*/SKILL.md`, rendered `.{agents,claude,pi}/skills/`, `AGENTS.md`, `CLAUDE.md`, `completions/{_bp3,bp3.bash}`, `test/{skills,completion}.sh`. |
| Acceptance | Fails today: conducting skills instruct agents to check `Output` / `Must not touch` prose instead of reading `parallel_batches` from `bp3 q r`, and completions lack `--owns` / `--kind`. |
| Depends on | `kinds.1 - typed-node-kinds` |

## Prose

Per `quest/SKILL.md` step 6.6, skill edits always ride as their own node with their own test gate. Also verifies `completions/_bp3` and `completions/bp3.bash` complete `--owns`, `--kind`, `owns`, and `approve`.
