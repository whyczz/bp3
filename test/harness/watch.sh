#!/usr/bin/env bash
# harness piece 'watch': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"
fixture_quests
fixture_runs
fixture_tapes

# --- watch (mvp.3): blocking done-signal, sole killer ---
if out=$(h watch 2>&1); then fail "watch neither identity accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "watch neither code: $out"
if out=$(h watch --run-id R-find --session-id S-other 2>&1); then fail "watch disagreeing accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "watch disagreeing code: $out"
if out=$(h watch --run-id R-find --run-id R-find 2>&1); then fail "watch duplicate accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "watch duplicate code: $out"
if out=$(h watch --run-id=R-find 2>&1); then fail "watch --flag=value accepted"; fi
if out=$(h watch --run-id R-find --silence-seconds 0 2>&1); then fail "watch zero silence accepted"; fi
if out=$(h watch --run-id R-find --timeout-seconds 30m 2>&1); then fail "watch suffixed timeout accepted"; fi
if out=$(h watch --run-id R-find --engine pi 2>&1); then fail "watch stated engine accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "watch engine code: $out"
if out=$(h watch --run-id "a/b" --timeout-seconds 1 2>&1); then fail "watch invalid run-id accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "watch invalid code: $out"
if out=$(h watch --run-id R-nope --timeout-seconds 1 2>&1); then fail "watch unknown run accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "watch unknown code: $out"
cp fixtures/pi-store/pi1.jsonl fixtures/pi-store/pi2.jsonl
if out=$(h watch --run-id R-pi-run --timeout-seconds 1 2>&1); then fail "watch ambiguous accepted"; fi
echo "$out" | jq -e '.error.code == "E_AMBIGUOUS"' >/dev/null || fail "watch ambiguous code: $out"
rm fixtures/pi-store/pi2.jsonl

mkdir -p fixtures/watch
printf '%s\n' '{"type":"message","id":"w1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-clean work"}}' '{"type":"session_closed","id":"w2"}' > fixtures/watch/clean.log
sleep 1 & CLEANPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-clean\",\"harness\":\"pi\",\"session_id\":\"S-watch-clean\",\"pid\":$CLEANPID,\"tape_path\":\"$work/repo/fixtures/watch/clean.log\",\"quest\":\"toy\"}" > "$store/R-watch-clean.jsonl"
out=$(h watch --run-id R-watch-clean --timeout-seconds 5) || fail "watch clean exit: $out"
echo "$out" | tail -1 | jq -e '.ok == true and .outcome == "settled" and .settled == true and .lifecycle == "finished" and .run_id == "R-watch-clean"' >/dev/null || fail "watch clean verdict: $out"
echo "$out" | while IFS= read -r line; do echo "$line" | jq -e . >/dev/null || fail "watch non-JSON stdout line: $line"; done
wait "$CLEANPID" 2>/dev/null || true
out=$(h w --session-id S-watch-clean --timeout-seconds 5) || fail "watch alias reverse exit: $out"
echo "$out" | tail -1 | jq -e '.outcome == "settled" and .run_id == "R-watch-clean"' >/dev/null || fail "watch alias reverse verdict: $out"

# watch --once (seam.2): one read-only fold; never waits, never signals.
out=$(h watch --run-id R-watch-clean --once) || fail "watch once finished exit: $out"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "watch once printed more than one line: $out"
echo "$out" | jq -e '.outcome == "settled" and .lifecycle == "finished" and .once == true' >/dev/null || fail "watch once finished verdict: $out"
if out=$(h watch --run-id R-watch-clean --once --once 2>&1); then fail "watch duplicate --once accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "watch duplicate --once code: $out"
printf '%s\n' '{"type":"message","id":"o1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-once work"}}' > fixtures/watch/once.log
sleep 30 & ONCEPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-once\",\"harness\":\"pi\",\"pid\":$ONCEPID,\"tape_path\":\"$work/repo/fixtures/watch/once.log\",\"quest\":\"toy\"}" > "$store/R-watch-once.jsonl"
once_start=$(date +%s)
out=$(h watch --run-id R-watch-once --once) || fail "watch once live exit: $out"
[ $(( $(date +%s) - once_start )) -le 1 ] || fail "watch once waited on a live run"
echo "$out" | jq -e '.outcome == "snapshot" and .lifecycle == "active" and .settled == false and .once == true' >/dev/null || fail "watch once live verdict: $out"
kill -0 "$ONCEPID" 2>/dev/null || fail "watch --once signalled a live run"
kill "$ONCEPID" 2>/dev/null || true; wait "$ONCEPID" 2>/dev/null || true
h watch -h | grep -q -- '--once' || fail "watch help does not document --once"

printf '%s\n' '{"type":"message","id":"h1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-hung work"}}' > fixtures/watch/hung.log
sleep 30 & HUNGPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-hung\",\"harness\":\"pi\",\"pid\":$HUNGPID,\"tape_path\":\"$work/repo/fixtures/watch/hung.log\",\"quest\":\"toy\"}" > "$store/R-watch-hung.jsonl"
set +e; out=$(h watch --run-id R-watch-hung --silence-seconds 1 --grace-seconds 1 --timeout-seconds 10); rc=$?; set -e
[ "$rc" = 1 ] || fail "watch hung exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "watchdog_killed" and .settled == false and .lifecycle == "orphaned"' >/dev/null || fail "watch hung verdict: $out"
wait "$HUNGPID" 2>/dev/null || true
if kill -0 "$HUNGPID" 2>/dev/null; then fail "hung pid survived watch"; fi

