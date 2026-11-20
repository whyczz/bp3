# CONTEXT.md: how others build agent harnesses

Common-sense ground for `/quest`, red-ink and graders. For each
question: what other builders do, one sourced and dated claim per
line, and where bp3 differs (`bp3:`), only where it does. Distilled
from [the dossier](docs/dossiers/agent-harness-landscape.md), which
keeps every source and the saved searches (its Re-run section).

**Refresh rule** (owner, 2026-11-19): before a quest or red chair
cites a claim checked more than 90 days ago, re-run its saved search
and update the line. There is no calendar job.

**What gets in:** a claim seen in two places, or stated first-party
by the team that does it. Numbers are the source's own and are not
audited. Anything thinner stays in the dossier.

## Q1 Orchestration

- Teams that coordinate agents use one coordinator over workers in their own contexts, not a swarm of peers ([Gas Town](https://github.com/gastownhall/gastown), [Claude Code sub-agents](https://code.claude.com/docs/en/sub-agents), [Cognition](https://cognition.com/blog/devin-can-now-manage-devins), checked 2026-11-19). bp3: the induct conductor over one child per step.
- Subagents earn their keep as context firewalls for search, test or review; role-play subagents failed ([HumanLayer](https://humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents), [Replit](https://frontier.replit.com/automated-self-testing/), checked 2026-11-19).
- A loop that restarts with fresh context and does one item per pass is the common alternative to a coordinator ([Ralph](https://ghuntley.com/ralph/), [Ronacher](https://lucumr.pocoo.org/2026/6/23/the-coming-loop/), checked 2026-11-19).
- Several writers on one feature is widely called an anti-pattern, because they make conflicting decisions ([Cognition](https://cognition.com/blog/dont-build-multi-agents), [pi](https://www.mariozechner.at/posts/2025-11-30-pi-coding-agent/), [Anthropic multi-agent](https://www.anthropic.com/engineering/multi-agent-research-system), checked 2026-11-19). bp3: one writer per node; parallel only across independent nodes.
- Exact work lives in deterministic scripts and judgment in the agent, and "the two never mix" ([firstmate VISION.md](https://github.com/kunchenguid/firstmate), checked 2026-11-19).

## Q2 Storage

- The default store is markdown plans in git; 411 HN setup replies mention SQLite zero times ([HN setup thread](https://news.ycombinator.com/item?id=50366117), [Reed](https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/), [pi](https://www.mariozechner.at/posts/2025-11-30-pi-coding-agent/), checked 2026-11-19).
- Git commits double as checkpoints: aider commits every edit, Gemini CLI keeps a shadow repo ([aider](https://aider.chat/docs/git.html), [Gemini CLI](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/checkpointing.md), checked 2026-11-19).
- Some keep state in the tracker instead: Symphony runs "without requiring a persistent database", CCPM uses GitHub Issues ([Symphony SPEC](https://github.com/openai/symphony/blob/main/SPEC.md), [CCPM](https://github.com/automazeio/ccpm), checked 2026-11-19).
- Databases show up with concurrent writers: Beads moved off JSONL to Dolt, Invoker runs SQLite behind one writer process ([Beads](https://github.com/gastownhall/beads), [Invoker](https://github.com/Neko-Catpital-Labs/Invoker), checked 2026-11-19). bp3: an append-only `ledger.jsonl` in the repo, written only by `bp3 q`; no other system found does this.
- Daemons that sync state draw complaints: Beads' daemon was "syncing the wrong things" ([HN on ticket](https://news.ycombinator.com/item?id=46487580), [Beads](https://github.com/gastownhall/beads), checked 2026-11-19). bp3: no daemon.
- Agents are "less likely to inappropriately change or overwrite JSON files compared to Markdown files" ([Anthropic long-running harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), checked 2026-11-19). bp3: state is generated YAML and JSONL; markdown is authored.

## Q3 Scaling

- A git worktree per agent or task is the mainstream isolation ([Claude Code sub-agents](https://code.claude.com/docs/en/sub-agents), [worktrunk](https://github.com/max-sixty/worktrunk), [Gas Town](https://github.com/gastownhall/gastown), checked 2026-11-19). bp3: desks.
- Containers or VMs per task come with cloud or untrusted work, and Cognition finds containers not enough ([Cognition](https://old.cognition.ai/blog/what-we-learned-building-cloud-agents), [container-use](https://github.com/dagger/container-use), checked 2026-11-19).
- Human attention is the cap, not compute: people top out at about 3-6 sessions, limited by "how fast I can review the results" ([HN setup thread](https://news.ycombinator.com/item?id=50366117), [Willison](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/), checked 2026-11-19).
- Verification sets how many agents can run: "Without them, you can really only run one or two Claudes at a time"; "You can't simply add Codex sessions and expect linear speedups" ([Claude Code team](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification), [OpenAI Sora](https://openai.com/index/shipping-sora-for-android-with-codex/), checked 2026-11-19).
- Merging is its own gated step: Gas Town's Refinery bisects a merge queue, Symphony moves Human Review to Merging to Done ([Gas Town](https://github.com/gastownhall/gastown), [Symphony SPEC](https://github.com/openai/symphony/blob/main/SPEC.md), checked 2026-11-19). bp3: only the owner promotes.

## Q4 Human-LLM interaction

- Intent goes in as a spec or plan file approved before code ([OpenSpec](https://github.com/Fission-AI/OpenSpec), [CCPM](https://github.com/automazeio/ccpm), [Jules](https://jules.google/docs), [Beck](https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes), checked 2026-11-19). bp3: `/quest` files plus red-ink, heavier than most.
- A plan must be enough to restart from: OpenAI's ExecPlans carry Progress, a Decision Log and a Retrospective ([ExecPlans](https://github.com/openai/openai-cookbook/blob/main/articles/codex_exec_plans.md), [OpenAI harness engineering](https://openai.com/index/harness-engineering/), checked 2026-11-19).
- The owner's words are kept verbatim, apart from the agent's spec, as acceptance ([firstmate](https://github.com/kunchenguid/firstmate), checked 2026-11-19). bp3: owner quotes live in QUEST.md decision tables.
- Humans judge choices and hard-to-undo calls: automated review "can't fill a slot that calls for a human", and people decide "which of several valid options should we choose" ([Anthropic code review](https://claude.dev/blog/solving-code-review-at-anthropic), [OpenAI skills and the Agents SDK](https://developers.openai.com/blog/skills-agents-sdk), checked 2026-11-19).
- Rich input beats typed prose: screenshots in half of prompts plus dictation, or annotated HTML pages polled back to the agent ([Steinberger](https://steipete.me/posts/just-talk-to-it), [Lavish](https://github.com/kunchenguid/lavish-axi), checked 2026-11-19).
- Agent apps give the human a diff-review UI rather than an LLM checking an LLM; Warp says so outright, and Vibe Kanban, Orca, Conductor and claude-squad do the same ([Warp](https://www.warp.dev/blog/agents-3-full-terminal-use-plan-code-review-integration), [dossier Q4](docs/dossiers/agent-harness-landscape.md#q4-human-llm-interaction-how-intent-is-handed-over), checked 2026-11-19). bp3: a per-commit LLM grader, which is rare.

## Q5 Learning and org scale

- Every mistake becomes a permanent fix: an instruction line, a lint rule or a test ([Hashimoto](https://mitchellh.com/writing/my-ai-adoption-journey), [Factory](https://factory.com/articles/what-is-a-software-factory-architecture), checked 2026-11-19). bp3: `runs/*/notes.md`, with no path from a note to a rule yet.
- Rules need pruning too, and "Any incidents are now an eval" ([Claude Code team](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification), [Anthropic code review](https://claude.dev/blog/solving-code-review-at-anthropic), checked 2026-11-19).
- The repo is the memory and stays short: AGENTS.md as a ~100-line table of contents pointing at versioned plans ([OpenAI harness engineering](https://openai.com/index/harness-engineering/), [agents.md](https://agents.md/), checked 2026-11-19).
- Always-loaded context beats triggered skills: a skill went uninvoked in 56% of Vercel's eval cases ([HN on Vercel](https://news.ycombinator.com/item?id=46809708), checked 2026-11-19). bp3: rules that matter belong in CLAUDE.md and AGENTS.md, not only in skills.
- Memory is re-checked when read: Copilot's memory cites code and re-verifies it against the current tree ([GitHub](https://github.blog/ai-and-ml/github-copilot/building-an-agentic-memory-system-for-github-copilot/), checked 2026-11-19).
- At org scale, skills live in one marketplace repo with an owner per plugin and lint CI: "autonomy for updates, governance for additions" ([AutoScout24](https://tech.autoscout24.com/blog/posts/designing-a-coding-agent-skills-marketplace/), checked 2026-11-19).

## Q6 Engineering canon, filtered

Every pre-LLM rule paid for a human limit. **Transfers**: the limit
still binds agents or the owner. **Inverts**: the limit is gone.
**Amplifies**: agents make it worse.

- Brooks's law, transfers: each session is a new hire and handoffs drop context ([MMM](https://www.informit.com/store/mythical-man-month-essays-on-software-engineering-anniversary-9780201835953), [Cognition](https://cognition.com/blog/dont-build-multi-agents), checked 2026-11-19). Harness: one writer per node.
- Conceptual integrity, amplifies: N sessions are N minds ([The Mythical Agent-Month](https://www.oreilly.com/radar/the-mythical-agent-month/), checked 2026-11-19). Harness: the owner is the architect.
- Plan to throw one away, inverts: spikes cost almost nothing, keeping them costs a lot ([Fowler site, Vaccari](https://www.martinfowler.com/articles/exploring-gen-ai/partner-with-ai-and-throw-away-the-code.html), checked 2026-11-19). Harness: spike nodes that never land.
- No Silver Bullet, transfers: models eat accidental complexity; spec and verification remain ([TR86-020](https://www.cs.unc.edu/techreports/86-020.pdf), [METR RCT](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/), checked 2026-11-19).
- TDD, transfers: the test is the agent's oracle ([Canon TDD](https://tidyfirst.substack.com/p/canon-tdd), [Claude Code best practices](https://code.claude.com/docs/en/best-practices), checked 2026-11-19). Harness: the test lands before the code.
- Small steps, transfers: agents leap ahead ([Beck](https://newsletter.kentbeck.com/p/genie-wants-to-leap), checked 2026-11-19). Harness: one node, one green commit.
- YAGNI, amplifies: building is free, carrying it is not ([Fowler](https://martinfowler.com/bliki/Yagni.html), [Beck](https://newsletter.kentbeck.com/p/augmented-coding-beyond-the-vibes), checked 2026-11-19). Harness: unrequested scope is a finding.
- Information hiding, transfers: the context window is working memory ([Parnas](https://dl.acm.org/doi/10.1145/361598.361623), [Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), checked 2026-11-19). Harness: each interface fits in one prompt.
- Gall's law, amplifies: no budget forces a small v1 anymore ([Arango](https://www.jarango.com/2026/06/26/still-holds-galls-law/), checked 2026-11-19). Harness: move to a heavier engine only after the simple one works.
- Goodhart's law, amplifies: agents optimize the check literally ([METR reward hacking](https://metr.org/blog/2025-06-05-recent-reward-hacking/), [ImpossibleBench](https://arxiv.org/abs/2510.20270), checked 2026-11-19). Harness: authors can't edit the tests that judge them.
- Chesterton's fence, amplifies: no memory, and deleting is free ([agent-skills](https://github.com/addyosmani/agent-skills), checked 2026-11-19). Harness: every deletion says why the fence was there.
- Conway's and Hyrum's laws, transfer and amplify: the harness topology becomes the code topology, and agents read every output field ([dossier Q6](docs/dossiers/agent-harness-landscape.md#q6-the-pre-llm-engineering-canon-filtered), reasoning only, checked 2026-11-19). Harness: one owner per shared tool; version the `bp3 q r` JSON.
- Small batches and trunk-based work, transfer: owner attention is the scarcest resource ([Google small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html), [DORA](https://dora.dev/capabilities/working-in-small-batches/), checked 2026-11-19). bp3 tension: quests land as large merges.
- Style guides, transfer as tooling: prose rules are only advice to a model ([Google style guides](https://google.github.io/styleguide/), [Claude Code best practices](https://code.claude.com/docs/en/best-practices), checked 2026-11-19). Harness: formatters and lint in `make check`.
- DRY, amplifies: agents clone code without knowing it, "4x more code cloning" ([GitClear](https://www.gitclear.com/ai_assistant_code_quality_2025_research), checked 2026-11-19, vendor). Harness: DRY the knowledge (plans, schemas), not every line.
- Code review's main value was shared understanding, which inverts: a stateless grader learns nothing ([Bacchelli & Bird](https://2013.icse-conferences.org/content/expectations-outcomes-and-challenges-modern-code-review.html), [Claude Code best practices](https://code.claude.com/docs/en/best-practices), checked 2026-11-19). Harness: the grader checks defects and spec; notes carry the knowledge.

## Review loops

- Models self-correct poorly without outside feedback ([Huang et al.](https://arxiv.org/abs/2310.01798), checked 2026-11-19).
- Judges favor their own outputs, so the worker and the judge are separate ([Panickssery et al.](https://arxiv.org/abs/2404.13076), [Anthropic harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps), checked 2026-11-19). bp3: a fresh grader per commit.
- A verifier that can run code catches most known high-severity bugs for a fraction of the tokens, and the same base model is fine ([OpenAI scaling code verification](https://alignment.openai.com/scaling-code-verification/), checked 2026-11-19).
- A reviewer asked to find problems "will always find something"; report only gaps that affect correctness ([Claude Code best practices](https://code.claude.com/docs/en/best-practices), [Google review standard](https://google.github.io/eng-practices/review/reviewer/standard.html), checked 2026-11-19).
- Deterministic checks beat model judgment: "Test don't review" ([HN](https://news.ycombinator.com/item?id=50529612), [HN](https://news.ycombinator.com/item?id=50538303), checked 2026-11-19).
- Agents delete or edit failing tests to go green, so tests get locked ([ImpossibleBench](https://arxiv.org/abs/2510.20270), [Anthropic long-running harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), checked 2026-11-19).
- "An approval covers one specific commit", and after three rounds the reviewer asks the author to reconsider the approach ([Anthropic code review](https://claude.dev/blog/solving-code-review-at-anthropic), checked 2026-11-19). bp3: same shape (`E_COMMIT_MISMATCH`, `max_cycles: 3`), but every round is a full re-grade.
- Later rounds review only the new diff and never repeat a finding; one PR without that ran "more than fifty rounds of review and fixes overnight" ([Anthropic code review](https://claude.dev/blog/solving-code-review-at-anthropic), checked 2026-11-19). bp3: not yet (fast-grader quest, on hold).
- "If a change can modify the check that judges it, the check is broken" ([Claude Code team](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification), checked 2026-11-19). bp3: not enforced.
- Evidence, not "done": every commit is stamped with how it was verified, even "none", and proof is attached to the PR before review ([Claude Code team](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification), [Lopopolo](https://hyperbo.la/w/production-function-changed/), checked 2026-11-19).
- Rework is "a full approach reset, not incremental patching" ([Symphony WORKFLOW.md](https://github.com/openai/symphony/blob/main/elixir/WORKFLOW.md), checked 2026-11-19).
- Flaky tests "train the agent to run them again rather than fixing the failing code" ([Claude Code team](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification), checked 2026-11-19).

## bp3 lessons

Our own, newest last. Each row names the record that holds it.

| Date | Lesson | Record |
|---|---|---|
| 2026-11-18 | `make check` took 170.40s because every test launched bp3 against a temp git repo; there was no unit layer. Measure before you plan. | `docs/quests/2026-11-18-test-pyramid/QUEST.md` (Context) |
| 2026-11-18 | A check that cannot fail certifies nothing: vacuous assertions passed with a dead pid. | `docs/quests/2026-11-18-test-pyramid/QUEST.md` (red-chair findings) |
| 2026-11-19 | tier.1's runner was bash 3.2 plus perl one-liners that nobody signed off on. It took six grading rounds on signal edge cases and was rewritten in OCaml (d6a711f) after "why can't we use ocaml for this?". Write the stack down and lint it. | `docs/quests/2026-11-19-constraints-context/ICEBOX.md` |
| 2026-11-19 | A census by file extension misses languages hiding in heredocs and `-e` strings: python and perl did not show up. | `docs/quests/2026-11-19-constraints-context/ICEBOX.md` |
| 2026-11-19 | Grades were the slow loop, not gates: 25 grades, median about 11 min at 78k-198k tokens each, 16 of them re-grades, while `make check` ran in seconds. | `docs/quests/2026-11-19-fast-grader/QUEST.md` (Context) |
| 2026-11-19 | Check the field before calling bp3 unique: "nobody binds a verdict to a commit or caps rounds" was wrong, because Anthropic does both. | `docs/dossiers/agent-harness-landscape.md` (Review loops) |
