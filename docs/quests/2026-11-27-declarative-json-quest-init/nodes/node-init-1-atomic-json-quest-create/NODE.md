---
node: init.1
---

# init.1 - atomic-json-quest-create

TL;DR
Wire `--file <path>` and optional `--scaffold` into `bp3 q c [<quest>] --file <path>` (`src/quest/{cli,main,names,release_io}.ml`, `scripts/check-bump`, `completions/`) so a validated `quest.json` atomically creates the quest branch and every node branch in topological order with zero partial state on error.

## Acceptance gates

Design trace:

```text
$ bp3 q c demo --file docs/quests/demo/quest.json
-> exit 0, {"ok": true, "quest": "demo", "state": "proposed", "nodes": [{"node": "node-a-1-...", ...}, ...]}
$ bp3 q r demo | jq '.nodes | length'
-> matches quest.json .nodes | length, with all kinds, deps, explore target/max_iterations set!

$ bp3 q c bad --file /tmp/bad-cycle.json
-> exit 1, E_INVALID_SPEC
$ bp3 q r bad
-> exit 1, E_NOT_FOUND   (zero partial refs left behind!)

$ bp3 q c demo2 --file docs/quests/demo2/quest.json --scaffold
-> exit 0, also writes docs/quests/demo2/QUEST.md and nodes/*/NODE.md with `## Acceptance gates`
```

Runnable goal block:
- **objective:** Enable one-command atomic quest + node DAG initialization from `quest.json`, with optional markdown scaffolding, `check-bump`/`bp3 release` compatibility, and zero partial refs on refusal.
- **prove by:** Unit tests in `test/unit/test_main.ml` (`--file`, `--scaffold` flag parsing), fixture tests in `test/g.sh` (atomic happy path across all 5 kinds + deps, `E_INVALID_SPEC` zero-ref rollback, `E_EXISTS` pre-check, `--scaffold`, and JSON-backed `bp3 q ... brief`), `test/completion.sh`, and `make check-full`.
- **done when:** `make check-full` exits `0`, `bp3 q c [<quest>] --file <path>` initializes quest + all nodes atomically in topological order, refuses any invalid or colliding spec before touching git refs, and completions cover `--file` and `--scaffold`.

## Diagram

```text
bp3 q c [<quest>] --file <path> [--scaffold]
  |
  1. read file + Quest_spec.parse_string  --Err--> E_INVALID_SPEC (0 refs written)
  2. check quest & node refs do not exist --Err--> E_EXISTS (0 refs written)
  3. validate goal_type plan + quest deps --Err--> E_INVALID_PLAN / E_USAGE (0 refs written)
  4. create quest ref + topologically sorted node refs (with kind, deps, target, max_iterations)
  5. if --scaffold: render QUEST.md + nodes/*/NODE.md
  --> return JSON summary verdict
```

## Pseudocode

```python
def do_quest_create_from_file(quest_arg: str | None, file_path: str, scaffold: bool):
    raw = read_file_or_not_found(file_path)
    spec = Quest_spec.parse_string(raw)           # raises E_INVALID_SPEC
    if quest_arg is not None and quest_arg != spec.quest:
        raise E_INVALID_SPEC("CLI quest arg disagrees with quest.json quest")
    validate_plan_exists(spec.goal_type)
    require_ref_absent(quest_branch(spec.quest))  # E_EXISTS before any write
    for n in spec.nodes:
        require_ref_absent(node_branch(spec.quest, n.id))
    ordered = topo_sort(spec.nodes)
    create_quest_branch(spec)
    created = [create_node_branch(spec.quest, n) for n in ordered]
    scaffolded = render_markdown_views(spec) if scaffold else []
    return {"ok": True, "quest": spec.quest, "state": "proposed", "nodes": created, "scaffolded": scaffolded}
```

## Tables

| Field | Value |
|---|---|
| Intent | Atomic single-command quest initialization from declarative `quest.json` with pre-write validation and optional markdown scaffolding. |
| Kind | `code` |
| Lane | `standard` |
| Output | `--file` / `--scaffold` flags in `src/quest/{names,cli,main}.ml`, `bump` fallback in `scripts/check-bump` & `release_io.ml`, `completions/{_bp3,bp3.bash}`, unit + fixture tests. |
| Acceptance | Fails today: `bp3 q c demo --file ...` fails with `E_USAGE: unknown flag: --file`. |
| Depends on | `spec.1 - json-quest-schema-and-brief` |

## Prose

Pre-validating every invariant (schema, slugs, plan existence, quest/node non-existence, dep closure, acyclicity) before the first `create_branch_commit` guarantees that a broken `quest.json` never leaves a half-initialized quest dangling in `refs/heads/bp3/`. Topological ordering ensures each node's `depends_on` references already-created sibling refs during initialization, matching imperative `bp3 q <q> c <n>` invariants cleanly.

Edge cases:
- `bp3 q c --file docs/quests/demo/quest.json` (omitting redundant `<quest>` positional): reads `quest` directly from `quest.json`.
- `bp3 q c wrong-name --file docs/quests/demo/quest.json`: refuses `E_INVALID_SPEC` naming the mismatch before writing anything.
- Existing `QUEST.md` when `--scaffold` is omitted: leaves authored `QUEST.md` untouched; `--scaffold` refuses to overwrite a modified file unless absent (or clearly documents overwrite behavior — settled in `/red-ink` Open question #2).
