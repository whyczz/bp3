# Genesis: runbook and acceptance evidence

Status: **MVP Exp 1 acceptance passed (all five stages).**
This is the agreed direct-authored bootstrap exception, not bp3 building itself.
The [Quest](quests/2026-11-05-bp3-mvp.md) remains active. This Exp 1 source
checkpoint is on `quest/bp3-mvp`, above skill-fix `28a274a` on `master`.
Exp 2 has a [proposed implementation packet](designs/bp3-auto-land-contract.md);
its next step is a fresh implementation Board at the exact checkpoint commit.
Exp 3 has not started. No master promotion, auto-land, or independent review
approval is implied. The user authorized pushing only the skill-fix commit.

## Build and offline checks

Dependencies: OCaml >=5.1, Dune >=3.17, SQLite3 OCaml bindings, Yojson, Lwt,
OUnit2; ocamlformat **0.29.0** for formatting; Node with native TypeScript type
stripping for adapter tests. Live tests additionally require pi, Zellij and a
configured model provider. `brew bundle` installs the shell/skill-check tooling,
not the OCaml toolchain or provider configuration.

```sh
opam install . --deps-only --with-test
opam install ocamlformat.0.29.0
# Use your opam environment if the toolchain is not already on PATH.
dune build @all
make check
./bin/bp3 --help
```

Verified here with OCaml 5.3.0, Dune 3.24.0, Node 25.4.0, pi 1.5.0 and
Zellij 0.45.1. `make check` covers shell lint, build, **35 OCaml tests**, **4
bridge adapter tests**, formatting, **12 skill files**, and **33 installer
assertions**. Adapter tests use a fake pi API and a real socket; they are not a
substitute for the live/human observations below. Package-mode
`dune build -p bp3` also passes. `opam lint bp3.opam` reports non-fatal metadata
warnings (homepage, bug-report URL and the non-SPDX `UNLICENSED` label); this is
not yet a published package. No project license was chosen by this bootstrap.

`bin/bp3` keeps `skills install` independent of OCaml. Core commands use an
explicit `BP3_CORE` executable, or `_build/default/core/control/main.exe`.
They do not silently rebuild the coordinator when a Worker changes source.

## Code map and invariants

| Path | Responsibility |
|---|---|
| `core/protocol/packet.ml` | v1 JSON, canonical retry identity, brief validation, local capabilities |
| `core/board/store.ml` | schema, prepared SQL, short transactions, snapshots/events |
| `core/board/authority.ml` | caller permissions, execution ownership, budget/takeover fences |
| `core/board/board.ml` | authenticate/replay/preflight/transaction boundary |
| `core/board/workflow.ml` | Quest, exp, brief, blocker, answer handling, candidate |
| `core/board/execution_ops.ml` | launch journal, bridge observations, durable inbox offers |
| `core/runtime/` | bounded private socket, singleton runtime, worktree/pane launcher |
| `core/control/main.ml` | disposable CLI, JSON context and operation ingress |
| `plugins/harness-pi/bridge.ts` | pi lifecycle hooks and transport, no policy or pane parsing |
| `tests/test_genesis.ml` | isolated Boards/Git repos, rollback/fencing/retry/process counterexamples |
| `tests/bridge.test.mjs` | held-ready, same-request retries, follow-up/ACK, takeover/release, abort |
| `tests/controller-recovery.mjs` | opt-in paid test: real Controller SIGKILL/replacement during work and pending question |

The [implementation contract](designs/bp3-genesis-contract.md) governs Exp 1.
Comments at the boundaries explain why an idle signal is not a result, an offer
is not handling, a report is not approval, and a launch retry must not respawn.
No function named land/review/promote is stubbed to succeed.

## Create a live fixture

This starts a visible real pi process. The brief is **held** until explicitly
queued; queueing it authorizes model work and may incur provider charges.
Choose a new directory and a dedicated Zellij session name each time.

```sh
tests/start-toy .bp3/my-run bp3-my-run YOUR_PROVIDER/MODEL hello
# Or use `blocker` instead of `hello` for the missing-check human drill.
zellij attach bp3-my-run
```

The script prints the exact context and queue-brief commands. It freezes the
bootstrap binary/bridge under that fixture's `genesis/`, materializes a fresh
Git repository from `tests/toy-template/`, creates `quest/toy`, starts one
runtime, and launches one Worker. `hello.ml` deliberately fails its check at
baseline. Scope is `hello.ml` only; the Worker must not alter the harness.
Use `dune runtest --root .` in nested toy worktrees so Dune does not select the
parent bp3 project.

