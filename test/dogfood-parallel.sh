#!/usr/bin/env bash
# dogfood.2 parallel-drive: one ready-set, two flappy variants.
# Two independent nodes claim separate links in separate desks,
# build and grade in parallel, then land through the serial
# queue. The scorecard is computed from the workers' own
# timestamps and the bp3 rollup; a fixture conflict serializes
# at land instead of overwriting.
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
lk() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness link "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
now_ms() { node -e 'process.stdout.write(String(Date.now()))'; }
es() { MUSE_SESSION_ID="$1" BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 e "${@:2}"; }

commit_file_on_exp() { # <exp> <path> <file> -> new exp-branch tip
  local exp=$1 path=$2 file=$3 branch="refs/heads/bp3/exp/par/$1"
  local tip blob tree new_tip idx="$work/idx-$1"
  tip=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(git hash-object -w "$file")
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$exp" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"; rm -f "$idx"
  printf '%s' "$new_tip"
}
commit_on_graph() { # <graph> <exp> <path> <content> -> new exp-branch tip
  local graph=$1 exp=$2 path=$3 content=$4
  local branch="refs/heads/bp3/exp/$graph/$exp" tip blob tree new_tip idx="$work/idx-$graph-$exp"
  tip=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(printf '%s' "$content" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$exp" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"; rm -f "$idx"
  printf '%s' "$new_tip"
}
flappy_write() { # <file> <variant> <sky>
  cat > "$1" <<HTML
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Flappy — $2</title>
<script type="importmap">{ "imports": { "three": "https://unpkg.com/three@0.160.0/build/three.module.js" } }</script>
</head><body><div id="hud">Score <b id="score">0</b></div>
<script type="module">
import * as THREE from 'three';
const scene = new THREE.Scene();
scene.background = new THREE.Color($3);
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 100);
camera.position.set(0, 0, 10);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(innerWidth, innerHeight);
document.body.appendChild(renderer.domElement);
const bird = new THREE.Mesh(new THREE.SphereGeometry(0.35, 24, 18),
  new THREE.MeshStandardMaterial({ color: 0xffd93d }));
bird.position.set(-2.5, 0, 0); scene.add(bird);
let vy = 0, started = false, alive = true;
addEventListener('pointerdown', () => { started = true; vy = 5.2; });
const clock = new THREE.Clock();
(function tick() { requestAnimationFrame(tick);
  const dt = Math.min(clock.getDelta(), 0.05);
  if (started && alive) { vy -= 13 * dt; bird.position.y += vy * dt; }
  renderer.render(scene, camera); })();
</script></body></html>
HTML
  sed -n '/<script type="module">/,/<\/script>/p' "$1" | sed '1d;$d' > "$1.mjs"
  node --check "$1.mjs" || fail "flappy $2 node --check"
  rm -f "$1.mjs"
}

# --- one ready-set: two independent variants, no deps ---
q c par >/dev/null
q par c flappy-day >/dev/null
q par c flappy-night >/dev/null
out=$(q r par)
echo "$out" | jq -e '.ready == ["flappy-day","flappy-night"]
  and .ready_set_waves == [["flappy-day","flappy-night"]] and .starved == []' >/dev/null \
  || fail "ready-set waves: $out"

# --- parallel author workers: claim, build, handoff, grade, verify ---
author_worker() { # <node> <session> <variant> <sky>
  local node=$1 session=$2 variant=$3 sky=$4
  local desk="$work/desk-$node"
  mkdir -p "$desk"
  now_ms > "$work/$node.start"
  local mint tok rid commit
  mint=$(lk mint --kind edge --graph par --node "$node" --edge handoff --depth 2 --desk "$desk")
  tok=$(echo "$mint" | jq -r .token); rid=$(echo "$mint" | jq -r .run_id)
  printf '%s' "$rid" > "$work/$node.run_id"
  MUSE_SESSION_ID="$session" lk claim "$tok" > "$work/$node.claim.json"
  flappy_write "$desk/$node.html" "$variant" "$sky"
  sleep 2
  commit=$(commit_file_on_exp "$node" "$node.html" "$desk/$node.html")
  printf '%s' "$commit" > "$work/$node.commit"
  es "$session" handoff --commit "$commit" --reason "flappy $variant" > "$work/$node.handoff.json"
  es "$session" grade --verdict ship --reason "artifact checked" > "$work/$node.grade.json"
  es "$session" verify --verdict pass --reason "node --check green" > "$work/$node.verify.json"
  now_ms > "$work/$node.end"
}
author_worker flappy-day sess-day day 0x87ceeb &
pid_day=$!
author_worker flappy-night sess-night night 0x0b1026 &
pid_night=$!
wait "$pid_day" || fail "flappy-day author worker"
wait "$pid_night" || fail "flappy-night author worker"

