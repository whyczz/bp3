---
date: 2026-11-06
quest: ../QUEST.md
exp: 7
status: active
---

# Exp 7 — Reusable Workers/reviewers through context forks

## TL;DR

Reuse the reviewer's knowledge, not its old authority. The Controller checks the
review packet, records its disposition and any optional human feedback, then
assigns a fork of that reviewer context to fix the accepted findings. A genuinely
fresh reviewer checks the new exact outputs. No agent approves its own fix.

ELI5: keep the useful notebook, issue a new work order, and have someone else
check the result. A new session ID alone does not make someone independent.

Status: **active — exact fork capability `4e61d7c` accepted for controlled
same-consumer use; actual reviewer-context repair has reached a submitted cold
engineering SHIP on Exp 2 output `9e1b1d0`.** Its author, Controller and cold
reviewer each pass the exact clean gate, **132 OCaml / 44 Node**. This completes
a real knowledge-handoff/output/independent-review cycle, not all Exp 7 recovery
or Exp 2 human/live acceptance. Main coordination remains frozen v2.

Earlier `7263287`/`a53b5c3` findings, failed checks and two interrupted unsubmitted
reviews remain recorded below. `915311d` received an actual submitted FIX FIRST;
its reproduced race and fixture failures drove the human-approved extra pair.
No saved review was fabricated as a submission. The specific `/bug` limitation
is unchanged. All **8/8 Runs / 28800 reserved seconds** are allocated, with no
refund, expired-authority revival or automatic replacement. The human's preferred
reviewer-to-fixer fork always receives new authority; the next reviewer stays
cold. Broader reusable scheduling remains follow-up scope. No overall completion,
master promotion or push is authorized.

## Context and scope

Home/frozen-v2 source: `e442374f9866b639078ed9f688c1f752d45a35df`.
[Exp 2](2026-11-05-auto-land.md) candidate
`e512fe5b572f9731b38dd75450bb69cd01d5d8a8` received a completed **FIX FIRST** review.
The human wants that reviewer's context used for the fix, rather than discarding
its understanding and repro work. The completed review remains immutable evidence.

Installed Pi 1.5.0 supports `--fork PATH`: a new session ID and current cwd with
history copied from the source. `--session PATH` instead resumes in the old cwd.
`SessionManager.forkFrom` copies all non-header entries; this is not a guarantee
of a distilled, credential-free or independent context. The existing bp3
[launcher](../../../core/runtime/launcher.ml) forwards a model and session directory,
not a fork source. The [bridge](../../../plugins/harness-pi/bridge.ts) binds credentials
and endpoint identity to one Run and refuses in-session fork/switch navigation.
Typing a new task into that session is not a new assignment.

In the immediate slice: explicit Controller-selected context fork for a new
author assignment; immutable source/context and feedback provenance; new Run,
session and worktree; held delivery; safe retry; tests and a narrow runbook.
Out: resuming/rebinding the live old process, generic warm pools, automatic
model routing, more concurrency, transcript mining, autonomous workflow policy,
or implementing the Exp 2 correctness fixes inside the plumbing assignment.
[Exp 5](2026-11-06-bounded-workflow-loop.md) owns eventual routine scheduling.
[Exp 8](2026-11-06-worker-retirement-revival.md) separately proposes automatic
closure of finished-unused tabs and explicit revival using this fork primitive.
It does not expand the active 7.1 assignment.

### Human-approved MVP exception — 2026-11-06

The human said **“bro do we care about the /bug? i will rarely, never usage it”**
and approved the recommendation to accept that limitation with **“yep continue”**.
The **manually invoked `/bug` generated-summary path after brief admission is
unsupported and excluded from MVP admission/budget-fencing acceptance**. The
counterexample remains valid, not fixed or erased: such a summary may reach the
model while Board authorization is pending/refusing. Do not use it in managed
Workers or claim cancellation fences every possible Pi model call. Ordinary bp3
prompt/tool execution, pre-brief holds, compaction/bash guards and all other
existing authority/review/recovery gates remain in scope. This is not a blanket
exemption for arbitrary utilities or a request to redesign/audit every Pi built-in.
A small supported disable is optional, not a new blocker; otherwise document the
limitation honestly. The immediate required fix is deterministic test settlement,
followed by exact checks and fresh review against this explicit narrower contract.

The human also attributed the provider interruption to **“codex hit the limit”**.
Retain that account-side explanation alongside the unchanged raw content-flag
error; the Controller has not independently verified provider quota/reset state.
The new continuation authorizes the next bounded assignment, not disguised
prompts, model substitution, repeated provider-error retries or budget renewal.
Any fresh provider/capacity refusal remains a stop point. Prior interrupted
reviews remain unsubmitted. No Exp 2 handoff or candidate acceptance is implied.

## Controller-check, fix and fresh-review workflow

```text
exact candidate + independent checks
                |
        independent reviewer R
                |
       immutable review packet
                |
     Controller reads and checks evidence
       + optional attributed human feedback
                |
       recorded disposition / handoff
        /                |                 \
 accept findings    dispute / clarify    accept candidate
        |                |                 |
 new author Run F   retain disagreement   existing exact gates
 fork of R context  no invented approval  land, not promote
        |
 fixed exact Outputs + independent checks
        |
 fresh reviewer R2 (no author/fixer conversation ancestry)
        |
 repeat bounded loop or land under existing gates
```

### Disposition is not one overloaded approval

The Controller reads the full packet and verifies load-bearing claims against
code and repro evidence. It records each finding as accepted for fixing,
disputed with reasons, or needing clarification. It also records candidate
accept/rework/hold disposition, the exact candidate/review/check references,
required tests, exclusions and stop conditions. Accepting a finding is not
accepting the candidate; rejecting a finding does not erase the original report
or manufacture an accepting independent review. Conflicting evidence is resolved
or reviewed again, not silently overridden to permit landing.

Human feedback is optional for ordinary fixes under an unchanged brief. If
present, preserve its source and exact scope separately from Controller analysis.
Only actual human input may be attributed to the human. Scope/acceptance changes,
budget escalation, promotion and push retain their existing authorization gates;
silence is never approval. No routine human scheduling step is added.

### Exp versus Run

Fixing rejected outputs under the same objective/acceptance is another author
**Run on the same exp**, not a fresh planning exp for every review cycle.
A materially different objective or explicitly refreshed scope gets a new exp
with links to the prior evidence. This reusable-context capability itself is a
separate useful outcome, hence Exp 7. Historical frozen-v2 bootstrap assignments
may need distinct exp records because that coordinator has no rework operation;
record that limitation rather than rewriting old bases or pretending v3 ran.

## Mini-design and responsibility map

