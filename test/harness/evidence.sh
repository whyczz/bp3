#!/usr/bin/env bash
# harness piece 'evidence': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"
fixture_quests
fixture_runs
fixture_tapes
fixture_watch_dir

# --- record-init retired (mvp.1): the run config replaces it ---
out=$(h record-init -h) || fail "record-init -h exit"
echo "$out" | grep -q "record-init" || fail "record-init help: $out"
echo "$out" | grep -q "E_RETIRED" || fail "record-init help codes: $out"
out=$(h r -h) || fail "alias r -h exit"
echo "$out" | grep -q "record-init" || fail "alias r help: $out"
out=$(h -h) || fail "harness -h exit"
echo "$out" | grep -q "record-init" || fail "harness help lists record-init: $out"
echo "$out" | grep -q "link" || fail "harness help lists link: $out"
if out=$(h record-init --run-id R-x --harness pi 2>&1); then fail "record-init accepted"; fi
echo "$out" | jq -e '.error.code == "E_RETIRED"' >/dev/null || fail "record-init code: $out"
if out=$(h r --run-id R-x --harness pi 2>&1); then fail "record-init alias accepted"; fi
echo "$out" | jq -e '.error.code == "E_RETIRED"' >/dev/null || fail "record-init alias code: $out"

# born lookup-able (legacy derivation fixture): the record lands
# before any tape entry exists; link-born runs are covered in link.sh
printf '%s\n' '{"kind":"init_record","run_id":"R-born","harness":"muse-code","quest":"toy","node":"e1","session_id":"S-born","ts":"2026-01-01T00:00:00Z"}' > "$store/R-born.jsonl"
head -1 "$store/R-born.jsonl" | jq -e '.kind == "init_record" and .run_id == "R-born" and .harness == "muse-code" and (.ts | type == "string")' >/dev/null || fail "born init row: $(head -1 "$store/R-born.jsonl")"
mkdir -p fixtures/muse-store/S-born
printf '%s\n' '{"session_id":"S-born","id":"b1","content":"BP3_RUN_ID=R-born work"}' > fixtures/muse-store/S-born/session.jsonl
[ ! fixtures/muse-store/S-born/session.jsonl -ot "$store/R-born.jsonl" ] || fail "tape predates its InitRecord"
out=$(h find-tape --run-id R-born) || fail "find-tape born exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/muse-store/S-born/session.jsonl" '.ok == true and .run_id == "R-born" and .harness == "muse-code" and .session_id == "S-born" and .wal == $w' >/dev/null || fail "find-tape born: $out"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e '(.runs[] | select(.run_id == "R-born"))' >/dev/null || fail "born run invisible to supervisor: $out"

# killed mid-spawn: record first, dead pid, stale tape -> orphaned, never invisible
printf '%s\n' '{"type":"message","id":"k9","message":{"role":"user","content":"BP3_RUN_ID=R-killed work"}}' > fixtures/killed.log
touch -t 202001010000 fixtures/killed.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-killed\",\"harness\":\"muse-code\",\"quest\":\"toy\",\"node\":\"e1\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/killed.log\"}" > "$store/R-killed.jsonl"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e '(.runs[] | select(.run_id == "R-killed") | .lifecycle == "orphaned")' >/dev/null || fail "killed run not orphaned: $out"

