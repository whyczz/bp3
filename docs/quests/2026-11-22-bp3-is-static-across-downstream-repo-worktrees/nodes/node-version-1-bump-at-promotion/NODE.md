---
date: 2026-11-22
quest: ../../QUEST.md
node: version.1
status: proposed
---

# version.1 - bump-at-promotion: the version moves when a quest lands

## TL;DR

bp3's version system already exists (node-5: semver, a meaning table,
annotated tags, `release-check`, the version guard) and has never been
used: `0.2.0` for 263 commits. This node adds the missing rule and the
tool. Every QUEST.md declares `bump: major | minor | patch | none` at
framing; `make lint` refuses a proposed or active quest without one.
Promotion runs `scripts/bump <level>`, which edits `bp3_version`,
commits `chore(release): v<new>`, and tags it. `RELEASING.md` (new root
doc) holds the meaning table, plus a CLI row, and the promotion steps.
Tests stop pinning the literal `0.2.0`.

## Acceptance gates

Observed today:

```text
$ git tag -l 'v*'
v0.2.0                                   # fcfce07, 2026-11-14; 263 commits behind master
$ ls scripts/bump RELEASING.md           # No such file or directory (both)
$ grep -c '^bump:' docs/quests/*/QUEST.md | grep -v ':0' | wc -l
0
$ grep -n '0.2.0' test/release.sh test/g.sh
test/release.sh:41: [ "$out" = "0.2.0" ] || fail "--version: $out"
test/g.sh:71: ... .bp3_version == "0.2.0" ...
```

Design trace:

```text
(scratch clone of bp3, clean)
$ scripts/bump minor
{"old":"0.2.0","new":"0.3.0","tag":"v0.3.0","commit":"<sha>"}
$ grep 'bp3_version =' src/quest/gitx.ml
let bp3_version = "0.3.0"
$ git log -1 --format=%s; git cat-file -t v0.3.0; git rev-parse v0.3.0^{commit} HEAD
chore(release): v0.3.0
tag
<sha>
<sha>
$ scripts/release-check
0.3.0
$ echo x >> README.md; scripts/bump patch
bump: the tree has tracked changes; commit first        (exit 1; gitx.ml and tags unchanged)
$ scripts/bump none
{"old":"0.3.0","new":"0.3.0","tag":null,"commit":null}
(a proposed QUEST.md with no bump:)
$ make lint
check-bump: docs/quests/<q>/QUEST.md: status proposed needs bump: major|minor|patch|none
(this quest's QUEST.md, bump: minor)    # lint passes
$ ./test/release.sh && ./test/g.sh      # at 0.3.0 in the scratch clone: green (they read the constant)
```

```yaml
objective: the version moves at every promotion by a level decided at framing, with one command that commits and tags it
prove by:
  - test/release.sh: scratch clone; bump minor/patch/major from 0.2.0 -> 0.3.0 / 0.2.1 / 1.0.0, each with the release commit
    and an annotated tag at it, release-check ok; tracked change -> refused, nothing changed; none -> no commit, no tag;
    an existing tag v<new> -> refused (E-style message naming it), nothing changed
  - scripts/check-bump (in make lint): a proposed or active QUEST.md without a legal bump: -> named; landed and canceled exempt;
    a bad value (bump: big) -> named
  - test/release.sh:41 and test/g.sh:71 read bp3_version from gitx.ml; both pass after a bump in a scratch clone
  - make check-full
done when: each case holds and each fails on master (no script, no lint rule, literal 0.2.0)
```

## Diagram

```text
framing:   QUEST.md frontmatter  bump: minor          (red-ink checks it against RELEASING.md)
lint:      scripts/check-bump ── proposed|active without a legal bump: ──► refuse
promotion: merge quest/<q> ──► scripts/bump minor ──► commit "chore(release): v0.3.0" + annotated tag v0.3.0
                          ──► make release (dist/, checksum) ──► make install ──► push master + tag (owner's word)
```