1. **Freeze inputs.** Resolve an explicitly selected, completed and settled
   source session from its Board-recorded identity, not a fuzzy name or latest
   session lookup. Capture a stable private snapshot with source Board/Run/session,
   full-file digest and selected leaf/context boundary. Retain the checked review
   packet and disposition digest/references. Detect source change during capture;
   fail or retry capture explicitly, never silently follow a changing transcript.
   Initially constrain reuse to a proven consumer binding; a separate clone with
   equal SHAs is not automatically that binding. Explicit transfer is a separate
   decision if the bootstrap reviewer fixture needs it.
2. **Reserve new authority.** A new Run gets its own frozen brief, budget, role,
   credentials and workspace. Historical outputs/verdicts/leases are unchanged.
   Bind the exact fork source and handoff into retry identity before side effects.
   The first slice admits context reuse only for author assignments, not supposedly
   independent reviews. Do not create an alternate policy engine in Pi.
3. **Fork rather than resume.** Runtime launches Pi with the pinned fork input,
   current new worktree and explicit `openai/gpt-6-astra:xhigh`. No `--continue`,
   old `--session`, terminal typing, manual JSONL rewrite, inherited environment
   capability or old endpoint reuse. Inherited messages are historical evidence,
   not permission: the new brief must identify the role switch, current cwd,
   exact code input, current authority, obligations and obsolete instructions.
4. **Hold, verify, deliver.** Verify the actual child session ID/cwd/lineage,
   observed model/thinking and exact mounted terminal before briefing it. Fork
   loading must not itself resume tool/model work or replay prior inbox actions.
   Fresh bridge credentials authenticate the child; old ones cannot impersonate it.
   Source tab/history stay separate. Preserve the existing bound Zellij session
   and never steal Controller focus.
5. **Retry and recover.** A reserved attempt is inspected after failure; do not
   fork/spawn twice or silently drop to a cold launch. Same request replays;
   changed source/digest/role/workspace/feedback conflicts. A coordinator without
   fork support must refuse the request, not ignore the field and launch cold.
   Interrupted capture or ambiguous spawn stays inspectable. Fork failure cannot extend a source
   lease, clear its obligations or modify its source transcript.
6. **Review independently.** Preserve context lineage, not just unique session
   IDs. A fresh independent reviewer may read the brief, diff, prior findings,
   disposition and checks, but cannot inherit author/fixer conversations. A
   reviewer who becomes a fixer is now an author for that output. Within the
   frozen-v2 bootstrap, Controller-enforced separation is explicitly a policy,
   not a new role/lineage guarantee already enforced by that old schema.

Responsibility anchors: [CLI](../../../core/control/main.ml) accepts explicit input;
[launcher](../../../core/runtime/launcher.ml) journals reservation/spawn;
[Board](../../../core/board/board.ml) owns operations/receipts;
[Run operations](../../../core/board/run_ops.ml) bind endpoint identity;
[bridge](../../../plugins/harness-pi/bridge.ts) transports, not assigns authority.
Read installed Pi `cli.md`, `sessions.md`, `session-format.md`, `sdk.md`, relevant
examples and actual fork/dispatch callers before implementation. Any bridge
change additionally requires the full relevant extension docs/examples.

### Submitted 7.1 implementation — candidate only

At `726328762e55aa7ec31fd1c0edf06da4c21f152c`, the implementation adds:

- **Pinned inputs:** `core/protocol/fork_spec.ml` validates source/session and
  disposition references, common Git-directory identity and private byte-for-byte
  capture. `core/board/fork_policy.ml` checks the read-only source Board and
  current child/input identity. A separate clone with the same SHA is refused.
- **New authority and effects:** `core/runtime/fork_launcher.ml` uses a stable
  runtime-only reservation receipt and existing launch stages, not a schema
  migration. It launches explicit Pi `--fork` with new credentials/session/cwd,
  Astra xhigh and private handoff copies. Retry inspects the same attempt without
  recapture or respawn; interrupted effects may require an explicit hold.
- **Held admission:** `core/protocol/fork_mount.ml` queries attached-display and
  owned-terminal metadata. Board/Run operations recheck fork identity and offered
  input; the fork-only bridge latch explicitly consumes refused input through
  Pi's real dispatcher. Current brief authority is distinct from inherited history.
- **Bounded compatibility:** explicit `fork-launch`, Pi 1.5.0 and matching bridge,
  schema v2 unchanged, author-only context reuse and public provenance without
  transcript bodies/tokens. Independent review remains Controller policy in v2.
- **Checks/runbook:** fork policy/retry/crash regressions, installed-Pi fork and
  dispatcher tests, a provider-free mounted fixture and `docs/context-fork.md`.
  These paths refer to the submitted candidate, not activated home code.

The patch spans 25 files, 2738 insertions and 26 deletions; its narrowness and
failure behavior are independent-review questions, not settled by those counts.
The proposed real handoff assigns a new fixer Board/worktree **within the prior
review clone's existing Git common directory**. It does not support direct
cross-clone context transfer into home. That procedure and eventual composition
with Exp 2 remain subject to review and an explicitly scoped next assignment.

## Delivery slices and dependencies

### 7.1 — Minimal fork-capable launcher (pulled forward now)

A fresh Astra xhigh bootstrap author builds the missing primitive from clean
`e442374`, coordinated by the unchanged frozen v2 runtime. This author is **not**
the Exp 2 fixer. Keep the patch narrow and independently reviewable; do not import
or activate the rejected v3 candidate to obtain fork support. Do not create an
incompatible schema v3 competing with Exp 2's migration. If safe persistence
requires a broader migration/design change, stop with a concrete blocker.

Candidate execution is restricted to fresh disposable Boards/repos or copies.
Existing live runtimes/binaries/bridges remain unchanged. Independent exact-build
checks and a fresh review precede use for the real handoff. Document how the
narrow change composes with Exp 2; it is not implicit activation of either kernel.

### 7.2 — Reviewer-context repair handoff

After the primitive passes, freeze an explicitly scoped handoff build/assignment
and use the prior reviewer's pinned context for Exp 2 repair. Controller feedback
accepts the verified three major findings and the undo-retry issue for fixing;
no acceptance contract is silently weakened. The fixer adopts faithful permanent
regressions with red-before/green-after evidence and submits new exact Outputs.
A fresh independent reviewer then checks them. Keep bootstrap Board/consumer
binding and candidate checkout provenance explicit; do not rewrite historical
bases to make the transfer appear native.

General reuse across unrelated exps, persistent pools and automatic role routing
are not part of 7.1. Exps 4–6 remain deferred; Exp 3 remains unstarted.

