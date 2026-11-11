#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/scripts" "$work/repo/plans" "$work/repo/docs/quests"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/invoke/main.exe" "$work/repo/invoke-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
bp3() { BP3_INVOKE_BIN="$work/repo/invoke-bin" ./bin/bp3 invoke "$@"; }

out=$(bp3 init demo --type default --engine single)
grep -q "## Success picture" docs/quests/demo/QUEST.md
grep -q "^stage: author" docs/quests/demo/state.yaml
BP3_INVOKE_BIN="$work/repo/invoke-bin" ./bin/bp3 quest list | jq -e 'any(.[]; .quest == "demo" and .status == "proposed")' >/dev/null
BP3_INVOKE_BIN="$work/repo/invoke-bin" ./bin/bp3 quest show demo | jq -e '.stage == "author"' >/dev/null
echo "$out" | jq -e '.stage == "author"' >/dev/null

# author submits commit B
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
out=$(bp3 demo submit --commit "$B" --reason "first cut")
echo "$out" | jq -e '.stage == "review"' >/dev/null

# stale/illegal: another submit from review is refused and logged
if bp3 demo submit --commit "$B" 2>/dev/null; then echo "FAIL: illegal submit accepted"; exit 1; fi

# one review round: fix_first -> fix (cycle 1), submit C, fix_first again -> blocked
out=$(bp3 demo review --actor reviewer-1 --verdict fix_first --reason "needs work")
echo "$out" | jq -e '.stage == "fix" and .cycle == 1' >/dev/null
echo fix > c.txt; git add c.txt; git commit -qm fix
C=$(git rev-parse HEAD)
out=$(bp3 demo submit --commit "$C" --reason "fixed")
echo "$out" | jq -e '.stage == "review"' >/dev/null
out=$(bp3 demo review --actor reviewer-1 --verdict fix_first --reason "still broken")
echo "$out" | jq -e '.stage == "blocked"' >/dev/null

# dirty tree refusal: fresh quest, dirty a file, submit must refuse
bp3 init dirty-demo >/dev/null
echo dirty >> a.txt
if bp3 dirty-demo submit --commit "$C" 2>/dev/null; then echo "FAIL: dirty submit accepted"; exit 1; fi
git checkout -q -- a.txt

# happy land path on a second quest
bp3 init ship-demo >/dev/null
out=$(bp3 ship-demo submit --commit "$C" --reason "work")
out=$(bp3 ship-demo review --actor reviewer-2 --verdict ship --reason "looks right")
if bp3 ship-demo land --reason "too early" 2>/dev/null; then echo "FAIL: land without check accepted"; exit 1; fi
out=$(bp3 ship-demo check --actor ci --verdict pass --reason "make check green")
echo "$out" | jq -e '.stage == "ready"' >/dev/null
out=$(bp3 ship-demo land --reason "gates pass")
echo "$out" | jq -e '.stage == "landed"' >/dev/null

# direct plan: no review stage at all
bp3 init direct-demo --type direct >/dev/null
out=$(bp3 direct-demo submit --commit "$C" --reason "solo work")
echo "$out" | jq -e '.stage == "ready"' >/dev/null
out=$(bp3 direct-demo check --actor ci --verdict pass --reason "green")
out=$(bp3 direct-demo land --reason "direct land")
echo "$out" | jq -e '.stage == "landed"' >/dev/null

# worktree utility
out=$(bp3 demo prepare --run r1); echo "$out" | grep -q worktree
test -d .bp3/worktrees/demo-r1
bp3 demo release --run r1 >/dev/null
test ! -d .bp3/worktrees/demo-r1

# parallel illegal invokes: refusals still get unique ledger seqs
bp3 init race-demo >/dev/null
for _ in 1 2 3 4 5 6 7 8; do bp3 race-demo land --reason race 2>/dev/null & done; wait
jq -s -e '([.[].seq] | unique | length) == (length)' docs/quests/race-demo/ledger.jsonl >/dev/null

# depends_on: submit refused until the dependency lands
bp3 init dep-demo --type direct >/dev/null
bp3 init gated-demo --depends-on dep-demo >/dev/null
bp3 gated-demo | jq -e '.blocked_by == ["dep-demo"]' >/dev/null
if bp3 gated-demo submit --commit "$C" 2>/dev/null; then echo "FAIL: submit before dependency landed"; exit 1; fi
bp3 dep-demo submit --commit "$C" --reason "dep work" >/dev/null
bp3 dep-demo check --actor ci --verdict pass --reason "green" >/dev/null
bp3 dep-demo land --reason "dep lands" >/dev/null
bp3 gated-demo | jq -e '.blocked_by == []' >/dev/null
out=$(bp3 gated-demo submit --commit "$C" --reason "now allowed")
echo "$out" | jq -e '.stage == "review"' >/dev/null

# cancel syncs QUEST.md status (not the fsm.yaml plan) and list filtering
bp3 init cancel-demo >/dev/null
cp docs/quests/cancel-demo/fsm.yaml "$work/fsm-before.yaml"
out=$(bp3 cancel-demo cancel --reason "called off")
echo "$out" | jq -e '.stage == "canceled"' >/dev/null
grep -q "^status: canceled" docs/quests/cancel-demo/QUEST.md
cmp -s docs/quests/cancel-demo/fsm.yaml "$work/fsm-before.yaml"
BP3_INVOKE_BIN="$work/repo/invoke-bin" ./bin/bp3 quest list --all | jq -e 'any(.[]; .quest == "cancel-demo" and .status == "canceled")' >/dev/null
BP3_INVOKE_BIN="$work/repo/invoke-bin" ./bin/bp3 quest list | jq -e 'all(.[]; .quest != "cancel-demo")' >/dev/null

# ledger has refusals recorded
jq -s -e 'any(.[]; .result == "refused")' docs/quests/demo/ledger.jsonl >/dev/null
echo "invoke tests: ok"
