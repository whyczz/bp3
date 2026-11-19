#!/bin/bash
# check-changed — change-scoped verification (test-pyramid tier.2).
# Runs the retired-term sweep first (seconds, before any suite), then
# `make check` (lint plus the unit tier), then every other suite whose
# `paths` globs in test/suites.tsv match a changed path, through
# run-suites. The unit tier always runs, so the selection is never
# empty; a path no row claims (docs/**, say) selects nothing more.
#
# Usage:
#   scripts/check-changed.sh [--list] [--table f] [path ...]
#   make check-changed        # paths from git diff vs HEAD + untracked
# --list prints the selected suite names in table order, runs nothing.
# --table reads another suite table (check-tiers.sh plants one).
# -h/--help prints this text, exit 0, reads no state.
#
# The suite table (test/suites.tsv) is the single list of suites: this
# script names none. A `paths` glob is a shell pattern, so `src/*`
# matches every path under src/.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
list_only=0; table="$root/test/suites.tsv"; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list_only=1 ;;
    --table) shift; [ $# -gt 0 ] || { echo "check-changed: --table needs a value" >&2; exit 2; }; table=$1 ;;
    -h|--help) grep '^#' "$0" | head -20; exit 0 ;;
    *) paths+=("$1") ;;
  esac
  shift
done
# Retired-term sweep first: a stale term fails in seconds, before the
# table is read or any suite runs.
[ "$list_only" = 1 ] || ./scripts/check-retired-terms.sh
[ -f "$table" ] || { echo "check-changed: no suite table: $table" >&2; exit 2; }
if [ ${#paths[@]} -eq 0 ]; then
  while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
fi

selected=()
while IFS=$'\t' read -r name tier _cmd _budget _serial _why globs; do
  case "$name" in ''|'#'*) continue ;; esac
  if [ "$tier" = unit ]; then selected+=("$name"); continue; fi
  hit=0
  IFS=',' read -r -a gl <<< "$globs"
  for p in "${paths[@]:-}"; do
    [ -n "$p" ] || continue
    for g in "${gl[@]}"; do
      # shellcheck disable=SC2053  # the glob is a pattern on purpose
      if [ "$g" != - ] && [[ $p == $g ]]; then hit=1; break 2; fi
    done
  done
  [ "$hit" = 1 ] && selected+=("$name")
done < "$table"

if [ "$list_only" = 1 ]; then printf '%s\n' "${selected[@]}"; exit 0; fi
echo "check-changed: suites: ${selected[*]}"
echo "check-changed: run make check"
make check
rest=()
while IFS=$'\t' read -r name tier _; do
  case "$name" in ''|'#'*) continue ;; esac
  [ "$tier" = unit ] && continue
  for s in "${selected[@]}"; do [ "$s" = "$name" ] && rest+=("$name"); done
done < "$table"
if [ ${#rest[@]} -gt 0 ]; then
  only=$(IFS=,; echo "${rest[*]}")
  echo "check-changed: run run-suites --only $only"
  ./scripts/run-suites --table "$table" --only "$only"
fi
echo "check-changed: ok (${#selected[@]} suites)"