# --- finish evidence (followup.2): per-harness, tail-scoped ---
sleep 60 & F2LIVE=$!
# muse child tape: exit entry (runtime terminal), no close marker
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' '{"payload_type":"runtime.session","payload":{"kind":"run","run_id":"x","event":{"kind":"terminal","terminal":"completed"}}}' > fixtures/f2-muse-exit.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-muse-exit\",\"harness\":\"muse-code\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/f2-muse-exit.log\"}" > "$store/R-f2-muse-exit.jsonl"
# muse main tape: session.end close marker
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' '{"payload_type":"session.end","payload":{"kind":"session_end"}}' > fixtures/f2-muse-end.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-muse-end\",\"harness\":\"muse-code\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/f2-muse-end.log\"}" > "$store/R-f2-muse-end.jsonl"
# same exit entry, live pid, stale tape: pid alive wins, never finished
cp fixtures/f2-muse-exit.log fixtures/f2-muse-live.log
touch -t 202001010000 fixtures/f2-muse-live.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-muse-live\",\"harness\":\"muse-code\",\"quest\":\"toy\",\"pid\":$F2LIVE,\"tape_path\":\"$work/repo/fixtures/f2-muse-live.log\"}" > "$store/R-f2-muse-live.jsonl"
# pi clean exit: final assistant entry stopped, pid dead
printf '%s\n' '{"type":"session","version":3,"id":"S-f2-pi","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"p1","message":{"role":"user","content":"work"}}' '{"type":"message","id":"p2","message":{"role":"assistant","stopReason":"stop","content":[]}}' > fixtures/f2-pi-exit.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-pi-exit\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/f2-pi-exit.log\"}" > "$store/R-f2-pi-exit.jsonl"
# pi died mid-work: final entry is a tool call, stale, pid dead
printf '%s\n' '{"type":"session","version":3,"id":"S-f2-pic","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"q1","message":{"role":"assistant","stopReason":"toolUse","content":[]}}' > fixtures/f2-pi-crash.log
touch -t 202001010000 fixtures/f2-pi-crash.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-pi-crash\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/f2-pi-crash.log\"}" > "$store/R-f2-pi-crash.jsonl"
# truncated mid-entry: torn final entry finishes nothing
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' > fixtures/f2-torn.log
printf '%s' '{"payload_type":"session.end","payl' >> fixtures/f2-torn.log
touch -t 202001010000 fixtures/f2-torn.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-torn\",\"harness\":\"muse-code\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/f2-torn.log\"}" > "$store/R-f2-torn.jsonl"

set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
last=$(echo "$out" | tail -1)
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f2-muse-exit") | .lifecycle == "finished")' >/dev/null || fail "followup.2 muse exit-entry fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f2-muse-end") | .lifecycle == "finished")' >/dev/null || fail "followup.2 muse close-marker fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f2-muse-live") | .lifecycle == "active")' >/dev/null || fail "followup.2 live pid wins: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f2-pi-exit") | .lifecycle == "finished")' >/dev/null || fail "followup.2 pi process-exit fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f2-pi-crash") | .lifecycle == "orphaned")' >/dev/null || fail "followup.2 pi crash fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f2-torn") | .lifecycle == "orphaned")' >/dev/null || fail "followup.2 torn fold: $last"
echo "$last" | jq -e '(.warnings | index("W_TORN_TAIL") != null)' >/dev/null || fail "followup.2 torn warning: $last"
kill $F2LIVE 2>/dev/null || true

# watch settles a muse child tape on its exit entry, no close marker
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' '{"payload_type":"runtime.session","payload":{"kind":"run","run_id":"y","event":{"kind":"terminal","terminal":"completed"}}}' > fixtures/watch/f2-muse.log
sleep 1 & F2WPID=$!
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f2-watch-muse\",\"harness\":\"muse-code\",\"pid\":$F2WPID,\"tape_path\":\"$work/repo/fixtures/watch/f2-muse.log\",\"quest\":\"toy\"}" > "$store/R-f2-watch-muse.jsonl"
out=$(h watch --run-id R-f2-watch-muse --timeout-seconds 5) || fail "followup.2 watch muse exit: $out"
echo "$out" | tail -1 | jq -e '.outcome == "settled" and .settled == true and .lifecycle == "finished"' >/dev/null || fail "followup.2 watch muse verdict: $out"
wait "$F2WPID" 2>/dev/null || true

# --- tape binding (followup.3): bind-tape verb, fold honor, tail scan ---
out=$(h bind-tape -h) || fail "bind-tape -h exit"
echo "$out" | grep -q "bind-tape" || fail "bind-tape help: $out"
echo "$out" | grep -q "E_NOT_FOUND" || fail "bind-tape help codes: $out"
out=$(h t -h) || fail "alias t -h exit"
echo "$out" | grep -q "bind-tape" || fail "alias t help: $out"
out=$(h -h) || fail "harness -h followup.3 exit"
echo "$out" | grep -q "bind-tape" || fail "harness help lists bind-tape: $out"
if out=$(h bind-tape --tape-path fixtures/f3-bound.log 2>&1); then fail "bind-tape without run-id accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "bind-tape no-run code: $out"
if out=$(h bind-tape --run-id R-f3-bound 2>&1); then fail "bind-tape without tape-path accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "bind-tape no-tape code: $out"
if out=$(h bind-tape --run-id "a/b" --tape-path fixtures/f3-bound.log 2>&1); then fail "bind-tape slash run-id accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "bind-tape slash code: $out"
if out=$(h bind-tape --run-id R-f3-bound --run-id R-f3-bound --tape-path fixtures/f3-bound.log 2>&1); then fail "bind-tape duplicate accepted"; fi
if out=$(h bind-tape --run-id=R-f3-bound --tape-path fixtures/f3-bound.log 2>&1); then fail "bind-tape --flag=value accepted"; fi
if out=$(h bind-tape --run-id R-nope --tape-path fixtures/f3-bound.log 2>&1); then fail "bind-tape unknown run accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "bind-tape unknown code: $out"

