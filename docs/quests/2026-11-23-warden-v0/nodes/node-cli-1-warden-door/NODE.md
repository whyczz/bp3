---
date: 2026-11-23
quest: ../../QUEST.md
node: cli.1
status: proposed
---

# cli.1 - warden-door: expose `bp3 q <quest> warden` CLI verb

## TL;DR

Wire `Warden.run` into the `bp3 q` door as `bp3 q <quest> warden [--no-sessions] [--format json|table]` and `bp3 q warden --all-landed [--no-sessions] [--format json|table]` (plus `-h`/`--help`), **auto-enabling Layer-2 session-trace plugs** via `Metrics_io.joined_traces` whenever local Claude/Pi/`agy` transcripts exist on disk, registering `Names.verb_warden` in `src/quest/names.ml` and `Store.reserved_slugs`, and adding `test/warden.sh` fixture coverage.

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden
{"ok":false,"error":{"code":"E_USAGE",...}}
```

Design trace:

```text
$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden
{"ok":true,"quests":["2026-11-22-induct-inline-as-default-measure-author"],"sessions_scanned":N,"findings":[...],"counts":{"by_rule":{...},"by_layer":{"git":M,"session":K},"total":T}}
# exit 0; Layer 2 auto-enabled when local transcripts match, degrades to sessions_scanned: 0 when absent

$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden --no-sessions
# Layer 1 git-only (<1s), sessions_scanned: 0, exit 0

$ ./bin/bp3 q 2026-11-22-induct-inline-as-default-measure-author warden --format table
RULE                  LAYER    SEV    NODE                        CYCLE  SUMMARY
...
# exit 0

$ ./bin/bp3 q warden --all-landed
{"ok":true,"quests":[...],"sessions_scanned":N,"findings":[...],"counts":{...}}
# exit 0

$ ./bin/bp3 q warden -h
bp3 q <quest> warden [--no-sessions] [--format json|table] | bp3 q warden --all-landed ...
# exit 0, stdout, reads no state
```

```yaml
objective: expose two-layer Warden plugs (with auto-enabled Layer-2 session traces) through bp3 q with JSON/table outputs, reserved slug protection, and fixture tests
prove by:
  - test/warden.sh: fixture quest with planted Layer-1 issues (minor-only bounce, vacuous-test bounce, 3 cycles, leaked grade desk) AND fixture session transcripts (--agy-dir / --dir) with planted Layer-2 issues (3x tool_retry_loop, 2x make check-full in author, >150k context_end) -> all 9 rules fire; --no-sessions suppresses Layer 2 cleanly; empty transcript dirs degrade cleanly to sessions_scanned=0; --format table, --all-landed, bad flag -> E_USAGE, unknown quest -> E_NOT_FOUND, reserved slug "warden" -> E_USAGE, -h -> stdout rc 0
  - real run against 2026-11-22-induct-inline-as-default-measure-author completes cleanly
  - make check-full
done when: test/warden.sh (registered in test/suites.tsv) and make check-full pass
```

## Diagram

```text
bp3 q <quest> warden [--no-sessions] [--format json|table]
bp3 q warden --all-landed [--no-sessions] [--format json|table]
   │
   ├─ Layer 1 inputs: node ledgers + metrics.jsonl + open desks (Worktree)
   ├─ Layer 2 inputs (auto unless --no-sessions): Metrics_io.joined_traces (Claude + Pi + agy)
   └─ Warden.run -> JSON or table on stdout, exit 0 (read-only, never mutates state)
```

## Pseudocode

```python
def do_warden(quest_opt, args):
    fmt, all_landed, no_sessions, dirs, pi_dirs, agy_dirs = parse_warden_flags(args)
    if all_landed and quest_opt is not None:
        usage("pass either <quest> or --all-landed, not both")
    quests = list_landed_quests() if all_landed else [require_quest(quest_opt)]
    findings, scanned = [], 0
    for q in quests:
        traces = [] if no_sessions else Metrics_io.joined_traces(q, dirs, pi_dirs, agy_dirs)
        scanned += len(traces)
        ev = load_evidence(q, traces=traces)
        findings.extend(Warden.run(ev))
    return format_table(quests, findings) if fmt == "table" else format_json(quests, scanned, findings)
```

## Tables

| Field | Value |
|---|---|
| Intent | give operators and `/warden` one fast, read-only CLI door to query deterministic waste findings |
| Lane | standard |
| Output | `src/quest/names.ml` (`verb_warden`), `src/quest/store.ml` (`reserved_slugs`), `src/quest/main.ml` (`do_warden`, help docstring), `completions/_bp3`, `completions/bp3.bash`, `CLAUDE.md`, `AGENTS.md` (1 Commands line), `test/warden.sh` (new), `test/suites.tsv` |
| Acceptance | fails today (`E_USAGE`); passes when `test/warden.sh` and `make check-full` pass |
| Depends on | `plugs.1 - warden-engine` |
| Must not touch | `skills/*`, `bin/bp3` |

## Prose

Two important CLI details:
- **Both `bp3 q <quest> warden` AND `bp3 q warden --all-landed`:** mirrors `bp3 q icebox r` (quest-less sub-door) and `bp3 q <quest> metrics r` (quest-scoped sub-door), with `warden` reserved in `Store.reserved_slugs` so no quest or node can collide with it.
- **Exit code is always 0 when the read succeeds** (even when findings are non-empty), because Warden is post-hoc evidence, never a blocking gate (`ICEBOX.md:21`). Only usage errors (`E_USAGE`) and missing quests (`E_NOT_FOUND`) exit 2.
- **Read-only guarantee:** `do_warden` writes zero git refs and zero `.git/bp3/` files, so it even runs cleanly inside `agy`'s default read-only `.git` sandbox!
