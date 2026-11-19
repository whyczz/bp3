#!/usr/bin/env bash
# mvp.2 context resolution: session rung, then desk rung;
# the claim stamps verdicts and ledger lines, env is a hint.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
lk() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness link "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
store=".git/bp3"
NOSID=(env -u MUSE_SESSION_ID -u MUSE_THREAD_ID -u BP3_SESSION_ID -u PI_SESSION_ID -u PI_SESSION_FILE -u BP3_RUN_ID)
es() { MUSE_SESSION_ID="$1" BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 e "${@:2}"; }

# --- help: e door documented, exit 0, no store created ---
out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 e -h) || fail "e -h exit"
echo "$out" | grep -q "bp3 e" || fail "e help: $out"
echo "$out" | grep -q "E_NO_CONTEXT" || fail "e help codes: $out"
out=$(q -h) || fail "q -h exit"
echo "$out" | grep -q "bp3 e" || fail "q help lists e: $out"
[ ! -e "$store" ] || fail "help created the store"

q c g1 >/dev/null
for n in n0 n1 n2 n3 n4 n5; do q g1 c "$n" >/dev/null; done
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)

# --- unclaimed: bare e refuses, explicit edge warns once ---
if out=$("${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 e 2>&1); then fail "unclaimed bare e accepted"; fi
echo "$out" | jq -e '.error.code == "E_NO_CONTEXT"' >/dev/null || fail "unclaimed bare e code: $out"
out=$("${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q g1 u n0 handoff --commit "$B" --reason "stranger")
echo "$out" | jq -e '.ok == true and .warnings == ["W_CONTEXT_UNCLAIMED"] and (has("run_id") | not)' >/dev/null || fail "unclaimed explicit: $out"
git show bp3/node/g1/n0:docs/quests/g1/nodes/n0/ledger.jsonl | tail -1 | jq -e 'has("run_id") | not' >/dev/null || fail "unclaimed ledger stamped"

# --- claimed session: zero context flags, claim stamps ---
out=$(lk mint --kind edge --quest g1 --node n1 --edge handoff --depth 2)
TOK=$(echo "$out" | jq -r .token); RID=$(echo "$out" | jq -r .run_id)
MUSE_SESSION_ID=sess-a lk claim "$TOK" >/dev/null
rm -f .bp3-context.json
out=$(es sess-a) || fail "bare e exit: $out"
echo "$out" | jq -e --arg r "$RID" '.ok == true and .quest == "g1" and .node == "n1" and .edge == "handoff"
  and .run_id == $r and .source == "session" and .state == "todo"
  and (.legal_edges | index("handoff") != null) and (.thresholds.depth_cap | type == "number")' \
  >/dev/null || fail "bare e context: $out"
out=$(es sess-a handoff --commit "$B" --reason "claimed cut") || fail "e handoff: $out"
echo "$out" | jq -e --arg r "$RID" '.ok == true and .state == "handed_off" and .run_id == $r and .source == "session"' >/dev/null || fail "e handoff verdict: $out"
out=$(es sess-a grade --verdict ship --reason "right")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "e grade: $out"
out=$(es sess-a verify --verdict pass --reason "green")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "e verify: $out"
out=$(es sess-a land --reason "ship it")
echo "$out" | jq -e --arg r "$RID" '.state == "landed" and .run_id == $r' >/dev/null || fail "e land: $out"
git show bp3/node/g1/n1:docs/quests/g1/nodes/n1/ledger.jsonl | tail -4 | jq -s -e --arg r "$RID" 'all(.run_id == $r)' >/dev/null || fail "claimed ledger stamps"

# explicit address from the claimed session stamps the claim too
out=$(lk mint --kind edge --quest g1 --node n2 --edge handoff --depth 2)
TOK2=$(echo "$out" | jq -r .token); RID2=$(echo "$out" | jq -r .run_id)
MUSE_SESSION_ID=sess-b lk claim "$TOK2" >/dev/null
rm -f .bp3-context.json
out=$(BP3_RUN_ID=someone-else MUSE_SESSION_ID=sess-b BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q g1 u n2 handoff --commit "$B" --reason "mismatch") || fail "mismatch handoff: $out"
echo "$out" | jq -e --arg r "$RID2" '.ok == true and .run_id == $r and (.warnings | index("W_CONTEXT_ENV_MISMATCH") != null)' >/dev/null || fail "env mismatch, claim wins: $out"
git show bp3/node/g1/n2:docs/quests/g1/nodes/n2/ledger.jsonl | tail -1 | jq -e --arg r "$RID2" '.run_id == $r' >/dev/null || fail "mismatch ledger claimed run-id"

# a session claiming again resolves to its latest claim
out=$(lk mint --kind edge --quest g1 --node n0 --edge grade --depth 2)
TOKL=$(echo "$out" | jq -r .token); RIDL=$(echo "$out" | jq -r .run_id)
MUSE_SESSION_ID=sess-a lk claim "$TOKL" >/dev/null
rm -f .bp3-context.json
out=$(es sess-a) || fail "reclaim bare e: $out"
echo "$out" | jq -e --arg r "$RIDL" '.run_id == $r and .node == "n0" and .source == "session"' >/dev/null || fail "latest claim wins: $out"

# --- claimed desk, new shell: desk rung, checked against cwd ---
mkdir -p "$work/desk3"
out=$(lk mint --kind edge --quest g1 --node n3 --edge handoff --depth 2 --desk "$work/desk3")
TOK3=$(echo "$out" | jq -r .token); RID3=$(echo "$out" | jq -r .run_id)
MUSE_SESSION_ID=sess-c lk claim "$TOK3" >/dev/null
rm -f .bp3-context.json
out=$(cd "$work/desk3" && "${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" e) || fail "desk bare e: $out"
echo "$out" | jq -e --arg r "$RID3" '.run_id == $r and .source == "desk" and .node == "n3"' >/dev/null || fail "desk rung: $out"
out=$(cd "$work/desk3" && "${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" e handoff --commit "$B" --reason "from desk") || fail "desk handoff: $out"
echo "$out" | jq -e --arg r "$RID3" '.state == "handed_off" and .run_id == $r and .source == "desk"' >/dev/null || fail "desk handoff verdict: $out"

# --- no false claim: an unclaimed desk inherits nothing ---
mkdir -p "$work/elsewhere"
if out=$(cd "$work/elsewhere" && "${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" e 2>&1); then fail "sibling context inherited"; fi
echo "$out" | jq -e '.error.code == "E_NO_CONTEXT"' >/dev/null || fail "no-false-claim code: $out"

# --- desk rung never guesses: two live claims, one desk ---
mkdir -p "$work/desk-amb"
for spec in "n4 sess-d1" "n5 sess-d2"; do
  node_name="${spec%% *}"; sess_name="${spec##* }"
  out=$(lk mint --kind edge --quest g1 --node "$node_name" --edge handoff --depth 2 --desk "$work/desk-amb")
  tok=$(echo "$out" | jq -r .token)
  MUSE_SESSION_ID="$sess_name" lk claim "$tok" >/dev/null
done
rm -f .bp3-context.json
if out=$(cd "$work/desk-amb" && "${NOSID[@]}" BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" e 2>&1); then fail "ambiguous desk accepted"; fi
echo "$out" | jq -e '.error.code == "E_NO_CONTEXT" and (.error.facts.live_run_ids | length) == 2' >/dev/null || fail "ambiguous facts name live runs: $out"
# the session rung still wins inside that same desk
out=$(cd "$work/desk-amb" && MUSE_SESSION_ID=sess-d1 BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" e) || fail "session over ambiguous desk: $out"
echo "$out" | jq -e '.node == "n4" and .source == "session"' >/dev/null || fail "session rung wins: $out"

echo "context tests: ok"
