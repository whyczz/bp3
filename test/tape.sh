#!/usr/bin/env bash
# Exp 4 fixtures: tape capture is verbatim evidence, never parsed
# into facts. The ledger gains lines only through `bp3 q u`.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/invoke/main.exe" "$work/repo/q-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

q c demo >/dev/null
q demo c parser-fix >/dev/null
exp_ledger() { git show "bp3/exp/demo/parser-fix:docs/quests/demo/experiments/parser-fix/ledger.jsonl"; }
runs_dir="docs/quests/demo/experiments/parser-fix/runs"

# (a) executor killed mid-output: tape keeps partial content.
mkdir -p "$runs_dir/killed-run"
slow="$work/slow.sh"
# shellcheck disable=SC2016 # Literal loop body written to the slow fixture.
printf '%s\n' '#!/usr/bin/env bash' 'for i in $(seq 1 100); do echo "tape-line-$i"; sleep 0.05; done' > "$slow"
chmod +x "$slow"
bash "$slow" > >(tee "$runs_dir/killed-run/tape.log" >/dev/null) 2>&1 &
producer=$!
sleep 0.4
kill "$producer" 2>/dev/null || true
wait "$producer" 2>/dev/null || true
sleep 0.3
[ -s "$runs_dir/killed-run/tape.log" ] || fail "killed run left an empty tape"
grep -q '^tape-line-1$' "$runs_dir/killed-run/tape.log" || fail "killed tape lost its first line"
if grep -q '^tape-line-100$' "$runs_dir/killed-run/tape.log"; then fail "killed tape claims complete output"; fi

# (b) hooks disabled: a tape-only run completes, ledger untouched.
before=$(exp_ledger)
mkdir -p "$runs_dir/hooks-off-run"
echo "hooks-off output" | tee "$runs_dir/hooks-off-run/tape.log" >/dev/null
[ -s "$runs_dir/hooks-off-run/tape.log" ] || fail "hooks-off run left no tape"
grep -q 'hooks-off output' "$runs_dir/hooks-off-run/tape.log" || fail "hooks-off tape lost output"
after=$(exp_ledger)
[ "$before" = "$after" ] || fail "tape-only run changed the ledger"

# (c) edges through bp3 q u: no tape-only string reaches the ledger.
marker="tape-only-marker-9f27c1"
mkdir -p "$runs_dir/submit-run"
printf 'session start %s\n' "$marker" | tee "$runs_dir/submit-run/tape.log" >/dev/null
grep -q "$marker" "$runs_dir/submit-run/tape.log" || fail "marker missing from tape"
echo work > b.txt
printf '%s\n' "$runs_dir/" > .gitignore
git add b.txt .gitignore; git commit -qm work
B=$(git rev-parse HEAD)
q demo u parser-fix submit --commit "$B" --reason "first cut" >/dev/null
q demo u parser-fix review --verdict ship --reason "looks right" >/dev/null
q demo u parser-fix check --verdict pass --reason "green" >/dev/null
q demo u parser-fix land --reason "ship it" >/dev/null
lines=$(exp_ledger | wc -l | tr -d ' ')
[ "$lines" -ge 5 ] || fail "expected submit/review/check/land ledger lines, got $lines"
if exp_ledger | grep -q "$marker"; then fail "ledger contains a string that appears only in the tape"; fi
if exp_ledger | grep -q 'hooks-off output'; then fail "ledger contains hooks-off tape text"; fi

echo "tape tests: ok"
