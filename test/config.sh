#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/q-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q "$@"; }
h() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness "$@"; }
c() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 config "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
store="$work/repo/.git/bp3"

# --- help: documented flags, exit 0, no state read ---
out=$(c -h) || fail "config -h exit"
echo "$out" | grep -q -- "--source" || fail "config help names --source: $out"
echo "$out" | grep -q -- "--format" || fail "config help names --format: $out"
[ ! -e "$store" ] || fail "config -h created the store"

# --- strict argv: dup, unknown, =-form, stray, bad format value ---
if out=$(c --source --source 2>&1); then fail "dup --source accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "dup --source code: $out"
if out=$(c --bogus 2>&1); then fail "unknown flag accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "unknown flag code: $out"
if out=$(c --format=json 2>&1); then fail "--flag=value accepted"; fi
if out=$(c stray 2>&1); then fail "stray positional accepted"; fi
if out=$(c --format xml 2>&1); then fail "bad --format value accepted"; fi
[ ! -e "$store" ] || fail "usage errors created the store"

# --- outside a git repo: no store, typed refusal; help still works ---
mkdir -p "$work/nogit/bin"
cp "$root/bin/bp3" "$work/nogit/bin/"
if out=$(BP3_Q_BIN="$work/repo/q-bin" "$work/nogit/bin/bp3" config 2>&1); then fail "config outside git accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "outside-git code: $out"
BP3_Q_BIN="$work/repo/q-bin" "$work/nogit/bin/bp3" config -h >/dev/null || fail "config -h outside git"

# --- first write creates the tree (zero setup) ---
out=$(h record-init --run-id R0 --harness muse-code --quest demo --exp exp-1)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "record-init: $out"
[ -f "$store/config.json" ] || fail "first write did not create config.json"
for d in runs links by-session desks run-lifecycle-derivations; do
  [ -d "$store/$d" ] || fail "first write did not create $d/"
done
jq -e '.thresholds.setup_slow_s == 180 and .thresholds.depth_cap == 3 and (has("contexts") | not)' \
  "$store/config.json" >/dev/null || fail "default config.json shape: $(cat "$store/config.json")"
[ -z "$(git status --porcelain)" ] || fail "config tree dirtied git status: $(git status --porcelain)"
[ -z "$(git ls-files "$store")" ] || fail "config tree is tracked: $(git ls-files "$store")"

# --- view: defaults, empty contexts, derivations folded in ---
out=$(c)
echo "$out" | jq -e '.ok == true and .thresholds.setup_slow_s == 180 and .thresholds.depth_cap == 3
  and .contexts == [] and .desks == [] and .by_session_entries == 0 and .derivations >= 1' \
  >/dev/null || fail "empty view: $out"
echo "$out" | jq -e '.config_dir | endswith(".git/bp3")' >/dev/null || fail "config_dir: $out"
out=$(c --format table) || fail "config --format table exit"
echo "$out" | grep -q "contexts" || fail "table view names contexts: $out"

# --- run configs fold into contexts; provenance per context ---
cat > "$store/runs/run-a.json" <<'JSON'
{"run_id":"run-a","kind":"edge","graph":"g1","node":"n1","edge":"handoff","state":"minted","desk":".bp3/worktrees/g1/n1/run-a","creator":{"run_id":"root-1","depth":2,"harness":"muse-code","model":"m","minted_at":"2026-11-16T00:00:00Z","token_hash":"sha256:x"}}
JSON
cat > "$store/runs/run-b.json" <<'JSON'
{"run_id":"run-b","kind":"edge","graph":"g1","node":"n2","edge":"grade","state":"claimed","desk":".bp3/worktrees/g1/n2/run-b","creator":{"run_id":"root-1","depth":2,"harness":"muse-code","model":"m","minted_at":"2026-11-16T00:00:30Z","token_hash":"sha256:y"},"claim":{"session_id":"sess-b","pid":48151,"cwd":"/tmp/desk-b","claimed_at":"2026-11-16T00:01:00Z"}}
JSON
out=$(c)
echo "$out" | jq -e '(.contexts | length) == 2
  and .contexts[0].run_id == "run-a" and .contexts[0].session_id == null and .contexts[0].state == "minted"
  and .contexts[1].run_id == "run-b" and .contexts[1].session_id == "sess-b" and .contexts[1].edge == "grade"
  and (.desks | length) == 2 and .by_session_entries == 1' >/dev/null || fail "contexts view: $out"
