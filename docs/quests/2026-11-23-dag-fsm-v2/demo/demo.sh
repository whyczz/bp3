#!/usr/bin/env bash
# Runnable demo for 2026-11-23-dag-fsm-v2 (scratch sandbox, never touches repo state).
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../../.." && pwd)
bin="$repo/_build/default/src/quest/main.exe"
[ -x "$bin" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-demo-dag-fsm-v2.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

cd "$work"
git init -q -b master
git config user.email demo@bp3.local
git config user.name "bp3 demo"
mkdir -p plans
cp "$repo/plans/default.yaml" "$repo/plans/direct.yaml" plans/
printf 'goal_type: manual\nmax_cycles: 3\ngrade:\n  required: true\nland: manual\n' > plans/manual.yaml
echo "base" > app.txt
git add -A && git commit -qm "base"

export BP3_HARNESS=agy BP3_MODEL=demo
q() { "$bin" q "$@"; }

echo "== 1. Lean 2-edge happy path (land: auto): todo -> handed_off -> landed =="
q c demo --type default | jq -c '{ok, quest, state}'
q demo c n1 | jq -c '{ok, node, state, legal_edges}'
echo "n1 work" >> app.txt && git add app.txt && git commit -qm "feat: n1"
C1=$(git rev-parse HEAD)
q demo n n1 e handoff --commit "$C1" --reason "n1 ready" | jq -c '{ok, node, state, legal_edges}'
out=$(q demo n n1 e grade --verdict ship --reason "clean")
echo "$out" | jq -c '{ok, node, state, fin, legal_edges}'
echo "$out" | jq -e '.state == "landed" and .fin == "node_fin"' >/dev/null

echo "== 2. Refusal: retired standalone verify edge returns E_USAGE =="
q demo c n-ver | jq -c '{ok, node, state}'
out=$(q demo n n-ver e verify --verdict pass --reason "old edge" || true)
echo "$out" | jq -c '{ok, code: .error.code, detail: .error.facts.detail}'
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null

echo "== 3. Refusal + recovery: E_MISSING_ANCESTOR on diverged dep branch =="
q demo c n2 --depends-on n1 | jq -c '{ok, node, deps}'
git checkout -qb diverged HEAD~1
echo "diverged work" > side.txt && git add side.txt && git commit -qm "feat: diverged n2"
C_DIV=$(git rev-parse HEAD)
out=$(q demo n n2 e handoff --commit "$C_DIV" --reason "missing n1" || true)
echo "$out" | jq -c '{ok, code: .error.code, missing: .error.facts.missing}'
echo "$out" | jq -e '.error.code == "E_MISSING_ANCESTOR" and .error.facts.missing[0].node == "n1"' >/dev/null
git merge -q master -m "merge n1 into n2"
C_OK=$(git rev-parse HEAD)
q demo n n2 e handoff --commit "$C_OK" --reason "rebased onto n1" | jq -c '{ok, node, state}'
q demo n n2 e grade --verdict ship --reason "ancestry verified" | jq -c '{ok, node, state, fin}'

echo "== 4. Opt-in land: manual preserves approved -> land =="
git checkout -q master
q c manual-demo --type manual | jq -c '{ok, quest}'
q manual-demo c m1 | jq -c '{ok, node}'
q manual-demo n m1 e handoff --commit "$C1" --reason "ready" | jq -c '{ok, state}'
out=$(q manual-demo n m1 e grade --verdict ship --reason "approved")
echo "$out" | jq -c '{ok, state, legal_edges}'
echo "$out" | jq -e '.state == "approved" and (.legal_edges | index("land") != null)' >/dev/null
q manual-demo n m1 e land --reason "explicit land" | jq -c '{ok, state, fin}'

echo "demo dag-fsm-v2: OK"
