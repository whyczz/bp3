# Why a quest still costs half a day after the November harness dossier

Question this serves: of the advice in
[agent-harness-landscape.md](agent-harness-landscape.md) (snapshot
2026-11-19, LessWrong and geohot pass 2026-11-20), which part never
reached the running brief, which part did, and which part does not
survive the evidence gathered on 2026-11-23?

Reader: the owner, before another harness quest. The active quest
[2026-11-23-fast-agy-induct](../quests/2026-11-23-fast-agy-induct/QUEST.md)
lists the same day's learn report as input still to fold in before
approval. This dossier is that class of input. It does not approve
that quest, does not thaw anything, and does not replace the November
file.

"Half a day" is the owner's pain on 2026-11-23, stated in the request
for [get-good-harness-engineering.md](../learn/get-good-harness-engineering.md).
No file read for this dossier contains "half a day" as a measured
quest wall.

## Map

### The fork, held open

Four readings fit the files. None is closed.

| | Reading | What would close it |
|---|---|---|
| A | The cheap half of the November advice never shipped, so the advice has not been tried | One measured quest that runs that half and still costs the same |
| B | The expensive half did ship (fresh grader, full re-judge, `make check-full`, one writer), and the pain is still the owner's | A wall split that shows the shipped half is where the time goes |
| C | The advice aimed at the wrong peer: a lab review loop, copied onto a solo quest | Keepers with a log who do not run this grader, plus a bp3 catch-rate that says the grader was buying something else |
| D | The one backpack number with a wall effect for later rounds (the icebox's 7–15 minutes) was never put in the brief, so "the advice is bad" is early | That number, replicated or refuted, on a later quest |

A, B, and D can all be true together. C is the reading that says
another round of the same advice will not help.

### Three patches wear one name

"Apply the November advice" is not one diff. Three designs exist on
disk, and the running brief is a fourth.

1. **November dossier, 2026-11-19.** bp3's grader "matches Anthropic's
   own practice." The gap it names is convergence: later rounds review
   only the delta since the last graded SHA, carry the prior findings,
   never repeat them, sort Important / Nit / Pre-existing so a nit
   cannot force `needs_fix`; at the cap, escalation asks the owner to
   reconsider the approach; a node's diff may not touch its own
   checks; handoff is stamped with how it was verified; new refusals
   start in observe mode. Labeled "Input for the fast-grader thaw,"
   not a decision
   ([agent-harness-landscape.md](agent-harness-landscape.md) lines
   387–396). The same file's options table already contains the exit:
   review option (b), deterministic gates plus human diff review,
   wins "if the grader's catches are mostly what scripts catch; that
   was half of test-pyramid's findings" (line 529). Open question 1
   then says the question is how the grader converges, not whether to
   have one (lines 535–549).
2. **Icebox sketch, frozen 2026-11-19.** Author plants the bug before
   handoff. Round 1 is a full brief with a cap. Round 2+ is prior
   findings plus the diff plus `make check-full`, "nothing else," and
   "cut later rounds to 7–15 minutes." The copy that survives is
   [ICEBOX.md](../quests/2026-11-19-fast-grader/ICEBOX.md) lines 17–27
   and 36–50. `docs/icebox/2026-11-19-fast-grader.md` was absent when
   this dossier was written. The copy's frontmatter still says
   `status: frozen` and `promoted: null`.
3. **Active quest, 2026-11-23.** `scripts/red-first` and
   `scripts/receipt` replace hand-planted mutants. Cycle 2+ is a delta
   over `git diff <prev7>..<sha7>` and the acceptance gates that diff
   touches. It does not quote the author-typed `--reason`. A nit
   ships as a follow-up. The grader stays read-only. The same quest
   also adds the `agy` harness, `/swarm` parallel authors, and an
   `agy` metrics reader
   ([QUEST.md](../quests/2026-11-23-fast-agy-induct/QUEST.md) lines
   10–37, 45–46, 188–201). Frontmatter `status: active`. Its own open
   question 1 says the learn report is folded in before owner
   approval (line 212). `ls scripts/red-first scripts/receipt` on
   2026-11-23: both paths absent. The quest's acceptance block records
   the same `ls` failure as "observed today" (lines 76–80).

The running brief is none of the three. Cycle 2+ says "Re-judge the
gates in full" and shows `git diff <prev>..<sha>`
([brief.ml](../../src/quest/brief.ml) lines 81–86). The file header
says the previous round shows the commit it judged, never its
`--reason` (line 6). [GRADING.md](../../GRADING.md) lines 10–12 make
`make check-full` the grade gate. Lines 27–29 tell every grader to
plant a bug in a scratch copy and watch it go red. The induct-inline
skill, the default since `fa189ab` (2026-11-22), spawns one fresh
grader per grade from that brief verbatim, and the author never forms
the verdict
([skills/induct-inline/SKILL.md](../../skills/induct-inline/SKILL.md)
lines 66–88, 118–119).

November says carry the prior findings. The icebox says the same.
`brief.ml` and the 2026-11-22 quest withhold the reason on purpose
([2026-11-22 QUEST](../quests/2026-11-22-induct-inline-as-default-measure-author/QUEST.md)
lines 178–184: "this quest adds no delta-only rule"). The active
quest withholds it too, and its strongest red-chair attack is the
hole that leaves: a cycle-2 grader that never sees the cycle-1
finding can miss a bug swept under the rug (lines 199–200). Their
settlement is receipt plus the diff plus the touched gates, not the
November sentence.

### What shipped after the dossier

| Commit | Date | What it put in the loop |
|---|---|---|
| `4ab3228` | 2026-11-17 | Grader computes; another step casts. Pure grade. |
| `bf26447` | 2026-11-19 | Grade and land run `make check-full`. |
| `edb32a5` | 2026-11-19 | Default plan allows three review rounds. Ancestor of HEAD. |
| `d9bf388` | 2026-11-21 | Raises the cap to ten. Subject: `chore(plans): raise the review cap to ten rounds`. |
| `96a21d5` | 2026-11-22 | Cold brief rendered from the bound commit. |
| `fa189ab` | 2026-11-22 | Induct-inline is the default. One author session, one fresh grader. |
| `7bbd117` | 2026-11-22 | Induct-inline-yolo. Parks owner calls. Does not skip grades. |

`plans/default.yaml` is `max_cycles: 10`, `grade.required: true`,
`verify: required`. [AGENTS.md](../../AGENTS.md) lines 79–83 record
the owner's words of 2026-11-21, "increase the rounds to 10, i do not
want to be involved," and still escalate to the human at the cap.
The November text asked for the opposite move at the cap: stop
patching and make the owner reconsider the approach (dossier line
391). The cap went from 3 to 10. The escalation stayed. The
"reconsider the approach" wording did not land.

[CONTEXT.md](../../CONTEXT.md) still stamps the cheap half as absent,
checked 2026-11-19/20:

- Line 98: same commit binding as Anthropic, a looser cap
  (`max_cycles: 10` since 2026-11-21, was 3), every round a full
  re-grade.
- Line 99: later rounds review only the new diff. "bp3: not yet
  (fast-grader quest, on hold)."
- Line 100: a change must not edit the check that judges it. "bp3:
  not enforced."
- Line 58: a mistake becomes a line, a lint rule, or a test. "bp3:
  `runs/*/notes.md`, with no path from a note to a rule yet."

The November file itself still says `max_cycles: 3` and "three rounds"
(lines 358, 388, 539). [CONTEXT.md](../../CONTEXT.md) line 98 is the
line that moved. The dossier was not revised. A reader who starts
there is still told the open question is convergence.

`plans/direct.yaml` is the loop with no grade: `max_cycles: 0`,
`grade.required: false`, `verify: required`. A search for
`goal_type: direct` hit the plan file, `src/quest/main.ml`, and one
fixture string in a NODE.md. No quest `fsm.yaml` selects it.

The fast-grader quest that was supposed to receive the thaw is still
`status: proposed`, "on hold," "draft only, not approved"
([QUEST.md](../quests/2026-11-19-fast-grader/QUEST.md) lines 1–12).
The 2026-11-22 quest lists the icebox under "related, not promoted"
and puts a time cap and delta-only grading out of scope
([QUEST.md](../quests/2026-11-22-induct-inline-as-default-measure-author/QUEST.md)
lines 56–58, 156).

```text
November dossier
  cheap half     delta, carry findings, nit cannot block,
                 locked check, observe mode, ask the owner at the cap
                 --> not in brief.ml, not in GRADING.md, scripts absent
  expensive half fresh grader, verdict bound to the SHA,
                 full re-judge, make check-full
                 --> induct-inline, the default since fa189ab
owner 2026-11-21 "ten rounds, I do not want to be involved"
                 --> plans/default.yaml max_cycles: 10
                    (escalation at the cap stays; "reconsider" does not)
```

### The bill is three populations

They are not one number, and the November forces table used the wrong
quantity. It lists "bp3's 100-200k-token grades" as the token-cost
evidence
([agent-harness-landscape.md](agent-harness-landscape.md) line 511).

**Test-pyramid, written up 2026-11-19.** The fast-grader quest's
census, from grader transcripts and `bp3 q r` timings, as that file
states it: 25 grades, 16 of them re-grades, median about 11 minutes
(range 4–37), 78k–198k tokens of context each. tier.1: 7 cycles, 14.3h
wall, 9.4h of it in `handed_off`. Findings: "about half: tests that
could not fail, or claims beyond the evidence." Quest and node
records 1,508 lines. Commit messages 53–77 lines on diffs of 42–135
lines. Framing note: `make check` 9s, `make check-full` 36s, and the
slow part was never the gates
([QUEST.md](../quests/2026-11-19-fast-grader/QUEST.md) lines 36–45,
120–124).

The icebox copy of the same run rounds differently: 7 to 35 minutes
and 100–200k tokens, tier.1 took 8 rounds, and a delta brief cut later
rounds to 7–15 minutes
([ICEBOX.md](../quests/2026-11-19-fast-grader/ICEBOX.md) lines 19–27).
[CONTEXT.md](../../CONTEXT.md) line 118 says the tier.1 runner took six
grading rounds on signal edge cases and was then rewritten. Seven,
eight, and six are all in authored files. This dossier does not pick
one.

"Half" is also two sentences. The icebox says about half of all
findings were probes that could not fail, or commit messages claiming
more than was verified, and that a self-check by the author would have
caught them in minutes (lines 21–24). The receipt node says about half
the findings were commit messages that claimed more than was verified
([NODE.md](../quests/2026-11-19-fast-grader/nodes/node-verify-2-receipt/NODE.md)
lines 101–103). The November options row compresses both into "what
scripts catch." A self-check, an overclaiming message, and a vacuous
test are three different fixes. The icebox also says "Graders were
precise; no finding was wrong" (line 21). Accurate and expensive can
both be true. The files do not say the findings were worth the wall.

**One grade whose spend was counted, 2026-11-21.** rules.4 round 4:
wall 1,280s, context at the end 173,523, input/output 100 / 77,424,
cache read 5,505,097, cache write 170,483. The quest file says the
grade processed about 5.75M tokens, 33 times the context figure,
almost all of it cache reads, and that 78k–198k was the wrong quantity
([metric-collectors QUEST](../quests/2026-11-21-metric-collectors/QUEST.md)
lines 73–91). 52 tool calls. No dollar figure. No file re-derives the
other 24 grades onto that spend metric. A shorter brief would change
the context figure. What it would do to the 5.75M was not measured.

**Later inline grades, two cuts.** The 2026-11-22 quest, citing
`metrics r` on three earlier quests: grade-wall median 201s (Claude,
metric-followups) and 109s (pi, pi-metrics); tool time 5–53s of a
76–237s Claude grade; author about 53% of quest wall on
metric-followups (~23 of ~44 min) and about 62% on pi-metrics (~13 of
~20 min), estimated from ledger dwell
([QUEST.md](../quests/2026-11-22-induct-inline-as-default-measure-author/QUEST.md)
lines 42–45). On that measurement, author time is the larger share,
and the quest's own reason for inline was that the grader's wall is
the author's dead time, so overlap is the cheapest saving (lines
140–142). Overlap is what `fa189ab` shipped. It does nothing for a
dependent chain: the skill waits for the grader when nothing else is
ready to author
([SKILL.md](../../skills/induct-inline/SKILL.md) lines 54, 60–64).

