#!/bin/bash
# shellcheck disable=SC2016 # Literal JSON and Markdown in fixtures.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-skills-tests.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
checks=0
assert() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; checks=$((checks + 1)); }
rejects() {
  if "$@" > "$work/out" 2> "$work/error"; then printf 'FAIL: expected rejection: %s\n' "$*" >&2; exit 1; fi
  checks=$((checks + 1))
}
# A fresh checkout must carry the project-scope discovery exclusions too.
for skill_dir in "$repo"/skills/*/; do
  id=$(basename "$skill_dir")
  assert jq -e --arg pattern "!**/.agents/skills/$id/SKILL.md" '.skills | index($pattern) != null' "$repo/.pi/settings.json"
done

mkdir -p "$work/project with spaces/bin" "$work/project with spaces/scripts"
root="$work/project with spaces"
cp "$repo/bin/bp3" "$root/bin/"
cp "$repo/scripts/check-skills" "$root/scripts/"
cp -R "$repo/skills" "$root/"
# A self repo by derivation (dogfood.3): tracked src/graph + bin/bp3.
# The fixture names its target explicitly (BP3_TARGET); mode still
# derives from the fixture repo itself, never from a flag.
mkdir -p "$root/src/graph"
touch "$root/src/graph/.keep"
git -C "$root" init -q -b main
git -C "$root" config user.email t@t.t
git -C "$root" config user.name t
git -C "$root" add bin/bp3 src/graph
export BP3_TARGET="$root"
source="$root/skills/add-yap-skill/SKILL.md"
cp "$source" "$work/good.md"

# The exact original nested-mapping regression: an unquoted colon+space.
awk '/^description:/ {$0="description: Add a portable, human-invoked skill to bp3-yap-skills through its gates: clarify, prior art, red chair, and trigger tests."} {print}' "$work/good.md" > "$source"
rejects "$root/scripts/check-skills"
rejects "$root/bin/bp3" skills install --harness=all
assert test ! -e "$root/.pi"
assert test ! -e "$root/.agents"
assert test ! -e "$root/.claude"
assert grep -Eq 'mapping|YAML' "$work/error"

# Quoted colon and block-scalar descriptions must pass real YAML parsing.
cp "$work/good.md" "$source"
"$root/scripts/check-skills" > /dev/null
assert test "$(yq --front-matter=extract '.description' "$source")" = 'Add a portable, human-invoked skill to bp3-yap-skills through its gates: clarify, prior art, red chair, and trigger tests.'
awk '/^description:/ {$0="description: |\n  A valid description: with a colon."} {print}' "$work/good.md" > "$source"
"$root/scripts/check-skills" > /dev/null

for description in 'description: [broken' 'description: {nested: mapping}' 'description: 42' 'description: ""'; do
  awk -v description="$description" '/^description:/ {$0=description} {print}' "$work/good.md" > "$source"
  rejects "$root/scripts/check-skills"
done
cp "$work/good.md" "$source"
awk '/^name:/ {$0="name: wrong"} {print}' "$work/good.md" > "$source"
rejects "$root/scripts/check-skills"
cp "$work/good.md" "$source"
rejects "$root/bin/bp3" skills install --harness=unknown
assert test ! -e "$root/.pi"
rejects "$root/bin/bp3" skills install --harness

mkdir -p "$root/.pi"
printf '{"defaultModel":"keep","skills":["/extra","!**/ignored/**"]}\n' > "$root/.pi/settings.json"
"$root/bin/bp3" skills install --harness=all > /dev/null
"$root/scripts/check-skills" "$root/skills" "$root/.pi/skills" "$root/.agents/skills" "$root/.claude/skills" > /dev/null

# Stale renders: a generated copy whose skill left the set is pruned;
# a hand-written skill (no GENERATED notice) is never touched.
mkdir -p "$root/.claude/skills/retired-skill" "$root/.claude/skills/hand-made"
printf -- '---\nname: retired-skill\n---\n<!-- GENERATED from skills/retired-skill/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->\nold\n' > "$root/.claude/skills/retired-skill/SKILL.md"
printf -- '---\nname: hand-made\n---\nmine\n' > "$root/.claude/skills/hand-made/SKILL.md"
"$root/bin/bp3" skills install --harness=claude > "$work/prune.out"
assert test ! -e "$root/.claude/skills/retired-skill"
assert test -f "$root/.claude/skills/hand-made/SKILL.md"
assert grep -q 'pruned retired-skill' "$work/prune.out"
rm -rf "$root/.claude/skills/hand-made"

