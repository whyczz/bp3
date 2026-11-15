# Check-in report — toy fleet preflight drive (2026-11-15)

Fleet named in merge order: `toy-a`, `toy-b`, `toy-c`.
Footprints declared in each toy QUEST.md Scope/Output
(fixtures under `/tmp/fleet-drive/`, checker
`/tmp/fleet-drive/preflight.py`, run by the author).

Observed preflight output, quoted verbatim:

```text
toy-a: ADMITTED footprint=['docs/toy-a/', 'docs/toy-a/hello.txt']
toy-b: ADMITTED footprint=['docs/toy-b/', 'docs/toy-b/hello.txt']
toy-c: REFUSED at preflight, overlaps toy-a, zero Runs spent
merge order: ['toy-a', 'toy-b']
```

| Quest | Fleet outcome |
|---|---|
| toy-a | admitted, disjoint |
| toy-b | admitted, disjoint |
| toy-c | refused at preflight, named, overlaps toy-a, zero Runs spent |

Ready for `quest_fin`, in predeclared merge order:
none in this drive — the fleet never merges, and this
drive stopped at preflight by design.

Not observed in this drive: two disjoint toy quests
reaching `exp_fin` in parallel, fleet-budget stop, and
shared-decision grouping. Those need a conductor-run
fleet with unlanded toy quests; the skill rules for
them are in `skills/induct-quest-no-human/SKILL.md`
and are grep-asserted in `test/skills.sh`. This report
does not claim them as live-proven.
