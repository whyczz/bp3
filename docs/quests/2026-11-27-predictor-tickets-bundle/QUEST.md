---
status: landed
home_repo: bp3
date: 2026-11-27
bump: patch
---

# predictor-tickets-bundle: brief heading fallback + red-ink/induct skill polish (tickets #7, #8, #9, #10, #11a)

TL;DR
Close the five zero-conflict `predictor -> bp3` tickets that do not touch `src/warden/` in one crisp patch release (`v0.12.1`): accept `## Acceptance test` as a fallback heading in `Brief.render` (Ticket `#10`), require explicit owner LGTM between `/red-ink` slices (`#7`), add an explicit **Layout** check to `/red-ink` Internals (`#8`), align `red-ink`'s node template to `## Acceptance gates` (`#10`), retire `/swarm` parallel-coder mode from `/induct` (`#9`), and default c2+ mechanical delta re-grades to `Model: "flash"` (`#11` part 1).

ELI5
While running quests in `predictor`, five small harness papercuts showed up: cold briefs missed acceptance gates whenever a `NODE.md` used `## Acceptance test` (the exact heading `red-ink` had in its own template!), `/red-ink` kept auto-advancing to the next slice without waiting for an "lgtm" and skipped reviewing directory layout, `/induct` still carried retired `/swarm` instructions, and mechanical c2+ delta re-grades burned `inherit` tokens instead of `flash`. This two-node patch quest fixes the OCaml brief parser and updates the skills cleanly.

## Context

