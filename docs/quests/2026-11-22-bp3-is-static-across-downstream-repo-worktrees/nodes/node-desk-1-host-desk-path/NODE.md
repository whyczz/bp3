---
date: 2026-11-22
quest: ../../QUEST.md
node: desk.1
status: proposed
---

# desk.1 - host-desk-path: host desks live beside the repo

## TL;DR

In a host repo, `bp3 harness desk prepare` puts the desk at
`../<repo>.desks/<run_id>` by default, outside the repo tree, so tools
that find their project root by walking up (dune; predictor's
pre-commit through it) see the desk instead of the outer checkout.
Self desks stay at `.bp3/worktrees/<run_id>`, and `--path` still wins.
Prepare refuses `E_DESK_NOT_IGNORED` when `.bp3/` (the desk registry)
isn't gitignored. The Claude Code render adds
`permissions.additionalDirectories: ["../<repo>.desks"]` to
`.claude/settings.json`, merged like the hooks.

## Acceptance gates

Observed today (scratch clone of predictor, installed bp3):

```text
$ bp3 harness desk prepare --quest 2026-11-22-predictor-conventions-naming
{"ok":true,...,"path":".bp3/worktrees/2026-11-22-predictor-conventions-naming",...}
$ cd .bp3/worktrees/2026-11-22-predictor-conventions-naming && dune build
Entering directory '<clone root>'
Error: No rule found for alias .bp3/worktrees/2026-11-22-predictor-conventions-naming/default
$ dune build --root .                # 138 s cold, 0 s warm: the desk builds only when pinned
```

Design trace:

```text
(host fixture repo r/ with dune-project, a tiny lib, .bp3/ in .gitignore)
$ bp3 harness desk prepare --quest q
{"ok":true,...,"path":"../r.desks/quest-q",...}
$ cd ../r.desks/quest-q && findroot      # fixture tool: prints the outermost dir holding a dune-project, like dune
<abs>/r.desks/quest-q
$ git -C r status --short                                 # empty
$ bp3 q r q   (from r/ and from the desk)                 # the same rollup
$ bp3 harness desk release --quest q                      # removed; r.desks/ kept
(.bp3/ not ignored)
$ bp3 harness desk prepare --quest q
{"ok":false,"error":{"code":"E_DESK_NOT_IGNORED","facts":{"path":".bp3/"},"guidance":"Add .bp3/ to .gitignore, commit, and prepare again."}}
$ git worktree list                                        # no new worktree
(bp3 repo, self mode: test/g.sh)                           # .bp3/worktrees/... unchanged
$ jq .permissions.additionalDirectories r/.claude/settings.json    # after bp3 skills install in r/
["../r.desks"]
```

```yaml
objective: a host desk is a checkout whose upward root search ends at the desk, and preparing one never dirties the root
prove by:
  - test/g.sh (or a new host block): host fixture; default path ../<repo>.desks/<run_id> for --quest and for a grade desk
    (--run grade-n-c1-a1 --commit <sha>); --path still wins; an upward search for dune-project from the desk stops at the desk;
    root status empty after prepare and release; the rollup from root == from desk
  - E_DESK_NOT_IGNORED when .bp3/ is not ignored, with git worktree list unchanged
  - self mode: the existing g.sh desk cases pass unchanged (.bp3/worktrees/)
  - test/skills.sh: host render merges permissions.additionalDirectories ["../<repo>.desks"], keeps other settings keys,
    is idempotent; the self render has no such key
  - make check-full
done when: each case holds and the path, refusal and settings cases fail on master
```

## Diagram

```text
~/m/predictor/            (dune-project, _opam/, .bp3/desks/*.json  registry, ignored)
~/m/predictor.desks/
   quest-<q>/              (worktree on quest/<q>; dune's root search stops here)
   grade-<n>-c1-a1/        (detached at the bound commit)
refs/heads/bp3/*           shared by all three checkouts → one quest state
```

## Pseudocode

```python
def default_desk_path(root, run_id, mode):
    if mode == "self":
        return root / ".bp3/worktrees" / run_id            # unchanged
    return root.parent / f"{root.name}.desks" / run_id

def prepare(quest, node, run_id, commit, path_override):
    if not git_check_ignore(root, ".bp3/"):
        refuse("E_DESK_NOT_IGNORED", path=".bp3/")
    path = path_override or default_desk_path(root, run_id, repo_mode(root))
    git_worktree_add(path, ...)                            # as today
    record(root / ".bp3/desks" / f"{run_id}.json", path=path)   # registry stays in the repo
```

## Tables

| Field | Value |
|---|---|
| Intent | downstream repos get desks their own tools can build in |
| Lane | standard |
| Output | `src/quest/worktree.ml` (default path by mode, ignore check), `src/quest/names.ml` (`e_desk_not_ignored`), `bin/bp3` (settings merge), `test/g.sh`, `test/skills.sh` |
| Acceptance | the trace above; fails today (nested path, no refusal, no setting) |
| Depends on | none |

| Mode | Default desk path | Why |
|---|---|---|
| self (bp3) | `.bp3/worktrees/<run_id>` | bp3's Makefile pins `--root=.` there; tests and history use it |
| host | `../<repo>.desks/<run_id>` | the downstream repo's tools guess their root by walking up |
| either, `--path` | as given | unchanged |

## Prose

A nested desk is a checkout inside a checkout. Every tool that finds its
project by walking up — dune (outermost `dune-project`), opam (`_opam`),
and anything that calls them, like predictor's pre-commit — finds the
outer one first. bp3 hides this for itself with one Makefile rule
(`--root=.` when the path contains `/.bp3/worktrees/`). Predictor has no
Makefile, and the next downstream repo won't either. Moving the desk out
of the tree fixes all of those tools at once.

The cost is the agent sandbox: a Claude Code session started in the repo
treats `../<repo>.desks/` as outside its working directory. The render
lists it in `permissions.additionalDirectories`; whether that is enough
for edits without a prompt is QUEST Open question 2, probed live in
dogfood.1. The other cost: opam's `_opam` lookup no longer finds the
repo's switch from the desk (QUEST finding 7). Agents don't need it
(`dune` comes from the default switch, the compiler from `dune.lock`),
and a repo whose hooks do can find it through `git rev-parse
--git-common-dir`.

The registry stays at `.bp3/desks/` inside the repo, so `desk list`,
`release` and the orphan sweep keep working unchanged. That is why `.bp3/`
must be ignored: an unignored `.bp3/` shows up as untracked in the root,
and a careless `git add -A` there would add the registry. Predictor
already ignores it; the refusal makes the rule explicit for the next
repo.

Self mode keeps its path. Moving it would touch g.sh's fixtures, the
Makefile rule and every desk path in history for no gain bp3 can measure
today (QUEST Open question 1).

Edges: `../<repo>.desks` not writable → `git worktree add` fails and
prepare refuses with its existing error. Two repos with the same name
under one parent can't both exist. Releasing the last desk leaves the
empty `<repo>.desks/` dir in place.

## Tests

Known cases: default path per mode, for a quest desk and a grade desk;
`--path` wins; the upward-search probe; root status clean; same rollup
from both checkouts; `E_DESK_NOT_IGNORED` with no worktree created; the
settings merge (added, other keys kept, idempotent, absent in self mode).
Property-based: omitted. Paths are a two-mode function plus an override,
and every combination is enumerated.
