#!/bin/bash
# shellcheck disable=SC2016 # Literal JSON and Markdown in fixtures.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-skills-tests.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export BP3_DB="${BP3_DB:-$work/bp3.sqlite}"
export BP3_COMPLETIONS_DIR="${BP3_COMPLETIONS_DIR:-$work/completions}"
export BP3_Q_BIN="${BP3_Q_BIN:-$repo/_build/default/src/quest/main.exe}"
[ -x "$BP3_Q_BIN" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }
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
# compat.1: fail-fast skills install auto-registers "project with spaces" -> "project-with-spaces"
assert jq -e '([.repos[].name] | index("project-with-spaces") != null)' <<< "$("$repo/bin/bp3" repo list)" >/dev/null

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
# passes silently; a backdated SKILL.md render (body drift,
# missing skill, or missing release tag) refuses
# E_RENDER_STALE naming render and source; re-render restores freshness.
"$root/bin/bp3" skills check > "$work/check-fresh.json"
assert jq -e '.ok == true and .skills_checked > 0' "$work/check-fresh.json"
# Retired Muse JS workflows in downstream repos are pruned on skills install,
# and an empty .agents/workflows/ directory is removed cleanly.
mkdir -p "$root/.agents/workflows"
for wf in node-loop induct-grade induct-land induct-node bp3g-node; do
  printf '// legacy\n' > "$root/.agents/workflows/$wf.js"
done
"$root/bin/bp3" skills install --harness=all > "$work/prune-wf.out"
for wf in node-loop induct-grade induct-land induct-node bp3g-node; do
  assert test ! -e "$root/.agents/workflows/$wf.js"
  assert grep -q "pruned $wf" "$work/prune-wf.out"
done
assert test ! -e "$root/.agents/workflows"
printf '\n<!-- drifted skill body -->\n' >> "$root/.agents/skills/quest/SKILL.md"
rejects "$root/bin/bp3" skills check
assert grep -q 'E_RENDER_STALE' "$work/out"
assert grep -q '.agents/skills/quest/SKILL.md' "$work/out"
assert grep -q 'skills/quest/SKILL.md' "$work/out"
"$root/bin/bp3" skills install --harness=all > /dev/null
rm -rf "$root/.claude/skills/warden"
rejects "$root/bin/bp3" skills check
assert grep -q 'E_RENDER_STALE' "$work/out"
assert grep -q '.claude/skills/warden/SKILL.md' "$work/out"
mkdir -p "$work/share-rel"
printf '{"tag":"v0.3.1","version":"0.3.1"}\n' > "$work/share-rel/RELEASE"
BP3_SHARE_DIR="$work/share-rel" rejects "$root/bin/bp3" skills check
assert grep -q 'E_RENDER_STALE' "$work/out"
BP3_SHARE_DIR="$work/share-rel" "$root/bin/bp3" skills install --harness=all > /dev/null
BP3_SHARE_DIR="$work/share-rel" "$root/bin/bp3" skills check > "$work/check-tagged.json"
assert jq -e '.ok == true and .skills_checked > 0' "$work/check-tagged.json"
"$root/bin/bp3" skills install --harness=all > /dev/null
"$root/bin/bp3" skills check > "$work/check-rerendered.json"
assert jq -e '.ok == true' "$work/check-rerendered.json"
assert jq -e '.defaultModel == "keep" and .skills == ["/extra","!**/ignored/**","!**/.agents/skills/add-bp3-skill/SKILL.md","!**/.agents/skills/add-yap-skill/SKILL.md","!**/.agents/skills/icebox/SKILL.md","!**/.agents/skills/induct/SKILL.md","!**/.agents/skills/induct-yolo/SKILL.md","!**/.agents/skills/naming/SKILL.md","!**/.agents/skills/quest/SKILL.md","!**/.agents/skills/red-ink/SKILL.md","!**/.agents/skills/using-bp3/SKILL.md","!**/.agents/skills/warden/SKILL.md"]' "$root/.pi/settings.json"
# induct is the one conducting skill; retired traverse/bp3g/induct-inline names render nowhere.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/induct/SKILL.md"
  for retired in traverse traverse-no-human bp3g bp3g-frame bp3g-no-human bp3g-landing-demo induct-inline induct-inline-yolo; do
    assert test ! -e "$root/$h/skills/$retired"
  done
done
# Pruning legacy induct-inline* renders automatically on skills install (codebase-diet skills.1).
for s in induct-inline induct-inline-yolo; do
  mkdir -p "$root/.claude/skills/$s"
  printf -- '---\nname: %s\n---\n<!-- GENERATED from skills/%s/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->\nold\n' "$s" "$s" > "$root/.claude/skills/$s/SKILL.md"