## Acceptance and evidence

The checks below are the intended acceptance contract, not a blanket pass.
The exact submitted candidate passes Controller and independent reviewer
`make check`, including installed-Pi provider-free fork/dispatcher tests. The
reviewer also ran a fresh mounted zero-provider drill. Nevertheless, its saved
**FIX FIRST** report contains three failures freshly reproduced by the Controller.
A provider refusal interrupted formal review submission; no Board review output
exists at this checkpoint. Correctness fixes, fresh review/acceptance, the actual
reviewer-to-fixer round-trip and human watchability remain pending. Detailed
observations and their boundaries are recorded below.

- Real installed-Pi fork without paid model work: child has a different ID, the
  new cwd, correct parent/pinned history and Astra xhigh selection; original file
  hash is unchanged. A marker from source context is retained. No automatic prompt,
  old inbox replay or model request occurs before the new brief.
- New author Run credentials authenticate only the child; old token/generation/
  session, wrong parent, wrong cwd/consumer, missing/malformed/changed source and
  changed handoff are rejected or held before work. Fresh source validation must
  not launder a copied author session into independent review.
- Duplicate launch and injected death at snapshot/reservation/spawn/ready boundaries
  produce one authorized child or an explicit hold, not a second fork/Worker.
  Source remains untouched; no fallback to resume or cold start without a decision.
- Disposition binds exact review/output/brief and distinguishes finding acceptance,
  candidate acceptance, disputed findings and optional human input. Conflicting or
  superseded feedback cannot approve changed outputs or silently expand scope.
- A toy reviewer-to-fixer round-trip retains useful source context, fixes a
  demonstrated regression and reports new outputs. A non-forked independent
  reviewer checks the exact fix. Tests refuse author/fixer-lineage self-review.
- `make check` passes on the exact submitted build. Opt-in visible drills confirm
  new mounted tabs in the bound session and preserved Controller/source sessions;
  actual human watchability remains separate from metadata evidence. Record any
  paid fixture budget and request count. A later human allowance permits bounded
  Controller polling for this iteration only; it does not permit fixture inference,
  change frozen Worker briefs or establish deferred zero-token-waiting acceptance.

## Red-chair record — Controller, 2026-11-06

Engineering/authority lens, read-only pass before writing this contract.

1. **Major — ID laundering is not independence.** Exp 2's candidate
   `Workflow.review` checks distinct Run/worktree/session IDs, not context ancestry.
   Pi `forkFrom` supplies a new ID with inherited history. Changed design: no
   context-bearing reviewer launch in the first slice; subsequent review starts
   without author/fixer history, with lineage recorded for future enforcement.
2. **Major — resume can return tools to the old workspace.** Pi's documented
   session cwd is immutable; `--session` resumes it. Installed `main.js` routes
   `--fork` to `SessionManager.forkFrom`, which creates a new cwd/ID and copies all
   non-header entries. Changed design: explicit fork, private pinned snapshot,
   new credentials and held handshake; test the real host, not argv alone.
3. **Major — feedback can become accidental approval.** The Exp 2 contract binds
   review/check authority to exact outputs; a conversational "approved" cannot
   replace that. Changed design: separate per-finding disposition, candidate
   disposition and human authority provenance. Disagreement remains visible.
4. **Major — bootstrapping through rejected code defeats self-hosting safety.**
   Home `Launcher.launch` has no fork argument; frozen v2 rejects replacement
   reservation for an existing exp. Changed design: an independent, bounded
   bootstrap capability assignment, no hot upgrade, no historical mutation.
5. **Minor — context reuse can cost more or preserve stale assumptions.** This
   is a risk, not a measured saving. Full history may contain stale paths or
   sensitive tool output. Keep snapshots private and same-scope, overlay explicit
   current instructions, and measure before claiming cheaper/faster repair.

What would change the verdict: inability to prove new workspace/authority and
source immutability, or a requirement to weaken independent review, stops the
fork path. A concise handoff to a cold author remains the explicit fallback,
not something silently substituted for the human's requested reviewer fork.

## Execution record — 2026-11-06

Delegated 7.1 through the existing frozen-v2 implementation Board
`.bp3/exp2/board.sqlite`: exp `context-fork-primitive`, Run `exp7-fork-author`,
source `e442374f9866b639078ed9f688c1f752d45a35df`, 7200-second budget. This adds a
new assignment, not a replacement generation or rewritten historical base.
The running binary/bridge remain unchanged; prior author/reviewer assignments
and submissions are not rewritten.

Launch used the normal CLI with `model=openai/gpt-6-astra:xhigh` and omitted
`session_name`, inheriting `bp3-bp3-mvp-0100a83fd2`. Before delivery, public Board
state and Zellij metadata confirmed ready-held, one owned terminal (`6`) in tab
`3` (`bp3:exp7-fork-author`), usable `50×91` terminal geometry, exact workspace
and retained Controller focus. No brief or outputs existed at that check.
The normal `brief` op then queued `brief-exp7-fork-author`; the bridge recorded
observation, and structured session metadata confirmed `openai/gpt-6-astra`,
`xhigh`, session `01a1b1a3-5f26-7376-be72-36044fa3b2c9` and the new worktree.
This establishes launch/delivery, not implementation, human watchability or
completion. The actual prior-reviewer fork has not been launched.

Retained assignment packet, input snapshots, operation JSON and startup evidence:
`.bp3/exp7/`. Packet SHA-256:
`eb7f31e844cbd62d227ef71ef2783bf4ed145f1148b0129207daff97300f846f`.
`ready-held.json` and `brief-observed.json` distinguish requested thinking from
observed metadata. An initial verifier assumed the announced session JSONL was
already persisted before the first prompt; Pi had not created it yet. A second
verifier assumed `ps` retained full startup argv, but that assertion did not pass.
Neither failure caused a relaunch or an invented pre-brief thinking observation.
Ready/mount/model were checked before delivery; persisted thinking was confirmed
after delivery. Behavioral acceptance and independent review remain pending.

### Submission, independent checks and review launch — 2026-11-06

Immutable output `run-output-exp7-fork-author` names exact candidate
**`726328762e55aa7ec31fd1c0edf06da4c21f152c`**, one commit above `e442374`.
The assigned author worktree remains clean; its exp is `ready` and work lease
has expired without renewal. Submission establishes completion of author work,
not review acceptance. The Controller matched these submitted evidence hashes:

```text
author-evidence.md  48866c75edbcaa9a9238916d8138a507f717d06903b865b3ef76924f8beef009
exact-check.log    75961596a88ece0323e561758b45527b98c73e8617f4ba41cc06355b5f167343
held-drill manifest 72ce8d80d9b3dab89dd2e0c1ba80e90a1747f240ff75c6d1e49be286e932f814
```

