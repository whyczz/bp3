---
status: frozen
date: 2026-11-15
promoted: null
---

# bp3-portable-mvp-dogfood-esc3

## Context

Frozen 2026-11-15, the same day the owner called the Muse
harness MVP good enough to stop bootstrapping bp3 with bp3
and try bp3 as a portable control plane on a product it did
not grow up in.

Owner decision, same session, settling the red-chair
identity finding: **esc3 will be a new repo.** It is not
`~/m/escapement-2` (Python, binary `esc2`, already running
old Backpack — `bp task`, campaigns, wars, `.worktrees/`
sprawl, dirty `master`) and not `~/m/esc2` (OCaml, binary
`esc`). Those repos were looked at and ruled out as the
target; escapement-2 remains a useful reference for what
esc3 may become, nothing more.

This matches bp3's own framing: [readme.md](../../readme.md)
— "esc3 follows as the transfer test, not the first proof" —
and the Quest 2 history in the workflows-v2 tapes: a
separate esc3 build-out, run through bp3, whose quest file
lives in esc3.

Framing: **bp3 is the control plane** (mechanism,
orchestrator, only writer of quest state); **esc3 is the
data plane** (a new product repo; its commits are what
quest moves bind to). Portable-MVP means: the bp3 that
exists today — installed binary + Muse harness — drives
real work in a repo that shares no history, skills, or
state with the bp3 repo, with no bp3-repo special-casing.

## Sketch

Smallest version that would work, once thawed:

1. Install the mechanism once, machine-wide:
   `make release` in bp3, then
   `PREFIX=$HOME/.local ./scripts/install-bp3.sh`
   (installs `bp3-q` 0.2.0 + the `bp3` shim; the shim
   roots at the caller's repo via `BP3_ROOT` or cwd —
   [gitx.ml](../../src/quest/gitx.ml) `root`).
2. Create the esc3 repo fresh (owner names path and
   product slice — see Blockers), `git init -b master`,
   one base commit. In it: `bp3-q init-repo` — today
   this scaffolds exactly `plans/default.yaml` +
   `plans/direct.yaml` and refuses (`E_EXISTS`) to
   clobber differing plans
   ([main.ml](../../src/quest/main.ml) `init-repo`).
   That, plus `docs/quests/<quest>/` from the first
   quest, is the entire control-plane footprint inside
   the data-plane repo.