Every mutation is a v1 envelope with a stable `op_id`, `op`, and `payload`, fed
to `bp3 --board PATH op FILE` (or `op -`). Controller operations are
`quest-create`, `exp-create`, `brief`, `steer`, `cancel`. Worker operations are
`block`, `answer-handled`, `report`, with credentials supplied from the Worker
environment. Reuse an operation ID only for the exact same request. Public
context excludes capabilities; do not publish the Board database, launch file,
or raw receipts, which contain local credentials.

## Live observations (2026-11-05/06)

### Successful Worker and recovery run

Local evidence: `.bp3/live-e1/` (ignored, retained on this machine).

- Real pi session `01a1ae53-e36b-743f-af1b-36d6767f48dc`, Zellij
  `bp3-mvp-e1`, execution `hello-worker`; bridge registered ready/idle before
  brief delivery. Endpoint matched pane/session/worktree metadata. No pane
  contents were read to infer state.
- Worker implemented `hello.ml`, including an entry-point comment. It blocked
  when unscoped `dune runtest` selected the parent project. A deterministic
  Controller correction supplied `--root .` through the Board. This was **not
  a human blocker-answer pass**. Question `hello-worker-check-root` is handled.
- Candidate **`9cfb9546978c8b7fbf64dd00681d4c03a4a8106b`**, result
  `result-hello-worker`. Independently reran `dune runtest --root .` and
  `dune exec --root . ./hello.exe`; checks passed, output `hello`. The fixture
  harness was unchanged. This is not an independent reviewer receipt or land.
- Replayed the exact stored Worker report: same result ID, one result total.
- SIGKILLed and restarted the runtime: same execution/result/handled question,
  living bridge reconnected. Closed the owned Worker pane: runtime marked it
  stale within the heartbeat timeout, with no replacement execution/result.
- Saved `ready-receipt.json` and `after-death.json`. Runtime subsequently stopped;
  the Worker pane is closed. The fixture Git repo, Board, and pi session remain.

### Human drill — passed

Local evidence: `.bp3/manual-e1/`; Zellij **`bp3-mvp-manual`**. This fixture
uses the post-review frozen binary/bridge. Launch file mode is 0600 and pane
command metadata contains no `BP3_TOKEN` binding.

The real Worker ran the deliberately absent `./missing-check`, raised question
**`hello-worker-missing-check`**, and settled without a candidate. Its open
question survived a runtime SIGKILL/restart with identical contents, one
execution and zero results (`before-restart.json`, `after-restart.json`). The
bridge reconnected. The runtime and now-completed Worker remain alive so the
human can inspect the finished pane. The execution has a 24-hour wall-clock
budget from launch, not an unlimited lease. Do not bypass an expired fence or
edit its deadline; this completed candidate remains durable evidence.

**IIUC:** the Worker may change only `hello.ml`; acceptance must use a check
chosen by the human, because the named check does not exist.
**Challenge:** inventing `missing-check` would silently change acceptance.
**Recommendation:** authorize `dune runtest --root .` and
`dune exec --root . ./hello.exe` as the checks, keeping the harness unchanged.

**Human update:** the user confirmed watchability and approved those checks.
Controller operation `human-answer-missing-check` recorded the decision.
Actual bridge takeover held the answer until human `/bp3-release`; the recorded
sequence is takeover (events 1111/1132), release (1265), answer observed (1268),
answer handled (1273), then candidate report and settled-idle (1302). This
sequence took over before answer delivery, rather than after the report in the
original checklist; the gate correctly prevented delivery while taken over.

On the user's “worker looks done” observation, the Controller verified:

- Candidate **`5a429fc31f70c8af0ebeb6b2d91332f45eed8540`**, exact worktree HEAD;
  clean tree and `hello.ml` as the only changed path from the frozen base.
- `dune runtest --root . --force` passes; `dune exec --root . ./hello.exe`
  prints `hello`. The harness and expected output were not changed.
- Question and reply inbox are both `handled`; takeover=0, idle=1, live.
- Exact authenticated report replay returns `result-hello-worker`, still one
  result. Repeating the original launch returns `replayed=true`, still one
  execution and one Worker pane. No pane contents were read.
