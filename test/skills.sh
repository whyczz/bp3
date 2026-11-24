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
assert jq -e '.defaultModel == "keep" and .skills == ["/extra","!**/ignored/**","!**/.agents/skills/add-bp3-skill/SKILL.md","!**/.agents/skills/add-yap-skill/SKILL.md","!**/.agents/skills/icebox/SKILL.md","!**/.agents/skills/induct/SKILL.md","!**/.agents/skills/induct-inline/SKILL.md","!**/.agents/skills/induct-inline-yolo/SKILL.md","!**/.agents/skills/induct-yolo/SKILL.md","!**/.agents/skills/naming/SKILL.md","!**/.agents/skills/quest/SKILL.md","!**/.agents/skills/red-ink/SKILL.md","!**/.agents/skills/using-bp3/SKILL.md","!**/.agents/skills/warden/SKILL.md"]' "$root/.pi/settings.json"
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
assert test -f "$root/.agents/hooks.json"
assert jq -e '.bp3.SessionStart[0].command == "../bin/bp3 q hooks || true" and .bp3.PreToolUse[0].hooks[0].command == "../bin/bp3 q hooks || true" and .bp3.PostToolUse[0].hooks[0].command == "../bin/bp3 q hooks || true" and .bp3.Stop[0].command == "../bin/bp3 q hooks || true"' "$root/.agents/hooks.json"
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
# Human touchpoints are irreducible: what a machine can do or observe is scripted.
assert grep -q 'Human touchpoints are irreducible' "$repo/skills/quest/SKILL.md"
assert grep -q 'one command the human starts' "$repo/skills/quest/SKILL.md"
# Icebox copy & delete: delete original docs/icebox/ entry right after copying to ICEBOX.md.
assert grep -q 'delete the original entry from `docs/icebox/` right away' "$repo/skills/quest/SKILL.md"
# Living run log split: LOG.md beside QUEST.md (never colliding with generated ledger.jsonl).
assert grep -qF 'companion `LOG.md` beside' "$repo/skills/quest/SKILL.md"
# Red-ink round 1 opener & closing plan slice: 10k-ft Shape gate before Output, Plan (nodes) at the end.
assert grep -qF 'PRFAQ-style Demo' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'Shape (10k-ft)' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'Plan (nodes)' "$repo/skills/red-ink/SKILL.md"
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
# grep -h: the filter must see the line only, never its file name
# (induct-grade.js, induct-land.js) or the repo path.
gate_grep() { grep -hnE 'make check([^-]|$)' "$@" | grep -iE 'grade|land|handoff|gate' || true; }
gate_lines=$(gate_grep "$repo"/skills/*/SKILL.md "$repo"/skills/induct/workflows/*.js)
[ -z "$gate_lines" ] || { echo "FAIL: a grade/land instruction names plain make check: $gate_lines" >&2; exit 1; }
checks=$((checks + 1))
# metric-followups skills.1: a plain line in a file whose name says
# "grade" passes; a line that grades with plain make check still fails.
# /dev/null makes it two files: grep names files only then, as it does
# over the real skill list, so without -h the plain line would fail.
mkdir -p "$work/gate-grade-land"
printf '// author cycles run make check\n' > "$work/gate-grade-land/induct-grade.js"
assert test -z "$(gate_grep "$work/gate-grade-land/induct-grade.js" /dev/null)"
printf '// grade with make check\n' >> "$work/gate-grade-land/induct-grade.js"
assert test -n "$(gate_grep "$work/gate-grade-land/induct-grade.js" /dev/null)"
for s in induct induct-inline induct-yolo using-bp3; do
  assert grep -q 'make check-full' "$repo/skills/$s/SKILL.md"
done

# constraints-context read.1: plans and grades read CONSTRAINTS.md and
# CONTEXT.md, in the sources and in every harness render. One rule each.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  q="$repo/$dir/quest/SKILL.md" r="$repo/$dir/red-ink/SKILL.md" i="$repo/$dir/induct-inline/SKILL.md"
  assert grep -q '^| 2 | Research the ground.*`CONSTRAINTS.md`.*`CONTEXT.md`' "$q"
  assert grep -q '^| 7 | .*\*\*constraints pass\*\*.*`/teach` pitch and the owner.s words before approval' "$q"
  assert grep -q '^| 7 | .*\*\*common-sense pass\*\*.*older than 90 days' "$q"
  assert grep -q 'step 7.s two fixed passes: the \*\*constraints pass\*\*' "$r"
  assert grep -q 'is `needs_fix`, \*\*owner class\*\*: never' "$i"
  assert grep -q 'new dated \*\*owner-words row\*\* in its Sign-off log is' "$i"
done
# CLAUDE.md and AGENTS.md stay identical and link both files.
assert cmp -s "$repo/CLAUDE.md" "$repo/AGENTS.md"
assert grep -q '\[CONSTRAINTS.md\](CONSTRAINTS.md)' "$repo/CLAUDE.md"
assert grep -q '\[CONTEXT.md\](CONTEXT.md)' "$repo/CLAUDE.md"

# metric-collectors read.1: conductors measure every grade, as evidence
# and never as a gate; the docs name the metrics door and its GENERATED
# file. In the sources and in every harness render.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ii="$repo/$dir/induct-inline/SKILL.md" ic="$repo/$dir/induct/SKILL.md" ub="$repo/$dir/using-bp3/SKILL.md"
  assert grep -q '^  `bp3 q <quest> metrics scrape`. It finds the grader' "$ii"
  assert grep -q 'evidence, never a gate: a `mismatched` grade is reported' "$ii"
  assert grep -q 'grade, run `bp3 q <quest> metrics scrape` once' "$ic"
  assert grep -q 'Measure with `./bin/bp3 q <quest> metrics r`' "$ub"
  assert grep -q '`metrics.jsonl` on each node.s state branch' "$ub"
  assert grep -q 'samples and moves no edge' "$ic"
  assert grep -q 'a finding to report, not a failed step' "$ub"
done
assert grep -q '^  metrics.jsonl          GENERATED' "$repo/CLAUDE.md"
assert grep -q 'and `metrics.jsonl` in a node' "$repo/CLAUDE.md"
assert grep -q '^\./bin/bp3 q <quest> metrics scrape|r' "$repo/CLAUDE.md"

# metric-followups skills.1: the skills describe the engine that exists.
# induct-yolo names the scrape as its one non-edge write, as induct does;
# using-bp3 lists real edges and doors only. Sources and every render.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  iy="$repo/$dir/induct-yolo/SKILL.md" ub="$repo/$dir/using-bp3/SKILL.md"
  assert grep -q '`metrics.jsonl` samples and moves no edge' "$iy"
  assert grep -q '`block` from any of the three' "$ub"
  assert grep -q '^   `--mechanical` `needs_fix` (an exact file, line and text fix,$' "$ub"
  assert test -z "$(grep -n '`cancel`' "$repo/$dir"/*/SKILL.md || true)"
  assert test -z "$(grep -nE 'q (show|list)|q create |--engine|bp3-writer' "$ub" "$iy" || true)"
  assert test -z "$(grep -n '^  writer, called by step children' "$iy" || true)"
  assert test -z "$(grep -nE 'outside quest folders|descend from the recorded|live in .fsm\.yaml.|Judgment moves need|move.s commit message' "$ub" || true)"
  assert grep -q '^   node dependency is `landed` or `deleted`' "$ub"
