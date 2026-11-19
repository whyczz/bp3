#!/usr/bin/env bash
# harness piece 'race': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"
fixture_quests
fixture_runs

# --- derivation concurrency (followup.1): parallel writers, one log ---
sleep 60 & RACE_LIVE=$!
printf '%s\n' '{"type":"message","id":"r1","message":{"role":"user","content":"race work"}}' > fixtures/race.log
printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-race\",\"harness\":\"pi\",\"pid\":$RACE_LIVE,\"tape_path\":\"$work/repo/fixtures/race.log\",\"quest\":\"toy\"}" > "$store/R-race.jsonl"
# two supervisors fold the same Run at once, repeatedly: rows
# interleave whole (single write, O_APPEND) or not at all
race_round=0
while [ $race_round -lt 3 ]; do
  race_round=$((race_round + 1))
  h supervisor toy --timeout-seconds 2 >/dev/null 2>&1 & RACE_A=$!
  h supervisor toy --timeout-seconds 2 >/dev/null 2>&1 & RACE_B=$!
  # name the pids: a bare wait also waits out RACE_LIVE (60s)
  wait "$RACE_A" "$RACE_B" 2>/dev/null || true
done
while IFS= read -r line; do echo "$line" | jq -e . >/dev/null || fail "followup.1 torn row in R-race: $line"; done < "$store/R-race.jsonl"
jq -e '.run_id == "R-race"' "$store/R-race.json" >/dev/null || fail "followup.1 cache torn after race"
# torn tail: an unterminated fragment appended mid-race is
# ignored by the fold and reported, never folded as fact
printf '%s' '{"kind":"observation","tape_seen":tru' >> "$store/R-race.jsonl"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e '.warnings | index("W_TORN_TAIL") != null' >/dev/null || fail "followup.1 torn tail not reported: $out"
echo "$out" | tail -1 | jq -e '(.runs[] | select(.run_id == "R-race") | .lifecycle == "active")' >/dev/null || fail "followup.1 torn tail changed the fold: $out"
kill $RACE_LIVE 2>/dev/null || true
wait "$RACE_LIVE" 2>/dev/null || true

echo "harness/race: ok"
