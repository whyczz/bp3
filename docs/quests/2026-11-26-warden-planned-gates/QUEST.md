---
status: proposed
home_repo: bp3
date: 2026-11-26
bump: minor
---

# warden-planned-gates: distinguish planned owner-gate blocks & touchpoints from unplanned `human_steer`

TL;DR
Add `--planned` to `bp3 q <quest> n <node> e block` (recorded as `"planned": true` in `ledger.jsonl`), pass `node_kind` (`--kind human-gate` etc.) into `Warden.node_evidence`, suppress `human_steer` findings for planned blocks, `human-gate` nodes, and Layer-2 `USER_INPUT` messages arriving inside planned `[block_ts, resume_ts]` windows, and report intentional owner gates separately via `planned_gates` in `bp3 warden` output.

ELI5
Right now, `bp3 warden` treats every `e block` and every mid-node chat message from the human as a `Major human_steer` defect — even when the quest *planned* to pause for AV approval or an overnight live production smoke run. This quest lets an agent mark intentional holds with `e block --planned`, teaches Warden about `--kind human-gate` nodes and planned block windows, and separates planned owner check-ins (`planned_gates`) from unplanned mid-node steering (`human_steer`).

## Context

Origin: Ticket `#3` (filed from `predictor`, 2026-11-26):
> During predictor quest `2026-11-24-kalshi-paper-desks` (`node-paper-8-paper-smoke`), `bp3 warden` emitted major `human_steer` findings for an intentional owner-gated `e block` (waiting for human AV approval and a 12h overnight live prod smoke run) and user operational check-in messages. Consider tagging planned owner-gate blocks or touchpoint nodes so warden separates planned human gates from unplanned mid-node steering.

Owner decision (2026-11-26):
- Support **both**: (1) treat `--kind human-gate` nodes (landed in `v0.11.0`) as planned owner gates, AND (2) add `--planned` to `e block` (ledgered as `"planned": true`) so intentional mid-node holds and operational check-ins inside `[block_ts, resume_ts]` are separated from `Major human_steer`.

Measured ground (audited 2026-11-26 on `master` `7f3ee886`, `v0.12.0`):

| Fact | Source |
|---|---|
| `Cli.flags` and `Cli.parse_flags` have no `--planned` flag; passing `--planned` fails with `E_USAGE: unknown flag: --planned` | `src/quest/cli.ml:7-84`, `src/quest/names.ml:79-96` |
| `Main.do_update` (`| "block" ->`) emits `ledger_line` with no `"planned"` key and returns `human_action_required: true` with no `"planned"` field | `src/quest/main.ml:489-497` |
| `Warden.node_evidence` carries `ne_node`, `ne_state`, `ne_entries`, `ne_samples`, with no `ne_kind`; `Warden_io.load_quest` folds `Store.fold_node` and discards `s.node_kind` | `src/warden/warden.ml:38-43`, `src/warden/warden_io.ml:193-197` |
| `Warden.plug_human_steer_block` flags every non-refused `block` edge or `to: blocked` as `Major human_steer` | `src/warden/warden.ml:376-388` |
| `Metrics.author_spans` intentionally skips `resume` when finding an author window's start (`x.e_edge <> "resume"`), so an author span across `block -> resume -> handoff` includes the entire blocked interval `[block_ts, resume_ts]` | `src/quest/metrics.ml:167-175` |
| `Warden.plug_human_steer_session` flags every `jt_user_steps` entry inside an author window as `Major human_steer`, with zero filtering for `human-gate` nodes or planned block intervals | `src/warden/warden.ml:497-511` |

## Terms

