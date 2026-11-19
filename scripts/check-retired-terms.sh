#!/bin/bash
# check-retired-terms — retired-term sweep for the fast tier
# (node-followup-6-check-tiers). Greps live surfaces for the
# repo's retired spellings before any suite runs, so a stale
# term costs seconds, not a grade cycle.
#
# Retired spellings (single source; post-rename vocabulary):
#   GOAL.md GRAPH.md EXPERIMENT.md   (now QUEST.md / NODE.md)
#
# Live surfaces swept: skills/, src/, bin/, scripts/,
# extensions/, the rendered skill copies (.pi/skills/,
# .agents/skills/, .claude/skills/, .agents/workflows/),
# and the root docs AGENTS.md / CLAUDE.md / README.md.
# Out of scope by definition: docs/ (frozen records — ledger
# lines, dated amendments, run notes quote history) and
# test/ (fixtures quote retired spellings as data).
#
# Fossil exemptions, one row per path, each with its reason.
# No blanket per-file exemption for live files.
#   scripts/migrate-graph-rename.sh | migration rename table:
#     quotes the retired spellings in order to rename them
#   scripts/check-retired-terms.sh  | declares the retired list
#
# shellcheck disable=SC2086 # $scope is a word list by design.
# Usage: scripts/check-retired-terms.sh [--root <dir>]
# Exit 0 clean; exit 1 with one file:line per hit.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root=$2; shift 2 ;;
    -h|--help) grep '^#' "$0" | head -30; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
cd "$root"
retired="GOAL.md GRAPH.md EXPERIMENT.md"
scope="skills src bin scripts extensions .pi/skills .agents/skills .claude/skills .agents/workflows"
hits=$(mktemp)
trap 'rm -f "$hits"' EXIT
# Tracked files only; untracked run residue is not a live surface.
for term in $retired; do
  for f in AGENTS.md CLAUDE.md README.md; do
    [ -f "$f" ] && grep -n -F "$term" "$f" >> "$hits" || true
  done
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git grep -n -F "$term" -- $scope >> "$hits" || true
  else
    grep -rn -F "$term" $scope >> "$hits" 2>/dev/null || true
  fi
done
# Apply per-path fossil exemptions.
filtered=$(mktemp)
trap 'rm -f "$hits" "$filtered"' EXIT
while IFS= read -r line; do
  path=${line%%:*}
  case "$path" in
    scripts/migrate-graph-rename.sh|scripts/check-retired-terms.sh) continue ;;
  esac
  printf '%s\n' "$line" >> "$filtered"
done < "$hits"
if [ -s "$filtered" ]; then
  echo "retired-term sweep: FAIL (retired spellings on live surfaces)" >&2
  cat "$filtered" >&2
  exit 1
fi
echo "retired-term sweep: ok"
