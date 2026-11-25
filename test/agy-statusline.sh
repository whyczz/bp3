#!/usr/bin/env bash
# Fixture tests for scripts/agy-statusline.
set -euo pipefail
unset AGY_CONVERSATION_ID CLAUDE_SESSION_ID

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

# 3b. Multiple active quests on one branch emits WARN
mkdir -p "$proj/docs/quests/second-q"
printf -- '---\nstatus: active\n---\n# second-q\n' > "$proj/docs/quests/second-q/QUEST.md"
out="$(printf '%s' "$payload" | NO_COLOR=1 "$script")"
assert_contains "$out" "WARN: 2 active quests" "multi-active warning"
rm -rf "$proj/docs/quests/second-q"

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

# --- session-scoped-statusline session.2: parallel session isolation & anti-hijack ---
mkdir -p "$proj/docs/quests/q-alpha" "$proj/docs/quests/q-beta" "$proj/docs/quests/stale-q"
printf -- '---\nstatus: proposed\n---\n# q-alpha\n' > "$proj/docs/quests/q-alpha/QUEST.md"
printf -- '---\nstatus: proposed\n---\n# q-beta\n' > "$proj/docs/quests/q-beta/QUEST.md"
printf -- '---\nstatus: proposed\n---\n# stale-q\n' > "$proj/docs/quests/stale-q/QUEST.md"
git -C "$proj" add -A && git -C "$proj" commit -qm "add parallel quest fixtures"
sha2="$(git -C "$proj" rev-parse HEAD)"

(cd "$proj" && ./bin/bp3 q c q-alpha >/dev/null)
(cd "$proj" && ./bin/bp3 q q-alpha c node-1-first >/dev/null)
(cd "$proj" && ./bin/bp3 q q-alpha c node-2-second >/dev/null)
(cd "$proj" && ./bin/bp3 q q-alpha n node-1-first e handoff --commit "$sha2" --reason "ok" >/dev/null)
(cd "$proj" && ./bin/bp3 q q-alpha n node-1-first e grade --verdict ship --verify-verdict pass --reason "ok" >/dev/null)
(cd "$proj" && ./bin/bp3 q q-alpha n node-1-first e land --reason "ok" >/dev/null)
(cd "$proj" && ./bin/bp3 q q-alpha n node-2-second e handoff --commit "$sha2" --reason "wip" >/dev/null)

touch "$proj/docs/quests/q-beta/QUEST.red-ink.md"
# Plant an abandoned QUEST.2b-reviewed.md that used to hijack every terminal
touch "$proj/docs/quests/stale-q/QUEST.2b-reviewed.md"

sess_dir="$(cd "$proj" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/bp3/sessions"
mkdir -p "$sess_dir"
printf '{"session_id":"sess-A","quest":"q-alpha","mode":"induct","desk":null,"red_ink_path":null,"updated_ts":1795640000}\n' > "$sess_dir/sess-A.json"
printf '{"session_id":"sess-B","quest":"q-beta","mode":"red-ink","desk":null,"red_ink_path":"docs/quests/q-beta/QUEST.red-ink.md","updated_ts":1795640000}\n' > "$sess_dir/sess-B.json"

# 6a. Parallel sessions sess-A (session_id) and sess-B (conversationId) show distinct quests simultaneously
pay_a="$(printf '{"session_id":"sess-A","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj")"
out_a="$(printf '%s' "$pay_a" | NO_COLOR=1 "$script")"
assert_contains "$out_a" "bp3: q-alpha [████░░░░] 1/2 (50%)" "sess-A induct progress"
assert_contains "$out_a" "2-second (handed_off c1)" "sess-A active node"
assert_contains "$out_a" "ctx 200k/1.0M (20%)" "sess-A ctx"

pay_b="$(printf '{"conversationId":"sess-B","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj")"
out_b="$(printf '%s' "$pay_b" | NO_COLOR=1 "$script")"
assert_contains "$out_b" "bp3: q-beta [red-ink]" "sess-B red-ink mode"
assert_contains "$out_b" "ctx 200k/1.0M (20%)" "sess-B ctx"

# 6b. Unbound session sess-C shows bp3: idle even with stale-q/QUEST.2b-reviewed.md on disk
pay_c="$(printf '{"session_id":"sess-C","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj")"
out_c="$(printf '%s' "$pay_c" | NO_COLOR=1 "$script")"
assert_contains "$out_c" "bp3: idle" "unbound sess-C not hijacked by stale 2b-reviewed"
assert_contains "$out_c" "ctx 200k/1.0M (20%)" "unbound sess-C ctx"

