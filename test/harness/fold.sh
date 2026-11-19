#!/usr/bin/env bash
# harness piece 'fold': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"

# --- fake children: nodes in landed / blocked / todo states ---
q c done-q >/dev/null; q done-q c e1 >/dev/null
q c gate-q >/dev/null; q gate-q c e1 >/dev/null
q c toy >/dev/null; q toy c e1 >/dev/null
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
q done-q u e1 handoff --commit "$B" --reason work >/dev/null
q done-q u e1 grade --verdict ship --reason ok >/dev/null
q done-q u e1 verify --verdict pass --reason ok >/dev/null
q done-q u e1 land --reason "done" >/dev/null
q gate-q u e1 handoff --commit "$B" --reason work >/dev/null
q gate-q u e1 grade --verdict needs_fix --reason broken >/dev/null

# settled: all landed -> outcome settled, exit 0
out=$(h supervisor done-q --timeout-seconds 5) || fail "settled exit: $out"
echo "$out" | tail -1 | jq -e '.ok == true and .outcome == "settled" and .settled == true' >/dev/null || fail "settled verdict: $out"

# human gate: blocked node -> outcome human_gate, exit 4, inbox names it
set +e; out=$(h supervisor gate-q --timeout-seconds 5); rc=$?; set -e
[ "$rc" = 4 ] || fail "human_gate exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "human_gate" and .settled == false and (.inbox | length == 1) and .inbox[0].node == "e1"' >/dev/null || fail "human_gate verdict: $out"

# timeout: todo node never settles -> outcome timeout, exit 3
set +e; out=$(h s toy --timeout-seconds 1); rc=$?; set -e
[ "$rc" = 3 ] || fail "timeout exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "timeout" and .settled == false' >/dev/null || fail "timeout verdict: $out"
# stdout is pure NDJSON: every line parses, human prose stays off it
echo "$out" | while IFS= read -r line; do echo "$line" | jq -e . >/dev/null || fail "non-JSON stdout line: $line"; done

# --- lifecycle fold over derivation fixtures ---
store=".git/bp3/run-lifecycle-derivations"
mkdir -p "$store" fixtures
echo tape > fixtures/fresh.log
touch -t 202001010000 fixtures/stale.log
sleep 60 & LIVE=$!
printf '%s\n' '{"kind":"init_record","run_id":"R-init","harness":"muse-code","quest":"toy"}' > "$store/R-init.jsonl"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-active\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/fresh.log\"}" > "$store/R-active.jsonl"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-orphan\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/stale.log\"}" > "$store/R-orphan.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-fin","harness":"pi","quest":"toy"}' '{"kind":"observation","exit_observed":true,"tape_closed":true}' > "$store/R-fin.jsonl"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-settle-live\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/fresh.log\"}" '{"kind":"observation","settle_row":true,"tape_closed":false}' > "$store/R-settle-live.jsonl"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-blind\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/missing.log\"}" > "$store/R-blind.jsonl"
printf '%s\n' '{"kind":"init_record","run_id":"R-torn","harness":"pi","quest":"toy"}' '{"kind":"observation","tape_seen":tru' > "$store/R-torn.jsonl"

# engine contradicting an InitRecord is a usage error
if out=$(h supervisor toy --engine muse-code --timeout-seconds 1 2>&1); then fail "engine contradiction accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "contradiction code: $out"

set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
last=$(echo "$out" | tail -1)
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-init") | .lifecycle == "init")' >/dev/null || fail "init fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-active") | .lifecycle == "active")' >/dev/null || fail "active fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-orphan") | .lifecycle == "orphaned")' >/dev/null || fail "orphan fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-fin") | .lifecycle == "finished")' >/dev/null || fail "finished fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-settle-live") | .lifecycle == "active")' >/dev/null || fail "settle-live fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-blind") | .lifecycle == "active") and (.warnings | index("W_SUPERVISOR_BLIND") != null)' >/dev/null || fail "blind fold: $last"
echo "$last" | jq -e '(.runs[] | select(.run_id == "R-torn") | .lifecycle == "init")' >/dev/null || fail "torn fold: $last"
echo "$last" | jq -e '(.orphans | index("R-orphan") != null)' >/dev/null || fail "orphans named: $last"

# --- find-tape (mvp.2): InitRecord-first, reverse, entry ---
mkdir -p fixtures/pi-store fixtures/muse-store/S-muse
printf '%s\n' '{"type":"session","version":3,"id":"S-pi","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"e1","message":{"role":"user","content":"BP3_RUN_ID=R-pi-run work"}}' '{"type":"message","id":"e2","message":{"role":"assistant","content":"done"}}' '{"type":"message","id":"e3","message":{"role":"assistant","content":"bye"}}' > fixtures/pi-store/pi1.jsonl
printf '%s\n' '{"session_id":"S-muse","id":"m1","content":"BP3_RUN_ID=R-muse-run work"}' > fixtures/muse-store/S-muse/session.jsonl
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-find\",\"harness\":\"pi\",\"session_id\":\"S-pi\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/pi-store/pi1.jsonl\",\"quest\":\"toy\"}" > "$store/R-find.jsonl"
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-bad\",\"harness\":\"pi\",\"tape_path\":\"$work/repo/fixtures/pi-store/pi1.jsonl\",\"quest\":\"toy\"}" > "$store/R-bad.jsonl"
export BP3_PI_TAPE_DIR="$work/repo/fixtures/pi-store" BP3_MUSE_TAPE_DIR="$work/repo/fixtures/muse-store"

