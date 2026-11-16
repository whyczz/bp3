# followup.4 bind-resolution — cycle 2 run notes

- Cycle 1 narrowed the scan to tapes carrying the Run's own edge, but
  live it still refused: the conductor's tape quotes the child's brief,
  so it carries the invocation textually too. Cycle 2 establishes by
  start order instead of uniqueness: among own engine-fsm-edge
  carriers, the earliest session started at-or-after the Run's
  InitRecord wins; a tie or none refuses `E_AMBIGUOUS`. The quoting
  conductor started before the InitRecord, so it never establishes.
- The concept is named engine-fsm-edge (owner ruling):
  `tape_carries_own_engine_fsm_edge` / `engine_fsm_edge_of_run_id` in
  `src/quest/harness.ml`; the `bp3 q u <edge>` grammar and the ledger
  edge field keep their spellings.
- Session start is the first entry's own timestamp (pi session-header
  `timestamp`, muse microsecond `recorded_at`, unwrapping the first
  retained frame); the InitRecord's `ts` now folds into `init_ts`.
  No readable start means never viable — fail-closed, never a guess.
- The binding is one-to-one and pinned: the fold reads the first
  `tape_binding` row only, and `bind-tape` refuses `E_EXISTS` for a
  second, different tape or a tape already bound to another run-id.
  Re-binding the same tape is a no-op. This reverses followup.3's
  latest-binding fold; its rebind fixture now asserts the pinned read.
- Live proof: `find-tape` for the cycle-1 submit Run, which refused
  `E_AMBIGUOUS` with four tapes at e25e0ae, now resolves uniquely to
  the author's tape. `make check` green.
- Lesson: a quoted invocation is indistinguishable from a real one
  per entry; only session start against the InitRecord separates the
  quoter from the author, so fixtures must shape session starts, not
  just invocation lines.
