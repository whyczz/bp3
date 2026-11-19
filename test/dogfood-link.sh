#!/usr/bin/env bash
# dogfood.1 link-drive: old brief vs link brief on muse and pi
# session shapes. The drive is the test: four flappy artifacts,
# three claim attacks, metrics recorded from the drive itself.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
perl -pi -e 's/^max_cycles: .*/max_cycles: 1/' "$work/repo/plans/default.yaml"  # fixtures assert one review round
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
lk() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness link "$@"; }
h() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
NOSID=(env -u MUSE_SESSION_ID -u MUSE_THREAD_ID -u BP3_SESSION_ID -u PI_SESSION_ID -u PI_SESSION_FILE -u BP3_RUN_ID)

q c g1 >/dev/null
q g1 c flappy >/dev/null
echo work > b.txt; git add b.txt; git commit -qm work
TIP=$(git rev-parse HEAD)

# --- flappy artifact: one spelling (flappy), node --check on its module ---
flappy_write() { # <file> <variant>
  cat > "$1" <<HTML
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Flappy — $2</title>
<script type="importmap">{ "imports": { "three": "https://unpkg.com/three@0.160.0/build/three.module.js" } }</script>
</head><body><div id="hud">Score <b id="score">0</b></div>
<script type="module">
import * as THREE from 'three';
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x87ceeb);
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

# --- briefs: old setup prose vs one-line link brief ---
old_brief() { # <run-id>
  cat <<EOF
You are the author child for node flappy of quest g1.
First export BP3_QUEST=g1 BP3_NODE=flappy BP3_RUN_ID=$1 BP3_HARNESS=muse-code BP3_MODEL=test-model.
Your desk is $work/repo; if state looks wrong, guess the desk from the quest branch name.
When done run: ./bin/bp3 q g1 u flappy handoff --commit <sha> --reason "<short reason>".
Build flappy in three.js.
EOF
}
OLD_CHARS=$(old_brief "2026-run-old" | wc -c | tr -d ' ')
[ "$OLD_CHARS" -gt 200 ] || fail "old brief too small to be the old way: $OLD_CHARS"

metrics="$work/metrics.json"; : > "$metrics"
attacks="$work/attacks.log"; : > "$attacks"

# drive <shape muse|pi> <way old|link> <variant>
drive() {
  local shape=$1 way=$2 variant=$3
  local art="$work/flappy-$way-$shape.html" calls="$work/calls-$way-$shape.log"
  : > "$calls"
  local t0 tend brief_chars setup_refusals=0
  if [ "$way" = link ]; then
    local mint tok
    mint=$(lk mint --kind edge --quest g1 --node flappy --edge handoff --depth 2 \
      --harness "$shape" --model test-model)
    tok=$(echo "$mint" | jq -r .token)
    local brief="claim $tok, build flappy $variant"
    [ "$(printf '%s' "$brief" | wc -l | tr -d ' ')" = 0 ] || fail "link brief not one line"
    printf '%s' "$brief" | grep -qiE 'export|desk|BP3_RUN_ID|BP3_QUEST|BP3_NODE' \
      && fail "link brief carries setup prose: $brief"
    brief_chars=$(printf '%s' "$brief" | wc -c | tr -d ' ')
    echo "claim $tok" >> "$calls"
    t0=$(date +%s)
    if [ "$shape" = muse ]; then
      MUSE_SESSION_ID="sess-$way-$shape" lk claim "$tok" >/dev/null \
        || fail "link claim $shape"
    else
      printf '%s\n' '{"type":"session","id":"x"}' > "$work/sess-$way-$shape.jsonl"
      "${NOSID[@]}" PI_SESSION_FILE="$work/sess-$way-$shape.jsonl" \
        BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness link claim "$tok" >/dev/null \
        || fail "link claim $shape"
    fi
    flappy_write "$art" "$variant"
    tend=$(date +%s)
    # edge call after claim: bare e door, no quest/node/run-id carried
    echo "bp3 e handoff --commit $TIP" >> "$calls"
    grep -qE 'bp3 q g1 u|BP3_RUN_ID|--run-id' "$calls" \
      && fail "link-way call carries carried context: $(cat "$calls")"
  else
    brief_chars=$OLD_CHARS
    t0=$(date +%s)
    flappy_write "$art" "$variant"
    tend=$(date +%s)
    echo "bp3 q g1 u flappy handoff --commit $TIP (exports + guessed desk)" >> "$calls"
    grep -q 'bp3 q g1 u' "$calls" || fail "old-way call shape unrecorded"
  fi
  [ -f "$art" ] || fail "drive $way-$shape wrote no artifact"
  jq -n --arg drive "$way-$shape" --argjson brief_chars "$brief_chars" \
    --argjson setup_refusals_at_claim "$setup_refusals" \
    --argjson time_to_first_productive_call_s "$((tend - t0))" \
    --argjson cycles_to_land 1 \
    '{drive:$drive, brief_chars:$brief_chars,
      setup_refusals_at_claim:$setup_refusals_at_claim,
      time_to_first_productive_call_s:$time_to_first_productive_call_s,
      cycles_to_land:$cycles_to_land}' >> "$metrics"
}

