#!/usr/bin/env bash
# Sandboxed runnable demo for quest 2026-11-26-warden-planned-gates.
# Uses a scratch mktemp directory and never mutates the real repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BP3_BIN="${BP3_BIN:-$REPO_ROOT/_build/default/src/quest/main.exe}"
if [ ! -x "$BP3_BIN" ]; then
  echo "error: build main.exe first (dune build src/quest/main.exe): $BP3_BIN" >&2
  exit 1
fi
bp3_demo() {
  (cd "$REPO" && BP3_ROOT="$REPO" "$BP3_BIN" "$@")
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
AGY="$TMP/agy"
mkdir -p "$REPO" "$AGY/conv-demo-1/.system_generated/logs"

git -C "$REPO" init -q -b master
git -C "$REPO" config user.email "demo@bp3.local"
git -C "$REPO" config user.name "bp3 demo"
cat > "$REPO/backpack.toml" <<'EOF'
version = 1
repo = "demo/repo"
[warden]
grade_wall_s = 300
EOF
mkdir -p "$REPO/plans"
cp "$REPO_ROOT/plans/default.yaml" "$REPO/plans/default.yaml"
git -C "$REPO" add backpack.toml plans/default.yaml
git -C "$REPO" commit -q -m "chore: init demo repo"

echo "=== 1. Proposed quest (QUEST.md only, before bp3 q c) ==="
mkdir -p "$REPO/docs/quests/proposedq"
printf '%s\n' '---' 'status: proposed' '---' '# proposedq' > "$REPO/docs/quests/proposedq/QUEST.md"
OUT_PROP="$(bp3_demo warden proposedq --no-sessions --format json)"
echo "$OUT_PROP"
echo "$OUT_PROP" | grep -q '"ok":true'
echo "$OUT_PROP" | grep -q '"total":0'

echo ""
echo "=== 2. Planned --kind human-gate node -> 0 human_steer + planned_gates[] ==="
bp3_demo q c demoq --type default >/dev/null
bp3_demo q demoq c node-av-gate --kind human-gate >/dev/null
BP3_DECIDER=human bp3_demo q demoq n node-av-gate e approve --reason "AV signed off" >/dev/null

OUT_GATE_JSON="$(bp3_demo warden demoq --no-sessions --format json)"
OUT_GATE_TBL="$(bp3_demo warden demoq --no-sessions --format table)"
echo "$OUT_GATE_JSON"
echo "$OUT_GATE_TBL"
echo "$OUT_GATE_JSON" | grep -q '"node":"node-av-gate"'
echo "$OUT_GATE_JSON" | grep -q '"reason":"AV signed off"'
echo "$OUT_GATE_JSON" | grep -q '"total":0'
echo "$OUT_GATE_TBL" | grep -q '(1 planned gate)'

echo ""
echo "=== 3. Unplanned e block on code node -> STILL Major human_steer ==="
bp3_demo q demoq c node-code-1 --kind code >/dev/null
bp3_demo q demoq n node-code-1 e block --reason "unexpected API 500 mid-build" >/dev/null

OUT_BLK_JSON="$(bp3_demo warden demoq --no-sessions --format json)"
OUT_BLK_TBL="$(bp3_demo warden demoq --no-sessions --format table)"
echo "$OUT_BLK_TBL"
echo "$OUT_BLK_JSON" | grep -q '"rule":"human_steer"'
echo "$OUT_BLK_JSON" | grep -q '"node":"node-code-1"'
echo "$OUT_BLK_JSON" | grep -q '"node":"node-av-gate"'

echo ""
echo "=== 4. Full-session human-log + query + standalone --session latest ==="
mkdir -p "$REPO/.git/bp3/quest-sessions"
cat > "$REPO/.git/bp3/quest-sessions/demoq.jsonl" <<'EOF'
{"sid":"conv-demo-1","harness":"agy","phase":"red-ink","ts":1795687200}
{"sid":"conv-demo-1","harness":"agy","phase":"induct","ts":1795687400}
EOF
cat > "$AGY/conv-demo-1/.system_generated/logs/transcript.jsonl" <<'EOF'
{"step_index":0,"type":"USER_INPUT","created_at":"2026-11-27T10:00:10Z","content":"let us red-ink demoq"}
{"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-11-27T10:00:20Z","content":"Drafting slice 1","tool_calls":[{"name":"ask_question","args":{"questions":"[{\"question\":\"Use human-gate instead of --planned?\"}]"}}]}
{"step_index":2,"type":"GENERIC","created_at":"2026-11-27T10:00:30Z","content":"Created At: 2026-11-27T10:00:20Z\nCompleted At: 2026-11-27T10:00:30Z\nA1: (Recommended) Yes, use --kind human-gate"}
{"step_index":3,"type":"USER_INPUT","created_at":"2026-11-27T10:04:00Z","content":"lgtm, induct demoq now"}
EOF

echo "--- bp3 warden human-log demoq --format table ---"
OUT_HL="$(bp3_demo warden human-log demoq --agy-dir "$AGY" --format table)"
echo "$OUT_HL"
echo "$OUT_HL" | grep -q 'red-ink'
echo "$OUT_HL" | grep -q 'ask_question'
echo "$OUT_HL" | grep -q 'induct'

echo "--- bp3 warden query latest --around 2 --window 1 --format table ---"
OUT_Q="$(bp3_demo warden query latest --around 2 --window 1 --agy-dir "$AGY" --format table)"
echo "$OUT_Q"
echo "$OUT_Q" | grep -q '#1'
echo "$OUT_Q" | grep -q '#2'
echo "$OUT_Q" | grep -q '#3'

echo "--- bp3 warden --session latest --format json ---"
OUT_SES="$(bp3_demo warden --session latest --agy-dir "$AGY" --format json)"
echo "$OUT_SES"
echo "$OUT_SES" | grep -q '"scope":"session"'
echo "$OUT_SES" | grep -q '"human_turns_count":3'
echo "$OUT_SES" | grep -q '"total":0'

echo ""
echo "=== 5. Refusal checks (E_USAGE exit 2) ==="
set +e
ERR1="$(bp3_demo warden query latest --agy-dir "$AGY" 2>&1)"
RC1=$?
ERR2="$(bp3_demo warden human-log demoq --session latest --agy-dir "$AGY" 2>&1)"
RC2=$?
set -e
echo "missing --around (exit $RC1): $ERR1"
echo "conflicting scope (exit $RC2): $ERR2"
[ "$RC1" -eq 2 ]
[ "$RC2" -eq 2 ]
echo "$ERR1" | grep -q '"code":"E_USAGE"'
echo "$ERR2" | grep -q '"code":"E_USAGE"'

echo ""
echo "DEMO PASS: all 5 scenarios verified in scratch sandbox."
