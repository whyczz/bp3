#!/bin/bash
# migrate-graph-rename — followup.3 scope-C rename, done mechanically.
# Renames, on every graph in this repo:
#   docs/goals/<g>/GOAL.md            -> docs/graphs/<g>/GRAPH.md
#   docs/goals/<g>/experiments/<e>/EXPERIMENT.md
#                                     -> docs/graphs/<g>/nodes/<node-e>/NODE.md
#   node ids  exp-<m>-<n>-<slug>      -> node-<m>-<n>-<slug>
#   refs      bp3/goal/<g>            -> bp3/graph/<g>   (bp3/quest/<g> too)
#             bp3/exp/<g>/<e>         -> bp3/node/<g>/<node-e>
#             quest/<g>, goal/<g>     -> graph/<g>      (work branches)
# References in live surfaces are re-pointed in the same change.
# Landed ledger lines are never edited (ledger.jsonl moves as-is;
# the engine fold in src/graph/store.ml maps old ids on read).
# Usage: migrate-graph-rename.sh [--dry-run|--apply] [graph]
#   --dry-run (default) prints the full plan, changes nothing.
#   --apply refuses on a dirty tree; every step is existence-
#   checked, so a second run is a no-op (idempotent).
set -euo pipefail
mode=dry-run
only_graph=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) mode=dry-run ;;
    --apply) mode=apply ;;
    -h|--help) grep '^#' "$0" | head -20; exit 0 ;;
    *) only_graph="$arg" ;;
  esac
done
root=$(git rev-parse --show-toplevel)
cd "$root"
canon_id() { case "$1" in exp-*) echo "node-${1#exp-}" ;; *) echo "$1" ;; esac; }
plan() { printf 'plan: %s\n' "$*"; }
run() { if [ "$mode" = apply ]; then printf 'do: %s\n' "$*"; "$@"; else plan "$*"; fi; }
if [ "$mode" = apply ] && git status --porcelain | grep -v '^??' | grep -v '/runs/' | grep -q .; then
  echo "refuse: dirty tree (tracked source changes present; run evidence under runs/ moves along)" >&2; exit 1
fi
# --- file moves -------------------------------------------------
shopt -s nullglob
for gdir in docs/goals/*/; do
  g=$(basename "$gdir")
  [ -n "$only_graph" ] && [ "$g" != "$only_graph" ] && continue
  [ -f "$gdir/GOAL.md" ] && run git mv "$gdir/GOAL.md" "$gdir/GRAPH.md"
  for edir in "$gdir"experiments/*/; do
    e=$(basename "$edir"); ne=$(canon_id "$e")
    [ -f "$edir/EXPERIMENT.md" ] && run git mv "$edir/EXPERIMENT.md" "$edir/NODE.md"
    if [ "$mode" = apply ]; then
      mkdir -p "$gdir/nodes"; git mv "$edir" "$gdir/nodes/$ne/" 2>/dev/null || mv "$edir" "$gdir/nodes/$ne/"
      # untracked run residue rides along with its node folder
      [ -d "$edir" ] && mv "$edir"/* "$gdir/nodes/$ne/" && rmdir "$edir" || true
    else
      plan "git mv $edir ${gdir}nodes/$ne/ (+ untracked residue)"
    fi
  done
  if [ -d "$gdir/experiments" ]; then
    if [ "$mode" = apply ]; then rmdir "$gdir/experiments" 2>/dev/null || true
    else plan "rmdir ${gdir}experiments (when empty)"; fi
  fi
  if [ "$mode" = apply ]; then
    mkdir -p docs/graphs; git mv "$gdir" "docs/graphs/$g/" 2>/dev/null || mv "$gdir" "docs/graphs/$g/"
    [ -d "$gdir" ] && mv "$gdir"/* "docs/graphs/$g/" && rmdir "$gdir" || true
  else
    plan "git mv $gdir docs/graphs/$g/ (+ untracked residue)"
  fi
done
# --- reference re-pointing (live surfaces; never ledger/runs) ---
repoint() {
  local f="$1"
  sed -i.bak \
    -e 's|docs/goals/|docs/graphs/|g' \
    -e 's|/GOAL\.md|/GRAPH.md|g' -e 's|/EXPERIMENT\.md|/NODE.md|g' \
    -e 's|/experiments/|/nodes/|g' \
    -e 's|exp-\(mig\|mvp\|config\|dogfood\|followup\|landing\|rename\)-\([0-9]\)|node-\1-\2|g' \
    "$f" && rm -f "$f.bak"
}
export -f repoint 2>/dev/null || true
if [ "$mode" = apply ]; then
  git ls-files -- '*.md' '*.ml' '*.sh' '*.js' '*.mjs' '*.json' '*.bash' \
    | grep -v 'ledger\.jsonl' | grep -v '/runs/' | grep -v 'migrate-graph-rename' | while read -r f; do
      [ -f "$f" ] && repoint "$f"; done
  git add -A
else
  plan "sed re-point: docs/goals/->docs/graphs/, GOAL.md->GRAPH.md, EXPERIMENT.md->NODE.md, /experiments/->/nodes/, exp-<m>-<n>->node-<m>-<n> on live .md/.ml/.sh (ledger.jsonl and runs/ excluded)"
fi
# --- branch renames (tips preserved) ----------------------------
rename_ref() {
  local old="$1" new="$2" tip
  tip=$(git rev-parse -q --verify "refs/heads/$old" || true)
  [ -z "$tip" ] && return 0
  if git rev-parse -q --verify "refs/heads/$new" >/dev/null; then
    plan "skip $old -> $new (target exists)"; return 0
  fi
  plan "branch $old -> $new (tip $tip kept)"
  if [ "$mode" = apply ]; then
    git update-ref "refs/heads/$new" "$tip"
    git update-ref -d "refs/heads/$old"
    [ "$(git rev-parse "refs/heads/$new")" = "$tip" ] || { echo "tip lost: $new" >&2; exit 1; }
  fi
}
git for-each-ref --format='%(refname:strip=2)' refs/heads/bp3/goal/ refs/heads/bp3/quest/ | while read -r b; do
  g="${b#bp3/goal/}"; g="${g#bp3/quest/}"
  [ -n "$only_graph" ] && [ "$g" != "$only_graph" ] && continue
  rename_ref "$b" "bp3/graph/$g"
done
git for-each-ref --format='%(refname:strip=2)' refs/heads/bp3/exp/ | while read -r b; do
  rest="${b#bp3/exp/}"; g="${rest%%/*}"; e="${rest#*/}"
  [ -n "$only_graph" ] && [ "$g" != "$only_graph" ] && continue
  rename_ref "$b" "bp3/node/$g/$(canon_id "$e")"
done
git for-each-ref --format='%(refname:strip=2)' refs/heads/quest/ refs/heads/goal/ | while read -r b; do
  g="${b#quest/}"; g="${g#goal/}"
  case "$g" in */*) continue ;; esac
  [ -n "$only_graph" ] && [ "$g" != "$only_graph" ] && continue
  cur=$(git branch --show-current)
  if [ "$b" = "$cur" ] && [ "$mode" = apply ]; then git branch -m "$b" "graph/$g"; plan "branch $b -> graph/$g (checked out, -m)"
  else rename_ref "$b" "graph/$g"; fi
done
echo "migrate-graph-rename: $mode complete (idempotent: re-run is a no-op)"
