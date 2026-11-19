---
name: trial
description: "Land a bp3 Quest with something the owner can watch and try — diligence gate first (unsettled or improperly-done nodes route to red-ink), then the Landing IIUC and a trial: one sandboxed script, recorded with asciinema and runnable live."
---
<!-- GENERATED from skills/trial/SKILL.md by: bp3 skills install --harness=pi. Edit the source, then re-run. -->

# Trial

Use when a human or Controller in bp3 invokes this skill by
name (`/trial`), when a Quest reaches
Quest-to-master promotion, or when asked “walk me through
what this quest became / what got done / let me try it.”
One output: a Landing IIUC with its trial (a script the owner
can watch as a recording or run live), presented in chat and, on human
approval, recorded at the Quest's landing.

Use `quest` instead to frame a new Quest. Use `using-bp3`
to operate quest state. Use `icebox` to freeze a deferred
idea. Use `red-ink` while a design is still being decided.

## The diligence gate (runs first, always)

Landing is a claim: every node did what its `NODE.md`
promised. Before any playback, check each node:

| Check | Pass evidence |
|---|---|
| Design settled | no open questions in the node; no unadopted `EXPERIMENT.red-ink.md` working copy |
| Acceptance met | every Acceptance case has `observed` evidence (run output, ledger line, test), not prose |
| Review judged the node, not just the code | the review verdict binds the bound commit AND the node's acceptance cases |

Any node failing a check stops the landing. Do not present
a clean playback over a failed node: open `/red-ink` on
that node (working copy, owner as gate) and settle it
first. This is where the red ink happens — at landing
time, when the reviewer says an node was not done properly,
the answer is a red-ink walk, not an apology paragraph in
the demo.

## Inputs

Read, in this order: the Quest file (and any working copy
the session settled, e.g. `QUEST.red-ink.md`), its
Terms/Concepts, nodes and acceptance checks, the decision
history the owner settled, `git log`/`git diff --stat` for
the change, bp3 verdicts where a binary exists, and icebox
entries or deferrals the quest spawned.

## Procedure

1. Run the diligence gate. Report its table before anything
   else; a failed node ends the run here (see above).
2. State the verdict: what is now true that was not true
   before this Quest, in the Quest's own success-picture
   words.
3. Give the settled picture in one diagram or short map:
   the parts, their owners, and the one flow that matters.
4. Decision record: every settled decision, one line each,
   before -> after, grouped by the walk's slices (output,
   inputs, data/state, functions, names, concepts).
5. Trial: write `docs/quests/<quest>/trial/trial.sh`. It
   builds a scratch sandbox (temp repo, freshly built binary;
   never this repo's state), then runs the happy path, the main
   refusal path, and the recovery path where one exists,
   echoing each command before it runs and exiting non-zero on
   any unexpected result. Record it in that folder with
   `asciinema rec --overwrite -c ./trial.sh trial.cast` (add
   `--headless` when recording without a terminal, as agents do); the owner
   replays it (`asciinema play trial.cast`)
   or runs `trial.sh` live, which prints the sandbox path and
   leaves it for poking until the owner removes it. Numbers in
   the IIUC come from this run (`observed`); a claim the script
   does not exercise is a `design trace`, labeled so, never
   dressed as a run.
6. Files touched: changed paths with one-line roles; name
   the original any working copy forked from, and state
   whether it is untouched.
7. Verification: what was actually run and observed,
   quoted; then what was not run, and why, in plain words.
   Never claim a gate that was skipped, dropped, or
   substituted.
8. Deliberately open: every deferred question with its
   owner or its icebox path. A deferred item is recorded,
   never quietly dropped.
9. Close with the checkpoint question the owner answers:
   promote, or another pass. On promotion, offer to record
   the Landing IIUC under the Quest's Success picture.

## Rules

- The demo is evidence, not marketing: numbers come from
  runs and ledgers, never from prose about runs.
- Terms in the Landing IIUC are the Quest's settled Terms,
  spelled exactly as the code and data structures spell
  them.
- Writes only the quest's `trial/` folder (`trial.sh`,
  `trial.cast`) and, on the owner's approval, the recorded
  Landing IIUC; it takes no bp3 moves and edits no ledger or
  state. The sandbox never touches this repo's refs.
- Keep it readable in one sitting: short sentences, short
  paragraphs, tables only where a mapping earns them.