The active quest cites a different cut of the same 2026-11-22 quest,
from `bp3 q 2026-11-22-induct-inline-as-default-measure-author metrics r`:
5 nodes, 16 grades, grade-wall sum 6,675s (111.3 min), median 377s
(6.3 min), max 674s (11.2 min), author-wall sum 3,411s (56.9 min).
Grading 66% of that compute. Of 11 `needs_fix` bounces, the quest
author's classification is 1 prod bug, 4 vacuous tests, 4 minor-only,
2 prose nits
([QUEST.md](../quests/2026-11-23-fast-agy-induct/QUEST.md) lines
20–26). The wall sums are attributed to `metrics r`. The 1/4/4/2
split is attributed to `git show` of `ledger.jsonl`. This dossier did
not re-run `metrics r` and did not read a ledger. Those rows are the
quest file's claims.

The 53–62% author share and the 111-versus-57 split are different
quests. Using either one as "the" backpack loop picks a side of the
fork in advance. tier.1's 14.3h, with 9.4h in `handed_off`, is the
nearest written multi-hour total, and most of it is dwell in a state,
not a grade transcript. Nothing in the files measures a quest that
ran all 10 cycles.

`make check` and `make check-full` were not re-timed on 2026-11-23.
The 9s / 36s pair is the 2026-11-19 framing note. The 170.40s `make
check` is the 2026-11-18 lesson, before the unit tier
([CONTEXT.md](../../CONTEXT.md) line 116).

