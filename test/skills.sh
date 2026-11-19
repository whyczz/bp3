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
# A self repo by derivation (dogfood.3): tracked src/quest + bin/bp3.
# The fixture names its target explicitly (BP3_TARGET); mode still
# derives from the fixture repo itself, never from a flag.
mkdir -p "$root/src/quest"
touch "$root/src/quest/.keep"
git -C "$root" init -q -b main
git -C "$root" config user.email t@t.t
git -C "$root" config user.name t
git -C "$root" add bin/bp3 src/quest
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
printf '\n// backdated render\n' >> "$root/.agents/workflows/induct-grade.js"
rejects "$root/bin/bp3" skills check
assert grep -q 'E_RENDER_STALE' "$work/out"
assert grep -q '.agents/workflows/induct-grade.js' "$work/out"
assert grep -q 'skills/induct/workflows/induct-grade.js' "$work/out"
"$root/bin/bp3" skills install --harness=all > /dev/null
"$root/bin/bp3" skills check > "$work/check-rerendered.json"
assert jq -e '.ok == true' "$work/check-rerendered.json"
assert jq -e '.defaultModel == "keep" and .skills == ["/extra","!**/ignored/**","!**/.agents/skills/add-bp3-skill/SKILL.md","!**/.agents/skills/add-yap-skill/SKILL.md","!**/.agents/skills/icebox/SKILL.md","!**/.agents/skills/induct/SKILL.md","!**/.agents/skills/induct-inline/SKILL.md","!**/.agents/skills/induct-yolo/SKILL.md","!**/.agents/skills/naming/SKILL.md","!**/.agents/skills/quest/SKILL.md","!**/.agents/skills/red-ink/SKILL.md","!**/.agents/skills/trial/SKILL.md","!**/.agents/skills/using-bp3/SKILL.md"]' "$root/.pi/settings.json"
# induct is the one conducting skill; retired traverse/bp3g names render nowhere.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/induct/SKILL.md"
  for retired in traverse traverse-no-human bp3g bp3g-frame bp3g-no-human bp3g-landing-demo; do
    assert test ! -e "$root/$h/skills/$retired"
  done
done
# The no-human skill renders beside induct in every harness.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/induct-yolo/SKILL.md"
done
for h in .pi .agents .claude; do
  assert test "$(yq --front-matter=extract '.description' "$root/$h/skills/add-yap-skill/SKILL.md")" = "$(yq --front-matter=extract '.description' "$source")"
  assert test -f "$root/$h/skills/quest/SKILL.md"
done
assert test -f "$root/.agents/workflows/node-loop.js"
assert cmp "$root/skills/induct/workflows/node-loop.js" "$root/.agents/workflows/node-loop.js"
assert test -f "$root/.agents/workflows/induct-node.js"
assert cmp "$root/skills/induct/workflows/induct-node.js" "$root/.agents/workflows/induct-node.js"
assert test ! -e "$root/.agents/workflows/induct-exp.js"
assert test ! -e "$root/.agents/workflows/bp3g-node.js"
assert test ! -e "$root/.agents/workflows/quest-land.js"
assert test -f "$root/.agents/workflows/induct-grade.js"
assert cmp "$root/skills/induct/workflows/induct-grade.js" "$root/.agents/workflows/induct-grade.js"
assert test -f "$root/.agents/workflows/induct-land.js"
assert cmp "$root/skills/induct/workflows/induct-land.js" "$root/.agents/workflows/induct-land.js"
assert test -f "$root/.claude/hooks.json"
assert jq -e '.hooks.SessionStart[0].hooks[0].command == "./bin/bp3 q hooks || true" and (.hooks | has("PreToolUse") and has("PostToolUse") and has("PostToolUseFailure") and has("PostLLMCall") and has("SubagentStart") and has("SubagentStop") and has("Stop") and has("SessionEnd"))' "$root/.claude/hooks.json"
assert test -f "$root/.muse/hooks.json"
assert cmp "$root/.claude/hooks.json" "$root/.muse/hooks.json"
assert test -f "$root/.claude/settings.json"
assert jq -e '.hooks.SessionStart[0].hooks[0].command == "./bin/bp3 q hooks || true" and (.hooks | has("PostLLMCall") | not)' "$root/.claude/settings.json"
mkdir -p "$root/.claude"
printf '{"keepMe":true}\n' > "$root/.claude/settings.json"
"$root/bin/bp3" skills install --harness=claude > /dev/null
assert jq -e '.keepMe == true and .hooks.SessionStart[0].hooks[0].command == "./bin/bp3 q hooks || true"' "$root/.claude/settings.json"
cp "$root/.pi/settings.json" "$work/settings.before"
"$root/bin/bp3" skills install --harness=pi > /dev/null
assert cmp "$work/settings.before" "$root/.pi/settings.json"
assert cmp "$root/skills/induct/workflows/node-loop.js" "$root/.agents/workflows/node-loop.js"
assert cmp "$root/skills/induct/workflows/induct-grade.js" "$root/.agents/workflows/induct-grade.js"
assert cmp "$root/skills/induct/workflows/induct-land.js" "$root/.agents/workflows/induct-land.js"

