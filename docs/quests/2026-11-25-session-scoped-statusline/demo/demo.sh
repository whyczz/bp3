#!/usr/bin/env bash
# Runnable sandbox demo for 2026-11-25-session-scoped-statusline.
# Exercises:
#   1. Parallel sessions conv-A (induct) and conv-B (red-ink) bound via bp3 q hooks
#   2. Unbound conv-C and malformed ../evil stay idle even with an abandoned QUEST.2b-reviewed.md
#   3. Deleting conv-B's QUEST.red-ink.md and releasing conv-A immediately return both to idle
set -euo pipefail
unset AGY_CONVERSATION_ID CLAUDE_SESSION_ID

repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
bp3_bin="$repo/_build/default/src/quest/main.exe"
statusline="$repo/scripts/agy-statusline"
[ -x "$bp3_bin" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/bp3-demo-statusline.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

proj="$work/repo"
mkdir -p "$proj/bin" "$proj/plans" "$proj/src/quest" "$proj/docs/quests/q-alpha" "$proj/docs/quests/q-beta" "$proj/docs/quests/abandoned-q"
cp "$repo/bin/bp3" "$proj/bin/bp3"
chmod +x "$proj/bin/bp3"
cp "$repo/plans/default.yaml" "$proj/plans/default.yaml"
touch "$proj/src/quest/main.ml"
printf -- '---\nstatus: proposed\n---\n# q-alpha\n' > "$proj/docs/quests/q-alpha/QUEST.md"
printf -- '---\nstatus: proposed\n---\n# q-beta\n' > "$proj/docs/quests/q-beta/QUEST.md"
printf -- '---\nstatus: proposed\n---\n# abandoned-q\n' > "$proj/docs/quests/abandoned-q/QUEST.md"
git -C "$proj" init -q -b master
git -C "$proj" config user.email demo@bp3
git -C "$proj" config user.name demo
git -C "$proj" add -A && git -C "$proj" commit -qm init
sha="$(git -C "$proj" rev-parse HEAD)"

(cd "$proj" && BP3_Q_BIN="$bp3_bin" ./bin/bp3 q c q-alpha >/dev/null)
(cd "$proj" && BP3_Q_BIN="$bp3_bin" ./bin/bp3 q q-alpha c node-1 >/dev/null)
(cd "$proj" && BP3_Q_BIN="$bp3_bin" ./bin/bp3 q q-alpha c node-2 >/dev/null)
(cd "$proj" && BP3_Q_BIN="$bp3_bin" ./bin/bp3 q q-alpha n node-1 e handoff --commit "$sha" --reason "demo" >/dev/null)
(cd "$proj" && BP3_Q_BIN="$bp3_bin" ./bin/bp3 q q-alpha n node-1 e grade --verdict ship --verify-verdict pass --reason "demo" >/dev/null)
(cd "$proj" && BP3_Q_BIN="$bp3_bin" ./bin/bp3 q q-alpha n node-1 e land --reason "demo" >/dev/null)

touch "$proj/docs/quests/q-beta/QUEST.red-ink.md"
touch "$proj/docs/quests/abandoned-q/QUEST.2b-reviewed.md"

echo "== 1. Bind conv-A (induct q-alpha) and conv-B (red-ink q-beta) via bp3 q hooks =="
printf '{"hookEventName":"PostToolUse","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"bp3 harness desk prepare --quest q-alpha"}}}' "$proj" \
  | BP3_Q_BIN="$bp3_bin" "$proj/bin/bp3" q hooks >/dev/null
printf '{"hookEventName":"PostToolUse","conversationId":"conv-B","cwd":"%s","toolCall":{"name":"edit_file","args":{"Path":"%s/docs/quests/q-beta/QUEST.red-ink.md"}}}' "$proj" "$proj" \
  | BP3_Q_BIN="$bp3_bin" "$proj/bin/bp3" q hooks >/dev/null

out_a="$(printf '{"session_id":"conv-A","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj" | NO_COLOR=1 BP3_Q_BIN="$bp3_bin" "$statusline")"
out_b="$(printf '{"conversation_id":"conv-B","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj" | NO_COLOR=1 BP3_Q_BIN="$bp3_bin" "$statusline")"
out_c="$(printf '{"session_id":"conv-C","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj" | NO_COLOR=1 BP3_Q_BIN="$bp3_bin" "$statusline")"
out_bad="$(printf '{"session_id":"../evil","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj" | NO_COLOR=1 BP3_Q_BIN="$bp3_bin" "$statusline")"

echo "conv-A:  $out_a"
echo "conv-B:  $out_b"
echo "conv-C:  $out_c"
echo "bad sid: $out_bad"

printf '%s' "$out_a" | grep -qF "bp3: q-alpha [████░░░░] 1/2 (50%)"
printf '%s' "$out_b" | grep -qF "bp3: q-beta [red-ink]"
printf '%s' "$out_c" | grep -qF "bp3: idle"
printf '%s' "$out_bad" | grep -qF "bp3: idle"

echo "== 2. Delete q-beta/QUEST.red-ink.md and release q-alpha -> both sessions drop to idle =="
rm -f "$proj/docs/quests/q-beta/QUEST.red-ink.md"
printf '{"hookEventName":"PostToolUse","conversationId":"conv-A","cwd":"%s","toolCall":{"name":"run_command","args":{"CommandLine":"BP3_DECIDER=human bp3 release q-alpha"}}}' "$proj" \
  | BP3_Q_BIN="$bp3_bin" "$proj/bin/bp3" q hooks >/dev/null

out_a2="$(printf '{"session_id":"conv-A","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj" | NO_COLOR=1 BP3_Q_BIN="$bp3_bin" "$statusline")"
out_b2="$(printf '{"conversation_id":"conv-B","cwd":"%s","context_window":{"context_window_size":1000000,"used_percentage":20.0}}' "$proj" | NO_COLOR=1 BP3_Q_BIN="$bp3_bin" "$statusline")"
echo "conv-A after release: $out_a2"
echo "conv-B after rm:      $out_b2"

printf '%s' "$out_a2" | grep -qF "bp3: idle"
printf '%s' "$out_b2" | grep -qF "bp3: idle"
echo "demo ok: session-scoped statusline isolated and unfreezes cleanly!"
