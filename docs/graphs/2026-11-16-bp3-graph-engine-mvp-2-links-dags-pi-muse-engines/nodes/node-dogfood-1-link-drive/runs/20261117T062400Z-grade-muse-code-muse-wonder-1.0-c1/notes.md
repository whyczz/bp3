# Grade notes — exp-dogfood-1-link-drive c1

- Reviewed by code-reviewer procedure at commit adfd7b0: claims from EXPERIMENT.md vs diff (Makefile + test/dogfood-link.sh only, no product code).
- Rung 3 observed: ./test/dogfood-link.sh -> "dogfood-link tests: ok"; node test/pi-tree.test.mjs standalone -> "pi-tree tests: ok".
- Findings: no critical/major. Minor: metrics setup_refusals/cycles_to_land are fixed values recorded by the drive, time is second-granularity; calls log is the drive's own record, not a tape inventory. Comments agree with code; tests can fail (brief size/one-line, E_LINK_SPENT/E_NOT_FOUND/E_NO_CONTEXT, pi parent chain, supervisor fold).
- Gate note: one `make check` run failed in pre-existing test/pi-tree.test.mjs orphan-watch (E_NOT_FOUND on watch after bind-tape) under make load, before dogfood ran; that file is untouched by this commit and passed standalone in this run. Treated as flake, not a defect of this diff.
- Verdict: ship.
