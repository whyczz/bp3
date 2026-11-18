# exp-6-hooks submit run — lessons

- Implemented `bp3 q hooks` in `src/quest/hooks.ml`: stdin JSON,
  self-gate (bin/bp3 + docs/quests at payload cwd), reentrancy
  skip, witnessed binding from the env preset in PreToolUse
  commands, and an internal fact writer that appends event
  lines to the exp ledger on its branch. Exit 0 always.
- Registry lives in the git dir (`bp3-run-registry.json`), never
  the worktree: witnessing a Run must not dirty the tree, or the
  submit guard (E_DIRTY_TREE) eats the Run it observes.
- Event lines carry no `edge`/`from`/`to` keys, so the fold
  skips them by construction. That forced dropping Exp 4's
  `run_started {edge, ...}` spelling: an `edge: "submit"` key
  is fold-visible even with no `to`. Kept `cycle` + `session_id`.
- `Stop` is checkpoint-only; settle is `SessionEnd`/`SubagentStop`.
  Usage tallies per Run in the registry and lands as exactly one
  `usage_recorded` at settle, summed from real PostLLMCall fields.
- SessionStart sweep marks every other unsettled binding
  `run_unsettled`. Sharp edge: a SessionStart while a parallel
  Run is still live would sweep it early; ordering in fixtures
  settles first. A last-seen age gate is the fix if that bites.
- `bp3 skills install` now also writes `.muse/hooks.json`
  (one `./bin/bp3 q hooks` command for all events), asserted in
  test/skills.sh; test/hooks.sh covers every Acceptance case.
- Verify: `make check` green (lint, skills 43 assertions, q,
  tape, hooks, induct-exp). No live induct-exp run with hooks
  firing in a real harness session was done in this Run; the
  live half of Exp 4's prove-by remains for a later Run.