The source evidence is `.bp3/exp7/author-evidence.md`; original exact-build log
and drill manifest are `/tmp/bp3-exp7-exact-7263287-check.log` and
`/tmp/bp3-exp7-held-fork-i/manifest.json`. The author's earlier failed attempts
remain described there, not converted into successful receipts.

**Fresh Controller check:** separate clone and clean detached worktree at
`/private/tmp/bp3-e7-review-7263287/verification`, exact candidate above.
`make check` exited **0** in 24.86 seconds: **74 OCaml tests** (36 genesis,
8 workspace, 30 fork), **17 Node tests**, none skipped; lint/build/format,
16 skill files and 37 installer assertions. Controller/session bindings were
omitted from the check environment. HEAD remained exact and source stayed clean.
Full output and receipt are `controller-make-check.log` and
`controller-check-receipt.json` under that fixture root. Log SHA-256:
`06973ff7d49256b1e4f933499c97e2a5ab64e00fca83f7ad6e555f316c345147`.
A green suite does not waive a reproduced counterexample or supply review judgment.

**Fresh independent review:** after the human confirmed reviewing the fork,
created a new disposable schema-v2 review Board in that separate clone through
normal operations. The unchanged frozen v2 binary/bridge coordinate Run
`exp7-astra-review`, exp `independent-fork-review`, budget 7200 seconds. This is
a cold launch, not a fork/resume of author/fixer history; schema v2's report API
will retain the review evidence rather than pretend to issue a native v3 verdict.
No old assignment, frozen base or lease was rewritten.

Before the brief, verified exact clean candidate/cwd, fresh session directory and
ID, ready-held/idle, empty inbox, one owned terminal **8** in tab **4**
(`bp3:exp7-astra-review`), usable **50×183** geometry, attached display and
preserved Controller focus in `bp3-bp3-mvp-0100a83fd2`. Endpoint confirmed Astra;
startup argv requested xhigh. Pi had not persisted its JSONL yet, so no pre-brief
thinking observation is claimed. Normal `brief` delivery became `observed`;
persisted metadata then confirmed **openai/gpt-6-astra, xhigh**, fresh session
`01a1b22e-4faf-71a4-b155-236925fafb4d`, correct cwd and no parent session.
Initial `list-clients --json` was refused by installed Zellij; supported plain
`list-clients` verified attachment before launch. No pane text or input was used.

Review assignment, input snapshots, operation JSON, frozen-runtime identity,
`ready-held.json`, `brief-observed.json` and check receipts are retained under
`/private/tmp/bp3-e7-review-7263287/`. Review packet SHA-256:
`70d0a6210a608ac459306053bea2cf40a24a3572869748622e1a1ae393a34330`.
Review scope includes the full patch, actual Pi boundary, source/feedback privacy,
retry/crash/mount/authority and the same-consumer handoff runbook. At launch no
verdict existed. This launch did not activate either candidate or start Exp 2 repair.

### Interrupted review and Controller disposition — 2026-11-06

The fresh reviewer saved `independent-findings.md` with verdict **FIX FIRST**,
then stopped with the provider's cybersecurity-risk refusal. Structured Pi
metadata confirms assistant entry `c6e47ac5`, `stopReason=error`, at
`2026-11-06T19:02:47.775Z`; the human also reported the displayed error. Its
specific triggering content is unknown. No retry/rephrasing or model substitution
was attempted to get around the refusal.

The Board still has **zero review Run Outputs**, no question, and an idle Run
with unexpired work authority at the follow-up. Idle is not completion. The saved
file is independent reviewer-authored evidence, **not a submitted immutable Board
review**; its prose describing report submission does not prove the op occurred.
The Controller did not impersonate the reviewer, use its credentials, extend its
lease or rewrite the Board. Report SHA-256:
`b2379a7db79c42e553d4c72a4dddf5b045616d4cbf3c673eb08a9e467161ca5f`.

**Controller disposition: accept all three findings for correction; hold use of
`7263287`.** Fresh reproductions ran from the separate exact verification build,
on new disposable fixtures only, preserving source and original review artifacts:

1. **Major — post-brief interactive input loses refusal.** After the first
   authoritative brief, interactive `took_over` signaling lies outside the
   fork's explicit consume-on-error block. Installed Pi catches its exception
   and reaches a new provider-stream boundary with `aborted=false` after the
   Board says `run is fenced`. Both ordinary submission and raw-input/submission
   ordering reproduced. Provider streaming was intercepted: **zero actual
   provider requests**, not a claim that paid execution occurred. The RPC probe's
   aborted boundary is explicitly different; tool guards still blocked work.
2. **Moderate — steering can impersonate the first brief.** Normal `steer` can
   occupy `brief-<Run>` with arbitrary text. It is offered/observed with no `brief`
   event, and the bridge opens its latch by ID. This is a Controller-API collision,
   not unauthenticated privilege escalation. Reserve the purpose/identity and
   validate the generated current-brief origin/text, not just offered-row equality.
3. **Moderate — unresolved source inbox is ignored.** Normal report → queued
   correction → cancel leaves a fenced, idle source that still passes source
   eligibility and reaches fork spawn. Check queued/offered source obligations
   consistently; do not require question-reply handling for an ordinary observed
   brief or silently rewrite historical obligations to make a source eligible.

Exact counterexample logs under the review fixture:

```text
controller-repros/board-boundaries.log
  90d1e0f7e1f89f173103775a283ec81647f5e36c2fb87ded30b5ff28ea96f0e2
controller-repros/installed-stream-boundary.log
  b35e966477eb3597ef5dbaa059dfb4bfc4e5fa7a51b248a940bbfac8d3005654
```

Both repro commands exited 0 because their **failure-demonstration assertions**
held; this is not a passing acceptance claim. Full argv, exit/time/hash and clean
source observations are in `controller-repros/controller-repro-receipt.json`.
`controller-disposition.md` records accepted findings, limits and next steps
separately from the unchanged reviewer report. All referenced reviewer-artifact
hashes matched its `review-evidence-manifest.json`.

The reviewer independently passed **74 OCaml / 17 Node tests** plus the existing
lint/format/skills gates, and one fresh real mounted held fixture at
`reviewer-held-fixture/` recorded zero provider requests, source preservation,
replay without respawn and detached-display refusal. Controller read and hashed
those outputs; this is not a Controller rerun of that mounted drill. These checks
do not eliminate the newly reproduced counterexamples.

