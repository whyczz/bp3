---
status: landed
home_repo: bp3
date: 2026-11-27
bump: minor
---

# declarative-json-quest-init: atomic `bp3 q c --file <quest.json>` and structured JSON brief gates (ticket #12)

TL;DR
Let quests be defined once in a typed `quest.json` file (`docs/quests/<quest>/quest.json`) and initialized atomically with `bp3 q c <quest> --file <path>` (validating the entire graph, kinds, deps, explore targets, and bump before writing a single ref). When `quest.json` exists at `<commit>`, `Brief.render` reads structured acceptance gates (`objective`, `prove_by`, `done_when`, `trace`) directly from JSON instead of scraping markdown headings, and `handoff` protects `quest.json` under `E_PROTECTED_FILE`. Legacy markdown-only quests and imperative `bp3 q c` remain 100% supported.

ELI5
Right now spinning up a 7-node quest means running 8+ sequential `bp3 q c` CLI calls by hand and hoping every `NODE.md` spelled `## Acceptance gates` identically so cold-grader briefs don't silently drop the gates. This quest lets you encode the whole quest graph — metadata, bump, nodes, kinds, dependencies, and structured acceptance gates — in one clean `quest.json` file, validate it all at once, initialize every branch in one command, and render cold-grader briefs straight from typed JSON instead of fragile markdown heading regexes.

## Context

Originated from `predictor` Ticket `#12` (2026-11-27, after `2026-11-25-house-spec-ir` hit heading fragility across all 7 `NODE.md` files and paid iterative `bp3 q c` setup loops).

Measured ground (read 2026-11-27 at `22090aef`):
- `src/quest/main.ml:45-171`: `do_quest_create` creates only the quest branch; each node requires a separate `bp3 q <quest> c <node> [--kind ...] [--depends-on ...]` call (each spawning 6 git plumbing commands).
- `src/quest/brief.ml:70-109`: `Brief.render` reads `docs/quests/<q>/nodes/<n>/NODE.md` and splits lines looking for `## Acceptance gates` (`## Acceptance test` fallback added in `2026-11-27-predictor-tickets-bundle`).
- `src/quest/store.ml:470-480`: `protected_files_for` locks `GRADING.md`, `CONSTRAINTS.md`, `scripts/receipt`, `scripts/red-first`, and the node's own `NODE.md` — it does not yet lock `quest.json`.
- `CONSTRAINTS.md`: `yojson` is already an approved OCaml library, `.json` is already in `data ext`, and `bp3 q` is already an approved CLI surface (zero new libraries or top-level doors required when wired as `bp3 q c <quest> --file <path>`).

## Terms

| Term | Meaning |
|---|---|
| `quest.json` | declarative JSON quest specification (schema `version: 1`) committed at `docs/quests/<quest>/quest.json`, holding quest metadata (`quest`, `title`, `tldr`, `goal_type`, `bump`, `home_repo`, `depends_on`) and the typed `nodes[]` DAG with structured `acceptance` |
| `Quest_spec` | pure OCaml module (`src/quest/quest_spec.ml`) parsing and validating `quest.json` (schema version, slugs, kinds, explore `--target` / `--max-iterations`, bumps, duplicate node IDs, unknown deps, and DAG cycles via `Store.dep_cycle_through`) |
| `E_INVALID_SPEC` | typed refusal (exit `1`) emitted when `quest.json` is malformed JSON, fails schema/field validation, names an unknown dep, or contains a dependency cycle — always raised BEFORE any git ref is written |
| `--file <path>` | flag on `bp3 q c [<quest>] --file <path>` that atomically validates `quest.json` and creates the quest branch plus every declared node branch in topological order |
| `--scaffold` | optional flag on `bp3 q c [<quest>] --file <path> --scaffold` that renders human-readable `docs/quests/<quest>/QUEST.md` and `nodes/<id>/NODE.md` (with guaranteed `## Acceptance gates` headings) in the working tree from `quest.json` |