# Corrupt settings must fail BEFORE rewriting any installed files.
printf 'sentinel\n' > "$root/.pi/skills/quest/SKILL.md"
for settings in '{broken' '{"skills":null}' '{"skills":[1]}'; do
  printf '%s\n' "$settings" > "$root/.pi/settings.json"
  rejects "$root/bin/bp3" skills install --harness=all
  assert grep -qx sentinel "$root/.pi/skills/quest/SKILL.md"
done
# Non-Pi installations must leave project Pi settings alone.
printf '{broken' > "$root/.pi/settings.json"
"$root/bin/bp3" skills install --harness=codex > /dev/null
assert grep -qx '{broken' "$root/.pi/settings.json"

# Quest red-chair of the source: critical/major concerns settle or become follow-up nodes.
assert grep -q 'Red-chair the source itself' "$repo/skills/quest/SKILL.md"
assert grep -q 'appended as a \*\*follow-up node\*\*' "$repo/skills/quest/SKILL.md"
assert grep -q 'Risks is not a parking lot' "$repo/skills/quest/SKILL.md"
assert grep -q 'Red-chair the source itself' "$root/.agents/skills/quest/SKILL.md"

# Cycle autonomy (node-6): needs_fix rides, blocked pages.
assert grep -q 'next author cycle itself' "$repo/skills/induct/SKILL.md"
assert grep -q 'named fix rides along verbatim' "$repo/skills/induct/SKILL.md"
assert grep -q 'does not ask the owner about the cycle' "$repo/skills/induct/SKILL.md"
assert grep -q 'cycle cap' "$repo/skills/induct/SKILL.md"
assert grep -q 'scope change autonomously' "$repo/skills/induct/SKILL.md"
assert grep -q 'Human attestation comes only from actual human words' "$repo/skills/induct/SKILL.md"
assert grep -q 'next author cycle itself' "$root/.agents/skills/induct/SKILL.md"

# Induct-no-human: renders everywhere, pointer plus rails.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/induct-yolo/SKILL.md"
  assert grep -q 'skills/induct/SKILL.md' "$root/$h/skills/induct-yolo/SKILL.md"
done
assert grep -q 'means `/induct <quest>` per' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'BP3_DECIDER` stays unset' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'never takes `resume` or `delete`' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'park it' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'missing Acceptance rows' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'open' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'design question' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'make check-full` is green' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'the budget stopped it' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'goal_fin` stays the' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'usage_recorded` token totals' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'bp3 harness desk list' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'skill mode of `induct`' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'induct-yolo' "$repo/skills/induct/SKILL.md"
assert grep -q 'No-human never' "$root/.agents/skills/induct/SKILL.md"

# Fleet (node-9): footprint preflight, merge order, fleet budget, check-in report.
assert grep -q 'one fleet, not several queues' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'merge order before the queue starts' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'Footprint: the paths a quest declares' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'no declared footprint' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'Disjoint quests run in parallel' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'refused at preflight, named' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'zero Runs spent on it' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'queues serially in a later fleet' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'The fleet never merges' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'predeclared merge order (fleet never merges)' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'one budget caps the whole fleet' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'every quest stops' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'one check-in list' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'grouped by quest, each with its inbox reason' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'same human decision appear as one' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'attested per node at resume time' "$repo/skills/induct-yolo/SKILL.md"
assert grep -q 'Disjoint quests run in parallel' "$root/.agents/skills/induct-yolo/SKILL.md"

# test-pyramid tier.3: grade and land run the full gate. No line that
# grades, lands or hands off may name the inner loop (plain make check),
# and each conducting skill names make check-full.
gate_lines=$(grep -nE 'make check([^-]|$)' "$repo"/skills/*/SKILL.md "$repo"/skills/induct/workflows/*.js \
  | grep -iE 'grade|land|handoff|gate' || true)
[ -z "$gate_lines" ] || { echo "FAIL: a grade/land instruction names plain make check: $gate_lines" >&2; exit 1; }
checks=$((checks + 1))
for s in induct induct-inline induct-yolo using-bp3; do
  assert grep -q 'make check-full' "$repo/skills/$s/SKILL.md"
done

printf 'skills tests: ok (%s assertions)\n' "$checks"
