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
if out=$(BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 n r 2>&1); then fail "unclaimed bp3 n accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_NO_CONTEXT"' >/dev/null || fail "unclaimed bp3 n code: $out"

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
git show bp3/node/demo/id-node:docs/quests/demo/nodes/id-node/ledger.jsonl | tail -1 | jq -e '.harness == "unknown" and .model == "unknown" and .bp3_version == "0.2.0"' >/dev/null || fail "identity ledger unknown"
if out=$(BP3_HARNESS=bogus BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q demo r parser-fix 2>&1); then fail "invalid harness accepted"; fi
echo "$out" | jq -e '.error.code == "E_IDENTITY"' >/dev/null || fail "identity code: $out"

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

# --- happy path handoff/grade/verify/land (alias spellings mixed) ---
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
out=$(q demo u parser-fix handoff --commit "$B" --reason "first cut")
echo "$out" | jq -e '.ok == true and .state == "handed_off" and .cycle == 1' >/dev/null || fail "handoff: $out"
out=$(q demo update parser-fix grade --verdict ship --reason "looks right")
echo "$out" | jq -e '.ok == true and .state == "handed_off"' >/dev/null || fail "grade ship stays handed_off until verify: $out"
out=$(q demo u parser-fix verify --verdict pass --reason "green")
echo "$out" | jq -e '.ok == true and .state == "approved"' >/dev/null || fail "verify pass approves: $out"
out=$(q demo u parser-fix land --reason "ship it")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "node_fin"' >/dev/null || fail "land: $out"
out=$(q r demo)
echo "$out" | jq -e '.ok == true and (.nodes[] | select(.node == "parser-fix") | .state == "landed" and .fin == "node_fin")' >/dev/null || fail "read after land: $out"

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
echo "$out" | jq -e --arg c "$B" '.state == "handed_off" and .cycle == 1 and .commit == $c and (.legal_edges | index("grade") != null) and (.legal_edges | index("verify") != null)' >/dev/null || fail "compat old submit folds handed_off: $out"
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
out=$(q fin-demo u only-node verify --verdict pass --reason "ok")
out=$(q fin-demo u only-node land --reason "done")
echo "$out" | jq -e '.state == "landed" and .fin == "node_fin"' >/dev/null || fail "fin land: $out"
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

