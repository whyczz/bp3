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
export BP3_COMPLETIONS_DIR="$work/completions"

# Every source skill is in exactly one set (fail-closed hosts).
core=$(sed -n 's/^CORE_SKILLS="\(.*\)"/\1/p' "$repo/bin/bp3")
dev=$(sed -n 's/^DEV_SKILLS="\(.*\)"/\1/p' "$repo/bin/bp3")
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
rejects "$repo/bin/bp3" harness link mint --kind node --quest g1 --node n1 --mode host
assert grep -q 'derived from the repo' "$work/out" "$work/error"
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
mint=$(cd "$host" && "$gbin" harness link mint --kind node --quest g1 --node n1 --harness pi --model test-model)
echo "$mint" | jq -e '.mode == "host"' > /dev/null || { echo "FAIL: mint mode: $mint" >&2; exit 1; }
checks=$((checks + 1))
run_id=$(echo "$mint" | jq -r .run_id)
assert jq -e '.mode == "host"' "$host/.git/bp3/runs/$run_id.json"

# Host install: core only, zero bp3-dev, host hook command.
BP3_TARGET="$host" "$repo/bin/bp3" skills install --harness=muse > /dev/null
for id in $core; do assert test -f "$host/.agents/skills/$id/SKILL.md"; done
for id in $dev; do assert test ! -e "$host/.agents/skills/$id"; done
assert grep -q '"command": "bp3 q hooks || true"' "$host/.claude/hooks.json"
assert test -f "$host/.agents/workflows/node-loop.js"

# Self fixture: tracked src/quest + bin/bp3 derives self and
# renders the bp3-dev overlay too, with the desk hook command.
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
for id in $core $dev; do assert test -f "$self/.agents/skills/$id/SKILL.md"; done
assert grep -q '"command": "./bin/bp3 q hooks || true"' "$self/.claude/hooks.json"

# Mode-aware reads: desk presence derives the read path.
for wf in node-loop induct-node induct-grade induct-land; do
  assert grep -q 'desk ? "./bin/bp3" : "bp3"' "$repo/skills/induct/workflows/$wf.js"
done

printf 'mode tests: ok (%s assertions)\n' "$checks"
