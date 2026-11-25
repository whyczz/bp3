---
name: using-bp3
description: "Operate bp3 correctly in this repo: quest folders, bp3 q edges, ledger discipline, and verification, for any Controller or Worker session."
---
<!-- GENERATED from skills/using-bp3/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Using bp3

Use when working in the bp3 repo and the task touches quest
state: starting a quest, advancing one, recording a review or a
blocker, landing, or recovering after a dead session. Invoked by
a human, Controller, or Worker by name (`/using-bp3`,
`$using-bp3`). One output: bp3 operations performed through
`bp3 q`, with state read from its JSON verdicts.

Use `quest` instead to frame a new quest's intent and shape,
including its QUEST.md and node records. To run a whole quest,
use `induct`, the default: this session authors each
node, and fresh graders judge each commit in the background
from the brief `bp3 q <quest> n <node> brief` renders. Use
`induct-yolo` when no human is present.
General coding in this repo does not need this skill.

## Procedure

1. Read state first: `./bin/bp3 q r <quest>` (the rollup),
   `./bin/bp3 q r` (every quest), `./bin/bp3 q <quest> n <node> r`
   (one node). Never read `state.yaml` or `ledger.jsonl` by hand
   to decide anything.
2. Start a quest with `./bin/bp3 q c <quest> --type <goal_type>`,
   then each node with `./bin/bp3 q <quest> c <node>`. State is
   written to bp3's state branches (`bp3/quest/<quest>`,
   `bp3/node/<quest>/<node>`), never to the working tree; QUEST.md
   and the node records are authored. `goal_type` is the plan in
   `plans/` (default: up to ten review rounds). Who executes (the
   engine) is not a `bp3 q` flag.
3. Dependencies are set at create with `--depends-on` (quest
   deps by quest name on `q c`; node deps, same quest, on
   `q <quest> c <node>`) and recorded in the ledger. `handoff`
   refuses (`E_DEPENDENCY`, `facts.blocked_by`) until every
   node dependency is `landed` or `deleted` (a quest dependency:
   it has nodes, all `landed` or `deleted`, and is not itself
   deleted). Node deps can be redeclared later with
   `q <quest> dep <node> --depends-on <a,b> --reason <why>`.
4. Take only legal moves: the verdict JSON's `legal_edges`
   lists them, cast as `./bin/bp3 q <quest> n <node> e <edge>`.
   From todo, `handoff --commit <sha>`; from handed_off,
   `grade --verdict ship|needs_fix [--verify-verdict pass|fail]`
   (one combined cast) or `verify`; from approved, `land`;
   `block` from any of the three. `resume` is human-only, and
   `delete` (`./bin/bp3 q <quest> d <node>`) is the owner's
   call (the engine requires a human only to delete a blocked
   node). Every move, `d` included, needs `--reason`; it is
   recorded on the move's ledger line. Verdicts bind to the exact
   current commit. A
   `needs_fix` below the cycle cap returns the node to todo; at
   the cap it escalates to blocked — do not work around it. A
   `--mechanical` `needs_fix` (an exact file, line and text fix,
   no judgment call) returns to todo at any cycle and never
   blocks.
5. Commit work before handing it off. Only clean commits move:
   `handoff` refuses any dirty working tree (`E_DIRTY_TREE`),
   quest folders included, and binds only a commit that exists
   (`E_COMMIT_MISMATCH`).
6. Recover from the ledger, not from memory: after a dead
   session, `bp3 q r <quest>` rebuilds state from
   `ledger.jsonl`. Transcripts and tapes are evidence, never
   state, and tape is never parsed into facts.
7. Verify with `make check` while working and with
   `make check-full` before handoff, grade or land (the
   gate); report exactly what ran.
8. Measure with `./bin/bp3 q <quest> metrics r`: what each grade
   and author cycle cost (wall, tool calls, tokens), each
   cycle's time in todo and handed_off, and node and quest
   roll-ups. `./bin/bp3 q <quest> metrics scrape` collects from
   Claude Code transcripts and is safe to re-run; it exits 1
   when a number could not be checked and was not written (a
   grade transcript that disagrees with the harness report, or
   an author window holding a usage-less line), which is
   a finding to report, not a failed step. Its samples
   live in `metrics.jsonl` on each node's state branch,
   GENERATED like `ledger.jsonl`: never hand-edit it.
9. Promote and release only on explicit owner go (`BP3_DECIDER=human`):
   - Quest promotion: `BP3_DECIDER=human ./bin/bp3 release <quest>`
     (preview anytime with `--dry-run`, override level with
     `--bump major|minor|patch|none`, force local tag with `--no-gh`,
     skip `$PREFIX` install with `--no-install`, or recover failed
     GitHub publishing with `--publish-only`).
   - Small bugfix release (no quest): `BP3_DECIDER=human ./bin/bp3
     release --commit <sha>` (defaults to `--bump patch`).
   - In self mode, tagged releases refresh `$PREFIX` (`share/bp3/RELEASE`)
     and user-global `CORE_SKILLS` + hooks in `~/` (`~/.claude`,
     `~/.gemini/config`, `~/.pi/agent`, `~/.codex`, `~/.muse`). Host repos
     activate via `backpack.toml` (`bp3 init-repo`, inspect with `bp3 config`)
     and remove legacy local skill copies with `bp3 skills prune-local`
     (`SessionStart` emits read-only `W_LOCAL_SKILLS_LEGACY` instead of
     auto-committing). `bp3 warden` flags `missing_repo_config` when
     `backpack.toml` is absent. See `RELEASING.md`.
10. Cross-repo SQLite control plane (`~/.local/share/bp3/bp3.sqlite`, `BP3_DB` override):
    - `./bin/bp3 db info [--format json|table]` — DB path, WAL status, and counts.
    - `./bin/bp3 repo add [<path>] [--name <slug>] | list | remove <name>` —
      local repo registry (`bp3 init` / `bp3 skills install` / `bp3 init-repo` auto-register).
    - `./bin/bp3 ticket add|list|read|claim|unclaim|done|dismiss` — cross-repo
      ticket queue (`./bin/bp3 ticket list --to bp3` checks incoming tickets from
      host repos; host repos file via `bp3 ticket add --to bp3 ...`).

## Rules

- Never hand-edit `state.yaml` or `ledger.jsonl`. If a move was
  not taken through `bp3 q`, it did not happen.
- Status is a frontmatter field in `QUEST.md`
  (`proposed | active | landed | canceled`), never a folder.
  Quest paths never move; links and node records point at them.
- A reviewer who refactors produces a new commit; it needs its
  own handoff and a fresh grade.
- Teach before building on a new quest or design: concept,
  before, change, after, bites, transfer cues — then the nod.
- Instructions only: this skill holds no state and writes no
  Board, ledger, or state itself; `bp3 q` does that.
