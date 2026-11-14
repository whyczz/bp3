---
status: proposed
home_repo: bp3
date: 2026-11-14
---

# bp3-cli-small-fixes: rendered tables, tab completion

TL;DR
The human surface of `bp3 q` stops lying: `--format table`
prints an actual table (aligned columns, header row), and
`bp3` gains shell tab completion (static verbs/edges/flags,
dynamic quest/exp names), and `bp3 q icebox r` makes frozen
entries searchable without `ls`+`grep`. JSON — the LLM
surface — does not change by one byte. Promoted from
[the bp3 CLI small fixes icebox entry](../../icebox/2026-11-14-bp3-cli-small-fixes.md);
promotion per the `quest` skill: transcription, not
adoption — everything below was re-decided in framing
(2026-11-14: owner confirmed both fixes, zsh first with
bash if cheap, flat table shapes first).

ELI5
Today `--format table` prints a YAML-shaped dump wearing a
table's name, and every quest/exp name must be typed from
memory. This quest makes the table a table and lets the
shell finish the names for you.

## Terms

| Term | One line |
|---|---|
| `--format` | the one output flag; exact values `json` (default), `table`, `tree` (`src/quest/main.ml`) |
| Door verb | `c\|r\|u\|d`, long forms `create\|read\|update\|delete`; quest door takes no `u`, exp door takes all four |
| Edge | one of `submit review check land block resume` (exact list in `do_update` dispatch) |
| Quest verdict | flat shape: `quest`, `state`, `exps[]`, `rollup`, `inbox[]` |
| Exp verdict | flat shape: `quest`, `exp`, `state`, `cycle`, `commit`, `legal_edges[]`, `changes[]` |
| Column model | per-verdict-shape ordered column list (name, source field, width rule) the table renderer renders from |
| Flat shape | a verdict whose rows are scalar fields; nested path trees are not flat and stay `tree`-only |
| Completion script | one file per shell (`_bp3` for zsh, `bp3.bash` for bash) proposing candidates per keystroke |
| Static completion | candidates fixed by the CLI grammar: door verbs, edges, flags |
| Dynamic completion | candidates read live: quest names, then that quest's exp names |
| Icebox entry | one frozen `docs/icebox/YYYY-MM-DD-<slug>.md`; not a quest, not state (`docs/icebox/README.md`) |
| Icebox door | `bp3 q icebox r`, read-only: list/search entries, or print one by slug; writes nothing |
| Help slot | a position where `-h`/`--help` prints that door's plain-text help, exit 0: after `bp3`, after `q`, after a door verb, after `<quest>` |

## Demos

### Observed — the papercut, today (2026-11-14)

```text
$ ./bin/bp3 q 2026-11-07-bp3-mvp-engine-core r exp-3-fsm --format table
ok: true
quest: 2026-11-07-bp3-mvp-engine-core
exp: exp-3-fsm
state: landed
cycle: 1
commit: 4d9ceaaac8de41a144f656fcea0a5732b77833ab
legal_edges:
changes:
  change="u" path="Makefile"
  change="u" path="bin/bp3"
```

No header row, no alignment, full 40-char commits, list
fields dumped as inline JSON. And:

```text
$ find . -iname '*completion*' -not -path './.git/*'   ->  (nothing)
```

### Design trace — what landing looks like (nothing here has run yet)

```text
$ ./bin/bp3 q 2026-11-07-bp3-mvp-engine-core --format table
quest 2026-11-07-bp3-mvp-engine-core [proposed] rollup: landed
exp                 state    cycle  commit   changes
exp-2-cli-scaffold  landed   1      4d9ceaa  +2 u5 -1
exp-3-fsm           landed   1      4d9ceaa  +2 u5 -1

$ bp3 q 2026-<TAB>          ->  quest names from `bp3 q r`
$ bp3 q <quest> r exp-<TAB> ->  exp names from `bp3 q <quest> r`
$ bp3 q <quest> u <exp> <TAB> ->  submit review check land block resume
```

## Goal and why

Frozen at the MVP landing: the owner ran the quest's
commands by hand and hit both papercuts in one sitting. The
JSON verdicts are the LLM surface and are fine; this quest
is human-surface only, and its whole value is that a human
driving `bp3 q` by hand can read a read at a glance and
never types a quest slug from memory.

## Success picture

`--format table` renders header + aligned columns for quest
reads and exp reads, plain ASCII, byte-identical JSON as
today. A zsh user who ran `bp3 init` completes quest names,
exp names, edges, and flags; completion fails silently
outside a bp3 repo or with an unbuilt binary.

## Scope

