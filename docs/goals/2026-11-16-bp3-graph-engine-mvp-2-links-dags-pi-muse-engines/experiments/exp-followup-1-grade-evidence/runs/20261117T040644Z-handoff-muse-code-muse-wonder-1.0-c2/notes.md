# exp-followup-1-grade-evidence — handoff run notes

Run: 20261117T040644Z-handoff-muse-code-muse-wonder-1.0-c2 (handoff, cycle 2)

## What changed

Cycle-2 fix (owner A): `validate_run_folder_present` is now
trustworthy.

- `skills/traverse/workflows/induct-grade.js` (+ synced
  `.agents/workflows/induct-grade.js` render):
  - The validations transport brief now prescribes exactly one
    shell one-liner (`for d in <expDir>/runs/*/; do ... echo
    "$n tape=$t notes=$u"; done`) and requires its stdout lines
    back unchanged as `run_folders` — never reformatted into
    prose. Extracted and run verbatim during this run, it emits
    `20261117T033939Z-handoff-...-c1 tape=yes notes=yes`.
  - `folderLines` accepts an array or a newline-joined string
    and drops blank lines; `lineHasFile` reads presence
    tolerantly (canonical `tape=yes`, `tape.log present`,
    `tape: yes`, bare `contains tape.log and notes.md`) while an
    affirmed absence (`=no`, `missing`, `not found`) never
    passes. `validate_run_folder_present` keeps the handoff
    preference and the exact fail quote.
- `test/induct-grade.test.mjs`: regression block feeding
  transport variants — canonical lines, three prose shapes, a
  newline string, an empty list, and missing-file lines in
  canonical and prose form — proving the existing handoff
  folder (`20261117T033939Z-handoff-...-c1`) passes and a
  folder missing `tape.log` or `notes.md` still fails and
  gates (`needs_fix`).

## Lessons

- A validator that only accepts one exact string makes the
  transport's phrasing part of the contract; either pin the
  transport to one emitted line or read presence semantically.
  This fix does both, so neither side can drift alone.
- Tolerant parsing must be asymmetric: affirmations widen,
  negations veto. A reader that treats any mention as present
  would pass the failure sentence itself.

## Verification

- Reproduced first with a mock-host probe (kept in /tmp):
  canonical passed; every prose/string variant false-failed
  with `no run folder with tape.log and notes.md`, matching
  the cycle-1 grade. After the fix all present-variants pass
  and all missing/empty variants still fail.
- `node test/induct-grade.test.mjs`: ok
- `./test/traverse.sh`: ok (node-loop, induct-node,
  induct-grade, quest-land, traverse-conduct)
- `./scripts/check-skills`: ok (40 files);
  `./test/skills.sh`: ok (123 assertions); `make lint`: ok
- `make check`: ok (full gate, exit 0).
