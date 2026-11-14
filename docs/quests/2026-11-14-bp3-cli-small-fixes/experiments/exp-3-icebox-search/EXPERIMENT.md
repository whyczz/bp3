---
date: 2026-11-14
quest: ../../QUEST.md
exp: 3
status: proposed
---

# Exp 3 — Icebox search: `bp3 q icebox r`

## TL;DR

`bp3 q` gains a read-only icebox door: `bp3 q icebox r
[term...]` lists frozen entries in `docs/icebox/` (slug,
date, status, promoted, title), filtered by a
case-insensitive substring over slug, title, and body when
terms are given; `bp3 q icebox r <slug>` prints that one
entry in full. JSON by default; `--format table` renders
the list through Exp 1's flat-shape renderer. The door
writes nothing — no ledger, no refs, no `promoted:`
marking (promotion stays the `quest` skill's move).

Added to this quest at framing, 2026-11-14, on the owner's
ask ("for us to search iceboxes"). It fits the quest's
human-surface scope but is new function, not a papercut
fix — recorded here so the red chair can price it honestly.

## Demo (design trace)

```text
$ ./bin/bp3 q icebox r
slug                         date        status  promoted  title
2026-11-14-bp3-cli-small-fixes  2026-11-14  frozen  -         bp3 CLI small fixes (rendered tables, tab completion)
2026-11-13-session-log-mining   2026-11-13  frozen  -         ...

$ ./bin/bp3 q icebox r table completion
2026-11-14-bp3-cli-small-fixes  ...  (2 matches in body)

$ ./bin/bp3 q icebox r 2026-11-14-bp3-cli-small-fixes
<full text of docs/icebox/2026-11-14-bp3-cli-small-fixes.md>

$ ./bin/bp3 q icebox r nope-not-a-slug
{"ok":false,"error":{"code":"E_NOT_FOUND", ...}}   (same verdict shape as quest not-found)
```

Today (observed): `./bin/bp3 q icebox r table` returns
`E_NOT_FOUND quest "icebox"` — the noun is parsed as a
quest name.

## Diagram

```text
bp3 q icebox r ─► dispatch: "icebox" noun (special case, like "hooks")
                    ├─ no arg ────────► list all entries
                    ├─ arg = slug ────► print entry text
                    ├─ arg = terms ───► list entries whose slug/title/body contains all terms
                    └─ no match ──────► empty list (ok) / E_NOT_FOUND (single-slug read)
                  reads: docs/icebox/*.md under BP3_ROOT ── writes: nothing
```

## Pseudocode

```python
def icebox_read(args, fmt):
    entries = [parse(f) for f in glob(root/"docs/icebox/*.md") if f != "README.md"]
    # parse = frontmatter (status, date, promoted) + first '# ' title; dumb, line-based
    if len(args) == 1 and is_slug(args[0], entries):
        return text_of(args[0])                      # full entry, verbatim
    hits = [e for e in entries if all(t.lower() in haystack(e).lower() for t in args)]
    return verdict(ok=True, entries=hits)            # rendered json | table per fmt
```

## Tables

| Field | Value |
|---|---|
| Intent | find a frozen idea without `ls` + `grep` archaeology across `docs/icebox/` |
| Lane | standard |
| Output | `icebox` noun in `src/quest/main.ml` dispatch + list/read in a small reader (store/render seam); fixtures in `test/q.sh` |
| Acceptance | cases below; the headline case fails today (observed above) |
| Depends on | Exp 1 for `--format table` rendering of the list (JSON works without it; sequence Exp 1 first) |

| Case | Expected after |
|---|---|
| `bp3 q icebox r` | every entry except `README.md`, sorted by filename; fields slug/date/status/promoted/title exact from frontmatter |
| `bp3 q icebox r <term...>` | only entries containing all terms (case-insensitive) in slug+title+body; no hits → `ok` with empty list |
| `bp3 q icebox r <slug>` | that entry's full text, byte-identical to the file |
| unknown slug-shaped arg with no text match | empty list, not an error (it's a term until it matches a slug exactly) |
| entry with `promoted:` set | shown in the list; the door never sets it |
| entry missing/malformed frontmatter | listed with `-` fields, never a crash (files are hand-authored) |
| writes | none: `git status` clean after any icebox command |

## Acceptance test (goal block)

- **Objective:** frozen entries are searchable and readable
  through `bp3 q icebox r`, read-only.
- **Prove by:** the four traced commands against today's
  real `docs/icebox/` (7 entries); a malformed-frontmatter
  fixture entry in a scratch repo; `git status` after each
  command; `make check` green.
- **Done when:** list/terms/slug outputs match the traces,
  the malformed entry degrades to `-` fields, and the
  worktree stays clean.

## Prose

Context: the owner asked mid-framing whether this quest
could carry icebox search. Why it fits: same human surface,
same "stop doing archaeology by hand" motive as the table
fix, and its list is exactly a flat shape. Why it is
carefully fenced: an icebox entry "is not a quest, not
state" (`docs/icebox/README.md`) — quests are listed from
git refs (`src/quest/store.ml:174`), entries are plain
files, so this door is the CLI's first filesystem reader.
That is safe precisely because it can only read: any write
verb here (`c`, promotion, thaw) would smuggle state into a
folder defined by having none, and is out. Parsing stays
dumb on purpose — three frontmatter fields and the first
heading, line-based, no markdown model — because the entry
shape is a convention, not a schema, and hand-authored
files must degrade, not crash. Sorting is filename order,
which is date order by the `YYYY-MM-DD-<slug>` convention.

## Tests

unit: none (line parser is fixture-sized; justified per
the test-split standard) · fixtures: list/terms/slug/
malformed/no-write cases in the q fixture suite against a
scratch icebox dir · demos: the traces above on the real
`docs/icebox/`
