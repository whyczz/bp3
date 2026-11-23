# Harness engineering that ships (GitHub proof)

Checked 2026-11-23 against the GitHub API (`gh api`), default-branch HEAD, and raw files. Stars are not used as proof. Short quotes only. "Can learn from" means the license allows reading the idea; it is not permission to copy code into bp3.

404s and redirects:

- `mariozechner/pi` is 404. `badlogic/pi-mono` resolves to `earendil-works/pi`. `badlogicgames/pi-mono` is 404.
- `ghuntley/how-to-ralph` is 404. The live Huntley repo is `ghuntley/how-to-ralph-wiggum` (a fork). The loop people actually run is `snarktank/ralph`.
- `sourcegraph/amp` is 404. Amp is a closed CLI that `snarktank/ralph` shells out to. No GitHub proof of Amp's loop.
- `gastownhall/gastown` and `gastownhall/beads` exist. `steveyegge/gastown` redirects to `gastownhall/gastown`.

## What is the smallest loop that still lands a commit?

### Takeaway

The loops that still move are one coding-agent process plus tools, or a thin outer process that starts a fresh agent and lets that agent commit. Multi-agent towns exist as real Go/Elixir/bash, but the commit is still made by one worker agent, and a human or a scripted gate sits before merge. Several named "harnesses" are skills or worktree CLIs and never land a commit themselves.

### Cited Findings

