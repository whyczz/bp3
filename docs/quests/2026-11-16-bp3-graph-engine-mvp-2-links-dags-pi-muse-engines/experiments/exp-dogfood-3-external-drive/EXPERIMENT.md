---
date: 2026-11-17
quest: ../QUEST.md
exp: dogfood.3
status: proposed
---

# dogfood.3 - external-drive: bp3 as a tool in a repo that is not bp3

## TL;DR

Owner idea, red-chaired and rebuilt (2026-11-17):
bp3 runs in two modes. **self**: bp3 is the
product (this repo; `bin/bp3` rides the branch).
**host**: bp3 is a tool (esc3, any git repo; one
installed binary). The mode is **derived** from
the repo, never passed as a flag — flags lie,
derivation cannot. Mode selects the skill set at
install (core conduct skills everywhere, bp3-dev
overlay only in self) and the read strategy
(deskNote only in self; host reads call `bp3` on
PATH). Dogfood: a full conduct in a fixture repo
with no bp3 source, landed end to end.

## Demo (design trace)

```text
fixture repo (git, tiny test cmd, zero bp3 source)
  bp3 skills install ─► core skills only (no bp3-dev leak)
  mode derives "host" ─► reads call bp3 on PATH, no $DESK/bin/bp3
  graph create ─► node-loop ─► grade ─► land ─► node_fin
this repo: mode derives "self", conduct unchanged
```

## Diagram

```text
repo ──derive──► self ─► install: core + bp3-dev overlay ─► reads: $DESK/bin/bp3 (deskNote)
              └► host ─► install: core only ──────────────► reads: bp3 on PATH (no deskNote)
mode recorded per Run (record-init) — evidence, never an input flag
```

## Pseudocode

```python
def repo_mode(repo):
    return "self" if tracked(repo, "src/quest") and tracked(repo, "bin/bp3") else "host"

def skills_install(repo, harness):
    render(core_conduct_skills, harness)                 # one source, both modes
    if repo_mode(repo) == "self": render(bp3_dev_skills, harness)  # additive only

def read_strategy(repo):
    return "$DESK/bin/bp3" if repo_mode(repo) == "self" else "bp3"  # PATH
```

| Field | Value |
|---|---|
| Intent | one engine, two habitats; the habitat is read from the repo, not remembered by callers |
| Lane | standard |
| Output | derived mode + mode-aware install/reads + external fixture conduct |
| Depends on | followup.3 (goal vocabulary first, per owner sequencing) |

## Acceptance

| Case | Expected |
|---|---|
| mode derives host | in the fixture repo, mode = `host` with no flag passed anywhere |
| mode derives self | in this repo, mode = `self`; existing conduct (reads, lands) unchanged |
| no flag surface | no `--mode` (or equivalent) accepted on harness/install verbs; passing one is a usage error naming derivation |
| skill sets | fixture render contains core conduct skills and zero bp3-dev skills (grep); self render contains both |
| mode-aware reads | host conduct tapes show zero `$DESK/bin/bp3` invocations; a self conduct shows zero bare-`bp3` state reads |
| full external conduct | fixture graph node travels todo → landed in the fixture repo; its test command green; zero bp3-source files added to the fixture tree |
| mode recorded | fixture Run's record-init record carries `mode: host`; a self Run carries `mode: self` |
| regression | `make check` green; per-mode fixtures in the workflow tests |

## Acceptance test (goal block)

- **Objective:** bp3 conducts a goal in a repo
  that contains no bp3 source, in host mode,
  derived not flagged.
- **Prove by:** the fixture conduct (state reads
  quoted) + skill-set greps + Run records.
- **Done when:** fixture node is landed and this
  repo's self conduct is provably unchanged.

## Tests

`make check`; new mode/install fixtures; the
live fixture conduct is itself the integration
test (not mocks — followup.2's blocked row is
the lesson).

## Context

Known blocker this node must face head-on:
skills source currently travels with the bp3
repo (`bin/bp3` reads `$root/skills`). The
fixture drive forces the packaging answer
(bundled skills or an explicit skills source
for the installed tool). Owner corollary:
"we don't need the deskNote if bp3 is a tool
(external) versus bp3 is the product (internal)"
— deskNote becomes self-mode machinery only.
