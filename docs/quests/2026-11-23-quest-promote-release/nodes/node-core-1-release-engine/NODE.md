---
date: 2026-11-23
quest: ../../QUEST.md
node: core.1
status: proposed
---

# core.1 - release-engine: pure OCaml semver, remote, frontmatter, release-notes, and sync core

## TL;DR

Add a pure, zero-I/O OCaml module `src/quest/release.ml` to `bp3_quest` plus unit and QCheck2 property tests in `test/unit/test_release.ml`. It owns every deterministic decision across both `bp3 release` modes (`<quest>` and `--commit <sha>`) and tag-gated local auto-sync: parsing and advancing semver tags (`major | minor | patch | none`), picking the latest `vX.Y.Z` tag (baseline `0.0.0` when untagged), detecting a GitHub `owner/repo` from remote URLs, parsing `QUEST.md` frontmatter (`status`, `bump`, H1 title, TL;DR) and rewriting `status:` to `landed`, updating `bp3_version` in `src/quest/gitx.ml` (or a `VERSION` file), parsing rendered `(vX.Y.Z)` stamps from `SKILL.md` headers + deciding `should_auto_sync`, and rendering deterministic **"What changed"** bodies for both quest releases and commit-hash bugfix releases.

## Acceptance gates

Observed today (2026-11-23):

```text
$ ls src/quest/release.ml test/unit/test_release.ml
ls: src/quest/release.ml: No such file or directory
ls: test/unit/test_release.ml: No such file or directory
```

Design trace (after `core.1` lands):

```text
$ dune test
# test_release.ml runs and passes:
# - parse_semver_tag: "v0.2.0" -> Some {0;2;0}, "v1.12.3" -> Some {1;12;3},
#   "0.2.0" / "v0.2" / "v0.2.0-rc1" / "v01.2.0" / "foo" -> None
# - latest_semver_tag: [] -> None; ["v0.2.0";"v0.10.0";"v0.9.9";"misc"] -> Some {0;10;0}
# - next_semver:
#     None, Minor -> Some {0;1;0}; None, Major -> Some {1;0;0}; None, Patch -> Some {0;0;1}
#     Some {0;2;0}, Minor -> Some {0;3;0}; Major -> Some {1;0;0}; Patch -> Some {0;2;1}; None_bump -> None
# - parse_github_repo: SSH, HTTPS, ssh://, with/without .git -> Some "owner/repo"; non-GitHub / local -> None
# - parse_quest_md + set_quest_status_landed: extracts status/bump/title/TL;DR,
#   flips only frontmatter status to landed leaving body byte-identical
# - sync_bp3_version: replaces let bp3_version = "0.2.0" -> "0.3.0"; refuses missing/duplicate
# - parse_rendered_release_tag: extracts Some {0;3;0} from
#   "<!-- GENERATED from skills/quest/SKILL.md (v0.3.0) by: bp3 skills install ... -->",
#   None from legacy unversioned notice
# - should_auto_sync: true when installed_tag > any rendered_tag OR any rendered skill lacks a version tag;
#   false when all rendered skills already match or exceed installed_tag
# - render_what_changed (quest mode) + render_commit_what_changed (commit mode): deterministic Markdown
# - QCheck2 laws: round-trip parse_semver_tag(format_tag v) = Some v; next_semver strictly greater;
#   Major resets minor/patch to 0; Minor resets patch to 0; Patch increments only patch
$ make check
# exit 0
```

```yaml
objective: implement the pure OCaml release & sync decision core (src/quest/release.ml) with unit and QCheck2 tests (test/unit/test_release.ml)
prove by:
  - dune test (test_release registered in test/unit/dune)
  - make check
done when: test_release.ml passes every unit case and QCheck2 law with zero I/O or git calls inside release.ml, and make check exits 0
```

## Diagram

```text
tags: string list ──► latest_semver_tag ──► prev: semver option ─┐
bump_str          ──► parse_bump        ──► bump                 ├──► next_semver ──► vX.Y.Z | None
remote_url        ──► parse_github_repo ──► GitHub "o/r" | Local_tag
QUEST.md text     ──► parse_quest_md    ──► {status, bump, title, tldr}
                  ──► set_quest_status_landed ──► updated QUEST.md
gitx.ml text      ──► sync_bp3_version  ──► updated gitx.ml (Ok | Error)
rendered SKILL.md ──► parse_rendered_release_tag ──► should_auto_sync ~installed ~rendered
(quest | commit inputs) ──► render_what_changed / render_commit_what_changed ──► {tag, title, body}
```

## Pseudocode

