---
node: gate.1
slug: planned-block-flag
kind: code
lane: standard
status: proposed
depends_on: []
---

# gate.1 - planned-block-flag

TL;DR
Add the boolean `--planned` flag to `bp3 q <quest> n <node> e block`, persist `"planned": true` in `ledger.jsonl`, track `blocked_planned` in `Store.node_state` (surfaced on `e block` and blocked node reads), reject `--planned` on non-`block` edges with `E_USAGE`, and advertise `--planned` in help text and shell completions.

## Acceptance gates

Design trace:

```text
$ bp3 q demoq n n1 e block --planned --reason "AV approval + overnight smoke"
{"ok":true,"quest":"demoq","node":"n1","kind":"code","state":"blocked","cycle":1,"planned":true,"human_action_required":true,...}
$ bp3 q demoq n n1 r
{"ok":true,...,"state":"blocked","blocked_planned":true,...}
$ bp3 q demoq n n1 e handoff --planned --commit HEAD --reason "bad"
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"--planned is only valid on block"},...}}
$ bp3 q demoq n n1 e block --planned --planned --reason "dup"
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"duplicate flag --planned"},...}}
```

Runnable goal block:
- **objective:** Allow `e block` to record intentional owner gates with `--planned` while rejecting misuse fail-closed.
- **prove by:** Unit tests in `test/unit/test_cli.ml` and `test/unit/test_store.ml`, CLI fixture tests in `test/fsm.sh` (or `test/block.sh`), and completion tests in `test/completion.sh`.
- **done when:** `make check-full` passes with assertions covering `--planned` parse/duplicate/non-block refusal, `"planned": true` in `ledger.jsonl`, `blocked_planned` fold/reset on `resume`, and shell completions.

## Diagram

```text
argv: bp3 q <q> n <n> e <edge> [--planned] --reason <why>
         |
         v
  Cli.parse_flags ---- duplicate --planned ---> E_USAGE
         |
         v
  Main.do_update
    |-- edge <> "block" && fl.planned --------> E_USAGE
    |-- edge = "block"
         |--> ledger_line (... extra: ["planned", true] when fl.planned)
         |--> state.blocked_planned <- fl.planned
         +--> verdict JSON {..., "planned": fl.planned, "human_action_required": true}
```

## Pseudocode

```python
@dataclass(frozen=True)
class BlockFlags:
    reason: str
    planned: bool = False          # True only when --planned passed on e block

def handle_block(state: NodeState, fl: BlockFlags) -> tuple[NodeState, dict]:
    if state.st not in ("todo", "handed_off", "approved"):
        raise IllegalEdge(state.st, "block")
    extra = [("planned", True)] if fl.planned else []
    line = make_ledger_line(edge="block", to="blocked", reason=fl.reason, extra=extra)
    next_state = replace(
        state,
        st="blocked",
        blocked_reason=fl.reason,
        blocked_planned=fl.planned,
    )
    verdict = {**finish(next_state, line), "planned": fl.planned, "human_action_required": True}
    return next_state, verdict
```

## Fields

| Field | Value |
|---|---|
| Intent | Persist and validate `--planned` on `e block` across CLI, ledger, folded state, and completions |
| Kind | `code` |
| Lane | `standard` |
| Output | Updated `src/quest/{names,cli,store,render,main}.ml`, `completions/{_bp3,bp3.bash}`, unit & CLI tests |
| Acceptance | Fails today (`E_USAGE: unknown flag: --planned`); passes when `--planned` writes `"planned": true` on `block`, resets `blocked_planned` on `resume`, and refuses non-`block` / duplicate usage |
| Depends on | none |

## Prose & edge cases

- **Backward compatibility:** Only emit `"planned": true` in `ledger.jsonl` when `fl.planned = true`; existing `block` ledger lines without `"planned"` fold with `blocked_planned = false`.
- **Reset on resume:** `Store.fold_ledger` sets `s.blocked_planned <- Util.get_bool j "planned" false` when `to_ = "blocked"`, and resets `s.blocked_planned <- false` on `edge = "resume"` (and any transition out of `blocked`).
- **Flag guard:** Reject `fl.planned = true` on every non-`block` edge (`handoff`, `grade`, `land`, `approve`, `iterate`, `resume`) and on `create`/`dep`/`delete` so `--planned` can never be silently ignored.
- **Tests:**
  - *Known cases:* parse `--planned`, duplicate `--planned` -> `E_USAGE`, non-`block` edge with `--planned` -> `E_USAGE`, `e block --planned` writes `"planned": true` to `ledger.jsonl` and returns `"planned": true`, unplanned `e block` omits `"planned"` from ledger and returns `"planned": false`, `e resume` clears `blocked_planned`, `completions/_bp3` & `completions/bp3.bash` offer `--planned`.
  - *Property-based:* Omitted in `gate.1` (finite 2-state boolean flag + 7-edge closed dispatch covered exhaustively by known cases; QCheck2 invariant lives in `gate.2`).
