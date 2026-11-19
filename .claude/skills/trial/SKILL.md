---
name: trial
description: Produce the Landing IIUC for a bp3 Quest being promoted — diligence gate first (every node checked against its own acceptance; unsettled or improperly-done nodes route to red-ink, not landing), then decision record, settled picture, demo traces, files touched, verification, and deliberately-open items.
---
<!-- GENERATED from skills/trial/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->

# Red-Ink Quest Landing Demo

Use when a human or Controller in bp3 invokes this skill by
name (`/trial`), when a Quest reaches
Quest-to-master promotion, or when asked “walk me through
what this quest became / what got done / give me the demos.”
One output: a Landing IIUC, presented in chat and, on human
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
5. Demos: one worked trace per acceptance claim — happy
   path, the main failure/refusal path, and the recovery
   path where one exists. Label each honestly: `observed`
   (actually run; quote real output) or `design trace`
   (walked from the spec). A design trace is never dressed
   as a run.
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
- Instructions only: this skill writes nothing unless the
  human approves recording the landing; it takes no bp3
  moves and edits no ledger or state.
- Keep it readable in one sitting: short sentences, short
  paragraphs, tables only where a mapping earns them.
