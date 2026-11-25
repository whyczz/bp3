---
status: landed
home_repo: bp3
date: 2026-11-25
bump: minor
---

# global-skills-and-backpack-toml: user-global bp3 skills & hooks + committed per-repo `backpack.toml`

TL;DR
Unify `bp3`'s machine-global binary (`~/.local/bin/bp3`) and SQLite control plane (`~/.local/share/bp3/bp3.sqlite`) with user-global `CORE_SKILLS` and hooks (matching `yap`: `~/.gemini/config/skills/`, `~/.claude/skills/`, `~/.pi/agent/skills/`, `~/.codex/skills/`) and a committed <=15-line `backpack.toml` manifest at each bp3-managed repo root (`version = 1`, `repo`, `[grade].gate`, `[warden].grade_wall_s`, `[release].target`). Keep `DEV_SKILLS` (`add-bp3-skill`, `add-yap-skill`, `using-bp3`) repo-local inside `bp3`, gate global `bp3 q hooks` deterministically on `backpack.toml`, retire host `SessionStart` auto-commit skill sync, add read-only `W_NO_REPO_CONFIG` warnings + `missing_repo_config` Warden plug, ship `bp3 skills prune-local`, and migrate `bp3` itself (followed post-release by `~/m/predictor`).

ELI5
Today every repo that uses `bp3` has to commit 21+ duplicated generated skill files (`.agents/`, `.claude/`, `.pi/`) and 4 hook configs into git, plus run a `SessionStart` hook that auto-commits skill updates whenever `bp3` bumps a version. That clutters host repos like `predictor`, mixes generated `bp3` files with repo-owned skills (`/new-strategy`, `/start-server`), and lets binary and skills drift out of sync. This quest moves `bp3`'s core skills and hooks to your user home directory (installed right alongside `bp3-q` on `bp3 release` / `make install`, just like `yap`) and gives each bp3 repo one tiny committed `backpack.toml` manifest (<=15 lines) that activates hooks and declares repo rules (`gate`, `grade_wall_s`, `target`).

## Context

Addresses Ticket `#2` in `bp3.sqlite` (filed from `predictor` on `2026-11-25`: *"Global bp3 skills + committed per-repo backpack.toml manifest (roll out to bp3, predictor)"*).

Owner decisions settled at framing (`2026-11-25`):
1. **`.toml` sign-off (`CONSTRAINTS.md`):** `"Sign off adding .toml to CONSTRAINTS.md data ext (pure-OCaml parser, 0 new libs) + update Surfaces skills row"`.
2. **Skill split:** `"CORE_SKILLS (7) install user-globally; DEV_SKILLS (add-bp3-skill, add-yap-skill, using-bp3) stay repo-local inside bp3"`.
3. **Global hooks + retire auto-sync:** `"Move hooks user-global too (~/.claude/settings.json, ~/.gemini/config/hooks.json) and self-gate bp3 q hooks on backpack.toml; retire host SessionStart auto-commit sync"`.
4. **Rollout boundary:** `"Quest builds + migrates bp3 itself and ships a clean migration command (bp3 init-repo / prune-local); predictor rollout runs right after bp3 release as the documented rollout check"`.

Measured ground (audited `2026-11-25` on `master` `a7087eb`):

