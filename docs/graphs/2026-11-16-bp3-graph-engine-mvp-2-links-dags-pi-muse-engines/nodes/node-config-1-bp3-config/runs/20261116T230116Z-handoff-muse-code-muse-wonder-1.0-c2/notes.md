# config.1 (bp3-config) — author run notes, cycle 2

Cycle-2 fix for the c1 grade (`needs_fix`): the gated evidence
rows and the dead thresholds accessor, at their roots.

Changes (this commit):
- `src/quest/config.ml`: `ensure_dir` now swallows only
  `EEXIST` (mirroring `ensure_dir` in `worktree.ml`); any other
  mkdir failure raises at its site instead of surfacing later,
  misattributed. Header now states the present truth: the run
  config shape is defined here, its writer is link mint in
  mvp.1 (no verb writes `runs/*.json` yet). Removed the dead
  `Config.thresholds()` accessor, which had no consumer.
- `src/quest/main.ml`: the `bp3 config` door doc now scopes the
  thresholds claim: honored by the view today; enforcement in
  edge verdicts lands with mvp.1 (depth cap) and mvp.3
  (`W_SETUP_SLOW`) — the grade's scoping option, taken over
  inventing a consumer in this exp.
- `test/config.sh`: added a tracked-files assertion for the
  local-only case (`git ls-files` over the store is empty),
  and an attribution case: an unwritable store fails the view
  with `EACCES` naming the mkdir site, and the view recovers
  after repair. Threshold section re-scoped to the view.

Verification: `dune build --root=. src/quest/main.exe` ok,
`./test/config.sh` ok, `./test/completion.sh` ok, shellcheck
ok, full `make check` exit 0 in this worktree.

Typed evidence for the previously missing gated rows:
```json
[
  {"case": "local only", "rung": 3, "evidence": {"kind": "command", "ref": "./test/config.sh", "quote": "[ -z \"$(git ls-files \"$store\")\" ] assertion passes; config tests: ok"}, "verdict": "pass"},
  {"case": "adherence: no hand-edited state", "rung": 2, "evidence": {"kind": "command", "ref": "git status --porcelain (pre-commit, this run)", "quote": " M src/quest/config.ml / M src/quest/main.ml / M test/config.sh only"}, "verdict": "pass"}
]
```

Lessons:
- A store accessor with no consumer is a claim the code does
  not keep; either wire it in the exp that owns the verb or
  scope the claim in the door doc where users read it.
- Swallowing every mkdir error turns a one-line diagnosis
  into a later, wrong one; only `EEXIST` is benign.
