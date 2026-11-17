---
date: 2026-11-14
goal: ../../GOAL.md
exp: 2
status: proposed
---

# Exp 2 — Tab completion for `bp3`

## TL;DR

`bp3` gains completion scripts — `completions/_bp3` (zsh,
required) and `completions/bp3.bash` (bash, if cheap: same
candidate logic; deferred only with a recorded reason here).
Static candidates come from the CLI grammar (door verbs,
edges, flags); dynamic candidates are quest names, then the
typed quest's exp names, from a fast `bp3 q` read.
Completion never completes commit SHAs or run-ids, never
folds a ledger beyond the read itself, and fails silently
(unbuilt binary, non-bp3 cwd, any error → no candidates, no
noise). `bp3 init` / `bp3 skills install` deliver the zsh
script; neither ever edits a shell rc file.

## Demo (design trace)

```text
$ bp3 q 2026-<TAB>            ->  2026-11-07-bp3-mvp-engine-core  2026-11-14-bp3-cli-small-fixes  toy-drive
$ bp3 q toy-drive r <TAB>     ->  blocked-demo  identity-check  parser-fix  skill-check
$ bp3 q toy-drive u parser-fix <TAB> ->  submit review check land block resume
$ bp3 q toy-drive r parser-fix --f<TAB> ->  --format
$ cd /tmp && bp3 q <TAB>      ->  (nothing; no error, no candidates)
```

## Diagram

```text
keystroke ─► completion script ─► position?
                                   ├─ verb slot ──────► static: c r u d / create read update delete
                                   ├─ quest slot ─────► dynamic: bp3 q r            (jq names, else silent)
                                   ├─ exp slot ───────► dynamic: bp3 q <quest> r  (same)
                                   ├─ edge slot ──────► static: submit review check land block resume
                                   └─ flag slot ──────► static: --format --reason --commit --verdict --target --type --depends-on
                                 any failure ─► empty candidates, exit silent
```

## Pseudocode

```python
def candidates(words, cur):
    try:
        match slot(words):
            case "quest": return jq_names(run(["bp3", "q", "r"]), ".quests[].quest")
            case "exp":   return jq_names(run(["bp3", "q", words.quest, "r"]), ".exps[].exp")
            case "edge":  return EDGES
            case "flag":  return FLAGS
            case _:       return VERBS
    except AnyError:
        return []          # silent: unbuilt binary, wrong cwd, no jq
```

## Tables

| Field | Value |
|---|---|
| Intent | no quest/exp slug is ever typed from memory again |
| Lane | standard |
| Output | `completions/_bp3`, `completions/bp3.bash` (if cheap), delivery wiring in `bin/bp3` (`skills_install`), a completion fixture |
| Acceptance | cases below; all fail today (no completion exists) |
| Depends on | none; if delivery edits `bin/bp3` collide with Exp 1 work, Exp 1 lands first |

| Case | Expected after |
|---|---|
| zsh: quest/exp/edge/flag slots | candidates as traced, sourced from the live grammar (verbs/edges/flags match `src/quest/main.ml` exactly) |
| unbuilt binary or non-bp3 cwd | no candidates, no stderr noise, shell unaffected |
| slow read | candidates from the one `bp3 q r` read only; no per-keystroke ledger fold beyond it |
| bash | same traces pass, **or** this record gains a dated deferral reason and bash leaves scope |
| delivery | fresh `bp3 init` in a scratch repo leaves `_bp3` where zsh finds it (or prints the one `source` line to add); no rc file modified |

## Acceptance test (goal block)

- **Objective:** a zsh user completes quest names, exp
  names, edges, and flags; everywhere else completion is
  silently absent.
- **Prove by:** scripted completion invocations (zsh
  `compadd` harness or `zsh -i` capture) for the four
  traced slots; the `/tmp` silent-failure case; fresh-repo
  `bp3 init` delivery check; `make check` green.
- **Done when:** all traces produce the traced candidates,
  the failure case produces nothing and says nothing, and
  a fixture pins the static lists against `main.ml`.

## Prose

Context: second papercut from the same MVP-landing sitting
(GOAL.md). Grammar source of truth is `src/quest/main.ml`:
door verbs `c|r|u|d` (+ long forms), edges `submit review
check land block resume`, flags as listed — the fixture
asserts the scripts against those spellings so the two
cannot drift silently. Latency bound is the icebox's own:
`bp3 q r` spawns the OCaml binary and reads refs (~tens of
ms); acceptable per keystroke, and the silent-failure rule
means a slow or broken read degrades to no completion,
never to a hung shell. Dynamic data goes through `jq` when
present and degrades silently when not — no new hard
dependency for an optional surface. Delivery follows the
existing `bp3 init` render pattern (copy + notice); where
zsh looks (`$fpath`) varies per user, so install copies
into an existing completions dir when one is found and
otherwise prints the path — deciding the user's shell
config for them is out.

## Tests

unit: none (shell scripts; no seam) · fixtures: static-list
assertion vs `main.ml` spellings, scripted candidate
traces, silent-failure case · demos: the traces above in a
real zsh at review