| Fact | Source |
|---|---|
| `CONSTRAINTS.md:24` lists `data ext .md .json .jsonl .yaml .tsv .txt .mmd .conf` — `.toml` is absent and fails `scripts/check-constraints` | `CONSTRAINTS.md:24`, `scripts/check-constraints:54-71` |
| `bin/bp3:36-37,83-92` hardcodes repo-local renders (`.pi/skills`, `.claude/skills`, `.agents/skills`) for all 7 `CORE_SKILLS` + 3 `DEV_SKILLS` and writes `.claude/hooks.json`, `.claude/settings.json`, `.muse/hooks.json`, `.agents/hooks.json` into every target repo | `bin/bp3:36-37,83-92,218-281` |
| `scripts/install-bp3.sh:31-63` copies `bp3-q`, `bp3`, and `share/bp3/skills`, but never installs user-global skills or hooks | `scripts/install-bp3.sh:31-63` |
| `src/quest/hooks.ml:221-333,367-371` gates repo hooks on `bin/bp3` + `docs/quests` (self-only!) and uses `maybe_host_auto_sync` to `git add` + `git commit` host skill dirs on `SessionStart`; `hooks.ml:401` uses `Gitx.root` rather than `gate_root` | `src/quest/hooks.ml:221-333,367-425` |
| `src/quest/main.ml:660-680` `init-repo` scaffolds only `plans/default.yaml` + `plans/direct.yaml` and calls `Repo_store.add`; creates no `backpack.toml` | `src/quest/main.ml:660-680` |
| `src/quest/config.ml:51-63` reads only `<git-common-dir>/bp3/config.json` and emits no repo manifest or `W_NO_REPO_CONFIG` | `src/quest/config.ml:51-63` |
| `src/warden/warden.ml:168-202` hardcodes `grade.wall_s > 300.` in `plug_cycle_outlier` and has no `missing_repo_config` plug | `src/warden/warden.ml:168-202` |
| `src/quest/release_io.ml:168-175` auto-detects `master`/`main` when `--target` is omitted; ignores any repo manifest | `src/quest/release_io.ml:168-175` |
| `src/quest/brief.ml:93-103` renders `GRADING.md` only; `scripts/receipt:53` defaults to `BP3_RECEIPT_GATE:-make check-full` | `src/quest/brief.ml:93-103`, `scripts/receipt:53` |
| `Makefile:35` and `scripts/check-gates:50` run `./scripts/check-skills skills .pi/skills .agents/skills .claude/skills` — keeping `DEV_SKILLS` (3 skills) in those 3 repo dirs keeps `check-gates` 100% green without gate churn | `Makefile:35`, `scripts/check-gates:50` |
| Registered local repos in `bp3.sqlite`: `bp3` (`/Users/whycz/m/bp3`), `esc3` (`/Users/whycz/m/esc3`), `predictor` (`/Users/whycz/m/predictor`) | `bp3 repo list` (`2026-11-25`) |
| `yap` global skills live at `~/.gemini/config/skills/` (tracked via `yap-skills.lock.json`); global `agy` hooks live at `~/.gemini/config/hooks.json` (keyed by top-level hook name `"bp3"`) | `~/.gemini/config/skills/yap-skills.lock.json`, `agy-customizations/docs/hooks.md` |

## Terms

| Term | Meaning |
|---|---|
| `backpack.toml` | committed per-repo bp3 manifest at repo root (`Layout.manifest_file`), <=15 lines, declaring `version = 1`, `repo = "<slug>"`, and optional `[grade].gate`, `[warden].grade_wall_s`, `[release].target` |
| `Backpack` | pure OCaml module `src/quest/backpack.ml` (stdlib-only) parsing, validating, and rendering `backpack.toml` with zero external libraries |
| `W_NO_REPO_CONFIG` | structured read-only warning (`Names.w_no_repo_config`) emitted by `bp3 config`, `bp3 q r`, `bp3 warden`, and `bp3 release --dry-run` when `backpack.toml` is absent (`"run bp3 init-repo to create backpack.toml"`) |
| `E_INVALID_CONFIG` | typed refusal (`Names.e_invalid_config`, exit 1) when `backpack.toml` exists on disk but has malformed syntax, unknown `version`, or invalid field types |
| `W_LOCAL_SKILLS_LEGACY` | read-only `SessionStart` hook warning when a host repo still carries leftover `<!-- GENERATED from skills/` copies after global-skills migration |
| `missing_repo_config` | Layer-1 Warden plug (`severity = Minor`, `evidence_ref = "repo:backpack.toml"`) firing when `backpack.toml` is absent from repo root |
| `CORE_SKILLS` | the 7 universal bp3 workflow skills (`induct`, `induct-yolo`, `quest`, `icebox`, `naming`, `red-ink`, `warden`), installed user-globally |
| `DEV_SKILLS` | the 3 bp3-authoring skills (`add-bp3-skill`, `add-yap-skill`, `using-bp3`), installed repo-locally only inside `bp3` (`self` mode) |
| `global_skills_dir` | user-global skill root per harness under `$HOME` (overridable via `$BP3_GLOBAL_HOME` in tests): `agy -> ~/.gemini/config/skills`, `claude -> ~/.claude/skills`, `pi -> ~/.pi/agent/skills`, `codex -> ~/.codex/skills`, `muse -> ~/.muse/skills` |
| `prune-local` | subcommand `bp3 skills prune-local` removing only `<!-- GENERATED from skills/` copies and legacy repo-local bp3 hook files/entries while preserving all repo-owned skills and non-bp3 hooks |