done

# pi-metrics skills.1: induct-inline names pi as a grader runtime, with
# the command, one session per grade, the join's first line, and the
# verdict cast as printed. In the source and every render.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ii="$repo/$dir/induct-inline/SKILL.md"
  assert grep -q '^  `pi -p --tools read,bash --session-id <fresh id> "<cold brief>"`\.$' "$ii"
  assert grep -q '^  session per grade: a fresh `--session-id` each time, never$' "$ii"
  assert grep -q 'whose first line names the node id$' "$ii"
  assert grep -q 'The verdict is the printed text, cast as returned\.' "$ii"
  assert grep -q 'one fresh grader: a subagent, or a headless pi when the owner names it' "$ii"
done

# induct-inline-as-default skills.1: induct-inline is the default way to
# run a quest, with background grades in grade desks, the rendered brief
# passed verbatim, the cast boundary, verify-then-cast, one session per
# quest. using-bp3 and induct point to it. Sources and every render.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ii="$repo/$dir/induct-inline/SKILL.md" ub="$repo/$dir/using-bp3/SKILL.md" id="$repo/$dir/induct/SKILL.md"
  assert grep -q 'This is$' "$ii"
  assert grep -q '^the default way to run a quest\. One quest\.' "$ii"
  assert grep -qF '`bp3 q <quest> n <node> brief --desk <grade desk path>` and pass' "$ii"
  assert grep -qF 'its `brief` text verbatim, adding nothing and leaving nothing' "$ii"
  assert grep -qF '`bp3 harness desk prepare <quest> <node> --run grade-<node>-c<cycle>-a<attempt> --commit <sha>`.' "$ii"
  assert grep -q 'at the \*\*cast boundary\*\* (right after that handoff, or when' "$ii"
  assert grep -q '^- \*\*Verify, then cast\*\*: before casting a verdict, check its grade$' "$ii"
  assert grep -q '^- One quest per session; one node being authored at a time;$' "$ii"
  assert test -z "$(grep -n 'one node in flight' "$ii" || true)"
  # skills.1 cycle 2 (grader): the verify, void, attempt, session and mode lines
  assert grep -q '^  desk\. `git rev-parse HEAD` must print the bound commit, and$' "$ii"
  assert grep -qF '`git status --short` must print nothing. Then cast the verdict' "$ii"
  assert grep -q '^  the verdict is void: cast nothing, keep the desk for the owner,$' "$ii"
  assert grep -q '^  and start the next attempt in a fresh desk\.$' "$ii"
  assert grep -qF 'Attempts count from `a1`; a grade dispatched again gets the next' "$ii"
  assert grep -qF 'per quest: this session runs this quest and no other' "$ii"
  assert grep -qF '(running, or finished with its verdict not yet cast): start one' "$ii"
  assert grep -qF 'seconds for graders, and counts `brief_verbatim` or' "$ii"
  assert grep -q '^`induct` when many independent nodes should run at once with$' "$ub"
  assert grep -q '^should run at once with workflow children, one desk per node\.$' "$id"
  assert grep -q '^use `induct-inline`, the default: this session authors each$' "$ub"
  assert grep -q '^`induct-inline` is the default way to run a quest: this session$' "$id"
