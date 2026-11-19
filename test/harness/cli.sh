#!/usr/bin/env bash
# harness piece 'cli': sections moved verbatim from test/harness.sh
# (test-pyramid tier.1). Shared setup lives in lib.sh.
# shellcheck source=test/harness/lib.sh
. "$(dirname "$0")/lib.sh"

# --- help: every harness verb documented, exit 0, no state read ---
out=$(h -h) || fail "harness -h exit"
echo "$out" | grep -q "supervisor" || fail "harness help lists supervisor: $out"
echo "$out" | grep -q "init-check" || fail "harness help lists init-check: $out"
out=$(h supervisor -h) || fail "supervisor -h exit"
echo "$out" | grep -q "settled=0" || fail "supervisor help exit classes: $out"
echo "$out" | grep -q "watchdog_killed=1" || fail "supervisor help watchdog class: $out"
echo "$out" | grep -q "timeout=3" || fail "supervisor help timeout class: $out"
echo "$out" | grep -q "human_gate=4" || fail "supervisor help gate class: $out"
out=$(h s -h) || fail "alias s -h exit"
echo "$out" | grep -q "supervisor" || fail "alias s help: $out"
out=$(h i -h) || fail "alias i -h exit"
echo "$out" | grep -q "init-check" || fail "alias i help: $out"
out=$(h watch -h) || fail "watch -h exit"
echo "$out" | grep -q "watchdog_killed" || fail "watch help outcomes: $out"
echo "$out" | grep -q "W_SUPERVISOR_BLIND" || fail "watch help blindness: $out"
out=$(h w -h) || fail "alias w -h exit"
echo "$out" | grep -q "watch" || fail "alias w help: $out"

# --- usage: strict argv, bare positive durations, exit 2 ---
if out=$(h supervisor 2>&1); then fail "supervisor without quest accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "no-quest code: $out"
if out=$(h supervisor toy --timeout-seconds 0 2>&1); then fail "zero timeout accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "zero timeout code: $out"
if out=$(h supervisor toy --timeout-seconds -5 2>&1); then fail "negative timeout accepted"; fi
if out=$(h supervisor toy --timeout-seconds 30m 2>&1); then fail "suffixed timeout accepted"; fi
if out=$(h supervisor toy --timeout-seconds=30 2>&1); then fail "--flag=value accepted"; fi
if out=$(h supervisor toy --engine bogus 2>&1); then fail "bogus engine accepted"; fi
if out=$(h supervisor toy --bogus 1 2>&1); then fail "unknown flag accepted"; fi
if out=$(h bogus 2>&1); then fail "unknown harness verb accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "unknown verb code: $out"
if out=$(h supervisor no-such-quest --timeout-seconds 1 2>&1); then fail "missing quest accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "missing quest code: $out"

# --- desk (mvp.6): harness desk door, worktree door is its alias ---
wt() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 worktree "$@"; }
normj() { jq -Sc 'walk(if type == "object" then del(.created_ts, .stale_s) else . end)'; }
out=$(h desk -h) || fail "desk -h exit"
for v in derive create inspect remove prepare check exit release list; do
  echo "$out" | grep -q "$v" || fail "desk help lists $v: $out"
done
out=$(h d -h) || fail "alias d -h exit"
echo "$out" | grep -q "harness desk" || fail "alias d help: $out"
if out=$(h desk 2>&1); then fail "desk without a verb accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "desk no-verb code: $out"

# golden parity: read verbs answer identically through both doors
[ "$(h desk derive demo node-a R1 | normj)" = "$(wt derive demo node-a R1 | normj)" ] || fail "derive parity"
[ "$(h desk list | normj)" = "$(wt list | normj)" ] || fail "empty list parity"
[ "$(h d list | normj)" = "$(h desk list | normj)" ] || fail "alias d list parity"
out=$(h desk prepare demo node-a --run DA)
echo "$out" | jq -e '.ok == true and .run_id == "DA" and .path == ".bp3/worktrees/demo/node-a/DA"' >/dev/null || fail "desk prepare: $out"
[ "$(h desk check --run DA | normj)" = "$(wt check --run DA | normj)" ] || fail "check parity"
[ "$(h desk list | normj)" = "$(wt list | normj)" ] || fail "list parity"
[ "$(h desk inspect .bp3/worktrees/demo/node-a/DA | normj)" = "$(wt inspect .bp3/worktrees/demo/node-a/DA | normj)" ] || fail "inspect parity"

# dirty refusal is the same verdict through both doors, record intact
echo stray >> .bp3/worktrees/demo/node-a/DA/a.txt
d1=$(h desk release --run DA 2>&1 | normj) || true
d2=$(wt release --run DA 2>&1 | normj) || true
[ "$d1" = "$d2" ] || fail "dirty release parity: $d1 vs $d2"
echo "$d1" | jq -e '.ok == false and .error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty release code: $d1"
out=$(h desk check --run DA)
echo "$out" | jq -e '.ok == true and .dirty == true' >/dev/null || fail "record lost after dirty release: $out"
out=$(h desk release --run DA --force)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "desk force release: $out"

# create/remove and exit through the desk door
SHA=$(git rev-parse HEAD)
out=$(h desk create .bp3/worktrees/demo/node-a/DC --commit "$SHA")
echo "$out" | jq -e '.ok == true and .detached == true' >/dev/null || fail "desk create: $out"
out=$(h desk remove .bp3/worktrees/demo/node-a/DC)
echo "$out" | jq -e '.ok == true and .removed == true' >/dev/null || fail "desk remove: $out"
h desk prepare demo node-a --run DB >/dev/null
out=$(cd .bp3/worktrees/demo/node-a/DB && BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" harness desk exit)
echo "$out" | jq -e '.ok == true and .released == true and (.conductor_path | type == "string")' >/dev/null || fail "desk exit: $out"
out=$(h desk prepare --quest demoq)
echo "$out" | jq -e '.ok == true and .node == "(quest)" and .path == ".bp3/worktrees/demoq"' >/dev/null || fail "desk quest prepare: $out"
out=$(h desk release --quest demoq)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "desk quest release: $out"

# creation refuses reserved door/verb slugs (E_USAGE), reads stay total
for bad in harness worktree desk supervisor watch c create list check; do
  if out=$(q c "$bad" 2>&1); then fail "quest create accepted reserved slug: $bad"; fi
  echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved quest code [$bad]: $out"
done
q c slug-q >/dev/null
for bad in harness desk find-tape release; do
  if out=$(q slug-q c "$bad" 2>&1); then fail "node create accepted reserved slug: $bad"; fi
  echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved node code [$bad]: $out"
done
if out=$(h desk prepare --quest watch 2>&1); then fail "desk prepare accepted reserved quest slug"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved desk-prepare code: $out"
out=$(q slug-q c fine-node)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "ordinary node create after refusals: $out"

# --- init-check: blind probe warns, never blocks ---
mkdir -p "$work/nohome"
out=$(HOME="$work/nohome" BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness init-check) || fail "init-check blind exit"
echo "$out" | jq -e '.ok == true and (.checks | length == 2) and (.warnings | index("W_SUPERVISOR_BLIND") != null)' >/dev/null || fail "init-check blind: $out"
out=$(h init-check --engine muse-code) || fail "init-check one engine exit"
echo "$out" | jq -e '.ok == true and (.checks | length == 1) and .checks[0].harness == "muse-code"' >/dev/null || fail "init-check engine: $out"

echo "harness/cli: ok"