## Inputs

| Input | Source & precedence |
|---|---|
| `backpack.toml` | repo root (`<repo>/backpack.toml`, or `git show <commit>:backpack.toml` inside `Brief.inputs`); strictly read-only on all read/check commands |
| CLI flags (`--target`, `BP3_RECEIPT_GATE`) | explicit invocation flag/env always wins over `backpack.toml` (`--target` > `[release].target` > auto-detect `master`/`main`; `BP3_RECEIPT_GATE` > `[grade].gate` > `make check-full`) |
| `<git-common-dir>/bp3/config.json` | machine-local config (existing `setup_slow_s`, `depth_cap`); separate from git-tracked `backpack.toml` |
| `BP3_GLOBAL_HOME` / `HOME` | overrides base directory for user-global skill & hook installs (tests export `BP3_GLOBAL_HOME="$work/home"` or `HOME="$work/home"` so real `~/` is never touched) |
| `BP3_SKIP_GLOBAL_SKILLS` | optional `=1` opt-out for `scripts/install-bp3.sh` in isolated binary-only checks |
| hook stdin JSON (`cwd`, `workspacePaths`) | harness hook payload; anchors `gate_root` even when the global hook process runs from `~/.gemini/config/` or `~/.claude/` |

## Outputs

| Output | Shape |
|---|---|
| `backpack.toml` (`bp3 init-repo`) | `version = 1`, `repo = "<slug>"`, `[grade]` / `[warden]` / `[release]` defaults; idempotent (existing `backpack.toml` preserved untouched), plus `plans/` scaffolding and `bp3.sqlite` registration |
| `bp3 config` (JSON/table) | adds `"repo_config"` object (or `null`) and optional `"warnings": [{"code":"W_NO_REPO_CONFIG","message":"..."}]`; strictly read-only |
| `bp3 q r` / `bp3 release --dry-run` | adds optional `"warnings"` array with `W_NO_REPO_CONFIG` when `backpack.toml` is missing (omitted when present); zero tree writes |
| `bp3 warden` | honors `[warden].grade_wall_s` (default `300`) in `cycle_outlier`, adds Layer-1 minor finding `missing_repo_config` when `backpack.toml` is absent, and emits `W_NO_REPO_CONFIG` warning |
| `bp3 q <q> n <n> brief` & `scripts/receipt` | renders `[grade].gate` from bound commit's `backpack.toml` in grader brief; `scripts/receipt` defaults gate command to `[grade].gate` when `BP3_RECEIPT_GATE` is unset |
| `bp3 skills install` / `scripts/install-bp3.sh` | installs 7 `CORE_SKILLS` + non-clobbering global hooks into user-global harness dirs (`agy`, `claude`, `pi`, `codex`, `muse`); in `self` mode also renders 3 `DEV_SKILLS` locally and prunes local `CORE_SKILLS` copies; in `host` mode writes zero files to the host repo |
| `bp3 skills prune-local` | removes only `<!-- GENERATED from skills/` copies and legacy repo-local bp3 hooks from `<target>`, preserving repo-owned skills and non-bp3 hooks |
| `bp3 q hooks` | activates when `backpack.toml` exists at `gate_root` (derived from `payload.cwd`, working even when process `$PWD` is `~/.gemini/config/`), stays dormant otherwise; emits `W_LOCAL_SKILLS_LEGACY` on `SessionStart` if stale local generated copies remain; never auto-commits |
| `bp3` repo migration (`skills.1`) | committed `backpack.toml` at `bp3` root; 21 duplicated local `CORE_SKILLS` renders + legacy repo-local hook files removed; 3 `DEV_SKILLS` kept local; global activation guard in all 7 `CORE_SKILLS` |

## Acceptance gates

Observed today (`2026-11-25`, `master` `a7087eb`):