```python
def parse_semver_tag(tag: str) -> Semver | None:
    if not tag.startswith("v"):
        return None
    parts = tag[1:].split(".")
    if len(parts) != 3 or any(not p.isdigit() for p in parts):
        return None
    if any(len(p) > 1 and p.startswith("0") for p in parts):
        return None
    return Semver(int(parts[0]), int(parts[1]), int(parts[2]))

def next_semver(prev: Semver | None, bump: Bump) -> Semver | None:
    base = prev or Semver(0, 0, 0)
    match bump:
        case "none":  return None
        case "major": return Semver(base.major + 1, 0, 0)
        case "minor": return Semver(base.major, base.minor + 1, 0)
        case "patch": return Semver(base.major, base.minor, base.patch + 1)

def parse_rendered_release_tag(skill_md: str) -> Semver | None:
    # Matches: <!-- GENERATED from skills/<id>/SKILL.md (vX.Y.Z) by: ... -->
    m = re.search(r"^<!-- GENERATED from skills/[^ ]+/SKILL\.md \((v\d+\.\d+\.\d+)\) by:", skill_md, re.M)
    return parse_semver_tag(m.group(1)) if m else None

def should_auto_sync(installed: Semver, rendered: list[Semver | None]) -> bool:
    if not rendered:
        return False
    return any(r is None or compare_semver(installed, r) > 0 for r in rendered)

def render_commit_what_changed(sha, subject, body, tag, prev_tag, commit_subjects) -> ReleaseNotes:
    title = f"{tag} — {subject}" if subject else tag
    lines = [f"# {title}", ""]
    if body.strip():
        lines += [body.strip(), ""]
    lines.append("## What changed")
    for s in (commit_subjects or [f"{subject} ({sha[:7]})"]):
        lines.append(f"- {s}")
    lines += ["", f"Commit: `{sha[:7]}`", f"Previous tag: {prev_tag or 'none'}"]
    return ReleaseNotes(tag=tag, title=title, body="\n".join(lines) + "\n")
```

## Tables

| Field | Value |
|---|---|
| Intent | Isolate all release arithmetic, parsing, rewriting, sync comparison, and note formatting in one pure OCaml module |
| Lane | standard |
| Output | `src/quest/release.ml`, `test/unit/test_release.ml`, `test/unit/dune` (register `test_release`) |
| Acceptance | `dune test` passes every `test_release` unit case & QCheck2 law; `make check` exits 0 |
| Depends on | none |

Edge cases handled purely in `Release`:

| Case | Behavior |
|---|---|
| Repo has zero tags (`[]`) | `latest_semver_tag [] = None`; `Minor` -> `v0.1.0`, `Major` -> `v1.0.0`, `Patch` -> `v0.0.1` |
| Non-semver / prerelease / leading-zero tags (`v0.2.0-rc1`, `v01.2.0`) | Ignored by `parse_semver_tag` |
| Numeric vs lexicographic order (`v0.10.0` vs `v0.9.9`) | Numeric tuple compare (`0.10.0 > 0.9.9`) |
| Legacy unversioned rendered skill (`<!-- GENERATED from skills/quest/SKILL.md by: ... -->`) | `parse_rendered_release_tag` returns `None`; `should_auto_sync` returns `true` so repos like `predictor` upgrade on first `v0.3.0` SessionStart |
| Mixed harness renders (`.claude` at `v0.3.0`, `.agents` at `v0.2.0`) | `should_auto_sync` returns `true` (syncs every stale harness dir together) |
| Host repo has no generated skills at all (`rendered = []`) | `should_auto_sync` returns `false` (never installs skills into a repo that never opted in) |
| `QUEST.md` body contains a prose line starting with `status:` | Untouched; `set_quest_status_landed` edits strictly inside the first `---` … `---` frontmatter block |
| `gitx.ml` missing `let bp3_version = "..."` or has >1 match | `sync_bp3_version` returns `Error msg` (fail closed) |

## Prose

Keeping every release and sync predicate pure in `src/quest/release.ml` makes both `cli.1` (`release_io.ml`) and `sync.1` (`hooks.ml`) thin I/O adapters over one verified core. Notice `should_auto_sync` with `rendered = []` returns `false`: if a repo has never run `bp3 init` / `bp3 skills install`, `SessionStart` must never unexpectedly inject `.claude/skills` into it, whereas a repo like `predictor` (which has legacy unversioned `<!-- GENERATED from skills/...` files) returns `rendered = [None; ...]` and cleanly triggers auto-sync on the first tagged release!

## Tests

- Unit cases (`case_*` in `test/unit/test_release.ml`): `parse_bump`, `parse_semver_tag`, `latest_semver_tag`, `next_semver`, `parse_github_repo`, `parse_quest_md`, `set_quest_status_landed`, `sync_bp3_version`, `parse_rendered_release_tag`, `should_auto_sync` (empty, all-current, one-stale, legacy-unversioned, ahead), `render_what_changed` (quest mode), `render_commit_what_changed` (commit mode).
- QCheck2 laws (`law_*`): `parse_semver_tag (format_tag v) = Some v`; monotonicity `compare_semver next v > 0` for `Major | Minor | Patch`; reset laws (`Major` -> `0.0`, `Minor` -> `.0`, `Patch` -> `+1`).