cat > fixtures/watch/stubborn.sh <<'EOS'
#!/usr/bin/env bash
trap '' TERM
while true; do sleep 0.2; done
EOS
chmod +x fixtures/watch/stubborn.sh
printf '%s\n' '{"type":"message","id":"t1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-stubborn work"}}' > fixtures/watch/stubborn.log
fixtures/watch/stubborn.sh & STUBPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-stubborn\",\"harness\":\"pi\",\"pid\":$STUBPID,\"tape_path\":\"$work/repo/fixtures/watch/stubborn.log\",\"quest\":\"toy\"}" > "$store/R-watch-stubborn.jsonl"
set +e; out=$(h watch --run-id R-watch-stubborn --silence-seconds 1 --grace-seconds 1 --timeout-seconds 10); rc=$?; set -e
[ "$rc" = 1 ] || fail "watch stubborn exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "watchdog_killed" and .settled == false and .lifecycle == "orphaned"' >/dev/null || fail "watch stubborn verdict: $out"
wait "$STUBPID" 2>/dev/null || true
if kill -0 "$STUBPID" 2>/dev/null; then fail "stubborn pid survived SIGKILL"; fi

cat > fixtures/watch/drip.sh <<'EOS'
#!/usr/bin/env bash
tape="$1"
for i in 1 2 3 4 5 6; do echo "drip $i" >> "$tape"; sleep 0.3; done
echo '{"type":"session_closed","id":"d9"}' >> "$tape"
EOS
chmod +x fixtures/watch/drip.sh
printf '%s\n' '{"type":"message","id":"p1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-drip work"}}' > fixtures/watch/drip.log
fixtures/watch/drip.sh "$work/repo/fixtures/watch/drip.log" & DRIPPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-drip\",\"harness\":\"pi\",\"pid\":$DRIPPID,\"tape_path\":\"$work/repo/fixtures/watch/drip.log\",\"quest\":\"toy\"}" > "$store/R-watch-drip.jsonl"
out=$(h watch --run-id R-watch-drip --silence-seconds 1 --grace-seconds 1 --timeout-seconds 10) || fail "watch drip exit: $out"
echo "$out" | tail -1 | jq -e '.outcome == "settled" and .settled == true and .lifecycle == "finished"' >/dev/null || fail "watch drip verdict: $out"
wait "$DRIPPID" 2>/dev/null || true

sleep 30 & BLINDPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-blind\",\"harness\":\"pi\",\"pid\":$BLINDPID,\"tape_path\":\"$work/repo/fixtures/watch/missing.log\",\"quest\":\"toy\"}" > "$store/R-watch-blind.jsonl"
set +e; out=$(h watch --run-id R-watch-blind --silence-seconds 1 --grace-seconds 1 --timeout-seconds 10); rc=$?; set -e
[ "$rc" = 1 ] || fail "watch blind exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "watchdog_killed" and .settled == false and (.warnings | index("W_SUPERVISOR_BLIND") != null)' >/dev/null || fail "watch blind verdict: $out"
wait "$BLINDPID" 2>/dev/null || true
if kill -0 "$BLINDPID" 2>/dev/null; then fail "blind pid survived watch"; fi

printf '%s\n' '{"type":"message","id":"c1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-closed work"}}' '{"type":"session_closed","id":"c2"}' > fixtures/watch/closed.log
sleep 30 & CLOSEDPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-closed\",\"harness\":\"pi\",\"pid\":$CLOSEDPID,\"tape_path\":\"$work/repo/fixtures/watch/closed.log\",\"quest\":\"toy\"}" > "$store/R-watch-closed.jsonl"
set +e; out=$(h watch --run-id R-watch-closed --silence-seconds 1 --grace-seconds 1 --timeout-seconds 2); rc=$?; set -e
[ "$rc" = 3 ] || fail "watch closed exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "timeout" and .settled == false and .lifecycle == "active"' >/dev/null || fail "watch closed verdict: $out"
kill -0 "$CLOSEDPID" 2>/dev/null || fail "closed-but-not-exited pid was killed"
kill "$CLOSEDPID" 2>/dev/null || true
wait "$CLOSEDPID" 2>/dev/null || true

printf '%s\n' '{"type":"message","id":"s1","message":{"role":"user","content":"BP3_RUN_ID=R-watch-settle work"}}' > fixtures/watch/settle.log
sleep 30 & SETTLEPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-watch-settle\",\"harness\":\"pi\",\"pid\":$SETTLEPID,\"tape_path\":\"$work/repo/fixtures/watch/settle.log\",\"quest\":\"toy\"}" '{"kind":"observation","settle_row":true,"tape_closed":false}' > "$store/R-watch-settle.jsonl"
set +e; out=$(h watch --run-id R-watch-settle --silence-seconds 1 --grace-seconds 1 --timeout-seconds 2); rc=$?; set -e
[ "$rc" = 3 ] || fail "watch settle exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "timeout" and .settled == false' >/dev/null || fail "watch settle verdict: $out"
kill -0 "$SETTLEPID" 2>/dev/null || fail "settling pid was killed"
kill "$SETTLEPID" 2>/dev/null || true
wait "$SETTLEPID" 2>/dev/null || true

# tick is idempotent: same fold, same runs on rerun
set +e; out=$(h supervisor toy --timeout-seconds 1); out2=$(h supervisor toy --timeout-seconds 1); set -e
r1=$(echo "$out" | tail -1 | jq -cS '.runs | sort_by(.run_id)')
r2=$(echo "$out2" | tail -1 | jq -cS '.runs | sort_by(.run_id)')
[ "$r1" = "$r2" ] || fail "tick not idempotent: $r1 vs $r2"

echo "harness/watch: ok"
