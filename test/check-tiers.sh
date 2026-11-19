#!/bin/bash
# check-tiers fixtures (node-followup-6-check-tiers): selector
# mappings, fast-tier membership, retired-term sweep timing and
# fossil exemptions. Run by the fast tier (check-tiers suite).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
sel="$repo/scripts/check-changed.sh"
sweep="$repo/scripts/check-retired-terms.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-check-tiers.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
checks=0
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_list() { # name expected... -- actual from stdin file
  local name=$1; shift
  local exp act
  exp=$(printf '%s\n' "$@")
  act=$(cat)
  [ "$act" = "$exp" ] || fail "$name: expected [$exp] got [$act]"
  checks=$((checks + 1))
}
# 1. skills/** -> skills checks + workflow tests, never harness.
"$sel" --list skills/induct/SKILL.md | expect_list skills-mapping check-skills skills induct
"$sel" --list skills/induct/SKILL.md | grep -q harness && fail "skills-mapping ran harness" || checks=$((checks + 1))
# 2. src/** -> build + binary suite, never skills suites.
"$sel" --list src/quest/main.ml | expect_list src-mapping build g transcripts
# 3. workflow renders -> skills check + matching test only.
"$sel" --list .agents/workflows/induct-grade.js | expect_list render-mapping skills-check wf:induct-grade
"$sel" --list skills/induct/workflows/node-loop.js | expect_list render-mapping-src skills-check wf:node-loop
# 4. Unknown path fails safe to the fast tier, never zero suites.
"$sel" --list docs/quests/some-quest/QUEST.md > "$work/unknown.txt"
"$sel" --fast --list > "$work/fast.txt"
cmp -s "$work/unknown.txt" "$work/fast.txt" || fail "unknown path did not fail safe to fast tier"
[ -s "$work/unknown.txt" ] || fail "unknown path selected zero suites"
checks=$((checks + 2))
# 5. Fast tier: lint + skills + workflow/unit, no wall-clock suite.
if ! grep -qx lint "$work/fast.txt" || ! grep -qx check-skills "$work/fast.txt" || ! grep -qx induct "$work/fast.txt"; then fail "fast tier missing lint/skills/workflow suites"; fi
grep -qx harness "$work/fast.txt" && fail "fast tier contains harness.sh (wall-clock)" || checks=$((checks + 2))
grep -q './test/harness.sh' "$repo/Makefile" || fail "full check lost harness.sh"
checks=$((checks + 1))
# 6. Planted stale term in a skills file fails the sweep in
# under 5s naming file:line, before any suite runs.
mkdir -p "$work/planted/scripts" "$work/planted/skills/demo"
cp "$sweep" "$sel" "$work/planted/scripts/"
printf -- '---\nname: demo\ndescription: demo\n---\nSee GOAL.md for the plan.\n' > "$work/planted/skills/demo/SKILL.md"
(cd "$work/planted" && git init -q && git add -A)
start=$(date +%s)
if "$work/planted/scripts/check-retired-terms.sh" --root "$work/planted" > "$work/planted.out" 2>&1; then fail "planted term passed the sweep"; fi
end=$(date +%s)
[ $((end - start)) -lt 5 ] || fail "planted-term sweep took $((end - start))s (>= 5s)"
grep -q 'skills/demo/SKILL.md:5' "$work/planted.out" || fail "planted-term hit did not name file:line: $(cat "$work/planted.out")"
checks=$((checks + 3))
if (cd "$work/planted" && ./scripts/check-changed.sh skills/demo/SKILL.md) > "$work/planted-run.out" 2>&1; then fail "planted term passed check-changed"; fi
grep -q 'retired-term sweep: FAIL' "$work/planted-run.out" || fail "check-changed did not fail at the sweep"
grep -q 'check-changed: run' "$work/planted-run.out" && fail "a suite ran before the sweep failed" || checks=$((checks + 3))
# 6b. Root docs match in any case: a lowercase readme.md hit fails
# the sweep naming file:line, with and without git. A case-exact
# README.md lookup skips it on Linux and drops the name on macOS.
for mode in git plain; do
  mkdir -p "$work/case-$mode/scripts"
  cp "$sweep" "$work/case-$mode/scripts/"
  printf '# demo\n\nSee docs/graphs for the plan.\n' > "$work/case-$mode/readme.md"
  if [ "$mode" = git ]; then (cd "$work/case-$mode" && git init -q && git add -A); fi
  if "$work/case-$mode/scripts/check-retired-terms.sh" --root "$work/case-$mode" > "$work/case-$mode.out" 2>&1; then fail "case-$mode: lowercase readme.md hit passed the sweep"; fi
  grep -q '^readme.md:3:' "$work/case-$mode.out" || fail "case-$mode: hit did not name readme.md:3: $(cat "$work/case-$mode.out")"
  checks=$((checks + 2))
done
# 7. Fossils stay legal: ledger lines, run notes, and the
# migration rename table quoting retired spellings pass.
mkdir -p "$work/fossil/scripts" "$work/fossil/skills/demo" "$work/fossil/docs/quests/g/nodes/n/runs/r1"
cp "$sweep" "$work/fossil/scripts/"
cp "$repo/scripts/migrate-quest-rename.sh" "$work/fossil/scripts/"
printf -- '---\nname: demo\ndescription: demo\n---\nClean.\n' > "$work/fossil/skills/demo/SKILL.md"
printf '{"old":"docs/goals/g/GOAL.md"}\n' > "$work/fossil/docs/quests/g/ledger.jsonl"
printf 'quoted EXPERIMENT.md in run notes\n' > "$work/fossil/docs/quests/g/nodes/n/runs/r1/notes.md"
(cd "$work/fossil" && git init -q && git add -A)
"$work/fossil/scripts/check-retired-terms.sh" --root "$work/fossil" > /dev/null || fail "fossil paths failed the sweep"
checks=$((checks + 1))
# 8. The real repo is clean under the sweep.
"$sweep" > /dev/null || fail "repo fails its own sweep"
checks=$((checks + 1))
echo "check-tiers tests: ok ($checks assertions)"