# --- pure-grade (followup.5): one combined cast approves; mechanical never blocks ---
out=$(q demo c pure-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "pure create: $out"
out=$(q demo u pure-node handoff --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "pure handoff: $out"
out=$(q demo u pure-node grade --verdict ship --verify-verdict pass --commit "$B" --reason "grade ship; verify pass")
echo "$out" | jq -e '.ok == true and .state == "approved" and .cycle == 1' >/dev/null || fail "combined cast approves once: $out"
git show bp3/node/demo/pure-node:docs/quests/demo/nodes/pure-node/ledger.jsonl | jq -se '([.[] | select(.edge == "grade")] | length == 1) and ([.[] | select(.edge == "grade")][0] | .verify_verdict == "pass")' >/dev/null || fail "combined cast is one ledger line"
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
if out=$(q demo u misuse-node verify --verdict pass --verify-verdict pass --reason "bad combo" 2>&1); then fail "verify-verdict on verify accepted"; fi
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
echo "$out" | jq -e '.ok == true and .state == "handed_off"' >/dev/null || fail "alt grade B: $out"
out=$(qa demo u alt-node verify --verdict pass --reason "ok")
echo "$out" | jq -e '.ok == true and .state == "approved"' >/dev/null || fail "alt verify A: $out"
out=$(qb demo u alt-node land --reason "ship")
echo "$out" | jq -e '.ok == true and .state == "landed"' >/dev/null || fail "alt land B: $out"
node_ledger alt-node | jq -se '([.[] | select(.edge == "handoff") | .model] == ["executor-a"]) and ([.[] | select(.edge == "grade") | .model] == ["executor-b"]) and ([.[] | select(.edge == "verify") | .model] == ["executor-a"]) and ([.[] | select(.edge == "land") | .model] == ["executor-b"])' >/dev/null || fail "alt ledger models"

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
if out=$(q demo u stale-node verify --verdict pass --commit "$STALE_A" --reason "stale" 2>&1); then fail "stale verify accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_COMMIT_MISMATCH"' >/dev/null || fail "stale verify code: $out"
after=$(node_ledger stale-node | wc -l)
[ "$before" = "$after" ] || fail "stale verdict ledgered"
out=$(q demo r stale-node)
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "stale still handed_off: $out"
out=$(q demo u stale-node grade --verdict ship --commit "$STALE_B" --reason "current")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "stale grade current: $out"
out=$(q demo u stale-node verify --verdict pass --commit "$STALE_B" --reason "current")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "stale verify current: $out"
out=$(q demo u stale-node land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "stale land: $out"

# --- grade + verify on same commit while handed_off: approved exactly once ---
out=$(q demo c parallel-node)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "parallel create: $out"
echo par-work > par.txt; git add par.txt; git commit -qm par-work
PAR=$(git rev-parse HEAD)
out=$(q demo u parallel-node handoff --commit "$PAR" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "parallel handoff: $out"
out=$(q demo u parallel-node grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "parallel grade first: $out"
out=$(q demo u parallel-node verify --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "parallel verify approves: $out"
[ "$(node_ledger parallel-node | grep -c '"to":"approved"')" = "1" ] || fail "parallel approved count"
if out=$(q demo u parallel-node grade --verdict ship --reason "again" 2>&1); then fail "parallel extra grade accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "approved"' >/dev/null || fail "parallel extra grade code: $out"
if out=$(q demo u parallel-node verify --verdict pass --reason "again" 2>&1); then fail "parallel extra verify accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "approved"' >/dev/null || fail "parallel extra verify code: $out"
[ "$(node_ledger parallel-node | grep -c '"to":"approved"')" = "1" ] || fail "parallel approved twice"
out=$(q demo u parallel-node land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "parallel land: $out"
out=$(q demo c parallel-rev)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "parallel-rev create: $out"
out=$(q demo u parallel-rev handoff --commit "$PAR" --reason "work")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "parallel-rev handoff: $out"
out=$(q demo u parallel-rev verify --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "parallel-rev verify first: $out"
out=$(q demo u parallel-rev grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "parallel-rev grade approves: $out"
[ "$(node_ledger parallel-rev | grep -c '"to":"approved"')" = "1" ] || fail "parallel-rev approved count"
out=$(q demo u parallel-rev land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "parallel-rev land: $out"

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

# --- two nodes land into one quest branch: clean merge keeps verdicts ---
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
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-a grade: $out"
out=$(q demo u land-a verify --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-a verify: $out"
out=$(q demo u land-b grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-b grade: $out"
out=$(q demo u land-b verify --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-b verify: $out"
out=$(q demo u land-a land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-a land: $out"
out=$(q demo u land-b land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-b clean merge: $out"
[ "$(git show bp3/quest/demo:fa.txt)" = "A-content" ] || fail "clean merge lost fa.txt"
[ "$(git show bp3/quest/demo:fb.txt)" = "B-content" ] || fail "clean merge lost fb.txt"
git merge-base --is-ancestor "$LAND_A" bp3/quest/demo || fail "land-a reviewed commit not ancestor of quest tip"
git merge-base --is-ancestor "$LAND_B" bp3/quest/demo || fail "land-b reviewed commit not ancestor of quest tip"
out=$(q demo r land-b)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-b verdicts kept: $out"
[ "$(node_ledger land-b | grep -c '"to":"approved"')" = "1" ] || fail "land-b approved verdict lost"

# --- two nodes land: conflict demotes only the conflicting node ---
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
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-c grade: $out"
out=$(q demo u land-c verify --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-c verify: $out"
out=$(q demo u land-d grade --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "land-d grade: $out"
out=$(q demo u land-d verify --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-d verify: $out"
out=$(q demo u land-c land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "land-c land: $out"
cycle_before=$(q demo r land-d | jq -r '.cycle')
out=$(q demo u land-d land --reason "ship")
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
echo "$b" | grep -q '^Desk:' && fail "brief Desk line without --desk: $b"
out=$(q brief-demo n bn brief --desk "$work")
echo "$out" | jq -r .brief | grep -qx "Desk: $work (check that \`git rev-parse HEAD\` prints $A1)" || fail "brief Desk line: $out"
for d in rel /no/such/dir "$(printf '%s\nfocus on parse' "$work")"; do
  if out=$(q brief-demo n bn brief --desk "$d" 2>&1); then fail "bad --desk accepted: $d"; fi
  echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "bad --desk code: $out"
done
# reads the commit, never the working tree
printf 'EDITED-AFTER-HANDOFF\n' >> docs/quests/brief-demo/nodes/bn/NODE.md
q brief-demo n bn brief | jq -r .brief | grep -q EDITED-AFTER-HANDOFF && fail "brief read the working tree"
git checkout -q -- docs/quests/brief-demo/nodes/bn/NODE.md
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
echo "$b" | grep -qF "Previous round: ${A1:0:7} was graded needs_fix. Re-judge the gates in full; the change since is \`git diff ${A1:0:7}..${A2:0:7}\`." || fail "brief range: $b"
echo "$b" | grep -qF "Other nodes' commits in that range: ${B2:0:7} (bn2)." || fail "brief others: $b"
echo "$b" | grep -q SENTINEL-REASON && fail "brief quotes the author's --reason: $b"
q brief-demo n bn2 e grade --verdict ship --verify-verdict pass --reason "ok" >/dev/null
if out=$(q brief-demo n bn2 brief 2>&1); then fail "brief in approved accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_HANDED_OFF" and .error.facts.state == "approved"' >/dev/null || fail "brief approved code: $out"
# the verb's word is reserved: no node can be named after it
if out=$(q brief-demo c brief 2>&1); then fail "node named brief accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "reserved brief code: $out"


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
stamp_ledger demo vf-node 0.3.0
out=$(q demo r vf-node)
echo "$out" | jq -e '.warnings | index("W_VERSION_AHEAD") != null' >/dev/null || fail "minor-ahead read warning: $out"
out=$(q demo u vf-node block --reason "minor ahead still writes")
echo "$out" | jq -e '.ok == true and .state == "blocked" and (.warnings | index("W_VERSION_AHEAD") != null)' >/dev/null || fail "minor-ahead write: $out"
stamp_ledger demo parser-fix 99.0.0
before=$(git rev-parse bp3/node/demo/parser-fix)
if out=$(q demo u parser-fix block --reason "major ahead must refuse" 2>&1); then fail "major-ahead write accepted: $out"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_VERSION_AHEAD" and .error.facts.binary == "0.2.0" and .error.facts.repo == "99.0.0"' >/dev/null || fail "major-ahead refusal: $out"
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
lk() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness link "$@"; }
out=$(lk mint --kind edge --quest demo --node parser-fix --edge block --depth 2)
MUSE_SESSION_ID=sess-vf lk claim "$(echo "$out" | jq -r .token)" >/dev/null
rm -f .bp3-context.json
if out=$(MUSE_SESSION_ID=sess-vf BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 e block --reason "claimed door" 2>&1); then fail "major-ahead e door wrote: $out"; fi
echo "$out" | jq -e '.error.code == "E_VERSION_AHEAD"' >/dev/null || fail "major-ahead e door code: $out"
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
for w in handoff grade verify land block resume --verdict --commit --reason --target; do echo "$out" | grep -qw -- "$w" || fail "update help missing $w: $out"; done
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