3. First quest is this entry's namesake:
   `bp3-portable-mvp-dogfood-esc3` — one quest, a small
   number of exps, driven through the Muse harness:
   create → submit (`--commit`) → review → land.
   Success = esc3's first real, usable slice lands
   entirely through bp3's gates, ledger in
   `esc3/docs/quests/` as the only record, and the
   friction list is written down (that list, not the
   slice, is the dogfood's real output).
4. The install loop is already proven — but only on a
   scratch repo: [test/install.sh](../../test/install.sh)
   git-inits `$work/esc3`, runs `init-repo`, a full
   quest/exp submit, and asserts the quest ref does
   **not** leak into the home repo. Thawing is that
   shape, for real, plus the harness.

Deliberately does **not** add: touching escapement-2,
migrating old Backpack (`bp task`/campaigns/wars), a
second harness or the Pi engine, cross-repo scheduling,
renaming or porting `esc2` code wholesale, or any bp3
feature built "for esc3" before the vanilla loop fails
somewhere specific. A bp3 bug found here becomes a bp3
exp with provenance, not a patch smuggled into the quest.

## Blockers

Red chair (engineering lens, 2026-11-15) findings,
updated for the new-repo decision. Facts verified against
disk that day; no repo was edited by the review.

- **[critical — settled] Identity.** Was: escapement-2
  misnamed as esc3. Settled by the owner: esc3 is a new
  repo. Remaining half: its path and its first product
  slice are still unnamed — a new repo with no slice
  definition thaws into a design session, not a quest.
- **[major] Nothing is installed.** `bp3-q` / `bp3`
  are not on PATH (`command not found`).
  `scripts/install-bp3.sh` needs a `make release`
  artifact first. This is step 1 of the sketch, listed
  here because every prior "it works" claim ran on the
  in-repo `./bin/bp3` or a test-prefix install.
- **[major] Harness skills have no road into esc3.**
  `./bin/bp3 skills install` roots at the bp3 repo's
  own `$root` — it renders skills into bp3, not into a
  target repo. The binary installs portably today; how
  Muse harness skills (quest, induct, commit…) reach
  esc3 is undecided: copy, symlink, harness-level
  install, or esc3 carries its own renders. First quest
  cannot run the harness until this is answered.

  Changes needed to make bp3 portable (red chair,
  engineering lens, 2026-11-15, second pass — the list
  this blocker actually contains):
  1. `skills install` needs a target: `--target` /
     `BP3_ROOT` / git-root resolution. Today `root` in
     `bin/bp3` is the script's own repo; there is no
     way to render into another repo at all.
  2. Kill `./bin/bp3` in everything that travels:
     `skills/using-bp3/SKILL.md` (steps 1–2),
     `skills/induct/SKILL.md` (`worktree prepare`),
     all three `skills/induct/workflows/*.js`
     (`"./bin/bp3 q …"` command strings), and the
     hooks command in `.claude/settings.json`
     (`./bin/bp3 q hooks`). esc3 has no `bin/bp3`;
     the PATH shim (`bp3`, from `scripts/bp3-shim`)
     is the only portable spelling.
  3. Root resolution in the binary: `src/quest/gitx.ml`
     `root` is `BP3_ROOT` or `Sys.getcwd ()` — no
     `git rev-parse --show-toplevel` anywhere in
     `src/quest/`. Invoking from a subdirectory of
     esc3 mis-roots quest state. Portable needs
     git-root fallback.
  4. `init-repo` is not an install: it scaffolds only
     `plans/default.yaml` + `plans/direct.yaml`. A
     portable install must also land the skill
     renders, the induct workflow copies, and the
     harness hook settings (merge, not clobber) — or
     explicitly scope itself to "binary + plans" and
     name who does the rest.
  5. Decide which skills travel. `using-bp3` says
     "in this repo" and describes an `invoke` /
     `--engine` API the current `bp3 q` CLI does not
     have (stale even at home); `add-bp3-skill` must
     *not* travel. Portable set (quest, induct,
     using-bp3-fixed, naming, icebox?) vs bp3-self set
     is an undecided cut.
  6. The boring alternative must be answered first:
     bp2 already does this — `bp2 init` installs a
     compiled skill catalog "into any git repo"
     (`~/m/bp2/README.md`), and `bp2` is installed on
     this machine. Building portability into bp3's
     shell installer may be reinventing bp2; shipping
     bp3's skills through the bp2/yap catalog may be
     the whole change. Unanswered, this is the
     strongest attack on the sketch as written.
- **[major] Control plane lives inside the data
  plane.** `init-repo` + quest create write `plans/`,
  `docs/quests/`, and `bp3/goal/*` refs *into* esc3
  (the scratch test asserts exactly this, checking only
  that refs don't leak *home*). Accepted by the Quest 2
  history ("the esc3 Quest's file lives in esc3"), but
  name it once: portability means the mechanism travels,
  not that state stays out of the product repo.
- **[minor] esc3 product scope is a blank page.**
  What esc3 does in one sentence, and what it borrows
  from escapement-2 vs leaves behind, is undecided.
  That is a `/quest` framing question at thaw, not a
  blocker for the portable mechanism itself — but the
  first slice must be real enough that the owner would
  use it, or the dogfood prices nothing.

What would change the red-chair verdict: owner names
esc3's path + first slice, `bp3-q --version` runs from
PATH, the skills-into-esc3 question has an answer, and
`init-repo` in the fresh repo diffs as only `plans/` +
the first `docs/quests/` folder.

## Promotion trigger

Thaw when the owner says "go" on
`bp3-portable-mvp-dogfood-esc3` **and**, observably:
`bp3-q --version` runs from PATH, the esc3 repo exists
with a clean `master` base commit, and one named first
slice exists. First move on thaw is `/quest`
transcription — install, `init-repo`, one quest — not
a port or a design session.
