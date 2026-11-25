#!/usr/bin/env bash
# Fixture suite for release install + global skills/hooks & read-only legacy skill warnings (global.1 + global.2):
# 1. Self-mode `bp3 release` auto-installs tagged build to $PREFIX, populates $BP3_GLOBAL_HOME
#    skills/hooks stamped with (v<ver>), and writes share/bp3/RELEASE
# 2. --no-install skips $PREFIX update; untagged installs remove RELEASE
# 3. Host repo with legacy local generated skills emits read-only W_LOCAL_SKILLS_LEGACY on
#    SessionStart and creates ZERO git commits (both without and with backpack.toml, clean or dirty)
# 4. After `bp3 skills prune-local`, SessionStart emits zero warnings and creates zero commits
# 5. agy payload keeps valid JSON ({}) and never mutates host; plain non-bp3 host untouched
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
export BP3_GLOBAL_HOME="$work/home"
export BP3_DB="$work/bp3.sqlite"
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
jq -e '.tag == "v0.3.0" and .version == "0.3.0"' "$prefix/share/bp3/RELEASE" >/dev/null || fail "bad RELEASE json: $(cat "$prefix/share/bp3/RELEASE")"
# global.1: release install populates user-global CORE_SKILLS with (v0.3.0) stamp + global hooks
grep -q 'GENERATED from skills/quest/SKILL.md (v0.3.0) by:' "$work/home/.gemini/config/skills/quest/SKILL.md" || fail "missing global agy (v0.3.0) stamp"
grep -q 'GENERATED from skills/quest/SKILL.md (v0.3.0) by:' "$work/home/.claude/skills/quest/SKILL.md" || fail "missing global claude (v0.3.0) stamp"
grep -q 'GENERATED from skills/quest/SKILL.md (v0.3.0) by:' "$work/home/.pi/agent/skills/quest/SKILL.md" || fail "missing global pi (v0.3.0) stamp"; ok

# --no-install skips updating a second prefix
prefix2="$work/prefix-noinstall"
echo fix >> "$self_repo/fix.txt" && git -C "$self_repo" add . && git -C "$self_repo" commit -qm "fix: noinstall"
fix_sha=$(git -C "$self_repo" rev-parse HEAD)
out=$(cd "$self_repo" && PREFIX="$prefix2" BP3_RELEASE_ARTIFACT="$qbin" BP3_DECIDER=human BP3_ROOT="$self_repo" "$qbin" release --commit "$fix_sha" --no-gh --no-install) || fail "no-install release failed: $out"
echo "$out" | jq -e '.ok == true and .tag == "v0.3.1" and .installed_prefix == null' >/dev/null || fail "no-install json: $out"
[ ! -e "$prefix2/share/bp3/RELEASE" ] || fail "--no-install still wrote prefix2"; ok

# Untagged commit + manual install-bp3.sh removes stale RELEASE and respects BP3_GLOBAL_HOME for agy settings
echo untagged >> "$self_repo/untagged.txt" && git -C "$self_repo" add . && git -C "$self_repo" commit -qm "wip: untagged"
prefix_untagged="$work/prefix-untagged"
mkdir -p "$prefix_untagged/share/bp3" "$work/home-iso/.gemini/antigravity-cli"
printf '{"tag":"v0.1.0"}\n' > "$prefix_untagged/share/bp3/RELEASE"
env -u BP3_AGY_SETTINGS BP3_GLOBAL_HOME="$work/home-iso" PREFIX="$prefix_untagged" "$self_repo/scripts/install-bp3.sh" "$qbin" >/dev/null
[ ! -e "$prefix_untagged/share/bp3/RELEASE" ] || fail "untagged install kept stale RELEASE"
jq -e '.statusLine.enabled == true' "$work/home-iso/.gemini/antigravity-cli/settings.json" >/dev/null || fail "BP3_GLOBAL_HOME did not isolate agy settings.json"; ok

# --- 2. Clean host repo with legacy unversioned skills -> read-only W_LOCAL_SKILLS_LEGACY on SessionStart ---
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
git -C "$host" add . && git -C "$host" commit -qm "chore: old skills"