done
"$root/bin/bp3" skills install --harness=claude > "$work/prune-inline.out"
assert test ! -e "$root/.claude/skills/induct-inline"
assert test ! -e "$root/.claude/skills/induct-inline-yolo"
assert grep -q 'pruned induct-inline' "$work/prune-inline.out"
assert grep -q 'pruned induct-inline-yolo' "$work/prune-inline.out"
# The no-human skill renders beside induct in every harness.
for h in .pi .agents .claude; do
  assert test -f "$root/$h/skills/induct-yolo/SKILL.md"
done
for h in .pi .agents .claude; do
  assert test "$(yq --front-matter=extract '.description' "$root/$h/skills/add-yap-skill/SKILL.md")" = "$(yq --front-matter=extract '.description' "$source")"
  assert test -f "$root/$h/skills/quest/SKILL.md"
done
assert test ! -e "$root/.agents/workflows"
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
# Stale retired bp3 skill exclusions in .pi/settings.json are pruned automatically
# while unrelated user entries stay untouched (codebase-diet warden fix).
jq '.skills += ["!**/.agents/skills/induct-inline/SKILL.md","!**/.agents/skills/induct-inline-yolo/SKILL.md","!**/.agents/skills/bp3g/SKILL.md"]' "$root/.pi/settings.json" > "$work/settings.stale"
mv "$work/settings.stale" "$root/.pi/settings.json"
"$root/bin/bp3" skills install --harness=pi > /dev/null
assert cmp "$work/settings.before" "$root/.pi/settings.json"

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
# Red-ink round 1 opener, per-slice 0-to-N 100%-confidence interview loop, before->after slice TL;DR, & closing plan slice.
assert grep -qF 'PRFAQ-style Demo' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'Shape (10k-ft)' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'Plan (nodes)' "$repo/skills/red-ink/SKILL.md"
assert grep -qF '100% confidence gate (per slice)' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'Zero questions is valid' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'Slice-settled TL;DR (`before -> after`)' "$repo/skills/red-ink/SKILL.md"
assert grep -qF 'AskUserQuestion' "$repo/skills/red-ink/SKILL.md"
assert grep -q 'Risks is not a parking lot' "$repo/skills/quest/SKILL.md"
assert grep -q 'Red-chair the source itself' "$root/.agents/skills/quest/SKILL.md"

# Cycle autonomy (node-6): needs_fix rides, blocked escalates at cycle cap.
assert grep -q 'cycle cap' "$repo/skills/induct/SKILL.md"
assert grep -q 'scope change autonomously' "$repo/skills/induct/SKILL.md"
assert grep -q 'human attestation comes only from actual human words' "$repo/skills/induct/SKILL.md"
assert grep -q 'induct-yolo' "$repo/skills/induct/SKILL.md"

# test-pyramid tier.3: grade and land run the full gate. No line that
# grades, lands or hands off may name the inner loop (plain make check),
# and each conducting skill names make check-full.
# grep -h: the filter must see the line only, never its file name
# or the repo path.
gate_grep() { grep -hnE 'make check([^-]|$)' "$@" | grep -iE 'grade|land|handoff|gate' || true; }
gate_lines=$(gate_grep "$repo"/skills/*/SKILL.md)
[ -z "$gate_lines" ] || { echo "FAIL: a grade/land instruction names plain make check: $gate_lines" >&2; exit 1; }
checks=$((checks + 1))
# metric-followups skills.1: a plain line in a file whose name says
# "grade" passes; a line that grades with plain make check still fails.
# /dev/null makes it two files: grep names files only then, as it does
# over the real skill list, so without -h the plain line would fail.
mkdir -p "$work/gate-grade-land"
printf '// author cycles run make check\n' > "$work/gate-grade-land/grade-probe.txt"
assert test -z "$(gate_grep "$work/gate-grade-land/grade-probe.txt" /dev/null)"
printf '// grade with make check\n' >> "$work/gate-grade-land/grade-probe.txt"
assert test -n "$(gate_grep "$work/gate-grade-land/grade-probe.txt" /dev/null)"
for s in induct induct-yolo using-bp3; do
  assert grep -q 'make check-full' "$repo/skills/$s/SKILL.md"
done

# constraints-context read.1: plans and grades read CONSTRAINTS.md and
# CONTEXT.md, in the sources and in every harness render. One rule each.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  q="$repo/$dir/quest/SKILL.md" r="$repo/$dir/red-ink/SKILL.md" i="$repo/$dir/induct/SKILL.md"
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
  ic="$repo/$dir/induct/SKILL.md" ub="$repo/$dir/using-bp3/SKILL.md"
  assert grep -q '^  `bp3 q <quest> metrics scrape`. It finds the grader' "$ic"
  assert grep -q 'evidence, never a gate: a `mismatched` grade' "$ic"
  assert grep -q 'Measure with `./bin/bp3 q <quest> metrics r`' "$ub"
  assert grep -q '`metrics.jsonl` on each node.s state branch' "$ub"
  assert grep -q 'samples and' "$ic"
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
  assert grep -q '`metrics.jsonl` samples and move no edge' "$iy"
  assert grep -q '`block` from any of the three' "$ub"
  assert grep -q '^   `--mechanical` `needs_fix` (an exact file, line and text fix,$' "$ub"
  assert test -z "$(grep -n '`cancel`' "$repo/$dir"/*/SKILL.md || true)"
  assert test -z "$(grep -nE 'q (show|list)|q create |--engine|bp3-writer' "$ub" "$iy" || true)"
  assert test -z "$(grep -nE 'induct-grade|node-loop|induct-node|induct-land|induct-inline' "$repo/$dir"/*/SKILL.md || true)"
  assert test -z "$(grep -nE 'outside quest folders|descend from the recorded|live in .fsm\.yaml.|Judgment moves need|move.s commit message' "$ub" || true)"
  assert grep -q '^   node dependency is `landed` or `deleted`' "$ub"