| Term | Meaning |
|---|---|
| `flag_planned` | `"--planned"` in `src/quest/names.ml` — boolean CLI flag accepted only on `e block` |
| `le_planned` | `bool` field on `Warden.ledger_entry`, parsed from JSON `"planned"` (defaults to `false` on legacy ledgers) |
| `ne_kind` | `string` field on `Warden.node_evidence` (`"code" \| "direct" \| "research" \| "explore" \| "human-gate"`), loaded from `Store.node_kind_to_string s.node_kind` |
| `planned_block_windows` | pure function `Warden.ledger_entry list -> (float * float) list` pairing each non-refused planned `block` timestamp with the next non-refused `resume` / `land` / `delete` timestamp (or `Float.infinity` if still blocked) |
| `planned_gates` | additive integer field in `bp3 warden` JSON/table output counting intentional owner gates across scanned quests (non-refused `approve` edges on `human-gate` nodes + non-refused planned `block` edges) |
| `human_steer` | existing `Major` Warden rule covering **unplanned** `block` edges, cycle-cap `to: blocked` escalations, and Layer-2 mid-node `USER_INPUT` messages outside planned block windows on non-`human-gate` nodes |

## Inputs

| Input | Source & precedence |
|---|---|
| `bp3 q <quest> n <node> e block [--planned] --reason <why>` | `bp3 q` CLI door; `--planned` rejected with `E_USAGE` on any edge other than `block`, and duplicate `--planned` rejected with `E_USAGE` |
| Node `ledger.jsonl` entries | `"planned": true` on planned `block` lines; `"node_kind": "human-gate"` on `create` lines; absent `"planned"` folds to `false` (100% backward-compatible with existing ledgers) |
| `Tx.joined_trace.jt_user_steps` | `(step_or_line, epoch_s) list` collected by `Metrics_io.joined_traces` for Layer-2 `author` traces |

## Outputs

| Output | Shape |
|---|---|
| `e block --planned` ledger line | existing `block` JSONL line plus `"planned": true` (omitted when unplanned so legacy ledgers stay unchanged) |
| `e block` verdict JSON | existing schema plus `"planned": bool` (`true` iff `--planned` was passed) |
| `bp3 q <q> n <n> r` / `state.yaml` | surfaces `blocked_planned: true` when currently `blocked` via `--planned` |
| `bp3 warden` JSON verdict | existing schema plus `"planned_gates": <int>` (additive); clean quests with only planned gates produce `"findings": []` and `"planned_gates": N` |
| `bp3 warden` table output | appends `planned_gates: N` to summary header when `N > 0` |
| `completions/_bp3`, `completions/bp3.bash` | advertise `--planned` on `block` edge |
| `skills/{using-bp3,warden,induct,induct-yolo}/SKILL.md` | document `e block --planned`, `--kind human-gate`, and Warden's `planned_gates` vs `human_steer` separation |

## Acceptance gates

Observed today (2026-11-26, `master` `7f3ee886`, `v0.12.0`):

```text
$ ./bin/bp3 q demoq n n1 e block --planned --reason "AV approval"
{"ok":false,"error":{"code":"E_USAGE","facts":{"detail":"unknown flag: --planned"},"guidance":"Fix the call: unknown flag: --planned"}}
$ grep -n "le_planned\|ne_kind\|planned_gates" src/warden/warden.ml src/warden/warden_io.ml
# 0 matches
```

Design trace (after quest lands):

