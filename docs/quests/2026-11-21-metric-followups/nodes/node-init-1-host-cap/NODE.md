---
date: 2026-11-21
quest: ../../QUEST.md
node: init.1
status: proposed
---

# init.1 - host-cap: new host repos get ten review rounds

## TL;DR

`bp3 init-repo` writes `plans/default.yaml` with `max_cycles: 3`
(`src/quest/main.ml:684`), while this repo's plan says 10 (owner,
2026-11-21). A host repo initialized today stops at a cap this repo
gave up. After this node, the scaffold says 10.

## Acceptance gates

Observed today:

```text
$ grep -n 'max_cycles: 3' src/quest/main.ml
684:      let plans = [("plans/default.yaml", "goal_type: default\nmax_cycles: 3\n...
```

Design trace:

```text
$ ./test/install.sh    # bp3 init-repo in a scratch host, BP3_COMPLETIONS_DIR in scratch
  plans/default.yaml -> max_cycles: 10; plans/direct.yaml -> max_cycles: 0 (unchanged)
```

```yaml
objective: a new host repo starts with this repo's review cap
prove by:
  - test/install.sh asserts max_cycles 10 in the scaffolded default plan
  - make check-full
done when: the scaffold assertion passes, and fails on master's binary
```

## Diagram

```text
bp3 init-repo -> plans/default.yaml (max_cycles: 3 -> 10), plans/direct.yaml (0, unchanged)
```

## Pseudocode

```python
PLANS = {"plans/default.yaml": "goal_type: default\nmax_cycles: 10\n...",   # was 3
         "plans/direct.yaml":  "goal_type: direct\nmax_cycles: 0\n..."}
```

## Tables

| Field | Value |
|---|---|
| Intent | one default cap across this repo and the repos it scaffolds |
| Lane | micro |
| Output | `src/quest/main.ml` scaffold literal, the init-repo fixture |
| Acceptance | scaffold assertion; fails today |
| Depends on | none |

## Prose

The owner raised the cap for this repo's yolo runs: "increase the rounds
to 10, i do not want to be involved". A host repo is where bp3 is a tool
and the owner least wants to be paged, so the same default fits. Repos
already initialized keep their own `plans/`; this node changes only
what `init-repo` writes from now on.

## Tests

Known cases: the scaffold assertion. Property-based: omitted, since a
literal has no input space.