out=$(h find-tape -h) || fail "find-tape -h exit"
echo "$out" | grep -q "E_NOT_FOUND" || fail "find-tape help codes: $out"
out=$(h f -h) || fail "alias f -h exit"
echo "$out" | grep -q "find-tape" || fail "alias f help: $out"

out=$(h find-tape --run-id R-find) || fail "find-tape InitRecord hit exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/pi-store/pi1.jsonl" '.ok == true and .run_id == "R-find" and .harness == "pi" and .session_id == "S-pi" and .wal == $w' >/dev/null || fail "find-tape InitRecord hit: $out"
out=$(h find-tape --session-id S-pi) || fail "find-tape reverse exit: $out"
echo "$out" | jq -e '.run_id == "R-find" and .session_id == "S-pi"' >/dev/null || fail "find-tape reverse: $out"
out=$(h f --run-id R-find --session-id S-pi) || fail "find-tape both-agreeing exit: $out"
echo "$out" | jq -e '.run_id == "R-find"' >/dev/null || fail "find-tape both-agreeing: $out"
out=$(h find-tape --run-id R-pi-run) || fail "find-tape scan hit exit: $out"
echo "$out" | jq -e '.run_id == "R-pi-run" and .harness == "pi" and .session_id == "S-pi"' >/dev/null || fail "find-tape scan hit: $out"
out=$(h find-tape --session-id S-muse) || fail "find-tape muse reverse exit: $out"
echo "$out" | jq -e '.run_id == "R-muse-run" and .harness == "muse-code" and .session_id == "S-muse"' >/dev/null || fail "find-tape muse reverse: $out"

printf '%s\n' '{"type":"message","id":"mx","message":{"role":"user","content":"R-mention-only was discussed here"}}' > fixtures/pi-store/mention.jsonl
if out=$(h find-tape --run-id R-mention-only 2>&1); then fail "bare mention accepted as a binding"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "bare mention code: $out"
rm fixtures/pi-store/mention.jsonl
if out=$(h find-tape --run-id R-nope 2>&1); then fail "unknown run accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unknown run code: $out"
if out=$(h find-tape --run-id R-bad 2>&1); then fail "unreferenced InitRecord tape accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unreferenced tape code: $out"
if out=$(h find-tape 2>&1); then fail "neither identity accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "neither code: $out"
if out=$(h find-tape --run-id R-find --session-id S-other 2>&1); then fail "disagreeing identity accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "disagreeing code: $out"
if out=$(h find-tape --run-id R-find --run-id R-find 2>&1); then fail "duplicate flag accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "duplicate code: $out"
if out=$(h find-tape --run-id=R-find 2>&1); then fail "--flag=value accepted"; fi
if out=$(h find-tape --run-id R-find --before-entries 1 2>&1); then fail "widen without entry accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "widen-without-entry code: $out"
if out=$(h find-tape --run-id R-find --entry e2 --before-entries -1 2>&1); then fail "negative widen accepted"; fi

# two candidate files refuse and name both
cp fixtures/pi-store/pi1.jsonl fixtures/pi-store/pi2.jsonl
if out=$(h find-tape --run-id R-pi-run 2>&1); then fail "ambiguous run accepted"; fi
echo "$out" | jq -e '.error.code == "E_AMBIGUOUS"' >/dev/null || fail "ambiguous code: $out"
echo "$out" | grep -q "pi1.jsonl" || fail "ambiguous names first: $out"
echo "$out" | grep -q "pi2.jsonl" || fail "ambiguous names second: $out"
rm fixtures/pi-store/pi2.jsonl

# pointer resolution: one digest-verified entry, widened
out=$(h find-tape --run-id R-find --entry e2 --before-entries 1 --after-entries 1) || fail "entry exit: $out"
echo "$out" | jq -e '.entry.id == "e2" and (.entries | length == 3) and .entries[0].id == "e1" and .entries[2].id == "e3" and (.entry.digest | startswith("sha256:"))' >/dev/null || fail "entry window: $out"
want=$(sed -n '3p' fixtures/pi-store/pi1.jsonl | tr -d '\n' | shasum -a 256 | cut -d' ' -f1)
got=$(echo "$out" | jq -r '.entry.digest' | sed 's/^sha256://')
[ "$want" = "$got" ] || fail "entry digest: want $want got $got"
if out=$(h find-tape --run-id R-find --entry nope 2>&1); then fail "unknown entry accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unknown entry code: $out"

echo "harness/fold: ok"
