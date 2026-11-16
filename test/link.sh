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
lk() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness link "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
store=".git/bp3"
lku() { env -u MUSE_SESSION_ID -u MUSE_THREAD_ID -u BP3_SESSION_ID -u PI_SESSION_ID -u PI_SESSION_FILE BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness link "$@"; }

# --- help: every link verb documented, exit 0, no store created ---
out=$(lk -h) || fail "link -h exit"
for v in mint claim lookup cleanup; do
  echo "$out" | grep -q "$v" || fail "link help lists $v: $out"
done
echo "$out" | grep -q "E_LINK_SPENT" || fail "link help codes spent: $out"
echo "$out" | grep -q "E_DEPTH" || fail "link help codes depth: $out"
out=$(h -h) || fail "harness -h exit"
echo "$out" | grep -q "link" || fail "harness help lists link: $out"
out=$(h link -h) || fail "harness link -h exit"
echo "$out" | grep -q "mint" || fail "harness link help: $out"
out=$(h record-init -h) || fail "record-init -h exit"
echo "$out" | grep -q "E_RETIRED" || fail "record-init help retired: $out"
[ ! -e "$store" ] || fail "help created the store"

# --- strict argv ---
if out=$(lk mint --graph g1 --node n1 2>&1); then fail "mint without kind accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "mint no-kind code: $out"
if out=$(lk mint --kind node --graph g1 --node n1 --edge handoff 2>&1); then fail "node with edge accepted"; fi
if out=$(lk mint --kind edge --graph g1 --node n1 2>&1); then fail "edge without edge accepted"; fi
if out=$(lk mint --kind edge --graph g1 --node n1 --edge bogus 2>&1); then fail "bogus edge accepted"; fi
if out=$(lk mint --kind=edge --graph g1 --node n1 --edge handoff 2>&1); then fail "--flag=value accepted"; fi
if out=$(lk mint --kind edge --kind edge --graph g1 --node n1 --edge handoff 2>&1); then fail "duplicate kind accepted"; fi
if out=$(lk mint --kind edge --graph g1 --node n1 --edge handoff --depth -1 2>&1); then fail "negative depth accepted"; fi
if out=$(lk claim 2>&1); then fail "claim without token accepted"; fi
if out=$(lk lookup 2>&1); then fail "lookup without identity accepted"; fi
if out=$(lk lookup --session-id S1 --run-id R1 2>&1); then fail "lookup with both accepted"; fi
if out=$(lk cleanup 2>&1); then fail "cleanup without graph accepted"; fi
if out=$(lk bogus 2>&1); then fail "unknown link verb accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "unknown verb code: $out"
[ ! -e "$store" ] || fail "usage errors created the store"

# --- mint + claim: run config is the InitRecord-equivalent ---
out=$(lk mint --kind edge --graph g1 --node n1 --edge handoff --parent-run-id root-1 --depth 2 --desk "$work/repo" --harness muse-code --model test-model)
echo "$out" | jq -e '.ok == true and .state == "minted" and (.token | startswith("bp3link_"))' >/dev/null || fail "mint verdict: $out"
TOK=$(echo "$out" | jq -r .token)
RID=$(echo "$out" | jq -r .run_id)
[ -f "$store/runs/$RID.json" ] || fail "mint wrote no run config"
jq -e '.state == "minted" and .kind == "edge" and .graph == "g1" and .node == "n1" and .edge == "handoff"
  and .creator.run_id == "root-1" and .creator.depth == 2 and .creator.harness == "muse-code"
  and (.creator.token_hash | startswith("sha256:")) and (.creator.minted_at | type == "string")' \
  "$store/runs/$RID.json" >/dev/null || fail "minted run config shape: $(cat "$store/runs/$RID.json")"
# quoting safety: the token sitting in a brief confers nothing
echo "brief: claim $TOK then build" > brief.txt
if out=$(lk lookup --session-id sess-a 2>&1); then fail "lookup before claim accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "pre-claim lookup code: $out"

out=$(MUSE_SESSION_ID=sess-a lk claim "$TOK") || fail "claim exit: $out"
echo "$out" | jq -e --arg r "$RID" '.ok == true and .run_id == $r and .state == "claimed"
  and .session_id == "sess-a" and (.pid | type == "number" and . > 0) and (.cwd | type == "string")' \
  >/dev/null || fail "claim verdict: $out"