done

# pi-metrics skills.1: induct names pi as a grader runtime, with
# the command, one session per grade, the join's first line, and the
# verdict cast as printed. In the source and every render.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ic="$repo/$dir/induct/SKILL.md"
  assert grep -q '^  `pi -p --tools read,bash --session-id <fresh id> "<cold brief>"`\.$' "$ic"
  assert grep -q '^  session per grade: a fresh `--session-id` each time, never$' "$ic"
  assert grep -q 'whose first line names the node id$' "$ic"
  assert grep -q 'The verdict is the printed text, cast as returned\.' "$ic"
  assert grep -q 'fresh grader in the background' "$ic"
done

# codebase-diet skills.1: induct (promoted from induct-inline) is the
# single conducting skill, with background grades in grade desks, the
# rendered brief passed verbatim, the cast boundary, verify-then-cast,
# and one session per quest. using-bp3 points to it.
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ic="$repo/$dir/induct/SKILL.md" ub="$repo/$dir/using-bp3/SKILL.md"
  assert grep -qF '`bp3 q <quest> n <node> brief --desk <grade desk path>` and pass' "$ic"
  assert grep -qF 'its `brief` text verbatim, adding nothing and leaving nothing' "$ic"
  assert grep -qF '`bp3 harness desk prepare <quest> <node> --run grade-<node>-c<cycle>-a<attempt> --commit <sha>`.' "$ic"
  assert grep -q 'at the \*\*cast boundary\*\* (right after that handoff, or when' "$ic"
  assert grep -q '^- \*\*Verify, then cast\*\*: before casting a verdict, check its grade$' "$ic"
  assert grep -q '^- One quest per session; one node being authored at a time;$' "$ic"
  assert test -z "$(grep -n 'one node in flight' "$ic" || true)"
  assert grep -q '^  desk\. `git rev-parse HEAD` must print the bound commit, and$' "$ic"
  assert grep -qF '`git status --short` must print nothing. Then cast the verdict' "$ic"
  assert grep -q '^  the verdict is void: cast nothing, keep the desk for the owner,$' "$ic"
  assert grep -q '^  and start the next attempt in a fresh desk\.$' "$ic"
  assert grep -qF 'Attempts count from `a1`; a grade dispatched again gets the next' "$ic"
  assert grep -qF 'per quest: this session runs this quest and no other' "$ic"
  assert grep -qF '(running, or finished with its verdict not yet cast): start one' "$ic"
  assert grep -qF 'seconds for graders, and counts `brief_verbatim` or' "$ic"
  assert grep -q '^use `induct`, the default: this session authors each$' "$ub"
done