## Inputs

| Input | Source | Precedence / Notes |
|---|---|---|
| `bp3 q c [<quest>] --file <path> [--scaffold]` | CLI quest create (`bp3 q` door) | if `<quest>` positional is supplied, it must match `quest.json`'s `"quest"` field (else `E_INVALID_SPEC`); if omitted, taken from `quest.json` |
| `quest.json` (`version: 1`) | local path passed to `--file` (and committed at `docs/quests/<quest>/quest.json`) | validated completely in memory before any branch is created |
| `docs/quests/<quest>/quest.json` at `<commit>` | `Brief.inputs` (`git show <commit>:...`) | when present and carrying the node's `acceptance` object, takes precedence over markdown `NODE.md` heading extraction; falls back to `NODE.md` when absent |

## Outputs

| Output | Shape |
|---|---|
| atomic create verdict | `{"ok": true, "quest": "<q>", "state": "proposed", "spec": "<path>", "nodes": [{"node": "...", "kind": "...", "deps": [...], "legal_edges": [...]}], "scaffolded": [...]}` |
| `E_INVALID_SPEC` verdict | `{"ok": false, "error": {"code": "E_INVALID_SPEC", "facts": {"file": "...", "errors": [...]}, "guidance": "..."}}`, exit `1`, **zero refs mutated** |
| JSON-backed cold brief | `Brief.render` renders `Acceptance gates (quest.json at <sha>):` with structured `objective`, `prove_by`, `done_when`, and optional `trace` |
| `E_PROTECTED_FILE` on `quest.json` | `Code`/`Direct` handoff refuses edits to `docs/quests/<quest>/quest.json` unless `--allow-protected` is passed; `Research`/`Explore` runs a JSON diff guard allowing edits ONLY to non-self `todo` node entries in `quest.json` (refusing quest metadata or own/non-`todo` node changes with `E_PROTECTED_FILE`) |

## Acceptance gates

Observed today (2026-11-27 at `22090aef`):

```text
$ ./bin/bp3 q c demo --file /tmp/quest.json
-> exit 2, E_USAGE: unknown flag: --file
```

Design trace (after quest lands):

```text
spec.1     Quest_spec.parse_string rejects missing fields, bad kinds, explore without target, unknown dep, or dep cycle with E_INVALID_SPEC
           Brief.render with docs/quests/demo/quest.json at <commit> renders structured acceptance gates directly from JSON
           Store.protected_violations locks docs/quests/demo/quest.json on handoff unless --allow-protected

init.1     $ bp3 q c demo --file docs/quests/demo/quest.json
           -> exit 0, creates bp3/quest/demo + all declared nodes in topological order in one call
           $ bp3 q c bad --file /tmp/cyclic-quest.json
           -> exit 1, E_INVALID_SPEC (zero bp3/quest/bad or bp3/node/bad/* refs created!)
           $ bp3 q c demo --file docs/quests/demo/quest.json --scaffold
           -> also writes docs/quests/demo/QUEST.md and nodes/*/NODE.md with `## Acceptance gates`

skills.1   skills/{quest,red-ink,using-bp3}/SKILL.md, AGENTS.md/CLAUDE.md, local DEV_SKILLS, completions, and test/{skills,completion}.sh synced;
           make check-full rc 0
