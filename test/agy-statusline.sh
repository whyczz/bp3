#!/usr/bin/env bash
# Fixture tests for scripts/agy-statusline.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo/scripts/agy-statusline"
checks=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local hay="$1" needle="$2" label="$3"
  checks=$((checks + 1))
  printf '%s' "$hay" | grep -qF -- "$needle" || fail "$label: expected '$needle' in '$hay'"
}

work="$(mktemp -d "${TMPDIR:-/tmp}/bp3-agy-statusline.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

# 1. --help exits 0
out="$("$script" --help)"
assert_contains "$out" "agy-statusline" "help docstring"

# 2. Active quest fixture: progress bar, active node, wall time, context token usage
proj="$work/repo"
mkdir -p "$proj/docs/quests/demo-q" "$proj/plans" "$proj/bin" "$proj/src/quest"
cp "$repo/plans/default.yaml" "$proj/plans/default.yaml"
cp "$repo/bin/bp3" "$proj/bin/bp3"
chmod +x "$proj/bin/bp3"
mkdir -p "$proj/_build/default/src/quest"
cp "$repo/_build/default/src/quest/main.exe" "$proj/_build/default/src/quest/main.exe"
git -C "$proj" init -q
git -C "$proj" config user.email test@bp3
git -C "$proj" config user.name test
printf -- '---\nstatus: active\n---\n# demo-q\n' > "$proj/docs/quests/demo-q/QUEST.md"
touch "$proj/src/quest/main.ml"
git -C "$proj" add -A && git -C "$proj" commit -qm init

(cd "$proj" && ./bin/bp3 q c demo-q >/dev/null)
(cd "$proj" && ./bin/bp3 q demo-q c node-1-first >/dev/null)
(cd "$proj" && ./bin/bp3 q demo-q c node-2-second >/dev/null)
sha="$(git -C "$proj" rev-parse HEAD)"
(cd "$proj" && ./bin/bp3 q demo-q n node-1-first e handoff --commit "$sha" --reason "ok" >/dev/null)
(cd "$proj" && ./bin/bp3 q demo-q n node-1-first e grade --verdict ship --verify-verdict pass --reason "ok" >/dev/null)
(cd "$proj" && ./bin/bp3 q demo-q n node-1-first e land --reason "ok" >/dev/null)
(cd "$proj" && ./bin/bp3 q demo-q n node-2-second e handoff --commit "$sha" --reason "wip" >/dev/null)

payload="$(printf '{"cwd":"%s","context_window":{"context_window_size":1048576,"used_percentage":25.0,"total_input_tokens":200000,"total_output_tokens":60000}}' "$proj")"
out="$(printf '%s' "$payload" | NO_COLOR=1 "$script")"
assert_contains "$out" "bp3: demo-q" "quest name"
assert_contains "$out" "[████░░░░] 1/2 (50%)" "progress bar and pct"
assert_contains "$out" "2-second (handed_off c1)" "active node and state"
assert_contains "$out" "ctx 262k/1.0M (25%)" "context token usage"

# 3. Red-ink working copy takes precedence over active/landed QUEST.md
touch "$proj/docs/quests/demo-q/QUEST.red-ink.md"
out="$(printf '%s' "$payload" | NO_COLOR=1 "$script")"
assert_contains "$out" "bp3: demo-q [red-ink]" "red-ink mode"
assert_contains "$out" "ctx 262k/1.0M (25%)" "context tokens in red-ink mode"
rm -f "$proj/docs/quests/demo-q/QUEST.red-ink.md"

# 4. Idle bp3 repo (no active quest) still prints context tokens and exits 0
printf -- '---\nstatus: landed\n---\n# demo-q\n' > "$proj/docs/quests/demo-q/QUEST.md"
out="$(printf '%s' "$payload" | NO_COLOR=1 "$script")"
assert_contains "$out" "bp3: idle" "idle state"
assert_contains "$out" "ctx 262k/1.0M (25%)" "context tokens in idle state"

# 4. Non-bp3 directory prints context tokens only and exits 0
nonbp3="$work/plain"
mkdir -p "$nonbp3"
payload2="$(printf '{"cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":88.0}}' "$nonbp3")"
out="$(printf '%s' "$payload2" | NO_COLOR=1 "$script")"
assert_contains "$out" "ctx 880k/1.0M (88%)" "non-bp3 ctx only"

# 5. Malformed stdin fails open (exit 0)
printf '{broken' | NO_COLOR=1 "$script" >/dev/null
checks=$((checks + 1))

echo "agy-statusline tests: ok ($checks assertions)"
