---
date: 2026-11-22
quest: ../../QUEST.md
node: install.2
status: proposed
---

# install.2 - drift-check: a repo can see stale renders and a mixed install

## TL;DR

`bp3 skills check` becomes the one drift door. It compares every render
the repo has (SKILL.md under `.claude/skills`, `.pi/skills`,
`.agents/skills`, and the workflow renders as today) with what
`bp3 skills install` would write now, and refuses `E_RENDER_STALE` naming
each stale file. In the installed layout it also compares
`bp3-q --build` with `share/bp3/BUILD` and refuses `E_INSTALL_MIXED`
when they differ.

## Acceptance gates

Observed today:

```text
$ grep -c 'one node in flight' ~/m/predictor/.claude/skills/induct-inline/SKILL.md
2                                   # predictor runs the 2026-11-20 induct-inline
(fixture host repo after bp3 skills install; one line appended to .claude/skills/induct-inline/SKILL.md)
$ bp3 skills check
{"ok":true,"fresh":[...]}           # only workflow renders are compared
```

Design trace:

```text
(same fixture)
$ bp3 skills check
{"ok":false,"error":{"code":"E_RENDER_STALE","facts":{"stale":[{"render":".claude/skills/induct-inline/SKILL.md","source":"skills/induct-inline/SKILL.md"}]},...}}
$ bp3 skills install && bp3 skills check
{"ok":true,...}
(scratch PREFIX install; share/bp3/BUILD rewritten to 0.2.0+0000000)
$ $S/bin/bp3 skills check
{"ok":false,"error":{"code":"E_INSTALL_MIXED","facts":{"binary":"0.2.0+e79a73a","share":"0.2.0+0000000"},...}}
(bp3 repo, self mode)
$ ./bin/bp3 skills check            # fresh, as today
```

```yaml
objective: a downstream repo's stale renders and a mixed install are refused by name, not passed
prove by:
  - test/skills.sh: host fixture, fresh renders -> ok; one SKILL.md render edited -> E_RENDER_STALE naming exactly it;
    a render deleted -> named too; re-install -> ok; a workflow render edited -> named (as today)
  - test/skills.sh or install.sh: scratch PREFIX, BUILD rewritten -> E_INSTALL_MIXED {binary, share}; repo layout (bp3 itself) never checks BUILD
  - property (seeded, 20 runs): edit a random subset of the fixture's render files -> the stale list equals that subset
  - make check-full
done when: each case holds and the SKILL.md and mixed-install cases fail on master
```

## Diagram

```text
bp3 skills check
  ├─ installed layout? ── bp3-q --build ≠ share/bp3/BUILD ──► E_INSTALL_MIXED
  └─ render the core (and, self mode, dev) skills into a temp target with skills_install's own render
       └─ cmp each render file the repo has against the temp copy ──► stale list ──► E_RENDER_STALE | ok
```

## Pseudocode

```python
def skills_check(target, mode, layout):
    if layout == "installed":
        b, s = run("bp3-q", "--build"), read(share / "BUILD").strip()
        if b != s:
            refuse("E_INSTALL_MIXED", binary=b, share=s)
    tmp = mktemp_dir()
    render_all(src_dir, tmp, harnesses=present_in(target), mode=mode)  # the function skills_install uses
    stale = [f for f in expected_renders(tmp) if not same(target / f, tmp / f)]
    if stale:
        refuse("E_RENDER_STALE", stale=[{"render": f, "source": source_of(f)} for f in stale])
    ok(fresh=names(expected_renders(tmp)))
```

## Tables

| Field | Value |
|---|---|
| Intent | drift is a refusal with a file name, not a silent pass |
| Lane | standard |
| Output | `bin/bp3` (`skills_check`, a render-to-target helper shared with `skills_install`), `test/skills.sh` |
| Acceptance | the trace above; the SKILL.md and mixed cases fail today |
| Depends on | install.1 (`share/bp3/BUILD`) |

| Case | Today | After |
|---|---|---|
| SKILL.md render edited or stale | ok | `E_RENDER_STALE` naming it |
| SKILL.md render missing | ok | `E_RENDER_STALE` naming it |
| workflow render stale | `E_RENDER_STALE` | same |
| binary and share builds differ | not checked | `E_INSTALL_MIXED` |
| repo layout (bp3 itself) | — | no BUILD check; renders checked against `skills/` |

## Prose

Predictor's renders say "one node in flight" today, two quests after
that rule was replaced, and `bp3 skills check` passes them. The check
was written for workflow scripts (followup.2's render freshness) and
never grew to the skill text, which is the part a session actually
reads.

Rendering into a temp target with the same function `skills_install`
uses keeps one definition of "what the render should be". A second
hand-written comparison (strip the GENERATED header, diff the body)
would drift from the renderer the first time the header changes.

Which harness dirs count: the ones present in the repo. A repo with only
`.claude/` is not stale for lacking `.pi/`.

`E_INSTALL_MIXED` guards the one way the three pieces can disagree after
install.1: someone copies a binary or a share by hand. It's checked only
in the installed layout, where `share/bp3/BUILD` exists; bp3's own repo
runs the engine it just built.

The check is still advisory where it is today (induct runs it before
dispatch). It never re-renders by itself: a stale repo is fixed by
`bp3 skills install` and a commit, which is the repo owner's.

## Tests

Known cases: the table rows above in a host fixture and a scratch
PREFIX, plus self mode unchanged on the bp3 repo. Property-based: for a
random subset of render files edited (seeded, 20 runs), the stale list
equals the subset, so no render is missed or falsely named.
