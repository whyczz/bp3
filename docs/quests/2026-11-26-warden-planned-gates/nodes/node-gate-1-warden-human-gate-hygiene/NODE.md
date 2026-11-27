---
node: gate.1
slug: warden-human-gate-hygiene
kind: code
lane: standard
status: proposed
depends_on: []
---

# gate.1 - warden-human-gate-hygiene

TL;DR
Thread `ne_kind` (`--kind human-gate` etc.) into `Warden.node_evidence` and `Warden_io.load_quest`, suppress Layer-1 and Layer-2 `human_steer` findings on `human-gate` nodes while keeping unplanned `e block`, cycle-cap escalations, and mid-code steers as `Major`, emit `planned_gates[]` in `bp3 warden` JSON (and summary count in table), and allow `bp3 warden <quest>` to succeed on proposed quests where `docs/quests/<q>/QUEST.md` exists before `bp3 q c <q>`.

## Acceptance gates

Design trace:

```text
# 1. Quest with --kind human-gate node approved via e approve -> 0 human_steer, visible in planned_gates[]
$ bp3 warden demoq --format json
{"ok":true,"scope":"quest","quests":["demoq"],"sessions_scanned":1,"planned_gates":[{"quest":"demoq","node":"node-av-gate","kind":"human-gate","cycle":1,"reason":"AV signed off"}],"findings":[],...}

# 2. Table summary appends planned gate count when > 0
$ bp3 warden demoq --format table
warden (quest): 0 findings across 1 quest(s), 1 session(s) scanned (1 planned gate)

# 3. Proposed quest (QUEST.md exists, no bp3 q c yet) -> succeeds instead of E_NOT_FOUND
$ bp3 warden 2026-11-26-warden-planned-gates --format json
{"ok":true,"scope":"quest","quests":["2026-11-26-warden-planned-gates"],"sessions_scanned":0,"planned_gates":[],"findings":[],...}

# 4. Unplanned e block or cycle-cap escalation or mid-code USER_INPUT -> STILL Major human_steer
```

Runnable goal block:
- **objective:** Make Warden `human-gate`-aware and proposed-quest-safe without adding any flags to `bp3 q`.
- **prove by:** Pure unit + QCheck2 tests in `test/unit/test_warden.ml` and CLI fixtures in `test/warden.sh`.
- **done when:** `make check-full` passes with all positive, negative, proposed-quest, and QCheck2 assertions green.

## Diagram

```text
Main.do_warden <quest>
  |-- fold_quest q <> None OR QUEST.md exists ---> Warden_io.load_quest q
  |                                                  |-- Store.fold_node -> ne_kind
  |                                                  v
  +-- neither exists ---> E_NOT_FOUND            Warden.run (pure)
                                                   |-- planned_gates_of(ev) -> [{quest,node,kind,cycle,reason}]
                                                   |-- plug_human_steer_block: skip ne_kind = "human-gate"
                                                   |-- plug_human_steer_session: skip ne_kind = "human-gate"
                                                   v
                                                 JSON (+ planned_gates[]) / table (+ "(N planned gate(s))")
```

## Pseudocode

```python
@dataclass(frozen=True)
class PlannedGate:
    quest: str
    node: str
    kind: Literal["human-gate"]
    cycle: int
    reason: str

def planned_gates_of(ev: Evidence) -> list[PlannedGate]:
    out = []
    for qe in ev.quests:
        for ne in qe.nodes:
            if ne.kind == "human-gate":
                for e in ne.entries:
                    if not e.refused and e.edge == "approve" and e.to == "landed":
                        out.append(PlannedGate(qe.quest, ne.node, "human-gate", e.cycle, e.reason))
    return out

def plug_human_steer_block(ev: Evidence) -> list[Finding]:
    # Skip any node with ne.kind == "human-gate".
    # Keep firing Major human_steer on all other non-refused block / to="blocked" entries.
    ...
```

## Fields

| Field | Value |
|---|---|
| Intent | Wire `ne_kind`, `planned_gates[]`, `human-gate` suppression, and proposed-quest support into Warden |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `src/warden/warden.ml`, `src/warden/warden_io.ml`, `src/quest/main.ml`, `test/unit/test_warden.ml`, `test/warden.sh` |
| Acceptance | Fails today (`Warden` lacks `ne_kind` & `planned_gates[]`, and `bp3 warden <proposed-quest>` returns `E_NOT_FOUND`); passes when all 4 design-trace cases and QCheck2 law pass |
| Depends on | none |

## Prose & edge cases

- **Unapproved `human-gate` node:** If a `human-gate` node is still `todo` (or `blocked`), `plug_human_steer_block` and `plug_human_steer_session` emit `0` `human_steer`, while `planned_gates[]` records approved `human-gate` entries (with `e.le_reason`).
- **Legacy nodes:** Nodes without `"node_kind"` in their `create` ledger line already fold to `Code` in `Store.fold_ledger`, preserving 100% backward compatibility.
- **Proposed quests (`QUEST.md` only):** When `fold_quest q = None` and `docs/quests/<q>/QUEST.md` exists, `Warden_io.load_quest` loads `qe_nodes = []`, `qe_open_desks = open_desks_for q`, `qe_post_land_commits = []`, `qe_traces = []` cleanly without crashing.
- **Tests:**
  - *Known cases:* (1) approved `human-gate` -> `0` findings, `planned_gates` has exact `{quest, node, kind, cycle, reason}` and table shows `(1 planned gate)`; (2) `human-gate` with `USER_INPUT` trace -> `0` Layer-2 `human_steer`; (3) `code` node with `e block` -> `Major human_steer` (Layer 1); (4) `code` node with cycle-cap `grade -> blocked` -> `Major human_steer` (Layer 1); (5) `code` node with mid-node `USER_INPUT` -> `Major human_steer` (Layer 2); (6) proposed quest with `QUEST.md` only -> exit `0`, `findings: []`; (7) nonexistent quest -> `E_NOT_FOUND` exit `1`.
  - *Property-based (QCheck2):* Generate arbitrary lists of `human-gate` and `code` nodes with random `block`/`approve`/`USER_INPUT` events; assert `human_steer` findings come strictly from non-`human-gate` nodes and `List.length (planned_gates_of ev)` equals the exact count of non-refused `approve -> landed` entries on `human-gate` nodes.
