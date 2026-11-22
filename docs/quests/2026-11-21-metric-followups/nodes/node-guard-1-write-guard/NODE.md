---
date: 2026-11-21
quest: ../../QUEST.md
node: guard.1
status: proposed
---

# guard.1 - write-guard: the version guard runs where every write goes

## TL;DR

An older-MAJOR binary refuses `E_VERSION_AHEAD` before any state write,
whatever the command's shape. Today `guard_write` matches argv
patterns, and only `q c`, `q d` and `q <quest> u|c|d ...` match. The
documented `q <quest> n <node> e <edge>` form writes past it
(observed), and so do the `e` door, `n c`, `dep`, `metrics scrape` and
hooks (by code read). The check moves into `Gitx`, where every write
passes.

## Acceptance gates

Observed today (scratch repo, node ledger stamped `99.0.0`, binary
`0.2.0`):

```text
$ q demo u pf block --reason "u form"       -> {"ok":false,"code":"E_VERSION_AHEAD"}
$ q demo n pf e block --reason "n e form"   -> {"ok":true,"state":"blocked"}
```

Design trace:

```text
$ ./test/g.sh      # the version-guard block, one case per form, each in the stamped repo:
  u <node> block | n <node> e block | n c <node> | c <node> | dep <node> --depends-on x --reason y | metrics scrape (fixture with a sample to write)
    -> {"ok":false,"error":{"code":"E_VERSION_AHEAD"}}, exit 1, every bp3/ ref unmoved
  q r <quest> | n <node> r | metrics r  -> ok, with W_VERSION_AHEAD
  minor-ahead (0.3.0): every form above still writes, with W_VERSION_AHEAD
```

```yaml
objective: no write form skips the version guard
prove by:
  - test/g.sh version-guard cases per form, refs compared before and after
  - a mutant that removes the guard call from Gitx.commit_files fails g.sh
  - make check-full
done when: every write form refuses in a major-ahead repo with no ref moved, reads still answer, and guard_write is gone
```

## Diagram

```text
argv -> Main.run -> dispatch -> do_update | do_node_create | dep | Metrics_io.append | Hooks.append_event | land
                                                   |
                                                   v
                            Gitx.commit_files / Gitx.move_ref
                                 !Gitx.write_guard ()     <- Main sets: refuse if Store.version_ahead is a newer MAJOR
                                                   |
                                                   v
                               git plumbing: blob, tree, commit-tree, update-ref
```

## Pseudocode

```python
# gitx.ml: a hook, so Gitx needs no Store
write_guard = ref(lambda: None)

def commit_files(branch, base_tip, expect_tip, files, msg):
    write_guard()()            # first: no temp index, no object, no ref
    ...                        # unchanged

def move_ref(branch, new_tip, old_tip):    # land's two update-ref calls use this
    write_guard()()
    return run_status(["update-ref", branch, new_tip, old_tip])

# main.ml, before dispatch (replaces guard_write argv):
Gitx.write_guard := lambda: (
    err("E_VERSION_AHEAD", binary=bp3_version, repo=v)
    if (v := Store.version_ahead()) and major(v) > major(bp3_version) else None)
```

## Tables

| Field | Value |
|---|---|
| Intent | one guard, at the chokepoint, for every writer |
| Lane | high-blast-radius: every state write passes the new call |
| Output | `src/quest/gitx.ml` (`write_guard`, `move_ref`), `src/quest/main.ml` (guard set, `guard_write` deleted, land uses `move_ref`), `test/g.sh` |
| Acceptance | the `n e` probe above refuses; fails today |
| Depends on | none |

| Form | Writes | Guarded today | After |
|---|---|---|---|
| `q c <quest>`, `q d <quest>` | yes | yes | yes |
| `q <quest> u <node> <edge>`, `q <quest> c|d <node>` | yes | yes | yes |
| `q <quest> n <node> e <edge>` | yes | no (observed) | yes |
| `e <edge>` (claimed door) | yes | no (code read) | yes |
| `q <quest> n c <node>`, `q <quest> dep <node>` | yes | no (code read) | yes |
| `q <quest> metrics scrape` | yes, when it has samples | no (code read) | yes |
| hooks `append_event` | yes | no (code read) | yes; its `with _ -> false` turns the refusal into a skipped append |
| reads (`r`, `n r`, `metrics r`, `diagram`) | no | not refused | not refused, `W_VERSION_AHEAD` stays |

## Prose

Node 5 made the rule: an older-MAJOR binary never writes in a newer
repo. The guard was written against argv, and every form added since
(the nested `n <node> e`, the claimed `e` door, `metrics`) had to
remember to join a pattern list. None did. Checking at the chokepoint
removes the list: a new writer is guarded by construction.

Edge cases:
- Refused moves are ledgered. In a major-ahead repo, the refusal's own
  ledger line hits the guard too, so the caller gets `E_VERSION_AHEAD`
  instead of its original refusal. That is the rule: never write.
- `err` raises `Verdict`; hooks catch every exception around their
  write, so a hook in a newer repo skips its append and never fails the
  harness.
- `Store.make_checkpoint` writes a dangling commit object and moves no
  ref. It stays unguarded: it changes no state.
- Unit tests that call `Gitx` directly see the no-op default.

## Tests

Known cases: one g.sh case per form in the table (major-ahead refuses,
refs unmoved; minor-ahead writes and warns), plus reads that still
answer. Property-based: omitted. The forms are a closed list, and the
mutant (guard call removed) shows the cases bite.