Evidence correction: literal SIGKILL tests cover reserved, capturing, pinned,
worktree, spawning and spawn-returned, **not a literal ready-handshake death**.
The original author's ready-boundary coverage summary overstates that proof.
The concurrent-receipt regression likewise is not a scheduled two-client/mount
race drill. Preserve these gaps in subsequent acceptance work.

**Temporary human allowance:** bounded Controller polling/looping is permitted
**for this iteration only** to drive progress. Deferred Exps 4/5 and their
zero-token/deterministic-loop acceptance remain unchanged. This neither overrides
provider refusals nor resets Run/aggregate budgets, amends frozen Worker briefs,
waives independent review or grants activation/promotion/push authority. No fix
Run or real Exp 2 handoff has been launched at this checkpoint.

### Authorized repair loop and first fix Run — 2026-11-06

The human then requested **“lets fix”**, followed by continuing through the fork
capability and Exp 2 until Exp 2 is **approvable**. This authorizes routine bounded
repair/check/fresh-review handoffs, not home Quest/master movement, build
activation, promotion or push. Approvable requires an exact corrected candidate,
independent checks and accepting fresh review plus the existing acceptance gates;
human typing/release/watchability and other genuinely human checks are not waived.

Controller bounds this iteration to at most **three fix/review cycles across both
stages**, six newly allocated author/reviewer Runs, **3600 seconds per Run** and
**21600 aggregate reserved seconds**. A rejecting review consumes the same limit;
new Runs do not replenish it. Provider refusal, exhaustion, ambiguous authority,
changed scope or a human-only gate stops the relevant progression for resolution.
The earlier interrupted review is now expired and remains unsubmitted. No lease,
report or old evidence was rewritten. Local Controller allocation record:
`.bp3/exp7/repair-loop.json`; this is operational bookkeeping, not an implemented
Exp 5 scheduler or alternate Board authority.

First repair assignment uses a new isolated clone/Board at
`/private/tmp/bp3-e7-fix-7263287/`, pinned to exact rejected `7263287`. Normal
frozen-v2 operations created Quest `fork-repair`, bootstrap exp
`fork-correctness-repair` and cold author Run **`exp7-fork-fix-author`**. Its scope
is the three confirmed issues, faithful portable red-before/green-after
regressions and honest coverage/runbook updates. This remains the same planning
Exp 7 objective; the separate bootstrap exp is a v2 rework/base limitation, not a
new objective. The rejected fork does not coordinate or context-fork its own fix.

Before normal brief delivery, verified exact clean input/worktree, no inherited
session, ready-held/idle, one owned terminal **9**, tab **5**
(`bp3:exp7-fork-fix-author`), **50×183** geometry, attached display and preserved
Controller focus in the same bound session. Endpoint showed Astra; startup argv
requested xhigh. Persisted metadata after brief observation confirmed
**openai/gpt-6-astra, xhigh**, session
`01a1b2d5-fe03-73b5-bc83-9d78328fcf64`, correct cwd and no parent session.
No pre-brief thinking-file observation is fabricated. Worktree:
`/private/tmp/bp3-e7-fix-7263287/worktrees/exp7-fork-fix-author`.

Pinned input snapshots, `repair-packet.md`, normal operation JSON, runtime
identity, `ready-held.json` and `brief-observed.json` are retained in that root.
Packet SHA-256:
`5f67b2a4a5941346053bd4bd63948e7a7d2ba7bab85278b06ad2a0368c77a950`.
The unchanged `.bp3/exp2/frozen/{bp3,bridge.ts}` coordinate this new Board;
candidate execution remains confined to fresh disposable fixtures. Controller's
temporary watcher reads normal public Board context and structured error metadata,
not terminal contents, and neither launches work nor changes authority itself.
The next observations supersede that launch-only checkpoint.

### First repair submitted; independent gate failed; fresh review launched

Run `exp7-fork-fix-author` submitted immutable output
`run-output-exp7-fork-fix-author` at exact **`a53b5c3558a22f21d99f61383b7f8874c26396ba`**,
one commit above `7263287`, eight changed files. Its worktree is clean, report
complete and session settled; no further work was assigned to it. Author evidence
is `/private/tmp/bp3-e7-fix-7263287/author-evidence.md`, SHA-256
`d4e56bc900e4f6de2bac509abc40023381b2024ae53fd1e4137de841394ed664`.
The referenced artifact manifest hash matched
`86e77b72b53176270bfe02b8cd67df3ee33b8eed79b372e29863c949d7c0cccc`.

The repair puts interactive/RPC/extension admission and manual controls behind
explicit refusal decisions; adds an RPC `input` signal; checks successful current
brief receipt/event plus generated text and returns a purpose acknowledgement;
reserves `brief-*` against steering; and rejects source queued/offered obligations
from the same read-only snapshot. It requires the matching admission-v2 bridge
marker, not a schema migration. Permanent tests retain the real Pi Agent lifecycle
and intercept only provider I/O. These are implementation descriptions, not
accepted correctness claims.

Author reports clean exact `make check` passing **84 OCaml / 37 Node tests**,
with final permanent test overlays failing against unchanged `7263287` production
code. Its report distinguishes primary counterexamples from unknown-new-protocol
failures, and retains a corrected preliminary user-bash test-caller mistake.
Literal ready-handshake death remains unverified; no new mounted drill was run
by that author. Those limitations are now explicit in the candidate runbook.

**Fresh Controller check FAILED:** from independent clean detached
`/private/tmp/bp3-e7-fix-review-1/verification`, `make check` exited **2** in
77.883 seconds. **84 OCaml tests passed; Node: 36 passed, 1 failed, 0 skipped.**
The failure is `REAL brief observation retries an identical envelope after lost
response` at `tests/pi-fork.test.mjs:254`: `admit()` asserted
`lifecycle.includes("agent_settled")` false after waiting for a stream boundary
and `session.isIdle`. Settling-event order is a hypothesis, not a demonstrated
root cause at this checkpoint. Later format/skills steps were not reached.
HEAD/source stayed exact and clean. Full output/receipt are
`controller-make-check.log` / `controller-check-receipt.json` in that review root;
log SHA-256:
`9de43f7c669c8b50ba934009d45e8f593b3b34225089126b54902a101c08270b`.
No rerun-until-green or weakened check erased the failure.

