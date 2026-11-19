# dogfood.3 external-drive — author notes (cycle 1)

## What landed

Derived self/host mode end-to-end, never a flag:

- `Gitx.repo_mode` (src/graph/gitx.ml): `self` iff tracked
  `src/graph` + `bin/bp3`, else `host`. (Conductor context said
  `src/quest`; the tree renamed it to `src/graph` — derivation
  follows the tracked tree, and both mode implementations agree.)
- Run record carries `mode`: link mint derives and writes it,
  claim preserves and reports it, `bp3 config` reports derived
  `mode` top-level and per context. `--mode` on harness mint/
  claim, graph edges, and `bp3 skills install|check` is an
  E_USAGE naming the derivation.
- `bin/bp3 skills install` renders into the target repo
  (BP3_TARGET > cwd repo ≠ script repo > script repo): core
  skills (`bp3g bp3g-frame bp3g-no-human icebox naming red-ink`)
  everywhere, bp3-dev overlay (`add-bp3-skill add-yap-skill
  bp3g-landing-demo using-bp3`) self-only. Hook command is
  mode-aware (`./bin/bp3 g hooks` self, `bp3 g hooks` host).
  Unlisted source skills install nowhere; test/mode.sh asserts
  every source skill is listed exactly once.
- Packaging answer to the skills-source blocker:
  `scripts/install-bp3.sh` installs `bp3-g`, the `bin/bp3` tool
  script as `bp3`, and skills+check-skills+completions under
  `share/bp3/`; the installed script falls back to `bp3-g` on
  PATH rooted at the caller's repo. New `bp3 init-repo` door
  on the script (the binary already had it).
- Mode-aware reads: the four bp3g workflows derive
  `bp3Bin = desk ? "./bin/bp3" : "bp3"` (a desk exists only in
  self mode, so desk presence is the derived signal; the
  deskNote stays self-only). `bp3g` skill documents the modes.

## Live external conduct (evidence in tape.log)

- Installed the built artifact to /tmp/bp3-host-prefix; fresh
  fixture /tmp/flappy-bird (playable page + `node smoke.mjs`,
  base commit c858c8a).
- In the fixture, with /tmp/bp3-host-prefix/bin on PATH and no
  flag anywhere: install derived `host`, core present, all four
  bp3-dev skills absent, hooks call `bp3 g hooks`,
  `bp3 config` mode `host`, zero bp3-source files tracked.
- Conducted node `score-counter` on graph `flappy-score`:
  real change (score counts once per passed pipe, drawn on the
  page; smoke asserts it) committed as 21fb9de, link mint/claim
  record `mode: host`, then handoff → grade(ship) →
  verify(pass) → land: `landed`, `fin: node_fin`, rollup
  `goal_fin`. Smoke green after land; fixture tree clean.
- Self probe in this repo: mint derived `mode: self`
  (cleaned up after). Fixture Run record:
  /tmp/flappy-bird/.git/bp3/runs/20261118T141104Z-node-muse-code-muse-wonder-1.0-c1.json.

## Lessons

- Verdicts print to stdout, not stderr — tests must grep both.
- The skills.sh fixture had to become a real self repo (tracked
  src/graph + bin/bp3, BP3_TARGET naming its target): under
  derivation an unversioned copy is a host, and that was the
  honest fix, not a mode override.
- One relative-path shell call edited the conductor checkout's
  bin/bp3 usage line; reverted immediately (`git checkout --`).
  Every command since used the worktree path explicitly.
- `make release` stays tag-gated (v0.2.0 tag ≠ HEAD); the
  fixture install used the install.sh pattern (built artifact
  + checksum, explicit artifact arg), which is the supported
  path for an untagged drive.

## Verification

- test/mode.sh: 49 assertions (sets, derivation, --mode
  rejections, per-mode installs, workflow read path).
- make check-fast: green (8 suites).
- Full make check: exit 0 (all suites; completion parity
  needed --mode added to both completion lists).
