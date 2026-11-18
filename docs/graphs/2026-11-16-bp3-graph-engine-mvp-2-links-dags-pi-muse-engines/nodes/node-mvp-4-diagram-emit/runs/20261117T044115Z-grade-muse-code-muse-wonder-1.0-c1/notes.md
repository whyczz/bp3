# grade notes — exp-mvp-4-diagram-emit @ fe6efe7

Verdict: ship (code-reviewer procedure: correctness, design, tests, comments).

- Rung 1: EXPERIMENT.md asks for ascii+mermaid from live rollup, waves + starved, honest generated label. No open design questions; no deferred gated cases.
- Rung 2: diff touches only render.ml (emitters), main.ml (diagram verb), store.ml (reserved slug "diagram"), completions, Makefile, test/diagram.sh. Both emitters share diagram_nodes/deps/waves/starved over one quest_view snapshot + one generated_at (main.ml:426-451), so same-moment equivalence holds by construction. mermaid_id is injective on the slug alphabet [a-z0-9-] (store.ml valid_slug), no id collisions. Comments at render.ml:327-335 and main.ml:406-409 agree with code.
- Rung 3: `make check` green (incl. diagram tests: ok, shellcheck, completion tests); live ascii/mermaid on this quest show identical 14 nodes incl. exp-mvp-4 (handed_off, cycle 1) with same timestamp; fixture tests prove deps, waves [[nb],[nc]], starved, exp_fin, currency, read-only, strict argv.
- Minor (non-blocking): empty-quest "(none)" branches untested; mermaid equivalence asserted by spot greps + exact json deps/waves rather than full cross-format diff.
