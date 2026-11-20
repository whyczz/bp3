---
status: proposed
home_repo: bp3
date: 2026-11-19
---

# constraints-context: what bp3 may be built from, and how others build it

TL;DR
Two root files that every plan and grade reads. CONSTRAINTS.md is
the owner-signed stack: languages, the libraries inside each, and
surfaces; a tiny lint in `make lint` turns anything unlisted red.
CONTEXT.md is common-sense ground: how solo devs, star devs,
startups and labs build agent harnesses, plus the pre-LLM engineering
canon filtered for agents, every claim sourced and dated. `/quest`,
red-ink and the induct-inline grader check against both.

ELI5
We kept making odd choices because nothing written said what we use
and nothing told us how everyone else does it. Now one file lists our
tools, a check complains the moment something new sneaks in, and
another file collects what other builders learned, so a plan can ask
"how would they do this, and why are we different?"

## Context

Promoted from `docs/icebox/2026-11-19-constraints-and-context.md`
(owner named it 2026-11-19: "let's focus on the CONTEXT.md and
CONTRAINTS.md icebox and make that the quest"), copied verbatim to
[ICEBOX.md](ICEBOX.md). The fast-grader quest is on hold
(`docs/quests/2026-11-19-fast-grader/`); its 2026-11-19 review-loop
fact-check feeds CONTEXT.md here.

Owner decisions, 2026-11-19:

| Question | Call |
|---|---|
| where the files live | repo root, linked from CLAUDE.md and AGENTS.md |
| enforcement | a tiny lint in `make check` |
| tools like jq, sed, awk, yq | "they are tools, call them libraries, e.g. we pick langs, but also libraries within the lang" |
| refresh | a claim older than 90 days is re-checked before it is cited |
| research scope | solo, star dev, startup, VC-backed; GitHub, HN, X, lobste.rs; "a report and re-doable search terms" |
| research questions | orchestration, storage, scaling, human-LLM interaction, learning and org scale (voice memo), plus the engineering canon "with some sort of filter" |
| named peers | Kun Chen's firstmate and Lavish (`kunchenguid/firstmate`, `kunchenguid/lavish-axi`), Edbert Chan's Invoker (`Neko-Catpital-Labs/Invoker`): "do a pass and go over that spec" |

Owner decisions at approval, 2026-11-20:

| Question | Call |
|---|---|
| approval | "Approve as-is": the quest governs build and the constraints block below is signed |
| grade path | the owner grades rules.1 and ctx.1 by reading the file; a fresh grader subagent grades rules.2 and read.1 |
| style guide | iceboxed: `docs/icebox/2026-11-20-style-guide.md` |
| icebox entry | promoted, then deleted: "Yes, delete" |

Owner decisions during build, 2026-11-20 (the census below was wrong
about perl and python; see the correction):

| Question | Call |
|---|---|
| python3 pty driver in `test/run-suites.sh` | "Rewrite without a pty": SIGINT and SIGQUIT go to the runner's process group, as a terminal sends them |
| 12 perl one-liners in 11 test files | "Replace with sed" |
| `scripts/migrate-quest-rename.sh` (done migration, perl) | "Delete it": the check-tiers fossil case moves to `scripts/migrate-graph-rename.sh` |
| where the purge lives | its own node, rules.3 stack-purge (follow-up); rules.2 depends on it, so the lint lands on a clean repo |

Census on master, 2026-11-19 (`git ls-files`, shebangs, imports):

- **Languages in code:** OCaml (23 `.ml`), bash (37 `.sh`, 1 `.bash`,
  shebang scripts), node (9 `.mjs`, 8 `.js`, 4 `.ts`, 2 node
  shebangs), and zsh (`completions/_bp3`).
- **No perl or python.** The test-pyramid deletion and the OCaml
  runner removed them. **Wrong** (corrected 2026-11-20, while building
  rules.2): perl runs in 11 test files (12 lines) and in
  `scripts/migrate-quest-rename.sh`, and `test/run-suites.sh` runs a
  python3 pty driver. The census grep failed on `\b` and missed
  interpreters after a `VAR=value` prefix. rules.3 removes them.
- **OCaml libraries:** yojson, unix, str, plus ounit2, qcheck-core and
  qcheck-ounit for tests.
- **Node:** builtins only, and type imports from
  `@earendil-works/pi-coding-agent`. `package.json` has no deps.
- **Brewfile:** yq, jq, yamllint, shellcheck.

## Terms

- **CONSTRAINTS.md**: root file; the owner-signed list of languages,
  each language's libraries, and surfaces, plus how to change them and
  a sign-off log.
- **constraints block**: the fenced ` ```constraints ` block in
  CONSTRAINTS.md; one `lang` line per language and one `data` line;
  the only copy of the list.
- **library**: anything a language pulls in: an OCaml library, a node
  import, a tool a bash script shells out to.
- **surface**: what bp3 ships for people to use: the CLI, skills,
  harness extensions.
- **sign-off row**: a dated line in the sign-off log quoting the
  owner's words; the only way a constraint changes.
- **CONTEXT.md**: root file; sourced, dated claims on how others build
  agent systems, by question, plus bp3's own lessons.
- **dossier**: `docs/dossiers/agent-harness-landscape.md`, the long
  research record behind CONTEXT.md, with a Re-run section of saved
  searches.
- **constraints pass**: red-chair step: does the plan add a language,
  library or surface outside CONSTRAINTS.md?
- **common-sense pass**: red-chair step: how would another team build
  this (from CONTEXT.md), and why are we different?
- **filter** (canon): keep a pre-LLM principle when the human
  constraint behind it still binds (transfers), flag it when the
  constraint is gone (inverts), stress it when agents make it worse
  (amplifies).

## Inputs

| Input | Source |
|---|---|
| tracked files | `git ls-files`, minus `docs/**` and `*.md` |
| the constraints block | CONSTRAINTS.md |
| declared libraries | dune `(libraries ...)`, node imports and `package.json`, Brewfile |
| research | the dossier and its saved searches |
| plans and commits under review | `/quest`, red-ink, the induct-inline grader |

## Outputs

| Output | Shape |
|---|---|
| CONSTRAINTS.md | sections Languages (the block), Surfaces, How to change, Sign-off log |
| check-constraints | `check-constraints: ok (<n> languages, <m> files)` exit 0; `FAIL <file>[:<line>]: <what> not in CONSTRAINTS.md` exit 1; no block exit 2 |
| CONTEXT.md | sections Q1-Q6, Review loops, bp3 lessons; one claim per line, link plus checked date |
| skill text | constraints pass and common-sense pass in quest and red-ink; owner-class rule in induct-inline |

## Acceptance gates (design trace)

```text
rules.1  CONSTRAINTS.md lands; owner's approval of this quest is its first sign-off row
rules.2  make lint -> check-constraints: ok (4 languages, 118 files)
         plant `perl -e` in a test -> FAIL test/x.sh:3: interpreter perl not in CONSTRAINTS.md
ctx.1    CONTEXT.md lands; every claim line has a link and a date (two greps agree)
read.1   /quest on a plan adding sqlite3 -> constraints pass: owner sign-off owed
         grader on a commit importing "zod" -> needs_fix, owner class; yolo parks it
```

Each step is proved by its node's goal block.

## Goal and why

Stop strange decisions at the cheapest point. tier.1's bash-plus-perl
runner cost six grading rounds before the owner asked "why can't we
use ocaml for this?"; a lint would have flagged the first perl line in
seconds, and a common-sense pass would have asked how other runners
handle signals. Owner: "we're making strange decisions".

## Success picture

- Adding an unlisted language, interpreter or library turns `make
  lint` red, naming the file.
- CONTEXT.md answers the six questions with sourced, dated claims,
  and the owner finds it useful at ctx.1's land.
- The next `/quest` after this one records a constraints pass and a
  common-sense pass in its red chair.

## Scope

| In | Out |
|---|---|
| CONSTRAINTS.md, CONTEXT.md, links from CLAUDE.md and AGENTS.md | a rule engine (`docs/icebox/2026-11-15-bp3-lint.md` stays frozen) |
| `scripts/check-constraints`, its fixture test, the lint step and check-gates pin | catching bash tools not in the Brewfile (guesswork; grader's job) |
| quest, red-ink, induct-inline skill text | the yap `red-chair` skill (another repo); the `induct` workflow grader |
| the dossier, written during framing | a style guide (iceboxed: `docs/icebox/2026-11-20-style-guide.md`) |

## Constraints at approval

Signed by the owner's approval of this quest (2026-11-20: "Approve
as-is"); rules.1 transcribes them and quotes the approval in the
sign-off log.

```constraints
lang ocaml  ext .ml .mli  files dune dune-project    libs stdlib unix str yojson ounit2 qcheck-core qcheck-ounit
lang bash   ext .sh .bash  shebang bash sh           libs git jq yq sed awk find mktemp make gh shellcheck yamllint
lang zsh    files completions/_bp3                    libs (completion builtins only)
lang node   ext .mjs .js .ts  shebang node           libs node:* @earendil-works/pi-coding-agent
data        ext .md .json .jsonl .yaml .tsv .txt .mmd .conf  files Makefile Brewfile .gitignore
```

| Surface | Allowed |
|---|---|
| bp3 CLI | `bin/bp3`, the `bp3 q` door, `bp3 harness` |
| skills | markdown, rendered per harness (`.claude`, `.pi`, `.agents`) |
| harness extensions | the pi extension (`extensions/bp3-pi`), workflow scripts |
| not without a quest and sign-off | web app, daemon or service, GUI, hosted database |

## Human touchpoints

- Approve this file. That signs the constraints above. Done
  2026-11-20.
- Grade rules.1 by reading CONSTRAINTS.md, and ctx.1 by reading
  CONTEXT.md and judging its usefulness. The conductor stops at
  `handed_off` for both and casts the owner's verdict. rules.2 and
  read.1 get a fresh grader subagent.
- Any later addition: a `/teach` pitch, then the owner's words in a
  sign-off row.
- Promote at the end (`goal_fin`).

## Nodes

### Milestone: rules

| Node | TL;DR |
|---|---|
| [rules.1 - constraints-file](nodes/node-rules-1-constraints-file/NODE.md) | CONSTRAINTS.md: the signed stack, one block, a sign-off log |
| [rules.2 - constraints-lint](nodes/node-rules-2-constraints-lint/NODE.md) | `scripts/check-constraints` in `make lint`: unlisted language, interpreter or library is red |
| [rules.3 - stack-purge (follow-up)](nodes/node-rules-3-stack-purge/NODE.md) | remove the perl and python the census missed, so rules.2 lands green: sed for perl, the Ctrl-C probe without a pty, the done migration deleted |

### Milestone: ctx

| Node | TL;DR |
|---|---|
| [ctx.1 - context-file](nodes/node-ctx-1-context-file/NODE.md) | CONTEXT.md: six questions plus review loops, sourced and dated, from the dossier |

### Milestone: read

| Node | TL;DR |
|---|---|
| [read.1 - readers](nodes/node-read-1-readers/NODE.md) | quest, red-ink and induct-inline check against both files; CLAUDE.md and AGENTS.md link them |

## Scorecard

| Row | Target | Read from |
|---|---|---|
| lint cost | check-constraints under 2s | rules.2 goal block |
| false positives | 0 on this repo at land | `make lint` |
| CONTEXT.md claims | every line linked and dated | ctx.1 greps |
| readers | next quest records both passes | its QUEST.md red chair |

## Risks and red chair

Strongest attack (step 7): **the lint becomes the next gate that
cries wolf.** A word like "python" in a comment, or a data file with
an odd extension, would fail `make check` and train everyone to edit
the allowlist to get green, which is the opposite of sign-off.
Changed: interpreters count only in command position with comments
skipped, and every unknown extension must land in a `lang` or `data`
line, both pinned as planted cases in rules.2. An agent editing the
block to pass is caught by read.1's grader rule (a CONSTRAINTS.md diff
needs an owner-words row), and by the owner at promotion.

Other attacks, and what each changed:

| Attack | Severity | Outcome |
|---|---|---|
| a human table and the block drift apart | major | settled: the block is the only copy of the list (rules.1) |
| CONTEXT.md grows into a wiki nobody reads | major | settled: claims only when seen twice or first-party, one line each; the dossier holds the rest (ctx.1) |
| zsh in `completions/_bp3` breaks "three languages" | minor | settled: grandfathered as its own line |
| an agent forges owner words in a sign-off row | minor | open: no identity in git; the owner reads CONSTRAINTS.md diffs at promotion |
| a bash script calls an unlisted tool | minor | open, stated as a gap in rules.2 |

Red chair of the source (step 7.5):
- **What the entry assumed.** It assumed prose rules would do, and
  that the lint was optional. Re-decided: the lint is in, by owner
  call.
- **Its blockers, now settled:**
  - location: root, linked
  - what counts as a language: languages contain libraries; tools are bash's libraries
  - existing violations: zsh is grandfathered; perl and python were
    thought gone but were not (2026-11-20), so rules.3 removes them
  - lint overlap: one tiny script, not the rule engine
  - research: dossier plus saved searches
  - yolo overlap: never mechanical, always the owner
- **The boring alternative** is to just ask the owner earlier in
  every plan. That fails silently whenever nobody thinks to ask, which
  is exactly what happened with perl.

## Open questions

None open. Settled at approval, 2026-11-20:

1. Grade path: the owner grades rules.1 and ctx.1; a grader grades
   rules.2 and read.1 (Human touchpoints).
2. Style guide: out of this quest, iceboxed as
   `docs/icebox/2026-11-20-style-guide.md`.
3. Trigger: the test-pyramid ledger is not formally landed (tier.2
   handed_off; tier.3 and retire.1 todo), though master has its code
   (7313084). The entry's trigger ("the test-pyramid quest lands") is
   taken as fired: the owner named the entry and approved this quest.

## Node diagram

```text
rules.1 constraints-file ──┐
rules.3 stack-purge ───────┴──► rules.2 constraints-lint ──┐
dossier (framing) ──► ctx.1 context-file ──────────────────┼──► read.1 readers
                     (rules.* and ctx.1 share no files; run alongside)
```