done

# induct-inline-as-default skills.2: induct-inline-yolo runs one quest
# inline under no-human rails; it follows induct-inline as written and
# carries no numbered procedure of its own. Sources and every render.
assert grep -Eq '^CORE_SKILLS="([^"]* )?induct-inline-yolo( [^"]*)?"$' "$repo/bin/bp3"
for dir in skills .claude/skills .pi/skills .agents/skills; do
  iiy="$repo/$dir/induct-inline-yolo/SKILL.md" ii="$repo/$dir/induct-inline/SKILL.md" iy="$repo/$dir/induct-yolo/SKILL.md"
  assert test -f "$iiy"
  assert grep -q '^name: induct-inline-yolo$' "$iiy"
  assert grep -qF 'Follow the `induct-inline` skill' "$iiy"
  assert grep -qF 'SKILL.md`) procedure and rules as written' "$iiy"
  assert test -z "$(grep -nE '^[0-9]+\. ' "$iiy" || true)"
  assert grep -qF '**Never attest**: `BP3_DECIDER` stays unset for the whole run.' "$iiy"
  assert grep -q 'Never take `resume` or `delete`, never promote, never push:' "$iiy"
  assert grep -qF '**Park, never page**' "$iiy"
  assert grep -q 'only its dependents\.$' "$iiy"
  assert grep -qF '  | constraints-class `needs_fix` | stop, pitch to the owner (`/teach`) | park, with the pitch written in the report |' "$iiy"
  assert grep -qF '| no subagent tool | the owner judges | use pi only if the invocation names it, else park at `handed_off`; never self-grade |' "$iiy"
  assert grep -qF '**Budget**: an optional stated budget, in grades or wall minutes.' "$iiy"
  assert grep -q '^## Check-in report$' "$iiy"
  assert grep -q '^- One quest per invocation and one session per quest; fleets are$' "$iiy"
  assert grep -q '^`induct-inline-yolo` to run one quest this way with no human$' "$ii"
  assert grep -q '^with no human present, use `induct-inline-yolo`\.$' "$iy"
  # skills.2 cycle 2 (grader): the budget stop, the scope-change park, the report's items and sources
  assert grep -q '^  | scope change or acceptance-gate edit | the owner.s call | park |$' "$iiy"
  assert grep -qF 'When it is spent, start no new author step and no new grade' "$iiy"
  assert grep -q '^- nodes at `node_fin`' "$iiy"
  assert grep -q '^- parked nodes, each with its reason' "$iiy"
  assert grep -q '^- the metrics readout:' "$iiy"
  assert grep -q '^- desks still open' "$iiy"
  assert grep -qF '`bp3 q <quest> metrics r`, the last `bp3 q <quest> metrics scrape`' "$iiy"
  assert grep -q '`brief_verbatim` / `brief_edited` (from the last scrape.s tally);' "$iiy"