Controller intentionally proceeded with **read-only review, not acceptance**, to
collect all reliability/semantic findings before another repair. Fresh cold Astra
xhigh Run `exp7-fork-fix-review`, budget 3600 seconds, uses a new independent clone
and frozen-v2 Board under `/private/tmp/bp3-e7-fix-review-1/`. It received the failed
check and full patch/evidence in its frozen brief. Normal launch verified exact
clean SHA/cwd, new session, attached **50×183** terminal **10** in tab **6**
(`bp3:exp7-fork-fix-review`), with Controller focus retained. Persisted metadata
after observed brief confirmed Astra xhigh, no parent session, ID
`01a1b2ee-4a55-7605-8370-ba34ae43cf83`.
Review packet SHA-256:
`987081af5898f8bf99bc5db15e4bc15acf8e251709cfdbf9b5b3ac1a8ba69c2f`.
Two Runs / 7200 reserved seconds are allocated from the iteration cap; no budget
was renewed and neither candidate is activated. At launch no new verdict was
claimed; the later saved findings and interruption are recorded below.

**Supplemental Controller ready-stage recovery drill:** exact `a53b5c3` ran a
provider-free real Pi/Zellij fork in a new owned fixture. After actual committed
ready, the Controller SIGKILLed only its owned runtime (exit **-9**), restarted
the identical binary/bridge, and observed a fresh heartbeat from the same child
endpoint, one Run and the same terminal identities. Exact launch retry inspected
the ready attempt without respawn. Source Board/transcript hashes stayed fixed;
no brief/task was delivered and the loopback provider sink counted **0 requests**.
Detached-display refusal still passed. Teardown removed only the fixture namespace;
a scoped process-metadata check found no remaining fixture processes.
This proves recovery **after committed ready**, not every instruction around the
ready-response write, human watchability or a passing full suite. It does not erase
the independent `make check` failure or upgrade the frozen coordination runtime.

Retained under `/private/tmp/bp3-e7-fix-review-1/`: temporary verification driver
`controller-ready-recovery.py` (outside source), full log and
`controller-ready-fixture/manifest.json`. Manifest SHA-256:
`95abe286217b0efbf71bc93e628cbfa61645742b70c6d37ca6c986aa57b9f069`.
Binary/bridge hashes match the submitted build. No permanent test or candidate
source was edited to run this supplemental drill.

### Repair review interrupted; two new findings reproduced; loop paused

Cold `exp7-fork-fix-review` saved **FIX FIRST** for exact `a53b5c3`, then hit the
provider's possible-cybersecurity-risk refusal at **2026-11-06T22:33:11.527Z**,
assistant entry `9f2a8a5f`, `stopReason=error`. Structured metadata, not pane text,
establishes the interruption; its triggering content is unknown. The Board had
**no Run Outputs and no questions**. The report's intended-submission wording is
not evidence of submission. Preserve it unchanged; no Controller impersonation,
old credentials, fabricated output or lease renewal was used to finish it.

The Controller read the full report, verified all **37 artifact fingerprints**,
and independently ran its unchanged provider-free probes from the separate exact
clean `verification` worktree. Both counterexamples reproduced:

1. **High — built-in summary misses the post-brief admission fence.** Real Pi
   editor `/bug` dispatch and summary/dialog flow reach a second **un-aborted**
   model boundary while the raw-input takeover authorization is pending and will
   refuse. Abort flags are `[false, false]`; only one Agent start occurred; the
   summary includes the synthetic inherited-history marker. This is a path not
   covered by ordinary `input`, compaction or fresh `agent_start`. Provider I/O
   alone was intercepted: **zero actual provider requests**, not an observed
   charge, upload or disclosure. Rendering and authority timing use test doubles;
   this is an installed-caller reproduction, not real human-terminal acceptance.
2. **Medium — deterministic test synchronization defect.** Holding the bridge's
   `settled` response reproduces the failed `admit()` assertion with `isIdle=true`
   but no subscriber `agent_settled`. Installed Pi clears active-run state before
   awaiting extension settlement and only then notifies subscribers. Releasing
   the reply produces exactly one settled event without another stream boundary;
   retried observation envelopes remain identical. This proves the ordering
   assumption invalid, not the exact original Controller scheduler trace.

The reviewer's one `make check` passed (exit **0**, 80.028 seconds, **84 OCaml /
37 Node**, no skips). It does not erase the Controller's failed full gate. Both
new probe processes exited **0 because counterexample assertions held**, not
because `a53b5c3` passed acceptance. No candidate source was changed or committed.

Retained under `/private/tmp/bp3-e7-fix-review-1/`:

| Artifact | SHA-256 |
|---|---|
| Saved, unsubmitted `independent-findings.md` | `b8790a19cdb5fa8871ab8ca1f957aca89b11399d481f592993afe858351cc808` |
| `reviewer-artifacts.json` | `9d3bb1c1e960f82c491c13da3451f917471fc64263c3d383816e319cb7621211` |
| `controller-repros/settle-ordering-probe.log` | `6233ba11bc2951968042cc0fd210fb0cbad83fedd4f96224b13a53efc61d8fe8` |
| `controller-repros/bug-summary-probe.log` | `74c839b2b18a9e96eef04313fe92f0ee9e4ca2826715df2b07ed9dcdfaa77e4e` |

`controller-provider-interruption.json` retains the exact provider error and
Board observation. `controller-repros/receipts.json` binds argv, source hashes,
times/exits and exact clean source. Separate `controller-disposition.md` accepts
both findings for fixing and holds the candidate; it is not reviewer approval.

**Progression is paused**, not silently retried or switched to another model.
The allocation ledger remains **2 of 6 Runs / 7200 of 21600 reserved seconds**;
reservations are not actual usage and unused authority is not refunded/reset.
No new author or Exp 2 handoff was launched. Resolve the provider refusal through
its supported access/support process before model-driven continuation; do not
rephrase to evade it. Any subsequent repair requires portable faithful red/green
regressions, supported fail-closed built-in admission, actual-event test
synchronization, a new exact candidate and fresh independent checks/review.

### Cycle 2 settlement author launched — 2026-11-06

Normal frozen-v2 operations created the separate bootstrap Board at
`/private/tmp/bp3-e7-settle-a53b5c3/`, Quest `fork-settlement`, exp
`fork-settlement-repair` and cold author Run **`exp7-settle-author`** on exact
`a53b5c3`. This is the same planning Exp 7, not native v2 rework or forked self-repair.
Scope: actual-event test synchronization, deterministic faithful red/green coverage
and accurate runbook limitations; no general built-in integration. In particular,
red evidence must retain the old defective test helper rather than overlay its fix.

Before briefing, exact clean cwd/input, cold launch/session directory, held-ready
idle state, attached display and owned **terminal 11 / tab 7**, **50×183** geometry
were verified. Controller focus stayed on tab 0. Normal brief observation then
persisted Astra xhigh and cold session **`01a1b328-93c0-73d3-9c04-a6a00d55374d`**.
Session JSONL was absent before the brief; pre-brief thinking is not claimed.
Packet SHA-256: `56c8fad25a012acc44f7179fa5eb3fce2b5c86b92a81212ec953cd041683aa5f`.
Inputs, normal operation JSON, runtime identity, capacity/ready/observed receipts
are retained in that root. **3/6 Runs and 10800/21600 reserved seconds allocated**;
author deadline is fixed at launch plus 3600 seconds, not renewed by continuation.