```text
gate.1    # planned block recorded cleanly; misuse rejected
          bp3 q demoq n node-smoke e block --planned --reason "waiting on AV approval + 12h live smoke"
          -> {"ok":true,"state":"blocked","planned":true,"human_action_required":true,...}
          bp3 q demoq n node-smoke e handoff --planned --commit HEAD --reason "bad"
          -> {"ok":false,"error":{"code":"E_USAGE",...}}

gate.2    # Warden separates planned owner gates from unplanned human_steer
          # Case A: code node with e block --planned at t=100, USER_INPUT check-ins at t=150 & t=200, e resume at t=300, handoff at t=400
          bp3 warden demoq --format json
          -> {"ok":true,"planned_gates":1,"findings":[]}

          # Case B: same node, plus an unplanned USER_INPUT steer at t=350 (after resume)
          bp3 warden demoq --format json
          -> {"ok":true,"planned_gates":1,"findings":[{"rule":"human_steer","layer":"session","severity":"major","observed":"1 mid-node user inputs",...}]}

          # Case C: unplanned e block (no --planned) OR cycle-cap auto-escalation to blocked
          bp3 warden demoq --format json
          -> {"ok":true,"planned_gates":0,"findings":[{"rule":"human_steer","layer":"git","severity":"major",...}]}

          # Case D: --kind human-gate node with USER_INPUT + e approve
          bp3 warden demoq --format json
          -> {"ok":true,"planned_gates":1,"findings":[]}

skills.1  # skill docs updated and verified
          make check-full -> 25/25 suites pass
```

## Goal and why

Keep `bp3 warden`'s `human_steer` signal sharp and trustworthy. When planned owner gates (AV approvals, live overnight smoke checks, `human-gate` nodes) trigger false-positive `Major human_steer` findings, owners start ignoring `human_steer` findings altogether and miss real mid-node drift. Separating intentional owner waits from unplanned steering preserves a zero-noise audit signal.

## Success picture

- `bp3 q <q> n <n> e block --planned --reason "..."` records `"planned": true` in `ledger.jsonl`, exposes `"planned": true` in the verdict and node read while blocked, and rejects `--planned` on non-`block` edges with `E_USAGE`.
- `bp3 warden` reports `0` `human_steer` findings for `--kind human-gate` nodes, for `e block --planned` edges, and for Layer-2 `USER_INPUT` steps timestamped inside `[block_ts, resume_ts]` of a planned block.
- `bp3 warden` still fires `Major human_steer` for unplanned `e block`, cycle-cap `to: blocked` escalations, and any Layer-2 `USER_INPUT` outside planned block windows on non-`human-gate` nodes.
- `bp3 warden` surfaces `planned_gates` count in JSON/table output so planned owner touchpoints remain auditable without inflating defect counts.
- `make check-full` passes with unit, property-based (QCheck2), and CLI/fixture coverage.

## Scope

| In | Out |
|---|---|
| `--planned` flag on `bp3 q ... e block` (`names.ml`, `cli.ml`, `main.ml`, `store.ml`, `render.ml`, completions) | Changing `Metrics.author_spans` window computation or rewriting existing historical ledgers |
| `ne_kind` & `le_planned` in `Warden` / `Warden_io` | Adding LLM-based classification of user check-in messages (stays 100% deterministic) |
| Filtering Layer-1 & Layer-2 `human_steer` against `human-gate` and `planned_block_windows` | Fuzzy grace buffers outside `[block_ts, resume_ts]` (strict ledger timestamps only; see Red Chair) |
| Additive `planned_gates` count in `bp3 warden` JSON/table output | Changing `human_steer` severity or retiring the plug |
| Skill docs update (`using-bp3`, `warden`, `induct`, `induct-yolo`) as its own node | Retroactively patching `predictor`'s already-landed `ledger.jsonl` |

## Human touchpoints

- **Quest approval (before `induct`):** owner approves this quest file (`proposed -> active`).
- **Promotion (`bp3 release`):** owner runs `BP3_DECIDER=human bp3 release 2026-11-26-warden-planned-gates` after Warden audit & demo.

## Nodes

### Milestone: gate

### gate.1 - planned-block-flag
Add `--planned` to `bp3 q ... e block` (strict flag parsing, `"planned": true` in `ledger.jsonl`, verdict & blocked-state surface, shell completions, unit + CLI tests). — [NODE.md](nodes/node-gate-1-planned-block-flag/NODE.md)