| In | Out |
|---|---|
| Table rendering for the flat shapes: quest verdict (one row per exp), exp verdict (one row per change) | exp-read `changes` path trees as tables (stay `tree`-only) |
| Column model per flat shape in `src/quest/render.ml` | any change to JSON output, verdict fields, or `--format tree` |
| zsh completion (static + dynamic); bash if cheap (same logic, recorded reason if deferred) | fish (only if asked), commit SHA / run-id completion, anything folding a ledger per keystroke |
| Delivery via `bp3 init` / `bp3 skills install` | editing the user's shell rc files; completion that errors visibly |
| `bp3 q icebox r`: list/search `docs/icebox/` entries, read one by slug (read-only) | any icebox write verb (create, promote, thaw) through `q`; parsing entries as state or pointing the ledger at them |
| `-h`/`--help` at every door (wrapper, `q`, quest door, exp door): plain text, stdout, exit 0 | help as a JSON verdict; changing any error verdict or exit code; help positions beyond the named slots |

## Human touchpoints

Quest approval (this file — approval also sets the icebox
entry's `promoted:` to this quest, per the `quest` skill);
the bash cheap/not-cheap call in Exp 2 if it comes to that.

## Exps

### Exp 1 — [Rendered tables](experiments/exp-1-rendered-tables/EXPERIMENT.md)
`--format table` gets a column model per flat shape:
header row, aligned ASCII columns, short commits, change
counts instead of inline JSON dumps. JSON and tree output
untouched. Depends on: none. Lane: standard.

### Exp 2 — [Tab completion](experiments/exp-2-tab-completion/EXPERIMENT.md)
One completion script per shell (zsh required, bash if
cheap): static verbs/edges/flags, dynamic quest/exp names
from a fast `bp3 q` read, silent failure everywhere else.
Delivered by `bp3 init` / `bp3 skills install`. Depends
on: none (parallel with Exp 1; both touch `bin/bp3` only
if Exp 2's delivery lands there — sequence Exp 1 first if
so). Lane: standard.

### Exp 3 — [Icebox search](experiments/exp-3-icebox-search/EXPERIMENT.md)
`bp3 q icebox r [term...]` lists/searches frozen entries;
`bp3 q icebox r <slug>` prints one in full. Read-only —
first filesystem door in the CLI, fenced to writes-nothing.
Added at framing on the owner's ask. Depends on: Exp 1
(its list is a flat shape; JSON works standalone).
Lane: standard.

### Exp 4 — [Help flags](experiments/exp-4-help/EXPERIMENT.md)
`-h`/`--help` at every door prints that door's docstring
help (plain text, stdout, exit 0); error verdicts unchanged.
Docstrings live beside dispatch, with a grammar-drift
fixture — the same standard the owner just added to
`code-writer` step 5. Added at framing on the owner's ask.
Depends on: none. Lane: standard.

## Scorecard

| Field | Value |
|---|---|
| Wall time | unmeasured until Runs record it |
| Context tokens | unmeasured per-Run until hooks tally them |
| Human-active minutes | approval + driving both demos by hand once |

## Risks and red chair

Red-chair pass at framing (2026-11-14), strongest attacks
and what they changed:

| Attack | Change it made |
|---|---|
| Nobody reads tables — LLMs eat JSON, humans copy the tree | scope cut to the two flat shapes humans actually scan (quest read, exp read); tree keeps the nested shapes |
| A column model ossifies a young verdict shape | columns derive from the existing verdict fields only; no new fields, JSON contract untouched, so a shape change is a column-list edit |
| Dynamic completion spawns the OCaml binary per keystroke | accepted with the icebox's own bound: `bp3 q r` reads refs/folds in tens of ms, never a ledger fold per keystroke beyond the read itself; silent failure is an acceptance case, not a hope |
| "bash if cheap" is an escape hatch that never lands | Exp 2's acceptance gates on zsh alone; bash lands or is deferred with a recorded reason in the exp record — either outcome is checkable |
| The icebox promotion trigger has not observably fired | recorded as Open question 1 instead of laundered into a claim; the owner directed this promotion directly |
| Exp 3 is scope creep: a "small fixes" quest growing a new door | priced honestly in its record: it is new function, kept read-only and dumb-parsing; if approval balks, it splits into its own quest with no damage to Exps 1–2 |
| Help text drifts from the grammar within a month | hand-written docstrings are accepted only with the drift fixture (every verb/edge/flag in help asserted against `main.ml`, both directions); deriving help from the parser was priced and rejected as a grammar refactor |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Promotion trigger not observed: no second hand-driven review asking for the table, no recorded name mistakes this session. Owner directed the thaw anyway — promotion proceeds on that instruction, trigger recorded unmet. | human (directed 2026-11-14) |
| 2 | Is `promoted:` set on the icebox entry at this Quest's approval, per the `quest` skill? | human (approval does it) |
