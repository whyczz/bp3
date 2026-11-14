---
date: 2026-11-14
quest: ../../QUEST.md
exp: 4
status: proposed
---

# Exp 4 — `-h` / `--help` for bp3 commands

## TL;DR

Every door gains a help path: `bp3 -h`, `bp3 q -h`,
`bp3 q c|r|d -h`, `bp3 q <quest> -h`, and
`bp3 q <quest> c|r|u|d -h` (both `-h` and `--help`, identical)
print plain-text help for that door to stdout and exit 0.
Help text is hand-written strings living next to dispatch
in `src/quest/main.ml` (plus the wrapper line in
`bin/bp3`), guarded by a fixture asserting every door verb,
edge, and flag spelling in the help matches the grammar in
`main.ml` — the same anti-drift guard Exp 2 uses for
completion. Error paths do not change: a malformed command
still returns the JSON `E_USAGE` verdict; help is only the
success path a human asked for.

Added at framing, 2026-11-14, on the owner's ask.

## Demo (design trace)

```text
$ bp3 -h
usage: bp3 init [...] | bp3 skills install [...] | bp3 q|quest ... | bp3 worktree ...
  bp3 q -h    quest/exp state commands

$ bp3 q -h
bp3 q — quest/exp state. Doors:
  bp3 q c|r|d ...                 quest door (create, read, delete)
  bp3 q <quest> c|r|u|d ...       exp door for one quest
  bp3 q icebox r [term...]        search frozen icebox entries
  bp3 q hooks                     harness hook emitter (fail-open)
Run bp3 q <door> -h for that door's verbs, edges, and flags.

$ bp3 q 2026-11-14-bp3-cli-small-fixes u -h
bp3 q <quest> u <exp> <edge> [--reason ...] [--commit ...] [--verdict ...]  (review: ship|needs_fix; check: pass|fail)
edges: submit review check land block resume

$ ./bin/bp3 q -h; echo exit:$?    ->  exit:0
```

Today (observed): `./bin/bp3 q -h` exits 2 with a JSON
`E_USAGE` verdict; `./bin/bp3 q r --help` parses `--help` as
a quest name (`E_NOT_FOUND quest "--help"`); `./bin/bp3
--help` prints the wrapper usage to stderr, exit 2.

## Diagram

```text
argv ─► help token in a help slot? ── yes ─► print door help ─► exit 0
              │ no
              └─► existing dispatch (unchanged; errors stay JSON E_USAGE)

help slots: after `bp3`, after `q`, after a door verb, after <quest>,
            after <quest> + door verb. Anywhere else: not a help slot.
```

## Pseudocode

```python
HELP = { "q": "...", "quest_door": "...", "exp_door": "...", "top": "..." }

def run(argv):
    if argv[:1] in (["-h"], ["--help"]):            return print_exit(HELP["q"], 0)
    quest, door = split_doors(argv)                  # existing grammar walk
    if door.rest[:1] in (["-h"], ["--help"]):
        return print_exit(HELP[door.kind], 0)
    return dispatch(argv)                            # untouched
```

Wrapper (`bin/bp3`): first arg `-h|--help` prints
`usage_text` to stdout, exit 0, before the case dispatch.

## Tables

| Field | Value |
|---|---|
| Intent | a human at any door can ask what the door does without reading `main.ml` or eating a JSON error |
| Lane | standard |
| Output | help strings + interception in `src/quest/main.ml`; wrapper case in `bin/bp3`; fixture cases in `test/q.sh` |
| Acceptance | cases below; all fail today (observed above) |
| Depends on | none (Exp 2 reuses its static-list guard; sequence either way) |

| Case | Expected after |
|---|---|
| `bp3 -h`, `bp3 --help` | wrapper usage on stdout, exit 0 |
| `bp3 q -h`, `bp3 q --help` | q-door help: both doors, `icebox`, `hooks`, pointer to per-door `-h`; exit 0 |
| `bp3 q c -h` / `r -h` / `d -h` | quest-door help naming verbs and their flags (`--type`, `--depends-on`, `--format`, `--reason`); exit 0 |
| `bp3 q <quest> -h` | exp-door help for that quest shape; exit 0 (quest need not exist — help is grammar, not state) |
| `bp3 q <quest> u -h` | update help: edges `submit review check land block resume`, required flags per edge; exit 0 |
| `-h` outside a help slot (e.g. after a flag value position) | treated as today: stray/unknown, JSON error — no new magic positions |
| help text vs grammar | fixture asserts every verb/edge/flag spelling in help appears in `main.ml`'s grammar and vice versa |
| non-help commands | byte-identical verdicts to today, JSON and exit codes unchanged |

## Acceptance test (goal block)

- **Objective:** `-h`/`--help` prints door help, exit 0, at
  every door; nothing else about the CLI moves.
- **Prove by:** the traced invocations at each door against
  the real binary; exit-code checks; a grammar-drift fixture
  (rename an edge in a scratch copy → fixture red);
  regression diff of representative non-help verdicts;
  `make check` green.
- **Done when:** every help case prints and exits 0, the
  drift fixture can fail, and the non-help diff is empty.

## Prose

Context: the third human-surface gap found while framing
this quest — the first two were the table that wasn't and
the completion that wasn't. Why help is plain text, not a
JSON verdict: verdicts are the LLM surface, and an LLM
never needs `-h` — it reads `legal_edges` from the read
verdict. Making help a verdict would force humans to parse
JSON to learn the human surface, the exact papercut this
quest exists to remove. Why hand-written strings instead
of deriving from the parser: the parser's knowledge is
scattered across `parse_flags` matches and dispatch arms;
a derived rendering is a refactor of the grammar, which is
Exp-sized on its own. Strings + the drift fixture get the
same honesty at a fraction of the blast radius — and Exp 2
already pays for the identical guard for completion, so
the two fixtures can share one spelling list. Edge case:
help must work with no quest, no repo state, and an
unbuilt-otherwise context wherever the binary itself runs;
it reads nothing.

## Tests

unit: none (strings + interception; no seam) · fixtures:
per-door help invocations with exit-0 and key-spelling
assertions, grammar-drift guard, non-help regression diff
in the q fixture suite · demos: the traces above, run by
hand at review