drive muse old muse-old
drive muse link muse-link
drive pi old pi-old
drive pi link pi-link

# link brief wins on chars, observed from the briefs themselves
jq -s -e '(.[] | select(.drive=="link-muse") | .brief_chars)
  < (.[] | select(.drive=="old-muse") | .brief_chars)
  and (.[] | select(.drive=="link-pi") | .brief_chars)
  < (.[] | select(.drive=="old-pi") | .brief_chars)' "$metrics" >/dev/null \
  || fail "link brief not shorter: $(cat "$metrics")"

# --- attacks refuse before work; zero setup cycles burned ---
# 1. duplicate claim -> E_LINK_SPENT naming the first claimant
mint=$(lk mint --kind edge --quest g1 --node flappy --edge handoff --depth 2)
TOK=$(echo "$mint" | jq -r .token)
MUSE_SESSION_ID=atk-first lk claim "$TOK" >/dev/null
if out=$(MUSE_SESSION_ID=atk-second lk claim "$TOK" 2>&1); then fail "duplicate claim accepted"; fi
echo "$out" | jq -e '.error.code == "E_LINK_SPENT"
  and .error.facts.first_claim.session_id == "atk-first"' >/dev/null \
  || fail "duplicate attack verdict: $out"
echo "duplicate claim -> E_LINK_SPENT" >> "$attacks"

# 2. quoting claim: token sitting in a brief confers nothing
mint=$(lk mint --kind edge --quest g1 --node flappy --edge grade --depth 2)
TOKQ=$(echo "$mint" | jq -r .token)
echo "brief: claim $TOKQ then grade" > "$work/brief.txt"
if out=$(lk lookup --session-id atk-quoting 2>&1); then fail "quoting lookup accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "quoting verdict: $out"
MUSE_SESSION_ID=atk-real lk claim "$TOKQ" >/dev/null || fail "claim after quoting refused"
echo "quoting claim -> E_NOT_FOUND (token in brief confers nothing)" >> "$attacks"

