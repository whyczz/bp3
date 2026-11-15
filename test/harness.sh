#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/q-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q "$@"; }
h() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness "$@"; }
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
wt() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 worktree "$@"; }
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
[ "$(h desk derive demo exp-a R1 | normj)" = "$(wt derive demo exp-a R1 | normj)" ] || fail "derive parity"
[ "$(h desk list | normj)" = "$(wt list | normj)" ] || fail "empty list parity"
[ "$(h d list | normj)" = "$(h desk list | normj)" ] || fail "alias d list parity"
out=$(h desk prepare demo exp-a --run DA)
echo "$out" | jq -e '.ok == true and .run_id == "DA" and .path == ".bp3/worktrees/demo/exp-a/DA"' >/dev/null || fail "desk prepare: $out"
[ "$(h desk check --run DA | normj)" = "$(wt check --run DA | normj)" ] || fail "check parity"
[ "$(h desk list | normj)" = "$(wt list | normj)" ] || fail "list parity"
[ "$(h desk inspect .bp3/worktrees/demo/exp-a/DA | normj)" = "$(wt inspect .bp3/worktrees/demo/exp-a/DA | normj)" ] || fail "inspect parity"

# dirty refusal is the same verdict through both doors, record intact
echo stray >> .bp3/worktrees/demo/exp-a/DA/a.txt
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
out=$(h desk create .bp3/worktrees/demo/exp-a/DC --commit "$SHA")
echo "$out" | jq -e '.ok == true and .detached == true' >/dev/null || fail "desk create: $out"
out=$(h desk remove .bp3/worktrees/demo/exp-a/DC)
echo "$out" | jq -e '.ok == true and .removed == true' >/dev/null || fail "desk remove: $out"
h desk prepare demo exp-a --run DB >/dev/null
out=$(cd .bp3/worktrees/demo/exp-a/DB && BP3_Q_BIN="$work/repo/q-bin" "$work/repo/bin/bp3" harness desk exit)
echo "$out" | jq -e '.ok == true and .released == true and (.conductor_path | type == "string")' >/dev/null || fail "desk exit: $out"
out=$(h desk prepare --quest demoq)
echo "$out" | jq -e '.ok == true and .exp == "(quest)" and .path == ".bp3/worktrees/demoq"' >/dev/null || fail "desk quest prepare: $out"
out=$(h desk release --quest demoq)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "desk quest release: $out"

# creation refuses reserved door/verb slugs (E_USAGE), reads stay total
for bad in harness worktree desk supervisor watch c create list check; do
  if out=$(q c "$bad" 2>&1); then fail "quest create accepted reserved slug: $bad"; fi
  echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved quest code [$bad]: $out"
done
q c slug-q >/dev/null
for bad in harness desk find-tape release; do
  if out=$(q slug-q c "$bad" 2>&1); then fail "exp create accepted reserved slug: $bad"; fi
  echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved exp code [$bad]: $out"
done
if out=$(h desk prepare --quest watch 2>&1); then fail "desk prepare accepted reserved quest slug"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved desk-prepare code: $out"
out=$(q slug-q c fine-exp)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "ordinary exp create after refusals: $out"

# --- init-check: blind probe warns, never blocks ---
mkdir -p "$work/nohome"
out=$(HOME="$work/nohome" BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 harness init-check) || fail "init-check blind exit"
echo "$out" | jq -e '.ok == true and (.checks | length == 2) and (.warnings | index("W_SUPERVISOR_BLIND") != null)' >/dev/null || fail "init-check blind: $out"
out=$(h init-check --engine muse-code) || fail "init-check one engine exit"
echo "$out" | jq -e '.ok == true and (.checks | length == 1) and .checks[0].harness == "muse-code"' >/dev/null || fail "init-check engine: $out"

# --- fake children: exps in landed / blocked / todo states ---
q c done-q >/dev/null; q done-q c e1 >/dev/null
q c gate-q >/dev/null; q gate-q c e1 >/dev/null
q c toy >/dev/null; q toy c e1 >/dev/null
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
q done-q u e1 submit --commit "$B" --reason work >/dev/null
q done-q u e1 review --verdict ship --reason ok >/dev/null
q done-q u e1 check --verdict pass --reason ok >/dev/null
q done-q u e1 land --reason "done" >/dev/null
q gate-q u e1 submit --commit "$B" --reason work >/dev/null
q gate-q u e1 review --verdict needs_fix --reason broken >/dev/null

# settled: all landed -> outcome settled, exit 0
out=$(h supervisor done-q --timeout-seconds 5) || fail "settled exit: $out"
echo "$out" | tail -1 | jq -e '.ok == true and .outcome == "settled" and .settled == true' >/dev/null || fail "settled verdict: $out"

# human gate: blocked exp -> outcome human_gate, exit 4, inbox names it
set +e; out=$(h supervisor gate-q --timeout-seconds 5); rc=$?; set -e
[ "$rc" = 4 ] || fail "human_gate exit class: $rc ($out)"
echo "$out" | tail -1 | jq -e '.outcome == "human_gate" and .settled == false and (.inbox | length == 1) and .inbox[0].exp == "e1"' >/dev/null || fail "human_gate verdict: $out"

