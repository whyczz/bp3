#!/bin/bash
# check-retired-terms — retired-term sweep for the fast tier
# (node-followup-6-check-tiers). Greps live surfaces for the
# repo's retired spellings before any suite runs, so a stale
# term costs seconds, not a grade cycle.
#
# Retired spellings (single source; post-rename vocabulary):
#   GOAL.md GRAPH.md EXPERIMENT.md   (now QUEST.md / NODE.md)
#   bp3g (skill family, now induct / quest / induct-yolo / trial)
#   docs/graphs (now docs/quests)
#
# Live surfaces swept: skills/, src/, bin/, scripts/,
# extensions/, the rendered skill copies (.pi/skills/,
# .agents/skills/, .claude/skills/, .agents/workflows/),
# and the root docs AGENTS.md / CLAUDE.md / README.md, matched in
# any case (this repo tracks readme.md).
# Out of scope by definition: docs/ (frozen records — ledger
# lines, dated amendments, run notes quote history) and
# test/ (fixtures quote retired spellings as data).
#
# Fossil exemptions, one row per path, each with its reason.
# No blanket per-file exemption for live files.
#   scripts/migrate-graph-rename.sh | migration rename table:
#     quotes the retired spellings in order to rename them
#   src/quest/layout.ml             | declares legacy spellings it folds on read
#   bin/bp3 RETIRED_WORKFLOWS= line | names the retired renders it prunes
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
retired="GOAL.md GRAPH.md EXPERIMENT.md bp3g docs/graphs"
scope="skills src bin scripts extensions .pi/skills .agents/skills .claude/skills .agents/workflows"
hits=$(mktemp)
trap 'rm -f "$hits"' EXIT
# Root docs by their real spelling: find -iname, because a
# case-exact name skips readme.md on Linux and macOS hides the gap.
root_docs=$(for d in AGENTS.md CLAUDE.md README.md; do
  find . -maxdepth 1 -type f -iname "$d"; done | sed 's|^\./||')
# Tracked files only; untracked run residue is not a live surface.
for term in $retired; do
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git grep -n -F "$term" -- $scope $root_docs >> "$hits" || true
  else
    grep -rHn -F "$term" $scope $root_docs >> "$hits" 2>/dev/null || true
  fi
done
# Apply per-path fossil exemptions.
filtered=$(mktemp)
trap 'rm -f "$hits" "$filtered"' EXIT
while IFS= read -r line; do
  path=${line%%:*}
  case "$path" in
    scripts/migrate-graph-rename.sh|scripts/check-retired-terms.sh|src/quest/layout.ml) continue ;;
  esac
  # bin/bp3 declares the retired workflow names it prunes; that one
  # line only, never the whole live file.
  case "$line" in bin/bp3:*:RETIRED_WORKFLOWS=*) continue ;; esac
  printf '%s\n' "$line" >> "$filtered"
done < "$hits"
if [ -s "$filtered" ]; then
  echo "retired-term sweep: FAIL (retired spellings on live surfaces)" >&2
  cat "$filtered" >&2
  exit 1
fi
echo "retired-term sweep: ok"
