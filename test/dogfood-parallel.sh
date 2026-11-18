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
cp "$root/_build/default/src/graph/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_G_BIN="$work/repo/g-bin" ./bin/bp3 g "$@"; }
lk() { BP3_G_BIN="$work/repo/g-bin" ./bin/bp3 harness link "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
now_ms() { node -e 'process.stdout.write(String(Date.now()))'; }
es() { MUSE_SESSION_ID="$1" BP3_G_BIN="$work/repo/g-bin" ./bin/bp3 e "${@:2}"; }

commit_file_on_node() { # <node> <path> <file> -> new node-branch tip
  local node=$1 path=$2 file=$3 branch="refs/heads/bp3/node/par/$1"
  local tip blob tree new_tip idx="$work/idx-$1"
  tip=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(git hash-object -w "$file")
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$node" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"; rm -f "$idx"
  printf '%s' "$new_tip"
}
commit_on_graph() { # <graph> <node> <path> <content> -> new node-branch tip
  local graph=$1 node=$2 path=$3 content=$4
  local branch="refs/heads/bp3/node/$graph/$node" tip blob tree new_tip idx="$work/idx-$graph-$node"
  tip=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(printf '%s' "$content" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$node" | git commit-tree "$tree" -p "$tip")
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

# --- parallel author workers: claim, build, handoff, one combined grade cast ---
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
  commit=$(commit_file_on_node "$node" "$node.html" "$desk/$node.html")
  printf '%s' "$commit" > "$work/$node.commit"
  es "$session" handoff --commit "$commit" --reason "flappy $variant" > "$work/$node.handoff.json"
  es "$session" grade --verdict ship --verify-verdict pass --commit "$commit" --reason "grade ship; verify pass" > "$work/$node.grade.json"
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

# isolation: each desk and each node branch holds only its variant
[ -f "$work/desk-flappy-day/flappy-day.html" ] && [ ! -e "$work/desk-flappy-day/flappy-night.html" ] \
  || fail "day desk bleed"
[ -f "$work/desk-flappy-night/flappy-night.html" ] && [ ! -e "$work/desk-flappy-night/flappy-day.html" ] \
  || fail "night desk bleed"
git show "bp3/node/par/flappy-day:flappy-day.html" | grep -q "Flappy — day" || fail "day branch artifact"
git show "bp3/node/par/flappy-night:flappy-night.html" | grep -q "Flappy — night" || fail "night branch artifact"
if git cat-file -e "bp3/node/par/flappy-day:flappy-night.html" 2>/dev/null; then fail "day branch holds night file"; fi
if git cat-file -e "bp3/node/par/flappy-night:flappy-day.html" 2>/dev/null; then fail "night branch holds day file"; fi
rm -f .bp3-context.json
out=$(es sess-day)
echo "$out" | jq -e '.node == "flappy-day" and .source == "session"' >/dev/null || fail "day context: $out"
out=$(es sess-night)
echo "$out" | jq -e '.node == "flappy-night" and .source == "session"' >/dev/null || fail "night context: $out"

# quality floor: full matrix per node, no rung skipped
for n in flappy-day flappy-night; do
  jq -e '.state == "handed_off"' "$work/$n.handoff.json" >/dev/null || fail "$n handoff state"
  jq -e '.state == "approved"' "$work/$n.grade.json" >/dev/null || fail "$n grade state"
  out=$(q par r "$n")
  echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "$n approved read: $out"
  git show "bp3/node/par/$n:docs/graphs/par/nodes/$n/ledger.jsonl" \
    | jq -s -e '([.[] | select(.edge == "grade" and .verdict == "ship")] | length == 1)
      and ([.[] | select(.edge == "grade" and .verdict == "ship")][0].verify_verdict == "pass")
      and ([.[] | select(.edge == "verify")] | length == 0)' >/dev/null \
    || fail "$n grade matrix ledger"
done

# --- serial land: one at a time, second re-checks the new tip ---
out=$(q par u flappy-day land --reason "serial land 1")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "day land: $out"
tip1=$(git rev-parse bp3/graph/par)
out=$(q par r flappy-night)
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "night still approved: $out"
out=$(q par u flappy-night land --reason "serial land 2")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "night land: $out"
git merge-base --is-ancestor "$tip1" bp3/graph/par || fail "second land did not build on first tip"
git merge-base --is-ancestor "$(cat "$work/flappy-day.commit")" bp3/graph/par || fail "day commit not landed"
git merge-base --is-ancestor "$(cat "$work/flappy-night.commit")" bp3/graph/par || fail "night commit not landed"
[ "$(git show bp3/graph/par:flappy-day.html | grep -c 'Flappy — day')" = 1 ] || fail "graph tip day file"
[ "$(git show bp3/graph/par:flappy-night.html | grep -c 'Flappy — night')" = 1 ] || fail "graph tip night file"

# --- scorecard: wall from the run itself, timing from the rollup ---
ready_wall_ms=$(( (day_end > night_end ? day_end : night_end) - (day_start < night_start ? day_start : night_start) ))
serial_sum_ms=$(( (day_end - day_start) + (night_end - night_start) ))
(( ready_wall_ms < serial_sum_ms )) \
  || fail "ready-set wall $ready_wall_ms not below serial sum $serial_sum_ms"
out=$(q r par)
echo "$out" | jq -e '(.nodes[] | select(.node == "flappy-day") | .state == "landed" and (.timing.wall_s | type == "number"))
  and (.nodes[] | select(.node == "flappy-night") | .state == "landed" and (.timing.wall_s | type == "number"))
  and (.setup | map(select(.node == "flappy-day" or .node == "flappy-night")) | length >= 2)' >/dev/null \
  || fail "rollup scorecard fields: $out"
jq -n --argjson ready_wall_ms "$ready_wall_ms" --argjson serial_sum_ms "$serial_sum_ms" \
  --arg day_wall_s "$(echo "$out" | jq -r '.nodes[] | select(.node == "flappy-day") | .timing.wall_s')" \
  --arg night_wall_s "$(echo "$out" | jq -r '.nodes[] | select(.node == "flappy-night") | .timing.wall_s')" \
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
[ "$(git show bp3/graph/conf:shared.txt)" = "A-side" ] || fail "conflict silently overwrote shared.txt"

# --- blocked variant starves only its dependents ---
q c parblk >/dev/null
q parblk c bx >/dev/null; q parblk c bw >/dev/null
q parblk c by --depends-on bx >/dev/null
q parblk u bx block --reason "choose storage shape" >/dev/null
out=$(q r parblk)
echo "$out" | jq -e '.ready == ["bw"] and .starved == [{"blocked":"bx","starved":["by"]}]' >/dev/null \
  || fail "blocked sibling isolation: $out"

# --- Pi bubble + Muse parity bubble in the parallel drive (cycle 2) ---
# One seeded node takes a human-blocking edge in each engine
# form while its sibling keeps moving in the same ready-set.
# Pi form: real OS processes (edge worker dies, node worker
# records blocked and exits, exactly one bubble, no descendant
# process remains; resume + a fresh Pi tree continues it).
# Muse form: the real bp3g-node workflow returns the same
# terminal blocked bubble and exits; revival is a fresh
# workflow, never a resume of the old run's agents. Evidence
# is timestamps and the process table, not state inference.
cat > "$work/bubble-drive.mjs" <<'BUBBLE_JS'
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
const repo = process.cwd();
const root = process.env.BP3_ROOT;
const work = process.env.BP3_WORK;
let failures = 0;
function assert(c, m) { if (!c) { console.error("FAIL: " + m); failures++; } }
function alive(pid) { try { process.kill(pid, 0); return true; } catch { return false; } }
async function waitDead(pid, ms = 5000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (!alive(pid)) return true; await new Promise((r) => setTimeout(r, 50)); }
  return !alive(pid);
}
const env = { ...process.env, BP3_HARNESS: "muse-code", BP3_MODEL: "test-model", BP3_G_BIN: path.join(repo, "g-bin") };
function bp3(args, extra = {}) {
  const out = execFileSync(path.join(repo, "bin", "bp3"), args, { cwd: repo, encoding: "utf8", env: { ...env, ...extra } });
  return JSON.parse(out.trim().split("\n").pop() ?? "{}");
}
function sh(cmd, extra = {}) {
  const out = execFileSync("bash", ["-c", cmd], { cwd: repo, encoding: "utf8", env: { ...env, ...extra } });
  return out.trim().split("\n").pop() ?? "";
}
const commonDir = execFileSync("git", ["-C", repo, "rev-parse", "--git-common-dir"], { encoding: "utf8" }).trim();
const runsDir = path.join(path.isAbsolute(commonDir) ? commonDir : path.join(repo, commonDir), "bp3", "runs");
function commitFor(graph, node) {
  const branch = "refs/heads/bp3/node/" + graph + "/" + node;
  const tip = execFileSync("git", ["rev-parse", branch], { cwd: repo, encoding: "utf8" }).trim();
  const blob = execFileSync("git", ["hash-object", "-w", "--stdin"], { cwd: repo, encoding: "utf8", input: node + " work\n" }).trim();
  const idx = path.join(work, "idx-" + graph + "-" + node + "-" + Date.now() + "-" + Math.random().toString(36).slice(2));
  const genv = { ...env, GIT_INDEX_FILE: idx };
  execFileSync("git", ["read-tree", tip], { cwd: repo, env: genv });
  execFileSync("git", ["update-index", "--add", "--cacheinfo", "100644," + blob + "," + node + ".txt"], { cwd: repo, env: genv });
  const tree = execFileSync("git", ["write-tree"], { cwd: repo, encoding: "utf8", env: genv }).trim();
  const nt = execFileSync("git", ["commit-tree", tree, "-p", tip], { cwd: repo, encoding: "utf8", input: "work " + node + "\n" }).trim();
  execFileSync("git", ["update-ref", branch, nt, tip], { cwd: repo, env: genv });
  try { fs.rmSync(idx); } catch {}
  return nt;
}
// Pi workers: real processes, claim first, then work.
const nodeWorker = path.join(work, "pi-node-worker.mjs");
fs.writeFileSync(nodeWorker, [
  'import { execFileSync, spawn } from "node:child_process";',
  'import fs from "node:fs";',
  'const [mode, graph, node, token, bubblePath, scratch] = process.argv.slice(2);',
  'const bp3 = (a) => JSON.parse(execFileSync("./bin/bp3", a, { encoding: "utf8", env: process.env }).trim().split("\\n").pop());',
  'bp3(["harness", "link", "claim", token]);',
  'const myRun = JSON.parse(fs.readFileSync(process.env.BP3_RUN_CFG, "utf8")).run_id;',
  'const minted = bp3(["harness", "link", "mint", "--kind", "edge", "--graph", graph, "--node", node, "--edge", "handoff", "--harness", "pi", "--model", "test-model", "--cycle", "1", "--desk", process.cwd(), "--parent-run-id", myRun]);',
  'const resultFile = scratch + ".edge.json";',
  'const child = spawn(process.execPath, [process.env.EDGE_WORKER, mode, graph, node, minted.token, resultFile], { stdio: "inherit" });',
  'fs.writeFileSync(scratch + ".edge.pid", String(child.pid));',
  'const code = await new Promise((r) => child.once("exit", r));',
  'let er = null; try { er = JSON.parse(fs.readFileSync(resultFile, "utf8")); } catch {}',
  'const chain = [myRun, minted.run_id];',
  'if (er && er.ok === false) {',
  '  bp3(["g", graph, "u", node, "block", "--reason", er.reason]);',
  '  fs.appendFileSync(bubblePath, JSON.stringify({ graph, node, state: "blocked", reason: er.reason, last_edge: "handoff", run_chain: chain, desk: process.cwd(), inbox_key: graph + "/" + node }) + "\\n");',
  '  process.exit(0);',
  '}',
  'const after = bp3(["g", graph, "r", node]);',
  'fs.appendFileSync(bubblePath, JSON.stringify({ graph, node, state: after.state, reason: null, last_edge: "handoff", run_chain: chain, desk: process.cwd(), inbox_key: graph + "/" + node }) + "\\n");',
  'process.exit(0);',
  "",
].join("\n"));
const edgeWorker = path.join(work, "pi-edge-worker.mjs");
fs.writeFileSync(edgeWorker, [
  'import { execFileSync } from "node:child_process";',
  'import fs from "node:fs";',
  'import path from "node:path";',
  'const [mode, graph, node, token, resultFile] = process.argv.slice(2);',
  'const bp3 = (a, e = {}) => JSON.parse(execFileSync("./bin/bp3", a, { encoding: "utf8", env: { ...process.env, ...e } }).trim().split("\\n").pop());',
  'bp3(["harness", "link", "claim", token]);',
  'if (mode === "block-fail") {',
  '  fs.writeFileSync(resultFile, JSON.stringify({ ok: false, kind: "typed_failure", code: "E_DECISION", reason: "choose storage shape" }));',
  '} else if (mode === "handoff") {',
  '  const branch = "refs/heads/bp3/node/" + graph + "/" + node;',
  '  const tip = execFileSync("git", ["rev-parse", branch], { encoding: "utf8" }).trim();',
  '  const blob = execFileSync("git", ["hash-object", "-w", "--stdin"], { encoding: "utf8", input: node + " fresh\\n" }).trim();',
  '  const idx = path.join(process.env.BP3_WORK, "idx-pi-" + node + "-" + Date.now());',
  '  const ge = { ...process.env, GIT_INDEX_FILE: idx };',
  '  execFileSync("git", ["read-tree", tip], { env: ge });',
  '  execFileSync("git", ["update-index", "--add", "--cacheinfo", "100644," + blob + "," + node + ".txt"], { env: ge });',
  '  const tree = execFileSync("git", ["write-tree"], { encoding: "utf8", env: ge }).trim();',
  '  const nt = execFileSync("git", ["commit-tree", tree, "-p", tip], { encoding: "utf8", input: "fresh " + node + "\\n" }).trim();',
  '  execFileSync("git", ["update-ref", branch, nt, tip], { env: ge });',
  '  bp3(["g", graph, "u", node, "handoff", "--commit", nt, "--reason", "fresh tree work"]);',
  '  fs.writeFileSync(resultFile, JSON.stringify({ ok: true }));',
  '}',
  "",
].join("\n"));
function spawnPi(mode, graph, node, bubblePath, scratch) {
  const minted = bp3(["harness", "link", "mint", "--kind", "node", "--graph", graph, "--node", node, "--harness", "pi", "--model", "test-model", "--cycle", "1", "--desk", repo]);
  const child = spawn(process.execPath, [nodeWorker, mode, graph, node, minted.token, bubblePath, scratch], {
    cwd: repo, env: { ...env, BP3_RUN_ID: minted.run_id, BP3_RUN_CFG: path.join(runsDir, minted.run_id + ".json"), EDGE_WORKER: edgeWorker }, stdio: "inherit",
  });
  return { child, runId: minted.run_id, pid: child.pid, started: Date.now() };
}
const exitOf = (c) => new Promise((r) => c.once("exit", r));
// Claims write .bp3-context.json at the desk root (the repo
// here); ignore it so the handoff dirty-tree check stays clean.
fs.writeFileSync(path.join(repo, ".gitignore"), ".bp3-context.json\n");
execFileSync("git", ["add", ".gitignore"], { cwd: repo, env });
execFileSync("git", ["commit", "-qm", "ignore bp3 context"], { cwd: repo, env });
// --- Pi form in parallel: seeded blocks, sibling lands handed_off ---
bp3(["g", "c", "bubpi"]); bp3(["g", "bubpi", "c", "seeded-pi"]); bp3(["g", "bubpi", "c", "sib-pi"]);
const piBubbles = path.join(work, "pi-bubbles.jsonl");
const piT0 = Date.now();
const piSeed = spawnPi("block-fail", "bubpi", "seeded-pi", piBubbles, path.join(work, "pi-seed"));
const piSib = spawnPi("handoff", "bubpi", "sib-pi", piBubbles, path.join(work, "pi-sib"));
assert((await exitOf(piSeed.child)) === 0, "Pi seeded node worker exits 0 on block");
assert((await exitOf(piSib.child)) === 0, "Pi sibling node worker exits 0");
const piT1 = Date.now();
const piLines = fs.readFileSync(piBubbles, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const piSeedBubbles = piLines.filter((b) => b.node === "seeded-pi");
assert(piSeedBubbles.length === 1, "Pi exactly one bubble, got " + piSeedBubbles.length);
const pb = piSeedBubbles[0];
assert(pb && pb.state === "blocked" && pb.reason === "choose storage shape" && pb.last_edge === "handoff" && pb.inbox_key === "bubpi/seeded-pi" && Array.isArray(pb.run_chain) && pb.run_chain.length === 2 && !("pid" in pb), "Pi bubble facts only: " + JSON.stringify(pb));
assert(await waitDead(piSeed.pid), "Pi node worker pid dead after bubble");
const piEdgePid = Number(fs.readFileSync(path.join(work, "pi-seed.edge.pid"), "utf8"));
assert(await waitDead(piEdgePid), "Pi edge worker pid dead after bubble (process table)");
assert(await waitDead(piSib.pid), "Pi sibling tree dead after its bubble");
assert(bp3(["g", "bubpi", "r", "seeded-pi"]).state === "blocked", "Pi seeded rests blocked");
assert(bp3(["g", "bubpi", "r", "sib-pi"]).state === "handed_off", "Pi sibling unaffected: handed_off while seeded blocked");
assert(bp3(["g", "r", "bubpi"]).inbox.filter((i) => i.node === "seeded-pi").length === 1, "Pi exactly one inbox entry");
const piResumed = bp3(["g", "bubpi", "u", "seeded-pi", "resume", "--reason", "use localStorage"], { BP3_DECIDER: "human" });
assert(piResumed.ok === true && piResumed.state === "todo", "Pi resume revives to todo");
const piFresh = spawnPi("handoff", "bubpi", "seeded-pi", piBubbles, path.join(work, "pi-seed2"));
assert((await exitOf(piFresh.child)) === 0, "Pi fresh tree exits 0");
assert(piFresh.runId !== piSeed.runId && piFresh.pid !== piSeed.pid, "Pi revival is a fresh tree: new run-id and pid");
assert(await waitDead(piFresh.pid), "Pi fresh tree dead after revival bubble");
assert(bp3(["g", "bubpi", "r", "seeded-pi"]).state === "handed_off", "Pi fresh tree continues node to handed_off");
assert(bp3(["g", "bubpi", "r", "sib-pi"]).state === "handed_off", "Pi sibling still unaffected after revival");
// --- Muse form in parallel: real bp3g-node workflow, same bubble ---
const workflow = (await import(pathToFileURL(path.join(root, "skills/bp3g/workflows/bp3g-node.js")).href)).default;
bp3(["g", "c", "bubcl"]); bp3(["g", "bubcl", "c", "seeded-cl"]); bp3(["g", "bubcl", "c", "sib-cl"]);
function extractCmd(input) { const i = input.indexOf("Run exactly `"); if (i < 0) return ""; const s = i + "Run exactly `".length; const e = input.indexOf("`", s); return e < 0 ? "" : input.slice(s, e); }
function makeClaudeHost(node, blockMode) {
  const host = { calls: 0, edgeCalls: {}, blockCalls: 0, args: { graph: "bubcl", node: node, ts: "20261117T000000Z", harness: "muse-code", model: "test-model", desk: repo },
    async agent({ label, input }) {
      host.calls++;
      const kind = label.split(" ")[0];
      if (kind === "read" || kind === "mint" || kind === "bind" || kind === "block") {
        if (kind === "block") host.blockCalls++;
        if (kind === "bind") {
          try { return sh(extractCmd(input)); } catch (e) { return JSON.stringify({ ok: false, error: { code: "E_BIND" } }); }
        }
        return sh(extractCmd(input));
      }
      if (kind === "resolve") {
        const tp = path.join(work, "claude-tape-" + node + "-" + host.calls + ".jsonl");
        fs.writeFileSync(tp, "{}\n");
        const m = input.match(/--run-id (\S+)/);
        return JSON.stringify({ ok: true, run_id: m ? m[1] : "", tape_path: tp });
      }
      if (kind === "apply") {
        // Looper apply child (followup.5): its spawn text is the
        // one combined cast itself, with no link token to claim;
        // run it and return its stdout JSON verdict.
        try { return sh(extractCmd(input)); } catch (e) {
          const out = ((e.stdout || "") + "").trim().split("\n").pop();
          return out || JSON.stringify({ ok: false, error: { code: "E_APPLY" } });
        }
      }
      const edge = kind;
      host.edgeCalls[edge] = (host.edgeCalls[edge] || 0) + 1;
      const tm = input.match(/link claim (bp3link_[A-Za-z0-9_-]+)/);
      const session = "sess-" + node + "-" + edge + "-" + host.calls;
      const claimed = bp3(["harness", "link", "claim", tm[1]], { MUSE_SESSION_ID: session });
      if (blockMode && edge === "handoff") {
        return JSON.stringify({ ok: false, run_id: claimed.run_id, reason: "choose storage shape", error: { code: "E_DECISION", guidance: "choose storage shape" } });
      }
      let commit = "abc1234"; let verdict = { ok: true };
      if (edge === "handoff") { commit = commitFor("bubcl", node); verdict = bp3(["e", "handoff", "--commit", commit, "--reason", "claude work"], { MUSE_SESSION_ID: session }); }
      else if (edge === "grade") { verdict = bp3(["e", "grade", "--verdict", "ship", "--reason", "artifact checked"], { MUSE_SESSION_ID: session }); }
      else if (edge === "verify") { verdict = bp3(["e", "verify", "--verdict", "pass", "--reason", "checks green"], { MUSE_SESSION_ID: session }); }
      else if (edge === "land") { verdict = bp3(["e", "land", "--reason", "serial land"], { MUSE_SESSION_ID: session }); }
      return JSON.stringify({ ok: true, run_id: claimed.run_id, commit, verdict });
    },
    async parallel(calls) { const out = []; for (const c of calls) out.push(await host.agent(c)); return out; } };
  return host;
}
const clSeedHost = makeClaudeHost("seeded-cl", true);
const clSibHost = makeClaudeHost("sib-cl", false);
const [clSeed, clSib] = await Promise.all([workflow(clSeedHost), workflow(clSibHost)]);
assert(clSeed.outcome === "blocked" && clSeed.reason === "choose storage shape" && clSeed.last_edge === "handoff" && clSeed.graph === "bubcl" && clSeed.inbox_key === "bubcl/seeded-cl", "Muse parity bubble same terminal facts: " + JSON.stringify(clSeed));
assert(clSib.outcome === "landed", "Muse sibling landed unaffected, got " + clSib.outcome);
assert((clSeedHost.edgeCalls.handoff || 0) === 1 && clSeedHost.blockCalls === 1, "Muse failed edge never retried, exactly one block");
assert(bp3(["g", "bubcl", "r", "seeded-cl"]).state === "blocked", "Muse seeded rests blocked");
assert(bp3(["g", "bubcl", "r", "sib-cl"]).state === "landed", "Muse sibling state landed");
const clOldCalls = clSeedHost.calls;
const clResumed = bp3(["g", "bubcl", "u", "seeded-cl", "resume", "--reason", "use localStorage"], { BP3_DECIDER: "human" });
assert(clResumed.ok === true && clResumed.state === "todo", "Muse resume revives to todo");
const clFreshHost = makeClaudeHost("seeded-cl", false);
const clFresh = await workflow(clFreshHost);
assert(clFresh.outcome === "landed", "Muse fresh workflow lands seeded, got " + clFresh.outcome);
assert(clSeedHost.calls === clOldCalls, "Muse revival never resumes old workflow agents");
assert(clFresh.run_ids.every((r) => !clSeed.run_ids.includes(r)), "Muse revival run-ids are fresh, disjoint from blocked run");
assert(bp3(["g", "bubcl", "r", "sib-cl"]).state === "landed", "Muse sibling still landed after revival");
if (failures > 0) process.exit(1);
console.log(JSON.stringify({ pi_bubble: pb.state, pi_fresh_run: piFresh.runId, pi_wall_ms: piT1 - piT0, claude_bubble: clSeed.outcome, claude_fresh: clFresh.outcome, sibling_pi: "handed_off", sibling_claude: clSib.outcome }));
BUBBLE_JS
bubble_out=$(BP3_ROOT="$root" BP3_WORK="$work" node "$work/bubble-drive.mjs") || fail "bubble drive: $bubble_out"
echo "bubble scorecard: $bubble_out"
echo "$bubble_out" | jq -e '.pi_bubble == "blocked" and .claude_bubble == "blocked" and .claude_fresh == "landed" and .sibling_claude == "landed"' >/dev/null \
  || fail "bubble scorecard: $bubble_out"

echo "dogfood-parallel tests: ok"
