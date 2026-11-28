---
status: frozen
date: 2026-11-23
promoted: null
---

# Single CLI: one `bp3` executable, no bash wrapper, no `bp3-q`

## Context

Frozen on 2026-11-23, during red-ink round 5 (functions) of
`docs/quests/2026-11-22-bp3-is-static-across-downstream-repo-worktrees/`.
Round 5 found that the installed wrapper never runs the engine installed
beside it. In the installed layout `bin/bp3` has `root=$PREFIX`, and
`run_q` (`bin/bp3:326-336`) tries `BP3_Q_BIN`, then
`$root/_build/default/src/quest/main.exe` (which never exists under a
prefix), then the first `bp3-q` on PATH. With two installs on PATH, one
install's wrapper ends up driving the other's engine.

The owner's words, in order: "pls do not do bp3-q, its bp3"; picked
"One binary" (merge the wrapper into OCaml); "damn why did we have the
bash wrapper"; "let's file an /icebox to have a single cli".

Why the wrapper exists. It came first. `bin/bp3` was born in 4467ab6
(2026-11-05) as the bash skills installer, before any OCaml existed.
The engine arrived in 851c0fc (2026-11-07), "behind bp3 invoke": it was
added under the bash command that already existed, rather than replacing
it. cebe3e0 (2026-11-14) made bp3 installable, and the engine was named
`bp3-q` so it could sit next to the wrapper. The split was never decided
as a split. It is 373 lines over 35 commits. It renders skills itself
(awk, the GENERATED notice, stale-render removal, workflow copies), owns
`init` and `skills install|check`, and passes `q n e harness config
worktree init-repo` to the engine.

## Sketch

```text
today                                   after
$PREFIX/bin/bp3     bash wrapper        $PREFIX/bin/bp3     OCaml, every verb
$PREFIX/bin/bp3-q   OCaml engine        (gone; make install removes a stale one)
$PREFIX/share/bp3/  skills, scripts     $PREFIX/share/bp3/  unchanged
./bin/bp3 (self)    the same wrapper    ./bin/bp3           thin pointer at _build (see Blockers)
```

- The engine gains `init` and `skills install|check`, and its renders
  are byte-identical to today's. Committed renders in bp3 and
  downstream repos must not churn, and `test/skills.sh` is the golden.
- Door names, verbs, flags and verdict JSON stay the same. Only the
  `bp3-q` filename and the `BP3_Q_BIN` lookup go away.
- The engine finds `share/bp3/` beside its own executable, as
  `Install.status` already plans to (install.3 of the static quest). No
  PATH lookup is left, so a wrong pairing can't happen.
- Hooks still fail open when no binary is built.
- Deliberately not added: no new language or library (OCaml with
  `yojson` + `unix` is already signed in `CONSTRAINTS.md`; bash leaves
  a surface, it doesn't join one). No behavior change to any verb, and
  no rename of the doors.

## Blockers

- **The self-mode `./bin/bp3` path.** Five hook events in
  `.claude/settings.json` run `./bin/bp3 q hooks || true`, and
  CLAUDE.md, the skills and the tests all call `./bin/bp3`. It has to
  keep working, and keep failing open, when `_build` is absent. That
  needs a decision: a 3-line exec stub (still bash, but trivial), a
  symlink into `_build`, or something else. Undecided.
- **Render parity.** Porting the awk renderer byte for byte is the real
  work. It is unmeasured how much of `test/skills.sh` pins exact bytes
  versus patterns.
- **`scripts/check-skills`** (bash, needs `jq` and Mike Farah `yq` v4)
  validates YAML before installing. Either keep shipping it in
  `share/bp3/scripts/`, or port it, which needs a YAML reader that is
  not in `CONSTRAINTS.md` today. That would be a pitch.
- **References to rewrite:** `bp3-q` appears in `Makefile`, `bin/bp3`,
  `scripts/bp3-shim` (deletable after), `scripts/install-bp3.sh`,
  `test/install.sh` and `test/js-unit.sh`. `BP3_Q_BIN` appears 72 times
  in `test/` and `Makefile`.
- **Version class.** Removing `bp3-q` from PATH is a CLI-contract break
  (MAJOR-class, which rides a MINOR before 1.0). It needs version.1 of
  the static quest (`bump:` and `RELEASING.md`) to land first, so the
  break is declared.
- **Overlap with the static quest.** Its install.1–install.3 are
  designed around two files (`bp3-q --build`, `E_INSTALL_MIXED` binary
  vs share). That quest's own round-5 call settles how it lives with the
  split until this thaws.

## Promotion trigger

Thaw when the static quest
(`2026-11-22-bp3-is-static-across-downstream-repo-worktrees`) has
landed, so `make install`, `share/bp3/BUILD` and `E_INSTALL_MIXED` exist
to test the merge against. Thaw sooner if a defect is traced to the
wrapper and the engine disagreeing: the wrong engine taken from PATH, or
a verb, flag or fix added to one side and not the other.
