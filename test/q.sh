#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/q-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q "$@"; }
quest_alias() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 quest "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- create / read verdict shapes, both spellings ---
out=$(q c demo)
echo "$out" | jq -e '.ok == true and .quest == "demo" and .state == "proposed"' >/dev/null || fail "quest create shape: $out"
out=$(q create demo2)
echo "$out" | jq -e '.ok == true and .state == "proposed"' >/dev/null || fail "quest create alias: $out"
out=$(quest_alias r demo)
echo "$out" | jq -e '.ok == true and .quest == "demo" and .state == "proposed" and (.exps | type == "array") and (.inbox | type == "array") and has("rollup")' >/dev/null || fail "quest read shape: $out"
out=$(q r)
echo "$out" | jq -e '.ok == true and (.quests | length >= 2)' >/dev/null || fail "quest list: $out"

out=$(q demo c parser-fix)
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 1' >/dev/null || fail "exp create: $out"
out=$(q demo create parser-fix2)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "exp create alias: $out"
out=$(q demo r parser-fix)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "exp read: $out"
out=$(q demo read parser-fix)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "exp read alias: $out"

# --- strict argv: dup flag, unknown flag, stray positional -> usage before write ---
before=$(git show bp3/exp/demo/parser-fix:docs/quests/demo/experiments/parser-fix/ledger.jsonl | wc -l)
if out=$(q demo u parser-fix submit --commit abc --reason x --reason y 2>&1); then fail "dup flag accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "dup flag code: $out"
if out=$(q demo u parser-fix submit --commit abc --reason x --bogus y 2>&1); then fail "unknown flag accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "unknown flag code: $out"
if out=$(q demo u parser-fix submit extra --commit abc --reason x 2>&1); then fail "stray positional accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "stray code: $out"
after=$(git show bp3/exp/demo/parser-fix:docs/quests/demo/experiments/parser-fix/ledger.jsonl | wc -l)
[ "$before" = "$after" ] || fail "strict argv wrote to ledger"

# --- refusal: land from todo, ledger unchanged ---
if out=$(q demo u parser-fix land --reason "too early" 2>&1); then fail "land from todo accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "todo" and .error.facts.edge == "land" and (.error.facts.legal_edges | index("submit") != null) and (.error.guidance | length > 0)' >/dev/null || fail "illegal edge facts: $out"
after=$(git show bp3/exp/demo/parser-fix:docs/quests/demo/experiments/parser-fix/ledger.jsonl | wc -l)
[ "$before" = "$after" ] || fail "refusal ledgered"

# --- identity: unset -> unknown + warning; invalid -> fail fast ---
out=$(env -u BP3_HARNESS -u BP3_MODEL BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q demo c id-exp)
echo "$out" | jq -e '.ok == true and (.warnings | index("W_IDENTITY_UNKNOWN") != null)' >/dev/null || fail "identity warning: $out"
git show bp3/exp/demo/id-exp:docs/quests/demo/experiments/id-exp/ledger.jsonl | tail -1 | jq -e '.harness == "unknown" and .model == "unknown" and .bp3_version == "0.2.0"' >/dev/null || fail "identity ledger unknown"
if out=$(BP3_HARNESS=bogus BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q demo r parser-fix 2>&1); then fail "invalid harness accepted"; fi
echo "$out" | jq -e '.error.code == "E_IDENTITY"' >/dev/null || fail "identity code: $out"

# --- happy path submit/review/check/land (alias spellings mixed) ---
echo work > b.txt; git add b.txt; git commit -qm work
B=$(git rev-parse HEAD)
out=$(q demo u parser-fix submit --commit "$B" --reason "first cut")
echo "$out" | jq -e '.ok == true and .state == "submitted" and .cycle == 1' >/dev/null || fail "submit: $out"
out=$(q demo update parser-fix review --verdict ship --reason "looks right")
echo "$out" | jq -e '.ok == true and .state == "submitted"' >/dev/null || fail "review ship stays submitted until check: $out"
out=$(q demo u parser-fix check --verdict pass --reason "green")
echo "$out" | jq -e '.ok == true and .state == "approved"' >/dev/null || fail "check pass approves: $out"
out=$(q demo u parser-fix land --reason "ship it")
echo "$out" | jq -e '.ok == true and .state == "landed" and .fin == "exp_fin"' >/dev/null || fail "land: $out"
out=$(q r demo)
echo "$out" | jq -e '.ok == true and (.exps[] | select(.exp == "parser-fix") | .state == "landed" and .fin == "exp_fin")' >/dev/null || fail "read after land: $out"

