#!/usr/bin/env bash
# harness piece 'supervisor': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"
fixture_quests
fixture_runs
fixture_tapes

# --- supervisor mechanism (mvp.4 writer/cache; mvp.5 legacy read retired) ---
out=$(h supervisor -h) || fail "supervisor -h mvp.4 exit"
echo "$out" | grep -q "run-lifecycle-derivations" || fail "supervisor help mechanism: $out"
common=$(git rev-parse --git-common-dir)
reg="$common/bp3-run-registry.json"
evdir="$common/bp3-run-events"
mkdir -p "$evdir"
now_s=$(date +%s)
printf '%s\n' "{\"sessions\":{\"S-leg\":{\"quest\":\"toy\",\"node\":\"e1\",\"run_id\":\"L-leg\",\"settled\":true,\"last_seen_epoch\":$now_s},\"S-dup\":{\"quest\":\"toy\",\"node\":\"e1\",\"run_id\":\"R-active\",\"settled\":true,\"last_seen_epoch\":$now_s}}}" > "$reg"
printf '%s\n' '{"kind":"init_record","run_id":"L-events","harness":"pi","quest":"toy"}' > "$evdir/L-events.jsonl"
reg_hash=$(shasum -a 256 "$reg" | cut -d' ' -f1)
reg_mtime=$(stat -f %m "$reg" 2>/dev/null || stat -c %Y "$reg")
ev_hash=$(shasum -a 256 "$evdir/L-events.jsonl" | cut -d' ' -f1)

# child never told any prefix: session-owned tape still resolves
printf '%s\n' '{"type":"session","version":3,"id":"S-noprefix","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"n1","message":{"role":"user","content":"hello work"}}' '{"type":"session_closed","id":"n2"}' > fixtures/noprefix.jsonl
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-noprefix\",\"harness\":\"pi\",\"session_id\":\"S-noprefix\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/noprefix.jsonl\",\"quest\":\"toy\"}" > "$store/R-noprefix.jsonl"
out=$(h find-tape --run-id R-noprefix) || fail "find-tape no-prefix exit: $out"
echo "$out" | jq -e '.run_id == "R-noprefix" and .session_id == "S-noprefix"' >/dev/null || fail "find-tape no-prefix: $out"

# natural completion folds finished once the probe is persisted
printf '%s\n' '{"type":"message","id":"k1","message":{"role":"user","content":"cache work"}}' '{"type":"session_closed","id":"k2"}' > fixtures/cache.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-cache\",\"harness\":\"pi\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/cache.log\",\"quest\":\"toy\"}" > "$store/R-cache.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-par-a","harness":"pi","quest":"toy"}' > "$store/R-par-a.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-par-b","harness":"pi","quest":"toy"}' > "$store/R-par-b.jsonl"

sleep 1
set +e; out=$(h supervisor toy --timeout-seconds 3); set -e
last=$(echo "$out" | tail -1)
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-noprefix") | .lifecycle == "active")' >/dev/null || fail "mvp.4 no-prefix fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-cache") | .lifecycle == "finished")' >/dev/null || fail "mvp.4 finished fold: $last"
echo "$last" | jq -e '([.runs[] | select(.run_id == "L-leg")] | length) == 0' >/dev/null || fail "mvp.5 legacy registry still read: $last"
echo "$last" | jq -e '([.runs[] | select(.run_id == "L-events")] | length) == 0' >/dev/null || fail "mvp.5 legacy events still read: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-active") | .lifecycle == "active")' >/dev/null || fail "mvp.5 derived wins, no silent merge: $last"
grep -q '"kind":"observation"' "$store/R-active.jsonl" || fail "mvp.4 observation row missing"
grep -q '"lifecycle":"active"' "$store/R-active.jsonl" || fail "mvp.4 observation lifecycle missing"
grep -q '"kind":"observation"' "$store/R-cache.jsonl" || fail "mvp.4 cache-run observation missing"
[ -f "$store/R-active.json" ] || fail "mvp.4 derived cache missing"
jq -e '.run_id == "R-active" and .lifecycle == "active"' "$store/R-active.json" >/dev/null || fail "mvp.4 derived cache content"
jq -e '.run_id == "R-cache" and .lifecycle == "finished"' "$store/R-cache.json" >/dev/null || fail "mvp.4 finished cache content"
grep -q "R-par-b" "$store/R-par-a.jsonl" && fail "mvp.4 parallel files cross-contaminated" || true
grep -q '"run_id":"R-par-a"' "$store/R-par-a.jsonl" || fail "mvp.4 parallel file a"
grep -q '"run_id":"R-par-b"' "$store/R-par-b.jsonl" || fail "mvp.4 parallel file b"
[ "$(shasum -a 256 "$reg" | cut -d' ' -f1)" = "$reg_hash" ] || fail "mvp.5 legacy registry rewritten"
[ "$(stat -f %m "$reg" 2>/dev/null || stat -c %Y "$reg")" = "$reg_mtime" ] || fail "mvp.5 legacy registry mtime moved"
[ "$(shasum -a 256 "$evdir/L-events.jsonl" | cut -d' ' -f1)" = "$ev_hash" ] || fail "mvp.5 legacy events rewritten"
kill -0 "$LIVE" 2>/dev/null || fail "mvp.4 passive supervisor disturbed a live pid"

# derived cache is disposable: deleting it rebuilds the same verdict
runs_before=$(echo "$last" | jq -cS '.runs | sort_by(.run_id)')
rm "$store/R-active.json"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
runs_after=$(echo "$out" | tail -1 | jq -cS '.runs | sort_by(.run_id)')
[ "$runs_before" = "$runs_after" ] || fail "mvp.4 cache deletion changed verdict: $runs_before vs $runs_after"
[ -f "$store/R-active.json" ] || fail "mvp.4 cache not rebuilt"

# stale cache is ignored: wrong fingerprints force a refold
printf '%s\n' '{"kind":"derived_state","run_id":"R-cache","harness":"pi","lifecycle":"init","warnings":[],"pid_alive":false,"fresh":false,"silence_seconds":600,"jsonl_size":999999,"jsonl_mtime":0,"tape_size":0,"tape_mtime":0}' > "$store/R-cache.json"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e '(.runs[] | select(.run_id == "R-cache") | .lifecycle == "finished")' >/dev/null || fail "mvp.4 stale cache trusted: $out"
kill $LIVE 2>/dev/null || true

echo "harness/supervisor: ok"
