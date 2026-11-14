---
date: 2026-11-14
quest: ../../QUEST.md
exp: 5
status: proposed
---

# Exp 5 — Release pattern: versioned bp3 artifacts

## TL;DR

bp3 gains a release pattern so an installed binary (Exp 6)
can be pinned, identified, and upgraded when bp3 changes:
`bp3_version` in `src/quest/gitx.ml` stays the single
version source; `bp3 q --version` prints it (plain text,
exit 0); `make release` builds `dist/bp3-q-v<version>-<os>-<arch>`
plus a `.sha256` beside it and refuses to run if a git tag
`v<version>` does not match the constant. Ledger lines
already stamp `bp3_version` on every write
(`src/quest/store.ml`), and this exp makes that stamp
load-bearing: versions are semver `MAJOR.MINOR.PATCH` and
the guard follows the major — a binary whose **MAJOR** is
older than the newest stamp in a repo's ledgers refuses
writes there (`E_VERSION_AHEAD`, reads still work with a
warning); a binary behind only on MINOR/PATCH writes with
a `W_VERSION_AHEAD` warning. An old-major binary never
silently mangles newer state.

Added at framing, 2026-11-14, on the owner's question:
"what if/when bp3 changes?" — this exp is the answer, and
it lands before Exp 6 spends it.

## Demo (design trace)

```text
$ bp3 q --version
0.2.0

$ make release
built dist/bp3-q-v0.2.0-macos-arm64  sha256: 9f2c…
$ shasum -a 256 -c dist/bp3-q-v0.2.0-macos-arm64.sha256
dist/bp3-q-v0.2.0-macos-arm64: OK

# repo stamped by a newer MAJOR, opened by this older binary:
$ bp3 q <quest> u <exp> submit --commit abc --reason "..."
{"ok":false,"error":{"code":"E_VERSION_AHEAD",
  "facts":{"binary":"0.2.0","repo":"1.0.0"}, ...}}     (reads still answer, with a warning)
```

Today (observed): `bp3 q --version` returns JSON `E_USAGE`
(exit 2); there is no `dist/`, no git tag, no release
target in the Makefile.

## Diagram

```text
gitx.ml bp3_version ──► bp3 q --version (print, exit 0)
        │
        ├──► git tag v<version> ──► make release ──► dist/bp3-q-v<version>-<os>-<arch> (+ .sha256)
        │        (mismatch = refuse)                     │
        │                                          Exp 6 installs this artifact
        └──► every ledger line stamps it ──► fold sees newer stamp than binary
                                                ├─ read:  answer + W_VERSION_AHEAD warning
                                                ├─ write, newer MINOR/PATCH: proceed + warning
                                                └─ write, newer MAJOR: E_VERSION_AHEAD, nothing written
```

## Pseudocode

```python
VERSION = bp3_version            # gitx.ml, the only source

def release():
    assert git_tag("v" + VERSION) == head(), "tag v%s must point at HEAD" % VERSION
    exe = dune_build("src/quest/main.exe")
    artifact = f"dist/bp3-q-v{VERSION}-{os()}-{arch()}"
    copy(exe, artifact); write(artifact + ".sha256", sha256(artifact))

def guard_write(repo_ledgers):
    newest = max(stamp(l) for l in repo_ledgers)     # already written per line
    if newest.major > VERSION.major:
        raise E_VERSION_AHEAD(binary=VERSION, repo=newest)
    if newest > VERSION:
        warn("W_VERSION_AHEAD", binary=VERSION, repo=newest)   # write proceeds
```

Version meaning (the contract a bump signs):

| Bump | Means | Examples |
|---|---|---|
| MAJOR | ledger/state semantics change: a fold reads old lines differently, or a line's meaning moved | ledger_line field renamed, fold step reinterpreted, verdict field removed |
| MINOR | backwards-compatible addition: old binary still folds new ledgers correctly, may not know the new thing | new door, new verb, new optional ledger field, new `--format` value |
| PATCH | no semantic change at all | bug fix, table rendering, help text, speed |

## Mapping to git releases

The release *is* a git release — one annotated tag, one
GitHub Release, assets built locally and uploaded with
`gh` (installed; repo is `whyczz/bp3` on GitHub, no tags
exist yet today). CI-built release assets are out until a
second platform actually needs one.

