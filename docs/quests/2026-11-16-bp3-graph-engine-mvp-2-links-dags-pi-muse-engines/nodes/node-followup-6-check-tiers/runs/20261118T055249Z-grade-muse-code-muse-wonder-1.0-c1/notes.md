# followup.6 check-tiers — grade run notes (cycle 1)

Verdict: ship. Bound commit 0f60c7a50a826ca932a99c0097a2baf7ac227877.

## Evidence (rungs 1-3, no tape read needed)

- Rung 1: NODE.md acceptance + amendment read; no open design question.
- Rung 2: `make check` recipe byte-identical before/after f96a969;
  no deletions (`--diff-filter=D` empty); full-tier harness.sh retained.
- Rung 3 (run, not read): selector lists match all four mappings
  (skills -> check-skills/skills/bp3g, src -> build/g,
  render -> skills-check/wf:bp3g-grade, unknown -> fast tier);
  sweep ok in 0.076s; test/check-tiers.sh ok (14 assertions);
  `make check-fast` exit 0 in 54.7s (< 120s, harness excluded);
  full `make check` 390s green quoted from the handoff run notes
  and the evidence matrix, corroborated by the unchanged recipe.
- Rung 4 (code-reviewer): no critical/major findings. Comments in
  both scripts state the table, fail-safe, and fossil reasons and
  agree with the code. One cosmetic nit (root-file grep lines lack
  a filename prefix) does not change pass/fail and is not named
  in the fix.

## Lesson

Tier membership set from measured suite times (g.sh ~126s stays
out of the fast tier) is what keeps the 120s bound honest.
