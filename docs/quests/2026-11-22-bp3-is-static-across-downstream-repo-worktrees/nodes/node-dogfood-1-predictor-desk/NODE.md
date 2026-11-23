---
date: 2026-11-22
quest: ../../QUEST.md
node: dogfood.1
status: proposed
---

# dogfood.1 - predictor-desk: the whole quest, checked out on predictor

## TL;DR

With bp3 reinstalled from the quest desk, `~/m/predictor` refreshes its
renders, sees `W_INSTALL_BEHIND` when its install is behind a tag (in
verdicts and in the SessionStart line), prepares a host desk beside the
repo, and runs one owner-picked node to `node_fin` through
`/induct-inline` in that desk, grade desk included. The root checkout
stays clean throughout. The output is the friction list in this
record's build notes, with the times measured.

## Acceptance gates

Observed today:

```text
$ ~/.local/bin/bp3-q --build                    # E_USAGE: the install predates build.1
$ (in ~/m/predictor) bp3 q r 2026-11-22-predictor-conventions-naming | jq -c .warnings
[]                                              # 64–112 commits behind master, and nothing says so
$ grep -c 'one node in flight' ~/m/predictor/.claude/skills/induct-inline/SKILL.md
2
$ ls -d ~/m/predictor/.bp3 ~/m/predictor.desks  # neither exists: no desk has ever run
```

Design trace (after build.1 through skills.1 land, before promotion):

```text
desk$       make install                          installed bp3 0.2.0+<sha7> -> ~/.local (was: unknown)   [owner's go]
            ~/.local/share/bp3/SOURCE             {"repo":"/Users/whycz/m/bp3","commit":"<quest tip>"}
predictor$  bp3 skills check                      E_RENDER_STALE [.claude/skills/induct-inline/SKILL.md, ...]
predictor$  bp3 skills install && bp3 skills check   ok      (committed in predictor on the owner's word)
version check, the real install against a scratch clone, so bp3's real tags stay untouched:
            scratch clone B of the quest tip; in B: scripts/bump minor (v0.3.0, scratch only)
predictor$  BP3_REPO_HOME=<B> bp3 q r <q> | jq -c .warnings      ["W_INSTALL_BEHIND"]
predictor$  echo '{"hook_event_name":"SessionStart",...}' | BP3_REPO_HOME=<B> bp3 q hooks
            bp3 0.2.0+<sha7> is installed; v0.3.0 is tagged in <B>: run make install there
predictor$  bp3 q r <q> | jq -c .warnings      []          (BP3_REPO_HOME unset: SOURCE's checkout, no tag past it yet)
predictor$  bp3 harness desk prepare --quest <q>  ../predictor.desks/quest-<q>
desk$       dune build                            builds the desk (no "Entering directory '~/m/predictor'"); cold N s
desk$       /induct-inline <q>                    one node: author, grade desk ../predictor.desks/grade-<n>-c1-a1, land
predictor$  git status --short                    empty (checked after prepare, each handoff, land, release)
predictor$  bp3 harness desk list                 grade desks released
```

