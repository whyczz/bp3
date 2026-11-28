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
sed 's/^max_cycles: .*/max_cycles: 1/' "$work/repo/plans/default.yaml" > "$work/repo/plans/default.yaml.tmp"; mv "$work/repo/plans/default.yaml.tmp" "$work/repo/plans/default.yaml"  # fixtures assert one review round
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

# --- fast-agy-induct agy.2: agy camelCase hook payloads ---
RUN_AGY=20260101T030000Z-handoff-agy-gemini-4-neon-c1
mkdir -p "docs/quests/demo/nodes/parser-fix/runs/$RUN_AGY"
agy_start=$(printf '{"hookEventName":"SessionStart","conversationId":"CONV1","cwd":"%s"}' "$repo")
out=$(hooks "$agy_start")
echo "$out" | jq -e '. == {}' >/dev/null || fail "agy SessionStart must reply {}: $out"
agy_pre=$(printf '{"hookEventName":"PreToolUse","conversationId":"CONV1","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_RUN_ID=%s BP3_QUEST=demo BP3_NODE=parser-fix echo hi"}}}' "$repo" "$RUN_AGY")
out=$(hooks "$agy_pre")
echo "$out" | jq -e '.decision == "allow"' >/dev/null || fail "agy PreToolUse must reply decision allow: $out"
ledger parser-fix | grep -q "\"run_id\":\"$RUN_AGY\"" || fail "agy PreToolUse did not bind run_started"
agy_post=$(printf '{"hookEventName":"PostToolUse","conversationId":"CONV1","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"make check"}}}' "$repo")
out=$(hooks "$agy_post")
echo "$out" | jq -e '. == {}' >/dev/null || fail "agy PostToolUse must reply {}: $out"
ledger parser-fix | grep "\"run_id\":\"$RUN_AGY\"" | grep -q '"event":"lint_checked"' || fail "agy PostToolUse did not emit lint_checked"
agy_stop=$(printf '{"hookEventName":"Stop","conversationId":"CONV1","cwd":"%s"}' "$repo")
out=$(hooks "$agy_stop")
echo "$out" | jq -e '. == {}' >/dev/null || fail "agy Stop must reply {}: $out"

