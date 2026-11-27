#!/usr/bin/env bash
# Runnable demo for 2026-11-23-dag-contracts (scratch sandbox, never touches repo state).
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../../.." && pwd)
bin="$repo/_build/default/src/quest/main.exe"
[ -x "$bin" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-demo-dag-contracts.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

cd "$work"
git init -q -b master
git config user.email demo@bp3.local
git config user.name "bp3 demo"
mkdir -p plans src/quest docs/quests/demo/nodes/d1 docs/quests/demo/nodes/c2 docs/quests/demo/research/r1 docs/quests/demo/explores/ex1
cp "$repo/plans/default.yaml" "$repo/plans/direct.yaml" plans/
printf 'rules v1\n' > GRADING.md
printf '# d1\n' > docs/quests/demo/nodes/d1/NODE.md
printf '# c2\n' > docs/quests/demo/nodes/c2/NODE.md
git add -A && git commit -qm "base"

export BP3_HARNESS=agy BP3_MODEL=demo
q() { "$bin" q "$@"; }

q c demo --type default | jq -c '{ok, quest}'

echo "== 1. Code node + E_PROTECTED_FILE refusal & --allow-protected recovery =="
q demo c c1 | jq -c '{ok, node, kind, legal_edges}'
printf 'rules v2\n' > GRADING.md && git add GRADING.md && git commit -qm "edit grading"
C_PROT=$(git rev-parse HEAD)
out=$(q demo n c1 e handoff --commit "$C_PROT" --reason "sneaky" || true)
echo "$out" | jq -c '{ok, code: .error.code, paths: .error.facts.paths}'
echo "$out" | jq -e '.error.code == "E_PROTECTED_FILE"' >/dev/null
q demo n c1 e handoff --commit "$C_PROT" --allow-protected --reason "intentional rule update" | jq -c '{ok, state}'

echo "== 2. Direct node auto-lands without AI grade =="
q demo c d1 --kind direct | jq -c '{ok, node, kind}'
echo "small chore" > chore.txt && git add chore.txt && git commit -qm "chore"
C_DIR=$(git rev-parse HEAD)
out=$(q demo n d1 e handoff --commit "$C_DIR" --reason "verified chore")
echo "$out" | jq -c '{ok, kind, state, fin}'
echo "$out" | jq -e '.state == "landed" and .fin == "node_fin"' >/dev/null

echo "== 3. Research node: E_DOC_ONLY_NODE on src/, E_PROTECTED_FILE on landed NODE.md, allows downstream todo NODE.md =="
q demo c r1 --kind research | jq -c '{ok, node, kind}'
q demo c c2 --depends-on r1 | jq -c '{ok, node, kind, deps}'
printf 'let leak = 1\n' > src/quest/leak.ml && git add src/quest/leak.ml && git commit -qm "src leak"
C_SRC=$(git rev-parse HEAD)
out=$(q demo n r1 e handoff --commit "$C_SRC" --reason "oops" || true)
echo "$out" | jq -c '{ok, code: .error.code, paths: .error.facts.paths}'
echo "$out" | jq -e '.error.code == "E_DOC_ONLY_NODE"' >/dev/null
printf '# rewrite landed d1\n' > docs/quests/demo/nodes/d1/NODE.md && git add docs/quests/demo/nodes/d1/NODE.md && git commit -qm "edit landed node"
C_LANDED=$(git rev-parse HEAD)
out=$(q demo n r1 e handoff --commit "$C_LANDED" --reason "rewrite history" || true)
echo "$out" | jq -c '{ok, code: .error.code, paths: .error.facts.paths}'
echo "$out" | jq -e '.error.code == "E_PROTECTED_FILE"' >/dev/null
printf '# Sourced Report\n' > docs/quests/demo/research/r1/REPORT.md
printf '# Grounded c2 spec\n' > docs/quests/demo/nodes/c2/NODE.md
git add docs/quests/demo/research/r1/REPORT.md docs/quests/demo/nodes/c2/NODE.md && git commit -qm "research report + c2 spec"
C_RES=$(git rev-parse HEAD)
q demo n r1 e handoff --commit "$C_RES" --reason "grounded c2 spec" | jq -c '{ok, kind, state, fin}'

echo "== 4. Explore node: --target, --max-iterations, E_EXPLORE_BOUND, and --outcome =="
q demo c ex1 --kind explore --target "make check < 10s" --max-iterations 2 | jq -c '{ok, kind, explore}'
q demo n ex1 e iterate --note "run 1: 14.2s" | jq -c '{ok, explore}'
q demo n ex1 e iterate --note "run 2: 8.7s" | jq -c '{ok, explore}'
out=$(q demo n ex1 e iterate --note "run 3" || true)
echo "$out" | jq -c '{ok, code: .error.code, facts: .error.facts}'
echo "$out" | jq -e '.error.code == "E_EXPLORE_BOUND"' >/dev/null
printf '# Explore Report\n8.7s verified\n' > docs/quests/demo/explores/ex1/REPORT.md
git add docs/quests/demo/explores/ex1/REPORT.md && git commit -qm "explore report"
C_EX=$(git rev-parse HEAD)
q demo n ex1 e handoff --commit "$C_EX" --outcome hit --reason "8.7s verified" | jq -c '{ok, kind, state, fin, explore}'

echo "== 5. Human-gate: E_HUMAN_REQUIRED when unset, human & human-approved-llm-yolo, strict scope on resume =="
q demo c g1 --kind human-gate --depends-on d1 | jq -c '{ok, node, kind, legal_edges}'
q demo c g2 --kind human-gate --depends-on g1 | jq -c '{ok, node, kind}'
out=$(q demo n g1 e approve --reason "pick B" || true)
echo "$out" | jq -c '{ok, code: .error.code}'
echo "$out" | jq -e '.error.code == "E_HUMAN_REQUIRED"' >/dev/null
BP3_DECIDER=human q demo n g1 e approve --reason "pick B" | jq -c '{ok, kind, state, fin, decider}'
BP3_DECIDER=human-approved-llm-yolo q demo n g2 e approve --reason "chose B: lower risk, reversible" | jq -c '{ok, kind, state, fin, decider}'
q r demo | jq -c '{yolo_approvals}'
q demo c blk | jq -c '{ok, node}'
q demo n blk e block --reason "stuck" | jq -c '{ok, state}'
out=$(BP3_DECIDER=human-approved-llm-yolo q demo n blk e resume --reason "try yolo resume" || true)
echo "$out" | jq -c '{ok, code: .error.code}'
echo "$out" | jq -e '.error.code == "E_HUMAN_REQUIRED"' >/dev/null

echo "demo dag-contracts: OK"