jq -e '.state == "claimed" and .claim.session_id == "sess-a" and (.claim.pid | type == "number")
  and (.claim.cwd | type == "string") and (.claim.claimed_at | type == "string")' \
  "$store/runs/$RID.json" >/dev/null || fail "claimed run config shape: $(cat "$store/runs/$RID.json")"
[ "$(cat "$store/by-session/sess-a")" = "$RID" ] || fail "by-session index content"
[ -f "$store/claims/$RID.claim" ] || fail "O_EXCL claim marker missing"
jq -e '.run_id and .graph == "g1"' .bp3-context.json >/dev/null || fail "desk context file: $(cat .bp3-context.json 2>/dev/null)"
rm -f .bp3-context.json brief.txt

# by-session join: one lookup from session-id alone
out=$(lk lookup --session-id sess-a) || fail "lookup exit: $out"
echo "$out" | jq -e --arg r "$RID" '.ok == true and .run_id == $r and .graph == "g1"
  and .node == "n1" and .edge == "handoff"' >/dev/null || fail "by-session join: $out"
out=$(BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 config) || fail "config view exit"
echo "$out" | jq -e --arg r "$RID" '(.contexts[] | select(.run_id == $r) | .session_id == "sess-a"
  and .parent_run_id == "root-1" and .depth == 2)' >/dev/null || fail "config context join: $out"

# one winner: second claim names the first claimant, forever
if out=$(MUSE_SESSION_ID=sess-b lk claim "$TOK" 2>&1); then fail "second claim accepted"; fi
echo "$out" | jq -e '.error.code == "E_LINK_SPENT" and .error.facts.first_claim.session_id == "sess-a"
  and (.error.facts.first_claim.pid | type == "number") and (.error.facts.first_claim.ts | type == "string")' \
  >/dev/null || fail "spent verdict names winner: $out"
if out=$(lku claim "$TOK" 2>&1); then fail "third claim accepted"; fi
echo "$out" | jq -e '.error.code == "E_LINK_SPENT"' >/dev/null || fail "spent forever code: $out"
if out=$(lk claim bp3link_00000000000000000000000000000000 2>&1); then fail "unknown token accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unknown token code: $out"

# --- graceful floor: no session offered, pid+cwd still claim ---
out=$(lk mint --kind node --graph g1 --node n2 --depth 1 --parent-run-id root-1)
TOK2=$(echo "$out" | jq -r .token); RID2=$(echo "$out" | jq -r .run_id)
out=$(lku claim "$TOK2") || fail "floor claim exit: $out"
echo "$out" | jq -e --arg r "$RID2" '.ok == true and .run_id == $r and .session_id == null
  and .parent_run_id == "root-1" and .depth == 1' >/dev/null || fail "floor claim: $out"
jq -e '(.claim | has("session_id") | not) and (.claim.pid | type == "number")' \
  "$store/runs/$RID2.json" >/dev/null || fail "floor run config: $(cat "$store/runs/$RID2.json")"
out=$(lk lookup --run-id "$RID2") || fail "lookup by run-id exit: $out"
echo "$out" | jq -e '.node == "n2" and .edge == null and .kind == "node"' >/dev/null || fail "node lookup: $out"

# claims write nothing into harness session logs
printf '%s\n' '{"type":"session","version":3,"id":"sess-tape","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' > guard-tape.log
GH=$(shasum -a 256 guard-tape.log | cut -d' ' -f1)
out=$(lk mint --kind edge --graph g1 --node n1 --edge land --depth 2)
TOKG=$(echo "$out" | jq -r .token)
MUSE_SESSION_ID=sess-tape lk claim "$TOKG" >/dev/null
[ "$(shasum -a 256 guard-tape.log | cut -d' ' -f1)" = "$GH" ] || fail "claim wrote into a session tape"
rm guard-tape.log
lk cleanup --graph g1 >/dev/null