After promotion (recorded in QUEST.md's success picture, not here): bp3
master tagged `v0.3.0`; a new Claude Code session in predictor shows the
SessionStart line until `make install` at the tag, then none.

```yaml
objective: predictor runs the induct-inline default in host desks with the reinstalled bp3, sees when that bp3 is behind, and the friction is written down
prove by:
  - ~/.local/bin/bp3-q --build == scripts/build-id in the quest desk; SOURCE names /Users/whycz/m/bp3
  - bp3 skills check in ~/m/predictor: E_RENDER_STALE before the re-render, ok after
  - the real install with BP3_REPO_HOME at a scratch clone tagged v0.3.0: W_INSTALL_BEHIND in a predictor verdict and the SessionStart line; unset: none
  - the chosen node reaches landed in bp3 q r, its grade cast from a grade desk, every grade brief_verbatim in the scrape
  - git -C ~/m/predictor status --short empty at each checkpoint listed above
  - cold dune build times for the quest desk and the first grade desk recorded (QUEST Open question 5)
  - whether a Claude Code session edited ../predictor.desks/ files without a permission prompt, recorded (QUEST Open question 2)
done when: the node is landed, the checks above are recorded in the build notes, and every friction item is listed with its owner (bp3 node, predictor fix, or icebox)
```

## Diagram

```text
owner: make install (quest desk) ─► ~/.local (bp3-q, bp3, share/{BUILD,SOURCE})
predictor: skills check ─► skills install ─► commit (owner)
scratch:   clone B + scratch tag ─► BP3_REPO_HOME=B ─► predictor verdict W_INSTALL_BEHIND, SessionStart line
predictor: desk prepare ─► ~/m/predictor.desks/quest-<q> ─► /induct-inline <q>
              author in quest desk ─► handoff ─► grade desk (beside) ─► verdict ─► land ─► release
evidence: build ids, render check, warnings, root status, dune times, permission prompts ─► build notes
```

## Pseudocode

```python
def dogfood(quest, node):
    assert installed_build() == build_id(quest_desk)           # owner ran make install there
    assert skills_check("~/m/predictor").code == "E_RENDER_STALE"
    skills_install("~/m/predictor"); owner_commit()
    assert skills_check("~/m/predictor").ok
    with scratch_clone_tagged("v0.3.0") as b:                 # never tags the real bp3 repo
        assert "W_INSTALL_BEHIND" in bp3_q_r("~/m/predictor", quest, BP3_REPO_HOME=b).warnings
        assert session_start_line("~/m/predictor", BP3_REPO_HOME=b)
    assert "W_INSTALL_BEHIND" not in bp3_q_r("~/m/predictor", quest).warnings
    desk = desk_prepare(quest)                                 # ../predictor.desks/quest-<quest>
    note(time(lambda: dune_build(desk)))
    induct_inline(quest, only=node, cwd=desk)                 # the skill as written
    for checkpoint in ("prepare", "handoff", "land", "release"):
        assert git_status("~/m/predictor") == ""
    write_build_notes(friction_list())
```

## Tables

| Field | Value |
|---|---|
| Intent | prove the quest on the repo that asked for it |
| Lane | standard (dogfood) |
| Output | this record's build notes (friction list, times, checks); predictor commits on the owner's word |
| Acceptance | the trace above; fails today (no `--build`, no warning, stale renders, no desk) |
| Depends on | skills.1 (and through it every other node) |

| Expected friction | Owner |
|---|---|
| predictor's pre-commit looks for `$root/_opam/bin` with root = the desk | predictor: find `_opam` via `git rev-parse --git-common-dir` |
| no `GRADING.md`: briefs tell the grader to find the gate | predictor: add one (`dune build`, `dune test`); QUEST Open question 4 |
| the desk's cold build (138 s in the scratch clone) | measured; QUEST Open question 5 |
| Claude Code permission prompts in `../predictor.desks/` | QUEST Open question 2 |
| whether SessionStart stdout reaches a live session's context | recorded; install.3 relies on it |

## Prose

The owner asked how predictor would use worktrees and then said "check
it out with predictor"; this node is both, run for real. Every other
node proves its part on a fixture. This one checks they compose on a
repo bp3 didn't grow up in: a real dune-pkg build, real hooks, a real
Claude Code session.

The quest's code lives on the quest branch until promotion, so the
install comes from the quest desk. Its build id names the quest tip; its
`SOURCE` still names the main checkout (install.1), whose only tag is
`v0.2.0`, so the real install warns about nothing, which is correct.
The warning is exercised on the real install by pointing
`BP3_REPO_HOME` at a scratch clone with a scratch tag, instead of
tagging bp3 early. The real end to end (tag `v0.3.0`, predictor
warned, reinstall, warning gone) happens at promotion and is recorded in
the QUEST success picture.

Human touchpoints are part of the node. `make install` changes the
installation, so the owner runs it or says go. The node to run is the
owner's pick from predictor's quests. Predictor's commits (the re-render,
and any GRADING.md or pre-commit fix) are predictor's history, made on
the owner's word.

A friction item becomes a bp3 node, a predictor fix, or an icebox entry.
None of them is fixed inside this node unless it blocks the run, and a
blocking fix is named in the notes with its commit.

## Tests

Known cases: the checkpoints in the goal block, recorded as observed.
Property-based: omitted; a dogfood run is one observation, and the
fixtures in the other nodes carry the breadth.