**Pi (`earendil-works/pi`)** — MIT, copyright 2025 Mario Zechner. Org earendil-works (earendil.com). Default branch `main`. HEAD `8c47efc7b4f07210b89a1c0207f98be05abfc82d` (2026-11-23), "fix(ai): drop shut down Groq models…". Latest release `v1.6.0` published 2026-11-20. Pushed 2026-11-23. Last month of subjects is provider-catalog fixes, p2 UI/voice, and small agent fixes, not a new orchestrator. — [repo](https://github.com/earendil-works/pi)

Smallest loop is one process. `packages/agent/src/agent-loop.ts` exports `runLoop`: an outer `while (true)` and an inner loop that streams an assistant message and runs tool calls until there is nothing queued. README: "Pi ships with powerful defaults but skips features like sub-agents and plan mode." Built-in tool names in `packages/coding-agent/src/core/tools/index.ts` are `read | bash | powershell | edit | write | grep | find | ls`. `packages/coding-agent/docs/how-pi-works.md`: one turn is request, stream, execute tools, record results; another turn only if tool results or queued messages require it. Sessions are a JSONL tree; compaction inserts a summary and leaves old entries in the tree. Extensions are TypeScript loaded into the same process. Pi does not commit for you; the model uses `bash` if the user asked for a commit. — [how-pi-works](https://github.com/earendil-works/pi/blob/8c47efc7b4f07210b89a1c0207f98be05abfc82d/packages/coding-agent/docs/how-pi-works.md) [agent-loop.ts](https://github.com/earendil-works/pi/blob/8c47efc7b4f07210b89a1c0207f98be05abfc82d/packages/agent/src/agent-loop.ts)

**Ralph (`snarktank/ralph`)** — MIT, copyright 2026 snarktank. HEAD `6c53cb0b831ebe8739c6a003e22af14902d8b0b5` (2026-02-02). No commits since 2026-10-23. README: "Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`." Based on Geoffrey Huntley's pattern. — [repo](https://github.com/snarktank/ralph)

`ralph.sh` is a bash `for` loop, default tool `amp`, else `claude`, default `MAX_ITERATIONS=10`. It pipes `prompt.md` into `amp --dangerously-allow-all`, or `CLAUDE.md` into `claude --dangerously-skip-permissions --print`. The shell does not commit. It exits 0 only if stdout contains `<promise>COMPLETE</promise>`. `prompt.md` tells the agent to pick the highest-priority story with `passes: false`, run typecheck/lint/test, and only then `commit ALL changes` as `feat: [Story ID] - [Story Title]`, then set `passes: true`. — [ralph.sh](https://github.com/snarktank/ralph/blob/6c53cb0b831ebe8739c6a003e22af14902d8b0b5/ralph.sh) [prompt.md](https://github.com/snarktank/ralph/blob/6c53cb0b831ebe8739c6a003e22af14902d8b0b5/prompt.md)

`ghuntley/how-to-ralph-wiggum` is a fork of `ClaytonFarr/ralph-playbook` (API `license` none). HEAD `88d488a148af97e4a3f22b11b4c3598c79d6a577` (2026-01-11), message "formatting". README describes three phases and two prompts (planning writes `IMPLEMENTATION_PLAN.md` only; building implements and commits). It is a playbook, not the runner. — [repo](https://github.com/ghuntley/how-to-ralph-wiggum)

`ghuntley/how-to-build-a-coding-agent` is a Go workshop (files `chat.go`, `bash_tool.go`, `edit_tool.go`, `read.go`, `code_search_tool.go`). API license none. HEAD `fa3dd49fdddf45e92b35c66746e6bb6aac6ac27e` (2026-10-09). No commits since 2026-10-23. Loop body was not opened. — [repo](https://github.com/ghuntley/how-to-build-a-coding-agent)

`mbernet/ralph-wiggums` exists (MIT, 0 stars, HEAD activity 2026-11-19, description "several workers share one project through a task API"). Its code was not opened. Not evidence of Huntley's loop.

**Aider (`Aider-AI/aider`)** — Apache-2.0. `paul-gauthier/aider` redirects here. HEAD `5dc9490bb35f9729ef2c95d00a19ccd30c26339c` (2026-05-22), merge adding an Anthropic model. No commits since 2026-10-23. Docs: "Whenever aider edits a file, it commits those changes." Commit messages come from "the `--weak-model`". Default skips pre-commit hooks via `--no-verify`. Code search hits `def auto_commit` in `aider/coders/base_coder.py`. One process, edit tools, then a commit. No subagent grader in the git doc. — [git.md](https://github.com/Aider-AI/aider/blob/5dc9490bb35f9729ef2c95d00a19ccd30c26339c/aider/website/docs/git.md)

**OpenAI Symphony (`openai/symphony`)** — Apache-2.0. HEAD `be10a1b79df723d6d7612b5651c8522704dafb2e` (2026-09-15), "ci: publish nightly binaries on main pushes". No commits since 2026-10-23. README calls it a "low-key engineering preview". The spec is the product: "Tell your favorite coding agent to build Symphony" from `SPEC.md`. Elixir under `elixir/` is "prototype software" and "the current Elixir/OTP implementation". — [README](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/README.md) [elixir README](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/elixir/README.md)

Smallest landing loop is one orchestrator plus one Codex child per issue, not a grader model. `SPEC.md` (2312 lines, "Draft v1"): a poll loop reads a tracker, creates a per-issue workspace, runs a coding agent. Tracker writes are done by the agent, not the orchestrator. A run may stop at `Human Review`. Defaults in the spec: `agent.max_concurrent_agents` 10, `agent.max_turns` 20. `elixir/lib/symphony_elixir/orchestrator.ex` (1990 lines) is that poller: `maybe_dispatch`, Codex token counters, retry. `elixir/WORKFLOW.md` sets `max_concurrent_agents: 10`, `max_turns: 20`, and `codex` command `codex ... app-server` with `approval_policy: never`. The prompt says the agent `commit`s during implementation and must not call `gh pr merge` itself; `Merging` follows a `land` skill. Human Review is a tracker state. — [SPEC.md](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/SPEC.md) [WORKFLOW.md](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/elixir/WORKFLOW.md) [orchestrator.ex](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/elixir/lib/symphony_elixir/orchestrator.ex)

**Gas Town (`gastownhall/gastown`)** — MIT, copyright 2025 Steve Yegge. HEAD `94cc82289d2ead275a62e1db4ef1d4ada4a1f98e` (2026-11-12). Pushed 2026-11-14. Last month is dependency and CVE bumps (Go, git, Dolt 2.6.0), not a redesign. README: Mayor is a Claude Code coordinator; polecats are worker agents with ephemeral sessions; hooks are git worktrees; Witness / Deacon / Dogs are watchdogs; Refinery is a per-rig merge queue that "runs verification gates". Those roles are code, not only a diagram: `internal/cmd/mayor.go`, `polecat.go`, `deacon.go`, `polecat_spawn.go`, plus `gt-model-eval` tests `class-a-witness.yaml`, `class-a-refinery.yaml`. `internal/cmd/polecat_capacity.go` imports `internal/scheduler/capacity` and tracks free slots (admission reservation TTL 30 minutes). README also says a capacity governor "prevents API rate limit exhaustion" and defaults to direct dispatch. The worker that edits code is still one polecat session. Refinery's gate body was not opened. — [README](https://github.com/gastownhall/gastown/blob/94cc82289d2ead275a62e1db4ef1d4ada4a1f98e/README.md) [polecat_capacity.go](https://github.com/gastownhall/gastown/blob/94cc82289d2ead275a62e1db4ef1d4ada4a1f98e/internal/cmd/polecat_capacity.go)

**Beads (`gastownhall/beads`)** — MIT, copyright 2025 Beads Contributors. HEAD `78624109904655d7a4609f27d34eb0982cd8963f` (2026-11-20), migration fix. Pushed 2026-11-23. Last month is Dolt storage, schema migration, and claim/ready bugs. It is not a coding loop. README: `bd ready` → `bd update --claim` → `bd close`, graph in Dolt, hash IDs so agents do not collide. "Compaction: Semantic memory decay summarizes old closed tasks to save context window." README install line still says `go install github.com/steveyegge/beads/cmd/bd@latest` while the GitHub repo is `gastownhall/beads`. — [README](https://github.com/gastownhall/beads/blob/78624109904655d7a4609f27d34eb0982cd8963f/README.md)

**firstmate (`kunchenguid/firstmate`)** — MIT, copyright 2026 Kun Chen. HEAD `427056c4181c41074ad24f051f79919330df0fa5` (2026-11-13). Pushed 2026-11-13. Last month is ship-lane / PR / gate fixes (`park ship lanes while awaiting review`, `no-mistakes gate`). README: "firstmate is not a model, not a harness, not a skill, not an MCP server, and not a CLI… an agent distro." The human talks to one first mate; crewmates run in tmux (or experimental backends) in a git worktree and open PRs. `VISION.md`: "Scripts own the mechanics, agents own the judgment." "The first mate stays free to command by never doing the work itself." So the process that lands the commit is a crewmate inside some other harness (README lists Claude Code, Codex, Pi as inhabitants), not firstmate code. `.no-mistakes.yaml` pins lint to `bin/fm-lint.sh` and disables project agent settings for gate agents. — [README](https://github.com/kunchenguid/firstmate/blob/427056c4181c41074ad24f051f79919330df0fa5/README.md) [VISION.md](https://github.com/kunchenguid/firstmate/blob/427056c4181c41074ad24f051f79919330df0fa5/VISION.md)

**OpenSpec (`Fission-AI/OpenSpec`)** — MIT. HEAD `0c737dc1b543249b38b0f4716816fcf493d894dd` (2026-11-19), "Version Packages (#2284)". Repo `pushed_at` is 2026-11-23; no newer default-branch commit was returned. Last month is skill install, archive/validate fixes, releases. It does not run an agent. README workflow is slash commands the host assistant performs (`/openspec-propose`, `/openspec-apply-change`). "Your AI writes these; you review the plan before any code is written." Recommends "Codex 5.5 and Opus 4.7" and a clean context window before implementation. — [README](https://github.com/Fission-AI/OpenSpec/blob/0c737dc1b543249b38b0f4716816fcf493d894dd/README.md)

**CCPM (`automazeio/ccpm`)** — MIT. HEAD `0bcfabb516913b6d484f20a8c9e449fae8e0c0ee` (2026-11-04). Last month is docs plus one sync/validate fix. "CCPM is now an AGENT SKILL" for Claude Code, Codex, OpenCode, and others. Repo top level is README plus `skill/ccpm`. The loop it describes is the host agent: PRD → epic → GitHub issues → worktree → "parallel agents" that commit `Issue #N: description`. No orchestrator binary was found. — [README](https://github.com/automazeio/ccpm/blob/0bcfabb516913b6d484f20a8c9e449fae8e0c0ee/README.md)

**Gemini CLI (`google-gemini/gemini-cli`)** — Apache-2.0. HEAD `eecccfcd5aff25de5e78135ca20f7abe3f566955` (2026-11-20). Pushed 2026-11-23. Last month is CLI bugfixes and changelogs (v0.69–v0.71). Checkpointing is not the project's commit loop. `docs/cli/checkpointing.md`: before a file-modifying tool, a commit is made in a shadow repo `~/.gemini/history/<project_hash>`, "It does not interfere with your own project's Git repository." `/restore` reverts files and the conversation. Disabled by default. `packages/core/src/utils/checkpointUtils.ts` calls `gitService.createFileSnapshot` and stores `commitHash`. One agent; the user approves tools. — [checkpointing.md](https://github.com/google-gemini/gemini-cli/blob/eecccfcd5aff25de5e78135ca20f7abe3f566955/docs/cli/checkpointing.md)

**opencode (`anomalyco/opencode`)** — MIT. Default branch `dev`. HEAD `2002026a120fc2da9e1b35ab3337a1273c263d70` (2026-11-23), "feat(core): report session cwd and load cwd AGENTS.md". Same-day release commit "release: v2.4.1". Packages include `core`, `cli`, `tui`, `session-ui`. Inner loop file was not opened (code search for `agent loop` in `index.ts` returned 0). A same-day commit changes shell timeout policy: "stop an automation's timed-out shell command instead of backgrounding it" (`e1fb08afc`). — [repo](https://github.com/anomalyco/opencode)

**OpenClaw (`openclaw/openclaw`)** — MIT, copyright 2026 OpenClaw Foundation. Peter Steinberger and the community; README says stewarded by the foundation. Formerly Clawdbot / Moltbot (not re-verified from this repo's history in this pass). HEAD `400004cc99ca08eababd795d78b75592f2cb1294` (2026-11-23). It is a personal-assistant gateway, not a coding harness. README: "Models and agent harnesses (Claude, Codex, local models) are plugins." Pi's README points at OpenClaw as "a real-world integration." Same-day commits do show child agents ("deliver a child's end state as parent history") and "compact at 80% on every route" (`412df9062`). The coding commit, if any, is made by a plugged-in harness. — [README](https://github.com/openclaw/openclaw/blob/400004cc99ca08eababd795d78b75592f2cb1294/README.md)

**jcode (`1jehuang/jcode`)** — MIT, copyright 2025 Jeremy Huang. HEAD `18132de30f4d02d300b2df8c81ef62dbce90f714` (2026-11-23). README: "Run dozens of agents in parallel without melting your machine." Last month is TUI streaming, a hosted Linux release path, and "Remove Jarvis always-on hourly speech-processing budget" (`99ec4c2bc20db352eaf0483a2bb5c991e8c4b6d0`, message is only that subject). The multi-agent scheduler was not opened. — [repo](https://github.com/1jehuang/jcode)

**Invoker (`Neko-Catpital-Labs/Invoker`)** — license file is Functional Source License 1.1 with Apache-2.0 as a future license (API `NOASSERTION`), copyright 2026 Neko Catpital Ventures, LLC. Not a license to copy into bp3. HEAD `dff12e28810bc64dcd00aa2becbb627d5dee97fa` (2026-11-22), a daily patch bump. November history is dominated by "[Daily Release Bump]" plus CI-regression commits. README claims a DAG of tasks in git worktrees with merge gates, desktop, CLI, and Slack. `ARCHITECTURE.md` is a five-layer package map (`execution-engine` at layer 3). `LOOP.md` is an operator prompt for a Mergify requeue battle test ("fix real bugs… so every worker-fixable open PR lands"), not the product loop. Execution-engine source was not opened. 21 stars; treat as a small active repo, not a proven town. — [README](https://github.com/Neko-Catpital-Labs/Invoker)

**worktrunk (`max-sixty/worktrunk`)** — MIT OR Apache-2.0. HEAD `2c82bd6564abac73a016975b1c64e8e9520efbd9` (2026-11-23). README: a git worktree CLI "designed for running AI agents in parallel." It does not call a model. Last month is git-remote fixes, docs, and dependency bumps. — [README](https://github.com/max-sixty/worktrunk)

**tinygrad (`tinygrad/tinygrad`)** — MIT. Not a harness. HEAD `fbb253b67f9ddac0f24a8453606c3f7942ce36bf` (2026-11-23), "nn cleanups". `AGENTS.md` is eight lines: pytest `-n12`, mypy, ruff, no amend commits, do not insert GPU kernel modules. The verification pattern is `sz.py`: `MAX_LINE_COUNT` from the environment, `assert ... total_lines <= max_line_count`. CI step is named "Repo line count <= 26000 lines" and runs `MAX_LINE_COUNT=26500 python sz.py` (`.github/workflows/test.yml`). `szdiff.yml` comments the PR line diff using master's `sz.py` and states "PR code is only line-counted by master's sz.py, never executed." — [sz.py](https://github.com/tinygrad/tinygrad/blob/fbb253b67f9ddac0f24a8453606c3f7942ce36bf/sz.py) [test.yml](https://github.com/tinygrad/tinygrad/blob/fbb253b67f9ddac0f24a8453606c3f7942ce36bf/.github/workflows/test.yml) [AGENTS.md](https://github.com/tinygrad/tinygrad/blob/fbb253b67f9ddac0f24a8453606c3f7942ce36bf/AGENTS.md)

### Inferences

- A commit-landing loop that is actually small is: one agent, a handful of tools, and either the agent commits (Aider, Ralph's prompt, Symphony's Codex child, a Gas Town polecat) or the user commits (Pi, Gemini CLI).
- Outer loops that survived in code are boring: bash iteration cap (Ralph), tracker poll plus per-issue workspace (Symphony), worktree plus a capacity count (Gas Town, firstmate, worktrunk). The judge of "is the code right" is still the agent's tests or a human, except where a script gate is explicit (firstmate `.no-mistakes.yaml`, tinygrad line cap, Symphony's Human Review state).
- bp3 can read Pi, Ralph, Aider, Symphony, Gas Town, Beads, firstmate, OpenSpec, CCPM, Gemini CLI, opencode, OpenClaw, jcode, and worktrunk for ideas (MIT or Apache-2.0). Do not copy Invoker (FSL). Aider and Ralph have been commit-quiet for months; quiet is part of the evidence.

### Gaps

- opencode's and jcode's in-process tool loops were not opened, so "one process plus tools" for those two is from package layout and README, not from a loop function.
- Gas Town Refinery's verification gate was not read, so it is unknown whether that gate is tests, a second model, or both.
- `mbernet/ralph-wiggums` and Huntley's workshop `chat.go` were not read.
- Amp has no public repo here.

## Where did a project delete orchestration after it got too expensive?

### Takeaway

No surveyed repo showed a commit that removed a multi-agent layer because it cost too much. What showed up instead: Pi never put sub-agents in core, Gas Town still has the town and an open cost-tracking issue, firstmate still runs a crew and has an open token-burn bug, jcode deleted an always-on speech budget, OpenClaw compacts at 80 percent.

### Cited Findings

- Pi README, same HEAD as above: core "skips features like sub-agents and plan mode." A commit search for "remove subagent" did not return a deletion of an orchestrator (hits were unrelated p2/durable commits). Open issue [#12293](https://github.com/earendil-works/pi/issues/12293): "Anthropic server-tool usage doubles the context reading; the clamp then sends max_tokens 1 in a loop." That is a token bug, not a removed architecture. — [README](https://github.com/earendil-works/pi/blob/8c47efc7b4f07210b89a1c0207f98be05abfc82d/README.md)
- Gas Town issue [#24](https://github.com/gastownhall/gastown/issues/24) (open): "Add cost tracking across Gas Town agents." Body says each Claude Code instance shows a cost and nothing aggregates it. Issue [#1143](https://github.com/gastownhall/gastown/issues/1143) (open) proposes a long-term dataset of time and tokens so the town can refuse thrash. It is a feature request, not a shipped cut. The code that does exist limits admission (`polecat_capacity.go`), it does not delete Witness/Refinery/Mayor. — [issue 24](https://github.com/gastownhall/gastown/issues/24)
- firstmate issue [#8553](https://github.com/kunchenguid/firstmate/issues/8553) (open, 2026): a Stop hook requeued the same wake for "more than 500 identical turns" when `/tmp` was full, because `bin/fm-wake-drain.sh` could not run. Issue [#8483](https://github.com/kunchenguid/firstmate/issues/8483) (open) is a user report that three or more workers make the first mate slow on Pi plus a GPT model, and not on Claude. `VISION.md` says depth is capped because every layer "costs fidelity and tokens," and the always-loaded contract has "a stated ceiling of 9,000 words." That is a written cap, not a deleted crew. — [VISION.md](https://github.com/kunchenguid/firstmate/blob/427056c4181c41074ad24f051f79919330df0fa5/VISION.md)
- jcode commit `99ec4c2bc20db352eaf0483a2bb5c991e8c4b6d0` (2026-11-23) subject: "Remove Jarvis always-on hourly speech-processing budget." Another same-day subject doubles "token plan inference credits from 2x to 4x." Speech budget is not the coding orchestrator. — [commit](https://github.com/1jehuang/jcode/commit/99ec4c2bc20db352eaf0483a2bb5c991e8c4b6d0)
- OpenClaw commit subject on 2026-11-23: "fix: compact at 80% on every route" (`412df9062`). Child-agent commits the same day still add parent/child delivery. Compaction, not removal. — [repo commits](https://github.com/openclaw/openclaw/commit/412df9062)
- Symphony's last commit is 2026-09-15. The orchestrator is still the whole Elixir tree. No "remove multi-agent" commit was looked for beyond the empty since-2026-10-23 history. The spec's own non-goal is "Mandating strong sandbox controls beyond what the coding agent and host OS provide." — [SPEC.md section 2.2](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/SPEC.md)
- Aider simply stopped committing after 2026-05-22. That is abandonment of the repo's pace, not a recorded deletion of agents. Ralph's runner stopped at 2026-02-02 with the 10-iteration bash loop still the whole system.

### Inferences

- Expense shows up as bugs and unfixed proposals (token clamp loops, rewake loops, missing cost rollup), not as a revert to a single agent in these trees.
- The deliberate cheap design is Pi's: judgment and extra roles live in extensions the user writes, so the shipped core never paid for a town.

### Gaps

- Commit-message search was narrow (a few queries on Pi, Gas Town, firstmate, jcode). A deletion under another wording could exist.
- Gas Town issue #24 and #1143 were not checked for linked PRs that might have landed partial cost tracking. PR #4981 ("price Claude usage from the llm-prices table") was open at search time and its diff was not read.

## How does review happen?

### Takeaway

Review is mostly the human's diff, or the same agent running the project's tests. A second model is explicit in Aider only for the commit message (`--weak-model`). Symphony and firstmate name a human or a script gate before land. Nobody surveyed publishes a separate grader model as the thing that allows the commit.

### Cited Findings

- Aider: human uses `/undo`, `/diff`, and git history. The weak model writes the commit message, not a ship/no-ship verdict. Pre-commit hooks are off unless `--git-commit-verify`. — [git.md](https://github.com/Aider-AI/aider/blob/5dc9490bb35f9729ef2c95d00a19ccd30c26339c/aider/website/docs/git.md)
- Ralph `prompt.md`: "ALL commits must pass your project's quality checks… Do NOT commit broken code." Frontend stories also want browser checks. The next iteration is not a different reviewer; it is a fresh copy of the same agent. The shell never inspects the diff. — [prompt.md](https://github.com/snarktank/ralph/blob/6c53cb0b831ebe8739c6a003e22af14902d8b0b5/prompt.md)
- Pi `how-pi-works.md`: "Enabled tools use the operating-system permissions of the Pi process." No review stage. `AGENTS.md` tells contributors that `npm run check` is lint/format/types and "Does not run tests," and "Never run `npm test` unless requested." That is the project's own contributor rule, not a product grader. — [AGENTS.md](https://github.com/earendil-works/pi/blob/8c47efc7b4f07210b89a1c0207f98be05abfc82d/AGENTS.md)
- Symphony `elixir/WORKFLOW.md`: states include `Human Review` and `Rework`. Before Human Review the agent must read PR comments and treat "every actionable reviewer comment (human or bot)" as blocking. Land is a skill, not `gh pr merge`. The orchestrator records tokens; it does not grade the patch. — [WORKFLOW.md](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/elixir/WORKFLOW.md)
- Gas Town README: Refinery "runs verification gates" and isolates failed merge requests. Witness restarts stuck polecats. That is lifecycle and merge machinery. Whether a model reads the diff was not verified in code. — [README](https://github.com/gastownhall/gastown/blob/94cc82289d2ead275a62e1db4ef1d4ada4a1f98e/README.md)
- firstmate `VISION.md`: "Workers are supervised, not trusted: independent validation, behavioral tests, and the configured merge authority." "Evidence is never authorization." "Merging… require the captain's explicit word" unless a project grant says otherwise. `.no-mistakes.yaml` is a deterministic lint command for gate agents. — [VISION.md](https://github.com/kunchenguid/firstmate/blob/427056c4181c41074ad24f051f79919330df0fa5/VISION.md)
- OpenSpec README: the human reviews the plan "before any code is written." No second-model grade in the README section read.
- Gemini CLI: the human approves the tool, then can `/restore`. The shadow commit is a snapshot, not a review.
- tinygrad: review is CI. Line cap is an assert, not a model. `AGENTS.md` tells agents to run pytest, mypy, and ruff. — [test.yml](https://github.com/tinygrad/tinygrad/blob/fbb253b67f9ddac0f24a8453606c3f7942ce36bf/.github/workflows/test.yml)
- CCPM README: "Every line of code must trace back to a specification" and GitHub issues are the tracker. No grader model is described. The "parallel agents" share one worktree.

### Inferences

- If bp3 wants a pattern these repos actually implemented, it is: tests or a script gate, then a human merge. A second model appears as a cheap commit-message writer (Aider) or as "reviewer comments" the worker must answer (Symphony), not as an independent ship verdict in the orchestrator.
- Ralph will keep spending iterations after a bad commit unless the prompt's self-check holds. The shell cannot tell.

### Gaps

- firstmate's gate scripts beyond `.no-mistakes.yaml` and `bin/fm-lint.sh` were not read, so "independent validation" might be another agent or only shell tests.
- Refinery and Invoker merge gates were not read.

## Which ideas are in code, and which are only a README?

### Takeaway

Pi's loop, Ralph's bash cap, Aider's auto-commit, Symphony's Elixir poller, Gas Town's role commands, Beads' CLI, Gemini's shadow snapshot, and tinygrad's line assert are in code. OpenSpec and CCPM are instructions for someone else's agent. firstmate is mostly scripts plus policy prose. Invoker's DAG is claimed and only the package map and a battle-test prompt were opened. Huntley's Ralph repo is a playbook.

### Cited Findings

In code (file seen):

- Pi agent loop and tool list: `packages/agent/src/agent-loop.ts`, `packages/coding-agent/src/core/tools/index.ts`. Compaction is documented in `packages/coding-agent/docs/compaction.md` (file exists; body not quoted). `packages/evals` exists (README, docker, src, test); no score file was opened.
- Ralph: `ralph.sh` plus `prompt.md` / `CLAUDE.md`. Completion is a string the model must print.
- Aider: `aider/coders/base_coder.py` `auto_commit` (search hit) and `aider/website/docs/git.md`.
- Symphony: `elixir/lib/symphony_elixir/orchestrator.ex`, `agent_runner.ex`, tracker `agent_tool.ex` files, `elixir/WORKFLOW.md`. `SPEC.md` is a spec an agent is invited to reimplement. Smoke files `docs/symphony-smoke-test-one.md` (113 bytes) and `docs/symphony-smoke-board-review.md` (122 bytes) are stubs, not a design.
- Gas Town: `internal/cmd/mayor.go`, `polecat.go`, `deacon.go`, `polecat_capacity.go`. Molecules and convoys are described in the README; their TOML was not opened (`docs/contrib-harnesses/polecat-pr-flow/mol-polecat-work.toml` exists).
- Beads: README commands match a shipped CLI (`bd`). `BENCHMARKS.md` names Go tests under `internal/storage/dolt`.
- Gemini: `checkpointUtils.ts` matches the doc.
- tinygrad: `sz.py` assert and the workflow step.
- firstmate: `.no-mistakes.yaml` and the scripts it names. `VISION.md` is policy. The crew is other people's agents following the distro.
- jcode: the Jarvis budget removal is a commit on `master`. The "dozens of agents" sentence is README.
- OpenClaw: child-agent and compact-at-80% commits are code changes. "Harnesses are plugins" is the README.

README or manifesto, not an engine in that repo:

- `ghuntley/how-to-ralph-wiggum` playbook (planning vs building prompts). The one-liner `while` loop is described in Huntley's profile and in `snwfdhmp/awesome-ralph`, which was not opened beyond search snippets.
- OpenSpec's propose → apply → archive story.
- CCPM's five-phase "No Vibe Coding" and the 5-agents-in-one-worktree picture. Implementation surface found: `skill/ccpm` only.
- Symphony README option 1: "Implement Symphony according to the spec" is an invitation, while option 2 is the Elixir tree that does exist.
- Invoker `LOOP.md` is a prompt with a machine path (`/Users/edbertchan/.cursor/worktrees/...`) and production PR numbers (#5803, #5812) as failure examples. That is a dogfood note mixed into the repo, not a measured benchmark. The worker it names (`packages/execution-engine/src/workers/pr-maintenance-workers.ts`) was not opened, so the claim that this worker merges PRs is unverified here.
- worktrunk: the agent is whoever you start in the worktree.

### Inferences

- A manifesto that matches code is usable (Pi how-it-works, Symphony spec plus orchestrator, Gemini checkpoint doc plus `checkpointUtils.ts`). A manifesto that only installs a skill (OpenSpec, CCPM) teaches the prompt, not the state machine.
- firstmate is the clearest written split of judgment vs code, and it is enforced by a yaml the gate is told to run, not by a model policy file alone.

### Gaps

- Pi `packages/evals` contents and Gas Town molecule TOML were not read, so some "in code" workflow steps may still be prompt text.
- Invoker execution engine not read. Daily version-bump commits make activity look higher than feature work.

## Is there a published benchmark or a dogfood log?

### Takeaway

Almost none of these repos contain a week of PRs with a cost table. The numbers that do exist are either storage microbenchmarks (Beads), a line-count CI gate (tinygrad), a four-scenario skill checklist in a README (CCPM), or an open wish for cost tracking (Gas Town). Token fields exist in Symphony's orchestrator and are not a published report.

### Cited Findings

- Symphony `orchestrator.ex` keeps `codex_input_tokens`, `codex_output_tokens`, `codex_total_tokens` and folds them into `codex_totals` from agent events (`extract_token_delta`). `SPEC.md` section 13.5 tells implementations to accumulate those counts and ignore delta-style `last_token_usage` for totals. No checked-in week of spend was found. Elixir README says sessions that need approval show up as blocked in an in-memory map that restart clears. Smoke markdown files are about 100 bytes each. — [orchestrator.ex](https://github.com/openai/symphony/blob/be10a1b79df723d6d7612b5651c8522704dafb2e/elixir/lib/symphony_elixir/orchestrator.ex)
- Beads `BENCHMARKS.md` is `go test -bench` for ready-work, search, and compaction on 10K/20K issue fixtures. It says May 2026 Dolt hot-path changes should be compared with those benches. No token or cycle-time table for an agent. — [BENCHMARKS.md](https://github.com/gastownhall/beads/blob/78624109904655d7a4609f27d34eb0982cd8963f/BENCHMARKS.md)
- tinygrad CI: `MAX_LINE_COUNT=26500 python sz.py` under a step titled "Repo line count <= 26000 lines". The two numbers disagree; both are in `.github/workflows/test.yml` around the lines read (step name at line 240, command at line 241). `szdiff.yml` posts a line diff comment and does not run the PR's code. — [test.yml](https://github.com/tinygrad/tinygrad/blob/fbb253b67f9ddac0f24a8453606c3f7942ce36bf/.github/workflows/test.yml)
- CCPM README "Proven Results": "89% less time lost to context switching", "5–8 parallel tasks", "75% reduction in bug rates", "Up to 3× faster", attributed to "Teams using this system" with no link. A second table says an internal eval scored CCPM 4/4, 4/4, 3/3 versus baseline 2/4, 0/4, 1/3 ("100%" vs "27.7%"). The eval harness was not in the file listing that was fetched (`skill/ccpm` only at that level). Treat the table as a README claim. — [README](https://github.com/automazeio/ccpm/blob/0bcfabb516913b6d484f20a8c9e449fae8e0c0ee/README.md)
- Gas Town #24 and #1143 ask for the cost log and do not contain one. — [issue 24](https://github.com/gastownhall/gastown/issues/24)
- firstmate #8553 is a dogfood failure (500-plus identical turns) without a token total. #8483 is a qualitative speed complaint. — [issue 8553](https://github.com/kunchenguid/firstmate/issues/8553)
- Invoker `LOOP.md` names two PRs that hit a repair cap and stayed open (#5803, #5812). That is an anecdote inside a prompt, not a results table. — [LOOP.md](https://github.com/Neko-Catpital-Labs/Invoker/blob/dff12e28810bc64dcd00aa2becbb627d5dee97fa/LOOP.md)
- jcode's "Double token plan inference credits" commit is product billing, not a measured run.
- Pi, Aider, Ralph, OpenSpec, opencode, OpenClaw, worktrunk: no cost table or week-of-PRs log was found in the files opened. Pi has a `packages/evals` directory and `packages/telemetry` ("vendor-neutral telemetry contracts") in the README package table. No result dump was read.
- Ralph README points at an X article by Ryan Carson for "how I use Ralph". That post was not fetched. The repo itself has no cost log.

### Inferences

- Cycle time and dollars are operational problems these maintainers talk about (issues, compaction, iteration caps, line caps) and rarely check in as data.
- The only hard, automatic "this cannot grow" gate seen in-repo is tinygrad's line assert. It measures the codebase, not the agent.

### Gaps

- Pi `packages/evals` and `packages/telemetry` were not opened, so a benchmark may exist there.
- Symphony dashboard/JSON status (`SPEC` section 13.7) may print tokens at runtime; no sample output is in git from this pass.
- opencode and jcode may log cost in the product; it was not in the files read.
- Third-party writeups (Harness Hub, huntley.com, Carson's article) were not used as proof of mechanism.