```

## Goal and why

Prefer typed, machine-validated JSON over brittle markdown parsing and multi-turn `bp3 q c` loops (`CONTEXT.md:35` — *"Agents are less likely to inappropriately change or overwrite JSON files compared to Markdown files"*). One declarative `quest.json` gives atomic graph validation, single-command initialization, and zero-drift cold-grader briefs while staying 100% compatible with existing markdown quests and the upcoming `2026-11-23-sqlite-quest-store`.

## Success picture

- Authoring a multi-node quest takes **1** atomic command (`bp3 q c <quest> --file docs/quests/<quest>/quest.json`) instead of `1 + N` imperative CLI calls.
- Invalid graphs (cycles, unknown deps, missing explore targets, bad kinds/bumps) fail fast with `E_INVALID_SPEC` and leave **zero** partial branches behind.
- Cold-grader briefs render structured acceptance gates straight from `quest.json` at `<commit>`, eliminating markdown heading drift permanently.
- `handoff` protects `quest.json` under `E_PROTECTED_FILE` so agents cannot silently weaken acceptance gates.
- `make check-full` passes with unit, QCheck2, fixture, completion, and skill tests.

## Scope

| In | Out |
|---|---|
| Pure OCaml `Quest_spec` v1 parser/validator (`E_INVALID_SPEC`), `Brief` JSON acceptance rendering, and `quest.json` protected-file lock (`spec.1`) | New top-level `bp3 quest` CLI door (stays inside signed `bp3 q` door unless owner signs off `CONSTRAINTS.md` — see Open question #1) |
| Atomic `bp3 q c [<quest>] --file <path> [--scaffold]` CLI wiring, topological node creation, completions, and fixture tests (`init.1`) | Migrating historical markdown-only quests to `quest.json` (legacy quests keep working as-is) |
| Updating `skills/{quest,red-ink,using-bp3}/SKILL.md`, `AGENTS.md`/`CLAUDE.md`, local `DEV_SKILLS`, completions, and `test/{skills,completion}.sh` (`skills.1`) | Quest-scoped `scratchpad.jsonl` (Ticket `#13` — separate quest/storage decision alongside `sqlite-quest-store`) |

## Constraints at approval

- **Constraints pass (`CONSTRAINTS.md`):** Zero new languages or libraries (`yojson` and `.json` are already in `CONSTRAINTS.md`). Wiring under `bp3 q c [<quest>] --file <path>` adds **zero** new CLI surfaces. *(If the owner prefers top-level `bp3 quest <name> init --file=...`, that adds a new surface in `CONSTRAINTS.md` and requires a Sign-off log row before `init.1`.)*
- **Common-sense pass (`CONTEXT.md`):**
  - *JSON over Markdown for structured agent state (`CONTEXT.md:35`)*: Anthropic's long-running harness finding directly backs moving structured quest graphs & acceptance gates into JSON while keeping human prose in `QUEST.md`.
  - *Deterministic checks beat model judgment (`CONTEXT.md:96`)*: validating cycles, missing deps, explore targets, and acceptance fields up front at init time catches malformed quests in milliseconds instead of mid-`induct`.
  - *Goodhart's law (`CONTEXT.md:81`)*: adding `quest.json` to `protected_files_for` prevents agents from editing structured gates without `--allow-protected`.

## Human touchpoints

| When | Owner |
|---|---|
| Settle Open questions 1–3 (or run `/red-ink`) and approve quest frame | owner |
| Promote via `bp3 release` at `goal_fin` and close Ticket `#12` | owner |

## Nodes

### Milestone: spec

| Node | TL;DR |
|---|---|
| [spec.1 - json-quest-schema-and-brief](nodes/node-spec-1-json-quest-schema-and-brief/NODE.md) | pure `Quest_spec` v1 parser/validator (`E_INVALID_SPEC`), `Brief` JSON acceptance gate rendering, `quest.json` protected-file lock, and unit/QCheck2 tests |

### Milestone: init

| Node | TL;DR |
|---|---|
| [init.1 - atomic-json-quest-create](nodes/node-init-1-atomic-json-quest-create/NODE.md) | wire `bp3 q c [<quest>] --file <path> [--scaffold]` with all-or-nothing validation, topological creation, completions, and `test/g.sh` fixtures |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - json-quest-skills-and-completions](nodes/node-skills-1-json-quest-skills-and-completions/NODE.md) | sync `skills/{quest,red-ink,using-bp3}/SKILL.md`, `AGENTS.md`/`CLAUDE.md`, local `DEV_SKILLS`, completions, and `test/{skills,completion}.sh` |

## Scorecard

