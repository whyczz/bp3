# bp3 Pi basics: oh-my-pi, subagent extensions, and the speed meta

Question this serves: what should a bp3 Pi engine actually be built
on — vanilla Pi plus which extensions, or the oh-my-pi fork — and
how is Pi made fast in practice? Reader: the implementer of the Pi executors Quest. Evidence date: 2026-11-08; star counts are
GitHub-API-verified only where stated, download ranks churn fast.

## Map

### oh-my-pi (omp)

- A hard fork of Pi (Stencil Labs, npm
  `@oh-my-pi/pi-coding-agent`), not an extension pack:
  [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi), about
  38.2k stars and actively pushed as of 2026-11-08; upstream
  [earendil-works/pi](https://github.com/earendil-works/pi) sits
  near 120k stars. omp advertises 60+ providers, 31 built-in tools,
  LSP and debugger operations, and a Rust core.
- Subagents are a first-class `task` tool: batched or single,
  background-capable, per-item model/effort/output-schema/tools/
  isolation, and a shared `context` string rendered into every
  child's system prompt. Children do not inherit conversation
  history; carry-over is the workspace tree, skills, rules, and
  approved-plan references. Isolated children run in copy-on-write
  worktrees with merge-back. Finished agents park and can be revived
  by messaging — explicitly preferred over respawning.
- Extras: an advisor role watching on its own model/context,
  parallel `/review` reviewers, and role-based model routing
  (default/smol/slow/vision/plan and friends).
- Costs: a 31-tool built-in surface versus Pi's sub-1k-token core.
  Every tool schema is per-request tokens. The fork's upstream merge
  policy is undocumented in the sources read, and its `settled`/
  idle honesty under bp3's bridge contract is untested.

### Pi subagent extensions, ranked (API-verified stars)

- [nicobailon/pi-subagents](https://github.com/nicobailon/pi-subagents)
  (about 4.2k stars): in-process foreground sessions (fastest),
  detached background runner, built-in scout/researcher/worker/
  reviewer roles, lazy loading that avoids busting the prompt cache.
  Roughly 788k downloads/month — the download leader in this class.
- [tintinweb/pi-subagents](https://github.com/tintinweb/pi-subagents)
  (about 1.4k stars): Claude-Code-style UX, steering and resume,
  background by default, even runs Claude Code workflow scripts.
- [Michaelliv/pi-dynamic-workflows](https://github.com/Michaelliv/pi-dynamic-workflows)
  (about 1.2k stars): the model writes sandboxed JS workflows
  (agent/parallel/pipeline/budget) in the Michaelliv shape.
- [mjakl/pi-subagent](https://github.com/mjakl/pi-subagent) (small):
  one separate Pi process per child, fresh context by default;
  parent-context cloning exists and is called out as expensive.
- The official Pi example subagent extension is process-per-child
  with small concurrency caps. Pi core deliberately ships no
  subagents, plan mode, or MCP.

### The wider extension meta (downloads/month, 2026-11)

From [awesome-pi.site/extensions](https://awesome-pi.site/extensions/):
`pi-mcp-adapter` (one proxy tool for all MCP servers, about 1.56M),
`pi-web-access` (search/fetch/PDF/video, about 1.22M),
`pi-subagents` (above), then ask-user-question, context-mode,
todo, plan-review, and LSP/lint extensions in the 90–170k band.
One catalog leader (a billion-context package near 3.1M/month) was
treated as suspect/inflated and excluded. Star counts for most of
these were not API-verified in this pass — downloads only.

### Speed, as actually practiced

- Keep the cached prefix stable: small, fixed tool surface; never
  add tools mid-session (each schema is tokens, and changes bust
  the prompt cache); lazy-load heavy tools.
- Compact rarely: LLM summarization breaks the cached prefix.
  Defaults reserve headroom and keep recent tokens; offload recon
  to fresh-context subagents so the parent stays small.
- Route models by role: cheap/fast models for scouts and titles,
  strong models for implementation and review.
- Reuse sessions: Pi session trees (fork/resume/continue), omp
  parked-agent revival, named persistent sessions. Respawning to
  re-buy context is the anti-pattern this whole exercise exists to
  kill.
- Vendor numbers stay unverified until measured locally:
  context-mode "98% reduction", omp prewalk "70–80% saving", and
  similar claims are marketing until a bp3 fixture says otherwise.

## Forces

- Cache economics punish novelty: every extension, tool change, and
  compaction is paid for in re-bought context. Minimalism is a
  speed feature, not austerity theater.
- In-process children are fastest but share fate with the parent;
  process-per-child isolates crashes at full context rent per child.
- A fork (omp) bundles everything first-class but couples bp3 to
  one maintainer's merge cadence and a fat tool surface; extensions
  keep vanilla Pi upstream-clean at the price of composition risk.
- bp3's bridge contract (`agent_settled`/`isIdle` honesty, session
  fencing) is unproven against every option here. A fast engine
  that lies about being settled breaks delivery gating.

## Options

- **Vanilla Pi + pi-subagents (lean).** Smallest delta from today,
  in-process speed, upstream releases. Composition risk sits with
  bp3; honesty must be proven on the toy fixture.
- **Vanilla Pi + dynamic-workflows.** Scripted fan-out in the same
  shape as Muse workflows; useful if one orchestration mental
  model across harnesses matters more than UX polish.
- **oh-my-pi wholesale.** Everything first-class: task tool,
  advisor, review, routing, worktree isolation. Pays with the
  31-tool surface, fork drift risk, and a re-prove of bridge
  honesty against a different binary.
- **Doing nothing.** Keep single fresh Pi Workers. Proven fencing
  and honesty; pays full context rent per Run forever.

## Open questions (ranked by what they change)

1. Does fan-out preserve settled/idle honesty and generation
   fencing under the bridge contract? A no kills whichever option
   fails, cheaply, on the toy fixture. Owner: implementer (Pi executors Quest).
2. Fork versus compose: is omp's bundled surface worth leaving
   vanilla upstream? Default: compose on vanilla; adopt the fork
   only if the Pi executors Quest shows extension friction dominating. Owner: human.
3. Which roles earn distinct models, measured how? Default: scouts
   cheap, author/reviewer strong, disagreement measured before
   routing spend. Owner: implementer.
4. How much of the download meta is signal versus churn? Default:
   re-check quarterly, never auto-adopt. Owner: whoever runs Pi
   exps.

## What I did not verify

- No bp3 run of any option: settled/idle honesty, fencing, and
  context savings are unmeasured until the Pi executors Quest spikes.
- Star counts beyond the four ranked repos, all vendor performance
  claims, and one snippet-only dynamic-workflows package.
- omp fork divergence and merge cadence versus upstream Pi.
