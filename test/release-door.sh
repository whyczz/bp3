#!/usr/bin/env bash
# Fixture suite for top-level `bp3 release` (quest-promote-release cli.1):
# quest mode, --commit mode, atomic CAS (E_NOT_FAST_FORWARD + E_STALE_WORLD),
# GitHub Release vs local annotated tag, --publish-only recovery, --dry-run,
# --no-gh, self-mode gitx.ml sync + Warden 0 FP, host-mode VERSION sync.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
checks=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { checks=$((checks + 1)); }

qbin="$root/_build/default/src/quest/main.exe"
[ -x "$qbin" ] || fail "missing built binary $qbin"

export BP3_HARNESS=agy BP3_MODEL=test-model
unset BP3_DECIDER || true

make_host_repo() { # dir
  local d=$1
  mkdir -p "$d/plans"
  cp "$root"/plans/*.yaml "$d/plans/"
  git -C "$d" init -q -b master
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name "Test User"
  echo base > "$d/README.md"
  git -C "$d" add .
  git -C "$d" commit -qm "chore: base"
}

run_bp3() { # dir args...
  local d=$1; shift
  (cd "$d" && BP3_ROOT="$d" "$qbin" "$@")
}

# Verify top-level bin/bp3 wrapper dispatches `release`
out=$(BP3_Q_BIN="$qbin" "$root/bin/bp3" release -h) || fail "bin/bp3 release -h failed"
echo "$out" | grep -q "bp3 release" || fail "bin/bp3 release -h text: $out"; ok

land_one_node() { # dir quest node commit_msg [bump]
  local d=$1 q=$2 n=$3 msg=$4 bump=${5:-minor}
  run_bp3 "$d" q c "$q" --type direct >/dev/null
  run_bp3 "$d" q "$q" c "$n" >/dev/null
  mkdir -p "$d/docs/quests/$q"
  if [ "$bump" = "MISSING" ]; then
    printf -- '---\nstatus: active\ndate: 2026-11-23\n---\n\n# %s title\n\nTL;DR\nSummary for %s.\n' "$q" "$q" > "$d/docs/quests/$q/QUEST.md"
  else
    printf -- '---\nstatus: active\ndate: 2026-11-23\nbump: %s\n---\n\n# %s title\n\nTL;DR\nSummary for %s.\n' "$bump" "$q" "$q" > "$d/docs/quests/$q/QUEST.md"
  fi
  echo "$msg" >> "$d/work-$q.txt"
  git -C "$d" add .
  git -C "$d" commit -qm "$msg"
  local sha
  sha=$(git -C "$d" rev-parse HEAD)
  run_bp3 "$d" q "$q" n "$n" e handoff --commit "$sha" --reason "handoff" >/dev/null
  run_bp3 "$d" q "$q" n "$n" e verify --verdict pass --reason "verify" >/dev/null
  run_bp3 "$d" q "$q" n "$n" e land --reason "land" >/dev/null
}

# --- 1. Help & preflight refusals ---
r1="$work/host-local"
make_host_repo "$r1"

out=$(run_bp3 "$r1" release -h) || fail "release -h failed"
echo "$out" | grep -q "bp3 release" || fail "release -h text: $out"; ok

# Non-existent quest -> E_NOT_FOUND (exit 2)
if out=$(BP3_DECIDER=human run_bp3 "$r1" release nope 2>&1); then fail "unknown quest accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unknown quest code: $out"; ok

# Quest with unlanded node -> E_NOT_READY
run_bp3 "$r1" q c q-pending --type default >/dev/null
run_bp3 "$r1" q q-pending c n1 >/dev/null
if out=$(BP3_DECIDER=human run_bp3 "$r1" release q-pending 2>&1); then fail "pending quest accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_READY" and (.error.facts.pending_nodes | index("n1") != null)' >/dev/null || fail "pending code: $out"; ok

# Deleted quest -> E_ILLEGAL_EDGE
run_bp3 "$r1" q c q-del --type default >/dev/null
run_bp3 "$r1" q d q-del --reason "drop" >/dev/null
if out=$(BP3_DECIDER=human run_bp3 "$r1" release q-del 2>&1); then fail "deleted quest accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE"' >/dev/null || fail "deleted code: $out"; ok

# Commit mismatch & --bump none on --commit
if out=$(BP3_DECIDER=human run_bp3 "$r1" release --commit deadbeef9999 2>&1); then fail "bad commit accepted"; fi
echo "$out" | jq -e '.error.code == "E_COMMIT_MISMATCH"' >/dev/null || fail "bad commit code: $out"; ok

base_sha=$(git -C "$r1" rev-parse HEAD)
if out=$(BP3_DECIDER=human run_bp3 "$r1" release --commit "$base_sha" --bump none 2>&1); then fail "commit bump none accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "commit bump none code: $out"; ok

# --- 2. Dry-run & human gate & dirty tree & missing bump ---
land_one_node "$r1" q-nobump n1 "feat: nobump" "MISSING"
if out=$(BP3_DECIDER=human run_bp3 "$r1" release q-nobump 2>&1); then fail "missing bump accepted"; fi
echo "$out" | jq -e '.error.code == "E_BUMP_MISSING"' >/dev/null || fail "missing bump code: $out"; ok

# Dry-run works WITHOUT BP3_DECIDER, mutates nothing, and warns W_NO_REPO_CONFIG when backpack.toml is absent
before_head=$(git -C "$r1" rev-parse master)
out=$(run_bp3 "$r1" release q-nobump --bump minor --dry-run) || fail "dry-run failed: $out"
echo "$out" | jq -e '.ok == true and .dry_run == true and .version == "0.1.0" and .tag == "v0.1.0" and .release_kind == "git_tag" and .warnings[0].code == "W_NO_REPO_CONFIG"' >/dev/null || fail "dry-run json: $out"
[ "$(git -C "$r1" rev-parse master)" = "$before_head" ] || fail "dry-run moved master"
[ -z "$(git -C "$r1" tag -l)" ] || fail "dry-run created tag"; ok

# Missing BP3_DECIDER=human -> E_HUMAN_REQUIRED
if out=$(run_bp3 "$r1" release q-nobump --bump minor 2>&1); then fail "non-human accepted"; fi
echo "$out" | jq -e '.error.code == "E_HUMAN_REQUIRED"' >/dev/null || fail "human code: $out"; ok

# Dirty tree -> E_DIRTY_TREE
echo dirty >> "$r1/README.md"
if out=$(BP3_DECIDER=human run_bp3 "$r1" release q-nobump --bump minor 2>&1); then fail "dirty tree accepted"; fi
echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty code: $out"
git -C "$r1" checkout -- README.md; ok

# --- 3. Local-only untagged host repo release -> v0.1.0, QUEST.md landed, clean status, idempotent refusal ---
out=$(BP3_DECIDER=human run_bp3 "$r1" release q-nobump --bump minor) || fail "local quest release failed: $out"
echo "$out" | jq -e '.ok == true and .mode == "quest" and .version == "0.1.0" and .tag == "v0.1.0" and .release_kind == "git_tag" and .dry_run == false' >/dev/null || fail "local quest json: $out"
[ "$(git -C "$r1" cat-file -t v0.1.0)" = "tag" ] || fail "v0.1.0 not annotated"
[ "$(git -C "$r1" rev-parse 'v0.1.0^{commit}')" = "$(git -C "$r1" rev-parse master)" ] || fail "v0.1.0 != master"
[ -z "$(git -C "$r1" status --short)" ] || fail "tree dirty after release: $(git -C "$r1" status --short)"
grep -q '^status: landed$' "$r1/docs/quests/q-nobump/QUEST.md" || fail "QUEST.md not flipped to landed"
git -C "$r1" tag -l --format='%(contents)' v0.1.0 | grep -q 'Summary for q-nobump.' || fail "tag missing TL;DR"
git -C "$r1" tag -l --format='%(contents)' v0.1.0 | grep -q 'feat: nobump' || fail "tag missing node bullet"; ok

# Second run -> E_ALREADY_PROMOTED
if out=$(BP3_DECIDER=human run_bp3 "$r1" release q-nobump --bump minor 2>&1); then fail "double release accepted"; fi
echo "$out" | jq -e '.error.code == "E_ALREADY_PROMOTED" and .error.facts.tag == "v0.1.0"' >/dev/null || fail "already promoted: $out"; ok

# --- 4. Commit-hash bugfix release (default patch -> v0.1.1) + major bump (v1.0.0) + quest bump: none ---
echo fix1 >> "$r1/README.md"; git -C "$r1" add .; git -C "$r1" commit -qm "fix: tiny bug"
fix_sha=$(git -C "$r1" rev-parse HEAD)
out=$(BP3_DECIDER=human run_bp3 "$r1" release --commit "$fix_sha") || fail "commit patch release failed: $out"
echo "$out" | jq -e '.ok == true and .mode == "commit" and .bump == "patch" and .previous_tag == "v0.1.0" and .version == "0.1.1" and .tag == "v0.1.1" and .release_kind == "git_tag"' >/dev/null || fail "commit patch json: $out"
git -C "$r1" tag -l --format='%(contents)' v0.1.1 | grep -q 'fix: tiny bug' || fail "commit tag missing subject"; ok

# Table format preview works cleanly
out=$(run_bp3 "$r1" release --commit "$fix_sha" --bump major --dry-run --format table) || fail "table dry-run failed"
echo "$out" | grep -q "v1.0.0" || fail "table missing v1.0.0"; ok

# Quest with bump: none promotes with no tag
land_one_node "$r1" q-none n1 "docs: typo" "none"
out=$(BP3_DECIDER=human run_bp3 "$r1" release q-none) || fail "bump none failed: $out"
echo "$out" | jq -e '.ok == true and .bump == "none" and .tag == null and .release_kind == "none"' >/dev/null || fail "bump none json: $out"
[ "$(git -C "$r1" tag -l 'v*' | wc -l | tr -d ' ')" = "2" ] || fail "bump none created a tag"; ok

# --- 5. Parallel quests CAS: E_NOT_FAST_FORWARD + atomic E_STALE_WORLD ---
r2="$work/parallel"
make_host_repo "$r2"
m0=$(git -C "$r2" rev-parse master)

# Branch quest/q1 and quest/q2 off M0
git -C "$r2" checkout -q -b quest/q1 "$m0"
land_one_node "$r2" q1 n1 "feat: q1" "minor"
git -C "$r2" checkout -q -b quest/q2 "$m0"
land_one_node "$r2" q2 n1 "feat: q2" "minor"
git -C "$r2" checkout -q master

# q1 releases first -> v0.1.0
out=$(BP3_DECIDER=human run_bp3 "$r2" release q1) || fail "q1 release failed: $out"
echo "$out" | jq -e '.ok == true and .tag == "v0.1.0"' >/dev/null || fail "q1 json: $out"; ok

# q2 (still based on M0) refuses E_NOT_FAST_FORWARD
if out=$(BP3_DECIDER=human run_bp3 "$r2" release q2 2>&1); then fail "non-ff q2 accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FAST_FORWARD"' >/dev/null || fail "non-ff code: $out"; ok

# Rebase q2 onto master, then simulate concurrent CAS lock on refs/tags/v0.2.0 -> atomic E_STALE_WORLD
git -C "$r2" checkout -q quest/q2
git -C "$r2" rebase -q master
git -C "$r2" checkout -q master
before_m=$(git -C "$r2" rev-parse master)
mkdir -p "$r2/.git/refs/tags"
: > "$r2/.git/refs/tags/v0.2.0.lock"
if out=$(BP3_DECIDER=human run_bp3 "$r2" release q2 2>&1); then fail "locked CAS accepted"; fi
echo "$out" | jq -e '.error.code == "E_STALE_WORLD"' >/dev/null || fail "stale world code: $out"
[ "$(git -C "$r2" rev-parse master)" = "$before_m" ] || fail "atomic CAS moved master despite tag lock!"
rm -f "$r2/.git/refs/tags/v0.2.0.lock"; ok

# Retry q2 now succeeds cleanly at v0.2.0
out=$(BP3_DECIDER=human run_bp3 "$r2" release q2) || fail "q2 retry failed: $out"
echo "$out" | jq -e '.ok == true and .previous_tag == "v0.1.0" and .tag == "v0.2.0"' >/dev/null || fail "q2 retry json: $out"; ok

# --- 6. GitHub remote mode (bare remote + insteadOf + stubbed gh) + --no-gh + --publish-only ---
bare="$work/gh-bare.git"
git init -q --bare "$bare"
r3="$work/gh-repo"
make_host_repo "$r3"
git -C "$r3" remote add origin "https://github.com/whyczz/demo-gh.git"
git -C "$r3" config "url.$bare.insteadOf" "https://github.com/whyczz/demo-gh.git"
git -C "$r3" push -q -u origin master

mkdir -p "$work/fakebin"
cat > "$work/fakebin/gh" <<'GH'
#!/usr/bin/env bash
state=${GH_STATE:?}
mode=${GH_MODE:-ok}
case "$1 $2" in
  "release view") [ -f "$state/$3" ] ;;
  "release create")
    [ "$mode" = "fail" ] && { echo "simulated gh auth error" >&2; exit 1; }
    mkdir -p "$state"
    [ ! -f "$state/$3" ] || exit 1
    printf '%s\n' "$@" > "$state/$3"
    echo "https://github.com/whyczz/demo-gh/releases/tag/$3"
    ;;
  *) echo "unexpected gh: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$work/fakebin/gh"
mkdir -p "$work/gh-state"

# Happy GitHub Release
land_one_node "$r3" q-gh1 n1 "feat: gh1" "minor"
out=$(GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-gh1) || fail "gh release failed: $out"
echo "$out" | jq -e '.ok == true and .tag == "v0.1.0" and .release_kind == "github" and .repo == "whyczz/demo-gh" and .release_url == "https://github.com/whyczz/demo-gh/releases/tag/v0.1.0"' >/dev/null || fail "gh json: $out"
[ -f "$work/gh-state/v0.1.0" ] || fail "gh create not called"
[ "$(git -C "$bare" rev-parse 'v0.1.0^{commit}')" = "$(git -C "$r3" rev-parse master)" ] || fail "tag not pushed to remote"; ok

# --no-gh skips push and gh
land_one_node "$r3" q-nogh n1 "feat: nogh" "patch"
out=$(GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-nogh --no-gh) || fail "no-gh failed: $out"
echo "$out" | jq -e '.ok == true and .tag == "v0.1.1" and .release_kind == "git_tag" and .repo == null' >/dev/null || fail "no-gh json: $out"
[ ! -f "$work/gh-state/v0.1.1" ] || fail "--no-gh still called gh"; ok

# Failed gh -> E_GH_FAILED {local_tagged: true}, then --publish-only recovers!
land_one_node "$r3" q-recover n1 "feat: recover" "minor"
if out=$(GH_MODE=fail GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-recover 2>&1); then fail "failed gh accepted"; fi
echo "$out" | jq -e '.error.code == "E_GH_FAILED" and .error.facts.local_tagged == true and .error.facts.tag == "v0.2.0"' >/dev/null || fail "gh fail json: $out"
out=$(GH_MODE=ok GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-recover --publish-only) || fail "publish-only failed: $out"
echo "$out" | jq -e '.ok == true and .publish_only == true and .tag == "v0.2.0" and .release_kind == "github"' >/dev/null || fail "publish-only json: $out"
grep -q "Summary for q-recover." "$work/gh-state/v0.2.0" || fail "publish-only notes missing TL;DR"; ok

# Duplicate publish-only -> E_RELEASE_EXISTS
if out=$(GH_MODE=ok GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-recover --publish-only 2>&1); then fail "duplicate publish accepted"; fi
echo "$out" | jq -e '.error.code == "E_RELEASE_EXISTS"' >/dev/null || fail "release exists code: $out"; ok

# --- 7. Self-mode gitx.ml sync + scripts/release-check + Warden 0 post_land_bugfix ---
r4="$work/self-repo"
make_host_repo "$r4"
mkdir -p "$r4/src/quest" "$r4/bin" "$r4/scripts"
printf 'let bp3_version = "0.2.0"\n' > "$r4/src/quest/gitx.ml"
cp "$root/bin/bp3" "$r4/bin/bp3"
cp "$root/scripts/release-check" "$r4/scripts/release-check"
git -C "$r4" add .
git -C "$r4" commit -qm "chore: self files"
git -C "$r4" tag -a v0.2.0 -m "bp3 v0.2.0"

land_one_node "$r4" q-self n1 "feat: major self" "major"
out=$(BP3_DECIDER=human run_bp3 "$r4" release q-self --no-install) || fail "self release failed: $out"
echo "$out" | jq -e '.ok == true and .previous_tag == "v0.2.0" and .version == "1.0.0" and .tag == "v1.0.0"' >/dev/null || fail "self release json: $out"
grep -q 'let bp3_version = "1.0.0"' "$r4/src/quest/gitx.ml" || fail "gitx.ml not updated to 1.0.0"
rc_out=$("$r4/scripts/release-check") || fail "release-check failed after self release"
[ "$rc_out" = "1.0.0" ] || fail "release-check printed $rc_out (expected 1.0.0)"
w_out=$(run_bp3 "$r4" warden q-self --no-sessions) || fail "warden failed: $w_out"
plb=$(echo "$w_out" | jq -r '.counts.by_rule.post_land_bugfix // 0')
[ "$plb" = "0" ] || fail "warden flagged post_land_bugfix=$plb on release commit: $w_out"; ok

# --- 8. Host repo with tracked VERSION file ---
r5="$work/host-ver"
make_host_repo "$r5"
printf '0.5.0\n' > "$r5/VERSION"
git -C "$r5" add VERSION && git -C "$r5" commit -qm "chore: version file"
git -C "$r5" tag -a v0.5.0 -m "v0.5.0"
land_one_node "$r5" q-ver n1 "feat: bump version file" "minor"
out=$(BP3_DECIDER=human run_bp3 "$r5" release q-ver) || fail "host VERSION release failed: $out"
[ "$(cat "$r5/VERSION")" = "0.6.0" ] || fail "VERSION not updated to 0.6.0: $(cat "$r5/VERSION")"; ok

# --- 9. manifest.2: [release].target honored when --target omitted, overridden by --target, clears W_NO_REPO_CONFIG ---
r6="$work/host-target"
make_host_repo "$r6"
git -C "$r6" branch main
printf 'version = 1\nrepo = "host-target"\n\n[release]\ntarget = "main"\n' > "$r6/backpack.toml"
git -C "$r6" add backpack.toml && git -C "$r6" commit -qm "chore: backpack"
land_one_node "$r6" q-tgt n1 "feat: manifest target" "minor"
out=$(run_bp3 "$r6" release q-tgt --dry-run) || fail "manifest target dry-run failed: $out"
echo "$out" | jq -e '.ok == true and .target == "main" and (has("warnings") | not)' >/dev/null || fail "manifest target json: $out"; ok
out_ovr=$(run_bp3 "$r6" release q-tgt --target master --dry-run) || fail "override target dry-run failed: $out_ovr"
echo "$out_ovr" | jq -e '.ok == true and .target == "master"' >/dev/null || fail "override target json: $out_ovr"; ok

echo "release-door tests: ok ($checks checks)"
