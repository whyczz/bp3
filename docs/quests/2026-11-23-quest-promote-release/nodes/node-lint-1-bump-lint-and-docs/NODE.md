---
date: 2026-11-23
quest: ../../QUEST.md
node: lint.1
status: proposed
---

# lint.1 - bump-lint-and-docs: bump frontmatter lint, RELEASING.md, and unpinning 0.2.0 tests

## TL;DR

Add `scripts/check-bump` to `make lint` (updating `scripts/check-gates` and `test/check-tiers.sh` in lockstep) to require `bump: major | minor | patch | none` on every proposed or active `QUEST.md` dated `>= 2026-11-22` (forward-only, exempting pre-`2026-11-22` historical quests plus `landed` and `canceled` quests). Write root `RELEASING.md` documenting the bump-meaning table, forward-only rule, `bp3 release <quest>`, `bp3 release --commit <sha>`, and tag-gated local auto-sync. Unpin the hardcoded `0.2.0` / `0.3.0` assertions in `test/release.sh` and `test/g.sh` so the suite stays green past `0.2.0`, and mark `version.1` in the unstarted `2026-11-22-bp3-is-static-across-downstream-repo-worktrees` draft superseded.

## Acceptance gates

Observed today (2026-11-23):

```text
$ ls scripts/check-bump RELEASING.md
ls: scripts/check-bump: No such file or directory
ls: RELEASING.md: No such file or directory
$ grep -n '0.2.0\|0.3.0' test/release.sh test/g.sh
test/release.sh:41:[ "$out" = "0.2.0" ] || fail "--version: $out"
test/g.sh:71:git show ... | jq -e '... .bp3_version == "0.2.0"'
test/g.sh:670:stamp_ledger demo vf-node 0.3.0
test/g.sh:678:echo "$out" | jq -e '... .error.facts.binary == "0.2.0" ...'
```

Design trace (after `lint.1` lands):

```text
$ ./scripts/check-bump
check-bump: ok
$ ./scripts/check-bump --root "$tmp_missing"
check-bump: FAIL docs/quests/2026-11-23-bad/QUEST.md: status proposed needs bump: major|minor|patch|none   # exit 1
$ ./scripts/check-bump --root "$tmp_invalid"
check-bump: FAIL docs/quests/2026-11-23-bad/QUEST.md: invalid bump: big (expected major|minor|patch|none)  # exit 1
$ ./scripts/check-bump --root "$tmp_exempt"   # landed, canceled, or date < 2026-11-22
check-bump: ok                                 # exit 0
$ ./scripts/check-gates && ./test/check-tiers.sh
# passes with ./scripts/check-bump pinned in lint allowlist
$ ./test/release.sh && ./test/g.sh
# both read bp3_version dynamically from src/quest/gitx.ml (proven passing at 0.3.0 in a scratch copy)
$ make check-full
# exit 0
```

```yaml
objective: enforce bump: frontmatter forward-only via make lint, document RELEASING.md, unpin 0.2.0/0.3.0 in tests, and note version.1 supersession
prove by:
  - ./scripts/check-bump (real repo + scratch fixtures in test/release.sh)
  - ./scripts/check-gates && ./test/check-tiers.sh
  - ./test/release.sh && ./test/g.sh (including scratch verification with gitx.ml bumped to 0.3.0)
  - make check-full
done when: all commands pass, scripts/check-bump rejects planted bad QUEST.md fixtures, and neither test/release.sh:41 nor test/g.sh:71,670,678 pins a literal version
```

## Diagram

```text
docs/quests/*/QUEST.md ──► scripts/check-bump (in make lint)
                             ├─ date < 2026-11-22       ──► exempt (forward-only)
                             ├─ status landed|canceled  ──► exempt
                             ├─ status proposed|active:
                             │    ├─ bump in {major,minor,patch,none} ──► ok
                             │    └─ missing or invalid               ──► FAIL (exit 1)
                             └─ scripts/check-gates + test/check-tiers.sh keep lint pinned

src/quest/gitx.ml (bp3_version) ──► test/release.sh & test/g.sh derive VER and NEXT_MINOR dynamically
```