done

# fast-agy-induct agy.2: --harness=agy installs .agents/skills and .agents/hooks.json
agy_self="$work/agy-self"
mkdir -p "$agy_self/src/quest" "$agy_self/bin"
git -C "$agy_self" init -q
touch "$agy_self/src/quest/main.ml" "$agy_self/bin/bp3"
git -C "$agy_self" add -A && git -C "$agy_self" commit -qm init
BP3_TARGET="$agy_self" BP3_COMPLETIONS_DIR="$work/comp-agy" "$repo/bin/bp3" skills install --harness=agy >/dev/null
assert test -f "$agy_self/.agents/skills/induct-inline/SKILL.md"
assert test -f "$agy_self/.agents/hooks.json"
assert jq -e '.bp3.PreToolUse[0].hooks[0].command == "../bin/bp3 q hooks || true"' "$agy_self/.agents/hooks.json"
assert jq -e '.bp3.SessionStart[0].command == "../bin/bp3 q hooks || true"' "$agy_self/.agents/hooks.json"
agy_host="$work/agy-host"
mkdir -p "$agy_host"
git -C "$agy_host" init -q
touch "$agy_host/README.md"
git -C "$agy_host" add -A && git -C "$agy_host" commit -qm init
BP3_TARGET="$agy_host" BP3_COMPLETIONS_DIR="$work/comp-agy" "$repo/bin/bp3" skills install --harness=agy >/dev/null
assert jq -e '.bp3.PreToolUse[0].hooks[0].command == "bp3 q hooks || true"' "$agy_host/.agents/hooks.json"

# fast-agy-induct skills.1: induct-inline semantic invariants (receipt,
# severity gate, agy invoke_subagent model tiering, /swarm coordinator rule)
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ii="$repo/$dir/induct-inline/SKILL.md"
  assert grep -qF './scripts/receipt' "$ii"
  assert grep -qF 'Severity gate' "$ii"
  assert grep -qF '[critical]' "$ii"
  assert grep -qF '[minor]' "$ii"
  assert grep -qF 'invoke_subagent' "$ii"
  assert grep -qF '"flash"' "$ii"
  assert grep -qF '"pro"' "$ii"
  assert grep -qF '/swarm' "$ii"
  assert grep -qF 'Gemini' "$ii"
  assert grep -qF 'explicitly instructs you' "$ii"
  assert grep -qF 'fork: "coordinator"' "$ii"
  assert grep -qF 'workspace: "share"' "$ii"
  assert grep -qF 'NEVER' "$ii"
  assert grep -qF 'sole `bp3 q` writer' "$ii"
done

# warden-v0 skills.1: unified /warden replaces /trial across all harnesses
for dir in skills .claude/skills .pi/skills .agents/skills; do
  w="$repo/$dir/warden/SKILL.md"
  assert test -f "$w"
  assert test ! -e "$repo/$dir/trial"
  assert grep -qF 'FEEDBACK.md' "$w"
  assert grep -qF '<= 3' "$w"
  assert grep -qF 'Deterministic first' "$w"
  assert grep -qF 'Pruning check' "$w"
  assert grep -qF '1–2 files' "$w"
  assert grep -qF 'docs/icebox/' "$w"
  assert grep -qF 'owner disposes' "$w"
done
assert grep -qF '`warden`' "$repo/skills/quest/SKILL.md"
assert grep -qF '`warden`' "$repo/skills/induct/SKILL.md"

printf 'skills tests: ok (%s assertions)\n' "$checks"