# timeout: todo exp never settles -> outcome timeout, exit 3
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
printf '%s\n' "{\"sessions\":{\"S-leg\":{\"quest\":\"toy\",\"exp\":\"e1\",\"run_id\":\"L-leg\",\"settled\":true,\"last_seen_epoch\":$now_s},\"S-dup\":{\"quest\":\"toy\",\"exp\":\"e1\",\"run_id\":\"R-active\",\"settled\":true,\"last_seen_epoch\":$now_s}}}" > "$reg"
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

# --- record-init (mvp.8): the launcher writes the InitRecord ---
out=$(h record-init -h) || fail "record-init -h exit"
echo "$out" | grep -q "record-init" || fail "record-init help: $out"
echo "$out" | grep -q "E_EXISTS" || fail "record-init help codes: $out"
out=$(h r -h) || fail "alias r -h exit"
echo "$out" | grep -q "record-init" || fail "alias r help: $out"
out=$(h -h) || fail "harness -h mvp.8 exit"
echo "$out" | grep -q "record-init" || fail "harness help lists record-init: $out"
if out=$(h record-init --harness muse-code 2>&1); then fail "record-init without run-id accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "record-init no-run code: $out"
if out=$(h record-init --run-id R-x 2>&1); then fail "record-init without harness accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "record-init no-harness code: $out"
if out=$(h record-init --run-id R-x --harness bogus 2>&1); then fail "record-init bogus harness accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "record-init bogus code: $out"
if out=$(h record-init --run-id "a/b" --harness pi 2>&1); then fail "record-init slash run-id accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "record-init slash code: $out"
if out=$(h record-init --run-id R-x --harness pi --pid 0 2>&1); then fail "record-init zero pid accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "record-init pid code: $out"
if out=$(h record-init --run-id R-x --run-id R-x --harness pi 2>&1); then fail "record-init duplicate accepted"; fi
if out=$(h record-init --run-id=R-x --harness pi 2>&1); then fail "record-init --flag=value accepted"; fi

# born lookup-able: the record lands before any tape entry exists
out=$(h record-init --run-id R-born --harness muse-code --quest toy --exp e1 --session-id S-born --model test-model) || fail "record-init born exit: $out"
echo "$out" | jq -e '.ok == true and .run_id == "R-born" and .harness == "muse-code" and .session_id == "S-born"' >/dev/null || fail "record-init born verdict: $out"
head -1 "$store/R-born.jsonl" | jq -e '.kind == "init_record" and .run_id == "R-born" and .harness == "muse-code" and (.ts | type == "string")' >/dev/null || fail "born init row: $(head -1 "$store/R-born.jsonl")"
mkdir -p fixtures/muse-store/S-born
printf '%s\n' '{"session_id":"S-born","id":"b1","content":"BP3_RUN_ID=R-born work"}' > fixtures/muse-store/S-born/session.jsonl
[ ! fixtures/muse-store/S-born/session.jsonl -ot "$store/R-born.jsonl" ] || fail "tape predates its InitRecord"
out=$(h find-tape --run-id R-born) || fail "find-tape born exit: $out"
echo "$out" | jq -e --arg w "$work/repo/fixtures/muse-store/S-born/session.jsonl" '.ok == true and .run_id == "R-born" and .harness == "muse-code" and .session_id == "S-born" and .wal == $w' >/dev/null || fail "find-tape born: $out"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e '(.runs[] | select(.run_id == "R-born"))' >/dev/null || fail "born run invisible to supervisor: $out"

# create-only: a second write for the same run-id is refused, file intact
born_hash=$(shasum -a 256 "$store/R-born.jsonl" | cut -d' ' -f1)
if out=$(h record-init --run-id R-born --harness muse-code 2>&1); then fail "second InitRecord accepted"; fi
echo "$out" | jq -e '.error.code == "E_EXISTS"' >/dev/null || fail "second InitRecord code: $out"
[ "$(shasum -a 256 "$store/R-born.jsonl" | cut -d' ' -f1)" = "$born_hash" ] || fail "refused rewrite touched the InitRecord"

# killed mid-spawn: record first, dead pid, stale tape -> orphaned, never invisible
printf '%s\n' '{"type":"message","id":"k9","message":{"role":"user","content":"BP3_RUN_ID=R-killed work"}}' > fixtures/killed.log
touch -t 202001010000 fixtures/killed.log
out=$(h r --run-id R-killed --harness muse-code --quest toy --exp e1 --pid 999999 --tape-path "$work/repo/fixtures/killed.log") || fail "record-init killed exit: $out"
set +e; out=$(h supervisor toy --timeout-seconds 1); set -e
echo "$out" | tail -1 | jq -e '(.runs[] | select(.run_id == "R-killed") | .lifecycle == "orphaned")' >/dev/null || fail "killed run not orphaned: $out"

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