Capacity inspection found no valid old work authority. The interrupted cycle-1
review runtime refused connection and its deadline elapsed, although frozen v2
still projected `desired=run`; deadline checks fence it without rewriting history.
The main frozen coordinator still pings as PID 97093 and both hashes are unchanged.
No claim of quota diagnosis/resolution, new submission or acceptance follows from
launch. Any fresh provider/capacity error remains a stop, not an automatic retry.

### Cycle 2 submitted and fresh review launched — 2026-11-06

Immutable `run-output-exp7-settle-author` names exact
**`4e61d7c4b1a54299b870205267692a504e7207c6`**. Its clean diff changes only
`tests/pi-fork.test.mjs` and `docs/context-fork.md` (99 insertions, 14 deletions).
Production, Makefile and other check gates are unchanged. Author evidence:
`/private/tmp/bp3-e7-settle-a53b5c3/author-evidence.md`, SHA-256
`d93c3d8282c46455f5a470095e8084eedcaa3b8a1e312580ba7ad43aa591bfa9`.
Controller matched all 23 author-manifest artifact hashes and independently
verified the baseline retains the original defective helper; replacing only that
helper makes its instrumented test byte-identical to the new test. The retained
red fails the precise old assertion; green waits behind the socket barrier until
actual subscriber settlement. This audit is not a Controller execution of the red.

From separate clean exact `/private/tmp/bp3-e7-settle-review/verification`,
**`make check` exited 0 in 84.240 seconds: 84 OCaml / 38 Node, no skips**, plus
lint/build/syntax/format, 16 skill files and 37 installer assertions. Source stayed
exact/clean. Log SHA-256:
`50c79eaa505d9dd3a46e458bacbbb2542b3fd2351c5693198821df912f1284fe`.
Binary/bridge match `a53b5c3` byte-for-byte; no new production recovery behavior is
claimed. The explicit `/bug` limitation and remaining proof gaps remain visible.

Fresh cold Astra xhigh reviewer **`exp7-settle-review`** uses normal frozen-v2
operations on the new review Board, with a fixed 3600-second budget. Before normal
brief delivery: exact clean cwd/SHA, cold session directory, held-ready idle state,
attached owned **terminal 12 / tab 8**, **50×183**, and preserved Controller focus
were verified. Observed brief metadata confirms no parent session, Astra xhigh,
ID **`01a1b339-c21d-7503-acb4-aa861cc99cba`**. Thinking was persisted after delivery,
not claimed before it. Review packet SHA-256:
`390cf30ee73422141f88af65fe399690844912519968fadd8c89647f3f5b1e2a`.
Receipts/inputs/checks/provenance audit are under `/private/tmp/bp3-e7-settle-review/`.
**4/6 Runs and 14400/21600 reserved seconds allocated**; no lease reset.
No handoff, activation or approval follows from this launch. Read-only Exp 2
source preflight still matches the original completed review/session and clean
same-consumer checkout; it is observation, not frozen fork authority.

### Submitted SHIP and controlled-use disposition — 2026-11-06

Unlike the prior interrupted reports, immutable **`run-output-exp7-settle-review`**
exists for exact `4e61d7c`. Its **SHIP for controlled same-consumer handoff** report
hash matches submitted evidence:
`f87f3ea1ebabbdc0f2e2a46c53cfc98e4b855769db8ff472be3603c99bcdea3c`.
Reviewer `make check` exited **0 in 82.635 seconds**, **84 OCaml / 38 Node**, no skips,
and its supplemental expected-timeout/teardown probe passed with zero provider
requests. Controller read those results and verified all **73** reviewer artifact
fingerprints; it did not relabel that supplemental execution as its own.

Separate `/private/tmp/bp3-e7-settle-review/controller-disposition.md` accepts the
exact capability for the scoped 7.2 handoff, retaining the explicit `/bug` exception
and unrun readiness/child-death/two-client/human gates. At-most-one launch and
inspect-only ambiguous-attempt holds support controlled use, not a claim of full
recovery proof or overall Exp 7 completion. Pin exact binary
`8e24a9f3de75f38af5568d2052a9c7c1509a00474ef29295080cdc3d08068c1c`
and bridge `353bf08f644d58392f5219919fb553b49e6b5d9aa28b3269ec2152283cbe934a`
only for a new Board/target/sibling worktree in the prior Exp 2 review consumer.
The main frozen coordinator, home refs and rejected Exp 2 kernel remain untouched.

**Completed bootstrap authority fencing:** v2 cannot seal reported Runs. After
verifying immutable exact outputs, final completed session, idle/no-interaction,
no obligations and clean worktrees, Controller used normal `cancel` on
`exp7-settle-author` and `exp7-settle-review` to revoke their remaining work
permission before the next author. V2 marks these bootstrap assignments cancelled
and advances their generations; this is explicitly **not native sealing, code
rejection, landing, successful retirement or tab closure**. Outputs, reports,
worktrees, session bytes and fixed deadlines were preserved. Per-root
`controller-fence-completed{,-receipt}.json` retain the operations/observations.
Existing allocations remain consumed; there is no budget refund or reset.

### Actual 7.2 handoff launched; final cycle author active — 2026-11-06

Accepted exact `4e61d7c` binary/bridge are pinned at
`/private/tmp/bp3-e2-context-repair-e512/frozen/`, coordinating only that root's
new schema-v2 Board. Normal `fork-launch` created **`exp2-context-fix-author`**,
from rejected Exp 2 code `e512fe5` and completed source reviewer
`exp2-astra-review`, within its existing `/private/tmp/bp3-e2-review-e512/repo/.git`.
New target `refs/heads/quest/exp2-context-repair` and a sibling author worktree do
not move the old review target or home refs. Separate v2 bootstrap assignment is
an explicit compatibility mechanism, not native v3 rework or a new planning exp.

Child session **`de48784cffc68fd08288b076fe63e05930dec9660c37ef60`** has new authority
and cwd, private captured source parent, and byte-equivalent parsed **166-entry**
inherited non-header prefix. Source session
`01a1b157-5e28-704d-8277-37200a9096d1`, leaf `ed8bdbc4`, and SHA-256
`2d0faf575cdd7513b1a1bad5fcc8abc3da92b16ac1393d1175f59060cd13720b` remain pinned.
Controller revalidated source output/brief/clean worktree/no obligations,
Astra xhigh launch and persisted metadata, actual owned tab **9** / pane **13**,
geometry **50×183**, held/no new task messages, and preserved Controller focus
before the sole normal brief was observed. Real model-driven work then began.
This is a started handoff, not completed repair, human watchability or independent
approval. Live provider traffic was not instrumented; no measured-zero claim.

