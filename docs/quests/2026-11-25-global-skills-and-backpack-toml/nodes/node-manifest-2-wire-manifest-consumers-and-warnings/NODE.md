---
date: 2026-11-25
quest: ../../QUEST.md
node: manifest.2
status: proposed
---

# manifest.2 - wire-manifest-consumers-and-warnings: `q r`, `warden`, `release`, `brief`, and `receipt`

## TL;DR

Wire `Backpack` into every read/check/execution consumer without ever mutating a tracked tree on read: emit read-only `W_NO_REPO_CONFIG` warnings on `bp3 q r`, `bp3 warden`, and `bp3 release --dry-run` when `backpack.toml` is absent; honor `[warden].grade_wall_s` (default `300s`) and add the Layer-1 minor hygiene plug `missing_repo_config` in `bp3 warden`; honor `[release].target` in `bp3 release` (CLI `--target` wins); render `[grade].gate` from the bound commit's `backpack.toml` in `bp3 q <q> n <n> brief`; and have `scripts/receipt` fall back to `[grade].gate` when `BP3_RECEIPT_GATE` is unset.

## Acceptance gates

Observed today (`2026-11-25`, `a7087eb`):

```text
$ grep -n '300\.' src/warden/warden.ml
183:          let slow_over = match slow_grade with Some (c, v) when v > 300. -> Some (c, v) | _ -> None in
$ grep -n 'missing_repo_config' src/warden/warden.ml || echo "missing"
missing
$ grep -n 'backpack\.toml' src/quest/brief.ml src/quest/release_io.ml scripts/receipt || echo "missing"
missing
```

Design trace:

```text
$ # 1. Repo without backpack.toml: strictly read-only warnings + minor warden finding
$ bp3 q r | jq '.ok, .warnings[0].code'
true
"W_NO_REPO_CONFIG"
$ bp3 release <q> --dry-run | jq '.ok, .warnings[0].code'
true
"W_NO_REPO_CONFIG"
$ bp3 warden <q> --no-sessions | jq '.ok, .warnings[0].code, any(.findings[]; .rule == "missing_repo_config" and .severity == "minor")'
true
"W_NO_REPO_CONFIG"
true
$ git status --porcelain  # empty

$ # 2. Repo with backpack.toml overrides:
$ #    [grade] gate = "echo custom-gate"
$ #    [warden] grade_wall_s = 600
$ #    [release] target = "main"
$ bp3 warden <q> --no-sessions  # 450s grade_wall_s -> NO cycle_outlier; NO missing_repo_config; 650s -> cycle_outlier (> 600s)
$ bp3 release <q> --dry-run | jq '.target, (.warnings // []) | length'
"main"
0
$ bp3 release <q> --target master --dry-run | jq '.target'
"master"
$ bp3 q <q> n <n> brief | jq -r '.prompt' | grep -F 'Repo gate (backpack.toml): echo custom-gate'
Repo gate (backpack.toml): echo custom-gate
$ ./scripts/receipt  # runs "echo custom-gate" when BP3_RECEIPT_GATE is unset
```

```yaml
objective: wire backpack.toml settings and read-only W_NO_REPO_CONFIG warnings across bp3 q r, bp3 warden, bp3 release, bp3 q ... brief, and scripts/receipt with exact CLI > manifest > default precedence
prove by:
  - test/unit/test_warden.ml: missing_repo_config fires when ev_has_repo_config = false (Minor, evidence_ref = "repo:backpack.toml") and clears when true; plug_cycle_outlier uses ev_grade_wall_s (e.g. 600s does not flag 450s, flags 650s, threshold string prints "> 600s grade wall")
  - test/unit/test_brief.ml: brief renders "Repo gate (backpack.toml): <cmd>" when bound commit's backpack.toml defines [grade].gate, omits when absent, and Brief.is_verbatim still holds (QCheck2)
  - test/warden.sh: missing backpack.toml triggers missing_repo_config + W_NO_REPO_CONFIG; adding backpack.toml with grade_wall_s = 600 clears missing_repo_config and suppresses a 450s grade_wall_s outlier while catching 650s
  - test/release-door.sh: missing backpack.toml emits W_NO_REPO_CONFIG on --dry-run; [release].target = "main" is honored when --target omitted; explicit --target overrides manifest
  - test/receipt.sh: scripts/receipt picks up [grade].gate from backpack.toml when BP3_RECEIPT_GATE is unset, and BP3_RECEIPT_GATE overrides backpack.toml
  - test/g.sh: bp3 q r emits W_NO_REPO_CONFIG when backpack.toml is absent and omits warnings when present
  - make check && make check-full
done when: all unit and fixture suites pass and zero read/check command ever mutates the working tree when backpack.toml is missing
```

## Diagram

