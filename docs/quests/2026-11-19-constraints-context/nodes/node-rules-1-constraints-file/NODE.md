---
date: 2026-11-19
quest: ../../QUEST.md
node: rules.1
status: proposed
---

# rules.1 - constraints-file: the owner-signed stack, in one file

## TL;DR

`CONSTRAINTS.md` at the repo root lists the languages bp3 is written
in, the libraries and tools each language may use, and the surfaces
bp3 ships. Adding any of them takes the owner's sign-off after a
`/teach` pitch, recorded as a dated row in the owner's words. A
fenced `constraints` block is the list itself, readable by people
and by the lint (rules.2).

## Acceptance gates

Observed today:

```text
$ ls CONSTRAINTS.md
ls: CONSTRAINTS.md: No such file or directory
```

Design trace:

```text
$ sed -n '/^```constraints/,/^```$/p' CONSTRAINTS.md
```constraints
lang ocaml  ext .ml .mli  files dune dune-project    libs stdlib unix str yojson ounit2 qcheck-core qcheck-ounit
lang bash   ext .sh .bash  shebang bash sh           libs git jq yq sed awk find mktemp make gh shellcheck yamllint
lang zsh    files completions/_bp3                    libs (completion builtins only)
lang node   ext .mjs .js .ts  shebang node           libs node:* @earendil-works/pi-coding-agent
data        ext .md .json .jsonl .yaml .tsv .txt .mmd .conf  files Makefile Brewfile .gitignore
```
$ grep -c '^| 2026-11-20 | owner' CONSTRAINTS.md
1
```

```yaml
objective: one root file says what bp3 may be built from and shipped as
prove by:
  - read CONSTRAINTS.md
  - the constraints block parses (rules.2's lint reads it)
done when:
  - Languages, Surfaces, How to change and Sign-off log sections exist
  - every language and surface row matches the quest's approved table
  - the sign-off log's first rows quote the owner's approval of this quest
```

## Diagram

```text
owner idea / plan adds X ──► /teach pitch (why X, cost, the boring alternative)
                                   │ owner: yes, in their words
                                   ▼
          Sign-off log row (date, owner words) + one constraints block line
                                   │
                                   ▼
                     lint (rules.2) and the readers (read.1) see X
```

## Pseudocode

```python
CONSTRAINTS = {
    "languages": {lang: {"where": paths, "libs": names} for lang in ("ocaml", "bash", "zsh", "node")},
    "surfaces": ["bp3 CLI", "skills", "harness extensions"],
    "change": "teach pitch -> owner words -> dated row; never by an agent alone",
}
```

## Tables

| Field | Value |
|---|---|
| Intent | write down what "brings a lot of value" protects, so a plan can be checked against it |
| Lane | micro |
| Output | `CONSTRAINTS.md` |
| Acceptance | the sections and rows above; fails today (no file) |
| Depends on | none |

The approved table lives in the quest file (Constraints at
approval); this node transcribes it.

## Prose

The trigger was tier.1 of test-pyramid: a runner in bash plus perl
one-liners that nobody signed off on, six grading rounds on signal
edge cases, then an OCaml rewrite after the owner asked "why can't we
use ocaml for this?". Nothing written said perl was off the table, so
no plan, red ink or grader could flag it.

Libraries sit inside languages (owner, 2026-11-19: "they are tools,
call them libraries, e.g. we pick langs, but also libraries within
the lang"). For bash, the tools it shells out to are its libraries.

Edge cases:

- **Docs are not code.** Python pseudocode in skills and records is
  prose; `docs/**` and `*.md` are out of the lint.
- **Harness CLIs** (`pi`, `claude`, `codex`) are surfaces bp3 drives,
  listed under Surfaces, not libraries.
- **One copy of the list.** The block is the list; prose around it
  says where and why, and never restates it, so the two cannot drift.
- **zsh is already here**: `completions/_bp3` is a zsh completion.
  The census grandfathers it as a dated row rather than pretending
  bp3 has three languages.
- **An agent may not add a row.** Rows change only with owner words
  in the sign-off log; read.1's grader rule checks that a diff to
  CONSTRAINTS.md carries one.
