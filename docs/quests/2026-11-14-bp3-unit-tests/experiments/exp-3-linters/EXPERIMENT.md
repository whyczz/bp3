---
date: 2026-11-14
quest: ../QUEST.md
exp: 3
status: proposed
---

# Exp 3 — bp3 lint: rule engine for OCaml and the CLI surface

## TL;DR

bp3 owns its checks the way SonarQube owns rules — as
data, run by one engine, reported as structured findings.
`bp3 lint` classifies files by language (OCaml now) and
surface (the bp3 CLI), runs the rule pack, and emits JSON
findings; `make check` gates on it. Whatever is
machine-checkable becomes a rule; prose best-practices
stay out of skills.

## Demo (design trace)

```text
$ ./bin/bp3 lint --format json
{"ok":false,"findings":[
  {"rule":"ocaml/no-legacy-spelling","severity":"error",
   "file":"src/quest/render.ml","line":41,
   "message":"legacy name 'invoke' — the settled spelling is 'q'"},
  {"rule":"cli/every-verb-in-usage","severity":"warning",
   "file":"bin/bp3","message":"verb 'hooks' missing from usage_text"}]}
exit 1 (any error-severity finding)
```

## Diagram

```text
tracked files ──► classify (lang by extension, surface by path)
                      │
rules/               ▼
  ocaml.rules ──► engine ──► findings (JSON | tree)
  cli.rules        │            │
                   │            └── gate: error severity -> exit 1
                   ▼
            command rules wrap existing tools
            (shellcheck, ocamlformat --check, node --check)
            pattern rules grep settled spellings / forbidden forms
```

## Pseudocode

```python
def bp3_lint(paths, format):
    findings = []
    for f in tracked(paths):
        for rule in pack.for_file(f):       # rules are data
            findings += rule.check(f)       # command | pattern
    verdict = {ok: no_error(findings), findings: findings}
    print(render(verdict, format))          # json default, tree for humans
    return 0 if verdict.ok else 1
```

## Tables

| Field | Value |
|---|---|
| Intent | one owned, extensible check surface instead of check logic scattered across Makefile + test scripts |
| Lane | standard |
| Output | `bp3 lint` verb (OCaml, `src/quest/lint.ml`); rule packs as data files; JSON verdict; `make check` wiring |
| Depends on | Exp 2 (unit harness exists first) |

Starter rule packs (deliberately small; a rule enters only
after the sin it catches has happened or is one step away):

| Pack | Rules |
|---|---|
| ocaml | legacy spelling `invoke` in identifiers/strings; `Obj.magic`; bare `TODO` without owner; `ocamlformat --check` if available (command rule, absent tool = skip, stated) |
| cli | every verb in `bin/bp3` usage text; every edge named in `induct-exp.js` exists in the FSM legal-edges table; hooks JSON registered events ⊆ emitter's handled events |

## Acceptance (fails today: no `bp3 lint`, findings are Makefile prose)

| Case | Expected |
|---|---|
| `bp3 lint` on the clean repo | `{"ok":true,"findings":[]}`, exit 0 |
| seeded `invoke` spelling in a scratch copy | exact rule id, file, line; exit 1 |
| seeded unregistered hook event | cli pack finding naming the event |
| absent optional tool (ocamlformat) | rule skipped, skip stated in output — never a silent pass, never a hard failure |
| `make check` | fails when `bp3 lint` fails |

## Acceptance test (goal block)

- **Objective:** bp3's checks run as data-driven rules
  with structured findings, gating the build.
- **Prove by:** the three seeded-violation fixtures +
  clean-tree run; `make check` red on a seeded violation,
  green clean.
- **Done when:** `bp3 lint` ships with both packs, all
  cases pass, and Makefile check logic delegates to it
  where a rule exists.

## Context

From the same landing red chair as Exp 1–2: per-language
"best practices" prose duplicates what tools enforce and
rots in skill files, eating context every Run. The
machine-checkable 80% belongs in an owned engine; the
judgment residue stays in role skills (code-writer's OCaml
reference is one page, deliberately). SonarQube is the
shape — rule registry, severities, structured findings —
at bp3 scale: one binary, files-in-git, no server.

## Tests

unit: classification + rule matching + severity gate join Exp 2's suite · fixtures: seed a violation in a scratch tree, expect the exact finding + exit 1; clean tree expects `ok` · demos: Demo trace above, observed at landing
