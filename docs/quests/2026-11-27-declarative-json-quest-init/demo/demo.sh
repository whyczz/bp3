#!/usr/bin/env bash
# Sandboxed runnable demo for quest 2026-11-27-declarative-json-quest-init.
# Uses a scratch mktemp directory and never mutates the real repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BP3_BIN="${BP3_BIN:-$REPO_ROOT/_build/default/src/quest/main.exe}"
if [ ! -x "$BP3_BIN" ]; then
  echo "error: build main.exe first (dune build src/quest/main.exe): $BP3_BIN" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/plans" "$REPO/docs/quests/json-demo"
cp "$REPO_ROOT/plans/default.yaml" "$REPO/plans/default.yaml"

git -C "$REPO" init -q -b master
git -C "$REPO" config user.email "demo@bp3.local"
git -C "$REPO" config user.name "bp3 demo"
cat > "$REPO/backpack.toml" <<'EOF'
version = 1
repo = "demo/repo"
EOF
git -C "$REPO" add backpack.toml plans/default.yaml
git -C "$REPO" commit -q -m "chore: init demo repo"

bp3_demo() {
  (cd "$REPO" && BP3_ROOT="$REPO" BP3_HARNESS=agy BP3_MODEL=demo "$BP3_BIN" "$@")
}

echo "=== 1. Refusal: cyclic quest.json fails E_INVALID_SPEC with ZERO refs created ==="
cat > "$TMP/bad-cycle.json" <<'JSON'
{
  "version": 1,
  "quest": "bad-cycle",
  "title": "Cyclic Spec",
  "tldr": "Must fail pre-write validation",
  "bump": "patch",
  "nodes": [
    {
      "id": "exp-a-1", "node": "a.1", "title": "A", "kind": "code",
      "depends_on": ["exp-b-1"], "intent": "A", "output": "a.txt",
      "acceptance": {"objective": "A", "prove_by": ["make check"], "done_when": "green"}
    },
    {
      "id": "exp-b-1", "node": "b.1", "title": "B", "kind": "code",
      "depends_on": ["exp-a-1"], "intent": "B", "output": "b.txt",
      "acceptance": {"objective": "B", "prove_by": ["make check"], "done_when": "green"}
    }
  ]
}
JSON
set +e
ERR_CYC="$(bp3_demo q c bad-cycle --file "$TMP/bad-cycle.json" 2>&1)"
RC_CYC=$?
ERR_READ="$(bp3_demo q r bad-cycle 2>&1)"
RC_READ=$?
set -e
echo "create cyclic (exit $RC_CYC): $ERR_CYC"
echo "read bad-cycle (exit $RC_READ): $ERR_READ"
[ "$RC_CYC" -eq 1 ]
[ "$RC_READ" -eq 2 ]
echo "$ERR_CYC" | jq -e '.error.code == "E_INVALID_SPEC"' >/dev/null
echo "$ERR_READ" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null

echo ""
echo "=== 2. Happy path: atomic bp3 q c --file across kinds in topological order ==="
cat > "$REPO/docs/quests/json-demo/quest.json" <<'JSON'
{
  "version": 1,
  "quest": "json-demo",
  "title": "Declarative JSON Quest Demo",
  "tldr": "Initialize research, explore, code, and human-gate nodes atomically",
  "bump": "minor",
  "nodes": [
    {
      "id": "node-gate-1", "node": "gate.1", "title": "Owner sign-off", "kind": "human-gate",
      "depends_on": ["node-code-1"], "intent": "Confirm rollout", "output": "approval",
      "acceptance": {"objective": "Owner approves", "prove_by": ["e approve"], "done_when": "approved"}
    },
    {
      "id": "node-code-1", "node": "code.1", "title": "Implement feature", "kind": "code",
      "depends_on": ["node-res-1", "node-exp-1"], "intent": "Build feature", "output": "feat.txt",
      "acceptance": {"objective": "Ship JSON-gated feature", "prove_by": ["make check-full"], "done_when": "all tests green"}
    },
    {
      "id": "node-exp-1", "node": "exp.1", "title": "Latency spike", "kind": "explore",
      "depends_on": [], "target": "p99 < 10ms", "max_iterations": 2,
      "intent": "Measure parser latency", "output": "bench.md",
      "acceptance": {"objective": "Find fast path", "prove_by": ["bench"], "done_when": "hit or bounded"}
    },
    {
      "id": "node-res-1", "node": "res.1", "title": "Inspect schema", "kind": "research",
      "depends_on": [], "intent": "Confirm spec bounds", "output": "notes.md",
      "acceptance": {"objective": "Lock down edge cases", "prove_by": ["notes"], "done_when": "complete"}
    }
  ]
}
JSON
git -C "$REPO" add docs/quests/json-demo/quest.json
git -C "$REPO" commit -q -m "docs(quest): add json-demo quest.json"