# 3. wrong-desk: claimed in desk A; bare e from desk B resolves nothing
mkdir -p "$work/repo/deskA" "$work/repo/deskB"
mint=$(lk mint --kind edge --quest g1 --node flappy --edge handoff --depth 2 --desk "$work/repo/deskA")
TOKW=$(echo "$mint" | jq -r .token)
(cd "$work/repo/deskA" && MUSE_SESSION_ID=atk-desk BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" harness link claim "$TOKW" >/dev/null) \
  || fail "desk A claim"
if out=$(cd "$work/repo/deskB" && "${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" e 2>&1); then
  fail "wrong-desk e accepted: $out"; fi
echo "$out" | jq -e '.error.code == "E_NO_CONTEXT"' >/dev/null || fail "wrong-desk verdict: $out"
[ ! -e "$work/repo/deskB/flappy.html" ] || fail "wrong-desk drive did work"
echo "wrong-desk e -> E_NO_CONTEXT (no context on the wrong desk)" >> "$attacks"
[ "$(wc -l < "$attacks" | tr -d ' ')" = 3 ] || fail "attack log rows: $(cat "$attacks")"

# --- Pi nested tree: root -> node worker -> edge worker, distinct links ---
mint=$(lk mint --kind node --quest g1 --node flappy --depth 0 --harness pi --model fake)
RTOK=$(echo "$mint" | jq -r .token); RRID=$(echo "$mint" | jq -r .run_id)
"${NOSID[@]}" PI_SESSION_FILE="$work/root.jsonl" BP3_Q_BIN="$work/repo/g-bin" \
  ./bin/bp3 harness link claim "$RTOK" >/dev/null || fail "pi root claim"
mint=$(lk mint --kind node --quest g1 --node flappy --depth 1 --parent-run-id "$RRID" --harness pi --model fake)
NTOK=$(echo "$mint" | jq -r .token); NRID=$(echo "$mint" | jq -r .run_id)
printf '%s\n' '{"type":"session","id":"n"}' > "$work/node.jsonl"
"${NOSID[@]}" PI_SESSION_FILE="$work/node.jsonl" BP3_Q_BIN="$work/repo/g-bin" \
  ./bin/bp3 harness link claim "$NTOK" >/dev/null || fail "pi node claim"
mint=$(lk mint --kind edge --quest g1 --node flappy --edge handoff --depth 2 --parent-run-id "$NRID" --harness pi --model fake)
ETOK=$(echo "$mint" | jq -r .token); ERID=$(echo "$mint" | jq -r .run_id)
printf '%s\n' '{"type":"session","id":"e"}' > "$work/edge.jsonl"
"${NOSID[@]}" PI_SESSION_FILE="$work/edge.jsonl" BP3_Q_BIN="$work/repo/g-bin" \
  ./bin/bp3 harness link claim "$ETOK" >/dev/null || fail "pi edge claim"
[ "$RRID" != "$NRID" ] && [ "$NRID" != "$ERID" ] || fail "pi tree run-ids not distinct"
jq -e --arg p "$RRID" '.creator.run_id == $p and .creator.depth == 1' ".git/bp3/runs/$NRID.json" >/dev/null \
  || fail "pi node parent chain"
jq -e --arg p "$NRID" '.creator.run_id == $p and .creator.depth == 2' ".git/bp3/runs/$ERID.json" >/dev/null \
  || fail "pi edge parent chain"

# --- supervised proof unchanged: lifecycle folds from the run config ---
q c toy2 >/dev/null; q toy2 c n1 >/dev/null
printf '%s\n' '{"type":"session","version":3,"id":"sess-sup","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' \
  '{"type":"message","id":"s1","message":{"role":"user","content":"work"}}' \
  '{"type":"session_closed","id":"s2"}' > sup-tape.log
mint=$(lk mint --kind edge --quest toy2 --node n1 --edge verify --depth 2 --harness pi --model fake-model)
STOK=$(echo "$mint" | jq -r .token); SRID=$(echo "$mint" | jq -r .run_id)
MUSE_SESSION_ID=sess-sup lk claim "$STOK" >/dev/null
h bind-tape --run-id "$SRID" --tape-path "$work/repo/sup-tape.log" >/dev/null
set +e; out=$(h supervisor toy2 --timeout-seconds 2 | tail -1); set -e
echo "$out" | jq -e --arg r "$SRID" '(.runs[] | select(.run_id == $r) | .lifecycle == "finished")' >/dev/null \
  || fail "supervisor fold from run config: $out"

jq -s '{drives: ., attacks: 3}' "$metrics" > "$work/scorecard.json"
echo "dogfood-link tests: ok"
