#!/usr/bin/env bash
# Node 6 fixtures: bp3 q hooks turns Muse hook payloads on
# stdin into past-tense event lines in the node ledger. Fail-open
# everywhere: exit 0 and no writes for garbage, foreign repos,
# unbound sessions, and its own reentrant calls.
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
mkdir -p docs/quests
repo=$(pwd)

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
hooks() { printf '%s' "$1" | BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q hooks; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ledger() { git show "bp3/node/demo/$1:docs/quests/demo/nodes/$1/ledger.jsonl"; }
lines() { ledger "$1" | wc -l | tr -d ' '; }

q c demo >/dev/null
q demo c parser-fix >/dev/null
q demo c parallel-node >/dev/null

# --- garbage on stdin: exit 0, writes nothing ---
before=$(lines parser-fix)
out=$(printf 'not json at all' | BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q hooks) || fail "garbage exit nonzero"
echo "$out" | jq -e '.ok == true and .event_line == null' >/dev/null || fail "garbage verdict: $out"
[ "$(lines parser-fix)" = "$before" ] || fail "garbage wrote a ledger line"

# --- g binary missing: hooks exit 0 (never block); other doors still exit 2 ---
nobin() { BP3_Q_BIN="$work/none" PATH=/usr/bin:/bin ./bin/bp3 q "$@"; }
printf '{"hook_event_name":"PreToolUse"}' | nobin hooks 2>/dev/null || fail "missing binary: hooks exit nonzero"
set +e; nobin r </dev/null 2>/dev/null; code=$?; set -e
[ "$code" = 2 ] || fail "missing binary: g r exit $code, want 2"

# --- hook fires outside a bp3 repo: exit 0, writes nothing ---
mkdir -p "$work/foreign"
foreign=$(printf '{"hook_event_name":"SessionStart","session_id":"SX","cwd":"%s"}' "$work/foreign")
out=$(hooks "$foreign") || fail "foreign exit nonzero"
echo "$out" | jq -e '.ok == true and .event_line == null' >/dev/null || fail "foreign verdict: $out"
[ "$(lines parser-fix)" = "$before" ] || fail "foreign event wrote a ledger line"

# --- unbound session event: exit 0, writes nothing ---
unbound=$(printf '{"hook_event_name":"PostLLMCall","session_id":"S-unbound","cwd":"%s","usage":{"input_tokens":5,"output_tokens":1,"cached_tokens":0,"reasoning_tokens":0}}' "$repo")
out=$(hooks "$unbound")
echo "$out" | jq -e '.event_line == null and .reason == "no binding witnessed for session"' >/dev/null || fail "unbound verdict: $out"
[ "$(lines parser-fix)" = "$before" ] || fail "unbound event wrote a ledger line"

# --- reentrant call (the emitter observing itself): no binding ---
RUN0=20260101T000000Z-handoff-muse-code-test-model-c1
mkdir -p "docs/quests/demo/nodes/parser-fix/runs/$RUN0"
reentrant=$(printf '{"hook_event_name":"PreToolUse","session_id":"S-re","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parser-fix ./bin/bp3 q hooks"}}' "$repo" "$RUN0")
out=$(hooks "$reentrant")
echo "$out" | jq -e '.event_line == null and .reason == "reentrant"' >/dev/null || fail "reentrant verdict: $out"

# --- preset witnessed but no matching run folder: unbound ---
gone=$(printf '{"hook_event_name":"PreToolUse","session_id":"S-gone","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=20260101T000000Z-handoff-muse-code-test-model-c9 BP3_QUEST=demo BP3_NODE=parser-fix echo hi"}}' "$repo")
out=$(hooks "$gone")
echo "$out" | jq -e '.event_line == null' >/dev/null || fail "missing run folder verdict: $out"
[ "$(lines parser-fix)" = "$before" ] || fail "missing run folder wrote a ledger line"

# --- bound Run: run_started, tallied usage, refused, lint, settle ---
RUN1=20260101T000000Z-handoff-muse-code-test-model-c1
mkdir -p "docs/quests/demo/nodes/parser-fix/runs/$RUN1"
bind=$(printf '{"hook_event_name":"PreToolUse","session_id":"S1","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parser-fix BP3_HARNESS=muse-code BP3_MODEL=test-model ./bin/bp3 q demo r parser-fix"}}' "$repo" "$RUN1")
out=$(hooks "$bind")
echo "$out" | jq -e --arg r "$RUN1" '.ok == true and .event_line.event == "run_started" and .event_line.run_id == $r and .event_line.session_id == "S1" and (.event_line | has("ts")) and (.event_line | has("edge") | not) and (.event_line | has("from") | not) and (.event_line | has("to") | not)' >/dev/null || fail "run_started verdict: $out"
ledger parser-fix | tail -1 | jq -e --arg r "$RUN1" '.event == "run_started" and .run_id == $r and (. | has("edge") | not)' >/dev/null || fail "run_started ledger line"
out=$(q demo r parser-fix)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "event line changed state: $out"

# first binding wins: a conflicting preset in the same session is ignored
conflict=$(printf '{"hook_event_name":"PreToolUse","session_id":"S1","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=20260101T000000Z-grade-muse-code-test-model-c1 BP3_QUEST=demo BP3_NODE=parallel-node echo hi"}}' "$repo")
out=$(hooks "$conflict")
echo "$out" | jq -e '.event_line == null and .reason == "already bound"' >/dev/null || fail "first-wins verdict: $out"

# usage tallies in memory/registry only: no ledger line yet
mid=$(lines parser-fix)
usage1=$(printf '{"hook_event_name":"PostLLMCall","session_id":"S1","cwd":"%s","usage":{"input_tokens":100,"output_tokens":10,"cached_tokens":3,"reasoning_tokens":2}}' "$repo")
out=$(hooks "$usage1")
echo "$out" | jq -e '.event_line == null' >/dev/null || fail "tally verdict: $out"
usage2=$(printf '{"hook_event_name":"PostLLMCall","session_id":"S1","cwd":"%s","usage":{"input_tokens":50,"output_tokens":5,"cached_tokens":1,"reasoning_tokens":1}}' "$repo")
hooks "$usage2" >/dev/null
[ "$(lines parser-fix)" = "$mid" ] || fail "PostLLMCall wrote a ledger line before settle"

# refused bp3 q u observed in PostToolUse: refused line, state unchanged
refused=$(jq -cn --arg cwd "$repo" --arg run "$RUN1" '{hook_event_name:"PostToolUse", session_id:"S1", cwd:$cwd, tool_input:{command:("BP3_RUN_ID=" + $run + " BP3_QUEST=demo BP3_NODE=parser-fix ./bin/bp3 q demo u parser-fix handoff --commit abc --reason work")}, tool_response:"{\"ok\":false,\"error\":{\"code\":\"E_DIRTY_TREE\",\"facts\":{},\"guidance\":\"clean it\"}}"}')
out=$(hooks "$refused")
echo "$out" | jq -e '.event_line.event == "refused" and .event_line.code == "E_DIRTY_TREE" and .event_line.attempted == "handoff"' >/dev/null || fail "refused verdict: $out"
out=$(hooks "$refused")
echo "$out" | jq -e '.event_line == null' >/dev/null || fail "duplicate refused not deduped: $out"
[ "$(ledger parser-fix | grep -c '"event":"refused"')" = "1" ] || fail "refused line count"
out=$(q demo r parser-fix)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "refused line changed state: $out"

# lint exit witnessed: pass on PostToolUse, fail on PostToolUseFailure
lint_pass=$(printf '{"hook_event_name":"PostToolUse","session_id":"S1","cwd":"%s","tool_input":{"command":"make check"},"tool_response":"all green"}' "$repo")
out=$(hooks "$lint_pass")
echo "$out" | jq -e '.event_line.event == "lint_checked" and .event_line.check == "make check" and .event_line.result == "pass"' >/dev/null || fail "lint pass verdict: $out"
lint_fail=$(printf '{"hook_event_name":"PostToolUseFailure","session_id":"S1","cwd":"%s","tool_input":{"command":"make check"},"error":"exit 1"}' "$repo")
out=$(hooks "$lint_fail")
echo "$out" | jq -e '.event_line.event == "lint_checked" and .event_line.result == "fail"' >/dev/null || fail "lint fail verdict: $out"

# settle: exactly one usage_recorded with summed real fields, then run_settled
end=$(printf '{"hook_event_name":"SessionEnd","session_id":"S1","cwd":"%s"}' "$repo")
out=$(hooks "$end")
echo "$out" | jq -e '.event_line.event == "run_settled" and .event_line.outcome == "settled"' >/dev/null || fail "run_settled verdict: $out"
[ "$(ledger parser-fix | grep -c '"event":"usage_recorded"')" = "1" ] || fail "usage_recorded count"
ledger parser-fix | grep '"event":"usage_recorded"' | jq -e '.input_tokens == 150 and .output_tokens == 15 and .cached_tokens == 4 and .reasoning_tokens == 3 and (.wall_ms | type == "number") and (.started_ts | type == "string") and (.settled_ts | type == "string") and (. | has("edge") | not)' >/dev/null || fail "usage_recorded fields"
[ "$(ledger parser-fix | grep -c '"event":"run_settled"')" = "1" ] || fail "run_settled count"
out=$(hooks "$end")
echo "$out" | jq -e '.event_line == null' >/dev/null || fail "second settle not deduped: $out"
[ "$(ledger parser-fix | grep -c '"event":"usage_recorded"')" = "1" ] || fail "second settle duplicated usage"

registry() { printf '%s/bp3-run-registry.json' "$(git rev-parse --absolute-git-dir)"; }
age_binding() { # $1 = session_id: backdate last_seen past the stale gate
  local reg; reg=$(registry)
  local tmp; tmp=$(mktemp)
  jq --arg s "$1" '.sessions[$s].last_seen_epoch -= 7200' "$reg" > "$tmp"
  mv "$tmp" "$reg"
}

# --- killed session: next SessionStart sweeps run_unsettled ---
RUN2=20260101T010000Z-handoff-muse-code-test-model-c1
mkdir -p "docs/quests/demo/nodes/parser-fix/runs/$RUN2"
bind2=$(printf '{"hook_event_name":"PreToolUse","session_id":"S2","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parser-fix echo work"}}' "$repo" "$RUN2")
hooks "$bind2" >/dev/null
age_binding S2
sweep=$(printf '{"hook_event_name":"SessionStart","session_id":"S3","cwd":"%s"}' "$repo")
out=$(hooks "$sweep")
echo "$out" | jq -e --arg r "$RUN2" '.event_line.event == "run_unsettled" and .event_line.run_id == $r and (.event_line | has("last_seen_ts"))' >/dev/null || fail "run_unsettled verdict: $out"
out=$(hooks "$sweep")
echo "$out" | jq -e '.event_line == null' >/dev/null || fail "second sweep not deduped: $out"
[ "$(ledger parser-fix | grep -c '"event":"run_unsettled"')" = "1" ] || fail "run_unsettled count"

# --- live parallel Runs: a fresh SessionStart sweeps nothing ---
RUN5=20260101T030000Z-handoff-muse-code-test-model-c1
RUN6=20260101T030000Z-grade-muse-code-test-model-c1
mkdir -p "docs/quests/demo/nodes/parser-fix/runs/$RUN5" "docs/quests/demo/nodes/parallel-node/runs/$RUN6"
bind5=$(printf '{"hook_event_name":"PreToolUse","session_id":"S6","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parser-fix echo live-a"}}' "$repo" "$RUN5")
bind6=$(printf '{"hook_event_name":"PreToolUse","session_id":"S7","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parallel-node echo live-b"}}' "$repo" "$RUN6")
hooks "$bind5" >/dev/null
hooks "$bind6" >/dev/null
live_sweep=$(printf '{"hook_event_name":"SessionStart","session_id":"S8","cwd":"%s"}' "$repo")
out=$(hooks "$live_sweep")
echo "$out" | jq -e '.event_line == null' >/dev/null || fail "live parallel sweep verdict: $out"
[ "$(ledger parser-fix | grep -c '"event":"run_unsettled"')" = "1" ] || fail "live parallel run marked unsettled"
if ledger parallel-node | grep -q '"event":"run_unsettled"'; then fail "live parallel-node run marked unsettled"; fi
age_binding S6
out=$(hooks "$live_sweep")
echo "$out" | jq -e --arg r "$RUN5" '.event_line.event == "run_unsettled" and .event_line.run_id == $r' >/dev/null || fail "stale-only sweep verdict: $out"
[ "$(ledger parser-fix | grep -c '"event":"run_unsettled"')" = "2" ] || fail "stale-only sweep count"
if ledger parallel-node | grep -q '"event":"run_unsettled"'; then fail "fresh parallel-node run swept with stale sibling"; fi

# --- parallel Runs: distinct bindings, no cross-talk ---
RUN3=20260101T020000Z-handoff-muse-code-test-model-c1
RUN4=20260101T020000Z-grade-muse-code-test-model-c1
mkdir -p "docs/quests/demo/nodes/parser-fix/runs/$RUN3" "docs/quests/demo/nodes/parallel-node/runs/$RUN4"
bind3=$(printf '{"hook_event_name":"PreToolUse","session_id":"S4","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parser-fix echo a"}}' "$repo" "$RUN3")
bind4=$(printf '{"hook_event_name":"PreToolUse","session_id":"S5","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parallel-node echo b"}}' "$repo" "$RUN4")
hooks "$bind3" >/dev/null
hooks "$bind4" >/dev/null
u4=$(printf '{"hook_event_name":"PostLLMCall","session_id":"S4","cwd":"%s","usage":{"input_tokens":7,"output_tokens":1,"cached_tokens":0,"reasoning_tokens":0}}' "$repo")
u5=$(printf '{"hook_event_name":"PostLLMCall","session_id":"S5","cwd":"%s","usage":{"input_tokens":70,"output_tokens":9,"cached_tokens":0,"reasoning_tokens":0}}' "$repo")
hooks "$u4" >/dev/null
hooks "$u5" >/dev/null
end4=$(printf '{"hook_event_name":"SessionEnd","session_id":"S4","cwd":"%s"}' "$repo")
hooks "$end4" >/dev/null
ledger parser-fix | grep '"event":"usage_recorded"' | tail -1 | jq -e '.input_tokens == 7' >/dev/null || fail "parallel usage leaked into parser-fix"
if ledger parallel-node | grep -q '"event":"usage_recorded"'; then fail "unsettled parallel run gained usage early"; fi
end5=$(printf '{"hook_event_name":"SubagentStop","session_id":"S5","cwd":"%s"}' "$repo")
out=$(hooks "$end5")
echo "$out" | jq -e '.event_line.event == "run_settled"' >/dev/null || fail "SubagentStop settle: $out"
ledger parallel-node | grep '"event":"usage_recorded"' | jq -e '.input_tokens == 70' >/dev/null || fail "parallel-node usage missing"

# every event line carries ts + run_id and no edge keys; fold still reads todo
ledger parser-fix | jq -e 'select(.event != null) | (. | has("ts") and has("run_id") and (has("edge") | not) and (has("from") | not) and (has("to") | not))' >/dev/null || fail "event line shape"
out=$(q demo r parser-fix)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "fold changed by event lines: $out"

echo "hooks tests: ok"