# Render freshness (followup.2, workflow-birth): a fresh desk
# passes silently; a backdated render refuses E_RENDER_STALE
# naming render and source; re-render restores freshness.
"$root/bin/bp3" skills check > "$work/check-fresh.json"
assert jq -e '.ok == true' "$work/check-fresh.json"
printf '\n// backdated render\n' >> "$root/.agents/workflows/bp3g-grade.js"
rejects "$root/bin/bp3" skills check
assert grep -q 'E_RENDER_STALE' "$work/out"
assert grep -q '.agents/workflows/bp3g-grade.js' "$work/out"
assert grep -q 'skills/bp3g/workflows/bp3g-grade.js' "$work/out"
"$root/bin/bp3" skills install --harness=all > /dev/null
"$root/bin/bp3" skills check > "$work/check-rerendered.json"
assert jq -e '.ok == true' "$work/check-rerendered.json"
assert jq -e '.defaultModel == "keep" and .skills == ["/extra","!**/ignored/**","!**/.agents/skills/add-bp3-skill/SKILL.md","!**/.agents/skills/add-yap-skill/SKILL.md","!**/.agents/skills/bp3g/SKILL.md","!**/.agents/skills/bp3g-frame/SKILL.md","!**/.agents/skills/bp3g-landing-demo/SKILL.md","!**/.agents/skills/bp3g-no-human/SKILL.md","!**/.agents/skills/icebox/SKILL.md","!**/.agents/skills/naming/SKILL.md","!**/.agents/skills/red-ink/SKILL.md","!**/.agents/skills/using-bp3/SKILL.md"]' "$root/.pi/settings.json"
# bp3g is the one conducting skill; old traverse/induct/quest names render nowhere.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/bp3g/SKILL.md"
  assert test ! -e "$root/$h/skills/traverse"
  assert test ! -e "$root/$h/skills/traverse-no-human"
  assert test ! -e "$root/$h/skills/quest"
  assert test ! -e "$root/$h/skills/induct"
done
# The no-human skill renders beside bp3g in every harness.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/bp3g-no-human/SKILL.md"
done
for h in .pi .agents .claude; do
  assert test "$(yq --front-matter=extract '.description' "$root/$h/skills/add-yap-skill/SKILL.md")" = "$(yq --front-matter=extract '.description' "$source")"
  assert test -f "$root/$h/skills/bp3g-frame/SKILL.md"
done
assert test -f "$root/.agents/workflows/node-loop.js"
assert cmp "$root/skills/bp3g/workflows/node-loop.js" "$root/.agents/workflows/node-loop.js"
assert test -f "$root/.agents/workflows/bp3g-node.js"
assert cmp "$root/skills/bp3g/workflows/bp3g-node.js" "$root/.agents/workflows/bp3g-node.js"
assert test ! -e "$root/.agents/workflows/induct-exp.js"
assert test ! -e "$root/.agents/workflows/induct-node.js"
assert test ! -e "$root/.agents/workflows/quest-land.js"
assert test -f "$root/.agents/workflows/bp3g-grade.js"
assert cmp "$root/skills/bp3g/workflows/bp3g-grade.js" "$root/.agents/workflows/bp3g-grade.js"
assert test -f "$root/.agents/workflows/bp3g-land.js"
assert cmp "$root/skills/bp3g/workflows/bp3g-land.js" "$root/.agents/workflows/bp3g-land.js"
assert test -f "$root/.claude/hooks.json"
assert jq -e '.hooks.SessionStart[0].hooks[0].command == "./bin/bp3 g hooks" and (.hooks | has("PreToolUse") and has("PostToolUse") and has("PostToolUseFailure") and has("PostLLMCall") and has("SubagentStart") and has("SubagentStop") and has("Stop") and has("SessionEnd"))' "$root/.claude/hooks.json"
assert test -f "$root/.muse/hooks.json"
assert cmp "$root/.claude/hooks.json" "$root/.muse/hooks.json"
assert test -f "$root/.claude/settings.json"
assert jq -e '.hooks.SessionStart[0].hooks[0].command == "./bin/bp3 g hooks" and (.hooks | has("PostLLMCall") | not)' "$root/.claude/settings.json"
mkdir -p "$root/.claude"
printf '{"keepMe":true}\n' > "$root/.claude/settings.json"
"$root/bin/bp3" skills install --harness=claude > /dev/null
assert jq -e '.keepMe == true and .hooks.SessionStart[0].hooks[0].command == "./bin/bp3 g hooks"' "$root/.claude/settings.json"
cp "$root/.pi/settings.json" "$work/settings.before"
"$root/bin/bp3" skills install --harness=pi > /dev/null
assert cmp "$work/settings.before" "$root/.pi/settings.json"
assert cmp "$root/skills/bp3g/workflows/node-loop.js" "$root/.agents/workflows/node-loop.js"
assert cmp "$root/skills/bp3g/workflows/bp3g-grade.js" "$root/.agents/workflows/bp3g-grade.js"
assert cmp "$root/skills/bp3g/workflows/bp3g-land.js" "$root/.agents/workflows/bp3g-land.js"

