# Run notes — exp-mvp-4-diagram-emit (handoff, cycle 1)

- Claimed link first; run_id matched the brief. The run
  folder did not exist, so it was created fresh.
- `read_file` resolves against the conductor checkout, not
  this worktree: live sources were read through bash in the
  worktree instead. Future children in desks should do the
  same or use absolute worktree paths.
- Diagram renders one `quest_view` snapshot per call, so
  ascii and mermaid of the same moment cannot drift; the
  json form carries both texts for fact diffing.
- Mermaid node ids sanitize `-` to `_`; labels keep the
  real slug, state, cycle, and `exp_fin`.
- Fixture proof lives in `test/diagram.sh`: diamond waves,
  blocked-starves in both formats, read-only, strict argv.
