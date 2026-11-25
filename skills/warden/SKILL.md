---
name: warden
description: Land a bp3 quest and run the self-improving audit — diligence gate, Landing IIUC + runnable trial, deterministic bp3 warden audit, standalone FEEDBACK.md, and <= 3 tiered harness proposals for owner disposal.
---

# Warden

Use when a human or Controller invokes `/warden [<quest>]`, when a
quest reaches promotion (`goal_fin`), or when asked to review a
finished quest, demo what shipped, or audit the repo for harness
waste. Replaces `/trial` as the single landing and self-improvement
skill.

One output:
- With `<quest>`: diligence gate, Landing IIUC + runnable trial,
  `bp3 warden <quest>` findings table, standalone
  `docs/quests/<quest>/FEEDBACK.md`, and at most **3** concrete
  proposals for owner disposal.
- With no `<quest>`: repo-wide `bp3 warden` sweep (repo invariants +
  last 5 unreviewed quests without `FEEDBACK.md`) and at most **3**
  concrete proposals.

Use `quest` to frame a new quest, `red-ink` while a design is still
being settled, `induct` to run nodes, `using-bp3` for a
single state edge, and `icebox` to freeze a deferred idea.

## Diligence gate (runs first when landing a quest)

Landing is a claim: every node did what its `NODE.md` promised.
Before any playback or audit, check each node:

| Check | Pass evidence |
|---|---|
| Design settled | no open questions in the node; no unadopted `*.red-ink.md` working copy |
| Acceptance met | every Acceptance case has `observed` evidence (run output, ledger line, test), not prose |
| Review judged the node | the grade verdict binds the bound commit AND the node's acceptance cases |

Any node failing a check stops the landing. Do not present a clean
playback over a failed node: open `/red-ink` on that node (working
copy, owner as gate) and settle it first.

## Procedure

1. **Diligence gate & Landing IIUC (when `<quest>` is landing):**
   - Run the diligence gate and report its table first.
   - State the verdict in the quest's own Success picture words, give
     the settled one-diagram map, decision record (`before -> after`),
     files touched, exact verification run (and what was not run),
     and deliberately open items.
   - Run `bp3 release <quest> --dry-run` (read-only) to preview the
     next semver tag, `release_kind` (`github` vs `git_tag`), and
     rendered "What changed" notes inside the Landing IIUC.
   - Write `docs/quests/<quest>/trial/trial.sh` (scratch sandbox,
     never this repo's state; exercises happy path, refusal path, and
     recovery where one exists; echoes commands and fails non-zero on
     mismatch). Record with
     `asciinema rec --overwrite --headless -c ./trial.sh trial.cast`
     when `asciinema` is installed, or run `trial.sh` live and quote
     its observed output.
2. **Deterministic audit (`bp3 warden`):**
   - Run `./bin/bp3 warden <quest>` (or `bp3 warden <quest>` in host
     mode; omit `<quest>` for a repo sweep).
   - Never invent findings outside deterministic `bp3 warden` output
     and directly cited evidence (`ledger:*`, `metrics:*`, `git:*`,
     `tx:*`, `desk:*`, `repo:*`).
   - Inspect each cited `evidence_ref` and group findings by root
     cause.
3. **Write standalone `docs/quests/<quest>/FEEDBACK.md` (when auditing `<quest>`):**
   - Keep `QUEST.md` as the plan of record and `LOG.md` as the build
     log; write post-quest review state only to `FEEDBACK.md` (its
     presence marks `<quest>` reviewed for bare `bp3 warden`).
   - Sections in `FEEDBACK.md`:
     - **Human post-land feedback**: bugs, steering friction, or
       surprises reported by the owner after `node_fin`.
     - **Warden deterministic summary**: exact `bp3 warden <quest>`
       counts (`by_layer`, `by_rule`, `sessions_scanned`) and audited
       findings table (TP / FP classification when backtesting).
     - **Proposals (`<= 3`)**: ranked by ROI, citing exact finding
       refs and target files.
     - **Owner disposition**: recorded decision per proposal
       (`applied <sha>` | `icebox <path>` | `quest <path>` | `skipped`).
4. **Draft `<= 3` concrete proposals (anti-bloat rules):**
   - **Hard cap:** propose at most **3** improvements per `/warden`
     run, ranked by ROI.
   - **Deterministic first:** prefer a lint check, script, or test
     over a prose rule. Only propose prose when no deterministic
     check can express the invariant.
   - **Pruning check:** whenever proposing an addition to prose
     (`GRADING.md`, `AGENTS.md`, `CLAUDE.md`, or a skill), inspect
     the target file for stale or redundant lines to prune — name
     what to delete, or state plainly why nothing can be cut.
5. **Present for tiered owner disposal (warden proposes, owner disposes):**
   - Stop and ask the owner to dispose each proposal (plus promote or
     another pass when landing):
     - **Small harness fix (1–2 files):** on owner go, apply directly
       as one clean bp3 commit, verify with `make check`, and record
       its SHA in `FEEDBACK.md`.
     - **Larger / multi-file fix:** freeze to `docs/icebox/` via
       `/icebox` or frame as a follow-up quest via `/quest`, and
       record the path in `FEEDBACK.md`.
     - **Skip / defer:** mark `skipped` in `FEEDBACK.md`.
     - **Cross-repo `bp3` bug or feature (host mode):** never edit
       `bp3`'s checkout from a downstream repo — file it via
       `bp3 ticket add --to bp3 --kind bug|feature --title "..." --body "..."`
       (repos auto-register on `bp3 init`). In self mode, inspect
       incoming tickets with `bp3 ticket list --to bp3` (then
       `bp3 ticket read|claim|unclaim|done|dismiss <id>`).
     - **Promote / release (owner go only):** run
       `BP3_DECIDER=human bp3 release <quest>` (or
       `BP3_DECIDER=human ./bin/bp3 release <quest>` in self mode) to
       atomically CAS-move `master`, tag `vX.Y.Z`, and publish the
       GitHub Release (or local tag).

## Rules

- **Warden proposes, owner disposes:** never auto-commit fixes,
  never auto-edit `GRADING.md`/`AGENTS.md`/skills, never promote, and
  never push without explicit owner approval.
- **Deterministic findings only:** every finding traces back to
  `bp3 warden` output or a cited git/ledger/transcript artifact —
  never fabricated prose complaints.
- **Read-only on bp3 state:** never hand-edit `state.yaml`,
  `ledger.jsonl`, or `metrics.jsonl`, and take no `bp3 q` state moves.
- **Keep `FEEDBACK.md` concise:** short tables, exact counts and
  refs, readable in one sitting.
