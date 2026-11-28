---
node: skills.1
---

# skills.1 - red-ink-and-induct-ticket-polish

TL;DR
Update `skills/red-ink/SKILL.md` (explicit owner LGTM gate `#7`, `Internals: layout` slice `#8`, drop parallel-waves push `#9`, align heading to `Acceptance gates` `#10`), `skills/induct/SKILL.md` (remove retired `/swarm` mode `#9`, default c2+ mechanical delta re-grades to `Model: "flash"` `#11a`), and `test/skills.sh` to pin every new rule and block `/swarm` regressions.

## Acceptance gates

Design trace:

```text
$ tmp=$(mktemp -d)
$ BP3_GLOBAL_HOME="$tmp/home" BP3_COMPLETIONS_DIR="$tmp/comp" BP3_DB="$tmp/bp3.sqlite" ./bin/bp3 skills install --harness=all
$ BP3_GLOBAL_HOME="$tmp/home" ./bin/bp3 skills check
-> ok
$ rg -n '/swarm' skills/induct/SKILL.md
-> (empty, exit 1)
$ ./test/skills.sh && make check-full
-> rc 0
```

Runnable goal block:
- **objective:** Apply Tickets `#7`, `#8`, `#9`, `#10` (template alignment), and `#11` (part 1) cleanly across `skills/red-ink/SKILL.md`, `skills/induct/SKILL.md`, and `test/skills.sh` under `v0.7.0`'s global `CORE_SKILLS` layout.
- **prove by:** Isolated `bp3 skills install --harness=all` + `bp3 skills check`, `rg '/swarm' skills/induct/SKILL.md` empty, `./test/skills.sh`, and `make check-full`.
- **done when:** `make check-full` exits `0`, `skills/red-ink/SKILL.md` enforces explicit owner LGTM before advancing slices, includes `Internals: layout` (`before -> after`) before `Names`, uses `Acceptance gates`, and does not push parallel waves; `skills/induct/SKILL.md` contains zero `/swarm` references and defaults c2+ mechanical delta re-grades to `Model: "flash"`; and `test/skills.sh` pins all of these across sources and global renders.

## Diagram

```text
skills/red-ink/SKILL.md (#7 LGTM gate, #8 Internals: layout, #9 no parallel waves, #10 Acceptance gates)
skills/induct/SKILL.md  (#9 remove /swarm section, #11a c2+ mechanical delta -> Model: "flash")
  --> test/skills.sh (replace retired /swarm checks with anti-regression + new rule pins)
  --> isolated bp3 skills install + bp3 skills check + make check-full GREEN
```

## Pseudocode

```python
def polish_red_ink_and_induct():
    # red-ink (#7, #8, #9, #10)
    add_explicit_lgtm_pause_before_next_slice("skills/red-ink/SKILL.md")
    add_internals_layout_slice_before_names("skills/red-ink/SKILL.md")
    drop_parallel_waves_default("skills/red-ink/SKILL.md")
    align_heading_to_acceptance_gates("skills/red-ink/SKILL.md")
    # induct (#9, #11a)
    remove_swarm_parallel_mode("skills/induct/SKILL.md")
    default_mechanical_delta_regrades_to_flash("skills/induct/SKILL.md")
    # tests
    update_skills_tests("test/skills.sh")
    assert run("make check-full") == 0
```

## Tables

| Field | Value |
|---|---|
| Intent | Dedicated skill-change node (per `quest/SKILL.md` step 6.6) landing Tickets `#7`, `#8`, `#9`, `#10` (template), and `#11` (part 1). |
| Kind | `code` |
| Lane | `micro` |
| Output | Updated `skills/red-ink/SKILL.md`, `skills/induct/SKILL.md`, and `test/skills.sh`. |
| Acceptance | Fails today: `skills/induct/SKILL.md` still contains `/swarm`, `skills/red-ink/SKILL.md` lacks the explicit LGTM pause and `Internals: layout` slice and still says `Acceptance test`. |
| Depends on | `brief.1 - accept-acceptance-test-heading` |

## Prose

Both `red-ink` and `induct` are global `CORE_SKILLS` (no repo-local copies under `.{agents,claude,pi}/skills/`). When updating `skills/induct/SKILL.md`, keep every surviving `test/skills.sh` invariant intact (`./scripts/receipt`, `Severity gate`, `[critical]`, `[minor]`, `invoke_subagent`, `"flash"`, `"pro"`, `brief --desk`, `metrics scrape`, `auto-lands directly`, `E_MISSING_ANCESTOR`, `E_PROTECTED_FILE`, `E_DOC_ONLY_NODE`, `E_EXPLORE_BOUND`, `e iterate --note`). Replace `test/skills.sh:454-460`'s retired `/swarm` assertions with a negative assertion ensuring `/swarm` does not return. Also check `skills/quest/SKILL.md` to confirm it does not push parallel waves by default (no edit needed if already clean).
