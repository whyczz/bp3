#!/usr/bin/env bash
# harness piece 'backtest': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"

# --- backtest (backtest.1): replay folds facts, findings never gate ---
out=$(h backtest -h) || fail "backtest -h exit"
echo "$out" | grep -q "backtest" || fail "backtest help: $out"
out=$(h b -h) || fail "alias b -h exit"
echo "$out" | grep -q "backtest" || fail "alias b help: $out"
mkdir -p fixtures/bt
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' 'BP3_RUN_ID=R-bt-1 bp3 q toy u e1 handoff --commit 0123456789abcdef0123456789abcdef01234567' '{"payload_type":"session.end","payload":{}}' > fixtures/bt/good.jsonl
printf '%s\n' '{"payload_type":"command.invoked","payload":{"kind":"command_invoked"}}' 'BP3_RUN_ID=R-bt-2 error E_BINDING_REFUSED' > fixtures/bt/refused.jsonl
printf '%s' '{"payload_type":"session.end","payl' > fixtures/bt/torn.jsonl
printf '%s\n' 'hello foreign tape' > fixtures/bt/foreign.jsonl
out=$(h backtest --corpus fixtures/bt) || fail "backtest exit: $out"
echo "$out" | jq -e '.ok == true and .tapes_replayed == 4 and .identifiable == 2' >/dev/null || fail "backtest counts: $out"
echo "$out" | jq -e '(.traces[] | select(.run_ids[0] == "R-bt-1") | .has_handoff == true and .finish_evidence == true)' >/dev/null || fail "backtest good trace: $out"
echo "$out" | jq -e '(.traces[] | select(.run_ids[0] == "R-bt-1") | .commits == ["0123456789abcdef0123456789abcdef01234567"])' >/dev/null || fail "backtest commits extraction: $out"
echo "$out" | jq -e '(.traces[] | select(.run_ids[0] == "R-bt-2") | .commits == [])' >/dev/null || fail "backtest refused commits empty: $out"
echo "$out" | jq -e '(.findings[] | select(.run_id == "R-bt-2"))' >/dev/null || fail "backtest refusal finding: $out"
echo "$out" | jq -e '(.findings[] | select(.evidence | test("torn")))' >/dev/null || fail "backtest torn finding: $out"
echo "$out" | jq -e '(.findings[] | select(.evidence | test("foreign")))' >/dev/null || fail "backtest foreign finding: $out"
if out=$(h backtest --corpus no-such-dir 2>&1); then fail "backtest missing corpus accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "backtest missing code: $out"
if out=$(h backtest --bogus 1 2>&1); then fail "backtest unknown flag accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "backtest usage code: $out"
if out=$(h backtest stray 2>&1); then fail "backtest stray accepted"; fi

# --- backtest pi (backtest.2): pi fold, usage sums, deterministic replay ---
mkdir -p fixtures/bt-pi
printf '%s\n' '{"type":"session","version":3,"id":"S-bt-pi-1","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"e1","message":{"role":"user","content":"BP3_RUN_ID=R-bt-pi-1 work"}}' '{"type":"message","id":"e2","message":{"role":"assistant","content":"done","usage":{"input":100,"output":10,"totalTokens":110},"stopReason":"stop"}}' > fixtures/bt-pi/good.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-bt-pi-2","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"e1","message":{"role":"user","content":"BP3_RUN_ID=R-bt-pi-2 work"}}' '{"type":"message","id":"e2","message":{"role":"assistant","content":"error E_BINDING_REFUSED"}}' > fixtures/bt-pi/refused.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-bt-pi-3","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' > fixtures/bt-pi/header.jsonl
printf '%s' '{"type":"session","id":"S-bt-pi-4","times' > fixtures/bt-pi/torn.jsonl
printf '%s\n' 'hello foreign tape' > fixtures/bt-pi/foreign.jsonl
printf '%s\n' '{"type":"session","version":3,"id":"S-bt-pi-5","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"session_closed","id":"c1"}' > fixtures/bt-pi/closed.jsonl
out=$(h backtest --engine pi --corpus fixtures/bt-pi) || fail "backtest pi exit: $out"
echo "$out" | jq -e '.ok == true and .engine == "pi" and .tapes_replayed == 6 and .identifiable == 4' >/dev/null || fail "backtest pi counts: $out"
echo "$out" | jq -e '(.traces[] | select(.session_id == "S-bt-pi-1") | .finish_evidence == true and .usage_input == 100 and .usage_output == 10 and .usage_total == 110)' >/dev/null || fail "backtest pi good trace: $out"
echo "$out" | jq -e '(.traces[] | select(.session_id == "S-bt-pi-5") | .finish_evidence == true)' >/dev/null || fail "backtest pi closed trace: $out"
echo "$out" | jq -e '(.findings[] | select(.evidence | test("E_BINDING_REFUSED")) | .fix_target == "dispatcher")' >/dev/null || fail "backtest pi refusal finding: $out"
echo "$out" | jq -e '(.findings[] | select(.evidence | test("header-only")))' >/dev/null || fail "backtest pi header finding: $out"
echo "$out" | jq -e '(.findings[] | select(.evidence | test("torn")))' >/dev/null || fail "backtest pi torn finding: $out"
echo "$out" | jq -e '(.findings[] | select(.evidence | test("foreign")))' >/dev/null || fail "backtest pi foreign finding: $out"
out2=$(h backtest --engine pi --corpus fixtures/bt-pi) || fail "backtest pi rerun exit: $out2"
[ "$out" = "$out2" ] || fail "backtest pi replay not deterministic"
if out=$(h backtest --engine bogus 2>&1); then fail "backtest bad engine accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "backtest bad engine code: $out"

# --- naming gate: retired spellings stay out of the new code ---
retired="Spawn""Record|spawn""ed|run""ning"
if grep -E "$retired" "$root/src/quest/harness.ml" >/dev/null; then fail "retired lifecycle spelling in harness.ml"; fi
if grep -q "bp3-run-registry" "$root/src/quest/harness.ml"; then fail "mvp.5 retired registry spelling in harness.ml"; fi
if grep -q "bp3-run-events" "$root/src/quest/harness.ml"; then fail "mvp.5 retired events spelling in harness.ml"; fi
if grep -q "legacy_views" "$root/src/quest/harness.ml"; then fail "mvp.5 legacy import still in harness.ml"; fi
grep -q "init_record" "$root/src/quest/harness.ml" || fail "init_record missing"
for w in '"init"' '"active"' '"finished"' '"orphaned"'; do
  grep -q "$w" "$root/src/quest/harness.ml" || fail "lifecycle word missing: $w"
done

echo "harness/backtest: ok"
