#!/usr/bin/env bash
# Runnable landing trial for 2026-11-23-codebase-diet.
# Exercises happy path, retired-surface refusal path, downstream host
# migration & pruning, and Chesterton's fence in a scratch sandbox
# (never touches this repo's state).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
bp3="$repo/bin/bp3"
gbin="$repo/_build/default/src/quest/main.exe"
[ -x "$gbin" ] || { echo "FAIL: build first (make check)" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/bp3-codebase-diet-trial.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
export BP3_DB="$work/bp3.sqlite"
export BP3_Q_BIN="$gbin"
export BP3_COMPLETIONS_DIR="$work/completions"

say() { printf '\n==> %s\n' "$*"; }

say "1. Happy path: lean repo surface, 3 languages, historical fold, Chesterton's fence"
(
  cd "$repo"
  test ! -e src/quest/harness.ml
  test ! -e skills/induct/workflows
  test ! -e extensions/bp3-pi
  test ! -e test/pi-discovery.mjs
  ./scripts/check-constraints
  suites="$(grep -c '^[^#]' test/suites.tsv)"
  echo "suites in test/suites.tsv: $suites"
  [ "$suites" -eq 25 ]
  hist="$(./bin/bp3 q r 2026-11-07-bp3-mvp-engine-core)"
  echo "$hist" | jq -e '.ok == true and .rollup == "landed" and .fin == "goal_fin"' >/dev/null
  echo "historical pre-rename quest fold: 2026-11-07-bp3-mvp-engine-core -> landed/goal_fin"
  tag_sha="$(git rev-parse archive/pre-codebase-diet:src/quest/harness.ml)"
  echo "Chesterton's fence tag archive/pre-codebase-diet:src/quest/harness.ml -> $tag_sha"
)

say "2. Refusal path: retired doors (bp3 harness supervisor, bp3 n, bp3 e) exit 2 with E_USAGE and leave state untouched"
fx="$work/fixture-repo"
mkdir -p "$fx"
git -C "$fx" init -q -b master
git -C "$fx" config user.email t@t.t
git -C "$fx" config user.name t
echo hi > "$fx/app.txt"
git -C "$fx" add app.txt
git -C "$fx" commit -qm init

# Read-only bp3 config must NOT create .git/bp3/
cfg="$(cd "$fx" && "$gbin" config)"
echo "$cfg" | jq -e '.ok == true and .mode == "host"' >/dev/null
test ! -e "$fx/.git/bp3"
echo "bp3 config: read-only ok (.git/bp3 not created)"

for cmd in "harness supervisor q1" "n r" "e handoff --commit HEAD --reason x"; do
  set +e
  # shellcheck disable=SC2086
  out="$(cd "$fx" && "$gbin" $cmd 2>&1)"
  rc=$?
  set -e
  echo "bp3 $cmd -> rc=$rc"
  [ "$rc" -eq 2 ] || { echo "FAIL: expected rc 2, got $rc: $out" >&2; exit 1; }
  echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || {
    echo "FAIL: expected E_USAGE JSON: $out" >&2; exit 1
  }
done
[ -z "$(git -C "$fx" status --short)" ]
echo "fixture repo clean after all refusals"

say "3. Downstream host migration & pruning (legacy workflows + induct-inline* + .pi/settings.json)"
mkdir -p "$fx/.agents/workflows" "$fx/.claude/skills/induct-inline" "$fx/.claude/skills/induct-inline-yolo" "$fx/.pi"
for wf in node-loop induct-grade induct-land induct-node; do
  echo "// legacy" > "$fx/.agents/workflows/$wf.js"
done
for s in induct-inline induct-inline-yolo; do
  printf -- '---\nname: %s\n---\n<!-- GENERATED from skills/%s/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->\nold\n' "$s" "$s" > "$fx/.claude/skills/$s/SKILL.md"
done
printf '{"skills":["/user/custom","!**/.agents/skills/induct-inline/SKILL.md","!**/.agents/skills/bp3g/SKILL.md"]}\n' > "$fx/.pi/settings.json"

BP3_TARGET="$fx" "$bp3" skills install --harness=all
test ! -e "$fx/.agents/workflows"
test ! -e "$fx/.claude/skills/induct-inline"
test ! -e "$fx/.claude/skills/induct-inline-yolo"
test -f "$fx/.claude/skills/induct/SKILL.md"
test -f "$fx/.claude/skills/induct-yolo/SKILL.md"
jq -e '(.skills | index("/user/custom") != null) and (.skills | index("!**/.agents/skills/induct-inline/SKILL.md") == null) and (.skills | index("!**/.agents/skills/bp3g/SKILL.md") == null) and (.skills | index("!**/.agents/skills/induct/SKILL.md") != null)' "$fx/.pi/settings.json" >/dev/null
BP3_TARGET="$fx" "$bp3" skills check | jq -e '.ok == true' >/dev/null
echo "downstream pruning + skills check: ok"

printf '\nTRIAL OK: all codebase-diet checks passed.\n'