# Corrupt settings must fail BEFORE rewriting any installed files.
printf 'sentinel\n' > "$root/.pi/skills/bp3g-frame/SKILL.md"
for settings in '{broken' '{"skills":null}' '{"skills":[1]}'; do
  printf '%s\n' "$settings" > "$root/.pi/settings.json"
  rejects "$root/bin/bp3" skills install --harness=all
  assert grep -qx sentinel "$root/.pi/skills/bp3g-frame/SKILL.md"
done
# Non-Pi installations must leave project Pi settings alone.
printf '{broken' > "$root/.pi/settings.json"
"$root/bin/bp3" skills install --harness=codex > /dev/null
assert grep -qx '{broken' "$root/.pi/settings.json"

# Graph red-chair of the source: critical/major concerns settle or become follow-up nodes.
assert grep -q 'Red-chair the source itself' "$repo/skills/bp3g-frame/SKILL.md"
assert grep -q 'appended as a \*\*follow-up node\*\*' "$repo/skills/bp3g-frame/SKILL.md"
assert grep -q 'Risks is not a parking lot' "$repo/skills/bp3g-frame/SKILL.md"
assert grep -q 'Red-chair the source itself' "$root/.agents/skills/bp3g-frame/SKILL.md"

# Cycle autonomy (node-6): needs_fix rides, blocked pages.
assert grep -q 'next author cycle itself' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'named fix rides along verbatim' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'does not ask the owner about the cycle' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'cycle cap' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'scope change autonomously' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'Human attestation comes only from actual human words' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'next author cycle itself' "$root/.agents/skills/bp3g/SKILL.md"

# Bp3g-no-human: renders everywhere, pointer plus rails.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/bp3g-no-human/SKILL.md"
  assert grep -q 'skills/bp3g/SKILL.md' "$root/$h/skills/bp3g-no-human/SKILL.md"
done
assert grep -q 'means `/bp3g <graph>` per' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'BP3_DECIDER` stays unset' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'never takes `resume` or `delete`' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'park it' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'missing Acceptance rows' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'open' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'design question' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'make check` is green' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'the budget stopped it' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'goal_fin` stays the' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'usage_recorded` token totals' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'bp3 harness desk list' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'skill mode of `bp3g`' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'bp3g-no-human' "$repo/skills/bp3g/SKILL.md"
assert grep -q 'No-human never' "$root/.agents/skills/bp3g/SKILL.md"

# Fleet (node-9): footprint preflight, merge order, fleet budget, check-in report.
assert grep -q 'one fleet, not several queues' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'merge order before the queue starts' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'Footprint: the paths a graph declares' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'no declared footprint' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'Disjoint graphs run in parallel' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'refused at preflight, named' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'zero Runs spent on it' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'queues serially in a later fleet' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'The fleet never merges' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'predeclared merge order (fleet never merges)' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'one budget caps the whole fleet' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'every graph stops' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'one check-in list' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'grouped by graph, each with its inbox reason' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'same human decision appear as one' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'attested per node at resume time' "$repo/skills/bp3g-no-human/SKILL.md"
assert grep -q 'Disjoint graphs run in parallel' "$root/.agents/skills/bp3g-no-human/SKILL.md"

printf 'skills tests: ok (%s assertions)\n' "$checks"