```text
$ test -f backpack.toml && echo exists || echo missing
missing
$ grep -n '\.toml' CONSTRAINTS.md || echo "no .toml in CONSTRAINTS.md"
no .toml in CONSTRAINTS.md
$ ls .agents/skills/ | wc -l
      10
$ ./bin/bp3 skills prune-local 2>&1 | head -1
usage: bp3 init [--harness=<pi|claude|codex|muse|agy|all>] | ...
$ grep -n 'grade.wall_s > 300' src/warden/warden.ml
183:          let slow_over = match slow_grade with Some (c, v) when v > 300. -> Some (c, v) | _ -> None in
```

Design trace (after quest lands):

```text
manifest.1  CONSTRAINTS.md allows .toml in data ext + documents user-global skills surface
            dune test (test_backpack.ml: parser + QCheck2 round-trip + malformed refusal) -> OK
            in fresh repo without backpack.toml:
              bp3 config -> ok:true, repo_config:null, warnings:[{code:"W_NO_REPO_CONFIG",...}] (tree untouched)
              bp3 init-repo -> creates backpack.toml + plans/, registers in bp3.sqlite, ok:true
              bp3 init-repo (2nd run, after custom edit to backpack.toml) -> preserves user's backpack.toml, ok:true
            ./test/config.sh && ./test/install.sh && ./test/check-constraints.sh -> rc 0

manifest.2  in repo without backpack.toml:
              bp3 q r / bp3 release --dry-run / bp3 warden -> ok:true + W_NO_REPO_CONFIG (zero writes)
              bp3 warden -> minor finding missing_repo_config (evidence_ref: "repo:backpack.toml")
            in repo with backpack.toml ([warden] grade_wall_s = 600, [release] target = "main", [grade] gate = "echo custom-gate"):
              bp3 warden on 450s grade_wall_s -> NO cycle_outlier; on 650s -> cycle_outlier (> 600s)
              bp3 release --dry-run (no --target) -> selects target "main"; --target master overrides to "master"
              bp3 q <q> n <n> brief -> includes "Repo gate (backpack.toml): echo custom-gate"
              ./scripts/receipt -> runs "echo custom-gate" when BP3_RECEIPT_GATE unset
            ./test/warden.sh && ./test/release-door.sh && ./test/receipt.sh && ./test/g.sh -> rc 0

global.1    BP3_GLOBAL_HOME="$work/home" ./bin/bp3 skills install --harness=all
              -> installs 7 CORE_SKILLS to $work/home/{.gemini/config/skills,.claude/skills,.pi/agent/skills,.codex/skills,.muse/skills}
              -> merges bp3 hooks into $work/home/.claude/settings.json and $work/home/.gemini/config/hooks.json WITHOUT clobbering existing custom hooks
              -> in self mode: renders ONLY 3 DEV_SKILLS into .agents/.claude/.pi/skills/ and prunes local CORE_SKILLS
              -> in host mode: creates ZERO files in host repo
            bp3 skills prune-local in legacy host repo with both generated bp3 skills AND custom .agents/skills/new-strategy/SKILL.md
              -> removes all generated bp3 skills + legacy bp3 hooks; preserves new-strategy/SKILL.md and non-bp3 hooks untouched
            scripts/install-bp3.sh installs bp3-q, bp3, share/bp3/skills AND global skills + global hooks in one step
            ./test/skills.sh && ./test/mode.sh && ./test/install.sh -> rc 0

global.2    cd /tmp && printf '{"hookEventName":"PreToolUse","conversationId":"c1","cwd":"<repo-with-backpack>","toolCall":...}' | bp3 q hooks
              -> activates via backpack.toml at gate_root (even though process PWD is /tmp!), resolves registry/runs under gate_root
            same payload with cwd="<non-bp3-repo>" -> exit 0, reason:"not a bp3 repo", zero writes
            SessionStart in host repo with leftover local generated skills -> exit 0, emits W_LOCAL_SKILLS_LEGACY, ZERO git commits
            ./test/hooks.sh && ./test/release-sync.sh -> rc 0

skills.1    bp3 repo root has committed backpack.toml (<= 15 lines)
            ls .agents/skills/ .claude/skills/ .pi/skills/ -> each holds ONLY add-bp3-skill, add-yap-skill, using-bp3 (3 each)
            all 7 CORE_SKILLS carry the backpack.toml activation guard
            ./bin/bp3 skills check -> {"ok":true,...}
            make check-full -> 25/25 suites green

post-rel    BP3_DECIDER=human ./bin/bp3 release 2026-11-25-global-skills-and-backpack-toml
            (cd ~/m/predictor && bp3 init-repo && bp3 skills prune-local)
              -> adds predictor backpack.toml (dune gate, grade_wall_s = 600, target = "master"), removes duplicated generated bp3 skills, keeps /new-strategy & /start-server untouched
```

