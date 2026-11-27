#!/usr/bin/env bash
# mvp.3: node deps, ready-set waves, starved sets, derived
# timing, setup gate, serial land. Fixture quests are built
# through bp3 q itself; timing fixtures write ledger lines
# with fixed timestamps through git plumbing.
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
fail() { echo "FAIL: $*" >&2; exit 1; }

commit_on_node() { # $1 quest $2 node $3 path $4 content -> new tip
  local branch="refs/heads/bp3/node/$1/$2" tip blob tree new_tip idx="$work/idx-$1-$2"
  tip=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(printf '%s' "$4" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$tip"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$3"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  new_tip=$(printf 'work %s\n' "$2" | git commit-tree "$tree" -p "$tip")
  git update-ref "$branch" "$new_tip" "$tip"; rm -f "$idx"
  printf '%s' "$new_tip"
}
land_node() { # $1 quest $2 node $3 path
  local c; c=$(commit_on_node "$1" "$2" "$3" "content-$2")
  q "$1" u "$2" handoff --commit "$c" --reason work >/dev/null
  q "$1" u "$2" grade --verdict ship --reason ok >/dev/null
}
node_ledger() { git show "bp3/node/$1/$2:docs/quests/$1/nodes/$2/ledger.jsonl"; }

# --- diamond: deps declared, waves, ready, handoff gate ---
q c sched >/dev/null
q sched c na >/dev/null; q sched c nb >/dev/null; q sched c nd >/dev/null
out=$(q sched c nc --depends-on na,nb)
echo "$out" | jq -e '.ok == true and .deps == ["na","nb"]' >/dev/null || fail "create deps: $out"
out=$(q sched r nc)
echo "$out" | jq -e '.deps == ["na","nb"] and .state == "todo"' >/dev/null || fail "deps read from record: $out"
out=$(q r sched)
echo "$out" | jq -e '.ready_set_waves == [["na","nb","nd"],["nc"]] and .ready == ["na","nb","nd"] and .starved == []' >/dev/null || fail "diamond waves: $out"
echo w > w.txt; git add w.txt; git commit -qm w; W=$(git rev-parse HEAD)
if out=$(q sched u nc handoff --commit "$W" --reason early 2>&1); then fail "dep-blocked handoff accepted"; fi
echo "$out" | jq -e '.error.code == "E_DEPENDENCY" and (.error.facts.blocked_by == ["na","nb"])' >/dev/null || fail "handoff gate: $out"
land_node sched na fa.txt; land_node sched nb fb.txt
out=$(q r sched)
echo "$out" | jq -e '.ready == ["nc","nd"] and .ready_set_waves == [["nc","nd"]]' >/dev/null || fail "ready after land: $out"

# --- cycle refused at write time, naming the cycle ---
q sched c nx >/dev/null
q sched dep nx --depends-on nc --reason "chain" >/dev/null
before=$(node_ledger sched nc | wc -l)
if out=$(q sched dep nc --depends-on nx --reason loop 2>&1); then fail "cycle dep accepted"; fi
echo "$out" | jq -e '.error.code == "E_DEP_CYCLE" and (.error.facts.cycle | index("nc") != null) and (.error.facts.cycle | index("nx") != null)' >/dev/null || fail "cycle facts: $out"
[ "$(node_ledger sched nc | wc -l)" = "$before" ] || fail "cycle refusal ledgered"
if out=$(q sched dep na --depends-on na --reason self 2>&1); then fail "self dep accepted"; fi
echo "$out" | jq -e '.error.code == "E_DEP_CYCLE"' >/dev/null || fail "self cycle code: $out"
if out=$(q sched c ghost --depends-on nope 2>&1); then fail "unknown dep accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "unknown dep code: $out"

# --- deps mutable-but-logged, mid-flight edit on the record + E_MISSING_ANCESTOR ---
out=$(q sched dep nd --depends-on na --reason "nd waits for na")
echo "$out" | jq -e '.ok == true and .deps == ["na"] and .state == "todo"' >/dev/null || fail "dep edit: $out"
node_ledger sched nd | tail -1 | jq -e '.edge == "dep" and .from == "todo" and .to == "todo" and .depends_on == ["na"]' >/dev/null || fail "dep line logged"
# $W branched from master, NOT descending from na's landed commit -> E_MISSING_ANCESTOR!
NA_COMMIT=$(q sched r na | jq -r .commit)
if out=$(q sched u nd handoff --commit "$W" --reason "diverged" 2>&1); then fail "diverged dep commit accepted"; fi
echo "$out" | jq -e --arg c "$W" --arg dep "$NA_COMMIT" '.ok == false and .error.code == "E_MISSING_ANCESTOR" and .error.facts.commit == $c and .error.facts.missing == [{"node":"na","commit":$dep}]' >/dev/null || fail "missing ancestor refusal: $out"
# Commit descending from na's landed commit succeeds:
ND_DESC=$(git commit-tree "$(git rev-parse "${NA_COMMIT}^{tree}")" -p "$NA_COMMIT" -m "nd descends from na")
out=$(q sched u nd handoff --commit "$ND_DESC" --reason work)
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "nd handoff (dep ancestor satisfied): $out"
out=$(q sched dep nd --depends-on nb --reason "mid-flight swap")
echo "$out" | jq -e '.ok == true and .state == "handed_off" and .deps == ["nb"]' >/dev/null || fail "mid-flight dep edit: $out"
node_ledger sched nd | tail -1 | jq -e '.edge == "dep" and .from == "handed_off" and .to == "handed_off" and .cycle == 1 and .depends_on == ["nb"]' >/dev/null || fail "mid-flight dep line carries state+cycle"
# Deleted dep and commit-less landed dep are skipped by ancestry check:
q c anc-edge >/dev/null
q anc-edge c del-dep >/dev/null
q anc-edge c nocommit-dep >/dev/null
q anc-edge c child --depends-on del-dep,nocommit-dep >/dev/null
q anc-edge d del-dep --reason "dropped" >/dev/null
# Plant a landed ledger with commit:null on nocommit-dep (e.g. future commit-less node)
nc_tip=$(git rev-parse bp3/node/anc-edge/nocommit-dep); nc_idx="$work/idx-nc"; rm -f "$nc_idx"
printf '{"ts":"2026-01-01T00:00:00Z","edge":"create","from":"","to":"todo","cycle":1,"commit":null,"verdict":null,"reason":"","harness":"t","model":"t","bp3_version":"0.2.0","node_type":"default"}\n{"ts":"2026-01-01T00:01:00Z","edge":"land","from":"approved","to":"landed","cycle":1,"commit":null,"verdict":null,"reason":"gate","harness":"t","model":"t","bp3_version":"0.2.0"}\n' > "$work/nc-ledger.jsonl"
nc_blob=$(git hash-object -w "$work/nc-ledger.jsonl")
GIT_INDEX_FILE="$nc_idx" git read-tree "$nc_tip"
GIT_INDEX_FILE="$nc_idx" git update-index --add --cacheinfo "100644,$nc_blob,docs/quests/anc-edge/nodes/nocommit-dep/ledger.jsonl"
nc_tree=$(GIT_INDEX_FILE="$nc_idx" git write-tree)
nc_nt=$(git commit-tree "$nc_tree" -p "$nc_tip" -m "commitless landed fixture")
git update-ref refs/heads/bp3/node/anc-edge/nocommit-dep "$nc_nt" "$nc_tip"; rm -f "$nc_idx"
out=$(q anc-edge u child handoff --commit "$W" --reason "skips deleted and commitless")
echo "$out" | jq -e '.ok == true and .state == "handed_off"' >/dev/null || fail "deleted/commitless deps should not trigger E_MISSING_ANCESTOR: $out"

# --- blocked blast radius: starved dependents, independents ready ---
q c blast >/dev/null
q blast c bx >/dev/null; q blast c bw >/dev/null
q blast c by --depends-on bx >/dev/null; q blast c bz --depends-on by >/dev/null
q blast u bx block --reason "choose storage" >/dev/null
out=$(q r blast)
echo "$out" | jq -e '.ready == ["bw"] and .starved == [{"blocked":"bx","starved":["by","bz"]}] and ([.inbox[] | select(.node == "bx")] | length == 1)' >/dev/null || fail "starved rollup: $out"
if out=$(q blast u by handoff --commit "$W" --reason early 2>&1); then fail "starved handoff accepted"; fi
echo "$out" | jq -e '.error.code == "E_DEPENDENCY"' >/dev/null || fail "starved handoff gate: $out"

# --- timing derived from ledger timestamps, hand-checked ---
q c timing >/dev/null; q timing c tm >/dev/null
tip=$(git rev-parse bp3/node/timing/tm); idx="$work/idx-tm"; rm -f "$idx"
cat > "$work/tm-ledger.jsonl" <<EOF
{"ts":"2026-01-01T00:00:00Z","edge":"create","from":"","to":"todo","cycle":1,"commit":null,"verdict":null,"reason":"","harness":"t","model":"t","bp3_version":"0.2.0","node_type":"default"}
{"ts":"2026-01-01T00:10:00Z","edge":"handoff","from":"todo","to":"handed_off","cycle":1,"commit":"$W","verdict":null,"reason":"work","harness":"t","model":"t","bp3_version":"0.2.0"}
{"ts":"2026-01-01T00:20:00Z","edge":"grade","from":"handed_off","to":"handed_off","cycle":1,"commit":"$W","verdict":"ship","reason":"ok","harness":"t","model":"t","bp3_version":"0.2.0"}
{"ts":"2026-01-01T00:30:00Z","edge":"verify","from":"handed_off","to":"approved","cycle":1,"commit":"$W","verdict":"pass","reason":"ok","harness":"t","model":"t","bp3_version":"0.2.0"}
{"ts":"2026-01-01T00:51:00Z","edge":"land","from":"approved","to":"landed","cycle":1,"commit":"$W","verdict":null,"reason":"ship","harness":"t","model":"t","bp3_version":"0.2.0"}
EOF
blob=$(git hash-object -w "$work/tm-ledger.jsonl")
GIT_INDEX_FILE="$idx" git read-tree "$tip"
GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,docs/quests/timing/nodes/tm/ledger.jsonl"
tree=$(GIT_INDEX_FILE="$idx" git write-tree)
nt=$(git commit-tree "$tree" -p "$tip" -m "timing fixture")
git update-ref refs/heads/bp3/node/timing/tm "$nt" "$tip"; rm -f "$idx"
out=$(q timing r tm)
echo "$out" | jq -e '.state == "landed" and .timing.wait_s == 600 and .timing.wall_s == 2460 and .timing.dwell_s == {"todo":600,"handed_off":1200,"approved":1260} and .timing.cycles == 1' >/dev/null || fail "timing math: $out"
out2=$(q r timing)
echo "$out2" | jq -e '(.nodes[] | select(.node == "tm") | .timing.wall_s == 2460)' >/dev/null || fail "rollup timing: $out2"
before=$(git rev-parse bp3/node/timing/tm)
q timing r tm >/dev/null; q r timing >/dev/null
[ "$(git rev-parse bp3/node/timing/tm)" = "$before" ] || fail "timing read wrote state"
dirty=$(git status --porcelain | wc -l | tr -d ' ')
[ "$dirty" = "0" ] || fail "timing read dirtied worktree: $dirty entries"
echo "timing read clean: tip unchanged, worktree entries: $dirty"
# No hand-edited state: reads derive timing from ledger timestamps
# and setup from machine-local run configs; neither writes a tracked
# ledger/state file. Counts are echoed so the check carries a
# quotable line (an empty porcelain output is not typed evidence).
tracked_state=$(git ls-files | grep -c -E 'ledger\.jsonl|state\.yaml' || true)
echo "tracked ledger/state files on fixture tip: $tracked_state"

# --- retired setup/W_SETUP_SLOW: setup field stays [] for schema compatibility ---
out=$(q r sched)
echo "$out" | jq -e '.setup == [] and ((has("warnings") | not) or (.warnings | index("W_SETUP_SLOW") == null))' >/dev/null || fail "setup empty compat: $out"

# --- serial land (land: manual): second land re-checks against the new tip ---
printf 'goal_type: manual\nmax_cycles: 1\ngrade:\n  required: true\nland: manual\n' > plans/manual.yaml
git add plans/manual.yaml; git commit -qm manual-plan
q c serial --type manual >/dev/null; q serial c sl-a >/dev/null; q serial c sl-b >/dev/null
CA=$(commit_on_node serial sl-a sa.txt "A"); CB=$(commit_on_node serial sl-b sb.txt "B")
for e in sl-a sl-b; do
  c=$CA; [ "$e" = sl-b ] && c=$CB
  q serial u "$e" handoff --commit "$c" --reason work >/dev/null
  q serial u "$e" grade --verdict ship --reason ok >/dev/null
done
out=$(q serial u sl-a land --reason first)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "first land: $out"
tip1=$(git rev-parse bp3/quest/serial)
out=$(q serial r sl-b)
echo "$out" | jq -e '.state == "approved"' >/dev/null || fail "second still approved: $out"
out=$(q serial u sl-b land --reason second)
echo "$out" | jq -e '.state == "landed"' >/dev/null || fail "second land: $out"
git merge-base --is-ancestor "$tip1" bp3/quest/serial || fail "second land did not build on first tip"
git merge-base --is-ancestor "$CB" bp3/quest/serial || fail "second reviewed commit not in quest tip"
[ "$(git show bp3/quest/serial:sa.txt)" = "A" ] && [ "$(git show bp3/quest/serial:sb.txt)" = "B" ] || fail "serial merge lost files"

# --- help: dep verb and flags documented at their doors ---
out=$(q sched dep -h) || fail "dep -h exit"
echo "$out" | grep -q -- "--depends-on" || fail "dep help flags: $out"
echo "$out" | grep -q "E_DEP_CYCLE" || fail "dep help cycle: $out"
out=$(q sched -h) || fail "node door -h exit"
echo "$out" | grep -q "dep" || fail "node door help dep: $out"
echo "$out" | grep -q -- "--depends-on" || fail "node door help depends-on: $out"

# --- quest-level deps (Store.dep_satisfied): a handoff waits until
# every node of each dependency quest is landed or deleted; a node in
# flight (approved, not landed) still holds it back ---
q c qdep-a --type manual >/dev/null; q qdep-a c e1 >/dev/null; q qdep-a c e2 >/dev/null; q qdep-a c e3 >/dev/null
q c qdep-b --depends-on qdep-a >/dev/null; q qdep-b c e1 >/dev/null
echo qdep > qdep.txt; git add qdep.txt; git commit -qm qdep; QD=$(git rev-parse HEAD)
qdep_refused() { # why
  if out=$(q qdep-b u e1 handoff --commit "$QD" --reason w 2>&1); then fail "handoff accepted: $1"; fi
  echo "$out" | jq -e '.error.code == "E_DEPENDENCY" and .error.facts.blocked_by == ["qdep-a"]' >/dev/null || fail "quest-dep refusal ($1): $out"
}
qdep_refused "every dependency node todo"
q qdep-a u e2 handoff --commit "$QD" --reason w >/dev/null
q qdep-a u e2 grade --verdict ship --reason ok >/dev/null
q qdep-a u e2 land --reason "landed" >/dev/null
q qdep-a d e3 --reason "dropped" >/dev/null
q qdep-a u e1 handoff --commit "$QD" --reason w >/dev/null
q qdep-a u e1 grade --verdict ship --reason ok >/dev/null
qdep_refused "one dependency node approved but not landed"
q qdep-a u e1 land --reason "landed" >/dev/null
out=$(q qdep-b u e1 handoff --commit "$QD" --reason w) || fail "handoff refused once every dependency node was landed or deleted: $out"
echo "$out" | jq -e '.state == "handed_off"' >/dev/null || fail "quest-dep handoff state: $out"

echo "ready tests: ok"
