#!/bin/bash
# check-tiers fixtures (test-pyramid tier.2): the table-driven selector,
# the gates' tiers, one list of suites, derived lint targets, and the
# retired-term sweep's timing and fossil exemptions. Fixture tier: runs in
# make check-full (lint's check-gates guards the gates in both).
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
# 3. The real table: src/** reaches the binary suites and never the
# skills render; docs/** selects no extra suites beyond make check.
"$sel" --list src/quest/main.ml > "$work/src.txt"
for s in g metrics warden; do grep -qx "$s" "$work/src.txt" || fail "src/quest/main.ml did not select $s"; done
grep -qx skills "$work/src.txt" && fail "src/quest/main.ml selected the skills render" || checks=$((checks + 1))
real_docs=$("$sel" --list docs/quests/some-quest/QUEST.md)
[ -z "$real_docs" ] || fail "real-docs: expected empty selection, got [$real_docs]"
checks=$((checks + 1))
# 4. The gates' wiring is checked from lint (scripts/check-gates), which
# both gates run first; lint must keep running it, and each planted
# break must fail it by name.
# read the plan once: grep -q under pipefail can SIGPIPE make (a flake)
lint_plan=$(make -C "$repo" -s -n lint)
grep -qx './scripts/check-gates' <<< "$lint_plan" || fail "make lint does not run scripts/check-gates"
grep -qx './scripts/check-constraints' <<< "$lint_plan" || fail "make lint does not run scripts/check-constraints"
grep -qx './scripts/check-bump' <<< "$lint_plan" || fail "make lint does not run scripts/check-bump"
"$repo/scripts/check-gates" > /dev/null || fail "check-gates fails on the real Makefile"
checks=$((checks + 4))
# Planted Makefiles, built with awk (no sed newline quirks): each break
# must fail check-gates, naming the reason.
plant_swap()   { awk -v o="$2" -v n="$3" '{ if ($0 == o) print n; else print }' "$repo/Makefile" > "$work/Makefile.$1"; }
plant_after()  { awk -v o="$2" -v n="$3" '{ print; if ($0 == o) print n }' "$repo/Makefile" > "$work/Makefile.$1"; }
plant_drop()   { awk -v o="$2" '$0 != o' "$repo/Makefile" > "$work/Makefile.$1"; }
plant_append() { { cat "$repo/Makefile"; printf '%s\n' "$2"; } > "$work/Makefile.$1"; }
gates_fail() { # name expected-message
  cmp -s "$repo/Makefile" "$work/Makefile.$1" && fail "gates-$1: the planted break changed nothing"
  if "$repo/scripts/check-gates" --makefile "$work/Makefile.$1" > "$work/gates-$1.out" 2>&1; then fail "gates-$1: a broken Makefile passed check-gates"; fi
  grep -qF -- "$2" "$work/gates-$1.out" || fail "gates-$1: wrong reason: $(cat "$work/gates-$1.out")"
  checks=$((checks + 1))
}
every=$'\t./scripts/run-suites'
dune_test=$'\t$(DUNE_TEST)'
plant_drop no-dune-test "$dune_test";                         gates_fail no-dune-test 'make check stops after 6 of 7 steps'
plant_swap dune-or-true "$dune_test" "$dune_test || true";    gates_fail dune-or-true 'the Makefile ignores errors'
plant_swap full-ignore "$every" $'\t-./scripts/run-suites';  gates_fail full-ignore "ignores errors ('-' prefix)"
plant_append dot-ignore '.IGNORE:';                           gates_fail dot-ignore 'the Makefile ignores errors'
plant_swap full-one-tier "$every" "$every --tier slow";       gates_fail full-one-tier 'make check-full step 8 is not the'
plant_swap full-no-lint 'check-full: lint ocaml' 'check-full: ocaml';  gates_fail full-no-lint 'make check-full step 1 is not the'
plant_swap full-no-dune 'check-full: lint ocaml' 'check-full: lint';   gates_fail full-no-dune 'make check-full step 6 is not the'
plant_swap fast-differs 'check-fast: check' 'check-fast: lint';        gates_fail fast-differs 'make check-fast is not make check'
plant_after suite-bash 'check: lint ocaml' $'\tbash test/g.sh';        gates_fail suite-bash 'make check has an extra step: bash test/g.sh'
plant_after suite-dot 'check: lint ocaml' $'\t./test/./g.sh';          gates_fail suite-dot 'make check has an extra step: ./test/./g.sh'
plant_after check-only 'check: lint ocaml' $'\t./scripts/check-retired-terms.sh'; gates_fail check-only 'make check has an extra step: ./scripts/check-retired-terms.sh'
plant_drop no-stack $'\t./scripts/check-constraints';           gates_fail no-stack 'make check step 2 is not the'
plant_drop no-bump $'\t./scripts/check-bump';                   gates_fail no-bump 'make check step 3 is not the'
plant_swap dune-root-hack $'\t$(DUNE_BUILD) src/quest/main.exe src/quest/run_suites.exe' $'\t$(DUNE_BUILD) --root=. src/quest/main.exe src/quest/run_suites.exe'; gates_fail dune-root-hack 'the Makefile carries a --root workaround'
plant_swap dune-test-root-hack "$dune_test" "$dune_test --root=."; gates_fail dune-test-root-hack 'the Makefile carries a --root workaround'
# shellcheck disable=SC2016  # literal Makefile $(...) syntax
plant_swap dune-cond-root-hack 'DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build' 'DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)'; gates_fail dune-cond-root-hack 'the Makefile carries a --root workaround'
# 5. Lint's targets are derived and cover every suite's script.
"$repo/scripts/shell-files" > "$work/shell.txt"
while IFS= read -r f; do
  grep -qx "$f" "$work/shell.txt" || fail "lint misses suite script $f"