| Layer | Name | Carries |
|---|---|---|
| version source | `bp3_version` in `gitx.ml` | the only number anyone edits |
| git tag | `v<MAJOR.MINOR.PATCH>` (annotated, at the release commit) | the human "this commit is that version" act; `make release` refuses without it |
| staging | `dist/bp3-q-v<version>-<os>-<arch>` + `.sha256` | `make release` output |
| GitHub Release | release for that tag, title `v<version>` | assets = the `dist/` files; notes = the release commit's bp3-format body (TL;DR section) |
| publish | `make publish` = `make release` + `gh release create v<version> dist/*` | refuses if the GitHub Release already exists (a version is published once, never overwritten) |
| fetch (Exp 6) | `gh release download v<version>` or the asset URL | installs verify the `.sha256` before anything touches PATH |

## Tables

| Field | Value |
|---|---|
| Intent | a bp3 binary outside this repo is a named, checkable thing — never an anonymous copy of `_build` |
| Lane | standard |
| Output | `--version` in `src/quest/main.ml`; `release` target in `Makefile`; write-guard in the fold/dispatch seam; fixtures in `test/q.sh` |
| Acceptance | cases below; all fail today (observed above) |
| Depends on | none; Exp 6 depends on this |

| Case | Expected after |
|---|---|
| `bp3 q --version` | prints exactly `bp3_version` from `gitx.ml`, exit 0, works outside any repo |
| `make release` with matching tag | `dist/bp3-q-v<version>-<os>-<arch>` + `.sha256`; checksum verifies; artifact runs `--version` |
| `make release` with missing/mismatched tag | refuses, names the expected tag, builds nothing |
| `make publish` on a fresh version | GitHub Release `v<version>` exists with both assets; asset bytes hash to the published `.sha256` |
| `make publish` on an already-published version | refuses; published assets are never overwritten (a fix is a new PATCH) |
| version bump with no other change | only `bp3_version` edited; artifact name, `--version`, and ledger stamps follow |
| ledger stamped newer than binary: read | verdict answers, carries `W_VERSION_AHEAD` warning with both versions |
| ledger stamped newer **MAJOR**: write | `E_VERSION_AHEAD` (exit 1), ledger unchanged — verified by ledger hash before/after |
| ledger stamped newer MINOR/PATCH only: write | write proceeds, verdict carries `W_VERSION_AHEAD` |
| version bump discipline | a change touching ledger semantics without a MAJOR bump is a review failure, named here so reviewers can cite it |
| same-version and older-stamp repos | every existing command byte-identical; `make check` green |

## Acceptance test (goal block)

- **Objective:** bp3 versions are visible, releasable as
  artifacts, and protective when a repo has moved ahead.
- **Prove by:** the traced commands; a scratch repo whose
  ledger is stamped `99.0.0` (fixture line) exercised for
  read-warning and write-refusal; `make check` green.
- **Done when:** artifact + checksum verify, `--version`
  matches the constant, the ahead-repo write is refused
  with the ledger untouched.

## Prose

Context: dogfooding bp3 in a second repo (owner named
esc3) makes the binary a distributed thing, and distributed
things change. Without this exp, Exp 6 would install an
anonymous `_build` copy whose provenance nobody can check
a month later. Why the ledger stamp can carry the guard:
`store.ml` already writes `bp3_version` into every ledger
line, so "newest stamp in repo" is derivable from truth the
repo already keeps — no new state file, no version registry.
Version comparison parses the constant's three dotted
numbers (`0.2.0`); prerelease suffixes are out until
someone needs one. The bump table above is the discipline
that makes the guard mean something: the guard can only
trust stamps if a semantics change always pays a MAJOR. Why a git tag gates the release: the tag
is the human's "this commit is that version" act, and
`make release` merely refuses to counterfeit it. What this
exp deliberately is not: a package registry beyond GitHub
Releases, CI-built assets, or auto-update — `gh` uploads
local artifacts with checksums; fetching them is Exp 6's
problem.

## Tests

unit: none (build plumbing + one comparison seam; the seam
is fixture-sized) · fixtures: `--version` output, release
refusal on tag mismatch, ahead-repo read/write cases with
ledger-hash assertion in the q fixture suite · demos: the
traces above, including `shasum -c`