# --- pi shape: the dispatcher's session file identity ---
out=$(lk mint --kind edge --graph g1 --node n1 --edge grade --depth 2 --parent-run-id "$RID2" --harness pi --model fake-model)
TOK3=$(echo "$out" | jq -r .token); RID3=$(echo "$out" | jq -r .run_id)
out=$(env -u MUSE_SESSION_ID -u MUSE_THREAD_ID -u BP3_SESSION_ID -u PI_SESSION_ID PI_SESSION_FILE="$work/sess-pi-1.jsonl" BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness link claim "$TOK3") || fail "pi claim exit: $out"
echo "$out" | jq -e '.session_id == "sess-pi-1" and .parent_run_id != "" and .depth == 2' >/dev/null || fail "pi claim: $out"
out=$(lk lookup --session-id sess-pi-1) || fail "pi lookup exit: $out"
echo "$out" | jq -e --arg r "$RID3" '.run_id == $r and .edge == "grade"' >/dev/null || fail "pi join: $out"
# tree reconstruction: edge -> node worker -> root via parent_run_id
jq -e --arg p "$RID2" '.creator.run_id == $p and .creator.depth == 2' "$store/runs/$RID3.json" >/dev/null \
  || fail "parent chain: $(cat "$store/runs/$RID3.json")"

# --- CAS race: two parallel claims, exactly one winner ---
out=$(lk mint --kind edge --graph g1 --node n1 --edge verify --depth 2)
TOKR=$(echo "$out" | jq -r .token)
MUSE_SESSION_ID=race-a lk claim "$TOKR" > "$work/race-a.json" 2>&1 & PA=$!
MUSE_SESSION_ID=race-b lk claim "$TOKR" > "$work/race-b.json" 2>&1 & PB=$!
set +e; wait $PA; wait $PB; set -e
WINS=0; SPENT=0
for f in "$work/race-a.json" "$work/race-b.json"; do
  if jq -e '.ok == true' "$f" >/dev/null 2>&1; then WINS=$((WINS+1)); fi
  if jq -e '.error.code == "E_LINK_SPENT"' "$f" >/dev/null 2>&1; then SPENT=$((SPENT+1)); fi
done
[ "$WINS" = 1 ] && [ "$SPENT" = 1 ] || fail "race outcome wins=$WINS spent=$SPENT: $(cat "$work"/race-*.json)"

# --- depth cap: beyond refuses E_DEPTH, machine-config overridable ---
if out=$(lk mint --kind edge --graph g1 --node n1 --edge handoff --depth 4 2>&1); then fail "depth 4 accepted"; fi
echo "$out" | jq -e '.error.code == "E_DEPTH" and .error.facts.depth_cap == 3' >/dev/null || fail "depth verdict: $out"
out=$(lk mint --kind edge --graph g1 --node n1 --edge handoff --depth 3) || fail "depth at cap refused: $out"
RIDCAP=$(echo "$out" | jq -r .run_id)
jq '.thresholds.depth_cap = 1' "$store/config.json" > "$store/config.json.tmp"
mv "$store/config.json.tmp" "$store/config.json"
if out=$(lk mint --kind edge --graph g1 --node n1 --edge handoff --depth 2 2>&1); then fail "depth over local cap accepted"; fi
echo "$out" | jq -e '.error.code == "E_DEPTH" and .error.facts.depth_cap == 1' >/dev/null || fail "local cap verdict: $out"
jq '.thresholds.depth_cap = 3' "$store/config.json" > "$store/config.json.tmp"
mv "$store/config.json.tmp" "$store/config.json"

# --- torn run config is never read as valid ---
echo '{not json' > "$store/runs/z-torn.json"
out=$(BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 config) || fail "config view with torn exit"
echo "$out" | jq -e '[.contexts[] | select(.run_id == "z-torn")] | length == 0' >/dev/null || fail "torn folded: $out"
rm "$store/runs/z-torn.json"

# --- bind-tape writes tape_path into the run config; record-init retired ---
printf '%s\n' '{"type":"session","version":3,"id":"sess-a","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"session_closed","id":"e9"}' > tape-a.log
out=$(h bind-tape --run-id "$RID" --tape-path "$work/repo/tape-a.log") || fail "bind-tape exit: $out"
echo "$out" | jq -e --arg r "$RID" '.ok == true and .run_id == $r' >/dev/null || fail "bind-tape verdict: $out"
jq -e --arg t "$work/repo/tape-a.log" '.tape_path == $t' "$store/runs/$RID.json" >/dev/null \
  || fail "tape_path not in run config: $(cat "$store/runs/$RID.json")"