- Evidence snapshot: `.bp3/manual-e1/completed-receipt.json` and Board events.
  This proves the Exp 1 round-trip, not Exp 2 reviewer approval/land.

The user noticed a half-width Worker and an empty neighbor. The fixture's
initial Zellij shell plus the launcher's `new-pane` created two panes in one
tab. Closed only the owned spare `terminal_0`; Zellij metadata confirms one
remaining tiled Worker pane. Future fixture layout cleanup is still polish
work; no pane text was read or input synthesized.

## Human checklist — reproduction reference

The current fixture has completed this checklist. These steps are retained for
future fresh fixtures; do not treat them as another pending human request.

1. Attach: `zellij attach bp3-mvp-manual`. Confirm you can see the
   `bp3:hello-worker` pane and understand its missing-check blocker. This is
   the watchability observation the agent cannot supply for you.
2. Tell the Controller you approve the recommended check, or choose another.
   The Controller records your answer via `steer`; you need not run raw ops.
   If you prefer to do the complete drill yourself, run this **from the home
   repo, outside the Worker pane**, only after making that decision:

   ```sh
   printf '%s\n' '{"v":1,"op_id":"human-answer-missing-check","op":"steer","payload":{"id":"human-check-answer","execution_id":"hello-worker","question_id":"hello-worker-missing-check","text":"Human decision: use dune runtest --root . and dune exec --root . ./hello.exe as acceptance. Keep expected.txt and the test harness unchanged. Acknowledge this inbox answer, run the checks, commit hello.ml only, and report the candidate."}}' |
     .bp3/manual-e1/genesis/bp3 --board .bp3/manual-e1/board.sqlite op -
   ```

3. Let the Worker handle the answer and report. Then type directly into its pi
   pane: `Human takeover test: acknowledge only; do not edit or report.`
   Wait for the response to settle. The status should show human takeover;
   Board `takeover` must be 1. This is actual human input, not scripted typing.
4. Enter **`/bp3-release`** in the idle Worker pane. Board `takeover` must return
   to 0. Do not use Ctrl-C as a substitute for release. Tell the Controller what
   you observed, including any surprising behavior.
5. The Controller checks durable answer handling, the single candidate, exact
   report retry, current endpoint/idle state, and the remaining recovery drill.
   A **fresh Controller session** must reconstruct the pending/active state
   without your re-explaining it; runtime death alone does not prove that.

Inspect without reading the pane:

```sh
.bp3/manual-e1/genesis/bp3 --board .bp3/manual-e1/board.sqlite context |
  jq '{executions: [.executions[] | {id,ready,idle,takeover,observed,desired}], questions, results}'
```

Do not mark Exp 1 complete on unit tests alone. All five stages have now been
observed, including the human checklist and literal Controller replacement below.

## Literal Controller death and recovery — passed

Run separately from the offline suite (requires provider access and spends model
work):

```sh
node tests/controller-recovery.mjs NEW_DIRECTORY NEW_SESSION PROVIDER/MODEL
```

Passing evidence: `.bp3/recovery-e1b/`. The script starts a real visible Worker,
which holds in one bounded shell tool at an external test barrier. It starts a
real pi Controller, waits for its actual `bp3 context` tool result, then sends
SIGKILL to **that Controller's own process group**. A fresh pi session, with no
history/context files or prior transcript, reconstructs the active obligation.
After the deterministic barrier releases, the Worker reports the missing-check
blocker. A second Controller SIGKILL/fresh-session cycle preserves the exact
pending question. Both replacement briefings correctly report no new launch.
Finally, Worker pane death becomes stale with one execution, zero results, and
the same open question. The test exp is then explicitly cancelled (not falsely
answered); its owned session/runtime are stopped and all evidence is retained.

`active-{killed,recovered}/` and `blocked-{killed,recovered}/` contain separate pi
sessions, JSON event logs and snapshots; replacement directories also contain
`briefing.json`. Audited all four tool traces: each executed only the instructed
`bp3 context` command. Read-only is the cooperative test role, not a bash sandbox.
`recovery-receipt.json` captures the retained obligation after Worker death.

