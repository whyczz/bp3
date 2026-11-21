---
date: 2026-11-19
quest: ../../QUEST.md
node: rules.2
status: proposed
---

# rules.2 - constraints-lint: a new language or library turns lint red

## TL;DR

`scripts/check-constraints` reads the `constraints` block in
CONSTRAINTS.md and fails when a tracked file is in a language, or
uses an interpreter or a library, that the block does not list. It
runs in `make lint`, so both `make check` and `make check-full` see
it. About 60 lines of bash.

## Acceptance gates

Observed today:

```text
$ ./scripts/check-constraints
zsh: no such file or directory: ./scripts/check-constraints
```

Design trace:

```text
$ ./scripts/check-constraints
check-constraints: ok (4 languages, 118 files)
$ printf 'print(1)\n' > tools/x.py && git add tools/x.py && ./scripts/check-constraints
check-constraints: FAIL tools/x.py: language .py not in CONSTRAINTS.md
$ echo 'perl -e "print 1"' >> test/foo.sh && ./scripts/check-constraints
check-constraints: FAIL test/foo.sh:12: interpreter perl not in CONSTRAINTS.md
```

```yaml
objective: lint refuses a language, interpreter or library the owner has not signed
prove by:
  - test/check-constraints.sh (fixture tier) over a planted repo, one
    case per row below, plus the clean case
  - make lint on this repo
done when:
  - every case row prints its FAIL line and exits 1; the clean repo exits 0
  - make lint runs check-constraints (check-gates pins the step) and is green
  - deleting one lib from the block turns this repo's lint red, naming the use
```

## Diagram

```text
CONSTRAINTS.md ```constraints``` ──► allowed {lang: ext, shebang, libs}
git ls-files (minus docs/**, *.md) ──► per file:
   ext / shebang ∉ allowed               ──► FAIL language
   line invokes a known interpreter ∉ allowed (python, perl, ruby, php, lua, ...) ──► FAIL interpreter
   dune (libraries ...) ∉ ocaml libs     ──► FAIL library
   import "x" (not ./, not node:) ∉ node libs; package.json deps ∉ node libs ──► FAIL library
   Brewfile brew "x" ∉ bash libs         ──► FAIL library
```

## Pseudocode

```python
def check(root):
    allowed = parse_block(root / "CONSTRAINTS.md")      # missing or empty block: exit 2
    fails = []
    for f in tracked(root, exclude=["docs/**", "*.md"]):
        lang = lang_of(f)                               # by extension, then shebang
        if lang is UNKNOWN_CODE: fails.append(f"{f}: language {ext(f)} not in CONSTRAINTS.md")
        for n, interp in interpreters_invoked(f):       # fixed list of known interpreters
            if interp not in allowed_interpreters(allowed):
                fails.append(f"{f}:{n}: interpreter {interp} not in CONSTRAINTS.md")
    fails += unlisted(dune_libraries(root), allowed["ocaml"].libs, internal={"bp3_quest"})
    fails += unlisted(node_imports(root) | package_deps(root), allowed["node"].libs)
    fails += unlisted(brewfile(root), allowed["bash"].libs)
    report(fails)                                       # exit 1 on any, else ok line
```

## Tables

| Field | Value |
|---|---|
| Intent | the honor system that let perl in becomes a red lint |
| Lane | standard (changes the gate: Makefile, check-gates, check-tiers) |
| Output | `scripts/check-constraints`, `test/check-constraints.sh`, a `fixture` row, the lint step in `Makefile`, `scripts/check-gates`, `test/check-tiers.sh` |
| Acceptance | the case table on a planted repo; fails today (no script) |
| Depends on | rules.1 - constraints-file, rules.3 - stack-purge (follow-up) |

| Case planted | FAIL line names |
|---|---|
| a `.py` file | `language .py` |
| a `#!/usr/bin/env python3` script with no extension | `language python3 (shebang)` |
| `perl -e` in a shell script | `interpreter perl` |
| `python3 - <<EOF` heredoc | `interpreter python3` |
| `TMPDIR=x python3 f.py` (env assignments before the command) | `interpreter python3`: the 2026-11-19 census missed exactly this |
| a new dune library | `library <name> (ocaml)` |
| a new bare import in a `.mjs` | `library <name> (node)` |
| a new Brewfile entry | `library <name> (bash)` |
| CONSTRAINTS.md with no block | exit 2, `no constraints block` |
| a comment or string naming python (`# port of the python version`) | no FAIL: only command position counts (line start, after `\|`, `;`, `&&`, `$(`, or after `VAR=value` words); comment lines are skipped |
| a tracked file with an extension in neither a lang nor the data line | `language <ext>` |

## Prose

Prose rules in skills are the same honor system that let perl in, so
the owner chose a tiny lint (2026-11-19). It checks what a script can
judge: files, interpreters, declared libraries. Surfaces (CLI or web
app) are judged by people and graders (read.1), not here.

Known gaps, stated rather than hidden: a bash script calling a tool
that is not in the Brewfile (say `fzf`) is not caught, because
command detection in shell is guesswork. The Brewfile check catches
the declared install; the grader rule in read.1 catches the rest.

Adding a lint step changes the gate plan, and `scripts/check-gates`
pins that plan exactly (test-pyramid tier.2), so this node updates
check-gates and its planted-break test in the same commit.