sleep 60 & F3LIVE=$!
# real Muse closing shape: run terminal, then trailing task entries
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked","record":{"command":"BP3_RUN_ID=R-f3-bound work"}}}' '{"payload_type":"runtime.session","payload":{"kind":"run","run_id":"x","event":{"kind":"terminal","terminal":"completed"}}}' '{"payload_type":"runtime.session","payload":{"kind":"task","run_id":"x","task_id":"t1","event":{"kind":"completed","task_id":"t1"}}}' '{"payload_type":"runtime.session","payload":{"kind":"task","run_id":"x","task_id":"t2","event":{"kind":"completed","task_id":"t2"}}}' > fixtures/f3-bound.log
# close marker buried mid-tape is content, never an ending
printf '%s\n' '{"payload_type":"session.end","payload":{"kind":"session_end"}}' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' > fixtures/f3-mid.log
# torn tails: unterminated fragment, and an unparseable whole entry
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' > fixtures/f3-torn.log
printf '%s' '{"payload_type":"session.end","payl' >> fixtures/f3-torn.log
touch -t 202001010000 fixtures/f3-torn.log
printf '%s\n' '{"payload_type":"runtime.session","payload":{"kind":"run","run_id":"x","event":{"kind":"terminal","terminal":"completed"}}}' '{"oops' > fixtures/f3-bad.log
touch -t 202001010000 fixtures/f3-bad.log
printf '%s\n' '{"kind":"init_record","run_id":"R-f3-bound","harness":"muse-code","quest":"toy"}' > "$store/R-f3-bound.jsonl"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-f3-live\",\"harness\":\"muse-code\",\"quest\":\"toy\",\"pid\":$F3LIVE}" > "$store/R-f3-live.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-f3-mid","harness":"muse-code","quest":"toy","pid":999999}' > "$store/R-f3-mid.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-f3-torn","harness":"muse-code","quest":"toy","pid":999999}' > "$store/R-f3-torn.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-f3-bad","harness":"muse-code","quest":"toy","pid":999999}' > "$store/R-f3-bad.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-f3-rebind","harness":"muse-code","quest":"toy"}' > "$store/R-f3-rebind.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-f3-other","harness":"muse-code","quest":"toy"}' > "$store/R-f3-other.jsonl"
cp fixtures/f3-bound.log fixtures/f3-live.log
cp fixtures/f3-mid.log fixtures/f3-rebind-a.log
cp fixtures/f3-bound.log fixtures/f3-rebind-b.log

# no binding, no tape path: init, and the probe is blind
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
last=$(echo "$out" | tail -1)
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-bound") | .lifecycle == "init")' >/dev/null || fail "followup.3 unbound fold: $last"
echo "$last" | jq -e '(.warnings | index("W_SUPERVISOR_BLIND") != null)' >/dev/null || fail "followup.3 unbound blind warning: $last"
grep -q '"kind":"observation"' "$store/R-f3-bound.jsonl" || fail "followup.3 blind probe row missing"
grep -q 'W_SUPERVISOR_BLIND' "$store/R-f3-bound.jsonl" || fail "followup.3 blind probe warning missing"

