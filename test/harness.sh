#!/usr/bin/env bash
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
h() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

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

echo "harness.sh: all checks passed"
