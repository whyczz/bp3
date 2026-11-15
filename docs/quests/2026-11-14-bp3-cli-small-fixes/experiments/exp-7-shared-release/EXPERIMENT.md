---
date: 2026-11-14
quest: ../../QUEST.md
exp: 7
status: proposed
---

# Exp 7 — Shared release mechanism: bp3 owns it, yap-skills rides it

## TL;DR

The Exp 5 release pattern becomes a mechanism bp3 owns and
both repos consume: canonical scripts in this repo
(`scripts/release-check`, `scripts/release-publish`, one
job each — version-source agreement, tag gate, artifact +
`.sha256`, `gh` publish-once) driven by a per-repo config
(version source, package command, asset names). This repo
calls them from `make release`/`make publish` for the
`bp3-q` binary; **bp3-yap-skills** vendors a copy of the
scripts plus its own config and releases skills the same
way: its `VERSION` file (`0.1.0` today) → annotated tag
`v<version>` → packaged bundles from `make package`
(`yap plugin`, already version-stamped) → GitHub Release.
Version numbers stay per-repo and independent; the
*mechanism* is what's shared. Yap's semver contract:
MAJOR = a skill's contract breaks (invocation or output
shape), MINOR = new skill or compatible improvement,
PATCH = wording. There is no ledger in yap, so there is
no version-ahead guard there — the guard stays bp3-only.

Added at framing, 2026-11-14, on the owner's ask. Depends
on Exp 5 (pattern proved on the binary first, then
extracted — not designed in the abstract for two repos).

## Demo (design trace)

```text
# in bp3 (Exp 5's flow, now via the shared scripts):
$ make publish
release-check: bp3_version 0.2.0 == tag v0.2.0 ✓
built dist/bp3-q-v0.2.0-macos-arm64 (+ .sha256)
gh: created release v0.2.0 on whyczz/bp3 ✓

# in bp3-yap-skills (same scripts, vendored; its own config):
$ make publish
release-check: VERSION 0.1.0 == tag v0.1.0 ✓
packaged generated/ (pi, claude, codex, muse) -> dist/bp3-yap-skills-v0.1.0.tar.gz (+ .sha256)
gh: created release v0.1.0 on whyczz/bp3-yap-skills ✓

# drift is visible, never silent:
$ head -2 scripts/release-check        # in either repo
# release-script v1 — source: bp3 scripts/release-check (vendored copies carry this line)
```

Today (observed): bp3-yap-skills has `VERSION` and
packaging but zero git tags and no release target; Exp 5's
pattern exists only as bp3 Makefile intent.

## Diagram

```text
bp3 (owner)                          bp3-yap-skills (consumer)
scripts/release-check ───┐           scripts/release-check (vendored copy)
scripts/release-publish ─┼─ config ─►├─ config: VERSION file, `make package`
Makefile release/publish ┘           Makefile release/publish (new, thin)
        │                                     │
   tag v0.2.0 ─► GitHub Release        tag v0.1.0 ─► GitHub Release
   asset: bp3-q binary                 asset: packaged skill bundles
   versions independent — pattern shared, numbers never synced
```

## Pseudocode

```python
CONFIG = load("release.conf")        # VERSION_SOURCE, PACKAGE_CMD, ASSET_GLOB, REPO

def release_check():
    v = read_version(CONFIG.VERSION_SOURCE)          # gitx.ml constant | VERSION file
    assert annotated_tag("v" + v) == HEAD            # the human's release act
    return v

def publish():
    v = release_check()
    run(CONFIG.PACKAGE_CMD)                          # dune build | yap plugin
    assets = collect(CONFIG.ASSET_GLOB, version=v)   # each + .sha256
    gh_release_create(f"v{v}", assets, if_absent=True)  # publish-once, both repos
```

## Tables

| Field | Value |
|---|---|
| Intent | one release discipline for both repos, owned where the binary lives; neither repo invents its own |
| Lane | standard |
| Output | `scripts/release-check`, `scripts/release-publish`, `release.conf` in bp3; vendored scripts + `release.conf` + thin Makefile targets in bp3-yap-skills |
| Acceptance | cases below |
| Depends on | Exp 5 |

| Case | Expected after |
|---|---|
| bp3 publish via shared scripts | same behavior Exp 5 specified (tag gate, checksum, publish-once) — now through `scripts/release-*` |
| yap-skills: `make release` | `dist/bp3-yap-skills-v<VERSION>.tar.gz` (+ `.sha256`) from `make package` output; version inside the bundle manifest equals `VERSION` |
| yap-skills: `make publish` | GitHub Release `v<VERSION>` on `whyczz/bp3-yap-skills` with the assets; second publish of same version refuses |
| tag/VERSION mismatch in either repo | `release-check` refuses and names both numbers |
| vendored copy edited in yap repo | the `release-script v1` source line + a hash note in yap's `release.conf` make the divergence one `diff` away; silent drift is a review catch, stated honestly |
| yap `make check`, bp3 `make check` | both green (yap check gains a release-config sanity case) |
| installed skills from a yap release | install from the release tarball matches install from checkout at the same tag (file-for-file on `skills/`) |

## Acceptance test (goal block)

- **Objective:** both repos cut publish-once, tag-gated,
  checksummed releases through one bp3-owned mechanism.
- **Prove by:** dry-run traces in both repos (mismatched
  tag refusal first), then one real PATCH publish each if
  the owner wants it live; asset checksum verification
  from the GitHub Releases; both `make check`s green.
- **Done when:** the refusal, staging, and publish cases
  pass in both repos and the assets verify from GitHub.

## Prose

Context: the owner asked for yap-skills releases too, with
bp3 owning the scripts. Why vendored copies rather than
yap calling into a bp3 checkout: bp3-yap-skills is
deliberately dependency-light (Bash + yq + jq, "installed
skills have no runtime dependency") — a release tool that
requires a sibling repo would break the portability the
library exists for. So bp3 owns the *source*, each repo
carries a runnable copy, and the source line makes copies
auditable. The known cost is drift; it is priced here, not
hidden: sync is a manual copy, and the day that hurts, the
fix is a sync check in `yap check`, not a shared runtime.
Why one mechanism may serve both: everything except the
artifact is identical — version source, tag gate, checksum,
publish-once, refusal shapes. What differs stays in
`release.conf`: where the version lives (OCaml constant vs
`VERSION` file) and what packaging means (dune binary vs
`yap plugin`). Cross-repo note: this exp writes in two
repos; the yap-side commit lands in bp3-yap-skills under
its own workflow, and this quest's ledger records only the
bp3-side verdicts.

## Tests

unit: none (shell plumbing) · fixtures: release-check
refusal/agreement cases in both repos' test homes
(scratch tags in throwaway clones — never test tags on the
real remotes) · demos: the traces above, dry-run first