# the launcher binds each finished child's session tape (pointer only)
out=$(h bind-tape --run-id R-f3-bound --tape-path "$work/repo/fixtures/f3-bound.log") || fail "bind-tape bound exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/f3-bound.log" '.ok == true and .run_id == "R-f3-bound" and .tape_path == $w' >/dev/null || fail "bind-tape bound verdict: $out"
tail -1 "$store/R-f3-bound.jsonl" | jq -e --arg w "$work/repo/fixtures/f3-bound.log" '.kind == "tape_binding" and .run_id == "R-f3-bound" and .tape_path == $w and (.ts | type == "string") and ((keys | length) == 4)' >/dev/null || fail "followup.3 binding row not pointer-only: $(tail -1 "$store/R-f3-bound.jsonl")"
h bind-tape --run-id R-f3-live --tape-path "$work/repo/fixtures/f3-live.log" >/dev/null || fail "bind-tape live exit"
h bind-tape --run-id R-f3-mid --tape-path "$work/repo/fixtures/f3-mid.log" >/dev/null || fail "bind-tape mid exit"
h bind-tape --run-id R-f3-torn --tape-path "$work/repo/fixtures/f3-torn.log" >/dev/null || fail "bind-tape torn exit"
h bind-tape --run-id R-f3-bad --tape-path "$work/repo/fixtures/f3-bad.log" >/dev/null || fail "bind-tape bad exit"
h bind-tape --run-id R-f3-rebind --tape-path "$work/repo/fixtures/f3-rebind-a.log" >/dev/null || fail "bind-tape rebind first exit"
out=$(h t --run-id R-f3-rebind --tape-path "$work/repo/fixtures/f3-rebind-a.log") || fail "bind-tape alias exit: $out"
echo "$out" | jq -e '.ok == true and .run_id == "R-f3-rebind"' >/dev/null || fail "bind-tape alias verdict: $out"

# pinned (followup.4): same tape again is a no-op, a second
# different tape refuses, and a bound tape names no second Run
out=$(h bind-tape --run-id R-f3-bound --tape-path "$work/repo/fixtures/f3-bound.log") || fail "bind-tape same-tape exit: $out"
echo "$out" | jq -e '.ok == true and .run_id == "R-f3-bound"' >/dev/null || fail "bind-tape same-tape verdict: $out"
[ "$(grep -c '"kind":"tape_binding"' "$store/R-f3-bound.jsonl")" = 1 ] || fail "bind-tape same-tape wrote a second row"
if out=$(h bind-tape --run-id R-f3-rebind --tape-path "$work/repo/fixtures/f3-rebind-b.log" 2>&1); then fail "bind-tape second tape accepted"; fi
echo "$out" | jq -e '.error.code == "E_EXISTS"' >/dev/null || fail "bind-tape second tape code: $out"
if out=$(h bind-tape --run-id R-f3-other --tape-path "$work/repo/fixtures/f3-bound.log" 2>&1); then fail "bind-tape bound tape accepted for another run"; fi
echo "$out" | jq -e '.error.code == "E_EXISTS"' >/dev/null || fail "bind-tape bound tape code: $out"

set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
last=$(echo "$out" | tail -1)
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-bound") | .lifecycle == "finished")' >/dev/null || fail "followup.3 bound fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-live") | .lifecycle == "active")' >/dev/null || fail "followup.3 live pid never finished: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-mid") | .lifecycle == "active")' >/dev/null || fail "followup.3 mid-tape marker fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-torn") | .lifecycle == "orphaned")' >/dev/null || fail "followup.3 torn bound fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-bad") | .lifecycle == "orphaned")' >/dev/null || fail "followup.3 unparseable bound fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-f3-rebind") | .lifecycle == "active")' >/dev/null || fail "followup.4 pinned first binding fold: $last"
echo "$last" | jq -e '(.warnings | index("W_TORN_TAIL") != null)' >/dev/null || fail "followup.3 torn bound warning: $last"
grep -q '"kind":"observation"' "$store/R-f3-bound.jsonl" || fail "followup.3 bound observation missing"
grep -q "\"tape_path\":\"$work/repo/fixtures/f3-bound.log\"" "$store/R-f3-bound.jsonl" || fail "followup.3 observation tape pointer missing"
out=$(h find-tape --run-id R-f3-bound) || fail "followup.3 find-tape bound exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/f3-bound.log" '.ok == true and .run_id == "R-f3-bound" and .wal == $w' >/dev/null || fail "followup.3 find-tape bound: $out"
out=$(h watch --run-id R-f3-bound --timeout-seconds 5) || fail "followup.3 watch bound exit: $out"
echo "$out" | tail -1 | jq -e '.outcome == "settled" and .settled == true and .lifecycle == "finished"' >/dev/null || fail "followup.3 watch bound verdict: $out"
kill $F3LIVE 2>/dev/null || true