# induct-yolo (promoted from induct-inline-yolo): runs one quest under
# no-human rails; follows induct as written and carries no numbered
# procedure of its own. Sources and every render.
assert grep -Eq '^CORE_SKILLS="([^"]* )?induct-yolo( [^"]*)?"$' "$repo/bin/bp3"
for dir in skills .claude/skills .pi/skills .agents/skills; do
  iy="$repo/$dir/induct-yolo/SKILL.md" ic="$repo/$dir/induct/SKILL.md"
  assert test -f "$iy"
  assert grep -q '^name: induct-yolo$' "$iy"
  assert grep -qF 'Follow the `induct` skill (`skills/induct/SKILL.md`)' "$iy"
  assert grep -qF 'procedure and rules as written' "$iy"
  assert test -z "$(grep -nE '^[0-9]+\. ' "$iy" || true)"
  assert grep -qF '**Never attest**: `BP3_DECIDER` stays unset for the whole run.' "$iy"
  assert grep -q 'Never take `resume` or `delete`, never promote, never push:' "$iy"
  assert grep -qF '**Park, never page**' "$iy"
  assert grep -q 'only its dependents\.$' "$iy"
  assert grep -qF '  | constraints-class `needs_fix` | stop, pitch to the owner (`/teach`) | park, with the pitch written in the report |' "$iy"
  assert grep -qF '| no subagent tool | the owner judges | use pi only if the invocation names it, else park at `handed_off`; never self-grade |' "$iy"
  assert grep -qF '**Budget**: an optional stated budget, in grades or wall minutes.' "$iy"
  assert grep -q '^## Check-in report$' "$iy"
  assert grep -q '^- One quest per invocation and one session per quest\.$' "$iy"
  assert grep -q '^Use `induct-yolo` to run one quest this way with no human present,$' "$ic"
  assert grep -q '^  | scope change or acceptance-gate edit | the owner.s call | park |$' "$iy"
  assert grep -qF 'When it is spent, start no new author step and no new grade' "$iy"
  assert grep -q '^- nodes at `node_fin`' "$iy"
  assert grep -q '^- parked nodes, each with its reason' "$iy"
  assert grep -q '^- the metrics readout:' "$iy"
  assert grep -q '^- desks still open' "$iy"
  assert grep -qF '`bp3 q <quest> metrics r`, the last `bp3 q <quest> metrics scrape`' "$iy"
  assert grep -q '`brief_verbatim` / `brief_edited` (from the last scrape.s tally);' "$iy"
done

# fast-agy-induct agy.2: --harness=agy installs .agents/skills and .agents/hooks.json
agy_self="$work/agy-self"
mkdir -p "$agy_self/src/quest" "$agy_self/bin"
git -C "$agy_self" init -q
touch "$agy_self/src/quest/main.ml" "$agy_self/bin/bp3"
git -C "$agy_self" add -A && git -C "$agy_self" commit -qm init
BP3_TARGET="$agy_self" BP3_COMPLETIONS_DIR="$work/comp-agy" "$repo/bin/bp3" skills install --harness=agy >/dev/null
assert test -f "$agy_self/.agents/skills/induct/SKILL.md"
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

# fast-agy-induct skills.1: induct semantic invariants (receipt,
# severity gate, agy invoke_subagent model tiering, /swarm coordinator rule)
for dir in skills .claude/skills .pi/skills .agents/skills; do
  ic="$repo/$dir/induct/SKILL.md"
  assert grep -qF './scripts/receipt' "$ic"
  assert grep -qF 'Severity gate' "$ic"
  assert grep -qF '[critical]' "$ic"
  assert grep -qF '[minor]' "$ic"
  assert grep -qF 'invoke_subagent' "$ic"
  assert grep -qF '"flash"' "$ic"
  assert grep -qF '"pro"' "$ic"
  assert grep -qF '/swarm' "$ic"
  assert grep -qF 'Gemini' "$ic"
  assert grep -qF 'explicitly instructs you' "$ic"
  assert grep -qF 'fork: "coordinator"' "$ic"
  assert grep -qF 'workspace: "share"' "$ic"
  assert grep -qF 'NEVER' "$ic"
  assert grep -qF 'sole `bp3 q` writer' "$ic"
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

# quest-promote-release skills.1: bump: frontmatter and bp3 release across harnesses
for dir in skills .claude/skills .pi/skills .agents/skills; do
  assert grep -qF 'bump: major | minor | patch | none' "$repo/$dir/quest/SKILL.md"
  assert grep -qF 'RELEASING.md' "$repo/$dir/quest/SKILL.md"
  assert grep -qF 'bp3 release <quest> --dry-run' "$repo/$dir/warden/SKILL.md"
  assert grep -qF 'BP3_DECIDER=human bp3 release <quest>' "$repo/$dir/warden/SKILL.md"
  assert grep -qF 'bp3 release' "$repo/$dir/using-bp3/SKILL.md"
  assert grep -qF -- '--commit <sha>' "$repo/$dir/using-bp3/SKILL.md"
  assert grep -qF 'BP3_DECIDER=human' "$repo/$dir/using-bp3/SKILL.md"
done

# sqlite-control-plane skills.1: cross-repo bp3 ticket / repo / db across harnesses
for dir in skills .claude/skills .pi/skills .agents/skills; do
  assert grep -qF 'bp3 ticket add --to bp3' "$repo/$dir/warden/SKILL.md"
  assert grep -qF 'bp3 ticket list --to bp3' "$repo/$dir/warden/SKILL.md"
  assert grep -qF 'bp3 ticket' "$repo/$dir/using-bp3/SKILL.md"
  assert grep -qF 'bp3 repo' "$repo/$dir/using-bp3/SKILL.md"
  assert grep -qF 'bp3 db info' "$repo/$dir/using-bp3/SKILL.md"
done

printf 'skills tests: ok (%s assertions)\n' "$checks"