OUT_INIT="$(bp3_demo q c --file docs/quests/json-demo/quest.json)"
echo "$OUT_INIT" | jq '{ok, quest, state, nodes: [.nodes[] | {node, kind, deps}]}'
echo "$OUT_INIT" | jq -e '.ok == true and .quest == "json-demo" and (.nodes | length) == 4' >/dev/null
echo "$OUT_INIT" | jq -e '.nodes[3].node == "node-gate-1" and .nodes[2].node == "node-code-1"' >/dev/null

echo ""
echo "=== 3. Research JSON diff guard (refuses own entry, allows downstream todo) + JSON brief ==="
jq '.nodes[3].intent = "Weakened own intent"' "$REPO/docs/quests/json-demo/quest.json" > "$TMP/q.tmp"
mv "$TMP/q.tmp" "$REPO/docs/quests/json-demo/quest.json"
git -C "$REPO" add docs/quests/json-demo/quest.json
git -C "$REPO" commit -q -m "research tries to edit own entry"
SHA_BAD="$(git -C "$REPO" rev-parse HEAD)"
set +e
ERR_PROT="$(bp3_demo q json-demo n node-res-1 e handoff --commit "$SHA_BAD" --reason "edit own entry" 2>&1)"
RC_PROT=$?
set -e
echo "research editing own quest.json entry (exit $RC_PROT): $ERR_PROT"
[ "$RC_PROT" -eq 1 ]
echo "$ERR_PROT" | jq -e '.error.code == "E_PROTECTED_FILE"' >/dev/null

git -C "$REPO" reset -q --hard HEAD~1
jq '.nodes[1].intent = "Sharpened downstream code intent"' "$REPO/docs/quests/json-demo/quest.json" > "$TMP/q.tmp"
mv "$TMP/q.tmp" "$REPO/docs/quests/json-demo/quest.json"
git -C "$REPO" add docs/quests/json-demo/quest.json
git -C "$REPO" commit -q -m "research sharpens downstream todo node-code-1"
SHA_OK="$(git -C "$REPO" rev-parse HEAD)"
OUT_RES="$(bp3_demo q json-demo n node-res-1 e handoff --commit "$SHA_OK" --reason "refined todo node-code-1")"
echo "research editing downstream todo entry: $(echo "$OUT_RES" | jq -c '{ok, node, state}')"
echo "$OUT_RES" | jq -e '.ok == true and .state == "landed"' >/dev/null

bp3_demo q json-demo n node-exp-1 e iterate --note "baseline p99 12ms -> optimized 4ms" >/dev/null
mkdir -p "$REPO/docs/quests/json-demo/explores/node-exp-1"
echo "bench result: p99 4ms" > "$REPO/docs/quests/json-demo/explores/node-exp-1/REPORT.md"
git -C "$REPO" add docs/quests/json-demo/explores/node-exp-1/REPORT.md
git -C "$REPO" commit -q -m "explore: bench hit"
OUT_EXP="$(bp3_demo q json-demo n node-exp-1 e handoff --commit "$(git -C "$REPO" rev-parse HEAD)" --outcome hit --reason "p99 4ms")"
echo "$OUT_EXP" | jq -e '.ok == true and .state == "landed"' >/dev/null

echo "feature impl" > "$REPO/feat.txt"
git -C "$REPO" add feat.txt && git -C "$REPO" commit -q -m "feat: implement json-gated feature"
bp3_demo q json-demo n node-code-1 e handoff --commit "$(git -C "$REPO" rev-parse HEAD)" --reason "ready for cold brief" >/dev/null
BRIEF="$(bp3_demo q json-demo n node-code-1 brief | jq -r '.brief')"
echo "$BRIEF" | grep -A 5 "Acceptance gates (quest.json at"
echo "$BRIEF" | grep -qF "Ship JSON-gated feature"
[ ! -e "$REPO/docs/quests/json-demo/nodes/node-code-1/NODE.md" ]

echo ""
echo "=== 4. Optional --scaffold + scripts/check-bump ==="
cat > "$TMP/scaf.json" <<'JSON'
{
  "version": 1,
  "quest": "scaf-demo",
  "title": "Scaffolded Quest",
  "tldr": "Render readable QUEST.md and NODE.md views from quest.json",
  "bump": "patch",
  "nodes": [
    {
      "id": "node-s-1", "node": "s.1", "title": "First step",
      "intent": "Verify scaffold", "output": "s.txt",
      "acceptance": {"objective": "Scaffold works", "prove_by": ["make check"], "done_when": "green"}
    }
  ]
}
JSON
OUT_SCAF="$(bp3_demo q c --file "$TMP/scaf.json" --scaffold)"
echo "$OUT_SCAF" | jq '{ok, quest, scaffolded}'
echo "$OUT_SCAF" | jq -e '.ok == true and (.scaffolded | length) == 2' >/dev/null
grep -qF "## Acceptance gates" "$REPO/docs/quests/scaf-demo/nodes/node-s-1/NODE.md"
"$REPO_ROOT/scripts/check-bump" --root "$REPO"

echo ""
echo "DEMO PASS: all 4 scenarios verified in scratch sandbox."