before_sha=$(git -C "$host" rev-parse HEAD)
payload='{"hook_event_name":"SessionStart","session_id":"s1","cwd":"'"$host"'"}'
# global.2: host SessionStart with legacy local generated skills emits read-only
# W_LOCAL_SKILLS_LEGACY and creates ZERO git commits (even from cd /tmp without BP3_ROOT).
out=$(cd /tmp && printf '%s\n' "$payload" | env -u BP3_ROOT PATH="$prefix/bin:$PATH" "$prefix/bin/bp3-q" q hooks) || fail "SessionStart hook failed: $out"
echo "$out" | jq -e '
  .ok == true
  and .event_line == null
  and ([.warnings[]?.code] | index("W_LOCAL_SKILLS_LEGACY") != null)
  and ([.warnings[]?.message] | any(contains("bp3 skills prune-local")))
  and ((.warnings[0].files | length) == 3)
' >/dev/null || fail "SessionStart W_LOCAL_SKILLS_LEGACY json: $out"
after_sha=$(git -C "$host" rev-parse HEAD)
[ "$before_sha" = "$after_sha" ] || fail "SessionStart mutated host repo HEAD"
[ -z "$(git -C "$host" status --short)" ] || fail "host tree dirty after SessionStart: $(git -C "$host" status --short)"; ok

# --- 3. Dirty host repo WITH backpack.toml + legacy skills: emits W_LOCAL_SKILLS_LEGACY, zero commits ---
printf 'version = 1\nrepo = "predictor-like"\n' > "$host/backpack.toml"
echo dirty > "$host/dirty.txt"
out=$(cd /tmp && printf '%s\n' "$payload" | env -u BP3_ROOT PATH="$prefix/bin:$PATH" "$prefix/bin/bp3-q" q hooks) || fail "dirty SessionStart failed: $out"
echo "$out" | jq -e '
  .ok == true
  and ([.warnings[]?.code] | index("W_LOCAL_SKILLS_LEGACY") != null)
  and ((.warnings[0].files | length) == 3)
' >/dev/null || fail "dirty backpack.toml json: $out"
[ "$(git -C "$host" rev-parse HEAD)" = "$after_sha" ] || fail "dirty host committed"
rm -f "$host/dirty.txt"; ok

# --- 3b. After bp3 skills prune-local, SessionStart emits 0 warnings and 0 commits ---
BP3_TARGET="$host" "$prefix/bin/bp3" skills prune-local >/dev/null || fail "prune-local failed"
out=$(cd /tmp && printf '%s\n' "$payload" | env -u BP3_ROOT PATH="$prefix/bin:$PATH" "$prefix/bin/bp3-q" q hooks) || fail "post-prune SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and (.warnings == null)' >/dev/null || fail "post-prune warnings remained: $out"
[ "$(git -C "$host" rev-parse HEAD)" = "$after_sha" ] || fail "post-prune SessionStart committed"; ok

# --- 4. agy SessionStart payload keeps valid JSON ({}) and never mutates host ---
agy_payload='{"hookEventName":"SessionStart","conversationId":"c1","cwd":"'"$host"'"}'
out=$(cd /tmp && printf '%s\n' "$agy_payload" | env -u BP3_ROOT PATH="$prefix/bin:$PATH" "$prefix/bin/bp3-q" q hooks) || fail "agy SessionStart failed: $out"
echo "$out" | jq -e '. == {}' >/dev/null || fail "agy stdout not {}: $out"
[ "$(git -C "$host" rev-parse HEAD)" = "$after_sha" ] || fail "agy SessionStart committed"; ok

# --- 5. Host repo with zero bp3-generated skills is never touched ---
plain="$work/plain-repo"
mkdir -p "$plain"
git -C "$plain" init -q -b master
git -C "$plain" config user.email t@t.t
git -C "$plain" config user.name "Test User"
echo hi > "$plain/README.md" && git -C "$plain" add . && git -C "$plain" commit -qm "init"
plain_sha=$(git -C "$plain" rev-parse HEAD)
plain_payload='{"hook_event_name":"SessionStart","session_id":"s9","cwd":"'"$plain"'"}'
out=$(cd /tmp && printf '%s\n' "$plain_payload" | env -u BP3_ROOT PATH="$prefix/bin:$PATH" "$prefix/bin/bp3-q" q hooks) || fail "plain SessionStart failed: $out"
echo "$out" | jq -e '.ok == true and .event_line == null and .reason == "not a bp3 repo" and (.warnings == null)' >/dev/null || fail "plain json: $out"
[ "$(git -C "$plain" rev-parse HEAD)" = "$plain_sha" ] || fail "plain repo modified"
[ ! -d "$plain/.claude" ] && [ ! -d "$plain/.agents" ] || fail "plain repo got skills injected"; ok

echo "release-sync tests: ok ($checks checks)"
