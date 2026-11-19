#!/bin/bash
# migrate-quest-rename — quest rename-back (2026-11-18), done
# mechanically. Renames, on every quest in this repo:
#   docs/graphs/<q>/GRAPH.md          -> docs/quests/<q>/QUEST.md
#   docs/graphs/<q>/...               -> docs/quests/<q>/...
#   refs      bp3/graph/<q>           -> bp3/quest/<q>
#             graph/<q>               -> quest/<q>      (work branches)
# Links in authored .md files are re-pointed in the same change.
# Ledgers and runs/ are never edited, and storage-branch trees are
# never rewritten: the engine folds every historical layout on read
# (src/quest/layout.ml, legacy roots and node folders).
# Usage: migrate-quest-rename.sh [--dry-run|--apply]
#   --dry-run (default) prints the plan, changes nothing.
#   --apply refuses on a dirty tree; every step is existence-
#   checked, so a second run is a no-op (idempotent).
set -euo pipefail
mode=dry-run
for arg in "$@"; do
  case "$arg" in
    --dry-run) mode=dry-run ;;
    --apply) mode=apply ;;
    -h|--help) grep '^#' "$0" | head -15; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done
root=$(git rev-parse --show-toplevel)
cd "$root"
plan() { printf 'plan: %s\n' "$*"; }
run() { if [ "$mode" = apply ]; then printf 'do: %s\n' "$*"; "$@"; else plan "$*"; fi; }
if [ "$mode" = apply ] && git status --porcelain | grep -v '^??' | grep -q .; then
  echo "refuse: dirty tree (commit or stash tracked changes first)" >&2; exit 1
fi

# --- file moves --------------------------------------------------
shopt -s nullglob
for qdir in docs/graphs/*/; do
  q=$(basename "$qdir")
  if [ -e "docs/quests/$q" ]; then plan "skip docs/graphs/$q (docs/quests/$q exists)"; continue; fi
  run mkdir -p docs/quests
  run git mv "docs/graphs/$q" "docs/quests/$q"
  if [ "$mode" = apply ]; then
    [ -f "docs/quests/$q/GRAPH.md" ] && run git mv "docs/quests/$q/GRAPH.md" "docs/quests/$q/QUEST.md"
  else
    plan "git mv docs/quests/$q/GRAPH.md docs/quests/$q/QUEST.md (when present)"
  fi
done
if [ "$mode" = apply ]; then rmdir docs/graphs 2>/dev/null || true; fi

# --- link re-pointing (authored .md only; never ledger or runs) ----
if [ "$mode" = apply ]; then
  git ls-files -- 'docs/*.md' '*.md' | grep -v '/runs/' | grep -v 'ledger\.jsonl' \
    | grep -v 'migrate-' | while read -r f; do
      [ -f "$f" ] || continue
      if grep -q 'docs/graphs/\|GRAPH\.md' "$f"; then
        perl -pi -e 's#docs/graphs/#docs/quests/#g; s#\bGRAPH\.md\b#QUEST.md#g' "$f"
        echo "do: re-point $f"
      fi
    done
  git add -A docs
else
  plan "re-point docs/graphs/ -> docs/quests/, GRAPH.md -> QUEST.md in tracked .md outside runs/"
fi

# --- ref renames (tips preserved) ----------------------------------
rename_ref() {
  local old="$1" new="$2" tip
  tip=$(git rev-parse -q --verify "refs/heads/$old" || true)
  [ -z "$tip" ] && return 0
  if git rev-parse -q --verify "refs/heads/$new" >/dev/null; then
    plan "skip $old -> $new (target exists)"; return 0
  fi
  plan "branch $old -> $new (tip $tip kept)"
  if [ "$mode" = apply ]; then
    git update-ref "refs/heads/$new" "$tip" ""
    git update-ref -d "refs/heads/$old" "$tip"
    [ "$(git rev-parse "refs/heads/$new")" = "$tip" ] || { echo "tip lost: $new" >&2; exit 1; }
  fi
}
git for-each-ref --format='%(refname:strip=2)' refs/heads/bp3/graph/ | while read -r b; do
  rename_ref "$b" "bp3/quest/${b#bp3/graph/}"
done
cur=$(git branch --show-current)
git for-each-ref --format='%(refname:strip=2)' refs/heads/graph/ | while read -r b; do
  q="${b#graph/}"
  if [ "$b" = "$cur" ]; then
    if [ "$mode" = apply ]; then git branch -m "$b" "quest/$q"; fi
    plan "branch $b -> quest/$q (checked out, -m)"
  else
    rename_ref "$b" "quest/$q"
  fi
done
echo "migrate-quest-rename: $mode complete (idempotent: re-run is a no-op)"