## Goal and why

Eliminate per-repo skill duplication, binary-vs-skill version skew, and git-polluting auto-sync commits across all `bp3`-managed repos while giving every repo one clean, committed manifest (`backpack.toml`) for repo-owned rules. One machine-global toolchain (`~/.local/bin/bp3` + `~/.local/share/bp3/bp3.sqlite` + user-global `CORE_SKILLS` + user-global hooks) paired with a <=15-line git-tracked `backpack.toml` establishes a crisp boundary: machine state stays out of git, repo policy lives in git, and `<repo>/.agents/skills/` belongs exclusively to repo-owned skills.

## Success picture

- `backpack.toml` (`<= 15` lines, pure OCaml parser, `.toml` signed in `CONSTRAINTS.md`) is the single repo-owned manifest read by `bp3 config`, `bp3 q r`, `bp3 warden`, `bp3 release`, `bp3 q ... brief`, `scripts/receipt`, and `bp3 q hooks`.
- Missing `backpack.toml` never mutates a tracked working tree on read/check commands; it emits `W_NO_REPO_CONFIG` and a minor `bp3 warden` finding (`missing_repo_config`).
- `bp3 skills install` and `scripts/install-bp3.sh` install the 7 `CORE_SKILLS` and non-clobbering `bp3` hooks user-globally (`~/.gemini/config/`, `~/.claude/`, `~/.pi/agent/`, `~/.codex/`, `~/.muse/`), keeping `DEV_SKILLS` strictly repo-local inside `bp3` and writing zero generated files into host repos.
- Global `bp3 q hooks` re-roots on `payload.cwd` (so running from `~/.gemini/config/` works identically), self-gates on `backpack.toml`, and never auto-commits inside host repos.
- `bp3` itself has a committed `backpack.toml` and zero duplicated local `CORE_SKILLS` copies, all 25/25 suites pass, and `bp3 init-repo` + `bp3 skills prune-local` gives `~/m/predictor` a 2-command rollout right after release.

## Scope

| In | Out |
|---|---|
| `CONSTRAINTS.md` sign-off for `.toml` in `data ext` + updated user-global `skills` surface (`manifest.1`) | Adding any external OCaml TOML opam library (pure stdlib subset parser only) |
| Pure OCaml `src/quest/backpack.ml` parser/serializer/validator + `bp3 init-repo` + `bp3 config` (`manifest.1`) | Moving machine paths/desks/SQLite into `backpack.toml` (those stay in `.git/bp3/`, `~/.bp3/desks/`, `bp3.sqlite`) |
| Wiring `backpack.toml` + `W_NO_REPO_CONFIG` into `bp3 q r`, `bp3 warden` (`grade_wall_s` + `missing_repo_config`), `bp3 release` (`target`), `brief.ml` + `scripts/receipt` (`gate`) (`manifest.2`) | Full arbitrary TOML 1.0 spec (arrays of tables, inline tables, multi-line strings, dates — out of scope for <=15-line flat manifest) |
| User-global `CORE_SKILLS` + non-clobbering global hooks in `bin/bp3` + `scripts/install-bp3.sh` + `bp3 skills prune-local` + `bp3 skills check` (`global.1`) | Uninstalling or modifying `yap` skills (`yap-skills.lock.json` or hand-written skills) |
| `hooks.ml` `gate_root` re-rooting + `backpack.toml` self-gate + retiring host `SessionStart` auto-commit sync in favor of `W_LOCAL_SKILLS_LEGACY` (`global.2`) | Directly committing inside `~/m/predictor` from inside a `bp3` quest node (runs post-release via the documented 2-command rollout) |
| Global activation guard in 7 `CORE_SKILLS`, committed `bp3/backpack.toml`, pruning `bp3`'s 21 duplicated local `CORE_SKILLS` renders + legacy repo-local hooks, doc updates (`skills.1`) | Migrating `esc3` in this quest (optional follow-up using the exact same `bp3 init-repo && bp3 skills prune-local`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):**
  - **Signed addition (owner, `2026-11-25`):** `"Sign off adding .toml to CONSTRAINTS.md data ext (pure-OCaml parser, 0 new libs) + update Surfaces skills row"`.
  - Adds **zero** new languages, **zero** new OCaml/bash libraries (pure OCaml stdlib TOML subset parser in `src/quest/backpack.ml`), and **zero** new top-level CLI doors (`bp3 init-repo`, `bp3 config`, `bp3 skills`, `bp3 warden`, `bp3 release`, `bp3 q` are all already signed).
  - `manifest.1` records the Sign-off log row quoting the owner's words verbatim alongside the `data ext .toml` and Surfaces `skills` edits.
