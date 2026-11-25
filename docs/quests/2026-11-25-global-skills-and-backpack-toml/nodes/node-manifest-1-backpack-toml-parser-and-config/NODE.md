---
date: 2026-11-25
quest: ../../QUEST.md
node: manifest.1
status: proposed
---

# manifest.1 - backpack-toml-parser-and-config: `CONSTRAINTS.md` sign-off, pure-OCaml `backpack.toml` parser, `init-repo`, and `bp3 config`

## TL;DR

Record the owner's `2026-11-25` sign-off in `CONSTRAINTS.md` adding `.toml` to `data ext` and updating the Surfaces `skills` row for user-global skill dirs (zero new libraries). Implement a pure-OCaml strict TOML subset parser/serializer/validator in `src/quest/backpack.ml` (`version = 1`, `repo`, `[grade].gate`, `[warden].grade_wall_s`, `[release].target`), register `Layout.manifest_file = "backpack.toml"`, `Names.w_no_repo_config = "W_NO_REPO_CONFIG"`, and `Names.e_invalid_config = "E_INVALID_CONFIG"`, wire `bp3 init-repo` to idempotently create minimal `backpack.toml` (never clobbering an existing one) alongside `plans/` and `bp3.sqlite` registration, and wire read-only `bp3 config` to expose `repo_config` and emit `W_NO_REPO_CONFIG` when `backpack.toml` is missing.

## Acceptance gates

Observed today (`2026-11-25`, `a7087eb`):

```text
$ grep -n '\.toml' CONSTRAINTS.md || echo "missing"
missing
$ test -f src/quest/backpack.ml && echo exists || echo missing
missing
$ ./bin/bp3 config | jq 'has("repo_config"), has("warnings")'
false
false
```

Design trace:

```text
$ ./scripts/check-constraints
check-constraints: ok (3 languages, ...)
$ dune test  # includes test_backpack.ml (unit + QCheck2 round-trip & malformed rejection)
OK
$ # in fresh git repo without backpack.toml:
$ bp3 config
{"ok":true,"config_dir":".../.git/bp3","mode":"host","thresholds":{...},"desks":[],
 "repo_config":null,
 "warnings":[{"code":"W_NO_REPO_CONFIG","message":"backpack.toml not found; run bp3 init-repo to create backpack.toml"}]}
$ git status --porcelain  # empty: strictly read-only
$ bp3 init-repo
{"ok":true,"manifest":"backpack.toml","manifest_created":true,"plans":["plans/default.yaml","plans/direct.yaml"]}
$ cat backpack.toml
version = 1
repo = "<slug>"

[grade]
gate = "make check-full"

[warden]
grade_wall_s = 300

[release]
target = "master"
$ bp3 config | jq '.repo_config.version, .repo_config.repo, (.warnings // []) | length'
1
"<slug>"
0
$ # editing backpack.toml and re-running bp3 init-repo preserves user's edits:
$ printf 'version = 1\nrepo = "custom"\n[warden]\ngrade_wall_s = 600\n' > backpack.toml
$ bp3 init-repo | jq '.ok, .manifest_created'
true
false
$ # malformed backpack.toml fails loud on read:
$ printf 'version = 99\n' > backpack.toml
$ bp3 config  # rc 1, error.code == "E_INVALID_CONFIG"
```

```yaml
objective: sign off .toml in CONSTRAINTS.md, implement pure-OCaml Backpack manifest parser/validator/writer, wire bp3 init-repo to scaffold backpack.toml idempotently, and wire read-only bp3 config to surface repo_config or W_NO_REPO_CONFIG
prove by:
  - ./scripts/check-constraints && ./test/check-constraints.sh (with a tracked .toml fixture proving .toml is accepted)
  - test/unit/test_backpack.ml: known cases (minimal, full, comments, escaped strings, defaults, missing sections, unknown version, syntax error, negative grade_wall_s, unknown key/section) + QCheck2 serialize->parse round-trip property
  - test/config.sh: missing backpack.toml emits W_NO_REPO_CONFIG without mutating tree or .git/bp3; valid backpack.toml populates repo_config with 0 warnings; invalid backpack.toml exits 1 with E_INVALID_CONFIG; read-only .git/ still succeeds
  - test/install.sh: bp3 init-repo creates minimal backpack.toml + plans/ + registers repo in bp3.sqlite; second bp3 init-repo after user edits preserves backpack.toml verbatim
  - make check && make check-full
done when: all unit and fixture suites pass, zero new opam libraries are added, and CONSTRAINTS.md contains the verbatim owner sign-off row
```

## Diagram

```text
<repo>/backpack.toml (<= 15 lines, committed in git)
        │
        ├── absent  ──► Backpack.load_opt root = Ok None
        │                 ├── bp3 config      ──► repo_config: null, warnings: [W_NO_REPO_CONFIG] (read-only)
        │                 └── bp3 init-repo   ──► write default backpack.toml + plans/ + Repo_store.add
        │
        ├── valid   ──► Backpack.load_opt root = Ok (Some cfg)
        │                 ├── bp3 config      ──► repo_config: {...}, warnings omitted
        │                 └── bp3 init-repo   ──► keep existing backpack.toml untouched (manifest_created: false)
        │
        └── invalid ──► Backpack.load_opt root = Error detail
                          └── bp3 config / init-repo ──► exit 1, E_INVALID_CONFIG
```

## Pseudocode

