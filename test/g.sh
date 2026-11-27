#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
sed 's/^max_cycles: .*/max_cycles: 1/' "$work/repo/plans/default.yaml" > "$work/repo/plans/default.yaml.tmp"; mv "$work/repo/plans/default.yaml.tmp" "$work/repo/plans/default.yaml"  # fixtures assert one review round
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
export BP3_DESKS_DIR="$work/desks"
BP3_VER=$(sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' "$root/src/quest/gitx.ml" | head -1)
IFS=. read -r _bp3_maj _bp3_min _bp3_pat <<< "$BP3_VER"
NEXT_MINOR="${_bp3_maj}.$((_bp3_min + 1)).0"
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
quest_alias() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- create / read verdict shapes, both spellings ---
out=$(q c demo)
echo "$out" | jq -e '.ok == true and .quest == "demo" and .state == "proposed"' >/dev/null || fail "quest create shape: $out"
out=$(q create demo2)
echo "$out" | jq -e '.ok == true and .state == "proposed"' >/dev/null || fail "quest create alias: $out"
out=$(quest_alias r demo)
echo "$out" | jq -e '.ok == true and .quest == "demo" and .state == "proposed" and (.nodes | type == "array") and (.inbox | type == "array") and has("rollup")' >/dev/null || fail "quest read shape: $out"
out=$(q r)
echo "$out" | jq -e '.ok == true and (.quests | length >= 2)' >/dev/null || fail "quest list: $out"

out=$(q demo c parser-fix)
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 1' >/dev/null || fail "node create: $out"
out=$(q demo create parser-fix2)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "node create alias: $out"
out=$(q demo r parser-fix)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "node read: $out"
out=$(q demo read parser-fix)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "node read alias: $out"

# --- rename-back: old g door gone (tombstone), canonical nested address, bp3 n door ---
if out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 g demo r parser-fix 2>&1); then fail "old g door accepted"; fi
if out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 quest demo r parser-fix 2>&1); then fail "old quest door accepted"; fi
out=$(q demo n parser-fix r)
echo "$out" | jq -e '.ok == true and .quest == "demo" and .node == "parser-fix" and .state == "todo" and (has("graph") | not) and (has("exp") | not)' >/dev/null || fail "nested node read: $out"
out=$(q demo n parser-fix)
echo "$out" | jq -e '.ok == true and .node == "parser-fix"' >/dev/null || fail "nested bare node read: $out"
# Retired doors (bp3 n, bp3 e, bp3 harness supervisor) refuse E_USAGE (exit 2).
rc=0; out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 n r 2>&1) || rc=$?
[ "$rc" -eq 2 ] || fail "retired bp3 n rc=$rc: $out"
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "retired bp3 n code: $out"
rc=0; out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 e handoff --commit HEAD --reason x 2>&1) || rc=$?
[ "$rc" -eq 2 ] || fail "retired bp3 e rc=$rc: $out"
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "retired bp3 e code: $out"
rc=0; out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness supervisor demo 2>&1) || rc=$?
[ "$rc" -eq 2 ] || fail "retired bp3 harness supervisor rc=$rc: $out"
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "retired bp3 harness supervisor code: $out"

# --- strict argv: dup flag, unknown flag, stray positional -> usage before write ---
before=$(git show bp3/node/demo/parser-fix:docs/quests/demo/nodes/parser-fix/ledger.jsonl | wc -l)
if out=$(q demo u parser-fix handoff --commit abc --reason x --reason y 2>&1); then fail "dup flag accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "dup flag code: $out"
if out=$(q demo u parser-fix handoff --commit abc --reason x --bogus y 2>&1); then fail "unknown flag accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "unknown flag code: $out"
if out=$(q demo u parser-fix handoff extra --commit abc --reason x 2>&1); then fail "stray positional accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "stray code: $out"
after=$(git show bp3/node/demo/parser-fix:docs/quests/demo/nodes/parser-fix/ledger.jsonl | wc -l)
[ "$before" = "$after" ] || fail "strict argv wrote to ledger"

# --- refusal: land from todo, ledger unchanged ---
if out=$(q demo u parser-fix land --reason "too early" 2>&1); then fail "land from todo accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "todo" and .error.facts.edge == "land" and (.error.facts.legal_edges | index("handoff") != null) and (.error.guidance | length > 0)' >/dev/null || fail "illegal edge facts: $out"
after=$(git show bp3/node/demo/parser-fix:docs/quests/demo/nodes/parser-fix/ledger.jsonl | wc -l)
[ "$before" = "$after" ] || fail "refusal ledgered"

# --- identity: unset -> unknown + warning; invalid -> fail fast ---
out=$(env -u BP3_HARNESS -u BP3_MODEL BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q demo c id-node)
echo "$out" | jq -e '.ok == true and (.warnings | index("W_IDENTITY_UNKNOWN") != null)' >/dev/null || fail "identity warning: $out"
git show bp3/node/demo/id-node:docs/quests/demo/nodes/id-node/ledger.jsonl | tail -1 | jq -e --arg v "$BP3_VER" '.harness == "unknown" and .model == "unknown" and .bp3_version == $v' >/dev/null || fail "identity ledger unknown"
if out=$(BP3_HARNESS=bogus BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q demo r parser-fix 2>&1); then fail "invalid harness accepted"; fi
echo "$out" | jq -e '.error.code == "E_IDENTITY"' >/dev/null || fail "identity code: $out"
for h in agy claude pi; do
  BP3_HARNESS="$h" BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q demo r parser-fix | jq -e '.ok == true' >/dev/null || fail "harness $h rejected"
done

# --- run-id: BP3_RUN_ID from env stamps verdict + ledger; unset is absent ---
out=$(BP3_RUN_ID=run-42 BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q c runq)
echo "$out" | jq -e '.ok == true and .run_id == "run-42"' >/dev/null || fail "run-id quest verdict: $out"
out=$(BP3_RUN_ID=run-42 BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q runq c rid-node)
echo "$out" | jq -e '.ok == true and .run_id == "run-42"' >/dev/null || fail "run-id node verdict: $out"
git show bp3/node/runq/rid-node:docs/quests/runq/nodes/rid-node/ledger.jsonl | tail -1 | jq -e '.run_id == "run-42" and .harness == "muse-code"' >/dev/null || fail "run-id ledger set"
out=$(BP3_RUN_ID=run-42 BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q runq r rid-node)
echo "$out" | jq -e '.ok == true and .run_id == "run-42"' >/dev/null || fail "run-id read verdict: $out"
out=$(env -u BP3_RUN_ID BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q runq c rid-unset)
echo "$out" | jq -e '.ok == true and (has("run_id") | not)' >/dev/null || fail "run-id unset verdict: $out"
git show bp3/node/runq/rid-unset:docs/quests/runq/nodes/rid-unset/ledger.jsonl | tail -1 | jq -e 'has("run_id") | not' >/dev/null || fail "run-id ledger unset"
out=$(env -u BP3_RUN_ID BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q runq r rid-unset)
echo "$out" | jq -e '.ok == true and (has("run_id") | not)' >/dev/null || fail "run-id unset read verdict: $out"
out=$(env -u BP3_HARNESS -u BP3_MODEL -u BP3_RUN_ID BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q runq c rid-unknown)
echo "$out" | jq -e '.ok == true and (has("run_id") | not) and (.warnings | index("W_IDENTITY_UNKNOWN") != null)' >/dev/null || fail "run-id unset identity warning: $out"
git show bp3/node/runq/rid-unknown:docs/quests/runq/nodes/rid-unknown/ledger.jsonl | tail -1 | jq -e '(has("run_id") | not) and .harness == "unknown"' >/dev/null || fail "run-id unset unknown ledger"

