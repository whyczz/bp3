#!/usr/bin/env bash
# Runnable landing trial for 2026-11-25-draft-desk-guard.
# Runs entirely in a scratch mktemp -d sandbox with isolated BP3_DESKS_DIR
# and BP3_DB — never touches real ~/.bp3/desks, ~/.local/share/bp3/bp3.sqlite,
# or the host checkout.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$script_dir/../../../.." && pwd)
qbin="$repo_root/_build/default/src/quest/main.exe"
[ -x "$qbin" ] || { echo "FAIL: missing $qbin (run make check first)" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export BP3_DESKS_DIR="$work/desks"
export BP3_DB="$work/bp3.sqlite"
export BP3_HARNESS=agy
export BP3_MODEL=trial-model
unset BP3_DECIDER || true

say() { printf '\n==> %s\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

repo="$work/demo-repo"
mkdir -p "$repo/bin" "$repo/plans"
cp "$repo_root/bin/bp3" "$repo/bin/bp3"
cp "$repo_root"/plans/*.yaml "$repo/plans/"
git -C "$repo" init -q -b master
git -C "$repo" config user.email trial@bp3.local
git -C "$repo" config user.name "bp3 Trial"
echo "base" > "$repo/README.md"
git -C "$repo" add . && git -C "$repo" commit -qm "chore: base"

bp3_run() {
  (cd "$repo" && BP3_Q_BIN="$qbin" "$repo/bin/bp3" "$@")
}

say "Scenario 1: Draft desk lifecycle (prepare, target_dirty, CAS rebase land from inside desk, conflict abort)"
out=$(bp3_run harness desk list)
echo "$out"
echo "$out" | jq -e '.ok == true and .target_branch == "master" and .target_dirty == false' >/dev/null || fail "desk list clean"

out=$(bp3_run harness desk prepare --draft quest-alpha)
echo "$out"
dpath=$(echo "$out" | jq -r '.path')
echo "$out" | jq -e '.ok == true and .node == "(draft)" and .ref == "draft/quest-alpha"' >/dev/null || fail "prepare draft"

# Author a doc in the draft desk while master moves ahead with another commit
echo "# alpha" > "$dpath/alpha.md"
git -C "$dpath" add alpha.md && git -C "$dpath" commit -qm "docs: frame alpha"
echo "concurrent master note" > "$repo/note.md"
git -C "$repo" add note.md && git -C "$repo" commit -qm "docs: concurrent note"

# Land draft from INSIDE the draft desk itself (rebased onto moved master)
out=$(cd "$dpath" && env -u BP3_ROOT BP3_Q_BIN="$qbin" "$repo/bin/bp3" harness desk land --draft quest-alpha)
echo "$out"
echo "$out" | jq -e '.ok == true and .rebased == true and .landed == true and .released == true and .branch_deleted == true' >/dev/null || fail "rebased draft land"
[ -f "$repo/alpha.md" ] && [ -f "$repo/note.md" ] || fail "master missing landed draft files"

# Conflict refusal: clean rebase --abort -> E_MERGE_CONFLICT
cpath=$(bp3_run harness desk prepare --draft conflict-demo | jq -r '.path')
echo "draft-edit" > "$cpath/README.md"
git -C "$cpath" add README.md && git -C "$cpath" commit -qm "docs: draft edit"
echo "master-edit" > "$repo/README.md"
git -C "$repo" add README.md && git -C "$repo" commit -qm "docs: master edit"
if out=$(bp3_run harness desk land --draft conflict-demo 2>&1); then fail "conflict land should fail"; fi
echo "$out"
echo "$out" | jq -e '.error.code == "E_MERGE_CONFLICT"' >/dev/null || fail "conflict code"
[ -z "$(git -C "$cpath" status --short)" ] || fail "conflict left draft dirty"
bp3_run harness desk release --draft conflict-demo >/dev/null

say "Scenario 2: Tiered CAS bp3 release (parallel disjoint quests q1 + q2, --ff-only, doc_only drift, verify fail)"
land_node() {
  local q=$1 n=$2 msg=$3 bump=$4
  bp3_run q c "$q" --type direct >/dev/null
  bp3_run q "$q" c "$n" >/dev/null
  mkdir -p "$repo/docs/quests/$q"
  printf -- '---\nstatus: active\ndate: 2026-11-25\nbump: %s\n---\n\n# %s\n\nTL;DR\nTrial %s.\n' "$bump" "$q" "$q" > "$repo/docs/quests/$q/QUEST.md"
  echo "$msg" > "$repo/work-$q.txt"
  git -C "$repo" add . && git -C "$repo" commit -qm "$msg"
  local sha
  sha=$(git -C "$repo" rev-parse HEAD)
  bp3_run q "$q" n "$n" e handoff --commit "$sha" --reason "handoff" >/dev/null
  bp3_run q "$q" n "$n" e verify --verdict pass --reason "verify" >/dev/null
  bp3_run q "$q" n "$n" e land --reason "land" >/dev/null
}

m0=$(git -C "$repo" rev-parse master)
git -C "$repo" checkout -q -b quest/q1 "$m0"
land_node q1 n1 "feat: q1" minor
git -C "$repo" checkout -q -b quest/q2 "$m0"
land_node q2 n1 "feat: q2" minor
q2_sha=$(git -C "$repo" rev-parse quest/q2)
git -C "$repo" checkout -q master

# q1 fast-forwards cleanly to v0.1.0
out=$(BP3_DECIDER=human bp3_run release q1)
echo "$out" | jq '{ok,tag,strategy,drift_kind,attempts}'
echo "$out" | jq -e '.ok == true and .tag == "v0.1.0" and .strategy == "fast_forward"' >/dev/null || fail "q1 ff"

# q2 --ff-only refuses E_NOT_FAST_FORWARD
if out=$(BP3_DECIDER=human bp3_run release q2 --ff-only 2>&1); then fail "ff-only accepted"; fi
echo "$out" | jq '{ok,code:.error.code}'
echo "$out" | jq -e '.error.code == "E_NOT_FAST_FORWARD"' >/dev/null || fail "ff-only code"

# q2 with failing verify gate refuses E_VERIFY_FAILED with master untouched
before_m=$(git -C "$repo" rev-parse master)
if out=$(BP3_RELEASE_VERIFY_CMD="false" BP3_DECIDER=human bp3_run release q2 2>&1); then fail "bad verify accepted"; fi
echo "$out" | jq '{ok,code:.error.code,drift:.error.facts.drift_kind}'
echo "$out" | jq -e '.error.code == "E_VERIFY_FAILED"' >/dev/null || fail "verify fail code"
[ "$(git -C "$repo" rev-parse master)" = "$before_m" ] || fail "failed verify moved master"

# q2 with passing verify auto-merges cleanly via 2-parent merge commit preserving graded SHA as HEAD^2
out=$(BP3_RELEASE_VERIFY_CMD="test -f work-q1.txt && test -f work-q2.txt" BP3_DECIDER=human bp3_run release q2)
echo "$out" | jq '{ok,tag,strategy,drift_kind,verified_merged,attempts}'
echo "$out" | jq -e '.ok == true and .tag == "v0.2.0" and .strategy == "merge" and .drift_kind == "code" and .verified_merged == "custom"' >/dev/null || fail "q2 merge"
[ "$(git -C "$repo" rev-parse master^2)" = "$q2_sha" ] || fail "q2 graded SHA not preserved"

# Scenario 3: Doc-only drift on master skips code verify command
say "Scenario 3: Doc-only drift (docs/icebox/*.md) skips code verify command"
m2=$(git -C "$repo" rev-parse master)
git -C "$repo" checkout -q -b quest/q3 "$m2"
land_node q3 n1 "feat: q3" patch
git -C "$repo" checkout -q master
mkdir -p "$repo/docs/icebox"
echo "side idea" > "$repo/docs/icebox/2026-11-25-side.md"
git -C "$repo" add docs/icebox/2026-11-25-side.md && git -C "$repo" commit -qm "docs(icebox): side"
out=$(BP3_RELEASE_VERIFY_CMD="false" BP3_DECIDER=human bp3_run release q3)
echo "$out" | jq '{ok,tag,strategy,drift_kind,verified_merged}'
echo "$out" | jq -e '.ok == true and .tag == "v0.2.1" and .strategy == "merge" and .drift_kind == "doc_only"' >/dev/null || fail "doc_only merge"

printf '\nALL 3 SCENARIOS PASSED\n'
