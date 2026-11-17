---
date: 2026-11-16
goal: ../GRAPH.md
exp: config.1
status: proposed
---

# config.1 - bp3-config: the machine-local context store

## TL;DR

Name and build the hard store as a bp3 config:
`<git-common-dir>/bp3/` holding `config.json`
(machine settings only: local timing thresholds
and gates), the per-run configs (`runs/<run_id>.json`,
created at link mint), the derived by-session
index, and the existing run-lifecycle derivations. Written only
by bp3 verbs (link mint/claim, desk prepare,
record-init) — never hand-edited, never
committed. `bp3 config` door views it. This is
the substrate mvp.1/mvp.2 resolve context from.

## Demo (design trace)

```text
bp3 config            -> {thresholds: {setup_slow_s: 180}, contexts: []}   # contexts folded from runs/
bp3 harness link mint … ; child claims
bp3 config            -> {contexts: [{graph, node, edge, run_id, session_id, desk}], …}  # view of runs/*.json
bp3 config --source   -> per-context: written by which verb, when
```

## Diagram

```text
verbs (link/desk/record-init) ──write──► <git-common-dir>/bp3/
                                           config.json (machine settings only)
                                           runs/<run_id>.json  by-session/ (derived)
                                           run-lifecycle-derivations/
callers ──read (inference ladder)────────► same tree
```

## Pseudocode

```python
def config_dir():
    return git_common_dir() / "bp3"          # inferred like git finds .git

def ensure_config():
    if not exists(config_dir()): create with defaults   # first write sets up
    return load("config.json")

def view(source=False):
    return contexts + desks + thresholds (+ provenance if source)
```

| Field | Value |
|---|---|
| Intent | one named, viewable home for all machine-local bp3 state |
| Lane | standard |
| Output | `bp3 config` view door; config tree layout; provenance per context |
| Depends on | none; mvp.1 and mvp.2 build on it |

## Acceptance

| Case | Expected |
|---|---|
| zero setup | first bp3 write on a fresh repo creates the config tree with defaults; no manual step |
| viewable | `bp3 config` prints thresholds plus contexts folded from run configs; `--source` names the writing verb + ts per context; deleting `by-session/` loses nothing (rebuilt from `runs/`) |
| local only | nothing under the config tree is committable (git status of the repo stays clean of it; tree lives in git-common-dir) |
| thresholds local | timing gates (setup_slow_s etc.) editable locally, honored by verdicts, never required by committed files |
| survives worktrees | all worktrees of the repo resolve the same config tree (common-dir), while contexts stay per-session |
| derivations folded in | existing run-lifecycle-derivations keep working at their current path under the tree |

## Acceptance test (goal block)

- **Objective:** a fresh clone needs zero setup
  and a human can always see what bp3 thinks the
  context is.
- **Prove by:** fresh-repo fixture: first write,
  view, claim, view again; provenance shown.
- **Done when:** config appears on first write
  and every context names its writer, observed.

## Tests

Known cases: fresh tree creation, view shapes,
per-session contexts coexisting, worktree-shared
tree. Property-based: no verb writes config
outside the common-dir tree; config never
required for read-only legacy calls (fails open
to today's behavior + warning).

## Context

The store grew organically (derivations in the
supervisor graph; claims designed in mvp.1).
Naming it config — and giving it a view door —
makes inference debuggable: when context
resolution surprises, `bp3 config --source`
says why. Setup is a non-event by design;
kubectl's hand-carried kubeconfig is the
anti-pattern this avoids.