Bundled from five open cross-repo tickets filed by `predictor` on 2026-11-27 (`bp3 ticket list --to bp3`):
- **Ticket `#7`**: `red-ink`: require explicit owner LGTM (`lgtm`/`okay`/`next`) before advancing to the next slice.
- **Ticket `#8`**: `red-ink`: make repo file/directory Layout (`before -> after`) an explicit part of the Internals walk.
- **Ticket `#9`**: `induct`: remove retired `/swarm` parallel-coder mode from `skills/induct/SKILL.md` (and verify `red-ink`/`quest` don't push parallel waves by default).
- **Ticket `#10`**: `brief.ml` heading mismatch (`## Acceptance test` vs `## Acceptance gates`) — root-caused directly to `skills/red-ink/SKILL.md:277,298` using `Acceptance test` while `skills/quest/SKILL.md:159` and `src/quest/brief.ml:74` expected `Acceptance gates`.
- **Ticket `#11` (part 1)**: default c2+ mechanical delta re-grades in `skills/induct/SKILL.md` to `Model: "flash"` (keeping `"inherit"`/`"pro"` strength on c1). *(Part 2 — turn-grouped `tool_retry_loop` in `src/warden/warden.ml` — is deliberately deferred until `2026-11-26-warden-planned-gates` lands so there is zero `src/warden/` conflict.)*

Measured ground (read 2026-11-27 at `22090aef`):
- `src/quest/brief.ml:74`: matches only `section "Acceptance gates" md`.
- `skills/red-ink/SKILL.md:13,28,126-131,217,277,298`: has no `Internals: layout` slice, auto-advances on "100% confident" without explicit owner LGTM, lists `parallel waves` in `Plan`, and writes `Acceptance test` instead of `Acceptance gates`.
- `skills/induct/SKILL.md:3,12-13,86-90,164-195`: still documents `/swarm` auto-enabled on Gemini and does not default c2+ mechanical delta re-grades to `"flash"`.
- `test/skills.sh:445-461`: pins the retired `/swarm` strings in `skills/induct/SKILL.md`.

## Terms

| Term | Meaning |
|---|---|
| `extract_gates` | pure helper in `src/quest/brief.ml` that extracts the `## Acceptance gates` section from `NODE.md`, falling back to `## Acceptance test` if absent or blank |
| `Internals: layout` | explicit slice in `skills/red-ink/SKILL.md` reviewing repo file/directory structure (authored configs, libraries, CLIs, runtime data paths — `before -> after`) right before `Internals: names` |
| explicit LGTM gate | rule in `skills/red-ink/SKILL.md` requiring explicit owner confirmation (`lgtm` / `okay` / `next`) after `Act + IIUC + Slice TL;DR` before opening the next slice |
| mechanical delta re-grade | cycle `c2+` re-grade following a `--mechanical` `needs_fix`, routed to `Model: "flash"` on `agy` instead of `"inherit"` |

## Inputs

| Input | Source | Precedence / Notes |
|---|---|---|
| `NODE.md` markdown at `<commit>` | `Brief.inputs` (`git show <commit>:.../NODE.md`) | `## Acceptance gates` takes precedence over `## Acceptance test` when both exist |
| `skills/{red-ink,induct}/SKILL.md` | repo `CORE_SKILLS` sources | rendered user-globally on `bp3 skills install` (never repo-local) |

## Outputs

| Output | Shape |
|---|---|
| `Brief.render` gates block | inlines `## Acceptance gates` (or `## Acceptance test` fallback) from `NODE.md`; keeps missing-section finding only when neither heading has content |
| updated `skills/red-ink/SKILL.md` | explicit LGTM gate (`#7`), `Internals: layout` slice (`#8`), no default parallel-wave push (`#9`), `## Acceptance gates` heading spelling (`#10`) |
| updated `skills/induct/SKILL.md` | zero `/swarm` parallel-coder instructions (`#9`), `Model: "flash"` default for c2+ mechanical delta re-grades (`#11` part 1) |
| updated `test/unit/test_brief.ml` & `test/skills.sh` | unit + property tests for heading fallback; skill tests asserting zero `/swarm` regression + new red-ink/induct rules |

## Acceptance gates

Observed today (2026-11-27 at `22090aef`):

```text
$ rg -n 'section "Acceptance' src/quest/brief.ml
74:    | Some md -> (match section "Acceptance gates" md with
$ rg -n 'Acceptance test|/swarm' skills/red-ink/SKILL.md skills/induct/SKILL.md | wc -l
      11
```

Design trace (after quest lands):

```text
brief.1   Brief.render on NODE.md containing `## Acceptance test` (no `## Acceptance gates`)
            -> inlines the Acceptance test body under `Acceptance gates (NODE.md at <sha>):` (no false finding)
          Brief.render on NODE.md containing both headings
            -> prefers `## Acceptance gates`
          Brief.render on NODE.md containing neither heading
            -> emits `(NODE.md at <sha> has no Acceptance gates section: that is a finding)`

skills.1  skills/red-ink/SKILL.md requires explicit owner LGTM before next slice, walks `Internals: layout`, uses `Acceptance gates`, drops parallel-waves default
          skills/induct/SKILL.md has zero `/swarm` references and defaults c2+ mechanical delta re-grades to `Model: "flash"`
          bp3 skills install --harness=all (isolated) && bp3 skills check -> ok
          make check-full -> 25/25 green
```

## Goal and why

Ship immediate relief for five real papercuts observed in `predictor` today without waiting on `2026-11-26-warden-planned-gates` or the larger declarative JSON quest init (`#12`).

## Success picture

- Cold briefs never drop acceptance gates just because a `NODE.md` used `## Acceptance test`.
- `/red-ink` pauses for explicit owner confirmation before advancing slices, reviews directory layout explicitly, and emits `## Acceptance gates` matching `quest` and `brief.ml`.
- `/induct` is cleanly single-session linear authoring + background cold graders (zero `/swarm` instructions) and routes c2+ mechanical delta re-grades to `"flash"`.
- `make check-full` passes with new unit and skill assertions, and Tickets `#7`, `#8`, `#9`, `#10` are ready to close on release (with `#11` part 1 done).

## Scope

| In | Out |
|---|---|
| `Brief.extract_gates` fallback for `## Acceptance test` + unit tests (`brief.1`, Ticket `#10`) | Declarative JSON quest init (`2026-11-27-declarative-json-quest-init`, Ticket `#12`) |
| `skills/red-ink/SKILL.md` (`#7`, `#8`, `#9`, `#10` heading fix) & `skills/induct/SKILL.md` (`#9`, `#11` part 1) + `test/skills.sh` (`skills.1`) | `tool_retry_loop` turn-grouping in `src/warden/warden.ml` (Ticket `#11` part 2 — deferred until `2026-11-26-warden-planned-gates` lands) |
| Keeping `test/skills.sh` and global `CORE_SKILLS` renders in sync (`skills.1`) | `scratchpad.jsonl` (Ticket `#13`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** Zero new languages, libraries, or surfaces. All edits stay in existing OCaml (`src/quest/brief.ml`), `skills/*/SKILL.md`, and existing test suites.
- **Common-sense pass (`CONTEXT.md`):**
  - *Every mistake becomes a permanent fix (`CONTEXT.md:58`)*: fixing both the parser (`brief.ml`) and the skill template (`red-ink/SKILL.md`) kills the heading-mismatch bug at both ends.
  - *Rules need pruning too (`CONTEXT.md:59`)* and *Swarms buy speed, not capability (`CONTEXT.md:43`)*: deleting the retired `/swarm` section removes ~35 lines of dead prose from `skills/induct/SKILL.md`.

## Human touchpoints

| When | Owner |
|---|---|
| Approve quest frame (zero open questions) | owner |
| Promote via `bp3 release` (`v0.12.1`) and close Tickets `#7`, `#8`, `#9`, `#10` at `goal_fin` | owner |

## Nodes

### Milestone: brief

| Node | TL;DR |
|---|---|
| [brief.1 - accept-acceptance-test-heading](nodes/node-brief-1-accept-acceptance-test-heading/NODE.md) | add `## Acceptance test` fallback in `src/quest/brief.ml` (`Acceptance gates` preferred) + unit/property tests in `test/unit/test_brief.ml` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - red-ink-and-induct-ticket-polish](nodes/node-skills-1-red-ink-and-induct-ticket-polish/NODE.md) | update `skills/red-ink/SKILL.md` (`#7`, `#8`, `#9`, `#10`), `skills/induct/SKILL.md` (`#9`, `#11a`), and `test/skills.sh` |

## Scorecard

| Row | Baseline (2026-11-27) | Target | Read from |
|---|---|---|---|
| `Brief.render` on `## Acceptance test` `NODE.md` | missing-gates finding (`0%` inlined) | **100%** inlined (fallback) | `test/unit/test_brief.ml` |
| Retired `/swarm` instructions in `skills/induct/SKILL.md` | 10 references (~35 lines) | **0** references (guarded by `test/skills.sh`) | `test/skills.sh` |
| `/red-ink` explicit LGTM gate + `Internals: layout` + `Acceptance gates` | absent / mismatched | **present & pinned** | `test/skills.sh` |

## Risks and red chair

- **Strongest attack (accepting `## Acceptance test` papers over markdown fragility instead of fixing it structurally):** "A fallback heading still relies on markdown H2 parsing; another synonym like `## Acceptance criteria` could still miss."
  - **Settled in design:** Both `skills/red-ink/SKILL.md` (the actual culprit) AND `src/quest/brief.ml` are fixed here for immediate relief, while the companion quest `2026-11-27-declarative-json-quest-init` (Ticket `#12`) eliminates markdown heading parsing structurally via `quest.json`.
- **Second attack (deleting `/swarm` assertions from `test/skills.sh` could look like weakening tests):** "Graders flag unjustified deletion of test assertions."
  - **Settled in design:** `skills.1` explicitly replaces the retired `/swarm` positive assertions in `test/skills.sh` with a strict negative assertion (`test -z "$(grep -n '/swarm' "$ic" || true)"`), proving the retired workflow cannot creep back in.

## Open questions

None — all five ticket specs are explicit owner decisions recorded in `bp3 ticket list`.

## Node diagram

```text
brief.1 (Acceptance test fallback in brief.ml) ──► skills.1 (red-ink + induct skill polish & tests)
```
