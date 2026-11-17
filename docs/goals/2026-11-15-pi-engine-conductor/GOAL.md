---
status: active
home_repo: bp3
date: 2026-11-15
---

# Pi engine conductor: induct on bare pi

TL;DR
The muse engine is proven: a conductor skill reads `bp3 q r`,
dispatches one small step per state (author, grade, land),
and children call `bp3 q u` directly. This Quest builds the
same engine on bare pi — our own thin dispatcher extension
spawning real pi processes per Run, designs plucked from
pi-subagents and oh-my-pi, nothing adopted whole. When it
lands, `/induct` runs on pi with the same guarantees:
settled signals we control, verdicts bound to commits,
blocked bubbles to the human in the TUI.

ELI5
Muse got a conductor and three small workers, and it
worked. Pi is where the human already lives, but bare pi
has no workers at all — deliberately. So we build the
smallest worker-spawner ourselves, steal the good ideas
from the two big community systems without marrying
either, and teach the pi conductor the same dance.

## Terms

| Term | Means |
|---|---|
| conductor | the skill (prose) that reads `bp3 q r`, dispatches one step per state, re-reads; same word, same procedure as the muse engine |
| step | one FSM transition family: author (`induct-exp`), grade (`induct-grade`), land (`quest-land`) |
| Run | one child pi process executing one step on one exp at one cycle; identified by run-id |
| dispatcher | our pi extension: registers the tool(s) that spawn, fence, and reap child pi processes. Ships as the pi package **`bp3-pi`** (below); "dispatcher" stays the concept word |
| child | one spawned `pi` process; a process, never an in-process agent |
| settled | child process exited AND its session is idle/closed; process exit alone is not settled |
| desk | a `bp3 worktree` checkout; two levels: a **quest desk** at `.bp3/desks/<quest>/conductor` (the conductor's cwd for a whole `/induct-goal` drive) and **run desks** at `.bp3/desks/<quest>/<exp>/<run_id>` (one child Run's cwd). Nesting is what makes parallel quest execution structural: one conductor per quest desk, one child per run desk, no shared checkout at either level |
| envPreset | `BP3_RUN_ID`, `BP3_QUEST`, `BP3_EXP`, `BP3_HARNESS=pi`, `BP3_MODEL` set in the child's environment at spawn; pi children inherit env directly — no hook prefix witness needed |
| tape | the child's session JSONL + captured stdout, stored under the exp's `runs/<run-id>/`; evidence, never parsed into facts |
| run event log | per-Run append-only event rows (`.git/bp3-run-events/<run_id>.jsonl`), folded on read; local receipts, never truth. Replaces the word "registry" everywhere (owner, red-ink): the legacy muse store is a session-keyed dict, but what the convention builds is an event log. Not the **ledger** — ledger is committed state transitions (truth); the event log is deletable. The codebase/docs rename (src, tests, skills, exp records) rides Exp 8 (muse) and Exp 4 (pi, born with the new name); a synonym left behind means the rename has not happened |
| role | a named child configuration: prompt file, tool allowlist, model pattern, thinking level (author, reviewer, checker, lander) |
| cold / fork | child context provisioning: cold = fresh session; fork = `pi --fork` of a named session (fix cycles carry the reviewer's context) |

## Demos

Design trace (nothing below is observed yet; pi runs bare
today — `~/.pi/agent/extensions/` is empty):

```text
/induct 2026-11-15-toy-pi
  conductor: ./bin/bp3 q r <quest>            (bash, no LLM child)
  exp-1 todo -> dispatcher.spawn(role=author, desk=..., envPreset)
    child pi -p --mode json --tools read,write,edit,bash
      ...works, commits, calls bp3 q u submit itself...
    settled -> conductor re-reads: submitted @ <sha>
  grade: two children in parallel (reviewer, checker)
    verdicts bind <sha>; approved
  land child -> landed == exp_fin; conductor reports
```

Demo: different experts, different Codex models (design
trace; the smoke test in Exp 6 runs exactly this cast):

```text
/induct 2026-11-15-toy-pi      conductor: gpt-6-astra, high
  exp todo
    -> author    gpt-6.1-sol,   medium   builds, submits
    -> reviewer  gpt-6-astra,   high     judges the commit
    -> checker   gpt-6.1-terra, medium   runs the checks
    -> lander    gpt-6.1-terra, low      lands: exp_fin
  event log rows show four Runs, three distinct models;
  the smoke test asserts model-per-role from those rows,
  not from the role files' claims.
```

## Engine output contract (the spec every harness targets)

Settled at red-ink (round 1, owner): the pi engine emits
exactly what the muse engine emits. This contract is the
interface; harnesses are implementations of it. A new
harness targets these shapes, in these spellings, and
the conductor skill needs no second dialect.

```python
# step result: one per dispatched step
StepResult = {
  "exp": str, "outcome": "submitted" | "approved"
           | "landed" | "blocked" | "refused",
  "commit": str | None,        # bound commit, from re-read
  "run_ids": [str],
  "refusals": [str],           # error codes + facts, verbatim
}

# event log row: one per (run_id, event)
RunEventRow = {
  "run_id": str, "quest": str, "exp": str,
  "harness": str, "model": str, "thinking": str,
  "event": "run_started" | "usage_recorded" | "run_settled"
           | "lint_checked",
  "usage": {"input": int, "output": int, "calls": int} | None,
}
# harness/model/thinking are witnessed config, recorded at
# run_started from the actual spawn (role default or named
# override), never parsed back out of the run-id string.
# The event log holds receipts, never defaults: intended
# config lives in role files only.
# Consumers read JSON fields. The run-id is an opaque
# identifier: its <ts>-<edge>-<harness>-<model>-c<cycle>
# format serves humans, folders, and tape lookup; no
# consumer derives harness, model, edge, or cycle by
# splitting it. On muse, hooks record the fields from the
# witnessed env (BP3_HARNESS / BP3_MODEL) at bind time —
# the prefix still binds session to Run; it no longer
# doubles as a data format.

# induct report: the conductor's only output
Report = {
  "dispatches": [StepResult],       # per exp, in order
  "matrices": [dict],               # grade matrices, verbatim
  "scorecard": {"tokens_in": int, "tokens_out": int,
                "runs": int,
                "human_active_minutes": int | "unmeasured"},
  "next_decision": str | None,      # the blocked gate, if any
}
```

Rules of the contract:

- `outcome` is read from `bp3 q r` after the step, never
  from the child's self-report. Process exit is evidence,
  not a verdict.
- Pi-isms (session JSONL, tape, TUI state) live behind
  `run_ids`: evidence paths the shapes point at, never
  new shapes of their own.
- Versioning: the contract changes by amending this
  section and re-grading both engines against it; a
  harness that emits a drifted shape fails its demo exp.

Artifact (settled at red-ink, round 1, owner: option A,
with a validation unit and a smoke test):

```text
docs/engine-contract/
  step-result.schema.json
  run-event.schema.json
  report.schema.json
  validate.*            # the validation unit
  fixtures/             # captured real results, both engines
```

- **Validation unit:** schema-checks any StepResult,
  RunEventRow, or Report value. Known cases: one valid
  fixture per shape passes; each malformed variant
  (missing field, drifted spelling, extra verdict word)
  is rejected by name. Runs in `make check`.
- **Smoke test:** one live pi dispatch and one captured
  muse workflow result, both fed through the validation
  unit in the demo exp; either engine drifting turns it
  red. Fixtures are refreshed only deliberately, never
  by the test itself.

## Shared conventions (owner, red-ink round 3 amendment)

This quest builds conventions, not just a pi engine.
Each convention below is defined once, in one place,
and both harnesses (muse workflows today, pi next, any
future harness) inherit or adhere to it. A convention
has: a name, a file that defines it, and a check that
fails when an engine drifts from it.

| Convention | Defined in | Adhered by | Checked by |
|---|---|---|---|
| Output types (`StepResult`, `RunEventRow`, `Report`) | `docs/engine-contract/*.schema.json` | every dispatcher/conductor | validation unit + smoke test (round 1) |
| Event log storage | per-Run `.git/bp3-run-events/<run_id>.jsonl`, fold on read | every event log writer/reader | event log tests per engine |
| Run-id derivation | `<ts>-<edge>-<harness>-<model>-c<cycle>` from (quest, exp, edge, cycle) | every spawner | derivation property tests |
| Role vocabulary | frontmatter fields `model`, `thinking`, `tools` + prompt body | every role file, every harness | skills tests |
| Identity env | `BP3_RUN_ID`, `BP3_QUEST`, `BP3_EXP`, `BP3_HARNESS`, `BP3_MODEL`; `BP3_DECIDER` human-only | every child spawn | refused-input tests (round 2) |
| Refusals | `{code, facts}` error shapes; a refusal is information, answered by re-reading | every step | contract fixtures |

Rule: a convention changes in its defining file first,
with its check updated in the same change; engines then
re-grade against it. No harness keeps a private variant
— a private variant is drift with good branding.

## Inputs (settled at red-ink, round 2, owner: option A)

The dispatcher takes a small, named input. Everything
else is derived or pinned — never caller-supplied.

```python
SpawnInput = {
  "quest": str, "exp": str,
  "role": "author" | "reviewer" | "checker" | "lander",
  "cycle": int,
  "fix": str | None,        # reviewer's named fix, verbatim
  "model": str | None,      # override; default is the role's
  "thinking": str | None,   # override; default is the role's
}
```

| Input class | Owned by | Rule |
|---|---|---|
| prompt, tool allowlist, default model/thinking | role file | caller cannot widen; a spawn asking for other tools is refused by name |
| run-id, desk path, envPreset | dispatcher | minted at spawn from (quest, exp, role, cycle, clock); the caller never passes `ts` — the extension reads its own clock |
| `model`, `thinking` overrides | caller | allowed, and written into the event log row: routing is visible and gradeable, never silent |
| `BP3_DECIDER`, any env key, any tool name | nobody | refused inputs; the dispatcher strips nothing quietly — it refuses the spawn and names the key |

The conductor's own input stays what it is on muse: one
quest. Roles are files, not arguments: changing a role
is a reviewed edit (Exp 5), not a runtime choice.

Models and effort are configuration (owner, round 2
amendment). Pi spells effort as thinking level
(`--thinking`: off, minimal, low, medium, high, xhigh,
max); this design uses pi's spelling.

Defaults (owner, 2026-11-15): the tested configuration
is the default — `openai/gpt-6-astra` at high thinking
smoke-tested live on a bare pi (read-only state query,
correct verdict, ~7s). Different experts run different
Codex models on purpose; the demo below shows the cast.

| Who | Configured where | Default | Recorded |
|---|---|---|---|
| conductor | the pi session itself: `--model` / `--thinking` at launch, or `.pi/settings.json` | `openai/gpt-6-astra`, thinking high | Report scorecard names conductor model + thinking |
| author child | role file frontmatter: `model:`, `thinking:` | `openai/gpt-6.1-sol`, thinking medium | event log row per Run |
| reviewer child | role file frontmatter | `openai/gpt-6-astra`, thinking high (the judge is not the builder) | event log row per Run |
| checker child | role file frontmatter | `openai/gpt-6.1-terra`, thinking medium | event log row per Run |
| lander child | role file frontmatter | `openai/gpt-6.1-terra`, thinking low (mechanical edge) | event log row per Run |

Precedence, one rule: spawn override (Inputs above)
beats role file; role file beats the conductor session's
own model. A child never silently inherits the
conductor's model — inheritance is how judge and builder
end up the same mind by accident. This is what makes the
iceboxed grade-model-routing question answerable:
routing is a role-file edit or a named override, both
on the record.

## Data at rest (settled at red-ink, round 3, owner: option A)

| Shape | At rest | Rule |
|---|---|---|
| Event log rows | `.git/bp3-run-events/<run_id>.jsonl` — one file per Run, rows appended by that Run only | readers fold the directory; no shared mutable file, on any harness |
| Run identity | run-id is the **primary key** of a Run in every store: event log file name, desk derivation, `runs/<run-id>/` tape folder, `(run_id, event)` idempotency inside the fold | session_id is a witnessed field, never a key; two sessions claiming one run-id is a collision, refused (`E_RUN_EXISTS` precedent in tape folders). This inverts the legacy muse event log, which keys by session_id with run_id as an attribute — Exp 8 re-keys it at write time. Settled at red-ink (owner: option A over session-id keying — a primary key must be mintable by the system that owns the record, at creation time; session ids are harness-minted, can be absent for ephemeral children, and are not 1:1 with work) |
| Role files | markdown + frontmatter (`model`, `thinking`, `tools`) + prompt body | repo skill mechanics; installed and tested like skills |
| Tape | child's session JSONL copied (never moved, never parsed) into `experiments/<exp>/runs/<run-id>/` at settle, beside the child's `notes.md` | dispatcher records the session path at spawn |
| `run_unsettled` vs `orphaned` | `run_unsettled` is an event-row word (a row that was appended, by hooks or dispatcher); `orphaned` is the derived lifecycle reading (round 4). Rows are facts; lifecycle is the fold. The pair survives only with this split written wherever both appear |
| Contract schemas | `docs/engine-contract/*.schema.json` + `fixtures/` | settled in round 1 |

Consequence for muse (owner, round 3): the single-file
`.git/bp3-run-events.json (legacy single file)` writer is legacy. Muse
hooks/workflows move to per-Run files under the same
rule — same directory, same fold. That migration is
owed work with its own gate; it is recorded here so the
contract never describes two storage shapes. Until it
lands, readers must fold per-Run files first and treat
the legacy file as older evidence, never merge the two
silently.

## State (settled at red-ink, round 4, owner: option A)

Run lifecycle is **derived, never stored**. The event
rows are the only stored facts; lifecycle is a fold of
rows + pid liveness, computed at read:

```text
spawned    run_started row only
running    heartbeat (last_seen) fresh
settled    run_settled row present
orphaned   heartbeat stale AND pid dead or absent
```

| Rule | Why |
|---|---|
| No stored lifecycle field | a stored `running` survives the crash that makes it false; everything else in bp3 folds or admits it's a cache |
| One vocabulary, two strengths | pi's dispatcher *observes* child exit; muse *infers* death from 900s heartbeat staleness (hooks.ml precedent). Same four words; the rows show which kind of evidence backs them |
| Orphaned = stale heartbeat AND dead pid | either signal alone lies: long silent work is not dead, and a recycled pid is not alive |
| Desk fate follows Run fate | settled → desk released; orphaned → desk is **listed** by the sweep, released only by an explicit act — an orphaned desk may hold the only copy of uncommitted work (the blocked-checkpoint precedent) |
| Desks nest (owner, red-ink round 4 amendment) | two levels matching the two merge stages: a **quest desk** (one per `/induct-goal`, the conductor's cwd for the whole drive, keyed by quest) and **run desks** inside it (keyed by run-id, prepared by the pi extension at spawn). `land` merges exp→quest inside the quest desk's world; the main tree sees the quest branch only at `goal_fin`. The conductor never conducts from the owner's main tree — the no-human drive's self-inflicted `E_DIRTY_TREE` park is the scar this prevents. Quest desk releases last, after its run desks, with the same dirty refusal. Paths: derivation today is `.bp3/worktrees/<quest>/<exp>/<run_id>` (worktree.ml); after Exp 1.2 renames worktree → desk in code, run desks live at `.bp3/desks/<quest>/<exp>/<run_id>` and the quest desk takes the reserved slot `.bp3/desks/<quest>/conductor` in the same namespace. **Purpose: parallel quest execution** — two `/induct-goal` conductors, two quest desks, no shared checkout at either level; the cli-small-fixes line of work (its `test/worktree.sh` desk cases) is the proving ground this convention inherits |
| The conductor has no lifecycle | the conductor is a session, not a Run (round 3); it mints run-ids, it never holds one |

Quest and exp state are untouched by this section:
ledger-folded as before, `state.yaml` still a cache.

## Functions (settled at red-ink, round 5, owner: option A)

The dispatcher exposes a handle-based, minimal surface.
No steering, no messaging, no kill: those would blur
the blocked/human gate.

```python
spawn_run(SpawnInput) -> RunHandle
    # mints run-id (primary key), prepares the desk,
    # spawns the child, appends run_started.
    # Refuses, by name: caller-supplied tools or env
    # keys, BP3_DECIDER, a second live child in the desk,
    # a run-id that already exists (E_RUN_EXISTS).

await_runs(run_ids, mode="all" | "any") -> [RunOutcome]
    # RunOutcome = process facts only: exit code,
    # settled | unsettled, usage, session path.
    # It never claims an FSM state.

list_runs(filter) -> [RunView]
    # Lifecycle folded from the event log (round 4):
    # spawned | running | settled | orphaned.
    # How a fresh conductor finds orphaned Runs and
    # their desks after a compaction or a crash.

release_desk(desk_key)
    # desk_key = run-id for a run desk, quest for the
    # quest desk. Explicit, named, refused while the
    # desk is dirty (worktree precedent). Never called
    # by a timer.
```

There is no `init_desk` (owner, red-ink round 5
amendment). Desk birth is atomic or mundane, never a
tool: a run desk is prepared inside `spawn_run` (mint
run-id → prepare → spawn → append run_started, one
act — a separately exposed prepare would let callers
create desks for run-ids the dispatcher never minted);
the quest desk is prepared by the conductor's own
bash (`bp3 worktree prepare`) at drive start, the
same channel as its state reads. `init` is also
already bp3's repo-setup word and is not reused.

Exposure (settled at red-ink, round 6, owner: option
A): the four functions register as four verb-named pi
tools — `spawn_run`, `await_runs`, `list_runs`,
`release_desk`. Role allowlists grant them to the
conductor only; children are spawned without them, so
a child spawning grandchildren is impossible by
construction, not by instruction.

What this is, honestly: pi has no workflow host, so
this quest rebuilds the workflow *runtime primitives*
(spawn typed children, await in parallel, detect
settled, keep a journal) as an extension, and keeps
the *control flow* where the induct design already
puts it on muse — in the conductor. Two deliberate
non-copies: no scripted determinism (the conductor is
an LLM following the skill; the re-read rule and the
grade are the discipline), and no resume journal (the
event log + re-read reconstructs outstanding work).

Packaging (settled at red-ink, round 6 amendment,
owner: option A): the dispatcher ships as a pi
package named **`bp3-pi`** — pi's plugin unit — in
this repo, installed by `bp3 skills install` into
`.pi/extensions/bp3-pi/` (pi itself also accepts it
via `pi install`). One package, two faces chosen by
env: the conductor face (the four tools) and the
child face (witness handlers appending event rows
when `BP3_RUN_ID` is set, silent otherwise). Roles
are NOT bundled into the package; they stay bp3
skill assets in their own install/test lane (Exp 6).

```text
extensions/bp3-pi/
  package.json          # pi manifest: extensions entry, version
  index.ts              # entry: conductor tools + child witness
  src/
    run-id.ts           # derivation (primary-key convention)
    events.ts           # event log append + fold
    desk.ts             # prepare / release / list
    roles.ts            # role frontmatter parsing
    spawn.ts            # child spawn + settled wait
  test/
    fake-pi.mjs         # shim for unit tests
    *.test.mjs
```

Layering rule: the conductor converts `RunOutcome` +
a fresh `bp3 q r` into the contract's `StepResult`.
The dispatcher's outcomes are evidence; the re-read is
the verdict. Children call their own `bp3 q u` edges;
neither dispatcher nor conductor calls a verdict edge
on a child's behalf. (The blocked gate's `resume` /
`delete` remain the conductor's, on attested owner
words, exactly as on muse.)

## Goal and why

The engine contract from bp3-mvp-engine-core is
harness-shaped on purpose: FSM in `bp3 q`, conductor in a
skill, steps as small Runs. Muse proved it with JS
workflows. Pi has no workflow runner and no subagents in
core — by design; its extension system is the intended
surface (verified: docs.pi.dev extensions; core ships
read/write/edit/bash and everything else is an extension).
Building the pi executor proves the contract is real and
puts induct where the human already works. It also
stress-tests the muse design: anything that only worked
because of Muse workflows will show up here.

Research basis (2026-11-15, full notes in the framing
session): pi 1.5.0 installed locally, bare; `-p`,
`--mode rpc|json`, `--session/--fork`, `--tools`,
`--model`, `-e` all present. pi-subagents (nicobailon,
ecosystem leader) offers chains/parallel/worktrees;
@tintinweb/pi-subagents offers a Claude-Code-like fleet
view; oh-my-pi (can1357 fork) offers a first-class `task`
tool, worktree-isolated workers, schema-validated yields,
and an Agent Hub. We pluck: typed yields, concurrency
semaphore, worktree-per-child, role files. We reject:
adopting either system whole (their semantics, their
roadmap, a fork to chase).

## Success picture

- A toy exp travels todo → `exp_fin` driven by
  `/induct` inside pi, every edge called by a child
  process we spawned, settled signals from our own
  dispatcher.
- Grade on pi produces the same typed matrix shape as
  the muse grade; a verdict against a superseded commit
  is refused by `bp3 q`, not by politeness.
- A blocked exp bubbles up in the pi TUI (dialog +
  inbox); the conductor never attests on its own.
- Event log rows for pi Runs carry usage (tokens, calls),
  so a pi drive has a scorecard, not vibes.
- `make check` green with pi-engine tests included.

## Scope

| In | Out |
|---|---|
| dispatcher extension (ours, TS, in-repo) | adopting pi-subagents or omp as a dependency |
| conductor skill parity for pi (author/grade/land) | daily-driver pi meta (model routing folklore, cache discipline) — separate iceboxed quest |
| hooks/event log parity via extension events | mining pi session logs (existing icebox entry) |
| context provisioning rules (cold vs fork per step) | pi TUI theming, prompt templates beyond roles |
| skill changes as their own exp (rule 6.6) | MCP servers |

## Human touchpoints

| Point | Shape |
|---|---|
| blocked gate | TUI dialog via extension `ctx.ui` + the quest inbox; owner words attested per exp, as everywhere |
| quest approval | this file: proposed until the owner says go |
| `goal_fin` | owner gate, demo first, as always |

## Exps

### Exp 1 — rename-run-event-log — [record](experiments/exp-1-rename-run-event-log/EXPERIMENT.md)
First by owner's ruling, two rename substeps: **1.1** registry → run event log across docs and codebase (words, identifiers, file name; storage migration stays Exp 8), and **1.2** worktree → desk in code (owner, post-adoption: module, CLI verb, paths, tests), so no later exp is born speaking either old word.

### Exp 2 — shared conventions + pi-step-runner — [record](experiments/exp-2-shared-conventions-pi-runner/EXPERIMENT.md)
Two substeps: **2.1 shared conventions** — the engine-contract artifact (`docs/engine-contract/` schemas + validation unit), per-Run event log storage + fold, run-id derivation, checked against muse as the first adherent. **2.2 pi-step-runner** — dispatcher extension: one child pi process per Run, typed result, honest settled, emitting contract-shaped results from its first spawn. The smoke test against both engines rides Exp 7.

### Exp 3 — pi-conductor — [record](experiments/exp-3-pi-conductor/EXPERIMENT.md)
The induct dance on pi: roles for author/grade/land, state dispatched per read.

### Exp 4 — pi-event-log — [record](experiments/exp-4-pi-event-log/EXPERIMENT.md)
Extension events feed the run event log: usage, lint, tape — parity with muse hooks.

### Exp 5 — pi-context — [record](experiments/exp-5-pi-context/EXPERIMENT.md)
Cold vs fork provisioning per step; conductor compaction rule (re-read, never remember).

### Exp 6 — pi-skills — [record](experiments/exp-6-pi-skills/EXPERIMENT.md)
Skill changes ride here: pi engine sections, `.pi` renders, skills tests (rule 6.6).

### Exp 7 — pi-engine-demo — [record](experiments/exp-7-pi-engine-demo/EXPERIMENT.md)
Quest-level demo: full toy drive + two-quest fleet on pi, check-in report, landing demo. Hosts the contract smoke test: one live pi dispatch + one captured muse result through the validation unit, and the model-per-role cast (author sol, reviewer astra/high, checker terra, lander terra/low) asserted from event log rows.

### Exp 8 — muse-event-log-per-run — [record](experiments/exp-8-muse-event-log-per-run/EXPERIMENT.md)
The muse writer migrates to per-Run event log files (round 3 convention); readers fold, legacy file read-only with a named sunset. Appended at red-ink by the owner.

## Scorecard

Fields: Runs per exp, tokens per Run (event log), wall
time, human-active minutes (or "unmeasured"), cycles
burned by fix loops, pi-vs-muse cost on the same toy —
the comparison is the point of a second engine.

## Risks and red chair

Strongest attacks, recorded at framing (2026-11-15):

1. **Process exit ≠ done.** A child can exit 0 without
   ever calling `bp3 q u`. Defense already exists and is
   harness-independent: the conductor judges only the
   re-read state, and grade judges the bound commit.
   The dispatcher returns outcomes; it never vouches.
2. **The conductor is an LLM session with compaction.**
   Pi compacts near the limit; a compacted conductor
   "remembers" a merge order that never existed.
   Defense: conductor state lives in `bp3 q r` reads,
   re-read after every dispatch and after any
   compaction; the skill says so in those words.
3. **Extension = in-process, full perms.** Our
   dispatcher is trusted repo code; community extensions
   are strangers with our credentials. Rule: vendor
   nothing at runtime; every extension in the pi engine
   is a file in this repo, reviewed like code.
4. **RPC envy.** `--mode rpc` gives live events and
   steering (omp's Agent Hub proves the value), but a
   JSON-protocol driver is a second product. Exp 2 must
   prove `-p --mode json` settled signals insufficient
   before RPC earns an exp.
5. **Parallel children, shared tree.** Two pi children
   in one checkout reproduce the branch-flip wart.
   Defense is exp-4-proven: desks, one quest per
   checkout. The dispatcher refuses a second live child
   in the same desk.

## Open questions

1. Disposition of `2026-11-07-bp3-engine-pi.md` and
   `2026-11-07-bp3-pi-qol.md` (both `proposed`, owner
   calls them dead): cancel both, superseded by this
   Quest + the new icebox entry? Owner decides at
   approval.
2. ~~Does the dispatcher ship as a bp3 skill-adjacent
   package or a standalone pi package?~~ Settled at
   red-ink round 6: the `bp3-pi` pi package, installed
   by `bp3 skills install` into `.pi/extensions/bp3-pi/`.
3. Child model routing: per-role `--model` patterns —
   which models for reviewer vs author is measured in
   Exp 2/3, not assumed at framing.

Context: promoted from
[the pi-engine icebox entry](ICEBOX.md) (verbatim copy;
the entry's promotion trigger fired — core landed, muse
executor proved, a pi-run exp is wanted). Prior art in
repo: `docs/dossiers/bp3-pi-basics.md` (2026-11 map of
omp + subagent extensions; stars/downloads there are
dated, re-verified at framing only for the headliners).