# true parallelism: intervals overlap, different claims and desks
day_start=$(cat "$work/flappy-day.start"); day_end=$(cat "$work/flappy-day.end")
night_start=$(cat "$work/flappy-night.start"); night_end=$(cat "$work/flappy-night.end")
(( day_start < night_end && night_start < day_end )) \
  || fail "author intervals do not overlap: day $day_start-$day_end night $night_start-$night_end"
day_rid=$(cat "$work/flappy-day.run_id"); night_rid=$(cat "$work/flappy-night.run_id")
[ "$day_rid" != "$night_rid" ] || fail "parallel claims share a run-id"
jq -e '.ok == true and .node == "flappy-day"' "$work/flappy-day.claim.json" >/dev/null || fail "day claim"
jq -e '.ok == true and .node == "flappy-night"' "$work/flappy-night.claim.json" >/dev/null || fail "night claim"

# isolation: each desk and each exp branch holds only its variant
[ -f "$work/desk-flappy-day/flappy-day.html" ] && [ ! -e "$work/desk-flappy-day/flappy-night.html" ] \
  || fail "day desk bleed"
[ -f "$work/desk-flappy-night/flappy-night.html" ] && [ ! -e "$work/desk-flappy-night/flappy-day.html" ] \
  || fail "night desk bleed"
git show "bp3/exp/par/flappy-day:flappy-day.html" | grep -q "Flappy — day" || fail "day branch artifact"
git show "bp3/exp/par/flappy-night:flappy-night.html" | grep -q "Flappy — night" || fail "night branch artifact"
if git cat-file -e "bp3/exp/par/flappy-day:flappy-night.html" 2>/dev/null; then fail "day branch holds night file"; fi
if git cat-file -e "bp3/exp/par/flappy-night:flappy-day.html" 2>/dev/null; then fail "night branch holds day file"; fi
rm -f .bp3-context.json
out=$(es sess-day)
echo "$out" | jq -e '.node == "flappy-day" and .source == "session"' >/dev/null || fail "day context: $out"
out=$(es sess-night)
echo "$out" | jq -e '.node == "flappy-night" and .source == "session"' >/dev/null || fail "night context: $out"

# quality floor: full matrix per node, no rung skipped
for n in flappy-day flappy-night; do
  jq -e '.state == "handed_off"' "$work/$n.handoff.json" >/dev/null || fail "$n handoff state"
  jq -e '.state == "handed_off"' "$work/$n.grade.json" >/dev/null || fail "$n grade state"
  jq -e '.state == "approved"' "$work/$n.verify.json" >/dev/null || fail "$n verify state"
  out=$(q par r "$n")
  echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "$n approved read: $out"
  git show "bp3/exp/par/$n:docs/quests/par/experiments/$n/ledger.jsonl" \
    | jq -s -e '([.[] | select(.edge == "grade" and .verdict == "ship")] | length == 1)
      and ([.[] | select(.edge == "verify" and .verdict == "pass")] | length == 1)' >/dev/null \
    || fail "$n grade matrix ledger"
done

# --- serial land: one at a time, second re-checks the new tip ---
out=$(q par u flappy-day land --reason "serial land 1")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "day land: $out"
tip1=$(git rev-parse bp3/quest/par)
out=$(q par r flappy-night)
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "night still approved: $out"
out=$(q par u flappy-night land --reason "serial land 2")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "night land: $out"
git merge-base --is-ancestor "$tip1" bp3/quest/par || fail "second land did not build on first tip"
git merge-base --is-ancestor "$(cat "$work/flappy-day.commit")" bp3/quest/par || fail "day commit not landed"
git merge-base --is-ancestor "$(cat "$work/flappy-night.commit")" bp3/quest/par || fail "night commit not landed"
[ "$(git show bp3/quest/par:flappy-day.html | grep -c 'Flappy — day')" = 1 ] || fail "quest tip day file"
[ "$(git show bp3/quest/par:flappy-night.html | grep -c 'Flappy — night')" = 1 ] || fail "quest tip night file"

