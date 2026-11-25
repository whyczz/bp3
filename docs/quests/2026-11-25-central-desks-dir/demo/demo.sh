#!/usr/bin/env bash
# Landing demo for 2026-11-25-central-desks-dir: exercises central ~/.bp3/desks/
# layout, sibling quest+grade non-nesting, worktree-context config/list, dirty
# refusal + recovery, legacy .bp3/desks/ release transition, and zero --root=. /
# zero self-only skill split — strictly in a scratch sandbox.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../../.." && pwd)
bin="$repo/_build/default/src/quest/main.exe"
[ -x "$bin" ] || { echo "FAIL: build $bin first (make check)" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-central-desks-demo.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

export HOME="$work/home"
export BP3_DESKS_DIR="$work/desks"
export BP3_HARNESS=agy BP3_MODEL=demo-model

mkdir -p "$work/repo" "$HOME"
git -C "$work/repo" init -q -b master
git -C "$work/repo" config user.email demo@example.com
git -C "$work/repo" config user.name demo
echo "hello" > "$work/repo/app.txt"
git -C "$work/repo" add app.txt
git -C "$work/repo" commit -qm "init"
sha=$(git -C "$work/repo" rev-parse HEAD)

run_show() {
  echo "+ $*"
  "$@"
}

echo "=== 1. Happy path: central quest desk + sibling grade desk (zero <repo>/.bp3/) ==="
qout=$(cd "$work/repo" && run_show env -u BP3_ROOT "$bin" worktree prepare --quest q1)
echo "$qout"
qpath=$(echo "$qout" | tail -n 1 | jq -r '.path')
[[ "$qpath" == "$work/desks/repo-"*/quests/q1 ]] || { echo "FAIL: unexpected quest path $qpath" >&2; exit 1; }

gout=$(cd "$work/repo" && run_show env -u BP3_ROOT "$bin" worktree prepare q1 node-a --run grade-node-a-c1-a1 --commit "$sha")
echo "$gout"
gpath=$(echo "$gout" | tail -n 1 | jq -r '.path')
[[ "$gpath" == "$work/desks/repo-"*/runs/q1/node-a/grade-node-a-c1-a1 ]] || { echo "FAIL: unexpected grade path $gpath" >&2; exit 1; }
case "$gpath" in "$qpath"/*) echo "FAIL: grade desk nested inside quest desk" >&2; exit 1 ;; esac
[ ! -e "$work/repo/.bp3" ] || { echo "FAIL: repo .bp3/ was created" >&2; exit 1; }
[ -z "$(git -C "$qpath" status --short)" ] || { echo "FAIL: quest desk dirty while grade desk open" >&2; exit 1; }
echo "ok: sibling central desks created; <repo>/.bp3/ absent; quest desk clean"

echo "=== 2. Worktree-context parity: desk list & bp3 config from inside quest desk ==="
wt_list=$(cd "$qpath" && env -u BP3_ROOT "$bin" worktree list)
wt_cfg=$(cd "$qpath" && env -u BP3_ROOT "$bin" config)
echo "$wt_list" | jq -c '{ok, runs: [.worktrees[].run_id]}'
echo "$wt_cfg" | jq -c '{ok, mode, desks}'
echo "$wt_list" | jq -e '([.worktrees[].run_id] | length) == 2' >/dev/null || { echo "FAIL: worktree list" >&2; exit 1; }
echo "$wt_cfg" | jq -e '(.desks | length) == 2' >/dev/null || { echo "FAIL: worktree config desks" >&2; exit 1; }
(cd "$work/repo" && env -u BP3_ROOT "$bin" worktree release --run grade-node-a-c1-a1) | jq -c '{ok, released, run_id}'

echo "=== 3. Refusal + recovery: dirty quest desk refused (E_DIRTY_TREE), then cleaned & released ==="
echo "uncommitted" > "$qpath/wip.txt"
set +e
refusal=$(cd "$work/repo" && env -u BP3_ROOT "$bin" worktree release --quest q1 2>&1)
rc=$?
set -e
echo "$refusal"
[ "$rc" -ne 0 ] || { echo "FAIL: dirty release succeeded" >&2; exit 1; }
echo "$refusal" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || { echo "FAIL: expected E_DIRTY_TREE" >&2; exit 1; }
rm "$qpath/wip.txt"
(cd "$work/repo" && env -u BP3_ROOT "$bin" worktree release --quest q1) | jq -c '{ok, released, removed}'
[ ! -e "$qpath" ] || { echo "FAIL: quest desk not removed" >&2; exit 1; }

echo "=== 4. Legacy .bp3/desks/ read+release upgrade fallback ==="
mkdir -p "$work/repo/.bp3/desks" "$work/repo/.bp3/worktrees"
git -C "$work/repo" worktree add -q --detach "$work/repo/.bp3/worktrees/legq" "$sha"
printf '{"run_id":"LEGACY1","quest":"legq","node":"(quest)","path":".bp3/worktrees/legq","ref":"%s","detached":true,"created_ts":1700000000}\n' "$sha" \
  > "$work/repo/.bp3/desks/LEGACY1.json"
(cd "$work/repo" && env -u BP3_ROOT "$bin" worktree list) | jq -c '[.worktrees[] | {run_id, missing, orphan}]'
(cd "$work/repo" && env -u BP3_ROOT "$bin" worktree release --run LEGACY1) | jq -c '{ok, released, removed}'
[ ! -e "$work/repo/.bp3/desks/LEGACY1.json" ] && [ ! -e "$work/repo/.bp3/worktrees/legq" ] || { echo "FAIL: legacy desk left behind" >&2; exit 1; }

echo "=== 5. Repo hygiene: zero --root= in Makefile/check-gates, zero self-only skill split ==="
if grep -n -- "--root=" "$repo/Makefile" "$repo/scripts/check-gates"; then
  echo "FAIL: --root= still present" >&2; exit 1
fi
if grep -rn "host mode works in the repo" "$repo/skills/" "$repo/.agents/skills/" "$repo/.claude/skills/" "$repo/.pi/skills/"; then
  echo "FAIL: self-only skill prose still present" >&2; exit 1
fi
echo "DEMO OK"