done < <(awk -F'\t' '$1 !~ /^#/ && $1 != "" { n = split($3, w, " "); for (i = 1; i <= n; i++) if (w[i] ~ /\.sh$/) print w[i] }' "$repo/test/suites.tsv" | sed 's|^\./||' | sort -u)
# shellcheck disable=SC2016  # the Makefile's literal $$
grep -qF 'files=$$(./scripts/shell-files) && [ -n "$$files" ] && shellcheck $$files' "$repo/Makefile" || fail "make lint does not derive its shellcheck targets"
checks=$((checks + 2))
# 5b. check-changed's run half, end to end, with make and run-suites
# stubbed: the sweep, then make check, then run-suites on exactly the
# matching rows; a path no row claims runs make check alone.
mkdir -p "$work/cc/scripts" "$work/cc/test"
cp "$sel" "$sweep" "$work/cc/scripts/"
cp "$work/planted.tsv" "$work/cc/test/suites.tsv"
printf 'check:\n\t@echo STUB make check\n' > "$work/cc/Makefile"
printf '#!/bin/sh\necho "STUB run-suites $*"\n' > "$work/cc/scripts/run-suites"
chmod +x "$work/cc/scripts/run-suites"
(cd "$work/cc" && git init -q && git add -A)
(cd "$work/cc" && ./scripts/check-changed.sh src/x.ml test/b.sh) > "$work/cc-run.out" 2>&1 || fail "check-changed run failed: $(cat "$work/cc-run.out")"
grep -E '^(retired-term sweep|STUB)' "$work/cc-run.out" > "$work/cc-steps.txt"
cc_root=$(cd "$work/cc" && pwd)   # as the script spells its own root
expect_list cc-run "retired-term sweep: ok" "STUB make check" "STUB run-suites --table $cc_root/test/suites.tsv --only a,b" < "$work/cc-steps.txt"
(cd "$work/cc" && ./scripts/check-changed.sh docs/other.md) > "$work/cc-docs.out" 2>&1 || fail "check-changed docs run failed"
grep -q 'STUB make check' "$work/cc-docs.out" || fail "a docs-only change skipped make check"
grep -q 'STUB run-suites' "$work/cc-docs.out" && fail "a docs-only change ran suites beyond the unit tier" || checks=$((checks + 1))
if "$sel" --lsit src/x.ml > /dev/null 2>&1; then fail "check-changed took an unknown flag as a path"; fi
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
cp "$repo/scripts/migrate-graph-rename.sh" "$work/fossil/scripts/"
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