# --- global.2: global hook from cd /tmp re-roots onto payload.cwd + backpack.toml gate ---
host_repo="$work/host-bp3"
mkdir -p "$host_repo/plans"
cp "$root"/plans/*.yaml "$host_repo/plans/"
cat > "$host_repo/backpack.toml" <<'TOML'
version = 1
repo = "host-bp3"
TOML
git -C "$host_repo" init -q -b master
git -C "$host_repo" config user.email t@t.t
git -C "$host_repo" config user.name t
git -C "$host_repo" add .
git -C "$host_repo" commit -qm "init host"
(cd "$host_repo" && BP3_ROOT="$host_repo" "$work/repo/g-bin" q c qhost >/dev/null)
(cd "$host_repo" && BP3_ROOT="$host_repo" "$work/repo/g-bin" q qhost c nhost >/dev/null)

# Notice: NO bin/bp3 in host_repo, process cwd is /tmp, BP3_ROOT is unset!
RUN_HOST=20260101T040000Z-handoff-muse-code-test-model-c1
mkdir -p "$host_repo/docs/quests/qhost/nodes/nhost/runs/$RUN_HOST"
global_hooks() { (cd /tmp && env -u BP3_ROOT "$work/repo/g-bin" q hooks <<< "$1"); }
host_ledger() { git -C "$host_repo" show "bp3/node/qhost/nhost:docs/quests/qhost/nodes/nhost/ledger.jsonl"; }

h_pre=$(printf '{"hook_event_name":"PreToolUse","session_id":"SH1","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=qhost BP3_NODE=nhost echo work"}}' "$host_repo" "$RUN_HOST")
out=$(global_hooks "$h_pre")
echo "$out" | jq -e --arg r "$RUN_HOST" '.ok == true and .event_line.event == "run_started" and .event_line.run_id == $r' >/dev/null || fail "global host run_started: $out"
host_ledger | grep -q "\"run_id\":\"$RUN_HOST\"" || fail "global host run_started missing from host ledger"

h_lint=$(printf '{"hook_event_name":"PostToolUse","session_id":"SH1","cwd":"%s","tool_input":{"command":"make check"},"tool_response":"ok"}' "$host_repo")
out=$(global_hooks "$h_lint")
echo "$out" | jq -e '.ok == true and .event_line.event == "lint_checked" and .event_line.result == "pass"' >/dev/null || fail "global host lint_checked: $out"

h_end=$(printf '{"hook_event_name":"SessionEnd","session_id":"SH1","cwd":"%s"}' "$host_repo")
out=$(global_hooks "$h_end")
echo "$out" | jq -e '.ok == true and .event_line.event == "run_settled"' >/dev/null || fail "global host run_settled: $out"
host_ledger | grep -q '"event":"run_settled"' || fail "global host run_settled missing from host ledger"

# agy workspacePaths fallback when cwd is omitted (from cd /tmp, BP3_ROOT unset)
RUN_WS=20260101T050000Z-handoff-agy-gemini-c1
mkdir -p "$host_repo/docs/quests/qhost/nodes/nhost/runs/$RUN_WS"
ws_pre=$(printf '{"hookEventName":"PreToolUse","conversationId":"CONV-WS","workspacePaths":["%s"],"toolCall":{"name":"run_command","args":{"CommandLine":"BP3_RUN_ID=%s BP3_QUEST=qhost BP3_NODE=nhost echo ws"}}}' "$host_repo" "$RUN_WS")
out=$(global_hooks "$ws_pre")
echo "$out" | jq -e '.decision == "allow"' >/dev/null || fail "global agy workspacePaths reply: $out"
host_ledger | grep -q "\"run_id\":\"$RUN_WS\"" || fail "global agy workspacePaths did not emit run_started"

# non-bp3 git repo (no backpack.toml, no bin/bp3): dormant, zero writes
non_bp3="$work/non-bp3-git"
mkdir -p "$non_bp3"
git -C "$non_bp3" init -q -b master
git -C "$non_bp3" config user.email t@t.t
git -C "$non_bp3" config user.name t
echo hi > "$non_bp3/README.md" && git -C "$non_bp3" add . && git -C "$non_bp3" commit -qm "init"
non_before=$(git -C "$non_bp3" rev-parse HEAD)
non_payload=$(printf '{"hook_event_name":"SessionStart","session_id":"SN1","cwd":"%s"}' "$non_bp3")
out=$(global_hooks "$non_payload")
echo "$out" | jq -e '.ok == true and .event_line == null and .reason == "not a bp3 repo" and (.warnings == null)' >/dev/null || fail "non-bp3 git repo verdict: $out"
[ "$(git -C "$non_bp3" rev-parse HEAD)" = "$non_before" ] || fail "non-bp3 git repo HEAD changed"
[ ! -e "$non_bp3/.git/bp3-run-registry.json" ] || fail "non-bp3 git repo created registry"

# --- session-scoped-statusline session.1: per-session quest binding (self + host) ---
sess_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/bp3/sessions"

# 1. Self repo: parallel sessions conv-A (induct) and conv-B (red-ink) isolated, zero repo dirt
s_pre_a=$(printf '{"hookEventName":"PreToolUse","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 harness desk prepare --quest q-alpha"}}}' "$repo")
out=$(hooks "$s_pre_a")
echo "$out" | jq -e '.decision == "allow"' >/dev/null || fail "session PreToolUse agy reply: $out"
[ -f "$sess_dir/conv-A.json" ] || fail "conv-A.json not written"
jq -e '.session_id == "conv-A" and .quest == "q-alpha" and .mode == "induct" and .red_ink_path == null and (.updated_ts | type == "number")' "$sess_dir/conv-A.json" >/dev/null || fail "conv-A.json content: $(cat "$sess_dir/conv-A.json")"

s_post_b=$(printf '{"hookEventName":"PostToolUse","conversationId":"conv-B","cwd":"%s","toolCall":{"name":"edit_file","args":{"Path":"%s/docs/quests/q-beta/QUEST.red-ink.md"}}}' "$repo" "$repo")
out=$(hooks "$s_post_b")
echo "$out" | jq -e '. == {}' >/dev/null || fail "session PostToolUse agy reply: $out"
[ -f "$sess_dir/conv-B.json" ] || fail "conv-B.json not written"
jq -e '.session_id == "conv-B" and .quest == "q-beta" and .mode == "red-ink" and .red_ink_path == "docs/quests/q-beta/QUEST.red-ink.md"' "$sess_dir/conv-B.json" >/dev/null || fail "conv-B.json content: $(cat "$sess_dir/conv-B.json")"
# conv-A must remain intact
jq -e '.quest == "q-alpha" and .mode == "induct"' "$sess_dir/conv-A.json" >/dev/null || fail "conv-A clobbered by conv-B"

# 2. Release clear: --dry-run and PostToolUseFailure do NOT clear; successful PostToolUse clears only matching session
s_dry=$(printf '{"hookEventName":"PostToolUse","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release q-alpha --dry-run"}}}' "$repo")
hooks "$s_dry" >/dev/null
[ -f "$sess_dir/conv-A.json" ] || fail "--dry-run must not clear conv-A.json"

s_fail=$(printf '{"hookEventName":"PostToolUseFailure","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release q-alpha"}},"error":"exit 1"}' "$repo")
hooks "$s_fail" >/dev/null
[ -f "$sess_dir/conv-A.json" ] || fail "PostToolUseFailure must not clear conv-A.json"

s_pre_rel=$(printf '{"hookEventName":"PreToolUse","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release q-alpha"}}}' "$repo")
hooks "$s_pre_rel" >/dev/null
[ -f "$sess_dir/conv-A.json" ] || fail "PreToolUse release must not clear conv-A.json before completion"

s_rel=$(printf '{"hookEventName":"PostToolUse","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release q-alpha"}}}' "$repo")
hooks "$s_rel" >/dev/null
[ ! -e "$sess_dir/conv-A.json" ] || fail "successful PostToolUse bp3 release did not clear conv-A.json"
[ -f "$sess_dir/conv-B.json" ] || fail "clearing conv-A touched conv-B.json"

# 3. Path traversal session_id is rejected safely (no file written outside sessions/)
s_bad=$(printf '{"hookEventName":"PostToolUse","conversationId":"../escape","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 q q-alpha r"}}}' "$repo")
hooks "$s_bad" >/dev/null
[ ! -e "$(dirname "$sess_dir")/escape.json" ] || fail "traversal session_id wrote outside sessions/"

# 4. SessionStart prunes >24h stale session JSON while preserving fresh session JSON
printf '{"session_id":"stale-old","quest":"old-q","mode":"induct","desk":null,"red_ink_path":null,"updated_ts":1000}\n' > "$sess_dir/stale-old.json"
s_start=$(printf '{"hookEventName":"SessionStart","conversationId":"conv-C","cwd":"%s"}' "$repo")
hooks "$s_start" >/dev/null
[ ! -e "$sess_dir/stale-old.json" ] || fail "SessionStart did not prune stale >24h session file"
[ -f "$sess_dir/conv-B.json" ] || fail "SessionStart pruned fresh conv-B.json"

# 5. Host repo (docs/quests present, NO bin/bp3): session binding, clear, and 24h GC all work identically
host="$work/host-repo"
mkdir -p "$host/docs/quests/host-q"
git -C "$host" init -q -b master
git -C "$host" config user.email t@t.t; git -C "$host" config user.name t
echo hi > "$host/README.md"
git -C "$host" add README.md
git -C "$host" commit -qm init
host_sess="$(cd "$host" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/bp3/sessions"

h_bind=$(printf '{"hookEventName":"PreToolUse","conversationId":"host-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 harness desk prepare --quest host-q"}}}' "$host")
out=$(hooks "$h_bind")
echo "$out" | jq -e '.decision == "allow"' >/dev/null || fail "host PreToolUse agy reply: $out"
[ -f "$host_sess/host-A.json" ] || fail "host repo did not write host-A.json"
jq -e '.quest == "host-q" and .mode == "induct"' "$host_sess/host-A.json" >/dev/null || fail "host-A.json content"

h_red=$(printf '{"hookEventName":"PostToolUse","conversationId":"host-B","cwd":"%s","toolCall":{"name":"edit_file","args":{"Path":"%s/docs/quests/host-q/QUEST.2b-reviewed.md"}}}' "$host" "$host")
out=$(hooks "$h_red")
echo "$out" | jq -e '. == {}' >/dev/null || fail "host PostToolUse agy reply: $out"
jq -e '.quest == "host-q" and .mode == "red-ink" and .red_ink_path == "docs/quests/host-q/QUEST.2b-reviewed.md"' "$host_sess/host-B.json" >/dev/null || fail "host-B.json content"

h_rel=$(printf '{"hookEventName":"PostToolUse","conversationId":"host-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release host-q"}}}' "$host")
hooks "$h_rel" >/dev/null
[ ! -e "$host_sess/host-A.json" ] || fail "host release did not clear host-A.json"
[ -f "$host_sess/host-B.json" ] || fail "host release touched host-B.json"

printf '{"session_id":"host-stale","quest":"old","mode":"induct","desk":null,"red_ink_path":null,"updated_ts":1000}\n' > "$host_sess/host-stale.json"
h_start=$(printf '{"hookEventName":"SessionStart","conversationId":"host-C","cwd":"%s"}' "$host")
hooks "$h_start" >/dev/null
[ ! -e "$host_sess/host-stale.json" ] || fail "host SessionStart did not prune stale session"
[ -f "$host_sess/host-B.json" ] || fail "host SessionStart pruned fresh host-B.json"
[ -z "$(git -C "$host" status --porcelain)" ] || fail "host repo dirtied by session binding"

# 6. warden-planned-gates session.1: durable quest-sessions/<q>.jsonl survives SessionStart TTL & dedupes consecutive (sid, phase)
qs_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/bp3/quest-sessions"
[ -f "$qs_dir/q-beta.jsonl" ] || fail "PostToolUse red-ink did not append quest-sessions/q-beta.jsonl"
jq -e '.sid == "conv-B" and .harness == "agy" and .phase == "red-ink" and (.ts | type == "number")' "$qs_dir/q-beta.jsonl" >/dev/null || fail "q-beta.jsonl content: $(cat "$qs_dir/q-beta.jsonl")"
# Repeat same (sid, phase) -> deduped (still 1 line)
hooks "$s_post_b" >/dev/null
[ "$(wc -l < "$qs_dir/q-beta.jsonl" | tr -d ' ')" = "1" ] || fail "duplicate consecutive (sid, phase) was not deduped"
# Transition to induct -> appends second line
s_ind_b=$(printf '{"hookEventName":"PostToolUse","conversationId":"conv-B","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 q q-beta r"}}}' "$repo")
hooks "$s_ind_b" >/dev/null
[ "$(wc -l < "$qs_dir/q-beta.jsonl" | tr -d ' ')" = "2" ] || fail "phase transition to induct did not append line"
# Survives SessionStart TTL GC
hooks "$s_start" >/dev/null
[ -f "$qs_dir/q-beta.jsonl" ] || fail "SessionStart deleted durable quest-sessions/q-beta.jsonl"

echo "hooks tests: ok"