| Row | Baseline (2026-11-27) | Target | Read from |
|---|---|---|---|
| CLI calls to initialize a 7-node quest | 8+ (`q c` + 7x `q <q> c`) | **1** (`bp3 q c --file quest.json`) | `test/g.sh` |
| Partial refs left on invalid quest spec | possible mid-loop | **0** (all-or-nothing pre-validation) | `test/g.sh` |
| Cold brief gate source for JSON quests | markdown H2 scraping | **typed `quest.json`** (zero heading drift) | `test/unit/test_brief.ml` |

## Risks and red chair

- **Strongest attack (two sources of truth — `quest.json` vs `QUEST.md` / `NODE.md` drifting apart):** "If a repo commits both `quest.json` and `QUEST.md`/`NODE.md`, someone edits `NODE.md` while `Brief.render` reads `quest.json` (or vice versa), creating silent spec drift."
  - **Settled in design:** `quest.json` is explicitly the **single source of truth** for machine-read structure (graph, kinds, deps, acceptance gates, bump). `QUEST.md` / `NODE.md` (when scaffolded via `--scaffold`) carry a generated banner pointing back to `quest.json` and hold optional human context/prose; `Brief.render` clearly labels its source (`Acceptance gates (quest.json at <sha>):` vs `Acceptance gates (NODE.md at <sha>):`) so drift is never silent.
- **Second attack (`Research`/`Explore` nodes refining downstream `todo` specs in `quest.json`):** "In `v0.12.0`, `Research`/`Explore` nodes are allowed to edit a downstream `todo` node's `NODE.md` while own and non-`todo` `NODE.md` stay locked. If all nodes live in one `quest.json`, editing `quest.json` could also touch a landed node's acceptance gates!"
  - **Settled (owner 2026-11-27):** `Code`/`Direct` handoff locks `docs/quests/<quest>/quest.json` under `E_PROTECTED_FILE` unless `--allow-protected`; `Research`/`Explore` handoff compares `quest.json` at `<commit>~1` vs `<commit>` in `Quest_spec.json_diff_violations` and permits edits ONLY to non-self `todo` node entries (refusing edits to quest-level metadata, own node entry, or any non-`todo` node entry with `E_PROTECTED_FILE`).
- **Third attack (`scripts/check-bump` reads `QUEST.md` frontmatter):** "`make lint` (`scripts/check-bump`) expects `bump:` in `QUEST.md`; a quest with only `quest.json` and no `QUEST.md` could trip `check-bump` or `bp3 release`."
  - **Settled in design:** `init.1` ensures `bp3 release` and `scripts/check-bump` either read `bump` from `quest.json` when present (falling back to `QUEST.md`) OR `--scaffold` generates `QUEST.md` with synced `bump:` frontmatter (and `bp3 q c --file` checks consistency if `QUEST.md` exists).

## Open questions

None — all three owner calls settled on 2026-11-27:
1. **CLI spelling (settled 2026-11-27):** `bp3 q c [<quest>] --file <path> [--scaffold]` inside the existing `bp3 q` door (`0` `CONSTRAINTS.md` surface churn).
2. **`QUEST.md` / `NODE.md` generation mode (settled 2026-11-27):** `quest.json` is the single source of truth; `--scaffold` optionally generates readable `QUEST.md` + `nodes/<id>/NODE.md` views, and `scripts/check-bump` + `bp3 release` read `quest.json` directly so markdown is optional.
3. **`Research`/`Explore` editing `quest.json` (settled 2026-11-27):** Parse `quest.json` at `<commit>~1` vs `<commit>` — allow edits ONLY to non-self `todo` node entries; refuse quest-level metadata or own/non-`todo` node changes with `E_PROTECTED_FILE` unless `--allow-protected`.

## Node diagram

```text
spec.1 (Quest_spec v1 + Brief JSON gates + lock) ──► init.1 (atomic bp3 q c --file + scaffold) ──► skills.1 (skills + completions + tests)
```