out=$(c --source)
echo "$out" | jq -e '.contexts[0].source.verb == "link mint" and .contexts[0].source.ts == "2026-11-16T00:00:00Z"
  and .contexts[1].source.verb == "link claim" and .contexts[1].source.ts == "2026-11-16T00:01:00Z"' \
  >/dev/null || fail "--source provenance: $out"

# --- by-session index: derived, rebuilt after deletion ---
[ "$(cat "$store/by-session/sess-b")" = "run-b" ] || fail "by-session index content"
rm -rf "$store/by-session"
out=$(c)
echo "$out" | jq -e '(.contexts | length) == 2 and .by_session_entries == 1' >/dev/null \
  || fail "view after by-session deletion: $out"
[ "$(cat "$store/by-session/sess-b")" = "run-b" ] || fail "by-session index not rebuilt"

# --- a torn run config is skipped, never folded ---
echo '{not json' > "$store/runs/z-torn.json"
out=$(c)
echo "$out" | jq -e '(.contexts | length) == 2' >/dev/null || fail "torn run config folded: $out"
rm "$store/runs/z-torn.json"

# --- thresholds are local and honored by the view (enforcement
# in edge verdicts lands with mvp.1/mvp.3, per the door doc) ---
jq '.thresholds.setup_slow_s = 42' "$store/config.json" > "$store/config.json.tmp"
mv "$store/config.json.tmp" "$store/config.json"
out=$(c)
echo "$out" | jq -e '.thresholds.setup_slow_s == 42 and .thresholds.depth_cap == 3' >/dev/null \
  || fail "edited threshold not honored: $out"
[ -z "$(git status --porcelain)" ] || fail "threshold edit dirtied git status"

# --- desk prepare is also a first-write verb (fresh repo) ---
mkdir -p "$work/repo2/bin" "$work/repo2/plans"
cp "$root/bin/bp3" "$work/repo2/bin/"
cp "$root"/plans/*.yaml "$work/repo2/plans/"
cd "$work/repo2"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q c demo >/dev/null
out=$(BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness desk prepare demo exp-1 --run D1)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "desk prepare repo2: $out"
[ -f "$work/repo2/.git/bp3/config.json" ] || fail "desk prepare did not create the config tree"
cd "$work/repo"

# --- all worktrees resolve the same tree ---
git worktree add -q "$work/wt2" -b wt2
mkdir -p "$work/wt2/bin"
cp "$root/bin/bp3" "$work/wt2/bin/"
main_dir=$(c | jq -r .config_dir)
wt_dir=$(BP3_Q_BIN="$work/repo/q-bin" "$work/wt2/bin/bp3" config | jq -r .config_dir)
[ "$main_dir" = "$wt_dir" ] || fail "worktree config_dir differs: $main_dir vs $wt_dir"
out=$(BP3_Q_BIN="$work/repo/q-bin" "$work/wt2/bin/bp3" config)
echo "$out" | jq -e '(.contexts | length) == 2' >/dev/null || fail "worktree view contexts: $out"

# --- legacy doors fail open: no config required, no new warnings ---
out=$(q c demo)
echo "$out" | jq -e '.ok == true and (has("warnings") | not)' >/dev/null || fail "legacy create changed: $out"
if out=$(q c config 2>&1); then fail "quest named config accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved config slug code: $out"

# --- mkdir failure is attributed at its site, not swallowed ---
rm -rf "$store/runs"
chmod 500 "$store"
if out=$(c 2>&1); then chmod 700 "$store"; fail "view over unwritable store accepted"; fi
chmod 700 "$store"
echo "$out" | grep -q "EACCES" || fail "mkdir failure not attributed: $out"
out=$(c)
echo "$out" | jq -e '.ok == true and (.contexts | length) == 0' >/dev/null \
  || fail "view after store repair: $out"

echo "config tests: ok"
