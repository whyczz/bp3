---
node: spec.1
---

# spec.1 - json-quest-schema-and-brief

TL;DR
Add pure OCaml `Quest_spec` (`src/quest/quest_spec.ml`) parsing and validating `quest.json` v1 (`E_INVALID_SPEC`), teach `Brief.render` to render structured acceptance gates straight from `quest.json` when present at `<commit>`, and add `docs/quests/<quest>/quest.json` to `E_PROTECTED_FILE` protection with unit and QCheck2 tests.

## Acceptance gates

Design trace:

```text
$ Quest_spec.parse_string valid_json
-> Ok { version = 1; quest = "demo"; nodes = [ ... ]; ... }
$ Quest_spec.parse_string cyclic_json
-> Error [ "dependency cycle: n1 -> n2 -> n1" ]
$ Quest_spec.parse_string explore_without_target_json
-> Error [ "node ex1 (explore) requires non-empty target" ]
$ Brief.render inputs_with_quest_json
-> contains "Acceptance gates (quest.json at abc1234):" + objective / prove_by / done_when
$ Store.protected_violations ~quest:"demo" ~node:"n1" ~allow_protected:false ["docs/quests/demo/quest.json"]
-> ["docs/quests/demo/quest.json"]
$ Quest_spec.json_diff_violations ~self_node:"r1" ~node_state_of ~before_json ~after_json
-> Ok () when only downstream todo node entries changed; Error ["docs/quests/demo/quest.json"] if own/non-todo node or quest-level fields changed
```

Runnable goal block:
- **objective:** Build the pure `Quest_spec` v1 schema/validator, JSON-backed cold brief rendering, `quest.json` protected-file lock, and `Research`/`Explore` JSON diff guard with exhaustive unit + property tests.
- **prove by:** New `test/unit/test_quest_spec.ml` (plus `test_brief.ml` and `test_store.ml` cases) covering valid specs, malformed JSON, bad slugs/kinds/bumps, duplicate node IDs, unknown deps, dep cycles, explore target/max_iterations, JSON brief rendering + fallback, `quest.json` protection, and `Quest_spec.json_diff_violations` (todo-only vs own/landed/top-level edits) + `make check-full`.
- **done when:** `make check-full` exits `0`, `Quest_spec` validates every invariant purely before any I/O, `Brief.render` prefers `quest.json` over `NODE.md` when present, `Store.protected_violations` locks `docs/quests/<quest>/quest.json`, and `Quest_spec.json_diff_violations` restricts `Research`/`Explore` `quest.json` edits to non-self `todo` node entries.

## Diagram

```text
quest.json text
  --> Quest_spec.parse_string (yojson)
        |-- invalid schema / bad kind / missing explore target / unknown dep / cycle --> Error (reasons) -> E_INVALID_SPEC
        +-- valid --> Quest_spec.t (topologically orderable DAG)
                        |
                        +--> Brief.render: formats objective / prove_by / done_when / trace directly
                        +--> Store.protected_violations: locks docs/quests/<q>/quest.json
```

## Pseudocode

```python
@dataclass(frozen=True)
class AcceptanceSpec:
    objective: str
    prove_by: list[str]
    done_when: str
    trace: list[str]

@dataclass(frozen=True)
class NodeSpec:
    id: str
    node: str
    title: str
    kind: Literal["code", "direct", "research", "explore", "human-gate"]
    lane: Literal["micro", "standard", "high-blast-radius"]
    depends_on: list[str]
    intent: str
    output: str
    acceptance: AcceptanceSpec
    target: str | None
    max_iterations: int | None

def parse_quest_spec(raw: str) -> Result[QuestSpec, list[str]]:
    j = parse_json(raw)
    require(j["version"] == 1)
    validate_slug(j["quest"])
    validate_bump(j["bump"])
    nodes = [parse_node(n) for n in j["nodes"]]
    check_no_duplicate_ids(nodes)
    check_all_deps_known(nodes)
    check_no_cycles(nodes)  # reuses Store.dep_cycle_through
    return Ok(QuestSpec(..., nodes=nodes))
```

## Tables

| Field | Value |
|---|---|
| Intent | Pure schema parsing, validation, JSON brief rendering, and Goodhart lock for declarative `quest.json` quests. |
| Kind | `code` |
| Lane | `standard` |
| Output | `src/quest/quest_spec.ml`, `Names.e_invalid_spec`, `Brief` JSON acceptance rendering in `src/quest/brief.ml`, `quest.json` lock in `src/quest/store.ml`, and unit/QCheck2 tests. |
| Acceptance | Fails today: `Quest_spec` and `E_INVALID_SPEC` do not exist; `Brief.render` ignores `quest.json`; `protected_files_for` does not lock `quest.json`. |
| Depends on | none |

## Prose

Separating pure `Quest_spec` parsing/validation from CLI git I/O (`init.1`) keeps the core schema 100% unit-testable with QCheck2 (fast sub-second inner loop, zero git subprocesses). Reusing `Store.valid_slug`, `Store.node_kind_of_string`, and `Store.dep_cycle_through` guarantees declarative JSON quests obey the exact same invariants as imperative `bp3 q c` calls.

Edge cases:
- Empty `nodes: []`: refused with `E_INVALID_SPEC` (a quest spec must declare at least one node).
- Unknown `kind` or `explore` with missing/blank `target` or `max_iterations <= 0`: refused with `E_INVALID_SPEC`.
- Self-dependency or multi-hop cycle: refused naming the exact cycle.
- Legacy quests without `quest.json`: `Brief.inputs` falls back transparently to `NODE.md` (`## Acceptance gates` -> `## Acceptance test`).
