#!/bin/bash
# dogfood.3: derived self/host mode — never a flag, core skills
# everywhere, bp3-dev overlay self-only, mode on the Run record.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-mode-tests.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
checks=0
assert() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; checks=$((checks + 1)); }
rejects() {
  if "$@" > "$work/out" 2> "$work/error"; then printf 'FAIL: expected rejection: %s\n' "$*" >&2; exit 1; fi
  checks=$((checks + 1))
}
gbin="$repo/_build/default/src/quest/main.exe"
[ -x "$gbin" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }
export BP3_DB="${BP3_DB:-$work/bp3.sqlite}"
export BP3_Q_BIN="${BP3_Q_BIN:-$gbin}"
export BP3_COMPLETIONS_DIR="$work/completions"
export BP3_GLOBAL_HOME="$work/home"

# Every source skill is in exactly one set (fail-closed hosts).
core=$(sed -n 's/^CORE_SKILLS="\(.*\)"/\1/p' "$repo/bin/bp3")
dev=$(sed -n 's/^DEV_SKILLS="\(.*\)"/\1/p' "$repo/bin/bp3")
# warden-v0 skills.1: warden is in CORE_SKILLS and trial is retired from DEV_SKILLS
case " $core " in *" warden "*) checks=$((checks + 1)) ;; *) echo "FAIL: warden missing from CORE_SKILLS" >&2; exit 1 ;; esac
case " $dev " in *" trial "*) echo "FAIL: trial still in DEV_SKILLS" >&2; exit 1 ;; *) checks=$((checks + 1)) ;; esac
for skill_dir in "$repo"/skills/*/; do
  id=$(basename "$skill_dir")
  n=0
  case " $core " in *" $id "*) n=$((n + 1)) ;; esac
  case " $dev " in *" $id "*) n=$((n + 1)) ;; esac
  assert test "$n" -eq 1
done

# Self: this repo derives self, and --mode is a usage error
# naming derivation on harness, quest, and install verbs.
out=$(cd "$repo" && ./bin/bp3 config)
echo "$out" | jq -e '.mode == "self"' > /dev/null || { echo "FAIL: self mode: $out" >&2; exit 1; }
checks=$((checks + 1))
rejects "$repo/bin/bp3" q g1 u n1 handoff --mode host --reason x
assert grep -q 'derived from the repo' "$work/out" "$work/error"
rejects "$repo/bin/bp3" skills install --mode host
assert grep -q 'derived from the repo' "$work/out" "$work/error"
rejects "$repo/bin/bp3" skills check --mode=self
assert grep -q 'derived from the repo' "$work/out" "$work/error"

# Host fixture: a git repo with no bp3 source derives host.
host="$work/host"
mkdir -p "$host"
git -C "$host" init -q -b main
git -C "$host" config user.email t@t.t
git -C "$host" config user.name t
echo app > "$host/app.txt"
git -C "$host" add .
git -C "$host" commit -qm base
out=$(cd "$host" && "$gbin" config)
echo "$out" | jq -e '.mode == "host"' > /dev/null || { echo "FAIL: host mode: $out" >&2; exit 1; }
checks=$((checks + 1))

# Host install (global.1): CORE_SKILLS + global hooks install under BP3_GLOBAL_HOME;
# ZERO generated skill or hook files are written into the host repo.
BP3_TARGET="$host" "$repo/bin/bp3" skills install --harness=all > /dev/null
for id in $core; do
  assert test -f "$work/home/.gemini/config/skills/$id/SKILL.md"
  assert test -f "$work/home/.claude/skills/$id/SKILL.md"
  assert test -f "$work/home/.pi/agent/skills/$id/SKILL.md"
  assert test -f "$work/home/.codex/skills/$id/SKILL.md"
  assert test -f "$work/home/.muse/skills/$id/SKILL.md"
done
for id in $dev; do
  assert test ! -e "$work/home/.gemini/config/skills/$id"
  assert test ! -e "$work/home/.claude/skills/$id"
done
assert test ! -e "$host/.agents"
assert test ! -e "$host/.claude"
assert test ! -e "$host/.pi"
assert test ! -e "$host/.muse"
assert jq -e '.hooks.SessionStart[0].hooks[0].command == "bp3 q hooks || true"' "$work/home/.claude/settings.json" >/dev/null
assert jq -e '.bp3.SessionStart[0].command == "bp3 q hooks || true"' "$work/home/.gemini/config/hooks.json" >/dev/null

# Self fixture (global.1): tracked src/quest + bin/bp3 derives self, installs
# CORE_SKILLS globally, and renders ONLY DEV_SKILLS repo-locally.
self="$work/self"
mkdir -p "$self/src/quest" "$self/bin"
git -C "$self" init -q -b main
git -C "$self" config user.email t@t.t
git -C "$self" config user.name t
touch "$self/src/quest/.keep"
cp "$repo/bin/bp3" "$self/bin/bp3"
git -C "$self" add .
git -C "$self" commit -qm base
BP3_TARGET="$self" "$repo/bin/bp3" skills install --harness=muse > /dev/null
for id in $dev; do assert test -f "$self/.agents/skills/$id/SKILL.md"; done
for id in $core; do assert test ! -e "$self/.agents/skills/$id"; done
assert jq -e '.hooks.SessionStart[0].hooks[0].command == "bp3 q hooks || true"' "$work/home/.muse/hooks.json" >/dev/null

printf 'mode tests: ok (%s assertions)\n' "$checks"