- **Common-sense pass (`CONTEXT.md`):**
  - Q5 Org scale (`CONTEXT.md:64`, checked 2026-11-19): *"At org scale, skills live in one marketplace repo with an owner per plugin and lint CI."* User-global installation from one canonical `bp3` release keeps skills and binary in lockstep without 3× per-repo copy drift.
  - Q5 Always-loaded context vs triggered skills (`CONTEXT.md:61`, checked 2026-11-19): repo-specific rules that must hold (`gate`, `grade_wall_s`, `target`) belong in structured machine-read config (`backpack.toml`), not duplicated across skill prose or `AGENTS.md`.
  - Q2 Storage & Q6 Chesterton's fence (`CONTEXT.md:34,82`, checked 2026-11-19): `maybe_host_auto_sync` existed solely because skills were duplicated into host git repos and drifted from `$PREFIX/bin/bp3`. Moving skills user-global removes the root cause so the auto-commit sync fence comes down cleanly.

## Human touchpoints

| When | Owner |
|---|---|
| Approve quest frame (optional `/red-ink` if any node detail changes) | owner |
| Promote & release (`goal_fin`: `/warden` + `BP3_DECIDER=human ./bin/bp3 release 2026-11-25-global-skills-and-backpack-toml`, which installs global binary + skills + hooks to `~/.local` and `~/`) | owner |
| Post-release `predictor` rollout: run `(cd ~/m/predictor && bp3 init-repo && bp3 skills prune-local)` and set `predictor`'s `backpack.toml` overrides (`gate`, `grade_wall_s = 600`, `target = "master"`), commit in `predictor` | owner |

## Nodes

### Milestone: manifest

| Node | TL;DR |
|---|---|
| [manifest.1 - backpack-toml-parser-and-config](nodes/node-manifest-1-backpack-toml-parser-and-config/NODE.md) | `CONSTRAINTS.md` sign-off (`.toml` + global skills surface), pure-OCaml `src/quest/backpack.ml` parser/validator, `bp3 init-repo` scaffolding `backpack.toml` + `plans/` + `bp3.sqlite`, read-only `bp3 config` with `repo_config` + `W_NO_REPO_CONFIG`, `test_backpack.ml` + `config.sh` + `install.sh` |
| [manifest.2 - wire-manifest-consumers-and-warnings](nodes/node-manifest-2-wire-manifest-consumers-and-warnings/NODE.md) | wire `backpack.toml` + read-only `W_NO_REPO_CONFIG` into `bp3 q r`, `bp3 warden` (`[warden].grade_wall_s` + `missing_repo_config` plug), `bp3 release` (`[release].target` + `--dry-run` warning), `brief.ml` + `scripts/receipt` (`[grade].gate`) |

### Milestone: global