## Pseudocode

```python
CUTOFF = "2026-11-22"
VALID_BUMPS = {"major", "minor", "patch", "none"}

def check_bump(root):
    fails = 0
    for path in sorted(glob(f"{root}/docs/quests/*/QUEST.md")):
        fm = parse_frontmatter(path)
        status = fm.get("status", "")
        date = fm.get("date", "")
        if status not in ("proposed", "active"):
            continue
        if date and date < CUTOFF:
            continue
        bump = fm.get("bump", "")
        if not bump:
            stderr(f"check-bump: FAIL {rel(path)}: status {status} needs bump: major|minor|patch|none")
            fails += 1
        elif bump not in VALID_BUMPS:
            stderr(f"check-bump: FAIL {rel(path)}: invalid bump: {bump} (expected major|minor|patch|none)")
            fails += 1
    if fails:
        exit(1)
    print("check-bump: ok")
```

## Tables

| Field | Value |
|---|---|
| Intent | Put bump discipline in `make lint`, write `RELEASING.md`, and remove hardcoded `0.2.0`/`0.3.0` test traps before `bp3` bumps |
| Lane | standard |
| Output | `scripts/check-bump`, `Makefile` (`lint:`), `scripts/check-gates`, `test/check-tiers.sh`, `RELEASING.md`, `test/release.sh`, `test/g.sh`, `test/suites.tsv` (add `scripts/check-bump` to `check-tiers` / `release` path globs), `docs/quests/2026-11-22-bp3-is-static-across-downstream-repo-worktrees/QUEST.md` (supersession note) |
| Acceptance | All `prove by` checks green; `scripts/check-bump` rejects missing/bad `bump:` on `>= 2026-11-22` proposed/active quests and passes on historical/landed/canceled; `test/release.sh` and `test/g.sh` pass dynamically |
| Depends on | none |

`RELEASING.md` bump-meaning table:

| Bump | Means | Examples |
|---|---|---|
| `major` | Breaking change: ledger/state semantics change OR breaking CLI/public contract removal/rename (`M+1.0.0`; cuts `1.0.0` from `0.x`) | ledger field renamed, CLI door/flag removed (`bp3 g` -> `bp3 q`) |
| `minor` | Backwards-compatible feature or addition (`M.m+1.0`; before `1.0`, breaking changes may optionally ride `minor` if staying `0.x`) | new CLI verb/flag, new skill, new optional JSON field, new Warden plug |
| `patch` | Bug fix or internal improvement with no contract change (`M.m.p+1`; default for `bp3 release --commit <sha>`) | small bugfix commit, performance, help/table polish |
| `none` | Docs, tests, or quest frames only — promotes quest branch and marks `QUEST.md` `landed` with no tag or GitHub Release (quest mode only) | quest frame, typo fix, test-only refactor |

## Prose

`scripts/check-gates` strictly allowlists every recipe line in `make check` and `make check-full` (and `test/check-tiers.sh` asserts exact step counts and indices). Adding `./scripts/check-bump` to `Makefile`'s `lint:` target therefore updates `scripts/check-gates` and `test/check-tiers.sh` in the same commit.

In `test/g.sh`, line 71 checks `.bp3_version == "$BP3_VER"`, line 670 stamps `NEXT_MINOR` (`${MAJOR}.$((MINOR + 1)).0`), and line 678 checks `.error.facts.binary == "$BP3_VER"`. Historical frozen-compat fixture lines (`test/g.sh:126-151`, `test/ready.sh:97-101`) deliberately keep `"0.2.0"`.

## Tests

- `test/release.sh`: extend with `scripts/check-bump` cases (missing `bump:`, invalid `bump: big`, `status: landed`, pre-`2026-11-22` `status: proposed`, valid `2026-11-23` `status: active`) + dynamic `BP3_VER` check.
- `test/check-tiers.sh`: updated allowlist step counts (`8 of 9`, shifted indices) and `grep -qx './scripts/check-bump'` assertion on `make -n lint`.
- `test/g.sh`: dynamic `BP3_VER` and `NEXT_MINOR` assertions; green under `make check-full`.