### gate.2 - warden-planned-gate-plugs
Wire `ne_kind` and `le_planned` into `Warden` / `Warden_io`, suppress `human_steer` for `human-gate` nodes and planned `[block_ts, resume_ts]` windows, emit additive `planned_gates` count, and cover with unit, QCheck2, and fixture tests. — [NODE.md](nodes/node-gate-2-warden-planned-gate-plugs/NODE.md)

### Milestone: skills

### skills.1 - document-planned-block-and-warden-gates
Document `e block --planned`, `--kind human-gate`, and Warden's `planned_gates` vs `human_steer` distinction across `skills/{using-bp3,warden,induct,induct-yolo}/SKILL.md` (plus repo-local `using-bp3` renders) and guard in `test/skills.sh`. — [NODE.md](nodes/node-skills-1-document-planned-block-and-warden-gates/NODE.md)

## Scorecard

| Metric | Target |
|---|---|
| False-positive `human_steer` on planned `e block --planned` + in-window check-ins | `0` |
| False-positive `human_steer` on `--kind human-gate` nodes | `0` |
| True-positive `human_steer` on unplanned `e block`, cycle-cap escalation, or post-resume steer | `100%` detected |
| `make check-full` | `100%` green |

## Risks and red chair

- **Constraints pass (`CONSTRAINTS.md`):** **None.** Pure OCaml (`stdlib`, `yojson`, `ounit2`, `qcheck-core`) + Bash/Zsh completions + Markdown skills. Zero new languages, libraries, or surfaces.
- **Common-sense pass (`CONTEXT.md`):** Aligns with `Q1` ("exact work lives in deterministic scripts and judgment in the agent, and the two never mix") and `Q2` (ledger is append-only truth; Warden derives facts deterministically from ledger + transcript timestamps rather than asking an LLM to guess whether a user message was a "check-in" or a "steer").
- **Opening attack & source red chair (Ticket #3):**
  1. *Gaming risk (Major):* Could a sloppy author pass `--planned` on an unplanned block to hide real `human_steer`? **Settled in design:** (a) every planned block still requires an explicit `--reason` recorded immutably in `ledger.jsonl` AND increments the visible `planned_gates` counter in `bp3 warden` output so an unexpected `planned_gates > 0` jumps out during Warden review; (b) automatic cycle-cap escalations on `grade` (`to: blocked`) never set `planned: true`; (c) `skills.1` explicitly instructs agents to pass `--planned` only for gates declared in `QUEST.md`'s `Human touchpoints` or `NODE.md`.
  2. *Boundary timing risk (Minor):* What if an owner runs `BP3_DECIDER=human bp3 q ... e resume` in a separate terminal *before* typing `"resumed, carry on"` in the agent session (so that single wake-up message lands a few seconds *after* `resume_ts`)? **Settled in design:** Keep `[block_ts, resume_ts]` strictly bounded by ledger timestamps in v1 (zero magic grace seconds that could mask real post-resume steering); if live usage shows external-shell resumes causing noise, follow up in a tiny patch or recommend resuming *after* sending the wake-up prompt (or using a dedicated `--kind human-gate` node).
  3. *Boring alternative check:* Why not ONLY use `--kind human-gate` and skip `--planned`? Because long-running operational nodes (like `predictor`'s `node-paper-8-paper-smoke`: start live paper desk -> wait for AV approval + 12h overnight run -> collect logs & handoff commit) legitimately pause mid-node and resume on the same node; forcing a split into 3 nodes adds friction when one flag (`e block --planned`) cleanly models the mid-node hold.

## Open questions

None blocking `induct`. (Post-resume external-shell wake-up timing is deliberately kept strict `[block_ts, resume_ts]` in v1; revisit only if observed in real runs — owner: `whycz`.)

## Node diagram

```text
Cohort 1:  [ gate.1 - planned-block-flag ]  (code)
                         |
                         v
Cohort 2:  [ gate.2 - warden-planned-gate-plugs ]  (code)
                         |
                         v
Cohort 3:  [ skills.1 - document-planned-block-and-warden-gates ]  (code)
```