# --- happy path handoff/grade auto-land (default land: auto) + retired verify refusal ---
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
out=$(q demo u parser-fix handoff --commit "$B" --reason "first cut")
echo "$out" | jq -e '.ok == true and .state == "handed_off" and .cycle == 1 and (.legal_edges | index("grade") != null) and (.legal_edges | index("verify") == null)' >/dev/null || fail "handoff: $out"
# Standalone verify edge is retired -> E_USAGE
if out=$(q demo u parser-fix verify --verdict pass --reason "retired" 2>&1); then fail "retired verify accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "retired verify code: $out"
# grade --verdict ship auto-lands directly on default plan (2 edges: handoff -> grade)
out=$(q demo update parser-fix grade --verdict ship --reason "looks right")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "node_fin" and .legal_edges == []' >/dev/null || fail "grade ship auto-lands: $out"
out=$(q r demo)
echo "$out" | jq -e '.ok == true and (.nodes[] | select(.node == "parser-fix") | .state == "landed" and .fin == "node_fin")' >/dev/null || fail "read after land: $out"

# --- land: manual opt-in preserves approved -> land; direct auto-lands on handoff ---
printf 'goal_type: manual\nmax_cycles: 1\ngrade:\n  required: true\nland: manual\n' > plans/manual.yaml
git add plans/manual.yaml; git commit -qm manual-plan
out=$(q c manual-demo --type manual)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "manual quest create: $out"
out=$(q manual-demo c mn1)
out=$(q manual-demo u mn1 handoff --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "manual handoff: $out"
out=$(q manual-demo u mn1 grade --verdict ship --reason "looks right")
echo "$out" | jq -e '.ok == true and .state == "approved" and (.legal_edges | index("land") != null)' >/dev/null || fail "manual grade approves: $out"
out=$(q manual-demo u mn1 land --reason "ship it")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "node_fin"' >/dev/null || fail "manual land: $out"
# direct plan (grade.required: false, land: auto): handoff lands directly
out=$(q c direct-demo --type direct)
out=$(q direct-demo c dn1)
out=$(q direct-demo u dn1 handoff --commit "$B" --reason "direct ship")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "node_fin"' >/dev/null || fail "direct handoff auto-lands: $out"

# --- mig.1 compat: frozen pre-rename ledger folds to new words, file untouched ---
out=$(q demo c compat-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "compat create: $out"
append_ledger_line() { # $1 node $2 json-line
  local br="bp3/node/demo/$1" path="docs/quests/demo/nodes/$1/ledger.jsonl" tip idx led blob tree nt
  tip=$(git rev-parse "$br")
  led=$(git show "$br:$path")
  idx=$(mktemp)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  blob=$(printf '%s\n%s\n' "$led" "$2" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  nt=$(git commit-tree "$tree" -p "$tip" -m "compat fixture $1")
  git update-ref "refs/heads/$br" "$nt" "$tip"
  rm -f "$idx"
}
compat_tip_before=$(git rev-parse bp3/node/demo/compat-node)
append_ledger_line compat-node "{\"ts\":\"2026-01-01T00:00:00Z\",\"edge\":\"submit\",\"from\":\"todo\",\"to\":\"submitted\",\"cycle\":1,\"commit\":\"$B\",\"verdict\":null,\"reason\":\"frozen\",\"harness\":\"t\",\"model\":\"t\",\"bp3_version\":\"0.2.0\"}"
out=$(q demo r compat-node)
echo "$out" | jq -e --arg c "$B" '.state == "handed_off" and .cycle == 1 and .commit == $c and (.legal_edges | index("grade") != null) and (.legal_edges | index("verify") == null)' >/dev/null || fail "compat old submit folds handed_off: $out"
append_ledger_line compat-node "{\"ts\":\"2026-01-01T00:01:00Z\",\"edge\":\"review\",\"from\":\"submitted\",\"to\":\"submitted\",\"cycle\":1,\"commit\":\"$B\",\"verdict\":\"ship\",\"reason\":\"frozen\",\"harness\":\"t\",\"model\":\"t\",\"bp3_version\":\"0.2.0\"}"
append_ledger_line compat-node "{\"ts\":\"2026-01-01T00:02:00Z\",\"edge\":\"check\",\"from\":\"submitted\",\"to\":\"approved\",\"cycle\":1,\"commit\":\"$B\",\"verdict\":\"pass\",\"reason\":\"frozen\",\"harness\":\"t\",\"model\":\"t\",\"bp3_version\":\"0.2.0\"}"
out=$(q demo r compat-node)
echo "$out" | jq -e '.state == "approved" and .cycle == 1' >/dev/null || fail "compat old grade/verify fold approved: $out"
# reads never rewrite the frozen file
q demo r compat-node >/dev/null
[ "$(git rev-parse bp3/node/demo/compat-node)" != "$compat_tip_before" ] || fail "compat fixture did not land"
compat_tip_read=$(git rev-parse bp3/node/demo/compat-node)
q r demo >/dev/null
[ "$(git rev-parse bp3/node/demo/compat-node)" = "$compat_tip_read" ] || fail "read rewrote frozen ledger"
# old verbs refuse as unknown edges, ledger unchanged
for old in submit review check; do
  if out=$(q demo u compat-node "$old" --commit "$B" --verdict ship --reason "old words" 2>&1); then fail "old edge $old accepted"; fi
  echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "old edge $old code: $out"
done
[ "$(git rev-parse bp3/node/demo/compat-node)" = "$compat_tip_read" ] || fail "old edge refusal ledgered"
# mixed vocab in one ledger (this quest's own shape): new handoff, old verdicts
out=$(q demo c mixed-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "mixed create: $out"
out=$(q demo u mixed-node handoff --commit "$B" --reason "new words")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "mixed handoff: $out"
append_ledger_line mixed-node "{\"ts\":\"2026-01-01T00:03:00Z\",\"edge\":\"review\",\"from\":\"submitted\",\"to\":\"submitted\",\"cycle\":1,\"commit\":\"$B\",\"verdict\":\"ship\",\"reason\":\"frozen\",\"harness\":\"t\",\"model\":\"t\",\"bp3_version\":\"0.2.0\"}"
append_ledger_line mixed-node "{\"ts\":\"2026-01-01T00:04:00Z\",\"edge\":\"check\",\"from\":\"submitted\",\"to\":\"approved\",\"cycle\":1,\"commit\":\"$B\",\"verdict\":\"pass\",\"reason\":\"frozen\",\"harness\":\"t\",\"model\":\"t\",\"bp3_version\":\"0.2.0\"}"
out=$(q demo r mixed-node)
echo "$out" | jq -e '.state == "approved" and .cycle == 1' >/dev/null || fail "mixed vocab folds approved: $out"

# --- fin report words: node_fin above; goal_fin when rollup landed ---
out=$(q c fin-demo)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "fin quest create: $out"
out=$(q fin-demo c only-node)
echo "$out" | jq -e '.state == "todo" and .fin == null' >/dev/null || fail "fin node create: $out"
out=$(q fin-demo u only-node handoff --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "fin handoff: $out"
out=$(q fin-demo u only-node grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "landed" and .fin == "node_fin"' >/dev/null || fail "fin auto-land: $out"
out=$(q r fin-demo)
echo "$out" | jq -e '.rollup == "landed" and .fin == "goal_fin" and (.nodes[0] | .state == "landed" and .fin == "node_fin")' >/dev/null || fail "goal_fin read: $out"
out=$(q r demo)
echo "$out" | jq -e '.fin == null' >/dev/null || fail "unfinished quest has no goal_fin: $out"

# --- blocked inbox after needs_fix at max_cycles (default max_cycles=1) ---
out=$(q demo u parser-fix2 handoff --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "submit2: $out"
out=$(q demo u parser-fix2 grade --verdict needs_fix --reason "broken")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "needs_fix blocks at max: $out"
out=$(q r demo)
echo "$out" | jq -e '(.inbox | length == 1) and .inbox[0].quest == "demo" and .inbox[0].node == "parser-fix2" and .inbox[0].reason == "broken" and (.inbox[0] | has("checkpoint")) and (.inbox[0] | has("cycle")) and (.inbox[0] | has("since"))' >/dev/null || fail "blocked inbox: $out"

# --- pure-grade (followup.5 + fsm.1): optional --verify-verdict compat; mechanical never blocks ---
out=$(q demo c pure-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "pure create: $out"
out=$(q demo u pure-node handoff --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "pure handoff: $out"
out=$(q demo u pure-node grade --verdict ship --verify-verdict pass --commit "$B" --reason "grade ship; verify pass")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "node_fin" and .cycle == 1' >/dev/null || fail "combined cast auto-lands: $out"
git show bp3/node/demo/pure-node:docs/quests/demo/nodes/pure-node/ledger.jsonl | jq -se '([.[] | select(.edge == "grade")] | length == 1) and ([.[] | select(.edge == "grade")][0] | .verify_verdict == "pass" and .to == "landed")' >/dev/null || fail "combined cast is one ledger line"
# --verify-verdict fail still overrides ship to needs_fix path (never accidentally lands)
out=$(q demo c vf-fail-node)
out=$(q demo u vf-fail-node handoff --commit "$B" --reason "work")
out=$(q demo u vf-fail-node grade --verdict ship --verify-verdict fail --mechanical --reason "receipt failed")
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 2' >/dev/null || fail "verify-verdict fail must not ship: $out"
out=$(q demo c mech-node)
out=$(q demo u mech-node handoff --commit "$B" --reason "work")
out=$(q demo u mech-node grade --verdict needs_fix --mechanical --reason "skills/induct/SKILL.md:12 stale term")
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 2' >/dev/null || fail "mechanical needs_fix returns todo at cap, never blocked: $out"
git show bp3/node/demo/mech-node:docs/quests/demo/nodes/mech-node/ledger.jsonl | tail -1 | jq -e '.to == "todo" and .fix_class == "mechanical"' >/dev/null || fail "mechanical ledger line"
out=$(q r demo)
echo "$out" | jq -e '(.inbox | map(select(.node == "mech-node")) | length == 0)' >/dev/null || fail "mechanical writes no blocked line: $out"
out=$(q demo u mech-node handoff --commit "$B" --reason "work again")
out=$(q demo u mech-node grade --verdict needs_fix --reason "same row still failing")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "disagreement blocks at cap: $out"
out=$(q demo c misuse-node)
out=$(q demo u misuse-node handoff --commit "$B" --reason "work")
if out=$(q demo u misuse-node verify --verdict pass --verify-verdict pass --reason "bad combo" 2>&1); then fail "retired verify accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "verify-verdict misuse code: $out"

# table format contains same facts
tbl=$(q r demo --format table)
echo "$tbl" | grep -q "demo" || fail "table missing quest"
echo "$tbl" | grep -q "parser-fix2" || fail "table missing blocked node"
echo "$tbl" | grep -q "blocked" || fail "table missing blocked state"

# rendered tables: header row, aligned columns, short commits, counts
echo "$tbl" | sed -n 1p | grep -q "^quest demo \[proposed\] rollup: " || fail "quest table header: $tbl"
echo "$tbl" | sed -n 2p | grep -Eq '^node +state +cycle +commit +changes$' || fail "quest table columns: $tbl"
echo "$tbl" | grep -Eq '^parser-fix +landed +1 +[0-9a-f]{7} +\+[0-9]+ u[0-9]+ -[0-9]+$' || fail "quest table landed row: $tbl"
if echo "$tbl" | grep -q '="'; then fail "quest table dumps inline JSON: $tbl"; fi
if echo "$tbl" | grep -q 'legal_edges'; then fail "quest table dumps raw fields: $tbl"; fi
etbl=$(q demo r parser-fix --format table)
echo "$etbl" | sed -n 1p | grep -Eq '^demo / parser-fix — landed, cycle 1, commit [0-9a-f]{7}, legal: ' || fail "node table summary: $etbl"
echo "$etbl" | sed -n 2p | grep -Eq '^change +path$' || fail "node table columns: $etbl"
echo "$etbl" | grep -Eq '^\+ +b\.txt$' || fail "node table change row: $etbl"
# null commit / unknown changes render as - / ?, never crash
out=$(q demo c null-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "null-node create: $out"
ntbl=$(q demo r null-node --format table)
echo "$ntbl" | sed -n 1p | grep -q 'commit -, legal: handoff, block, delete' || fail "null commit cell: $ntbl"
echo "$ntbl" | grep -q '? changes unknown' || fail "unknown changes cell: $ntbl"
qtbl_null=$(q r demo --format table)
echo "$qtbl_null" | grep -Eq '^null-node +todo +1 +- +\?$' || fail "quest table null row: $qtbl_null"

# tree format: the human view (git-status alphabet: + todo, u in-flight, - deleted, blank landed)
tree=$(q r demo --format tree)
echo "$tree" | grep -q "^demo " || fail "tree missing quest root: $tree"
echo "$tree" | grep -q "u parser-fix2 - blocked" || fail "tree blocked marker: $tree"
echo "$tree" | grep -q "parser-fix - landed (node_fin)" || fail "tree node_fin: $tree"
echo "$tree" | grep -q "(human owed)" || fail "tree human owed: $tree"
echo "$tree" | grep -q "human owed:" || fail "tree inbox header: $tree"
etree=$(q demo r parser-fix2 --format tree)
echo "$etree" | grep -q "u parser-fix2 - blocked" || fail "node tree marker: $etree"
echo "$etree" | grep -q "legal: resume, delete" || fail "node tree legal edges: $etree"

# delete spellings (d / delete) on a scratch node
out=$(q demo c scratch-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "scratch create: $out"
out=$(q demo d scratch-node --reason "no longer needed")
echo "$out" | jq -e '.ok == true and .state == "deleted"' >/dev/null || fail "node delete d: $out"
out=$(q demo create scratch-node2)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "scratch2 create: $out"
out=$(q demo delete scratch-node2 --reason "gone")
echo "$out" | jq -e '.ok == true and .state == "deleted"' >/dev/null || fail "node delete alias: $out"

# --- scenario helpers ---
qa() { env BP3_MODEL=executor-a BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
qb() { env BP3_MODEL=executor-b BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
node_ledger() { git show "bp3/node/demo/$1:docs/quests/demo/nodes/$1/ledger.jsonl"; }
commit_on_node() {
  local node_name="$1"
  local file_path="$2"
  local content="$3"
  local branch="refs/heads/bp3/node/demo/$node_name"
  local tip
  local blob
  local tree
  local new_tip
  local idx="$work/idx-$node_name"
  tip=$(git rev-parse "$branch")
  rm -f "$idx"
  blob=$(printf '%s' "$content" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$file_path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$node_name" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"
  rm -f "$idx"
  printf '%s' "$new_tip"
}

# --- two executors alternate edges on one node, identical guards ---
out=$(q demo c alt-node)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "alt create: $out"
if out_a=$(qa demo u alt-node land --reason "too early" 2>&1); then fail "alt land by A accepted"; fi
if out_b=$(qb demo u alt-node land --reason "too early" 2>&1); then fail "alt land by B accepted"; fi
echo "$out_a" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "todo" and .error.facts.edge == "land"' >/dev/null || fail "alt guard A: $out_a"
echo "$out_b" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "todo" and .error.facts.edge == "land"' >/dev/null || fail "alt guard B: $out_b"
[ "$(echo "$out_a" | jq -cS '.error.facts')" = "$(echo "$out_b" | jq -cS '.error.facts')" ] || fail "alt guards differ: $out_a vs $out_b"
echo alt-work > alt.txt; git add alt.txt; git commit -qm alt-work
ALT=$(git rev-parse HEAD)
out=$(qa demo u alt-node handoff --commit "$ALT" --reason "work")
echo "$out" | jq -e '.ok == true and .state == "handed_off"' >/dev/null || fail "alt handoff A: $out"
out=$(qb demo u alt-node grade --verdict ship --reason "ok")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "node_fin"' >/dev/null || fail "alt grade B auto-lands: $out"
node_ledger alt-node | jq -se '([.[] | select(.edge == "handoff") | .model] == ["executor-a"]) and ([.[] | select(.edge == "grade") | .model] == ["executor-b"])' >/dev/null || fail "alt ledger models"

# --- verdict naming a superseded commit refused ---
out=$(q demo c stale-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "stale create: $out"
echo stale-a > stale.txt; git add stale.txt; git commit -qm stale-a
STALE_A=$(git rev-parse HEAD)
out=$(q demo u stale-node handoff --commit "$STALE_A" --reason "first")
echo "$out" | jq -e '.state == "handed_off" and .cycle == 1' >/dev/null || fail "stale handoff A: $out"
out=$(q demo u stale-node block --reason "hold")
echo "$out" | jq -e '.state == "blocked"' >/dev/null || fail "stale block: $out"
out=$(BP3_DECIDER=human q demo u stale-node resume --reason "go simpler")
echo "$out" | jq -e '.state == "todo" and .cycle == 2' >/dev/null || fail "stale resume: $out"
echo stale-b > stale.txt; git add stale.txt; git commit -qm stale-b
STALE_B=$(git rev-parse HEAD)
out=$(q demo u stale-node handoff --commit "$STALE_B" --reason "second")
echo "$out" | jq -e '.state == "handed_off" and .cycle == 2' >/dev/null || fail "stale handoff B: $out"
before=$(node_ledger stale-node | wc -l)
if out=$(q demo u stale-node grade --verdict ship --commit "$STALE_A" --reason "stale" 2>&1); then fail "stale grade accepted"; fi
echo "$out" | jq -e --arg b "$STALE_B" '.ok == false and .error.code == "E_COMMIT_MISMATCH" and .error.facts.bound == $b' >/dev/null || fail "stale grade code: $out"
after=$(node_ledger stale-node | wc -l)
[ "$before" = "$after" ] || fail "stale verdict ledgered"
out=$(q demo r stale-node)
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "stale still handed_off: $out"
out=$(q demo u stale-node grade --verdict ship --commit "$STALE_B" --reason "current")
echo "$out" | jq -e '.state == "landed" and .fin == "node_fin"' >/dev/null || fail "stale grade current auto-lands: $out"

# --- extra grade after auto-land refused with E_ILLEGAL_EDGE ---
out=$(q demo c parallel-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "parallel create: $out"
echo par-work > par.txt; git add par.txt; git commit -qm par-work
PAR=$(git rev-parse HEAD)
out=$(q demo u parallel-node handoff --commit "$PAR" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "parallel handoff: $out"
out=$(q demo u parallel-node grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "landed" and .fin == "node_fin"' >/dev/null || fail "parallel grade auto-lands: $out"
[ "$(node_ledger parallel-node | grep -c '"to":"landed"')" = "1" ] || fail "parallel landed count"
if out=$(q demo u parallel-node grade --verdict ship --reason "again" 2>&1); then fail "parallel extra grade accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "landed"' >/dev/null || fail "parallel extra grade code: $out"
if out=$(q demo u parallel-node land --reason "redundant" 2>&1); then fail "redundant land after auto-land accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "landed"' >/dev/null || fail "redundant land code: $out"
[ "$(node_ledger parallel-node | grep -c '"to":"landed"')" = "1" ] || fail "parallel landed twice"

# --- needs_fix at max_cycles blocked; resume human gate (parser-fix2 above) ---
before=$(node_ledger parser-fix2 | wc -l)
if out=$(q demo u parser-fix2 resume --reason "go" 2>&1); then fail "resume without human accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_HUMAN_REQUIRED"' >/dev/null || fail "resume human code: $out"
after=$(node_ledger parser-fix2 | wc -l)
[ "$before" = "$after" ] || fail "refused resume ledgered"
out=$(q demo r parser-fix2)
echo "$out" | jq -e '.state == "blocked" and .cycle == 1 and (.legal_edges | index("resume") != null) and (.legal_edges | index("delete") != null)' >/dev/null || fail "blocked legal edges: $out"
out=$(BP3_DECIDER=human q demo u parser-fix2 resume --reason "go simpler")
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 2' >/dev/null || fail "resume human todo cycle+1: $out"
out=$(q r demo)
echo "$out" | jq -e '[.inbox[] | select(.node == "parser-fix2")] | length == 0' >/dev/null || fail "resumed node still in inbox: $out"

# --- two nodes auto-land into one quest branch: clean merge keeps verdicts ---
out=$(q demo c land-a)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-a create: $out"
out=$(q demo c land-b)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-b create: $out"
LAND_A=$(commit_on_node land-a fa.txt "A-content")
LAND_B=$(commit_on_node land-b fb.txt "B-content")
out=$(q demo u land-a handoff --commit "$LAND_A" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-a handoff: $out"
out=$(q demo u land-b handoff --commit "$LAND_B" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-b handoff: $out"
out=$(q demo u land-a grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-a auto-land: $out"
out=$(q demo u land-b grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-b clean merge auto-land: $out"
[ "$(git show bp3/quest/demo:fa.txt)" = "A-content" ] || fail "clean merge lost fa.txt"
[ "$(git show bp3/quest/demo:fb.txt)" = "B-content" ] || fail "clean merge lost fb.txt"
git merge-base --is-ancestor "$LAND_A" bp3/quest/demo || fail "land-a reviewed commit not ancestor of quest tip"
git merge-base --is-ancestor "$LAND_B" bp3/quest/demo || fail "land-b reviewed commit not ancestor of quest tip"
out=$(q demo r land-b)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-b verdicts kept: $out"
[ "$(node_ledger land-b | grep -c '"to":"landed"')" = "1" ] || fail "land-b landed verdict lost"

# --- two nodes auto-land: conflict demotes only the conflicting node ---
out=$(q demo c land-c)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-c create: $out"
out=$(q demo c land-d)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-d create: $out"
LAND_C=$(commit_on_node land-c shared.txt "C-side")
LAND_D=$(commit_on_node land-d shared.txt "D-side")
out=$(q demo u land-c handoff --commit "$LAND_C" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-c handoff: $out"
out=$(q demo u land-d handoff --commit "$LAND_D" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-d handoff: $out"
out=$(q demo u land-c grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-c auto-land: $out"
cycle_before=$(q demo r land-d | jq -r '.cycle')
out=$(q demo u land-d grade --verdict ship --reason "ok")
echo "$out" | jq -e --argjson cyc "$cycle_before" '.ok == true and .state == "todo" and .cycle == $cyc and .facts.land_conflict == true' >/dev/null || fail "land-d conflict demotion: $out"
out=$(q demo r land-d)
echo "$out" | jq -e --argjson cyc "$cycle_before" '.state == "todo" and .cycle == $cyc' >/dev/null || fail "land-d cycle changed: $out"
out=$(q demo r land-c)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-c demoted by other conflict: $out"
out=$(q demo r land-a)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-a demoted by other conflict: $out"
[ "$(git show bp3/quest/demo:shared.txt)" = "C-side" ] || fail "conflict overwrote quest work file"

# --- dirty-tree handoff refused; block checkpoint is a real commit ---
out=$(q demo c dirty-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "dirty create: $out"
echo dirty-work > dirty.txt; git add dirty.txt; git commit -qm dirty-work
DIRTY_WORK=$(git rev-parse HEAD)
echo dirty >> a.txt
before=$(node_ledger dirty-node | wc -l)
if out=$(q demo u dirty-node handoff --commit "$DIRTY_WORK" --reason "work" 2>&1); then fail "dirty handoff accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty handoff code: $out"
after=$(node_ledger dirty-node | wc -l)
[ "$before" = "$after" ] || fail "dirty handoff ledgered"
out=$(q demo r dirty-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "dirty handoff changed state: $out"
git checkout -- a.txt
out=$(q demo u dirty-node handoff --commit "$DIRTY_WORK" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "clean handoff after dirty: $out"
echo dirty-again >> a.txt
out=$(q demo u dirty-node block --reason "stuck")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "dirty block: $out"
checkpoint=$(node_ledger dirty-node | tail -1 | jq -r '.checkpoint')
[ -n "$checkpoint" ] && [ "$checkpoint" != "null" ] || fail "block checkpoint missing"
[ "$(git cat-file -t "$checkpoint")" = "commit" ] || fail "checkpoint is not a commit object: $checkpoint"
out=$(q r demo)
echo "$out" | jq -e --arg ck "$checkpoint" '[.inbox[] | select(.node == "dirty-node" and .checkpoint == $ck)] | length == 1' >/dev/null || fail "inbox checkpoint mismatch: $out"
git checkout -- a.txt

# --- delete from blocked requires human; tombstone keeps branch ref ---
before=$(node_ledger dirty-node | wc -l)
if out=$(q demo d dirty-node --reason "gone" 2>&1); then fail "delete blocked without human accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_HUMAN_REQUIRED"' >/dev/null || fail "delete blocked code: $out"
after=$(node_ledger dirty-node | wc -l)
[ "$before" = "$after" ] || fail "refused delete ledgered"
out=$(q demo r dirty-node)
echo "$out" | jq -e '.state == "blocked"' >/dev/null || fail "refused delete changed state: $out"
out=$(BP3_DECIDER=human q demo d dirty-node --reason "gone")
echo "$out" | jq -e '.ok == true and .state == "deleted"' >/dev/null || fail "delete blocked human: $out"
git rev-parse --verify -q refs/heads/bp3/node/demo/dirty-node >/dev/null || fail "delete removed node branch ref"
out=$(q demo r dirty-node)
echo "$out" | jq -e '.state == "deleted" and (.legal_edges | length == 0)' >/dev/null || fail "tombstone read: $out"
node_ledger dirty-node | tail -1 | jq -e '.edge == "delete" and .to == "deleted"' >/dev/null || fail "tombstone ledger line"

# --- fresh-clone reconstruction from branch tips alone ---
out=$(q demo c clone-blocked)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "clone-blocked create: $out"
echo cb-work > cb.txt; git add cb.txt; git commit -qm cb-work
CB_WORK=$(git rev-parse HEAD)
out=$(q demo u clone-blocked handoff --commit "$CB_WORK" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "clone-blocked handoff: $out"
out=$(q demo u clone-blocked grade --verdict needs_fix --reason "clone blocked reason")
echo "$out" | jq -e '.state == "blocked" and .human_action_required == true' >/dev/null || fail "clone-blocked blocks: $out"
before_clone=$(q r demo | jq -S -c '{quest, state, rollup, nodes: (.nodes | sort_by(.node) | map({node, state, cycle, commit})), inbox: (.inbox | sort_by(.node))}')
git clone -q "$work/repo" "$work/clone"
cd "$work/clone"
git config user.email t@t.t; git config user.name t
git fetch -q origin '+refs/heads/bp3/*:refs/heads/bp3/*'
test ! -f docs/quests/demo/nodes/clone-blocked/state.yaml || fail "clone worktree carries state.yaml; branch-tip proof unclear"
clone_q() { BP3_Q_BIN="$work/clone/g-bin" ./bin/bp3 q "$@"; }
after_clone=$(clone_q r demo | jq -S -c '{quest, state, rollup, nodes: (.nodes | sort_by(.node) | map({node, state, cycle, commit})), inbox: (.inbox | sort_by(.node))}')
[ "$before_clone" = "$after_clone" ] || fail "clone reconstruction differs: $before_clone vs $after_clone"
out=$(clone_q demo r clone-blocked)
echo "$out" | jq -e '.state == "blocked"' >/dev/null || fail "clone blocked node: $out"
out=$(clone_q demo r land-a)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "clone landed node: $out"
out=$(clone_q demo r land-d)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "clone demoted node: $out"
out=$(clone_q r demo)
echo "$out" | jq -e '.rollup == "blocked" and ([.inbox[] | select(.node == "clone-blocked" and .reason == "clone blocked reason")] | length == 1)' >/dev/null || fail "clone rollup/inbox: $out"
cd "$work/repo"

# --- proposed changes: the bound commit's changeset, visible before land ---
q c chg >/dev/null
q chg c files >/dev/null
echo new > added.txt; mkdir -p sub; echo deep > sub/deep.txt; echo change >> a.txt; git rm -q b.txt 2>/dev/null || rm -f b.txt
git add -A; git commit -qm "add+modify+delete"
CHG=$(git rev-parse HEAD)
out=$(q chg u files handoff --commit "$CHG" --reason "changeset demo")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "chg handoff: $out"
out=$(q chg r files)
echo "$out" | jq -e '[.changes[] | select(.change == "+" and .path == "added.txt")] | length == 1' >/dev/null || fail "changes +: $out"
echo "$out" | jq -e '[.changes[] | select(.change == "u" and .path == "a.txt")] | length == 1' >/dev/null || fail "changes u: $out"
echo "$out" | jq -e '[.changes[] | select(.change == "-" and .path == "b.txt")] | length == 1' >/dev/null || fail "changes -: $out"
ctree=$(q chg r files --format tree)
echo "$ctree" | grep -q "├── + added.txt" || fail "node tree files: $ctree"
echo "$ctree" | grep -q "├── sub" || fail "node tree dir branch: $ctree"
echo "$ctree" | grep -q "└── + deep.txt" || fail "node tree nested leaf: $ctree"
echo "$ctree" | grep -qF "+ added.txt" || fail "node tree + line: $ctree"
echo "$ctree" | grep -qF "u a.txt" || fail "node tree u line: $ctree"
echo "$ctree" | grep -qF -- "- b.txt" || fail "node tree - line: $ctree"
qtree=$(q r chg --format tree)
echo "$qtree" | grep -q "\[+2 u1 -1\]" || fail "quest tree counts: $qtree"
git checkout -q HEAD -- a.txt 2>/dev/null || true
# unsure changeset renders as ?, never a fake empty
q chg c fresh >/dev/null
ftree=$(q chg r fresh --format tree)
echo "$ftree" | grep -q "? changes unknown" || fail "unsure changes marker: $ftree"
out=$(q chg r fresh)
echo "$out" | jq -e '.changes == null' >/dev/null || fail "unsure changes json: $out"

# --- icebox door: read-only list/search/slug over docs/icebox ---
mkdir -p docs/icebox
cat > docs/icebox/2026-01-01-alpha-idea.md <<'EOF'
---
status: frozen
date: 2026-01-01
promoted: null
---

# Alpha idea

Body mentions Tables and completion.
EOF
cat > docs/icebox/2026-01-02-beta-idea.md <<'EOF'
---
status: frozen
date: 2026-01-02
promoted: docs/quests/some-quest/QUEST.md
---

# Beta idea

Plain body.
EOF
printf 'no frontmatter here\njust text about tables\n' > docs/icebox/2026-01-03-broken.md
printf '# Icebox\n\nnot an entry\n' > docs/icebox/README.md
icebox_status_before=$(git status --porcelain)
out=$(q icebox r)
echo "$out" | jq -e '.ok == true and (.entries | length == 3) and .entries[0].slug == "2026-01-01-alpha-idea" and .entries[0].date == "2026-01-01" and .entries[0].status == "frozen" and .entries[0].promoted == null and .entries[0].title == "Alpha idea" and .entries[1].promoted == "docs/quests/some-quest/QUEST.md" and .entries[2].slug == "2026-01-03-broken" and .entries[2].date == "-" and .entries[2].status == "-" and .entries[2].title == "-"' >/dev/null || fail "icebox list: $out"
out=$(q icebox read)
echo "$out" | jq -e '.ok == true and (.entries | length == 3)' >/dev/null || fail "icebox read alias: $out"
out=$(q icebox r TABLE)
echo "$out" | jq -e '.ok == true and (.entries | length == 2) and .entries[0].slug == "2026-01-01-alpha-idea" and .entries[1].slug == "2026-01-03-broken"' >/dev/null || fail "icebox term case-insensitive: $out"
out=$(q icebox r alpha tables)
echo "$out" | jq -e '.ok == true and (.entries | length == 1) and .entries[0].slug == "2026-01-01-alpha-idea"' >/dev/null || fail "icebox all terms: $out"
out=$(q icebox r zzz-no-hit)
echo "$out" | jq -e '.ok == true and (.entries | length == 0)' >/dev/null || fail "icebox no hits empty: $out"
q icebox r 2026-01-01-alpha-idea > "$work/icebox-out.txt"
cmp docs/icebox/2026-01-01-alpha-idea.md "$work/icebox-out.txt" || fail "icebox slug verbatim"
itbl=$(q icebox r --format table)
echo "$itbl" | sed -n 1p | grep -Eq '^slug +date +status +promoted +title$' || fail "icebox table header: $itbl"
echo "$itbl" | grep -Eq '^2026-01-01-alpha-idea +2026-01-01 +frozen +- +Alpha idea$' || fail "icebox table alpha row: $itbl"
echo "$itbl" | grep -q 'docs/quests/some-quest/QUEST.md' || fail "icebox table promoted: $itbl"
if out=$(q icebox c nope 2>&1); then fail "icebox write verb accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "icebox write verb code: $out"
[ "$(git status --porcelain)" = "$icebox_status_before" ] || fail "icebox command wrote to worktree"

# --- brief (induct-inline-as-default brief.1): the grader's cold brief, from the bound commit ---
q c brief-demo >/dev/null
q brief-demo c bn >/dev/null; q brief-demo c bn2 >/dev/null; q brief-demo c bn3 >/dev/null
mkdir -p docs/quests/brief-demo/nodes/bn
printf '# bn\n\n## TL;DR\n\nt\n\n## Acceptance gates\n\nGATE-ROW-ONE\n\n## Diagram\n\nDIAGRAM-TEXT\n' > docs/quests/brief-demo/nodes/bn/NODE.md
printf '# Grading\n\nRUN-THE-GATE\n' > GRADING.md
git add -A; git commit -qm "bn: work"; A1=$(git rev-parse HEAD)   # -A: earlier sections leave fixtures untracked, and a handoff needs a clean tree
q brief-demo n bn e handoff --commit "$A1" --reason "work" >/dev/null
out=$(q brief-demo n bn brief)
echo "$out" | jq -e --arg c "$A1" '.ok == true and .quest == "brief-demo" and .node == "bn" and .cycle == 1 and .commit == $c and (.brief | type == "string")' >/dev/null || fail "brief shape: $out"
b=$(echo "$out" | jq -r .brief)
[ "$(echo "$b" | head -1)" = "Grade bn at ${A1:0:7} (full SHA $A1) in quest brief-demo, cycle 1." ] || fail "brief join line: $b"
echo "$b" | grep -q '^GATE-ROW-ONE$' || fail "brief gates: $b"
echo "$b" | grep -q 'DIAGRAM-TEXT' && fail "brief leaks the next section: $b"
echo "$b" | grep -q '^RUN-THE-GATE$' || fail "brief GRADING.md: $b"
echo "$b" | grep -qF 'Severity gate:' || fail "brief severity gate: $b"
echo "$b" | grep -q '^FOLLOW-UPS:' || fail "brief FOLLOW-UPS: $b"
echo "$b" | grep -q '^Desk:' && fail "brief Desk line without --desk: $b"
out=$(q brief-demo n bn brief --desk "$work")
echo "$out" | jq -r .brief | grep -qx "Desk: $work (check that \`git rev-parse HEAD\` prints $A1)" || fail "brief Desk line: $out"
# real directories, so only the one-line rule can refuse them
nl="$work/$(printf 'nl\nfocus on parse')"; cr="$work/$(printf 'cr\rfocus on parse')"; sp="$work/sp ignore the tests"; nb="$work/$(printf 'nb\302\240ship\302\240it')"; ff="$work/$(printf 'ff\014ship')"
mkdir "$nl" "$cr" "$sp" "$nb" "$ff"
out=$(q brief-demo n bn brief --desk "$nb" 2>&1) || true   # the refusal names the real rule
echo "$out" | jq -e '.error.facts.detail | test("printable ASCII with no space")' >/dev/null || fail "--desk refusal text: $out"
for d in rel /no/such/dir "$nl" "$cr" "$sp" "$nb" "$ff"; do
  if out=$(q brief-demo n bn brief --desk "$d" 2>&1); then fail "bad --desk accepted: $d"; fi
  echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "bad --desk code: $out"
done
# reads the commit, never the working tree
printf '# bn\n\n## TL;DR\n\nt\n\n## Acceptance gates\n\nGATE-ROW-ONE\nEDITED-AFTER-HANDOFF\n\n## Diagram\n\nDIAGRAM-TEXT\n' > docs/quests/brief-demo/nodes/bn/NODE.md
b=$(q brief-demo n bn brief | jq -r .brief); echo "$b" | grep -q '^GATE-ROW-ONE$' || fail "brief (working-tree probe) empty: $b"; echo "$b" | grep -q EDITED-AFTER-HANDOFF && fail "brief read the working tree"
printf 'GRADING-EDITED-AFTER-HANDOFF\n' >> GRADING.md
b=$(q brief-demo n bn brief | jq -r .brief); echo "$b" | grep -q '^RUN-THE-GATE$' || fail "brief (working-tree probe) lost GRADING.md: $b"; echo "$b" | grep -q GRADING-EDITED-AFTER-HANDOFF && fail "brief read GRADING.md from the working tree"
git checkout -q -- docs/quests/brief-demo/nodes/bn/NODE.md GRADING.md
# todo and approved refuse with the state's legal edges
if out=$(q brief-demo n bn3 brief 2>&1); then fail "brief in todo accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_HANDED_OFF" and .error.facts.state == "todo" and (.error.facts.legal_edges | index("handoff"))' >/dev/null || fail "brief todo code: $out"
# cycle 2: range and other nodes' commits, never the needs_fix reason
echo b2 > b2.txt; git add b2.txt; git commit -qm "bn2: work"; B2=$(git rev-parse HEAD)
q brief-demo n bn2 e handoff --commit "$B2" --reason "work" >/dev/null
q brief-demo n bn e grade --verdict needs_fix --mechanical --reason "SENTINEL-REASON row 1" >/dev/null
echo fix > fix.txt; git add fix.txt; git commit -qm "bn: fix"; A2=$(git rev-parse HEAD)
q brief-demo n bn e handoff --commit "$A2" --reason "fix" >/dev/null
b=$(q brief-demo n bn brief | jq -r .brief)
echo "$b" | head -1 | grep -q "cycle 2\.$" || fail "brief cycle 2 line: $b"
echo "$b" | grep -qF "Previous round: ${A1:0:7} was graded needs_fix. Delta re-grade: run \`./scripts/receipt\`, review \`git diff ${A1:0:7}..${A2:0:7}\` (ignoring other nodes' commits below), and re-verify only the Acceptance gates touched by that diff plus any test deletions." || fail "brief range: $b"
echo "$b" | grep -qF "Re-judge the gates in full" && fail "brief still says Re-judge the gates in full: $b"
echo "$b" | grep -qF "Other nodes' commits in that range: ${B2:0:7} (bn2)." || fail "brief others: $b"
echo "$b" | grep -q SENTINEL-REASON && fail "brief quotes the author's --reason: $b"
q brief-demo n bn2 e grade --verdict ship --reason "ok" >/dev/null
if out=$(q brief-demo n bn2 brief 2>&1); then fail "brief in landed accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_HANDED_OFF" and .error.facts.state == "landed"' >/dev/null || fail "brief landed code: $out"
# the verb's word is reserved: no node can be named after it
if out=$(q brief-demo c brief 2>&1); then fail "node named brief accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved brief code: $out"


# --- induct-inline-as-default skills.1: commits stacked in one quest desk land in turn ---
# (background grades: B is committed on top of A before A's verdict is cast)
q c stack-demo >/dev/null; q stack-demo c sa >/dev/null; q stack-demo c sb >/dev/null
sdesk=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness desk prepare --quest stack-demo | jq -r .path)
( cd "$sdesk"
  echo A > sa.txt; git add sa.txt; git commit -qm "sa: work"; SA=$(git rev-parse HEAD)
  q stack-demo n sa e handoff --commit "$SA" --reason a >/dev/null
  echo B > sb.txt; git add sb.txt; git commit -qm "sb: work"; SB=$(git rev-parse HEAD)
  q stack-demo n sb e handoff --commit "$SB" --reason b >/dev/null
  q stack-demo n sa e grade --verdict ship --reason ok | jq -e '.state == "landed"' >/dev/null || fail "stacked auto-land sa"
  [ -z "$(git status --short)" ] || fail "desk dirty after the first stacked land: $(git status --short)"
  q stack-demo n sb e grade --verdict ship --reason ok | jq -e '.state == "landed"' >/dev/null || fail "stacked auto-land sb"
  [ -z "$(git status --short)" ] || fail "desk dirty after the second stacked land"
  [ "$(git rev-parse HEAD)" = "$SB" ] || fail "a land moved the desk's branch"
  [ "$(git rev-parse quest/stack-demo)" = "$SB" ] || fail "quest branch tip"
)

# --- manifest.2: bp3 q r warns W_NO_REPO_CONFIG when backpack.toml absent, clears when present; brief shows [grade].gate ---
out=$(q r) || fail "q r all failed"
echo "$out" | jq -e '.ok == true and any(.warnings[]; (type == "object") and .code == "W_NO_REPO_CONFIG")' >/dev/null || fail "q r missing W_NO_REPO_CONFIG: $out"
[ -z "$(git status --porcelain)" ] || fail "q r mutated working tree"
printf 'version = 1\nrepo = "g-fx"\n\n[grade]\ngate = "echo g-manifest-gate"\n' > backpack.toml
git add backpack.toml && git commit -qm "chore: add backpack.toml"
out=$(q r) || fail "q r with backpack failed"
echo "$out" | jq -e '.ok == true and all((.warnings // [])[]; (type != "object") or (.code != "W_NO_REPO_CONFIG"))' >/dev/null || fail "q r still warned with backpack.toml: $out"
q c bf-gate >/dev/null
q bf-gate c n1 >/dev/null
BF_SHA=$(git rev-parse HEAD)
q bf-gate n n1 e handoff --commit "$BF_SHA" --reason "h" >/dev/null
out=$(q bf-gate n n1 brief) || fail "brief with backpack failed: $out"
echo "$out" | jq -r '.brief' | grep -qF "Repo gate (backpack.toml): echo g-manifest-gate" || fail "brief missing Repo gate: $out"
git rm -qf backpack.toml && git commit -qm "chore: remove temp backpack.toml"

# --- version guard: minor-ahead warns and writes; major-ahead refuses writes ---
stamp_ledger() { # $1 quest $2 node $3 version
  local br="bp3/node/$1/$2" path="docs/quests/$1/nodes/$2/ledger.jsonl" tip idx led blob tree nt
  tip=$(git rev-parse "$br")
  led=$(git show "$br:$path")
  idx=$(mktemp)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  blob=$(printf '%s\n{"ts":"2026-01-01T00:00:00Z","edge":"note","from":"todo","to":"todo","cycle":1,"commit":null,"verdict":null,"reason":"fixture stamp","harness":"t","model":"t","bp3_version":"%s"}\n' "$led" "$3" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  nt=$(git commit-tree "$tree" -p "$tip" -m "fixture stamp $3")
  git update-ref "refs/heads/$br" "$nt" "$tip"
  rm -f "$idx"
}
out=$(q demo c vf-node)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "vf-node create: $out"
stamp_ledger demo vf-node "$NEXT_MINOR"
out=$(q demo r vf-node)
echo "$out" | jq -e '.warnings | index("W_VERSION_AHEAD") != null' >/dev/null || fail "minor-ahead read warning: $out"
out=$(q demo u vf-node block --reason "minor ahead still writes")
echo "$out" | jq -e '.ok == true and .state == "blocked" and (.warnings | index("W_VERSION_AHEAD") != null)' >/dev/null || fail "minor-ahead write: $out"
stamp_ledger demo parser-fix 99.0.0
before=$(git rev-parse bp3/node/demo/parser-fix)
if out=$(q demo u parser-fix block --reason "major ahead must refuse" 2>&1); then fail "major-ahead write accepted: $out"; fi
echo "$out" | jq -e --arg v "$BP3_VER" '.ok == false and .error.code == "E_VERSION_AHEAD" and .error.facts.binary == $v and .error.facts.repo == "99.0.0"' >/dev/null || fail "major-ahead refusal: $out"
[ "$(git rev-parse bp3/node/demo/parser-fix)" = "$before" ] || fail "major-ahead refusal wrote"
# guard.1: the guard sits at the write, so every write form refuses the
# same way and no ref moves; reads still answer, with the warning.
refs_before=$(git for-each-ref --format='%(refname) %(objectname)' refs/heads/)
guarded() { # $1 label, rest: the q call
  local label=$1 out; shift
  if out=$(q "$@" 2>&1); then fail "major-ahead $label wrote: $out"; fi
  echo "$out" | jq -e '.error.code == "E_VERSION_AHEAD"' >/dev/null || fail "major-ahead $label code: $out"
}
guarded "n e" demo n parser-fix e block --reason "nested edge"
guarded "n c" demo n c vf-new
guarded "node c" demo c vf-new2
guarded "dep" demo dep parser-fix --depends-on "" --reason "clear deps"
guarded "quest c" c vf-quest --type default
guarded "node d" demo d parser-fix --reason "delete"
[ "$(git for-each-ref --format='%(refname) %(objectname)' refs/heads/)" = "$refs_before" ] || fail "major-ahead refusals moved a ref"
out=$(q r demo) || fail "major-ahead rollup read: $out"
echo "$out" | jq -e '.warnings | index("W_VERSION_AHEAD") != null' >/dev/null || fail "major-ahead rollup warning: $out"
out=$(q demo n parser-fix r) || fail "major-ahead node read: $out"

# --- help: -h/--help at every door, stdout, exit 0, no state read ---
out=$(q -h) || fail "q -h exit"
echo "$out" | grep -q "bp3 q c|r|d" || fail "q -h doors: $out"
echo "$out" | grep -q "icebox" || fail "q -h icebox: $out"
out=$(q --help) || fail "q --help exit"
echo "$out" | grep -q "quest door" || fail "q --help text: $out"
out=$(q c -h) || fail "quest door -h exit"
for w in --type --depends-on --format --reason; do echo "$out" | grep -q -- "$w" || fail "quest door help missing $w: $out"; done
out=$(q demo -h) || fail "node door -h exit"
echo "$out" | grep -q "node door" || fail "node door help: $out"
out=$(q demo u -h) || fail "update -h exit"
for w in handoff grade land block resume --verdict --commit --reason --target; do echo "$out" | grep -qw -- "$w" || fail "update help missing $w: $out"; done
out=$(q icebox -h) || fail "icebox -h exit"
echo "$out" | grep -q "icebox r" || fail "icebox help: $out"
out=$(q icebox r --help) || fail "icebox r --help exit"
echo "$out" | grep -q "read-only" || fail "icebox r help: $out"
out=$(./bin/bp3 -h) || fail "wrapper -h exit"
echo "$out" | grep -q "usage: bp3" || fail "wrapper help: $out"
out=$(q r --help) || fail "r --help should be quest-door help"
echo "$out" | grep -q "quest door" || fail "r --help text: $out"
# help reads no state: works for a nonexistent quest
out=$(q no-such-quest -h) || fail "ghost quest -h exit"
echo "$out" | grep -q "node door" || fail "ghost quest help: $out"

echo "g tests: ok"