| Node | TL;DR |
|---|---|
| [global.1 - global-skills-and-hooks-installer](nodes/node-global-1-global-skills-and-hooks-installer/NODE.md) | user-global `CORE_SKILLS` (7) + non-clobbering global hooks (`~/.claude/settings.json`, `~/.gemini/config/hooks.json`, `~/.muse/hooks.json`) in `bin/bp3` & `scripts/install-bp3.sh`; keep `DEV_SKILLS` (3) self-local; ship `bp3 skills prune-local` & updated `bp3 skills check`; isolated `skills.sh` + `mode.sh` + `install.sh` |
| [global.2 - hooks-backpack-gate-and-retire-autosync](nodes/node-global-2-hooks-backpack-gate-and-retire-autosync/NODE.md) | re-root `hooks.ml` onto `payload.cwd` `gate_root` (works when process `$PWD` is `~/.gemini/config/`), self-gate on `backpack.toml`, retire `maybe_host_auto_sync` git auto-commits in favor of read-only `W_LOCAL_SKILLS_LEGACY`, update `hooks.sh` + `release-sync.sh` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - global-activation-prose-and-bp3-migration](nodes/node-skills-1-global-activation-prose-and-bp3-migration/NODE.md) | add `backpack.toml` activation guard to all 7 `CORE_SKILLS`, update `warden`/`using-bp3` docs, commit `bp3`'s own `backpack.toml`, untrack 21 duplicated local `CORE_SKILLS` renders + legacy repo-local hooks (keeping 3 `DEV_SKILLS`), update `AGENTS.md`/`CLAUDE.md`/`RELEASING.md` |

## Scorecard

| Row | Baseline (`2026-11-25`, `a7087eb`) | Target | Read from |
|---|---|---|---|
| Generated `bp3` skill files committed per host repo | 21 files (7 skills × 3 dirs) + 4 hook files | **0 files** (only committed <=15-line `backpack.toml` + `plans/`) | `bp3 skills install` in host fixture |
| Generated `CORE_SKILLS` copies tracked in `bp3` | 21 files (`.agents`/`.claude`/`.pi`) | **0 files** (only 3 `DEV_SKILLS` × 3 = 9 local files) | `ls .agents/skills/ .claude/skills/ .pi/skills/` |
| External OCaml libraries added for TOML | 0 | **0** (pure stdlib `src/quest/backpack.ml`) | `CONSTRAINTS.md`, `src/quest/dune` |
| `SessionStart` git auto-commits in host repos | mutates host repo via `git commit --no-verify` | **0 git writes** (read-only `W_LOCAL_SKILLS_LEGACY` warning) | `test/release-sync.sh` |
| Configurable `[warden].grade_wall_s` / `[grade].gate` / `[release].target` | hardcoded `300s` / `make check-full` / `master\|main` | driven by `backpack.toml` with CLI override precedence | `test/warden.sh`, `test/release-door.sh`, `test/receipt.sh` |

## Risks and red chair

Red chair of the plan AND Ticket `#2` source (Steps 7 & 7.5):

- **Attack 1 (Critical — global `agy` hook process runs with `cwd = ~/.gemini/config/`, breaking `Gitx.root` in `hooks.ml`):**
  - Per `agy-customizations/docs/hooks.md:131`, command hooks execute with `$PWD` set to the directory containing `hooks.json`. Once `hooks.json` lives in `~/.gemini/config/hooks.json`, `Gitx.root` would resolve to `~/.gemini/config/` instead of the target repo, breaking `load_registry ()`, `run_dir`, and `emit` in `hooks.ml`.
  - **Settled in `global.2`:** Resolve `gate_root` from `payload.cwd` (falling back to `payload.workspacePaths[0]`, then `Gitx.root`) and explicitly re-root git/registry/run operations in `hooks.ml` onto `gate_root` (never trusting process `$PWD`). Proved in `test/hooks.sh` by invoking `bp3 q hooks` from `cd /tmp` with `"cwd": "$repo"` in the stdin payload.
- **Attack 2 (Critical — installing global hooks into `~/.claude/settings.json` or `~/.gemini/config/hooks.json` could clobber user-defined hooks):**
  - Today `bin/bp3:247-249` replaces `.hooks` wholesale in repo-local `.claude/settings.json`. Doing that on `~/.claude/settings.json` would destroy unrelated user hooks.
  - **Settled in `global.1`:** `jq` merges ONLY the `"bp3"` key in `~/.gemini/config/hooks.json` and upserts ONLY entries matching `bp3 q hooks` inside each event array of `~/.claude/settings.json`, preserving all other hooks and settings keys. Proved in `test/skills.sh` with planted custom hooks in both files.
