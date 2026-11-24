#!/usr/bin/env bash
# Runnable landing trial for 2026-11-23-quest-promote-release.
# Scratch sandbox only (mktemp -d); never mutates this repo or ~/.local.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../../../.." && pwd)
qbin="$repo/_build/default/src/quest/main.exe"
[ -x "$qbin" ] || { echo "build main.exe first: make check" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export BP3_HARNESS=agy BP3_MODEL=trial
export BP3_AGY_SETTINGS="$work/agy-settings.json"
unset BP3_DECIDER || true

say() { printf '\n=== %s ===\n' "$*"; }
run_bp3() { local d=$1; shift; (cd "$d" && BP3_ROOT="$d" "$qbin" "$@"); }

make_repo() {
  local d=$1
  mkdir -p "$d/plans"
  cp "$repo"/plans/*.yaml "$d/plans/"
  git -C "$d" init -q -b master
  git -C "$d" config user.email trial@bp3.local
  git -C "$d" config user.name "bp3 Trial"
  echo base > "$d/README.md"
  git -C "$d" add . && git -C "$d" commit -qm "chore: init"
}

land_quest() {
  local d=$1 q=$2 msg=$3 bump=${4:-minor}
  run_bp3 "$d" q c "$q" --type direct >/dev/null
  run_bp3 "$d" q "$q" c n1 >/dev/null
  mkdir -p "$d/docs/quests/$q"
  printf -- '---\nstatus: active\ndate: 2026-11-23\nbump: %s\n---\n\n# %s\n\nTL;DR\nTrial summary for %s.\n' "$bump" "$q" "$q" > "$d/docs/quests/$q/QUEST.md"
  echo "$msg" >> "$d/$q.txt"
  git -C "$d" add . && git -C "$d" commit -qm "$msg"
  local sha
  sha=$(git -C "$d" rev-parse HEAD)
  run_bp3 "$d" q "$q" n n1 e handoff --commit "$sha" --reason "trial" >/dev/null
  run_bp3 "$d" q "$q" n n1 e verify --verdict pass --reason "trial" >/dev/null
  run_bp3 "$d" q "$q" n n1 e land --reason "trial" >/dev/null
}

say "1. Happy path: quest release (v0.1.0) + commit-hash patch release (v0.1.1)"
r1="$work/local-repo"
make_repo "$r1"
land_quest "$r1" q-demo "feat: add release trial" "minor"
echo "$ bp3 release q-demo --dry-run"
run_bp3 "$r1" release q-demo --dry-run | jq -c '{ok, mode, tag, bump, release_kind, dry_run}'
echo "$ bp3 release q-demo   # refused without BP3_DECIDER=human"
run_bp3 "$r1" release q-demo | jq -c '{ok, code: .error.code}' || true
echo "$ BP3_DECIDER=human bp3 release q-demo"
out=$(BP3_DECIDER=human run_bp3 "$r1" release q-demo)
echo "$out" | jq -c '{ok, tag, release_kind, state}'
echo "$out" | jq -e '.ok == true and .tag == "v0.1.0" and .release_kind == "git_tag"' >/dev/null
git -C "$r1" tag -l --format='%(contents)' v0.1.0 | head -n 6

echo fix > "$r1/fix.txt" && git -C "$r1" add . && git -C "$r1" commit -qm "fix: small bugfix"
fix_sha=$(git -C "$r1" rev-parse HEAD)
echo "$ BP3_DECIDER=human bp3 release --commit ${fix_sha:0:7}"
out=$(BP3_DECIDER=human run_bp3 "$r1" release --commit "$fix_sha")
echo "$out" | jq -c '{ok, mode, bump, previous_tag, tag}'
echo "$out" | jq -e '.ok == true and .tag == "v0.1.1" and .bump == "patch"' >/dev/null

say "2. Parallel quests CAS: E_NOT_FAST_FORWARD + atomic E_STALE_WORLD -> v0.2.0"
r2="$work/parallel-repo"
make_repo "$r2"
m0=$(git -C "$r2" rev-parse master)
git -C "$r2" checkout -q -b quest/q1 "$m0" && land_quest "$r2" q1 "feat: q1" "minor"
git -C "$r2" checkout -q -b quest/q2 "$m0" && land_quest "$r2" q2 "feat: q2" "minor"
git -C "$r2" checkout -q master
BP3_DECIDER=human run_bp3 "$r2" release q1 | jq -c '{q:"q1", ok, tag}'
echo "$ BP3_DECIDER=human bp3 release q2   # master moved -> E_NOT_FAST_FORWARD"
out=$(BP3_DECIDER=human run_bp3 "$r2" release q2 || true)
echo "$out" | jq -c '{q:"q2", ok, code: .error.code}'
echo "$out" | jq -e '.error.code == "E_NOT_FAST_FORWARD"' >/dev/null
git -C "$r2" checkout -q quest/q2 && git -C "$r2" rebase -q master && git -C "$r2" checkout -q master
mkdir -p "$r2/.git/refs/tags" && : > "$r2/.git/refs/tags/v0.2.0.lock"
echo "$ BP3_DECIDER=human bp3 release q2   # locked tag -> atomic E_STALE_WORLD"
out=$(BP3_DECIDER=human run_bp3 "$r2" release q2 || true)
echo "$out" | jq -c '{q:"q2-race", ok, code: .error.code}'
echo "$out" | jq -e '.error.code == "E_STALE_WORLD"' >/dev/null
rm -f "$r2/.git/refs/tags/v0.2.0.lock"
out=$(BP3_DECIDER=human run_bp3 "$r2" release q2)
echo "$out" | jq -c '{q:"q2-retry", ok, previous_tag, tag}'
echo "$out" | jq -e '.ok == true and .tag == "v0.2.0"' >/dev/null

say "3. GitHub Release failure & --publish-only recovery (stubbed gh + bare remote)"
bare="$work/gh.git" && git init -q --bare "$bare"
r3="$work/gh-repo" && make_repo "$r3"
git -C "$r3" remote add origin "https://github.com/whyczz/trial-gh.git"
git -C "$r3" config "url.$bare.insteadOf" "https://github.com/whyczz/trial-gh.git"
git -C "$r3" push -q -u origin master
mkdir -p "$work/fakebin" "$work/gh-state"
cat > "$work/fakebin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  "release view") [ -f "${GH_STATE:?}/$3" ] ;;
  "release create")
    [ "${GH_MODE:-ok}" = "fail" ] && { echo "offline" >&2; exit 1; }
    touch "${GH_STATE:?}/$3"
    echo "https://github.com/whyczz/trial-gh/releases/tag/$3" ;;
esac
GH
chmod +x "$work/fakebin/gh"
land_quest "$r3" q-gh "feat: gh release" "minor"
out=$(GH_MODE=fail GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-gh || true)
echo "$out" | jq -c '{ok, code: .error.code, local_tagged: .error.facts.local_tagged}'
echo "$out" | jq -e '.error.code == "E_GH_FAILED" and .error.facts.local_tagged == true' >/dev/null
out=$(GH_MODE=ok GH_STATE="$work/gh-state" PATH="$work/fakebin:$PATH" BP3_DECIDER=human run_bp3 "$r3" release q-gh --publish-only)
echo "$out" | jq -c '{ok, publish_only, tag, release_kind, release_url}'
echo "$out" | jq -e '.ok == true and .publish_only == true and .release_kind == "github"' >/dev/null

say "4. Tag-gated self install -> host SessionStart auto-sync (clean vs dirty)"
self_r="$work/self"
mkdir -p "$self_r/src/quest" "$self_r/bin" "$self_r/scripts" "$self_r/plans" "$self_r/completions"
cp "$repo/bin/bp3" "$self_r/bin/"
cp "$repo/scripts/install-bp3.sh" "$repo/scripts/release-check" "$repo/scripts/check-skills" "$repo/scripts/agy-statusline" "$self_r/scripts/"
cp -R "$repo/skills" "$self_r/skills"
cp "$repo"/plans/*.yaml "$self_r/plans/"
cp "$repo"/completions/* "$self_r/completions/"
printf 'let bp3_version = "0.2.0"\n' > "$self_r/src/quest/gitx.ml"
git -C "$self_r" init -q -b master
git -C "$self_r" config user.email trial@bp3.local && git -C "$self_r" config user.name "bp3 Trial"
git -C "$self_r" add . && git -C "$self_r" commit -qm "base" && git -C "$self_r" tag -a v0.2.0 -m "v0.2.0"
land_quest "$self_r" q-self "feat: self v0.3.0" "minor"
prefix="$work/prefix"
out=$(PREFIX="$prefix" BP3_RELEASE_ARTIFACT="$qbin" BP3_DECIDER=human run_bp3 "$self_r" release q-self --no-gh)
echo "$out" | jq -c '{ok, tag, installed_prefix}'
cat "$prefix/share/bp3/RELEASE"

host="$work/predictor-sim"
mkdir -p "$host/.agents/skills/quest"
git -C "$host" init -q -b master
git -C "$host" config user.email trial@bp3.local && git -C "$host" config user.name "bp3 Trial"
printf -- '---\nname: quest\ndescription: old\n---\n<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=agy. -->\nold\n' > "$host/.agents/skills/quest/SKILL.md"
git -C "$host" add . && git -C "$host" commit -qm "old skills"
payload='{"hook_event_name":"SessionStart","session_id":"s1","cwd":"'"$host"'"}'
out=$(printf '%s\n' "$payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks)
echo "$out" | jq -c '{ok, auto_sync}'
echo "$out" | jq -e '.auto_sync.status == "synced" and .auto_sync.tag == "v0.3.0"' >/dev/null
git -C "$host" show -s --format='commit: %h %s' HEAD

jq '.tag = "v0.4.0" | .version = "0.4.0"' "$prefix/share/bp3/RELEASE" > "$prefix/share/bp3/RELEASE.tmp"
mv "$prefix/share/bp3/RELEASE.tmp" "$prefix/share/bp3/RELEASE"
echo wip > "$host/wip.txt"
out=$(printf '%s\n' "$payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks)
echo "$out" | jq -c '{ok, auto_sync}'
echo "$out" | jq -e '.auto_sync.status == "dirty_skipped" and .auto_sync.warning == "W_BP3_UPDATE_AVAILABLE"' >/dev/null

printf '\ntrial: ALL 4 SCENARIOS PASSED\n'
