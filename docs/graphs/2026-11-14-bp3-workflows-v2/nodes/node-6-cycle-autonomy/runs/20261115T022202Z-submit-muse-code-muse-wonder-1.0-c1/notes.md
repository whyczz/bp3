# exp-6 cycle-autonomy — author notes (c1)

Work: rewrote `skills/induct/SKILL.md` as the conductor plus
cycle autonomy, then re-installed (`bp3 skills install`) so
`.pi`/`.claude`/`.agents` copies match. Added 7 text
assertions to `test/skills.sh`; `bash test/skills.sh` passes
(55 assertions).

Lessons:
- The FSM already auto-cycles: `needs_fix`/`fail` below
  `max_cycles` returns the exp to `todo` at cycle+1
  (`src/quest/main.ml`); only the cap lands in `blocked`.
  The skill just had to stop paging the owner for weather.
- The branch base predates Exp 3's conductor text (master
  carries it; this quest branch does not), so the rewrite
  ports the conductor dispatch table before amending it.
  Workflow JS files were left untouched as out of scope.
- Multi-word grep assertions must match single lines;
  phrases split by wrapping fail silently into a red test.
