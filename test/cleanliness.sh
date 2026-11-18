#!/usr/bin/env bash
# Cleanliness fixture (followup.3 cycle 3): runtime residue
# (.bp3-context.json, run tape.log) never dirties the tree;
# authored evidence (notes.md) stays deliberate.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
cp "$root/.gitignore" .gitignore
echo base > a.txt; git add .; git commit -qm base
fail() { echo "FAIL: $*" >&2; exit 1; }

runs_dir="docs/graphs/demo/nodes/parser-fix/runs/run-1"
mkdir -p "$runs_dir"
printf '%s\n' '{"run_id":"run-1"}' > .bp3-context.json
printf '%s\n' 'tape line' > "$runs_dir/tape.log"
[ -z "$(git status --porcelain)" ] || fail "residue dirtied the tree: $(git status --porcelain)"

# A workflow step appends to the tape and regenerates the
# desk context; the tree must stay clean.
printf '%s\n' 'bind-tape append' >> "$runs_dir/tape.log"
printf '%s\n' '{"run_id":"run-1","desk":"desk"}' > .bp3-context.json
[ -z "$(git status --porcelain)" ] || fail "step residue dirtied the tree: $(git status --porcelain)"

git check-ignore -q .bp3-context.json || fail ".bp3-context.json is not ignored"
git check-ignore -q "$runs_dir/tape.log" || fail "run tape.log is not ignored"
if git check-ignore -q "$runs_dir/notes.md"; then fail "notes.md must stay deliberate, not ignored"; fi
printf '%s\n' 'authored lessons' > "$runs_dir/notes.md"
git status --porcelain --untracked-files=all | grep -q 'notes.md' || fail "notes.md is invisible; evidence must be deliberate"

echo "cleanliness tests: ok"
