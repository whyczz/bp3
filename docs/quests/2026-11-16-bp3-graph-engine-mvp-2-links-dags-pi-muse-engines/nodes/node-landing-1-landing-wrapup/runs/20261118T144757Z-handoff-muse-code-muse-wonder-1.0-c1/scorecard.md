# landing.1 — scorecard (observed)

Graph: `2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines`
Run: `20261118T144757Z-handoff-muse-code-muse-wonder-1.0-c1`
Source: live rollup `./bin/bp3 g <graph> r` executed in this Run
(verbatim JSON in this run's `tape.log`). Every number names its
source artifact; nothing is copied from prose about a run.

## Verdict in one line

Before: children narrated completion in briefs. After: a one-time
link binds session to Run, `bp3` resolves context from the claim,
the rollup schedules ready-sets and reports wall/wait/dwell, and
the CLI speaks graph/node/state/edge via `bp3 g | bp3 n | bp3 e`.
This record prepares the owner's promotion gate; it does not
promote.

## Scorecard — every node, evidence or unmeasured

State, cycle, commit, and timing are the live rollup's words,
quoted as returned. "Land run" is the observed `runs/` evidence
that the node executed its full edge chain.

| Node | State (rollup) | Cyc | Commit | Wall | Land run (observed) |
|---|---|---|---|---|---|
| node-config-1-bp3-config | todo | 1 | — | unmeasured (a) | `20261116T231422Z-land-…-c2` |
| node-mig-1-handoff-verbs | todo | 1 | — | unmeasured (a) | `20261116T194825Z-land-…-c1` |
| node-mig-2-traverse-rename | todo | 1 | — | unmeasured (a) | `20261116T212257Z-land-…-c2` |
| node-mvp-1-link-claim | todo | 1 | — | unmeasured (a) | `20261117T004025Z-land-…-c1` |
| node-mvp-2-context-resolution | todo | 1 | — | unmeasured (a) | `20261117T011548Z-land-…-c1` |
| node-mvp-3-ready-set-timing | todo | 1 | — | unmeasured (a) | `20261117T042701Z-land-…-c2` |
| node-mvp-4-diagram-emit | todo | 1 | — | unmeasured (a) | `20261117T044950Z-land-…-c1` |
| node-mvp-5-blocked-fail-fast | todo | 1 | — | unmeasured (a) | `20261117T060015Z-land-…-c2` |
| node-dogfood-1-link-drive | todo | 1 | — | unmeasured (a) | `20261117T063415Z-land-…-c1` |
| node-dogfood-2-parallel-drive | todo | 1 | — | unmeasured (a) | `20261117T084452Z-land-…-c2` |
| node-rename-1-bp3g-rename | todo | 1 | — | unmeasured (a) | `20261117T155529Z-land-…-c1` |
| node-followup-1-grade-evidence | todo | 1 | — | unmeasured (a) | `20261117T042103Z-land-…-c2` |
| node-followup-2-workflow-birth | todo | 1 | — | unmeasured (a) | `20261117T155359Z-land-…-c2` |
| node-followup-3-goal-term-purge | landed | 4 | `2dbe30ce3263` | 17466 s | `20261118T001519Z-land-…-c4` |
| node-followup-5-pure-grade | landed | 4 | `691547e4653d` | 16388 s | `20261118T052124Z-land-…-c4` |
| node-followup-6-check-tiers | landed | 1 | `0f60c7a50a82` | 1950 s | `20261118T060256Z-land-…-c1` |
| node-dogfood-3-external-drive | landed | 1 | `ac43954bd4e7` | 1315 s | `20261118T144632Z-land-…-c1` |
| node-landing-1-landing-wrapup | todo | 1 | this commit | — | this Run |

(a) Unmeasured, named: the rollup returns `wall_s: null` for the
14 pre-rename nodes. Their ledger lines were written under
`exp-…` IDs (and `submit` verbs); the fold maps old verbs on
read but does not re-key state/timing to the renamed `node-…`
IDs, so no wall number exists in-system. Inventing one from
run-folder timestamps would break the "no number without a
source artifact" property, so the field is named unmeasured.
The observed per-Run `setup_wall_s` values for these nodes are
in the rollup's `setup[]` array (tape.log); they run 5–124 s.

Dwell (landed nodes, seconds, from rollup `timing.dwell_s`):
followup.3 `todo 2662, handed_off 10463, blocked 4212, approved
129`; followup.5 `todo 7061, handed_off 9116, blocked 115,
approved 96`; followup.6 `handed_off 1252, approved 698`;
dogfood.3 `handed_off 1239, approved 76`.

## Named unmeasured fields (all nodes, with reasons)

| Field | Status | Reason |
|---|---|---|
| `wait_s` (create → first handoff) | unmeasured, all 18 | rollup returns `wait_s: null` for every node; no derivation exists in-system for this graph |
| wall, 14 pre-rename nodes | unmeasured | see (a) above |
| tokens per node | unmeasured | rollup has no per-node token field (dogfood.2's named cause); none invented |
| human-active minutes | unmeasured | no in-system timer exists; blocked dwell (followup.3: 4212 s) is the nearest observed proxy, not a substitute |
| setup wall | observed | rollup `setup[]`: 5–316 s typical; two slow outliers — followup.3 verify c4 `316 s` and dogfood.3 handoff c1 `1963 s` — rollup carries `W_SETUP_SLOW` |

## Dogfood numbers (from the nodes' own run notes)

A/B (dogfood.1, `test/dogfood-link.sh`, observed): brief chars
old 425 vs link-muse 70, link-pi 68. Attacks refused before
work: duplicate claim `E_LINK_SPENT`, quoting claim
`E_NOT_FOUND`, wrong-desk `bp3 e` `E_NO_CONTEXT`; zero setup
cycles burned.

Ready-set (dogfood.2, `test/dogfood-parallel.sh`, observed):
ready wall 3955 ms vs serial sum 6890 ms (cycle 1); 3982 ms vs
6970 ms (cycle 2). Per-node rollup wall 2 s each. Bubble proof:
`pi_bubble: blocked, claude_bubble: blocked, claude_fresh:
landed, sibling_claude: landed`.

## Acceptance mapping

| Case | Result |
|---|---|
| scorecard complete | met — all 18 nodes above; unmeasured fields named with reasons |
| findings dispositioned | met — `disposition.md`, 100% with homes |
| walkthrough run | met — `walkthrough.md`, executed in this Run, outputs quoted |
| diagrams included | met — ascii + mermaid from the live rollup in `walkthrough.md` |