# --- fin report words: exp_fin above; quest_fin when rollup landed ---
out=$(q c fin-demo)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "fin quest create: $out"
out=$(q fin-demo c only-exp)
echo "$out" | jq -e '.state == "todo" and .fin == null' >/dev/null || fail "fin exp create: $out"
out=$(q fin-demo u only-exp submit --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "fin submit: $out"
out=$(q fin-demo u only-exp review --verdict ship --reason "ok")
out=$(q fin-demo u only-exp check --verdict pass --reason "ok")
out=$(q fin-demo u only-exp land --reason "done")
echo "$out" | jq -e '.state == "landed" and .fin == "exp_fin"' >/dev/null || fail "fin land: $out"
out=$(q r fin-demo)
echo "$out" | jq -e '.rollup == "landed" and .fin == "quest_fin" and (.exps[0] | .state == "landed" and .fin == "exp_fin")' >/dev/null || fail "quest_fin read: $out"
out=$(q r demo)
echo "$out" | jq -e '.fin == null' >/dev/null || fail "unfinished quest has no quest_fin: $out"

# --- blocked inbox after needs_fix at max_cycles (default max_cycles=1) ---
out=$(q demo u parser-fix2 submit --commit "$B" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "submit2: $out"
out=$(q demo u parser-fix2 review --verdict needs_fix --reason "broken")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "needs_fix blocks at max: $out"
out=$(q r demo)
echo "$out" | jq -e '(.inbox | length == 1) and .inbox[0].quest == "demo" and .inbox[0].exp == "parser-fix2" and .inbox[0].reason == "broken" and (.inbox[0] | has("checkpoint")) and (.inbox[0] | has("cycle")) and (.inbox[0] | has("since"))' >/dev/null || fail "blocked inbox: $out"

# table format contains same facts
tbl=$(q r demo --format table)
echo "$tbl" | grep -q "demo" || fail "table missing quest"
echo "$tbl" | grep -q "parser-fix2" || fail "table missing blocked exp"
echo "$tbl" | grep -q "blocked" || fail "table missing blocked state"

# rendered tables: header row, aligned columns, short commits, counts
echo "$tbl" | sed -n 1p | grep -q "^quest demo \[proposed\] rollup: " || fail "quest table header: $tbl"
echo "$tbl" | sed -n 2p | grep -Eq '^exp +state +cycle +commit +changes$' || fail "quest table columns: $tbl"
echo "$tbl" | grep -Eq '^parser-fix +landed +1 +[0-9a-f]{7} +\+[0-9]+ u[0-9]+ -[0-9]+$' || fail "quest table landed row: $tbl"
if echo "$tbl" | grep -q '="'; then fail "quest table dumps inline JSON: $tbl"; fi
if echo "$tbl" | grep -q 'legal_edges'; then fail "quest table dumps raw fields: $tbl"; fi
etbl=$(q demo r parser-fix --format table)
echo "$etbl" | sed -n 1p | grep -Eq '^demo / parser-fix — landed, cycle 1, commit [0-9a-f]{7}, legal: ' || fail "exp table summary: $etbl"
echo "$etbl" | sed -n 2p | grep -Eq '^change +path$' || fail "exp table columns: $etbl"
echo "$etbl" | grep -Eq '^\+ +b\.txt$' || fail "exp table change row: $etbl"
# null commit / unknown changes render as - / ?, never crash
out=$(q demo c null-exp)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "null-exp create: $out"
ntbl=$(q demo r null-exp --format table)
echo "$ntbl" | sed -n 1p | grep -q 'commit -, legal: submit, block, delete' || fail "null commit cell: $ntbl"
echo "$ntbl" | grep -q '? changes unknown' || fail "unknown changes cell: $ntbl"
qtbl_null=$(q r demo --format table)
echo "$qtbl_null" | grep -Eq '^null-exp +todo +1 +- +\?$' || fail "quest table null row: $qtbl_null"

# tree format: the human view (git-status alphabet: + todo, u in-flight, - deleted, blank landed)
tree=$(q r demo --format tree)
echo "$tree" | grep -q "^demo " || fail "tree missing quest root: $tree"
echo "$tree" | grep -q "u parser-fix2 - blocked" || fail "tree blocked marker: $tree"
echo "$tree" | grep -q "parser-fix - landed (exp_fin)" || fail "tree exp_fin: $tree"
echo "$tree" | grep -q "(human owed)" || fail "tree human owed: $tree"
echo "$tree" | grep -q "human owed:" || fail "tree inbox header: $tree"
etree=$(q demo r parser-fix2 --format tree)
echo "$etree" | grep -q "u parser-fix2 - blocked" || fail "exp tree marker: $etree"
echo "$etree" | grep -q "legal: resume, delete" || fail "exp tree legal edges: $etree"

# delete spellings (d / delete) on a scratch exp
out=$(q demo c scratch-exp)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "scratch create: $out"
out=$(q demo d scratch-exp --reason "no longer needed")
echo "$out" | jq -e '.ok == true and .state == "deleted"' >/dev/null || fail "exp delete d: $out"
out=$(q demo create scratch-exp2)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "scratch2 create: $out"
out=$(q demo delete scratch-exp2 --reason "gone")
echo "$out" | jq -e '.ok == true and .state == "deleted"' >/dev/null || fail "exp delete alias: $out"

# --- scenario helpers ---
qa() { env BP3_MODEL=executor-a BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q "$@"; }
qb() { env BP3_MODEL=executor-b BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q "$@"; }
exp_ledger() { git show "bp3/exp/demo/$1:docs/quests/demo/experiments/$1/ledger.jsonl"; }
commit_on_exp() {
  local exp_name="$1"
  local file_path="$2"
  local content="$3"
  local branch="refs/heads/bp3/exp/demo/$exp_name"
  local tip
  local blob
  local tree
  local new_tip
  local idx="$work/idx-$exp_name"
  tip=$(git rev-parse "$branch")
  rm -f "$idx"
  blob=$(printf '%s' "$content" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$file_path"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$exp_name" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"
  rm -f "$idx"
  printf '%s' "$new_tip"
}

# --- two executors alternate edges on one exp, identical guards ---
out=$(q demo c alt-exp)
echo "$out" | jq -e '.ok == true and .state == "todo"' >/dev/null || fail "alt create: $out"
if out_a=$(qa demo u alt-exp land --reason "too early" 2>&1); then fail "alt land by A accepted"; fi
if out_b=$(qb demo u alt-exp land --reason "too early" 2>&1); then fail "alt land by B accepted"; fi
echo "$out_a" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "todo" and .error.facts.edge == "land"' >/dev/null || fail "alt guard A: $out_a"
echo "$out_b" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "todo" and .error.facts.edge == "land"' >/dev/null || fail "alt guard B: $out_b"
[ "$(echo "$out_a" | jq -cS '.error.facts')" = "$(echo "$out_b" | jq -cS '.error.facts')" ] || fail "alt guards differ: $out_a vs $out_b"
echo alt-work > alt.txt; git add alt.txt; git commit -qm alt-work
ALT=$(git rev-parse HEAD)
out=$(qa demo u alt-exp submit --commit "$ALT" --reason "work")
echo "$out" | jq -e '.ok == true and .state == "submitted"' >/dev/null || fail "alt submit A: $out"
out=$(qb demo u alt-exp review --verdict ship --reason "ok")
echo "$out" | jq -e '.ok == true and .state == "submitted"' >/dev/null || fail "alt review B: $out"
out=$(qa demo u alt-exp check --verdict pass --reason "ok")
echo "$out" | jq -e '.ok == true and .state == "approved"' >/dev/null || fail "alt check A: $out"
out=$(qb demo u alt-exp land --reason "ship")
echo "$out" | jq -e '.ok == true and .state == "landed"' >/dev/null || fail "alt land B: $out"
exp_ledger alt-exp | jq -se '([.[] | select(.edge == "submit") | .model] == ["executor-a"]) and ([.[] | select(.edge == "review") | .model] == ["executor-b"]) and ([.[] | select(.edge == "check") | .model] == ["executor-a"]) and ([.[] | select(.edge == "land") | .model] == ["executor-b"])' >/dev/null || fail "alt ledger models"

# --- verdict naming a superseded commit refused ---
out=$(q demo c stale-exp)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "stale create: $out"
echo stale-a > stale.txt; git add stale.txt; git commit -qm stale-a
STALE_A=$(git rev-parse HEAD)
out=$(q demo u stale-exp submit --commit "$STALE_A" --reason "first")
echo "$out" | jq -e '.state == "submitted" and .cycle == 1' >/dev/null || fail "stale submit A: $out"
out=$(q demo u stale-exp block --reason "hold")
echo "$out" | jq -e '.state == "blocked"' >/dev/null || fail "stale block: $out"
out=$(BP3_DECIDER=human q demo u stale-exp resume --reason "go simpler")
echo "$out" | jq -e '.state == "todo" and .cycle == 2' >/dev/null || fail "stale resume: $out"
echo stale-b > stale.txt; git add stale.txt; git commit -qm stale-b
STALE_B=$(git rev-parse HEAD)
out=$(q demo u stale-exp submit --commit "$STALE_B" --reason "second")
echo "$out" | jq -e '.state == "submitted" and .cycle == 2' >/dev/null || fail "stale submit B: $out"
before=$(exp_ledger stale-exp | wc -l)
if out=$(q demo u stale-exp review --verdict ship --commit "$STALE_A" --reason "stale" 2>&1); then fail "stale review accepted"; fi
echo "$out" | jq -e --arg b "$STALE_B" '.ok == false and .error.code == "E_COMMIT_MISMATCH" and .error.facts.bound == $b' >/dev/null || fail "stale review code: $out"
if out=$(q demo u stale-exp check --verdict pass --commit "$STALE_A" --reason "stale" 2>&1); then fail "stale check accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_COMMIT_MISMATCH"' >/dev/null || fail "stale check code: $out"
after=$(exp_ledger stale-exp | wc -l)
[ "$before" = "$after" ] || fail "stale verdict ledgered"
out=$(q demo r stale-exp)
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "stale still submitted: $out"
out=$(q demo u stale-exp review --verdict ship --commit "$STALE_B" --reason "current")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "stale review current: $out"
out=$(q demo u stale-exp check --verdict pass --commit "$STALE_B" --reason "current")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "stale check current: $out"
out=$(q demo u stale-exp land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "stale land: $out"

# --- review + check on same commit while submitted: approved exactly once ---
out=$(q demo c parallel-exp)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "parallel create: $out"
echo par-work > par.txt; git add par.txt; git commit -qm par-work
PAR=$(git rev-parse HEAD)
out=$(q demo u parallel-exp submit --commit "$PAR" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "parallel submit: $out"
out=$(q demo u parallel-exp review --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "parallel review first: $out"
out=$(q demo u parallel-exp check --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "parallel check approves: $out"
[ "$(exp_ledger parallel-exp | grep -c '"to":"approved"')" = "1" ] || fail "parallel approved count"
if out=$(q demo u parallel-exp review --verdict ship --reason "again" 2>&1); then fail "parallel extra review accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "approved"' >/dev/null || fail "parallel extra review code: $out"
if out=$(q demo u parallel-exp check --verdict pass --reason "again" 2>&1); then fail "parallel extra check accepted"; fi
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "approved"' >/dev/null || fail "parallel extra check code: $out"
[ "$(exp_ledger parallel-exp | grep -c '"to":"approved"')" = "1" ] || fail "parallel approved twice"
out=$(q demo u parallel-exp land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "parallel land: $out"
out=$(q demo c parallel-rev)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "parallel-rev create: $out"
out=$(q demo u parallel-rev submit --commit "$PAR" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "parallel-rev submit: $out"
out=$(q demo u parallel-rev check --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "parallel-rev check first: $out"
out=$(q demo u parallel-rev review --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "parallel-rev review approves: $out"
[ "$(exp_ledger parallel-rev | grep -c '"to":"approved"')" = "1" ] || fail "parallel-rev approved count"
out=$(q demo u parallel-rev land --reason "ship")
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "parallel-rev land: $out"

# --- needs_fix at max_cycles blocked; resume human gate (parser-fix2 above) ---
before=$(exp_ledger parser-fix2 | wc -l)
if out=$(q demo u parser-fix2 resume --reason "go" 2>&1); then fail "resume without human accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_HUMAN_REQUIRED"' >/dev/null || fail "resume human code: $out"
after=$(exp_ledger parser-fix2 | wc -l)
[ "$before" = "$after" ] || fail "refused resume ledgered"
out=$(q demo r parser-fix2)
echo "$out" | jq -e '.state == "blocked" and .cycle == 1 and (.legal_edges | index("resume") != null) and (.legal_edges | index("delete") != null)' >/dev/null || fail "blocked legal edges: $out"
out=$(BP3_DECIDER=human q demo u parser-fix2 resume --reason "go simpler")
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 2' >/dev/null || fail "resume human todo cycle+1: $out"
out=$(q r demo)
echo "$out" | jq -e '[.inbox[] | select(.exp == "parser-fix2")] | length == 0' >/dev/null || fail "resumed exp still in inbox: $out"

# --- two exps land into one quest branch: clean merge keeps verdicts ---
out=$(q demo c land-a)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-a create: $out"
out=$(q demo c land-b)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-b create: $out"
LAND_A=$(commit_on_exp land-a fa.txt "A-content")
LAND_B=$(commit_on_exp land-b fb.txt "B-content")
out=$(q demo u land-a submit --commit "$LAND_A" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-a submit: $out"
out=$(q demo u land-b submit --commit "$LAND_B" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-b submit: $out"
out=$(q demo u land-a review --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-a review: $out"
out=$(q demo u land-a check --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-a check: $out"
out=$(q demo u land-b review --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-b review: $out"
out=$(q demo u land-b check --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-b check: $out"
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
[ "$(exp_ledger land-b | grep -c '"to":"approved"')" = "1" ] || fail "land-b approved verdict lost"

# --- two exps land: conflict demotes only the conflicting exp ---
out=$(q demo c land-c)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-c create: $out"
out=$(q demo c land-d)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "land-d create: $out"
LAND_C=$(commit_on_exp land-c shared.txt "C-side")
LAND_D=$(commit_on_exp land-d shared.txt "D-side")
out=$(q demo u land-c submit --commit "$LAND_C" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-c submit: $out"
out=$(q demo u land-d submit --commit "$LAND_D" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-d submit: $out"
out=$(q demo u land-c review --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-c review: $out"
out=$(q demo u land-c check --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-c check: $out"
out=$(q demo u land-d review --verdict ship --reason "ok")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "land-d review: $out"
out=$(q demo u land-d check --verdict pass --reason "ok")
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "land-d check: $out"
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

# --- dirty-tree submit refused; block checkpoint is a real commit ---
out=$(q demo c dirty-exp)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "dirty create: $out"
echo dirty-work > dirty.txt; git add dirty.txt; git commit -qm dirty-work
DIRTY_WORK=$(git rev-parse HEAD)
echo dirty >> a.txt
before=$(exp_ledger dirty-exp | wc -l)
if out=$(q demo u dirty-exp submit --commit "$DIRTY_WORK" --reason "work" 2>&1); then fail "dirty submit accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty submit code: $out"
after=$(exp_ledger dirty-exp | wc -l)
[ "$before" = "$after" ] || fail "dirty submit ledgered"
out=$(q demo r dirty-exp)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "dirty submit changed state: $out"
git checkout -- a.txt
out=$(q demo u dirty-exp submit --commit "$DIRTY_WORK" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "clean submit after dirty: $out"
echo dirty-again >> a.txt
out=$(q demo u dirty-exp block --reason "stuck")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "dirty block: $out"
checkpoint=$(exp_ledger dirty-exp | tail -1 | jq -r '.checkpoint')
[ -n "$checkpoint" ] && [ "$checkpoint" != "null" ] || fail "block checkpoint missing"
[ "$(git cat-file -t "$checkpoint")" = "commit" ] || fail "checkpoint is not a commit object: $checkpoint"
out=$(q r demo)
echo "$out" | jq -e --arg ck "$checkpoint" '[.inbox[] | select(.exp == "dirty-exp" and .checkpoint == $ck)] | length == 1' >/dev/null || fail "inbox checkpoint mismatch: $out"
git checkout -- a.txt

# --- delete from blocked requires human; tombstone keeps branch ref ---
before=$(exp_ledger dirty-exp | wc -l)
if out=$(q demo d dirty-exp --reason "gone" 2>&1); then fail "delete blocked without human accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_HUMAN_REQUIRED"' >/dev/null || fail "delete blocked code: $out"
after=$(exp_ledger dirty-exp | wc -l)
[ "$before" = "$after" ] || fail "refused delete ledgered"
out=$(q demo r dirty-exp)
echo "$out" | jq -e '.state == "blocked"' >/dev/null || fail "refused delete changed state: $out"
out=$(BP3_DECIDER=human q demo d dirty-exp --reason "gone")
echo "$out" | jq -e '.ok == true and .state == "deleted"' >/dev/null || fail "delete blocked human: $out"
git rev-parse --verify -q refs/heads/bp3/exp/demo/dirty-exp >/dev/null || fail "delete removed exp branch ref"
out=$(q demo r dirty-exp)
echo "$out" | jq -e '.state == "deleted" and (.legal_edges | length == 0)' >/dev/null || fail "tombstone read: $out"
exp_ledger dirty-exp | tail -1 | jq -e '.edge == "delete" and .to == "deleted"' >/dev/null || fail "tombstone ledger line"

# --- fresh-clone reconstruction from branch tips alone ---
out=$(q demo c clone-blocked)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "clone-blocked create: $out"
echo cb-work > cb.txt; git add cb.txt; git commit -qm cb-work
CB_WORK=$(git rev-parse HEAD)
out=$(q demo u clone-blocked submit --commit "$CB_WORK" --reason "work")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "clone-blocked submit: $out"
out=$(q demo u clone-blocked review --verdict needs_fix --reason "clone blocked reason")
echo "$out" | jq -e '.state == "blocked" and .human_action_required == true' >/dev/null || fail "clone-blocked blocks: $out"
before_clone=$(q r demo | jq -S -c '{quest, state, rollup, exps: (.exps | sort_by(.exp) | map({exp, state, cycle, commit})), inbox: (.inbox | sort_by(.exp))}')
git clone -q "$work/repo" "$work/clone"
cd "$work/clone"
git config user.email t@t.t; git config user.name t
git fetch -q origin '+refs/heads/bp3/*:refs/heads/bp3/*'
test ! -f docs/quests/demo/experiments/clone-blocked/state.yaml || fail "clone worktree carries state.yaml; branch-tip proof unclear"
clone_q() { BP3_Q_BIN="$work/clone/q-bin" ./bin/bp3 q "$@"; }
after_clone=$(clone_q r demo | jq -S -c '{quest, state, rollup, exps: (.exps | sort_by(.exp) | map({exp, state, cycle, commit})), inbox: (.inbox | sort_by(.exp))}')
[ "$before_clone" = "$after_clone" ] || fail "clone reconstruction differs: $before_clone vs $after_clone"
out=$(clone_q demo r clone-blocked)
echo "$out" | jq -e '.state == "blocked"' >/dev/null || fail "clone blocked exp: $out"
out=$(clone_q demo r land-a)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "clone landed exp: $out"
out=$(clone_q demo r land-d)
echo "$out" | jq -e '.state == "todo"' >/dev/null || fail "clone demoted exp: $out"
out=$(clone_q r demo)
echo "$out" | jq -e '.rollup == "blocked" and ([.inbox[] | select(.exp == "clone-blocked" and .reason == "clone blocked reason")] | length == 1)' >/dev/null || fail "clone rollup/inbox: $out"
cd "$work/repo"

# --- proposed changes: the bound commit's changeset, visible before land ---
q c chg >/dev/null
q chg c files >/dev/null
echo new > added.txt; mkdir -p sub; echo deep > sub/deep.txt; echo change >> a.txt; git rm -q b.txt 2>/dev/null || rm -f b.txt
git add -A; git commit -qm "add+modify+delete"
CHG=$(git rev-parse HEAD)
out=$(q chg u files submit --commit "$CHG" --reason "changeset demo")
echo "$out" | jq -e '.state == "submitted"' >/dev/null || fail "chg submit: $out"
out=$(q chg r files)
echo "$out" | jq -e '[.changes[] | select(.change == "+" and .path == "added.txt")] | length == 1' >/dev/null || fail "changes +: $out"
echo "$out" | jq -e '[.changes[] | select(.change == "u" and .path == "a.txt")] | length == 1' >/dev/null || fail "changes u: $out"
echo "$out" | jq -e '[.changes[] | select(.change == "-" and .path == "b.txt")] | length == 1' >/dev/null || fail "changes -: $out"
ctree=$(q chg r files --format tree)
echo "$ctree" | grep -q "├── + added.txt" || fail "exp tree files: $ctree"
echo "$ctree" | grep -q "├── sub" || fail "exp tree dir branch: $ctree"
echo "$ctree" | grep -q "└── + deep.txt" || fail "exp tree nested leaf: $ctree"
echo "$ctree" | grep -qF "+ added.txt" || fail "exp tree + line: $ctree"
echo "$ctree" | grep -qF "u a.txt" || fail "exp tree u line: $ctree"
echo "$ctree" | grep -qF -- "- b.txt" || fail "exp tree - line: $ctree"
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

echo "q tests: ok"