**Retained Controller verification failure:** the first pre-brief guard compared
the source runtime's live event cursor as if it were immutable. It held delivery.
Two saved observations differed only in `at`/`cursor`; read-only event inspection
since preparation found only that source runtime's normal `reconcile` events,
with assignment/output/inbox/question rows unchanged. Initial full before
snapshot was not persisted, so no byte-identical source-Board claim is made.
The failed `controller-bootstrap.py` remains unchanged; separate
`controller-verify-held.py` revalidated the same child's pinned source and current
rows, ancestry/model/mount/identity and delivered the existing brief operation.
No respawn, launch-file change, candidate patch, source mutation or deadline
extension. Receipts and diagnosis are retained in the new assignment root.

Ledger now consumes **5/6 Runs, 18000/21600 reserved seconds**, cycle **3**. The
3600-second author reservation includes its held launch interval; no refund/reset.
One cold final reviewer remains. The four accepted Exp 2 findings and truthful
red/green permanent tests remain required; inherited reviewer knowledge gives no
self-approval rights. See the [current Exp 2 record](2026-11-05-auto-land.md#actual-prior-reviewer-context-repair-started--2026-11-06).

## Runbook, recovery and next step

Use normal Board/runtime operations to delegate; omit `session_name` to inherit
`BP3_SESSION`. Check usable attached display metadata before launch, then exact
owned mounted terminal and ready-held state before delivering a brief. On an
ambiguous launch inspect the same attempt; never type into panes or rewrite a
launch file. Preserve source histories, review report, fingerprints and artifacts.

Disable new fork launches to roll back the capability; existing assignments and
history retain their authority. Runtime switches, migrations and deployment must
be explicit and version-bound, never an incidental effect of building code.
**Retained cycle-3 stop:** cold `exp2-context-fix-review` submitted FIX FIRST on exact
`915311d`, without fixer ancestry. Controller verified all 62 reviewer fingerprints
and reproduced both variants of the ordinary observed/admission race with real Pi
and production Board operations (provider-free). Its own timeout-setup failure
and the reviewer's four readiness errors remain failed independent gates; Node
was not reached in either full run. This is a completed knowledge-handoff/output/
cold-review cycle, not an accepted Exp 2 repair or overall Exp 7 completion.

All **6/6 Runs and 21600/21600 reserved seconds** are allocated; no further
automatic cycle/replacement/reset is available. Completed author and reviewer
were normally cancelled only after submitted/idle/no-obligation verification,
to fence unused v2 work authority; outputs, histories, deadlines and tabs remain.
Not native sealing, retirement, code approval or budget refund. Full findings,
repro limits and hashes: [final Exp 2 disposition](2026-11-05-auto-land.md#final-review-submitted-controller-reproductions-iteration-paused).
The recommended additional pair was not authorized at that stop. The human then
replied **“yea”**: one author plus cold reviewer, at most 3600 seconds each, is
now authorized. Overall ceiling becomes **eight Runs / 28800 reserved seconds**;
the previous six/21600 remain consumed. New author **`exp2-delivery-fix-author`**
is now launched and normally briefed through the unchanged accepted `4e61d7c` tool on a
new Board under `/private/tmp/bp3-e2-delivery-repair-915311d/`, source completed
reviewer `exp2-context-fix-review`, input `915311d`, and a new target/sibling
worktree in `/private/tmp/bp3-e2-context-review-final/repo/.git`. Fresh source
hash/leaf/completion, review fingerprints and capacity were checked; source
history/authority and prior use receipts remain unchanged. New session
`0a6b3ab13dba352376384b6d4e9e82ed7c9dbe8f71606e26` has an exact parsed/raw-line
**205-entry** inherited prefix; held verification confirmed current Astra xhigh,
clean exact cwd, owned tab **11** / pane **15**, **50×91** geometry and Controller
focus before the sole brief. Source rows were persisted/compared without treating
normal reconcile cursor traffic as immutable identity. No respawn or deadline
extension. **7/8 Runs / 25200 of 28800 reserved seconds** allocated; one cold
review slot remains. This is another explicit same-consumer assignment, not
global activation, cross-clone transfer, completed fixes or human watchability.
That author has now submitted exact **`9e1b1d0`**, with author and fresh Controller
clean full gates passing **132 OCaml / 44 Node**. Controller audited 1361 hashes,
85 baseline files and exact overlays/helper prefixes; this is not a rerun of the
historical reds. Normal v2 cancellation after final stop/idle fenced unused
authority while preserving output/history/deadline/tab. Final cold reviewer
`exp2-delivery-fix-review` is now active through unchanged frozen v2, session
`01a1b3f1-6cac-7188-9b9f-0fa91b6f04c9`, no parent, tab **12** / pane **18**,
**50×91** geometry. Exact cwd/model/mount/focus were checked before normal brief;
persisted xhigh/no-parent metadata followed delivery. **8/8 Runs / 28800 of
28800 reserved seconds** allocated, with no ninth Run or automatic replacement.
The reviewer has now **actually submitted SHIP for bounded engineering review**
on exact `9e1b1d0`; its own clean gate passes **132 OCaml / 44 Node** in
**133.502981 seconds**. Controller matched all **669** reviewer fingerprints,
accepted the scoped disposition and freshly ran six provider-free probes. The
extra context-filter counterexample is retained outside the actual isolated
managed extension selection; it is not an accepting test or a new supported-work
waiver. Both completed actors' unused v2 authority was normally cancelled after
final stop/idle checks, without tab closure, history loss or budget refund.
This real knowledge-handoff/output/cold-SHIP cycle is not full Exp 7 or Exp 2
acceptance. Remaining human/live/death-window/onboarding gates need a separately
scoped/budgeted next decision; no further Run is launched. See
[Exp 2 submitted SHIP and limits](2026-11-05-auto-land.md#submitted-engineering-ship-acceptance-rehearsals-still-pending).
Do not rewrite older submissions or revive old credentials.
A fresh provider/capacity error stops progression again; no automatic replacement. Preserve both interruptions, both unsubmitted reviews and the
failed gate. Bounded Controller polling is allowed for this iteration, but an
interruption is a decision point, not a reason for endless retries or budget resets.
The narrow fork capability and actual 7.2 assignment are pinned; the global
coordinator remains unchanged. No home master/Quest-target movement, activation
or push is authorized.
