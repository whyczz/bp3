#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/scripts" "$work/repo/plans" "$work/repo/docs/quests"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/invoke/main.exe" "$work/repo/invoke-bin"
cp "$root/plans/default.yaml" "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
bp3() { BP3_INVOKE_BIN="$work/repo/invoke-bin" ./bin/bp3 invoke "$@"; }

out=$(bp3 init demo --type default --engine single)
grep -q "## Success picture" docs/quests/demo/QUEST.md
grep -q "^stage: author" docs/quests/demo/state.yaml
bp3 list | jq -e 'any(.[]; .quest == "demo" and .status == "proposed")' >/dev/null
echo "$out" | jq -e '.stage == "author"' >/dev/null

# author submits commit B
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
out=$(bp3 demo submit --commit "$B" --reason "first cut")
echo "$out" | jq -e '.stage == "review"' >/dev/null

# stale/illegal: another submit from review is refused and logged
if bp3 demo submit --commit "$B" 2>/dev/null; then echo "FAIL: illegal submit accepted"; exit 1; fi

# one review round: fix_first -> fix (cycle 1), submit C, fix_first again -> blocked
out=$(bp3 demo review --verdict fix_first --reason "needs work")
echo "$out" | jq -e '.stage == "fix" and .cycle == 1' >/dev/null
echo fix > c.txt; git add c.txt; git commit -qm fix
C=$(git rev-parse HEAD)
out=$(bp3 demo submit --commit "$C" --reason "fixed")
echo "$out" | jq -e '.stage == "review"' >/dev/null
out=$(bp3 demo review --verdict fix_first --reason "still broken")
echo "$out" | jq -e '.stage == "blocked"' >/dev/null

# dirty tree refusal: fresh quest, dirty a file, submit must refuse
bp3 init dirty-demo >/dev/null
echo dirty >> a.txt
if bp3 dirty-demo submit --commit "$C" 2>/dev/null; then echo "FAIL: dirty submit accepted"; exit 1; fi
git checkout -q -- a.txt

# happy land path on a second quest
bp3 init ship-demo >/dev/null
out=$(bp3 ship-demo submit --commit "$C" --reason "work")
out=$(bp3 ship-demo review --verdict ship --reason "checks green")
echo "$out" | jq -e '.stage == "ready"' >/dev/null
out=$(bp3 ship-demo land --reason "gates pass")
echo "$out" | jq -e '.stage == "landed"' >/dev/null

# ledger has refusals recorded
jq -s -e 'any(.[]; .result == "refused")' docs/quests/demo/ledger.jsonl >/dev/null
echo "invoke tests: ok"
