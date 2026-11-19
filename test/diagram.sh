#!/usr/bin/env bash
# mvp.4: diagram verb — ascii + mermaid generated from the
# live rollup. Fixture quests are built through bp3 q itself;
# both formats must carry the rollup facts of the same moment.
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
fail() { echo "FAIL: $*" >&2; exit 1; }

commit_on_node() { # $1 quest $2 node $3 path $4 content -> new tip
  local branch="refs/heads/bp3/node/$1/$2" tip blob tree new_tip idx="$work/idx-$1-$2"
  tip=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(printf '%s' "$4" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$3"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$2" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"; rm -f "$idx"
  printf '%s' "$new_tip"
}
land_node() { # $1 quest $2 node $3 path
  local c; c=$(commit_on_node "$1" "$2" "$3" "content-$2")
  q "$1" u "$2" handoff --commit "$c" --reason work >/dev/null
  q "$1" u "$2" grade --verdict ship --reason ok >/dev/null
  q "$1" u "$2" verify --verdict pass --reason ok >/dev/null
  q "$1" u "$2" land --reason ship >/dev/null
}

# --- diamond: waves, deps, landed marker, honest labels ---
q c quest1 >/dev/null
q quest1 c na >/dev/null; q quest1 c nb >/dev/null
q quest1 c nc --depends-on na,nb >/dev/null
land_node quest1 na fa.txt
ascii=$(q quest1 diagram --format ascii)
mermaid=$(q quest1 diagram --format mermaid)
echo "$ascii" | grep -q "generated from live state at 20" || fail "ascii honest label: $ascii"
echo "$mermaid" | grep -q "generated from live state at 20" || fail "mermaid honest label: $mermaid"
echo "$ascii" | grep -qx "  na (landed, cycle 1, node_fin)" || fail "ascii landed node: $ascii"
echo "$ascii" | grep -qx "  nb (todo, cycle 1)" || fail "ascii todo node: $ascii"
echo "$ascii" | grep -qx "  na .* nc" || fail "ascii dep na->nc: $ascii"
echo "$ascii" | grep -qx "  nb .* nc" || fail "ascii dep nb->nc: $ascii"
echo "$ascii" | grep -qx "  wave 1: nb" || fail "ascii wave: $ascii"
echo "$mermaid" | grep -q 'na\["na (landed, cycle 1, node_fin)"\]' || fail "mermaid landed node: $mermaid"
echo "$mermaid" | grep -q 'nb -->|dep| nc' || fail "mermaid dep nb->nc: $mermaid"
echo "$mermaid" | grep -q 'na -->|dep| nc' || fail "mermaid dep na->nc: $mermaid"
echo "$mermaid" | grep -q 'wave 1' || fail "mermaid wave: $mermaid"
# every node and dep exactly once per format (definitions)
for fmt in ascii mermaid; do
  out=$(q quest1 diagram --format "$fmt")
  [ "$(echo "$out" | grep -c 'na (landed')" = 1 ] || fail "$fmt na defined once: $out"
  [ "$(echo "$out" | grep -c 'nc (todo')" = 1 ] || fail "$fmt nc defined once: $out"
  [ "$(echo "$out" | grep -c 'dep' )" -ge 2 ] || fail "$fmt deps drawn: $out"
done
# json carries the same facts plus both texts
out=$(q quest1 diagram --format json)
echo "$out" | jq -e '.ok == true and .format == "json" and (.generated_at | test("^20")) and .ready_set_waves == [["nb"],["nc"]] and (.deps | sort_by(.from) == [{"from":"na","to":"nc"},{"from":"nb","to":"nc"}]) and (.diagram_ascii | contains("na (landed, cycle 1, node_fin)")) and (.diagram_mermaid | contains("graph LR"))' >/dev/null || fail "json facts: $out"

# --- ascii is current: moving one node changes that node ---
before=$(q quest1 diagram --format ascii)
q quest1 u nb block --reason "choose storage" >/dev/null
after=$(q quest1 diagram --format ascii)
echo "$after" | grep -qx "  nb (blocked, cycle 1)" || fail "ascii current state: $after"
echo "$after" | grep -qx "  nb starves: nc" || fail "ascii starved: $after"
m2=$(q quest1 diagram --format mermaid)
echo "$m2" | grep -q "nb starves: nc" || fail "mermaid starved: $m2"
echo "$m2" | grep -q 'nb (blocked, cycle 1)' || fail "mermaid blocked node: $m2"
[ "$(diff <(echo "$before") <(echo "$after") | grep -c '^[<>]')" -ge 2 ] || fail "diagram did not change"

# --- read-only: diagram writes no ledger line ---
tip_before=$(git rev-parse bp3/node/quest1/nb)
q quest1 diagram --format ascii >/dev/null; q quest1 diagram --format mermaid >/dev/null; q quest1 diagram --format json >/dev/null
[ "$(git rev-parse bp3/node/quest1/nb)" = "$tip_before" ] || fail "diagram wrote state"

# --- strict argv + help at its door ---
if out=$(q quest1 diagram --format svg 2>&1); then fail "bad format accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "bad format code: $out"
if out=$(q quest1 diagram extra 2>&1); then fail "stray positional accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "stray code: $out"
if out=$(q nope diagram --format ascii 2>&1); then fail "unknown quest accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unknown quest code: $out"
out=$(q quest1 diagram -h) || fail "diagram -h exit"
echo "$out" | grep -q -- "--format ascii|mermaid|json" || fail "diagram help flags: $out"
echo "$out" | grep -q "generated" || fail "diagram help generated: $out"
out=$(q quest1 -h) || fail "node door -h exit"
echo "$out" | grep -q "diagram" || fail "node door help diagram: $out"
out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q -h) || fail "q -h exit"
echo "$out" | grep -q "diagram" || fail "q help diagram: $out"

echo "diagram tests: ok"
