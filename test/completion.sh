#!/usr/bin/env bash
# Tab completion fixture: static lists pin against src/graph/main.ml,
# scripted candidate traces (bash and zsh), silent failure, delivery.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- static lists: every spelling in the scripts exists in main.ml ---
main_ml="$root/src/graph/main.ml"
for shell_file in "$root/completions/_bp3" "$root/completions/bp3.bash"; do
  [ -f "$shell_file" ] || fail "missing completion script: $shell_file"
  flags=$(sed -n 's/^_bp3_flags=//p' "$shell_file" | tr -d "()'" | tr ' ' '\n' | sed '/^$/d')
  for flag in $flags; do
    grep -q -- "\"$flag\"" "$main_ml" || fail "flag $flag in $shell_file not in main.ml"
  done
  # Reverse: every flag main.ml parses is completed.
  for flag in $(sed -n '/^let parse_flags/,/^let split_flags/p' "$main_ml" | grep -o '"--[a-z-]*"' | tr -d '"' | sort -u); do
    echo "$flags" | grep -qx -- "$flag" || fail "flag $flag in main.ml not in $shell_file"
  done
  edges=$(sed -n 's/^_bp3_edges=//p' "$shell_file" | tr -d "()'" | tr ' ' '\n' | sed '/^$/d')
  for edge in $edges; do
    grep -q "\"$edge\"" "$main_ml" || fail "edge $edge in $shell_file not in main.ml"
  done
  for edge in handoff grade verify land block resume; do
    echo "$edges" | grep -qx -- "$edge" || fail "edge $edge in main.ml not in $shell_file"
  done
  for verb in c create r read u update d delete; do
    grep -qw -- "$verb" "$shell_file" || fail "verb $verb not in $shell_file"
    grep -q "\"$verb\"" "$main_ml" || fail "verb $verb not in main.ml"
  done
done
grep -q '#compdef bp3' "$root/completions/_bp3" || fail "zsh script lacks #compdef bp3"
grep -q 'compadd' "$root/completions/_bp3" || fail "zsh script lacks compadd"
grep -q 'complete -F _bp3 bp3' "$root/completions/bp3.bash" || fail "bash script lacks complete -F _bp3 bp3"

# --- scratch repo with live graphs/nodes ---
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/graph/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
export BP3_G_BIN="$work/repo/g-bin"
export BP3_COMPLETION_BP3="$work/repo/bin/bp3"
q() { BP3_G_BIN="$work/repo/g-bin" ./bin/bp3 g "$@"; }
q c toy-drive >/dev/null
q c demo >/dev/null
q toy-drive c parser-fix >/dev/null
q toy-drive c skill-probe >/dev/null

has() { # has <candidates> <word>
  echo "$1" | grep -qx -- "$2" || fail "candidates [$1] missing $2"
}
lacks() {
  if echo "$1" | grep -qx -- "$2"; then fail "candidates [$1] unexpectedly has $2"; fi
}

# --- bash traces ---
# shellcheck disable=SC1091
source "$root/completions/bp3.bash"
out=$(_bp3_candidates g "toy-")
has "$out" toy-drive; lacks "$out" demo
out=$(_bp3_candidates g "")
has "$out" toy-drive; has "$out" demo; lacks "$out" r
out=$(_bp3_candidates g r "")
has "$out" toy-drive
out=$(_bp3_candidates g toy-drive r "")
has "$out" parser-fix; has "$out" skill-probe
out=$(_bp3_candidates g toy-drive r "parser-")
has "$out" parser-fix; lacks "$out" skill-probe
out=$(_bp3_candidates g toy-drive u parser-fix "")
for edge in handoff grade verify land block resume; do has "$out" "$edge"; done
out=$(_bp3_candidates g toy-drive r parser-fix "--f")
has "$out" --format; lacks "$out" --reason
out=$(_bp3_candidates g toy-drive r parser-fix --format "")
has "$out" json; has "$out" table; has "$out" tree
out=$(_bp3_candidates g toy-drive "")
has "$out" r; has "$out" u
out=$(_bp3_candidates "")
has "$out" harness; has "$out" worktree; has "$out" config
out=$(_bp3_candidates config "")
has "$out" --source; has "$out" --format
out=$(_bp3_candidates harness "")
has "$out" desk; has "$out" supervisor; has "$out" find-tape
out=$(_bp3_candidates harness desk "")
for v in derive create inspect remove prepare check exit release list; do has "$out" "$v"; done
out=$(_bp3_candidates harness d "")
has "$out" prepare; has "$out" release

# --- zsh traces (same candidate logic) ---
if command -v zsh >/dev/null 2>&1; then
  zcand() { zsh -c 'source "$1"; shift; _bp3_candidates "$@"' _ "$root/completions/_bp3" "$@"; }
  out=$(zcand g "toy-")
  has "$out" toy-drive; lacks "$out" demo
  out=$(zcand g toy-drive r "")
  has "$out" parser-fix; has "$out" skill-probe
  out=$(zcand g toy-drive u parser-fix "")
  for edge in handoff grade verify land block resume; do has "$out" "$edge"; done
  out=$(zcand g toy-drive r parser-fix "--f")
  has "$out" --format
fi

# --- silent failure: unbuilt binary / non-bp3 cwd says nothing ---
mkdir -p "$work/nowhere"
cd "$work/nowhere"
err="$work/err.txt"
out=$(BP3_COMPLETION_BP3="$work/no-such-bp3" _bp3_candidates g "" 2>"$err")
[ -z "$out" ] || fail "silent failure produced candidates: $out"
[ ! -s "$err" ] || fail "silent failure made noise: $(cat "$err")"
if command -v zsh >/dev/null 2>&1; then
  out=$(BP3_COMPLETION_BP3="$work/no-such-bp3" zsh -c 'source "$1"; shift; _bp3_candidates "$@"' _ "$root/completions/_bp3" g "" 2>"$err")
  [ -z "$out" ] || fail "zsh silent failure produced candidates: $out"
  [ ! -s "$err" ] || fail "zsh silent failure made noise: $(cat "$err")"
fi

# --- delivery: bp3 init copies _bp3, edits no rc file ---
mkdir -p "$work/delivery" "$work/dest" "$work/home"
cp -R "$root/bin" "$root/completions" "$root/skills" "$root/scripts" "$work/delivery/"
out=$(HOME="$work/home" BP3_COMPLETIONS_DIR="$work/dest" "$work/delivery/bin/bp3" init --harness=muse)
echo "$out" | grep -q "installed _bp3 -> $work/dest/_bp3" || fail "delivery did not install _bp3: $out"
cmp "$root/completions/_bp3" "$work/dest/_bp3" || fail "delivered _bp3 differs from source"
[ ! -e "$work/home/.zshrc" ] || fail "delivery edited .zshrc"
[ ! -e "$work/home/.bashrc" ] || fail "delivery edited .bashrc"

echo "completion tests: ok"