- **Attack 3 (Major — `pi` duplicate skill discovery if `codex`/`muse` wrote to `~/.agents/skills/`):**
  - `pi` scans both `~/.pi/agent/skills/` and `~/.agents/skills/`. Writing global `CORE_SKILLS` to `~/.agents/skills/` would make `pi` see every bp3 skill twice.
  - **Settled in `global.1`:** Global targets map `agy -> ~/.gemini/config/skills`, `claude -> ~/.claude/skills`, `pi -> ~/.pi/agent/skills`, `codex -> ~/.codex/skills`, `muse -> ~/.muse/skills` — zero overlap with `pi`'s `~/.agents/skills` scan and zero `~/.pi/agent/settings.json` exclusion hacks needed.
- **Attack 4 (Major — `Makefile:35` & `scripts/check-gates:50` checking `.pi/skills`, `.agents/skills`, `.claude/skills`):**
  - Removing all skills from `bp3`'s `.agents/skills/` etc. would break `scripts/check-skills` (fails on empty dir) and force a `check-gates` rewrite.
  - **Settled in `global.1` + `skills.1`:** Keeping the 3 `DEV_SKILLS` (`add-bp3-skill`, `add-yap-skill`, `using-bp3`) repo-local inside `bp3` keeps all three dirs populated and valid, so `Makefile:35` and `scripts/check-gates:50` remain green with zero gate weakening.
- **Attack 5 (Major — existing fixture tests run in temp repos without `backpack.toml`):**
  - Making missing `backpack.toml` a hard error or mutating the tree on read would break 20+ existing fixture suites and violate Ticket `#2`'s read-only rule.
  - **Settled in `manifest.1` + `manifest.2`:** Missing `backpack.toml` is strictly read-only (`ok: true`, exit `0`, additive `warnings: [{code: "W_NO_REPO_CONFIG", ...}]`), and `missing_repo_config` is a `Minor` Warden finding. Malformed existing `backpack.toml` fails loud (`E_INVALID_CONFIG`, exit `1`).
- **Attack 6 (Major — red-chairing Ticket `#2` itself: global skills firing unprompted in non-bp3 repos):**
  - User-global skills appear in every repo's skill list, including repos that do not use `bp3`.
  - **Settled in `global.2` + `skills.1`:** Hooks hard-gate deterministically on `backpack.toml` at `gate_root` (instant no-op in non-bp3 repos), and every global `CORE_SKILL` begins with an explicit `backpack.toml` activation rule so agents stay dormant in non-bp3 repos unless explicitly asked to bootstrap via `bp3 init-repo`.

## Open questions

| # | Question | Owner | Default if untouched |
|---|---|---|---|
| 1 | Also roll out `backpack.toml` + `bp3 skills prune-local` to `~/m/esc3` after `predictor`? | owner (post-release) | Out of scope for this quest; identical 2-command rollout whenever convenient |

## Node diagram

```text
Wave 1: manifest.1 (backpack-toml-parser-and-config: CONSTRAINTS.md sign-off,
                    src/quest/backpack.ml pure parser, bp3 init-repo, bp3 config W_NO_REPO_CONFIG)
           │
           ├─────────────────────────────────────────────┐
Wave 2: manifest.2 (wire-manifest-consumers)         global.1 (global-skills-and-hooks-installer)
        q r / warden / release / brief / receipt     user-global CORE_SKILLS + non-clobber hooks,
                                                     self-local DEV_SKILLS, prune-local, install-bp3.sh
                                                         │
Wave 3:                                              global.2 (hooks-backpack-gate-and-retire-autosync)
                                                     hooks.ml gate_root re-root + backpack.toml gate,
                                                     retire auto-commit sync -> W_LOCAL_SKILLS_LEGACY
           │                                             │
           └──────────────────────┬──────────────────────┘
Wave 4: skills.1 (global-activation-prose-and-bp3-migration)
        CORE_SKILLS activation guard, bp3/backpack.toml, untrack 21 local CORE_SKILLS + legacy hooks,
        update AGENTS.md / CLAUDE.md / RELEASING.md, 25/25 suites green
```
