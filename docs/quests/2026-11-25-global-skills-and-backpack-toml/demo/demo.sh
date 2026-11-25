#!/usr/bin/env bash
# Runnable landing demo for 2026-11-25-global-skills-and-backpack-toml.
# Runs strictly inside a fresh mktemp -d sandbox with isolated BP3_GLOBAL_HOME,
# BP3_COMPLETIONS_DIR, and BP3_DB — never touches real ~/ or repo state.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../../../.." && pwd)
bp3="$repo/bin/bp3"
qbin="$repo/_build/default/src/quest/main.exe"
[ -x "$qbin" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-global-demo.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

export BP3_Q_BIN="$qbin"
export BP3_GLOBAL_HOME="$work/home"
export BP3_COMPLETIONS_DIR="$work/comp"
export BP3_DB="$work/bp3.sqlite"
export BP3_HARNESS=agy BP3_MODEL=demo-model

step() { printf '\n=== %s ===\n' "$1"; }
run() { printf '$ %s\n' "$*" >&2; "$@"; }

# 1. Happy path: host repo bootstrap + user-global skills/hooks + global hook from /tmp
step "1. Happy path: bp3 init-repo + user-global CORE_SKILLS/hooks + /tmp hook re-root"
host="$work/host-app"
mkdir -p "$host"
git -C "$host" init -q -b main
git -C "$host" config user.email demo@t.t
git -C "$host" config user.name demo
echo "hello" > "$host/README.md"
git -C "$host" add . && git -C "$host" commit -qm "init"

(cd "$host" && BP3_ROOT="$host" run "$qbin" init-repo) | jq '{ok, manifest, manifest_created, plans}'
(cd "$host" && run cat backpack.toml)
(cd "$host" && BP3_ROOT="$host" run "$qbin" config) | jq '{ok, mode, repo: .repo_config.repo, target: .repo_config.release.target, warnings: (.warnings // []) | length}'

# Install user-global CORE_SKILLS + hooks: host repo gets ZERO local skill/hook dirs
BP3_TARGET="$host" "$bp3" skills install --harness=all >/dev/null
printf 'Global agy skill present: %s\n' "$(test -f "$BP3_GLOBAL_HOME/.gemini/config/skills/induct/SKILL.md" && echo yes || echo no)"
printf 'Global claude skill present: %s\n' "$(test -f "$BP3_GLOBAL_HOME/.claude/skills/induct/SKILL.md" && echo yes || echo no)"
printf 'Host local .agents/.claude/.pi count: %s\n' "$(find "$host" -maxdepth 1 \( -name .agents -o -name .claude -o -name .pi \) | wc -l | tr -d ' ')"

# Invoke global hook from /tmp (BP3_ROOT unset): re-roots onto payload.cwd via backpack.toml
(cd "$host" && BP3_ROOT="$host" "$qbin" q c demo-q >/dev/null && BP3_ROOT="$host" "$qbin" q demo-q c demo-n >/dev/null)
RUN_ID="20261125T170000Z-handoff-agy-demo-c1"
mkdir -p "$host/docs/quests/demo-q/nodes/demo-n/runs/$RUN_ID"
payload=$(printf '{"hook_event_name":"PreToolUse","session_id":"S-demo","cwd":"%s","tool_input":{"command":"BP3_RUN_ID=%s BP3_QUEST=demo-q BP3_NODE=demo-n echo work"}}' "$host" "$RUN_ID")
hook_out=$(cd /tmp && printf '%s\n' "$payload" | env -u BP3_ROOT "$qbin" q hooks)
echo "$hook_out" | jq '{ok, event: .event_line.event, run_id: .event_line.run_id}'
echo "$hook_out" | jq -e '.ok == true and .event_line.event == "run_started"' >/dev/null

# 2. Refusal path: malformed backpack.toml -> E_INVALID_CONFIG; non-bp3 repo -> dormant hook
step "2. Refusal path: malformed backpack.toml & non-bp3 repo hook dormancy"
bad="$work/bad-toml"
mkdir -p "$bad"
git -C "$bad" init -q -b main
printf 'version = 99\nunknown_key = "nope"\n' > "$bad/backpack.toml"
set +e
bad_out=$(cd "$bad" && BP3_ROOT="$bad" "$qbin" config 2>&1)
bad_rc=$?
set -e
printf 'bp3 config on bad backpack.toml exited %d:\n' "$bad_rc"
echo "$bad_out" | jq '{ok, code: .error.code}'
[ "$bad_rc" -eq 1 ]
echo "$bad_out" | jq -e '.ok == false and .error.code == "E_INVALID_CONFIG"' >/dev/null

plain="$work/non-bp3"
mkdir -p "$plain"
git -C "$plain" init -q -b main
git -C "$plain" config user.email demo@t.t && git -C "$plain" config user.name demo
echo x > "$plain/a.txt" && git -C "$plain" add . && git -C "$plain" commit -qm "init"
plain_out=$(cd /tmp && printf '{"hook_event_name":"SessionStart","session_id":"S-plain","cwd":"%s"}\n' "$plain" | env -u BP3_ROOT "$qbin" q hooks)
echo "$plain_out" | jq '{ok, event_line, reason}'
echo "$plain_out" | jq -e '.ok == true and .event_line == null and .reason == "not a bp3 repo"' >/dev/null

# 3. Recovery / migration path: legacy local generated skills -> W_LOCAL_SKILLS_LEGACY -> prune-local
step "3. Recovery path: legacy local skills warn (0 commits) -> bp3 skills prune-local preserves custom skills"
mkdir -p "$host/.agents/skills/quest" "$host/.agents/skills/my-custom"
cat > "$host/.agents/skills/quest/SKILL.md" <<'MD'
---
name: quest
description: legacy
---
<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=agy. Edit the source, then re-run. -->
MD
cat > "$host/.agents/skills/my-custom/SKILL.md" <<'MD'
---
name: my-custom
description: repo-owned skill
---
Custom repo skill (must survive prune-local).
MD
git -C "$host" add . && git -C "$host" commit -qm "chore: legacy generated + custom skill"
before_sha=$(git -C "$host" rev-parse HEAD)

warn_out=$(cd /tmp && printf '{"hook_event_name":"SessionStart","session_id":"S-mig","cwd":"%s"}\n' "$host" | env -u BP3_ROOT "$qbin" q hooks)
echo "$warn_out" | jq '{ok, warning: .warnings[0].code, files: .warnings[0].files}'
echo "$warn_out" | jq -e '.warnings[0].code == "W_LOCAL_SKILLS_LEGACY"' >/dev/null
[ "$(git -C "$host" rev-parse HEAD)" = "$before_sha" ]

prune_out=$(BP3_TARGET="$host" "$bp3" skills prune-local)
echo "$prune_out" | jq '{ok, mode, pruned_skills}'
test ! -e "$host/.agents/skills/quest"
test -f "$host/.agents/skills/my-custom/SKILL.md"

clean_out=$(cd /tmp && printf '{"hook_event_name":"SessionStart","session_id":"S-mig2","cwd":"%s"}\n' "$host" | env -u BP3_ROOT "$qbin" q hooks)
echo "$clean_out" | jq '{ok, warnings: (.warnings // []) | length}'
echo "$clean_out" | jq -e '.ok == true and (.warnings == null)' >/dev/null

printf '\ndemo: ALL CHECKS PASSED\n'