### What the 2026-11-23 keepers run

Outside evidence here is the 2026-11-23 learn report's reading of
pages it opened. This dossier did not re-fetch them. URLs are the
ones that report names.

People who published a run they then kept do not run a fresh model
grader that re-judges the gates. Ronacher's kept port is one pi
session, the existing Rust snapshot suite as the oracle, 10h of which
3 were supervised, about 45 minutes of his time, 34 prompts, $60,
2.2M tokens
([MiniJinja port](https://lucumr.pocoo.org/2026/1/14/minijinja-go-port/),
as read in the learn report). His killed factory is Astra: 35h, about
$1,200, about 1B tokens on the run log, 79 commits, nothing he would
keep. The same post's ~4B figure is a different estimate
([Astra](https://lucumr.pocoo.org/2026/9/7/astra-why/)). Hashimoto
adds no model grader; a mistake becomes a line or a tool; one
background agent
([adoption journey](https://mitchellh.com/writing/my-ai-adoption-journey)).
Steinberger stays the coordinator of sessions he can see, hits escape,
and says a fresh context spends about ten minutes rereading
([just talk to it](https://steipete.me/posts/just-talk-to-it)). The
Ask HN setup thread was sampled, first 50 of 504 top-level comments,
not a census: the visible majority in that slice is one Claude or
Codex session plus a definition of done
([50366117](https://news.ycombinator.com/item?id=50366117)).

The labs that do run a model reviewer spend the time on purpose.
OpenAI's harness essay, read only on the zh-Hant mirror, describes
review until the agent reviewers are satisfied, runs that often exceed
six hours, and a linter whose error text contains the fix
([mirror](https://openai.com/zh-Hant-HK/index/harness-engineering/)).
Cognition measured a clean-context reviewer at about 2 bugs per pull
request, about 58% severe, and still says parallel writers have no
meaningful adoption. Their "up to 60%" line does not match the $1.35
versus $10.53 row in the same material, and this dossier does not
resolve that
([multi-agents](https://cognition.com/blog/multi-agents-working)).
Nobody in the opened set published a token factor for diff-only
re-review versus a full re-judge. The icebox's 7–15 minutes is a
backpack wall figure from one writeup, not that factor.

Twitter, same pass: `@0xSero` describes a loop that spends tokens on a
local worker inside one session, not on a fresh grader.
`@realGeorgeHotz` returned no posts from the API, so his timeline is
unread. `@__tinygrad__` is a different account. The blog essays are a
different surface. Detail and the rejected recaps live in the learn
report; they are not re-argued here.

### Amp, fetched 2026-11-23

The November forces table cites Amp for "fresh context beats
compaction"
([agent-harness-landscape.md](agent-harness-landscape.md) line 510).
That citation is the 2025-10-23 post, and Amp has since published the
opposite product decision. The pages below were fetched for this
dossier. Podcasts were not transcribed. Public threads linked from the
ball-pit essay were not opened.

**The loop they named.** Lewis Metcalf, 2026-02-05, "Feedback
Loopable": a problem the agent cannot see (a moving animation) becomes
a playground the human and the agent share, URL query parameters that
make a bug repeatable, and a headless CLI that prints text so the
inner loop is bash
([feedback loopable](https://ampcode.com/notes/feedback-loopable)).
He did not tell the CLI which columns to print. The agent added a
position delta, and frame 20's delta is the bug. He writes that he did
not read that CLI until the essay. The human reviews the result, not
the code, and sends the next URL. The same shape on their own product
is a `widget` CLI, wrapped in a skill, that renders a TUI widget as a
tree or as ASCII. No token count, no wall time, no count of bugs the
CLI missed.

Harry Charlesworth, 2026-01-14: the failure mode is under-specification,
and the speed trap is an agent that outruns the human's ability to
verify. The prompt he keeps is a reference file plus "run the tests
after each step." Last line: "Trust isn't a feeling, it's a passing
test suite"
([how to pair](https://ampcode.com/notes/how-to-pair-with-an-agent)).
No measurement.

Permissions, 2025-09-10: agents work best when they can run the tests
and see the result. Taking tools away makes the agent reach for bash.
Git makes a wrong edit cheap
([permissions](https://ampcode.com/notes/permissions)). FIF, notes
index 2025-04-29, still says edit-by-edit approval "traps you in a
local maximum by impeding the agentic feedback loop"
([FIF](https://ampcode.com/notes/fif)). The same page still argues
against a model selector. The 2026-11-12 post killed the dial and
shipped one
([bye bye dial](https://ampcode.com/news/bye-bye-dial)). The
edit-approval paragraph was not retracted in the page fetched. A model
switch, that post says, busts the prompt cache, and the first message
after it costs more.

**Their reviewer is a comment feed.** 2025-12-18: a review agent on
Gemini 3 Pro replaces a single-shot review. The loop is write, open
the panel, drag a diff range, read the review while it runs, feed the
comments back into the writing agent. They say quality improved and
publish no count. Open questions they leave: reviews are not 1:1 with
threads, and they have not decided whether accepted or rejected
comments should land in `AGENTS.md`
([agentic review](https://ampcode.com/news/agentic-code-review)).
2026-02-04: `amp review` and an in-thread "review the outstanding
changes." A check is a markdown file in `.agents/checks/`. The review
tool starts a separate agent per check, which they say is a stronger
guarantee than burying the check in `AGENTS.md`. The writing agent can
be told to fix what came back
([liberating code review](https://ampcode.com/news/liberating-code-review)).
That is a second model. It is not a verdict bound to a SHA, and it has
no round cap.

**They reversed the compaction line.** 2025-10-23: compaction removed,
replaced by handoff, because compaction "encourages long, meandering
threads" and they want focused ones. The human edits the drafted next
prompt before sending
([handoff](https://ampcode.com/news/handoff)). Lewis, 2025-12-09, one
feature he shipped: 13 threads connected by mentions, biggest thread
"151k output tokens and four user messages," average "around 80k."
"Agents get drunk" on a long thread. He is explicit that he does not
keep spec files to move context; he mentions the previous thread
([200k](https://ampcode.com/notes/200k-tokens-is-plenty)). 2026-05-06:
compaction is back, automatic at 90% full, and handoff is gone, because
"today's leading frontier models are great at handling compaction."
They turned it off for a day during a migration and "everyone
complained." One beta user: "I love having auto-compaction. NOT
missing handoff"
([Amp, rebuilt](https://ampcode.com/news/neo)). 2026-07-02: their
longest thread has been compacted over 68 times and would be over 21
million tokens without that. The first version of the `read_thread`
subagent answered from the first hit; in a long thread that hit is
often an attempt later revised or reverted
([read bigger threads](https://ampcode.com/news/read-bigger-threads)).
The November line that treats Amp as a witness for fresh context over
compaction is the retired post.

**Subagents, then orbs.** Thorsten Ball, 2025-06-10: the search
subagent was read-only and had been there from the start. Other typed
subagents failed, either because humans could not tell them apart or
because the model did the work itself. Sonnet 4 invokes generic
subagents that can write and run commands, each with its own context
window, including in parallel. He writes that they do not know whether
plan files are now obsolete, and they did not crank the system prompt
([agents for the agent](https://ampcode.com/notes/agents-for-the-agent)).
No count of tasks those subagents finished. Tim Culverhouse,
2025-12-18: renaming a function from the agent's `present()` to his
`swapScreens()` made later turns spin. Letting the agent pick the
probable name made it faster. "Cost more tokens" is his description,
not a ledger
([by an agent](https://ampcode.com/notes/by-an-agent-for-an-agent)).

2026-02-19: with the newest models, the wrapper "is no longer the
limiting factor" and bash is often enough. The bottleneck he names is
how the codebase and the org are arranged. Editor extensions
self-destruct 2026-03-05
([the coding agent is dead](https://ampcode.com/news/the-coding-agent-is-dead)).
2026-07-02, putting an agent in an orb: `.agents/setup` is a 428-line
bash script (database, locked toolchain, `pnpm install`, and an
orb-local `AGENTS.md`). A `dev-server` skill's script reuses a healthy
server or restarts a wedged one so the agent does not diagnose that
itself. Two demos came back "after a couple of minutes" and "after a
few minutes," with screenshots, and he had not said how to start the
server or log in
([putting an agent in an orb](https://ampcode.com/notes/putting-an-agent-in-an-orb)).
2026-08-04: when a change is about 800 lines he tells the orb he wants
"100% proof," screenshots, a video, a matrix of cases. "The agent runs
for eight, ten, twenty, sometimes thirty minutes." He can close the
laptop. "More things shipped, faster" has no count attached. He spends
the first half of the essay saying a feature list would not be
believed
([what I want to tell you](https://ampcode.com/notes/what-i-want-to-tell-you-about-orbs)).
2026-08-25: an orb is a remote agent that sleeps when idle, costs only
while running, can be spawned in the hundreds, can wake on a schedule,
and can spawn other orbs and message them
([orbs, explained](https://ampcode.com/notes/orbs-explained)).

The Amp Way, docs page fetched 2026-11-23, no date in the body: core
team pushes to main, no mandatory PR review, agents "run in a loop,"
threads are shared for humans to look at. "Feedback loops for the
agents above everything else." A thread ends when the change has
landed and they know it works, not when the code is written. "Our
agents wait on us, not the other way around." A bug report starts an
orb immediately; most of the time the fix is right and they push it
([the Amp way](https://ampcode.com/docs/using-amp/how-we-work)). How We
Build, notes index 2025-05-12: "thesis-driven, not metrics-driven," and
also "put your numbers on the board." No task longer than a week. A
branch should not sit and grow to 10,000 lines
([how we build](https://ampcode.com/how-we-build)). The numbers they
actually printed are the thread sizes, the 68 compactions, the 428-line
setup script, and the 8-to-30 minute proof runs. There is no keep-rate
and no token ledger for a feature.

Against the fork: Amp's published loop is the writer running a fast
text oracle, plus a human looking at the result, plus an optional
review agent whose comments go back into the writer. That is closer to
a receipt script and a watching human than to a fresh grader that
re-judges the gates for up to ten rounds. Their 8-to-30 minute proof
run is the same order of magnitude as backpack's later grade medians
(109s, 201s, 377s, and the 11-minute census), and it is the writer
producing proof, with the human gone. It is not a second session
bound to a SHA. The counter-case is the one they leave open: they
built the review agent because review is the bottleneck, they have not
measured it, How We Build says they are not metrics-driven, and a
screenshot the writer produced is an oracle the writer can satisfy.
"100% proof" is a prompt, not a check the change cannot edit.

### Where the November file aimed the next quest

The forces table pulls two ways at once: fresh children per step,
because context rots, and narrow briefs plus cheaper models, because
tokens cost money (lines 510–511). A grader with different tools
should be its own session, because of the prompt cache (line 514).
The shipped shape took the fresh session and the full re-judge. The
narrow brief, the cheaper model, and the delta stayed in the icebox.
The 5.75M-token grade is the bill of the half that shipped, and it is
almost all cache reads. The forces table predicted that shape. It
also predicted the other half, which was the half with the only
internal wall-time claim.

Open question 1 then told the next session to treat "whether to have a
grader" as settled. The options table had not settled it. Review
option (b) was sitting in the same file, conditioned on a "half" the
census does not cleanly define. That is the mechanical way an unused
exit survives a dossier: the ranked question points somewhere else.

## Forces

| Force | Evidence | What it does to the fork |
|---|---|---|
| Owner attention versus the owner's instruction | Dossier line 391: at the cap, ask the owner to reconsider. Owner, 2026-11-21, recorded in AGENTS.md: ten rounds, do not involve me. Escalation at the cap remains. | Raising the cap is a way to be left alone. It multiplies grade wall on a node that does not converge. It does not test the cheap half. |
| Fresh context versus a narrow brief | November forces, lines 510–514, citing Amp for fresh context over compaction. That Amp post is 2025-10-23. Amp's 2026-05-06 product is automatic compaction, and handoff is gone. `brief.ml` lines 81–86: full re-judge plus a diff. Icebox: delta cut later rounds to 7–15 min, unshipped. | A and D. The shipped pull is the expensive one. The unshipped pull is the one with a wall number. The Amp citation under the shipped pull has been retired by Amp. |
| The prompt cache | November line 514. The counted grade is ~5.75M tokens, almost all cache reads. | A shorter brief's effect on spend is unmeasured. Wall and spend can move differently. B is not settled by the context-size figure. |
| Goodhart, in the expensive form | GRADING.md lines 27–29: plant a bug by hand, every round. CONTEXT.md line 100: a change must not edit its check; bp3 does not enforce that. Icebox line 21: findings were precise. | The guard that shipped is grader labor. The guard the dossier ranked first (tests the author cannot edit) is a script that is not on disk. |
| Dwell versus grade wall | tier.1: 9.4h of 14.3h in `handed_off`. The 2026-11-22 quest's own ground: author ~53–62% on two earlier quests. The active quest's ground for that same quest: 111 min of grade versus 57 min of author. | B depends on which population is "the" quest. They disagree. The half-day story can be waiting on a human, or it can be the grader. |
| A bundle hides the cause | The active quest's scorecard is one before/after: median grade wall 377s to <=180s, mean cycles 3.2 to <=1.5, on a quest that also adds `agy` and `/swarm` (lines 188–195). | If it lands as one diff, the next dossier cannot tell A from a harness change. |
| The peer the advice was copied from | November lines 387–389 and 535–549, aimed at Anthropic's three-round reviewer. CONTEXT.md line 98 already records the cap mismatch. The 2026-11-23 keepers with a log do not run that reviewer. Cognition's ~2 bugs/PR is the counter-measurement. | C. Copying more of the lab loop (unbounded review, a manager of writing children) spends the resource the owner is out of. |

## Options

Doing nothing is included. Each option says what would have to be true.
None of these is a decision.

**(a) Leave the running brief alone.** Induct-inline, cap 10, full
re-judge, `make check-full`, hand-planted mutants, fresh grader, author
in the main session.

Takes nothing. Breaks nothing that is already shipped. The November
convergence advice stays untested, and the next quest keeps today's
bill. Wins if the half day is `handed_off` dwell and framing time, or
if the independent verdict is worth 111 minutes of grade wall on a
five-node quest. The icebox's "no finding was wrong" is the evidence
on that side.

**(b) Land the cheap half as its own change, and measure it.** Cycle
2+ scoped to the diff. A nit cannot force `needs_fix`. A script
prints the gate and the red-first result so the grader does not hunt.
No new harness, no second writer.

Takes a quest whose scorecard splits those three pieces. Breaks the
active quest's bundle: that quest is the place this work already got
written down, and splitting it is a scope change that quest would have
to accept. Also breaks nothing mechanical until the design picks a
side of the findings question. November and the icebox carry prior
findings. `brief.ml` and the active quest withhold `--reason`. The
active quest's red chair says the withhold can miss a swept bug. The
2026-11-19 fast-grader draft also had the grader write the fix; the
2026-11-23 quest settled the grader as read-only. Those are two
drafts, not one patch.

Wins if the icebox's 7–15 minute later rounds show up again, and if
the bounce split is mostly vacuous tests and minors. The 1/4/4/2
split would support that, and it is an unre-run ledger classification.
The "half" sentences do not, by themselves.

**(c) Stop model-grading work the owner is watching.**
`plans/direct.yaml` already encodes it: no grade, verify still
required. No quest fsm found here selects it.

Takes a plan flag on a quest, plus the owner in the session. Breaks
the independent verdict the inline skill exists to protect. The
vacuous-test census, and Lobsters commenters saying a session that
writes the code and the tests writes weak tests, are the case against
it ([kornel](https://lobste.rs/s/miwcai/do_you_let_llms_write_both_your_tests_your),
via the learn report). No file times one prompted session against
induct-inline. "Sometimes the old way would have been faster" is the
owner's question, not a result. Wins if the grader's catches are the
class a script or a watching owner already sees, which is the
condition the November options table wrote for review option (b).

**(d) Run the active quest as written.** Cheapening, plus `agy`, plus
`/swarm` parallel authors, scored as one before/after on itself.
Target: median grade wall <=180s, mean cycles <=1.5.

Takes the quest that is already `status: active`, an owner sign-off
for adding `agy` to CONSTRAINTS.md (the quest's open question 2), and
the learn-report fold-in its open question 1 asks for. The scripts it
names are not on disk. Breaks the ability to close A, B, or C from
the result, because a miss has four causes. Parallel writers are the
shape Cognition's later post still rejects for the writing role, and
the shape Astra's log killed. Wins if this repo has independent ready
nodes often enough that author wall and grade wall both have to move,
and if the scorecard is later split so the cheap half can be read on
its own.

**(e) Copy more of the lab loop.** Review until the reviewer is
satisfied. A manager of writing children. More rounds.

The November file already lists "add more agents" and "the grader
fixes every finding" under tempting and misleading (lines 492–494).
OpenAI's unbounded review is a choice to spend agent time instead of
human time. Wins if the goal is lab throughput with the owner
optional at merge. The 2026-11-21 instruction makes the owner less
involved by raising the cap. It does not say to spend more grader
passes. The keepers with a log did not take this option. Amp's 2026-02-19
post says the wrapper is no longer the limiting factor, and their
review product feeds comments back into the writer instead of adding
rounds.

Amp's published loop, read against (b) and (c): the fast oracle is a
CLI or a test the writer runs (Metcalf's playground, Charlesworth's
"run the tests after each step," the orb setup script), and the human
looks at a URL, a screenshot, or a video. The review agent is optional
and returns comments, not a `needs_fix` cast. That is (b)'s script and
(c)'s watching human inside one thread. It does not add an option.
What would have to be true for it to beat (a) here is the same
condition as (b) and (c): the catches in the census are the class a
script or a watching owner already sees. Amp does not supply that
count. Their open question, whether rejected review comments become
`AGENTS.md`, is the learning path [CONTEXT.md](../../CONTEXT.md) line
58 says bp3 does not have yet (`runs/*/notes.md`, no path to a rule).

**If a change is made.** The learn report's proposal 2 is the Amp
shape of that change, and this dossier does not adopt it. A CLI the
writer runs prints the gate, whether the new tests fail on the parent,
and the case that failed. The human reads that output. If a second
model reviews, it returns comments into the writer for one pass. It
does not open a fresh session that re-judges every gate, and it does
not loop until it is satisfied. A grader that still runs still
withholds `--reason`. Feeding those comments to the writer is not the
same as pasting the previous verdict into the next grade. The change
is not `agy`, not `/swarm`, not orbs, not push-to-main, and not a
change to the cap. `scripts/receipt` and `scripts/red-first` were
absent when this was written. What would have to be true is the same
condition as (b) and (c). Amp did not publish the count. The counter
already written on (b) still applies: a delta that never carries
findings can miss a bug the writer swept, which is the active quest's
own red chair. A second counter belongs to this shape and not to (b):
a CLI the writer owns is an oracle the writer can satisfy. Amp does
not discuss that.

**Lab pass, same day, does not move this.** A later section of the
learn report reads the Anthropic, OpenAI, and Google harness posts as
product copy. It does not add an option, and this dossier does not
adopt one. Anthropic's published dollar table puts the hours on the
writer: a solo run at 20 minutes and $9, a three-agent harness at 6
hours and $200, a later run at 3 hours 50 minutes and $124.70. Each
QA round on that later run was 6.8 to 9.6 minutes and about $3 to $4,
and round two still found stubbed features. They then deleted context
resets and the sprint scaffold when the next model no longer needed
them ([Harness design](https://www.anthropic.com/research/harness-design-long-running-apps)).
Their research multi-agent post says most coding tasks are a poor
fit, and the 90.2% figure is an internal research eval
([multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system)).
The C-compiler team cost just under $20,000 and still called GCC for
the part it could not do
([C compiler](https://www.anthropic.com/engineering/building-c-compiler)).
OpenAI's English essay, fetched 2026-11-23, says the autonomous loop
should not be assumed to generalize
([Harness engineering](https://openai.com/index/harness-engineering/)).
Google's 95% table is labeled illustrative. The sample loop is `go
test`, one retry, then a human
([Durable loops](https://cloud.google.com/blog/topics/developers-practitioners/how-to-build-durable-agentic-systems-with-google-antigravity-from-instructions-to-loops)).
Jules, the previous async agent, is in a published wind-down with no
keep-rate
([Jules turndown](https://jules.google/docs/changelog/2026-10-29.md)).
None of that is a catch-rate for this repo. Copying the lab loop is
still option (e).

**Lean, labeled.** The grade bill that the active quest itself cites
(111 minutes of grade wall against 57 of author, on the 2026-11-22
quest) lines up with the November sentences that are absent from
`brief.ml`: delta, a nit that cannot block, a check the author cannot
word. The sentences present in the running brief are the expensive
half, and the cap moved from 3 to 10 against the dossier's "at the
cap, ask the owner."

**Strongest counter-case.** tier.1's 14.3 hours were 9.4 hours in
`handed_off`, so the half-day story can be waiting, and shortening the
grader does not touch it. The 7–15 minute figure is one writeup, the
round counts disagree (6, 7, and 8), and a delta that hides prior
findings is the active quest's own strongest attack. "The advice is
bad" waits on one run of the unused half. Until that run, A and D are
open, and C is a lean from other people's logs, not a measurement of
this repo's catch-rate.

**Second lean, weaker.** November open question 1 aimed the next
quest at Anthropic's reviewer. The 2026-11-23 keepers who published a
log they kept do not run that reviewer.

**Its counter-case.** The icebox says the graders were precise and no
finding was wrong. Cognition's clean-context reviewer is a measured
~2 bugs per pull request, ~58% severe. Amp built a review agent for
the same reason and published no catch-rate. Dropping the grader drops
a check the files call accurate. The files do not say what that
accuracy cost per bug, and they do not say how many of the accurate
findings a script would have printed first.

## Open questions (ranked by what they change)

1. **On the next quest that feels like half a day, how many minutes
   are grade wall, how many are `handed_off`, and how many are
   author?** The written populations disagree about which share is
   larger. The answer picks (a), (b), or (c) as the lever. This
   dossier did not run `metrics r`. The legal read is `bp3 q <quest>
   metrics r` and `bp3 q r <quest>`, not a hand parse of
   `ledger.jsonl`.

2. **If cycle 2+ is delta-only, do prior findings get carried or
   withheld?** November and the icebox carry them. `brief.ml`, the
   2026-11-22 quest, and the active quest withhold `--reason`. The
   active quest claims receipt plus touched gates cover a swept bug.
   The scripts in that claim are not on disk. The answer decides
   whether (b) and (d) are the same design.

3. **Of the `needs_fix` rounds, how many are vacuous tests, how many
   are overclaiming messages, how many are minors, and how many are
   prod bugs?** The "half" sentences name different sets. The 1/4/4/2
   split is one quest file's ledger classification, unre-run here.
   The answer is the November condition for review option (b), and the
   condition for a severity gate. It decides (b) versus (c).

4. **Does the review have to be a new session?** Amp's review agent
   feeds comments back into the writer, and since 2026-05-06 their
   product compacts inside one thread instead of handing off to a
   fresh one. bp3's grader is a new session by construction
   ([induct-inline](../../skills/induct-inline/SKILL.md) lines 84–88),
   which is also what [CONTEXT.md](../../CONTEXT.md) line 93 records
   as the defense against a judge favoring its own output. The answer
   decides whether (b) is a shorter fresh brief or the writer running
   the oracle with comments coming back. Amp did not publish which of
   those catches more.

5. **Does a shorter brief change the ~5.75M cache-read spend, or only
   the ending context size?** One grade was counted. The other 24
   were not. The answer decides whether "narrow the brief" is a token
   fix. Wall time can fall while cache reads stay. Amp's 2026-11-12
   note that a model switch busts the cache is a different event from
   a grade whose 5.75M is almost all cache reads inside one session.

6. **Does `plans/direct.yaml`, on a quest the owner is watching,
   finish sooner with a keep-rate the owner accepts?** No timed
   comparison exists. The answer decides (c). It is a plan flag. It
   is not a new engine.

7. **If the active quest lands as one bundle, which piece moved the
   median?** The written scorecard is one before/after for receipt,
   severity, delta, `agy`, and `/swarm` together. Without a split,
   the result cannot close A. The answer decides whether (d) is an
   experiment or a new default that cannot be interpreted.

Cut, because the answer would not move this fork: cross-vendor
reviewer versus the same model, why Beads left JSONL, spec weight,
org scale, batch size, and switching the default grader to pi on the
unpaired 109s versus 201s medians. Those were November questions, or
they are already flagged as unpaired in the learn report.

## What I did not verify

- `bp3 q r` and `bp3 q <quest> metrics r` were not run. `state.yaml`,
  `ledger.jsonl`, and `metrics.jsonl` were not parsed. The active
  quest's 6,675s / 3,411s figures and the 1/4/4/2 bounce split are
  that QUEST.md's claims. Frontmatter `status: active` is the
  authored field, not an engine rollup of where its nodes sit.
- `make check` and `make check-full` were not re-timed. 9s / 36s is
  the 2026-11-19 framing note. 170.40s is the 2026-11-18 lesson.
- The November sources were not re-opened. External rows other than
  Amp, and other than the lab pages linked in the lab-pass paragraph,
  are the 2026-11-23 learn report's reading, with the URLs it names.
  Amp's pages listed above, and the lab pages linked above, were
  fetched on 2026-11-23. Not opened: the three public ball-pit threads, the
  Raising an Agent podcast episodes, the `widget` CLI in a repo, and
  any Amp thread used as a run log. The 8-to-30 minute proof range is
  Thorsten Ball's account of his own use, not a table. The Amp Way
  page has no date in the body. FIF's model-selector section and the
  2026-11-12 dial post disagree; the later post is the product, and
  the FIF page had not been revised to match when it was fetched.
- The English OpenAI essay was fetched on 2026-11-23 and matched the
  mirror. The METR PDF was not opened. `@realGeorgeHotz` returned no
  posts, so that timeline is unread. `@__tinygrad__` is a different
  account. Antigravity launch posts, `/swarm`, and the arXiv paper
  behind the 22–29% adoption line were not opened. The lab-pass
  paragraph above uses only the pages it links.
- `docs/icebox/2026-11-19-fast-grader.md` was absent. Why it is absent
  was not recovered from git. The verbatim copy in both quest
  `ICEBOX.md` files still says frozen and `promoted: null`, while the
  active quest's prose says promoted.
- No host repo was searched for a quest that selects
  `plans/direct.yaml`.
- tier.1's six, seven, and eight rounds were not reconciled. They may
  be different cuts of one node. They may be a mistake. The files do
  not say which.
- The learn report ranks concrete changes. Its proposal 2 is the Amp
  shape named under "If a change is made." This dossier does not
  adopt that ranking, and it does not adopt that proposal. The
  options above are the decision space.
