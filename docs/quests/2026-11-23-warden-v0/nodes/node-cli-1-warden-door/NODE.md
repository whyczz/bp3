---
date: 2026-11-23
quest: ../../QUEST.md
node: cli.1
status: proposed
---

# cli.1 - warden-door: expose top-level `bp3 warden` CLI door

## TL;DR

Add `src/warden/warden_io.ml` (read-only I/O edge) and wire top-level **`bp3 warden [<quest>] [--last N|--all] [--no-sessions] [--format json|table]`** (plus `-h`/`--help`) through `bin/bp3` -> `main.exe warden ...`. Bare `bp3 warden` runs repo-level health checks (`multi_active_quest`, leaked desks) plus the last 5 unreviewed real quests (quests with `docs/quests/<q>/QUEST.md` and NO `FEEDBACK.md`); `<quest>` or `--all` overrides the `FEEDBACK.md` skip. Auto-enables Layer-2 session traces via `Metrics_io.joined_traces`, updates `CONSTRAINTS.md:49` + owner Sign-off row, completions, `AGENTS.md`/`CLAUDE.md`, and adds `test/warden.sh` (registered in `test/suites.tsv`).

## Acceptance gates

Observed today:

```text
$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author
usage: bp3 init ...
```

Design trace:

```text
$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author
{"ok":true,"scope":"quest","quests":["2026-11-22-induct-inline-as-default-measure-author"],"sessions_scanned":N,"findings":[...],"counts":{"by_rule":{...},"by_layer":{"git":M,"session":K},"total":T}}
# exit 0; Layer 2 auto-enabled when local transcripts match, degrades to sessions_scanned: 0 when absent

$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author --no-sessions
# Layer 1 git-only (<1s), sessions_scanned: 0, exit 0

$ ./bin/bp3 warden 2026-11-22-induct-inline-as-default-measure-author --format table
RULE                  LAYER    SEV    NODE                        CYCLE  OBSERVED       SUMMARY
...
# exit 0

$ ./bin/bp3 warden
# scope: "repo", repo checks + last 5 unreviewed real quests (skips quests with FEEDBACK.md), exit 0

$ ./bin/bp3 warden --all
# scope: "repo", sweeps every real quest regardless of FEEDBACK.md, exit 0

$ ./bin/bp3 warden -h
# prints docstring + flags on stdout, exit 0, reads no state
```

```yaml
objective: expose two-layer Warden plugs through top-level bp3 warden with FEEDBACK.md reviewed-skip, JSON/table output, CONSTRAINTS.md sign-off, and fixture tests
prove by:
  - test/warden.sh: planted 12-plug fixture (git + --dir/--agy-dir) fires all 12 rules with observed/threshold/evidence_ref; FEEDBACK.md skip on bare bp3 warden vs --all vs explicit <quest>; --last N; --no-sessions; empty transcript dirs -> sessions_scanned=0; --format table; bad flag -> E_USAGE rc 2; unknown quest -> E_NOT_FOUND rc 2; -h -> stdout rc 0; repo unchanged (read-only)
  - test/check-constraints.sh + CONSTRAINTS.md:49 bp3 warden surface + owner sign-off row
  - test/completion.sh + real run against 2026-11-22-induct-inline-as-default-measure-author
  - make check-full
done when: test/warden.sh (in test/suites.tsv), test/check-constraints.sh, test/completion.sh, and make check-full pass
```

## Diagram

```text
bin/bp3 warden [<quest>] [--last N|--all] [--no-sessions] [--format json|table]
   │
   ▼ main.exe warden ... -> Warden_io.run
   ├─ repo checks: docs/quests/*/QUEST.md (status: active count), Worktree.list
   ├─ target selection: explicit <quest>, OR repo sweep (last N real quests without FEEDBACK.md; --all includes all)
   ├─ Layer 1 per quest: node ledgers + metrics.jsonl + post-land rev-list (<last_land_sha>..<branch|landed_commit>)
   ├─ Layer 2 per quest (auto unless --no-sessions): Metrics_io.joined_traces (Claude + Pi + agy)
   └─ Warden.run -> JSON or table on stdout, exit 0 (strictly read-only)
```

## Pseudocode

```python
def do_warden(args):
    quest_opt, last_n, all_flag, no_sessions, fmt, dirs, pi_dirs, agy_dirs = parse_flags(args)
    if quest_opt and (all_flag or last_n is not None):
        usage("pass either <quest> or --last/--all, not both")
    scope = "quest" if quest_opt else "repo"
    quests = [require_quest(quest_opt)] if quest_opt else select_real_quests(last=last_n or 5, include_reviewed=all_flag)
    ev = Warden_io.load(scope, quests, no_sessions, dirs, pi_dirs, agy_dirs)
    findings = Warden.run(ev)
    return format_table(ev, findings) if fmt == "table" else format_json(ev, findings)
```

## Tables

| Field | Value |
|---|---|
| Intent | give operators and `/warden` one fast, read-only top-level CLI door (`bp3 warden`) |
| Lane | standard |
| Output | `src/warden/warden_io.ml` (new), `src/quest/dune` (link `bp3_warden`), `src/quest/main.ml`, `bin/bp3` (`warden)` dispatch), `CONSTRAINTS.md` (`bp3 warden` surface + owner sign-off row), `completions/_bp3`, `completions/bp3.bash`, `AGENTS.md`, `CLAUDE.md`, `test/warden.sh` (new), `test/suites.tsv` |
| Acceptance | fails today (unknown door `warden`); passes when `test/warden.sh`, `check-constraints.sh`, `completion.sh`, and `make check-full` pass |
| Depends on | `plugs.1 - warden-engine` |
| Must not touch | `skills/*` |

## Prose

- **`CONSTRAINTS.md` sign-off (settled in red-ink closing red chair):** `cli.1` adds `bp3 warden` to `CONSTRAINTS.md:49` (`bp3 CLI`) and records the dated owner-words Sign-off row quoting Round 2 (`"Should Warden be its own top-level command — bp3 warden ... lock"`).
- **Read-only guarantee:** `Warden_io` writes zero git refs and zero `.git/bp3/` files, so `bp3 warden` runs cleanly inside `agy`'s default read-only `.git` sandbox.
- **Test split:** Known fixture cases in `test/warden.sh`; property-based tests omitted at the CLI layer (stated decision: core sort/count invariants live in `test/unit/test_warden.ml`).