# --- bind resolution (followup.4): own engine-fsm-edge, start order ---
out=$(h find-tape -h) || fail "find-tape -h followup.4 exit"
echo "$out" | grep -q "engine-fsm-edge" || fail "find-tape help engine-fsm-edge: $out"
out=$(h bind-tape -h) || fail "bind-tape -h followup.4 exit"
echo "$out" | grep -q "pinned" || fail "bind-tape help pinned: $out"
echo "$out" | grep -q "E_EXISTS" || fail "bind-tape help E_EXISTS: $out"

# the live sibling shape: init and resolve tapes bind the id to
# their own verbs, the conductor quotes the author's invocation
# but started before the InitRecord, the author carries it after
F4RUN="20260101T000000Z-handoff-pi-test-model-c1"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"$F4RUN\",\"harness\":\"pi\",\"quest\":\"toy\",\"node\":\"e1\",\"ts\":\"2026-01-01T00:00:00Z\"}" > "$store/$F4RUN.jsonl"
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-init","timestamp":"2026-01-01T00:00:10Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"i1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4RUN bp3 harness record-init --run-id $F4RUN\"}}" > fixtures/pi-store/f4-init.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-resolve","timestamp":"2026-01-01T00:00:20Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"v1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4RUN bp3 harness find-tape --run-id $F4RUN\"}}" > fixtures/pi-store/f4-resolve.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-conductor","timestamp":"2025-12-31T23:59:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"c1\",\"message\":{\"role\":\"user\",\"content\":\"brief: BP3_RUN_ID=$F4RUN bp3 q toy u e1 handoff --commit abc --reason work\"}}" "{\"run_id\":\"$F4RUN\",\"note\":\"conductor quotes the run\"}" > fixtures/pi-store/f4-conductor.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-author","timestamp":"2026-01-01T00:01:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4RUN bp3 q toy u e1 handoff --commit abc --reason work\"}}" > fixtures/pi-store/f4-author.jsonl
out=$(h find-tape --run-id "$F4RUN") || fail "followup.4 find-tape exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/pi-store/f4-author.jsonl" '.ok == true and .wal == $w' >/dev/null || fail "followup.4 own engine-fsm-edge resolves author: $out"
set +e; out=$(h watch --run-id "$F4RUN" --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e --arg w "$work/repo/fixtures/pi-store/f4-author.jsonl" '.wal == $w and .outcome == "timeout"' >/dev/null || fail "followup.4 watch shares engine-fsm-edge: $out"

# no own engine-fsm-edge tape among several references: typed refusal
F4NONE="20260101T000000Z-handoff-pi-test-model-c2"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"$F4NONE\",\"harness\":\"pi\",\"quest\":\"toy\",\"node\":\"e1\",\"ts\":\"2026-01-01T00:00:00Z\"}" > "$store/$F4NONE.jsonl"
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-none-init","timestamp":"2026-01-01T00:00:10Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"i1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4NONE bp3 harness record-init --run-id $F4NONE\"}}" > fixtures/pi-store/f4-none-init.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-none-resolve","timestamp":"2026-01-01T00:00:20Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"v1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4NONE bp3 harness find-tape --run-id $F4NONE\"}}" > fixtures/pi-store/f4-none-resolve.jsonl
if out=$(h find-tape --run-id "$F4NONE" 2>&1); then fail "followup.4 no-own-edge accepted"; fi
echo "$out" | jq -e '.error.code == "E_AMBIGUOUS"' >/dev/null || fail "followup.4 no-own-edge code: $out"
echo "$out" | grep -q "f4-none-init" || fail "followup.4 no-own-edge names init: $out"
echo "$out" | grep -q "f4-none-resolve" || fail "followup.4 no-own-edge names resolve: $out"

# two own engine-fsm-edge tapes started at the same time: tie refuses
F4TWO="20260101T000000Z-handoff-pi-test-model-c3"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"$F4TWO\",\"harness\":\"pi\",\"quest\":\"toy\",\"node\":\"e1\",\"ts\":\"2026-01-01T00:00:00Z\"}" > "$store/$F4TWO.jsonl"
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-two-a","timestamp":"2026-01-01T00:02:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4TWO bp3 q toy u e1 handoff --commit abc --reason work\"}}" > fixtures/pi-store/f4-two-a.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-two-b","timestamp":"2026-01-01T00:02:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a2\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4TWO bp3 q toy u e1 handoff --commit def --reason work\"}}" > fixtures/pi-store/f4-two-b.jsonl
if out=$(h find-tape --run-id "$F4TWO" 2>&1); then fail "followup.4 tied own-edge accepted"; fi
echo "$out" | jq -e '.error.code == "E_AMBIGUOUS"' >/dev/null || fail "followup.4 tied own-edge code: $out"
if out=$(h watch --run-id "$F4TWO" --timeout-seconds 1 2>&1); then fail "followup.4 watch tied own-edge accepted"; fi
echo "$out" | jq -e '.error.code == "E_AMBIGUOUS"' >/dev/null || fail "followup.4 watch tied own-edge code: $out"

# two viable own engine-fsm-edge tapes: the earliest session wins
F4EARLY="20260101T000000Z-handoff-pi-test-model-c4"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"$F4EARLY\",\"harness\":\"pi\",\"quest\":\"toy\",\"node\":\"e1\",\"ts\":\"2026-01-01T00:00:00Z\"}" > "$store/$F4EARLY.jsonl"
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-early-a","timestamp":"2026-01-01T00:03:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4EARLY bp3 q toy u e1 handoff --commit abc --reason work\"}}" > fixtures/pi-store/f4-early-a.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-early-b","timestamp":"2026-01-01T00:02:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a2\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4EARLY bp3 q toy u e1 handoff --commit def --reason work\"}}" > fixtures/pi-store/f4-early-b.jsonl
out=$(h find-tape --run-id "$F4EARLY") || fail "followup.4 earliest exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/pi-store/f4-early-b.jsonl" '.ok == true and .wal == $w' >/dev/null || fail "followup.4 earliest session wins: $out"

# workflow-birth: the claimed session's tape wins over an
# earlier own-edge tape from another session; stale and
# conductor tapes merely referencing the Run never win
out=$(h find-tape -h) || fail "find-tape -h workflow-birth exit"
echo "$out" | grep -q "workflow-birth" || fail "find-tape help workflow-birth: $out"
WBRUN="20260101T000000Z-handoff-pi-test-model-c6"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"$WBRUN\",\"harness\":\"pi\",\"quest\":\"toy\",\"node\":\"e1\",\"session_id\":\"S-wb-child\",\"ts\":\"2026-01-01T00:00:00Z\"}" > "$store/$WBRUN.jsonl"
printf '%s\n' '{"type":"session","version":3,"id":"S-wb-other","timestamp":"2026-01-01T00:01:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$WBRUN bp3 q toy u e1 handoff --commit abc --reason work\"}}" > fixtures/pi-store/wb-other.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-wb-child","timestamp":"2026-01-01T00:05:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"a2\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$WBRUN bp3 q toy u e1 handoff --commit def --reason work\"}}" > fixtures/pi-store/wb-child.jsonl
out=$(h find-tape --run-id "$WBRUN") || fail "workflow-birth find-tape exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/pi-store/wb-child.jsonl" '.ok == true and .wal == $w and .session_id == "S-wb-child"' >/dev/null || fail "workflow-birth claimed session wins: $out"

# the only own engine-fsm-edge tape started before the InitRecord
F4OLD="20260101T000000Z-handoff-pi-test-model-c5"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"$F4OLD\",\"harness\":\"pi\",\"quest\":\"toy\",\"node\":\"e1\",\"ts\":\"2026-01-01T00:00:00Z\"}" > "$store/$F4OLD.jsonl"
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-old-quote","timestamp":"2025-12-31T23:59:00Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"c1\",\"message\":{\"role\":\"user\",\"content\":\"brief: BP3_RUN_ID=$F4OLD bp3 q toy u e1 handoff --commit abc --reason work\"}}" > fixtures/pi-store/f4-old-quote.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-f4-old-resolve","timestamp":"2026-01-01T00:00:20Z","cwd":"/tmp"}' "{\"type\":\"message\",\"id\":\"v1\",\"message\":{\"role\":\"user\",\"content\":\"BP3_RUN_ID=$F4OLD bp3 harness find-tape --run-id $F4OLD\"}}" > fixtures/pi-store/f4-old-resolve.jsonl
if out=$(h find-tape --run-id "$F4OLD" 2>&1); then fail "followup.4 pre-init own-edge accepted"; fi
echo "$out" | jq -e '.error.code == "E_AMBIGUOUS"' >/dev/null || fail "followup.4 pre-init own-edge code: $out"
echo "$out" | grep -q "f4-old-quote" || fail "followup.4 pre-init names quoting tape: $out"

echo "harness/evidence: ok"