```text
                    backpack.toml (read-only)
                               │
       ┌───────────────┬───────┴────────┬─────────────────┬────────────────┐
       ▼               ▼                ▼                 ▼                ▼
   bp3 q r         bp3 warden      bp3 release      bp3 q ... brief   scripts/receipt
  (warnings:      ([warden]        (--target >      (git show sha:    (BP3_RECEIPT_GATE >
   W_NO_REPO_      grade_wall_s,    [release].target backpack.toml    [grade].gate >
   CONFIG)         missing_repo_    > master/main;   -> Repo gate)    make check-full)
                   config Minor)    --dry-run warn)
```

## Pseudocode

```python
# src/warden/warden.ml (pure)
# Extend evidence with:
#   ev_has_repo_config : bool
#   ev_grade_wall_s    : float   (default 300.)

def plug_missing_repo_config(ev):
    if ev.ev_has_repo_config:
        return []
    return [Finding(
        rule="missing_repo_config", layer=Git, severity=Minor,
        quest="", node="", cycle=0,
        observed="backpack.toml absent",
        threshold="backpack.toml present at repo root",
        evidence_ref="repo:backpack.toml",
        summary="backpack.toml missing at repo root; run bp3 init-repo",
    )]

def plug_cycle_outlier(ev):
    limit = ev.ev_grade_wall_s  # default 300.0
    # slow_over checks v > limit, threshold = f"> {int(limit)}s grade wall"
    ...

# src/quest/release_io.ml
def resolve_target(cli_target: str | None, manifest: RepoConfig | None) -> str:
    preferred = cli_target or (manifest.release_target if manifest else None)
    return detect_target_branch(preferred)

# src/quest/brief.ml
# Add `gate : string option` to Brief.inputs, loaded from Gitx.git_show commit "backpack.toml"
# When Some g -> render paragraph "Repo gate (backpack.toml): " ^ g before grading rules
# Brief.is_verbatim uses the exact same `render` so verbatim scraping stays intact!

# scripts/receipt
# If BP3_RECEIPT_GATE is set -> use it.
# Else if backpack.toml exists -> extract [grade].gate via awk (or bp3 config --format json | jq -r '.repo_config.grade.gate // empty')
# Else -> "make check-full"
```

## Tables

| Field | Value |
|---|---|
| Intent | wire `backpack.toml` rules (`grade_wall_s`, `target`, `gate`) and read-only `W_NO_REPO_CONFIG` warnings into all `bp3` consumers |
| Lane | standard |
| Output | `src/warden/warden.ml`, `src/warden/warden_io.ml`, `src/quest/main.ml`, `src/quest/release_io.ml`, `src/quest/brief.ml`, `scripts/receipt`, `test/unit/test_warden.ml`, `test/unit/test_brief.ml`, `test/warden.sh`, `test/release-door.sh`, `test/receipt.sh`, `test/g.sh` |
| Acceptance | fails today (hardcoded `300s`, no `missing_repo_config`, no `W_NO_REPO_CONFIG`, `release`/`brief`/`receipt` ignore `backpack.toml`); passes when all unit + fixture checks are green |
| Depends on | `manifest.1 - backpack-toml-parser-and-config` |
| Must not touch | `bin/bp3`, `scripts/install-bp3.sh`, `src/quest/hooks.ml`, `skills/*`, `CONSTRAINTS.md`, `Makefile`, `scripts/check-gates` |

## Prose

Precedence is strictly **explicit CLI/env > `backpack.toml` > built-in default** everywhere:
- `bp3 release`: `--target <branch>` > `[release].target` > auto-detect `master`/`main`.
- `scripts/receipt`: `BP3_RECEIPT_GATE` > `[grade].gate` from `backpack.toml` > `make check-full`.
- `bp3 warden`: `[warden].grade_wall_s` > `300` seconds.

In `scripts/receipt`, prefer reading `[grade].gate` directly with `awk` (keeping `scripts/receipt` standalone even if `bp3` isn't built yet, and staying within `CONSTRAINTS.md` bash `libs`). Be sure to unescape double-quoted TOML strings cleanly so commands with quotes/pipes work identically.

In `bp3 q r`, `bp3 warden`, and `bp3 release --dry-run`: omit `"warnings"` when `backpack.toml` is present (or keep existing JSON fields untouched) so existing callers parsing `.ok`, `.nodes`, `.findings`, `.target` see zero breaking schema changes, and emit `"warnings": [{"code":"W_NO_REPO_CONFIG","message":"..."}]` when absent. When `backpack.toml` exists on disk but fails to parse, fail loud with `E_INVALID_CONFIG` (exit 1) rather than silently falling back to defaults.

## Tests

- **Unit (`test/unit/test_warden.ml`, `test/unit/test_brief.ml`):** `missing_repo_config` on/off, custom `ev_grade_wall_s = 600.` suppressing 450s and flagging 650s with updated threshold text, `Brief.render` + `Brief.is_verbatim` QCheck2 with and without `gate`.
- **Fixture (`test/warden.sh`, `test/release-door.sh`, `test/receipt.sh`, `test/g.sh`):** end-to-end checks for missing vs present `backpack.toml`, CLI override precedence, and strict read-only `git status --porcelain` invariant.