# --- scorecard: wall from the run itself, timing from the rollup ---
ready_wall_ms=$(( (day_end > night_end ? day_end : night_end) - (day_start < night_start ? day_start : night_start) ))
serial_sum_ms=$(( (day_end - day_start) + (night_end - night_start) ))
(( ready_wall_ms < serial_sum_ms )) \
  || fail "ready-set wall $ready_wall_ms not below serial sum $serial_sum_ms"
out=$(q r par)
echo "$out" | jq -e '(.exps[] | select(.exp == "flappy-day") | .state == "landed" and (.timing.wall_s | type == "number"))
  and (.exps[] | select(.exp == "flappy-night") | .state == "landed" and (.timing.wall_s | type == "number"))
  and (.setup | map(select(.node == "flappy-day" or .node == "flappy-night")) | length >= 2)' >/dev/null \
  || fail "rollup scorecard fields: $out"
jq -n --argjson ready_wall_ms "$ready_wall_ms" --argjson serial_sum_ms "$serial_sum_ms" \
  --arg day_wall_s "$(echo "$out" | jq -r '.exps[] | select(.exp == "flappy-day") | .timing.wall_s')" \
  --arg night_wall_s "$(echo "$out" | jq -r '.exps[] | select(.exp == "flappy-night") | .timing.wall_s')" \
  '{ready_wall_ms: $ready_wall_ms, serial_sum_ms: $serial_sum_ms,
    wall_saved_ms: ($serial_sum_ms - $ready_wall_ms),
    nodes: {"flappy-day": {wall_s: ($day_wall_s | tonumber)},
            "flappy-night": {wall_s: ($night_wall_s | tonumber)}},
    tokens: null,
    tokens_note: "bp3 rollup reports no per-node token field; tokens are not invented"}' \
  > "$work/scorecard.json"
jq -e '.wall_saved_ms > 0 and .tokens == null and (.tokens_note | length > 0)' "$work/scorecard.json" >/dev/null \
  || fail "scorecard: $(cat "$work/scorecard.json")"
echo "scorecard: $(cat "$work/scorecard.json")"

# --- conflict fixture: one file, two nodes; land serializes, no overwrite ---
q c conf >/dev/null; q conf c touch-a >/dev/null; q conf c touch-b >/dev/null
CA=$(commit_on_graph conf touch-a shared.txt "A-side")
CB=$(commit_on_graph conf touch-b shared.txt "B-side")
for spec in "touch-a $CA" "touch-b $CB"; do
  n=${spec%% *}; c=${spec##* }
  q conf u "$n" handoff --commit "$c" --reason work >/dev/null
  q conf u "$n" grade --verdict ship --reason ok >/dev/null
  q conf u "$n" verify --verdict pass --reason ok >/dev/null
done
out=$(q conf u touch-a land --reason first)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "touch-a land: $out"
out=$(q conf u touch-b land --reason second)
echo "$out" | jq -e '.ok == true and .state == "todo" and .facts.land_conflict == true' >/dev/null \
  || fail "touch-b conflict named: $out"
[ "$(git show bp3/quest/conf:shared.txt)" = "A-side" ] || fail "conflict silently overwrote shared.txt"

# --- blocked variant starves only its dependents ---
q c parblk >/dev/null
q parblk c bx >/dev/null; q parblk c bw >/dev/null
q parblk c by --depends-on bx >/dev/null
q parblk u bx block --reason "choose storage shape" >/dev/null
out=$(q r parblk)
echo "$out" | jq -e '.ready == ["bw"] and .starved == [{"blocked":"bx","starved":["by"]}]' >/dev/null \
  || fail "blocked sibling isolation: $out"

echo "dogfood-parallel tests: ok"
