#!/bin/bash
# check-tiers fixtures (test-pyramid tier.2): the table-driven selector,
# the gates' tiers, one list of suites, derived lint targets, and the
# retired-term sweep's timing and fossil exemptions. Unit tier: runs in
# make check.
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
# 1. The selector reads the table: a planted one pins exact picks.
# Unit rows always run; a row joins when one of its paths globs
# matches a changed path ('*' crosses '/'); picks keep table order.
T=$(printf '\t')
{
  printf '%s\n' "u1${T}unit${T}true${T}60${T}0${T}-${T}-"
  printf '%s\n' "a${T}fixture${T}true${T}60${T}0${T}-${T}src/*"
  printf '%s\n' "b${T}slow${T}true${T}60${T}0${T}real processes${T}skills/*,test/b.sh"
  printf '%s\n' "c${T}fixture${T}true${T}60${T}0${T}-${T}docs/keep.md"
} > "$work/planted.tsv"
"$sel" --table "$work/planted.tsv" --list src/quest/x.ml | expect_list planted-src u1 a
"$sel" --table "$work/planted.tsv" --list src/a/b/c.ml | expect_list planted-nested u1 a
"$sel" --table "$work/planted.tsv" --list test/b.sh | expect_list planted-script u1 b
"$sel" --table "$work/planted.tsv" --list docs/keep.md src/y skills/s/SKILL.md | expect_list planted-order u1 a b c
# 2. A path no row claims selects the unit tier alone: never zero suites.
"$sel" --table "$work/planted.tsv" --list docs/other.md | expect_list planted-unclaimed u1
# 3. The real table: src/** reaches the binary suites and the drift
# check, never the skills render; docs/** is the unit tier alone.
"$sel" --list src/quest/main.ml > "$work/src.txt"
for s in g bp3-pi transcripts; do grep -qx "$s" "$work/src.txt" || fail "src/quest/main.ml did not select $s"; done
grep -qx skills "$work/src.txt" && fail "src/quest/main.ml selected the skills render" || checks=$((checks + 1))
units=()
while IFS= read -r u; do units+=("$u"); done < <(awk -F'\t' '$2 == "unit" { print $1 }' "$repo/test/suites.tsv")
[ ${#units[@]} -gt 0 ] || fail "the suite table has no unit tier"
"$sel" --list docs/quests/some-quest/QUEST.md | expect_list real-docs "${units[@]}"
"$sel" --list test/pi-tree.test.mjs | grep -qx pi-tree || fail "test/pi-tree.test.mjs did not select pi-tree"
checks=$((checks + 1))
# 4. Gates pick tiers, never suites: check runs the unit tier,
# check-full adds fixture and slow, check-fast is check.
mk() { make -C "$repo" -n "$1" 2>/dev/null; }
mk check | grep -q 'run-suites --tier unit$' || fail "make check does not run the unit tier"
mk check-full | grep -q 'run-suites --tier fixture,slow$' || fail "make check-full does not add fixture and slow"
[ "$(mk check-fast)" = "$(mk check)" ] || fail "make check-fast is not make check"
checks=$((checks + 3))
# 5. Suite names live in one list: no row's command appears in the
# Makefile or the selector, and lint covers every suite's script.
while IFS="$T" read -r name _tier cmd _; do
  case "$name" in ''|'#'*) continue ;; esac
  if grep -qF -- "$cmd" "$repo/Makefile" "$sel"; then fail "suite $name is listed outside test/suites.tsv: $cmd"; fi
done < "$repo/test/suites.tsv"
checks=$((checks + 1))
"$repo/scripts/shell-files" > "$work/shell.txt"
while IFS= read -r f; do
  grep -qx "$f" "$work/shell.txt" || fail "lint misses suite script $f"
done < <(awk -F'\t' '$1 !~ /^#/ && $1 != "" { n = split($3, w, " "); for (i = 1; i <= n; i++) if (w[i] ~ /\.sh$/) print w[i] }' "$repo/test/suites.tsv" | sed 's|^\./||' | sort -u)
# shellcheck disable=SC2016  # the Makefile's literal $$
grep -q 'shellcheck \$\$(./scripts/shell-files)' "$repo/Makefile" || fail "make lint does not derive its targets"
checks=$((checks + 2))
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