if out=$(h bind-tape --run-id "$RID" --tape-path "$work/repo/other.log" 2>&1); then fail "rebind accepted"; fi
echo "$out" | jq -e '.error.code == "E_EXISTS"' >/dev/null || fail "rebind code: $out"
out=$(h bind-tape --run-id "$RID" --tape-path "$work/repo/tape-a.log") || fail "same-tape rebind exit: $out"
if out=$(h record-init --run-id R-retired --harness pi 2>&1); then fail "record-init accepted"; fi
echo "$out" | jq -e '.error.code == "E_RETIRED"' >/dev/null || fail "record-init code: $out"
if out=$(h r --run-id R-retired --harness pi 2>&1); then fail "record-init alias accepted"; fi
echo "$out" | jq -e '.error.code == "E_RETIRED"' >/dev/null || fail "record-init alias code: $out"

# --- supervisor fold derives lifecycle from the run config ---
q c toy2 >/dev/null; q toy2 c n1 >/dev/null
out=$(lk mint --kind edge --graph toy2 --node n1 --edge handoff --depth 2 --harness pi --model fake-model)
TOKS=$(echo "$out" | jq -r .token); RIDS=$(echo "$out" | jq -r .run_id)
printf '%s\n' '{"type":"session","version":3,"id":"sess-sup","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"s1","message":{"role":"user","content":"work"}}' '{"type":"session_closed","id":"s2"}' > sup-tape.log
# dead pid (999999 cannot be claimed live; claim as this shell then bind tape:
# pid in config is the claim shell's, already dead by supervisor time)
MUSE_SESSION_ID=sess-sup lk claim "$TOKS" >/dev/null
h bind-tape --run-id "$RIDS" --tape-path "$work/repo/sup-tape.log" >/dev/null
out=$(lk mint --kind edge --graph toy2 --node n1 --edge grade --depth 2 --harness pi --model fake-model)
RIDM=$(echo "$out" | jq -r .run_id)
set +e; out=$(h supervisor toy2 --timeout-seconds 2); set -e
last=$(echo "$out" | tail -1)
echo "$last" | jq -e --arg r "$RIDS" '(.runs[] | select(.run_id == $r) | .lifecycle == "finished")' >/dev/null \
  || fail "supervisor finished from run config: $last"
echo "$last" | jq -e --arg r "$RIDM" '(.runs[] | select(.run_id == $r) | .lifecycle == "init")' >/dev/null \
  || fail "supervisor init for minted: $last"
out=$(h find-tape --session-id sess-sup) || fail "find-tape by claimed session exit: $out"
echo "$out" | jq -e --arg r "$RIDS" '.run_id == $r' >/dev/null || fail "find-tape join: $out"

# --- stale mint cleanup: only still-minted of that graph ---
h1=$(shasum -a 256 "$store/runs/$RID.json" | cut -d' ' -f1)
h2=$(shasum -a 256 "$store/runs/$RID2.json" | cut -d' ' -f1)
out=$(lk cleanup --graph g1) || fail "cleanup exit: $out"
echo "$out" | jq -e --arg r "$RIDCAP" '.ok == true and (.removed | index($r) != null)
  and (.removed | index("'"$RID"'") == null)' >/dev/null || fail "cleanup removed set: $out"
[ ! -f "$store/runs/$RIDCAP.json" ] || fail "stale mint survived cleanup"
[ "$(shasum -a 256 "$store/runs/$RID.json" | cut -d' ' -f1)" = "$h1" ] || fail "cleanup touched claimed g1"
[ "$(shasum -a 256 "$store/runs/$RID2.json" | cut -d' ' -f1)" = "$h2" ] || fail "cleanup touched claimed node"
out=$(lk cleanup --graph g1) || fail "cleanup rerun exit: $out"
echo "$out" | jq -e '.removed == [] and .count == 0' >/dev/null || fail "cleanup rerun: $out"

echo "link tests: ok"