```python
# src/quest/backpack.ml (pure, stdlib only)
@dataclass
class RepoConfig:
    version: int                  # must be 1
    repo: str                     # non-empty kebab/alnum slug
    grade_gate: str | None        # [grade].gate
    warden_grade_wall_s: int | None  # [warden].grade_wall_s (> 0)
    release_target: str | None    # [release].target (non-empty branch name)

def parse(text: str) -> Result[RepoConfig, str]:
    section = ""  # "", "grade", "warden", "release"
    seen = set()
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = strip_comment_outside_quotes(raw).strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            if section not in ("grade", "warden", "release"):
                return Error(f"line {lineno}: unknown section [{section}]")
            continue
        key, val = split_first_equals(line)  # error if missing '='
        full_key = f"{section}.{key}" if section else key
        if full_key in seen:
            return Error(f"line {lineno}: duplicate key {full_key}")
        seen.add(full_key)
        # validate exact key + type:
        #   version -> int == 1
        #   repo -> quoted non-empty string
        #   grade.gate -> quoted non-empty string
        #   warden.grade_wall_s -> positive int (> 0)
        #   release.target -> quoted non-empty string
        #   anything else -> Error(f"line {lineno}: unknown key {full_key}")
    require version == 1 and repo non-empty
    return Ok(cfg)

def render_default(repo_slug: str, target_branch: str) -> str:
    # <= 12 lines minimal TOML:
    # version = 1
    # repo = "<repo_slug>"
    #
    # [grade]
    # gate = "make check-full"
    #
    # [warden]
    # grade_wall_s = 300
    #
    # [release]
    # target = "<target_branch>"

def warning_no_repo_config() -> json:
    return {"code": Names.w_no_repo_config,
            "message": "backpack.toml not found; run bp3 init-repo to create backpack.toml"}
```

## Tables

| Field | Value |
|---|---|
| Intent | establish the `backpack.toml` schema, pure-OCaml parser, `CONSTRAINTS.md` sign-off, `init-repo` scaffolding, and read-only `bp3 config` surface |
| Lane | standard |
| Output | `CONSTRAINTS.md`, `src/quest/layout.ml`, `src/quest/names.ml`, `src/quest/backpack.ml`, `src/quest/config.ml`, `src/quest/main.ml`, `test/unit/test_backpack.ml`, `test/unit/dune`, `test/config.sh`, `test/install.sh`, `test/check-constraints.sh` |
| Acceptance | fails today (no `.toml` in `CONSTRAINTS.md`, no `backpack.ml`, `init-repo` creates no `backpack.toml`, `bp3 config` emits neither `repo_config` nor `W_NO_REPO_CONFIG`); passes when all unit + fixture gates are green |
| Depends on | none |
| Must not touch | `bin/bp3`, `scripts/install-bp3.sh`, `src/quest/hooks.ml`, `src/warden/*`, `skills/*`, `Makefile`, `scripts/check-gates` |

## Prose

Why a pure-OCaml subset parser instead of an opam TOML package: `backpack.toml` is intentionally capped at `<= 15` lines with 5 flat/1-level-section keys. Writing ~80 lines of pure OCaml (`stdlib`) adds zero build/opam dependency risk, keeps `CONSTRAINTS.md`'s OCaml library list unchanged, and lets us reject unknown sections/keys with line numbers cleanly (catching typos like `grade_wall = 600` instead of silently ignoring them).

Comment stripping must respect quoted strings so a gate command containing `#` inside quotes (e.g., `gate = "sh -c 'echo ok # test'"`) is preserved verbatim while trailing comments (`grade_wall_s = 600 # cold dune build`) strip cleanly.

In `bp3 init-repo`, derive default `repo` slug from `Repo_store.slug_of_path root` (or sanitized basename of canonical repo root) and default `target` branch from existing `master` vs `main` (defaulting to `"master"`). If `backpack.toml` already exists, validate it via `Backpack.parse` (refusing `E_INVALID_CONFIG` if corrupted) and leave it untouched (`manifest_created: false`) so `bp3 init-repo` is always safe and idempotent.

In `CONSTRAINTS.md`, add one Sign-off log row dated `2026-11-25` quoting the owner's words verbatim (`"Sign off adding .toml to CONSTRAINTS.md data ext (pure-OCaml parser, 0 new libs) + update Surfaces skills row"`), add `.toml` to the `data ext` line, and update the Surfaces `skills` row to note user-global harness skill dirs alongside `bp3`'s repo-local dev skills.

## Tests

- **Known cases (`test/unit/test_backpack.ml`):** minimal (`version = 1` + `repo`), full predictor-shaped manifest (`gate = "dune build --root . @fmt && dune test --root . --force 4>&-"`, `grade_wall_s = 600`, `target = "master"`), inline `#` comments outside quotes vs `#` inside double quotes, escaped quotes/backslashes, duplicate keys, unknown section, unknown key, `version = 2`, `grade_wall_s = 0` or `-5`, missing `repo`, non-integer `grade_wall_s`.
- **Property-based (QCheck2 in `test/unit/test_backpack.ml`):** for any generated valid `Backpack.t`, `parse (render cfg) = Ok cfg` (exact round-trip law) and `render cfg` has `<= 15` lines.
- **Fixture tests (`test/config.sh`, `test/install.sh`, `test/check-constraints.sh`):** verify read-only `W_NO_REPO_CONFIG` with clean `git status`, `init-repo` idempotency without clobbering user edits, `E_INVALID_CONFIG` refusal on malformed `backpack.toml`, and `check-constraints` accepting a tracked `backpack.toml`.