An earlier `.bp3/recovery-e1/` run stopped on a test-prompt schema ambiguity: the
Controller returned boolean `idle:false`, but the assertion expected Board
integer `0`. Clarified the prompt to require integer 0/1, kept the assertion,
and ran a fresh fixture. That failed attempt is retained, not counted as a pass.
The fixture launcher now refuses an existing session name before creating any
files; a live negative check confirmed this guard. The suite never kills or
reuses an unrelated session.

## Red-chair record

Engineering/security passes, followed by separate fix iterations:

1. **Major — credentials in Zellij argv.** First live launch exposed the
   capability through pane metadata. Moved environment bindings into a private
   launch file; the fresh live fixture verified mode 0600 and no token binding
   in pane argv. Same-user access remains explicitly trusted.
2. **Major — stale cached offers.** Worker-style replay-before-fencing would
   also replay a bridge offer after cancellation/expiry. Bridge replay now
   revalidates authority/session; three regression cases cover cancellation,
   expiry, and takeover/permission. Old report receipts remain replayable.
3. **Major — runtime cleanup ownership race.** Unlock-before-unlink could
   remove a successor's socket. Cleanup now unlinks while holding the OS lock.
   Process tests cover singleton refusal, SIGKILL/restart and reconnect; they
   do not claim an exhaustive scheduler interleaving proof.
4. **Minor — nested Dune root and filesystem aliases.** Live Worker correctly
   blocked on the former; tests reproduced `/var` versus `/private/var` on the
   latter. Checks now name `--root .`; repo identity canonicalizes at ingress.

Final Exp 1 verdict: **accept the bounded round-trip/recovery slice**, not the
MVP or auto-land/promotion. The strongest retry/recovery attacks preserved one
execution/result and pending obligations across real process death. Tests and
live logs support that scoped verdict. This was Controller self-review, not the
fresh independent reviewer required by Exp 2.

The user authorized the bootstrap split: skill fix on `master` and pushed,
then Exp 1 locally on `quest/bp3-mvp`. The skill-only commit `28a274a` was checked
from an isolated staged-tree export; this second commit adds the genesis kernel
and handoff. The default branch was explicitly renamed from `main` to `master`.
No Quest code was promoted or pushed. See the Exp 2 packet for delegation from
the exact checkpoint rather than the old pre-genesis base.

## Recovery, ownership, and known limits

- `.bp3/board.sqlite` is the **historical bootstrap Board**, recording the real
  home Quest `bp3-mvp` and genesis exp at pre-genesis base
  `2c8bce6b68073c89d62f6c0402585316b19e94aa`. The user-authorized source checkpoint
  now advances `quest/bp3-mvp`; do not launch against the historical Board or
  silently rewrite its frozen base. Before Exp 2, preserve it and initialize a
  fresh implementation Board at the exact Quest checkpoint via normal create
  operations. The historical bootstrap exp remains `working` in this minimal
  schema (no administrative bootstrap-accept op). Completed observations are
  recorded here, not as a fabricated Worker result or a bypassed auto-land.
- `context` is a machine JSON snapshot, not yet the Exp 3 human briefing.
  Toy Boards are separate authority domains; do not copy their candidates
  into the home Board as fictitious bp3 results.
- Restart with the **same frozen** binary, Board and bridge:
  `.../genesis/bp3 --board .../board.sqlite runtime --binary /absolute/.../genesis/bp3 --bridge /absolute/.../genesis/bridge.ts`.
  Do not repeat an ambiguous launch to force a spawn. Its durable stage is the
  recovery evidence; new generation/rework recovery is not implemented yet.
- For a clean stop, obtain the current runtime PID with `ping`, then SIGTERM
  that owned process. Close only the owned Zellij pane/session. Keep the Board,
  worktrees, launch files and sessions while evidence is needed. A stopped
  runtime does not kill the Worker; a `cancel` fences but does not OS-kill it.
- An offered-but-unobserved message may be ambiguous after process loss or a
  takeover race. Genesis does not promise exactly-once external delivery or
  provide a forced reinjection command. Inspect and stop rather than guess.
- One live author, standard/code only, no prerequisites/review/land/promotion.
  A reported execution still occupies the author slot until explicit cancel
  or expiry; terminal/rework transitions belong to Exp 2, not implicit respawn.
- Synchronous Git/Zellij launch has no external-command deadline; a hung
  command can delay the event loop. Receipt/event compaction, portable restore,
  cost measurement, longer idle-provider observation, and process-tree
  supervision remain hardening work. Worktrees/capabilities are not isolation.