## Pseudocode

```python
def bump(level):
    if level == "none":
        return {"old": V, "new": V, "tag": None, "commit": None}
    if git_rc("diff", "--quiet", "HEAD", "--") != 0:
        die("bump: the tree has tracked changes; commit first")
    old = read_version("src/quest/gitx.ml")
    new = semver_next(old, level)                 # major -> M+1.0.0, minor -> M.m+1.0, patch -> M.m.p+1
    if tag_exists(f"v{new}"):
        die(f"bump: tag v{new} already exists")
    write_version("src/quest/gitx.ml", new)
    commit(f"chore(release): v{new}", body=release_body(since=latest_tag()))   # bp3 format, merges since the last tag
    tag_annotated(f"v{new}", msg=f"bp3 v{new}")
    return {"old": old, "new": new, "tag": f"v{new}", "commit": head()}

def check_bump(quest_md):
    fm = frontmatter(quest_md)
    if fm["status"] in ("proposed", "active") and fm.get("bump") not in ("major", "minor", "patch", "none"):
        fail(quest_md)
```

## Tables

| Field | Value |
|---|---|
| Intent | versions mean something because they move by a declared rule |
| Lane | standard |
| Output | `scripts/bump` (new), `scripts/check-bump` (new, in `make lint`), `RELEASING.md` (new), `CLAUDE.md` and `AGENTS.md` (one Commands line), `test/release.sh`, `test/g.sh` |
| Acceptance | the trace above; fails today (no script, no rule, literal versions in tests) |
| Depends on | build.1 (RELEASING.md names the build id beside the version) |

`RELEASING.md`'s table (node-5's rows, plus the CLI row):

| Bump | Means | Examples |
|---|---|---|
| MAJOR | ledger or state meaning changes: a fold reads old lines differently | a ledger field renamed, a fold step reinterpreted |
| MAJOR | a CLI contract breaks: a door, verb, flag or error code removed or renamed, a JSON field removed | `bp3 g` → `bp3 q` |
| MINOR | a compatible addition: old binaries still fold new ledgers | a new verb, flag, optional field, skill, warning |
| PATCH | no meaning change | a bug fix, help text, speed |
| none | docs, tests, frames | a quest frame, a typo |

Before 1.0, a MAJOR-class change rides a MINOR bump (semver's 0.x rule);
`RELEASING.md` says so, and QUEST Open question 7 owns the 1.0 call.

## Prose

node-5 (2026-11-14) wrote the contract a bump signs and the guard that
enforces it, then shipped `0.2.0` and never bumped again. The guard is
correct and useless: it compares numbers that don't change. What was
missing is a moment. Promotion is the moment: it is already the owner's
gate, it already writes one merge commit, and it is when master gains
something a downstream repo could notice.

Declaring the level at framing, not at promotion, puts the call where
the design is reviewed. A red-ink round can argue "this removes a flag,
so it's major-class" while changing it costs a sentence; at promotion it
would be a guess about a finished diff.

`scripts/bump` refuses a dirty tree for the same reason `make install`
does: the tag must name a commit that is exactly the release.
It never pushes; pushing stays the owner's word.

The tests that pin `0.2.0` would break at the first bump, so they read
the constant instead. Fixture ledger lines that stamp `0.2.0` stay:
they are older-version lines, which the guard accepts silently.

This quest's own QUEST.md carries `bump: minor`, the first use. Its
promotion takes bp3 to `0.3.0`: since `v0.2.0` master gained the brief
verb, metrics, desks and skills (minor), and broke the CLI once (g → q),
which rides the minor before 1.0.

## Tests

Known cases: each level from a fixed version, the dirty refusal, `none`,
an existing tag, the lint cases, and the two tests reading the constant.
Property-based: `semver_next` over generated versions (major, minor,
patch in 0..99) holds the laws: the result is greater than the input;
major resets minor and patch; minor resets patch; exactly one component
changes in patch.
