#!/usr/bin/env bash
# Fixture suite for tag-gated local auto-sync (quest-promote-release sync.1):
# 1. Self-mode `bp3 release` auto-installs tagged build to $PREFIX + writes share/bp3/RELEASE
# 2. --no-install skips $PREFIX update; untagged installs remove RELEASE
# 3. Clean host repo with legacy unversioned skills auto-syncs & commits on SessionStart
#    (surviving a failing pre-commit hook via --no-verify), stamping (v<ver>)
# 4. Second SessionStart is an up_to_date no-op
# 5. Dirty / detached / mid-rebase host repo skips git writes + emits W_BP3_UPDATE_AVAILABLE
# 6. BP3_NO_AUTO_SYNC=1 disables auto-sync; agy payload keeps valid JSON; non-bp3 host untouched
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
checks=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { checks=$((checks + 1)); }

qbin="$root/_build/default/src/quest/main.exe"
[ -x "$qbin" ] || fail "missing built binary $qbin"

export BP3_HARNESS=agy BP3_MODEL=test-model
export BP3_AGY_SETTINGS="$work/agy-settings.json"
unset BP3_DECIDER || true

# --- 1. Self-mode repo: bp3 release installs into $PREFIX + writes share/bp3/RELEASE ---
self_repo="$work/bp3-self"
mkdir -p "$self_repo/src/quest" "$self_repo/bin" "$self_repo/scripts" "$self_repo/plans" "$self_repo/completions"
cp "$root/bin/bp3" "$self_repo/bin/"
cp "$root/scripts/install-bp3.sh" "$root/scripts/release-check" "$root/scripts/check-skills" "$root/scripts/agy-statusline" "$self_repo/scripts/"
cp -R "$root/skills" "$self_repo/skills"
cp "$root"/plans/*.yaml "$self_repo/plans/"
cp "$root"/completions/* "$self_repo/completions/"
printf 'let bp3_version = "0.2.0"\n' > "$self_repo/src/quest/gitx.ml"
git -C "$self_repo" init -q -b master
git -C "$self_repo" config user.email t@t.t
git -C "$self_repo" config user.name "Test User"
git -C "$self_repo" add .
git -C "$self_repo" commit -qm "chore: base self"
git -C "$self_repo" tag -a v0.2.0 -m "bp3 v0.2.0"

# Land a quest in self_repo
(cd "$self_repo" && BP3_ROOT="$self_repo" "$qbin" q c q-sync --type direct >/dev/null)
(cd "$self_repo" && BP3_ROOT="$self_repo" "$qbin" q q-sync c n1 >/dev/null)
mkdir -p "$self_repo/docs/quests/q-sync"
printf -- '---\nstatus: active\ndate: 2026-11-23\nbump: minor\n---\n\n# sync release\n\nTL;DR\nShips v0.3.0.\n' > "$self_repo/docs/quests/q-sync/QUEST.md"
git -C "$self_repo" add . && git -C "$self_repo" commit -qm "feat: sync release"
sha=$(git -C "$self_repo" rev-parse HEAD)
(cd "$self_repo" && BP3_ROOT="$self_repo" "$qbin" q q-sync n n1 e handoff --commit "$sha" --reason "h" >/dev/null)
(cd "$self_repo" && BP3_ROOT="$self_repo" "$qbin" q q-sync n n1 e verify --verdict pass --reason "v" >/dev/null)
(cd "$self_repo" && BP3_ROOT="$self_repo" "$qbin" q q-sync n n1 e land --reason "l" >/dev/null)

prefix="$work/prefix"
out=$(cd "$self_repo" && PREFIX="$prefix" BP3_RELEASE_ARTIFACT="$qbin" BP3_DECIDER=human BP3_ROOT="$self_repo" "$qbin" release q-sync --no-gh) || fail "self release install failed: $out"
echo "$out" | jq -e --arg p "$prefix" '.ok == true and .tag == "v0.3.0" and .installed_prefix == $p' >/dev/null || fail "self release json: $out"
[ -x "$prefix/bin/bp3" ] && [ -x "$prefix/bin/bp3-q" ] || fail "binaries not installed to $prefix"
[ -f "$prefix/share/bp3/RELEASE" ] || fail "share/bp3/RELEASE missing"
jq -e '.tag == "v0.3.0" and .version == "0.3.0"' "$prefix/share/bp3/RELEASE" >/dev/null || fail "bad RELEASE json: $(cat "$prefix/share/bp3/RELEASE")"; ok

# --no-install skips updating a second prefix
prefix2="$work/prefix-noinstall"
echo fix >> "$self_repo/fix.txt" && git -C "$self_repo" add . && git -C "$self_repo" commit -qm "fix: noinstall"
fix_sha=$(git -C "$self_repo" rev-parse HEAD)
out=$(cd "$self_repo" && PREFIX="$prefix2" BP3_RELEASE_ARTIFACT="$qbin" BP3_DECIDER=human BP3_ROOT="$self_repo" "$qbin" release --commit "$fix_sha" --no-gh --no-install) || fail "no-install release failed: $out"
echo "$out" | jq -e '.ok == true and .tag == "v0.3.1" and .installed_prefix == null' >/dev/null || fail "no-install json: $out"
[ ! -e "$prefix2/share/bp3/RELEASE" ] || fail "--no-install still wrote prefix2"; ok

# Untagged commit + manual install-bp3.sh removes stale RELEASE
echo untagged >> "$self_repo/untagged.txt" && git -C "$self_repo" add . && git -C "$self_repo" commit -qm "wip: untagged"
prefix_untagged="$work/prefix-untagged"
mkdir -p "$prefix_untagged/share/bp3"
printf '{"tag":"v0.1.0"}\n' > "$prefix_untagged/share/bp3/RELEASE"
PREFIX="$prefix_untagged" "$self_repo/scripts/install-bp3.sh" "$qbin" >/dev/null
[ ! -e "$prefix_untagged/share/bp3/RELEASE" ] || fail "untagged install kept stale RELEASE"; ok

# --- 2. Clean host repo with legacy unversioned skills -> auto-syncs & commits on SessionStart ---
host="$work/predictor-like"
mkdir -p "$host/.claude/skills/quest" "$host/.agents/skills/quest" "$host/.pi/skills/quest"
git -C "$host" init -q -b master
git -C "$host" config user.email t@t.t
git -C "$host" config user.name "Test User"
# Legacy unversioned rendered skill (exact predictor state)
cat > "$host/.agents/skills/quest/SKILL.md" <<'MD'
---
name: quest
description: old
---
<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=agy. Edit the source, then re-run. -->
old content
MD
cp "$host/.agents/skills/quest/SKILL.md" "$host/.claude/skills/quest/SKILL.md"
cp "$host/.agents/skills/quest/SKILL.md" "$host/.pi/skills/quest/SKILL.md"
# Install a failing pre-commit hook to prove --no-verify avoids blocking SessionStart
mkdir -p "$host/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$host/.git/hooks/pre-commit"
chmod +x "$host/.git/hooks/pre-commit"
git -C "$host" add . && git -C "$host" commit --no-verify -qm "chore: old skills"

before_sha=$(git -C "$host" rev-parse HEAD)
payload='{"hook_event_name":"SessionStart","session_id":"s1","cwd":"'"$host"'"}'
out=$(printf '%s\n' "$payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "SessionStart hook failed: $out"
echo "$out" | jq -e '.ok == true and .auto_sync.status == "synced" and .auto_sync.tag == "v0.3.0"' >/dev/null || fail "auto_sync synced json: $out"
after_sha=$(git -C "$host" rev-parse HEAD)
[ "$before_sha" != "$after_sha" ] || fail "auto_sync did not commit"
[ "$(git -C "$host" show -s --format=%s HEAD)" = "chore(bp3): sync skills/hooks to v0.3.0" ] || fail "bad sync commit msg: $(git -C "$host" show -s --format=%s HEAD)"
[ -z "$(git -C "$host" status --short)" ] || fail "host tree dirty after auto-sync: $(git -C "$host" status --short)"
grep -q 'GENERATED from skills/quest/SKILL.md (v0.3.0) by:' "$host/.agents/skills/quest/SKILL.md" || fail "missing (v0.3.0) stamp in .agents"
grep -q 'GENERATED from skills/quest/SKILL.md (v0.3.0) by:' "$host/.claude/skills/quest/SKILL.md" || fail "missing (v0.3.0) stamp in .claude"
grep -q 'GENERATED from skills/quest/SKILL.md (v0.3.0) by:' "$host/.pi/skills/quest/SKILL.md" || fail "missing (v0.3.0) stamp in .pi"; ok

# --- 3. Second SessionStart is a fast up_to_date no-op ---
out=$(printf '%s\n' "$payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "second SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and .auto_sync.status == "up_to_date" and .auto_sync.tag == "v0.3.0"' >/dev/null || fail "up_to_date json: $out"
[ "$(git -C "$host" rev-parse HEAD)" = "$after_sha" ] || fail "second SessionStart created extra commit"; ok

# --- 4. Bump installed RELEASE to v0.4.0 while host is DIRTY -> dirty_skipped + W_BP3_UPDATE_AVAILABLE ---
jq '.tag = "v0.4.0" | .version = "0.4.0"' "$prefix/share/bp3/RELEASE" > "$prefix/share/bp3/RELEASE.tmp"
mv "$prefix/share/bp3/RELEASE.tmp" "$prefix/share/bp3/RELEASE"
echo dirty > "$host/dirty.txt"
out=$(printf '%s\n' "$payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "dirty SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and .auto_sync.status == "dirty_skipped" and .auto_sync.installed_tag == "v0.4.0" and .auto_sync.warning == "W_BP3_UPDATE_AVAILABLE"' >/dev/null || fail "dirty_skipped json: $out"
[ "$(git -C "$host" rev-parse HEAD)" = "$after_sha" ] || fail "dirty host committed"
grep -q '(v0.3.0)' "$host/.agents/skills/quest/SKILL.md" || fail "dirty host modified skills"
rm -f "$host/dirty.txt"; ok

# --- 5. Detached HEAD -> dirty_skipped (zero mutations) ---
git -C "$host" checkout -q --detach HEAD
out=$(printf '%s\n' "$payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "detached SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and .auto_sync.status == "dirty_skipped" and .auto_sync.warning == "W_BP3_UPDATE_AVAILABLE"' >/dev/null || fail "detached json: $out"
git -C "$host" checkout -q master; ok

# --- 6. BP3_NO_AUTO_SYNC=1 disables auto-sync cleanly ---
out=$(printf '%s\n' "$payload" | BP3_NO_AUTO_SYNC=1 PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "opt-out SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and (has("auto_sync") | not)' >/dev/null || fail "opt-out json: $out"
[ "$(git -C "$host" rev-parse HEAD)" = "$after_sha" ] || fail "opt-out committed"; ok

# --- 7. agy SessionStart payload keeps valid JSON ({}) and still syncs clean host ---
agy_payload='{"hookEventName":"SessionStart","conversationId":"c1","cwd":"'"$host"'"}'
out=$(printf '%s\n' "$agy_payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "agy SessionStart failed: $out"
echo "$out" | jq -e 'type == "object"' >/dev/null || fail "agy stdout not JSON: $out"
[ "$(git -C "$host" show -s --format=%s HEAD)" = "chore(bp3): sync skills/hooks to v0.4.0" ] || fail "agy SessionStart did not sync to v0.4.0"; ok

# --- 7b. SessionStart launched from a nested subdirectory resolves git toplevel and still syncs ---
mkdir -p "$host/src/nested"
echo "// nested" > "$host/src/nested/app.py"
git -C "$host" add src/nested/app.py && git -C "$host" commit --no-verify -qm "feat: nested dir"
jq '.tag = "v0.4.1" | .version = "0.4.1"' "$prefix/share/bp3/RELEASE" > "$prefix/share/bp3/RELEASE.tmp"
mv "$prefix/share/bp3/RELEASE.tmp" "$prefix/share/bp3/RELEASE"
subdir_payload='{"hook_event_name":"SessionStart","session_id":"s-sub","cwd":"'"$host/src/nested"'"}'
out=$(printf '%s\n' "$subdir_payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$host" "$prefix/bin/bp3-q" q hooks) || fail "subdir SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and .auto_sync.status == "synced" and .auto_sync.tag == "v0.4.1"' >/dev/null || fail "subdir auto_sync json: $out"
[ "$(git -C "$host" show -s --format=%s HEAD)" = "chore(bp3): sync skills/hooks to v0.4.1" ] || fail "subdir SessionStart did not commit v0.4.1"; ok

# --- 8. Host repo with zero bp3-generated skills is never touched ---
plain="$work/plain-repo"
mkdir -p "$plain"
git -C "$plain" init -q -b master
git -C "$plain" config user.email t@t.t
git -C "$plain" config user.name "Test User"
echo hi > "$plain/README.md" && git -C "$plain" add . && git -C "$plain" commit -qm "init"
plain_sha=$(git -C "$plain" rev-parse HEAD)
plain_payload='{"hook_event_name":"SessionStart","session_id":"s9","cwd":"'"$plain"'"}'
out=$(printf '%s\n' "$plain_payload" | PATH="$prefix/bin:$PATH" BP3_ROOT="$plain" "$prefix/bin/bp3-q" q hooks) || fail "plain SessionStart failed: $out"
[ "$(git -C "$plain" rev-parse HEAD)" = "$plain_sha" ] || fail "plain repo modified"
[ ! -d "$plain/.claude" ] && [ ! -d "$plain/.agents" ] || fail "plain repo got skills injected"; ok

echo "release-sync tests: ok ($checks checks)"