# 6b2. Malformed session_id (../evil) fails safe to bp3: idle (never falls back to global red-ink glob)
pay_bad="$(printf '{"session_id":"../evil","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj")"
out_bad="$(printf '%s' "$pay_bad" | NO_COLOR=1 "$script")"
assert_contains "$out_bad" "bp3: idle" "invalid session_id fails safe to idle"

# 6c. Deleting q-beta/QUEST.red-ink.md immediately unfreezes sess-B -> bp3: idle
rm -f "$proj/docs/quests/q-beta/QUEST.red-ink.md"
out_b2="$(printf '%s' "$pay_b" | NO_COLOR=1 "$script")"
assert_contains "$out_b2" "bp3: idle" "sess-B drops red-ink when working copy removed"

# 6d. transcript_path fallback extracts session ID when session_id / conversation_id omitted
pay_tx="$(printf '{"transcript_path":"/Users/test/.gemini/antigravity-cli/brain/sess-A/.system_generated/logs/transcript.jsonl","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj")"
out_tx="$(printf '%s' "$pay_tx" | NO_COLOR=1 "$script")"
assert_contains "$out_tx" "bp3: q-alpha [████░░░░] 1/2 (50%)" "transcript_path fallback resolves sess-A"

# 6e. Promoted/landed bound quest drops session to bp3: idle
printf -- '---\nstatus: landed\n---\n# q-alpha\n' > "$proj/docs/quests/q-alpha/QUEST.md"
out_a_landed="$(printf '%s' "$pay_a" | NO_COLOR=1 "$script")"
assert_contains "$out_a_landed" "bp3: idle" "landed bound quest drops to idle"
printf -- '---\nstatus: proposed\n---\n# q-alpha\n' > "$proj/docs/quests/q-alpha/QUEST.md"

# 6f. Worktree on quest/<slug> branch falls back to quest/<slug> for an unbound session
wt_q="$work/wt-q-alpha"
git -C "$proj" worktree add -q -b quest/q-alpha "$wt_q"
pay_wt="$(printf '{"session_id":"sess-wt-unbound","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$wt_q")"
out_wt="$(printf '%s' "$pay_wt" | NO_COLOR=1 "$script")"
assert_contains "$out_wt" "bp3: q-alpha [████░░░░] 1/2 (50%)" "quest/<slug> worktree fallback for unbound session"
git -C "$proj" worktree remove --force "$wt_q"

# 6g. Host repo (no $host/bin/bp3, installed bp3 + bp3-q on PATH) resolves session binding cleanly
host="$work/host-repo"
mkdir -p "$host/docs/quests/host-q" "$host/plans" "$work/bin"
cp "$repo/bin/bp3" "$work/bin/bp3"
cp "$repo/_build/default/src/quest/main.exe" "$work/bin/bp3-q"
cp "$repo/plans/default.yaml" "$host/plans/default.yaml"
chmod +x "$work/bin/bp3" "$work/bin/bp3-q"
git -C "$host" init -q -b master
git -C "$host" config user.email test@bp3
git -C "$host" config user.name test
printf -- '---\nstatus: proposed\n---\n# host-q\n' > "$host/docs/quests/host-q/QUEST.md"
git -C "$host" add -A && git -C "$host" commit -qm init
(cd "$host" && env -u BP3_Q_BIN PATH="$work/bin:$PATH" bp3 q c host-q >/dev/null)
(cd "$host" && env -u BP3_Q_BIN PATH="$work/bin:$PATH" bp3 q host-q c node-1-one >/dev/null)
host_sess="$(cd "$host" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/bp3/sessions"
mkdir -p "$host_sess"
printf '{"session_id":"host-S","quest":"host-q","mode":"induct","desk":null,"red_ink_path":null,"updated_ts":1795640000}\n' > "$host_sess/host-S.json"
pay_host="$(printf '{"conversation_id":"host-S","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":15.0}}' "$host")"
out_host="$(printf '%s' "$pay_host" | NO_COLOR=1 env -u BP3_Q_BIN PATH="$work/bin:$PATH" "$script")"
assert_contains "$out_host" "bp3: host-q [░░░░░░░░] 0/1 (0%)" "host repo session lookup"

echo "agy-statusline tests: ok ($checks assertions)"
