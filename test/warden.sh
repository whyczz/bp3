#!/usr/bin/env bash
# warden-v0 (cli.1): top-level bp3 warden fixture covering all 12 plugs
# (8 Layer-1 git/repo + 4 Layer-2 session traces), FEEDBACK.md reviewed skip,
# --last N, --all, --no-sessions, empty transcript dirs, --format table,
# E_USAGE/E_NOT_FOUND rc 2, -h rc 0, and read-only git invariants.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-warden-tests.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/repo/bin" "$work/repo/plans" "$work/home" "$work/empty" "$work/agy"
export BP3_DESKS_DIR="$work/desks"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"

cd "$work/repo"
git init -q -b master
git config user.email t@t.t
git config user.name t
echo base > a.txt
printf '.bp3/\ng-bin\n' > .gitignore
git add .
git commit -qm base

export BP3_HARNESS=agy BP3_MODEL=gemini-3-pro HOME="$work/home"
export BP3_Q_BIN="$work/repo/g-bin"
bp() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
checks=0
assert() { "$@" || fail "$*"; checks=$((checks + 1)); }
expect_eq() {
  checks=$((checks + 1))
  [ "$2" = "$3" ] || fail "$1: want '$2', got '$3'"
}

# Create two active quests so multi_active_quest fires.
mkdir -p docs/quests/2026-11-23-q1 docs/quests/2026-11-23-q2
printf -- '---\nstatus: active\n---\n# q1\n' > docs/quests/2026-11-23-q1/QUEST.md
printf -- '---\nstatus: active\n---\n# q2\n' > docs/quests/2026-11-23-q2/QUEST.md
git add docs/quests
git commit -qm "docs: seed active quests"

bp q c 2026-11-23-q1 --type default >/dev/null
bp q 2026-11-23-q1 c na >/dev/null
bp q 2026-11-23-q1 c nb >/dev/null
bp q c 2026-11-23-q2 --type default >/dev/null

# Cycle 1 of na: bounce on [minor]-only -> minor_only_bounce
echo c1 >> a.txt && git add a.txt && git commit -qm "na c1"
sha1=$(git rev-parse HEAD)
bp q 2026-11-23-q1 n na e handoff --commit "$sha1" --reason "c1" >/dev/null
bp q 2026-11-23-q1 n na e grade --verdict needs_fix --reason "[minor] rename local variable" >/dev/null

# Cycle 2 of na: bounce on vacuous test -> vacuous_test_bounce
echo c2 >> a.txt && git add a.txt && git commit -qm "na c2"
sha2=$(git rev-parse HEAD)
bp q 2026-11-23-q1 n na e handoff --commit "$sha2" --reason "c2" >/dev/null
bp q 2026-11-23-q1 n na e grade --verdict needs_fix --reason "[major] test stays green under mutation" >/dev/null

# Cycle 3 of na: author window with planted Layer-2 anomalies (tool_retry_loop,
# full_gate_in_author, context_bloat >400k agy, mid-node human_steer).
sleep 1
t_prev=$(date -u +%Y-%m-%dT%H:%M:%S)
echo c3 >> a.txt && git add a.txt && git commit -qm "na c3"
sha3=$(git rev-parse HEAD)
short3=${sha3:0:7}
bp q 2026-11-23-q1 n na e handoff --commit "$sha3" --reason "c3" >/dev/null

# Build fake agy author transcript stamped inside c3's author window [grade_c2 .. handoff_c3].
auth_dir="$work/agy/conv-author/.system_generated/logs"
mkdir -p "$auth_dir"
{
  # Kickoff prompt before c3 window (index 0, dropped by assign)
  printf '{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-20T00:00:00Z","content":"kickoff quest"}\n'
  # 3 consecutive failing tool calls -> tool_retry_loop
  printf '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.100Z","model":"gemini-3-pro","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"dune build\\""}}],"input_tokens":10000,"output_tokens":50,"cache_read_tokens":1000}\n' "$t_prev"
  printf '{"step_index":2,"source":"TOOL","type":"GENERIC","status":"ERROR","created_at":"%s.150Z","content":"err1"}\n' "$t_prev"
  printf '{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.200Z","model":"gemini-3-pro","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"dune build\\""}}],"input_tokens":10000,"output_tokens":50,"cache_read_tokens":1000}\n' "$t_prev"
  printf '{"step_index":4,"source":"TOOL","type":"GENERIC","status":"ERROR","created_at":"%s.250Z","content":"err2"}\n' "$t_prev"
  printf '{"step_index":5,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.300Z","model":"gemini-3-pro","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"dune build\\""}}],"input_tokens":10000,"output_tokens":50,"cache_read_tokens":1000}\n' "$t_prev"
  printf '{"step_index":6,"source":"TOOL","type":"GENERIC","status":"ERROR","created_at":"%s.350Z","content":"err3"}\n' "$t_prev"
  # 2x make check-full -> full_gate_in_author
  printf '{"step_index":7,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.400Z","model":"gemini-3-pro","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"make check-full\\""}}],"input_tokens":20000,"output_tokens":50,"cache_read_tokens":1000}\n' "$t_prev"
  printf '{"step_index":8,"source":"TOOL","type":"GENERIC","status":"DONE","created_at":"%s.450Z","content":"ok"}\n' "$t_prev"
  printf '{"step_index":9,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.500Z","model":"gemini-3-pro","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"make check-full\\""}}],"input_tokens":30000,"output_tokens":50,"cache_read_tokens":1000}\n' "$t_prev"
  printf '{"step_index":10,"source":"TOOL","type":"GENERIC","status":"DONE","created_at":"%s.550Z","content":"ok"}\n' "$t_prev"
  # Mid-node human steer -> human_steer
  printf '{"step_index":11,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"%s.600Z","content":"mid-node steer fix"}\n' "$t_prev"
  # Handoff cast with context_end > 400k -> context_bloat (agy limit)
  printf '{"step_index":12,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.700Z","model":"gemini-3-pro","tool_calls":[{"name":"run_command","args":{"CommandLine":"\\"./bin/bp3 q 2026-11-23-q1 n na e handoff --commit %s --reason c3\\""}}],"input_tokens":410000,"output_tokens":100,"cache_read_tokens":10000}\n' "$t_prev" "$short3"
  printf '{"step_index":13,"source":"TOOL","type":"GENERIC","status":"DONE","created_at":"%s.750Z","content":"{\\"ok\\":true,\\"state\\":\\"handed_off\\"}"}\n' "$t_prev"
} > "$auth_dir/transcript.jsonl"

# Grade transcript for na c3: wall_s = 0.8s (within 1s window) and grade.tokens_out = 30000 (>25k floor) > author.tokens_out = 350 -> grade_inversion
t_grade=$(date -u +%Y-%m-%dT%H:%M:%S)
grade_dir="$work/agy/conv-grade/.system_generated/logs"
mkdir -p "$grade_dir"
{
  printf '{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"%s.100Z","content":"Grade na at %s in quest 2026-11-23-q1, cycle 3."}\n' "$t_grade" "$short3"
  printf '{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"%s.800Z","model":"gemini-3-pro","tool_calls":[],"input_tokens":10000,"output_tokens":30000,"cache_read_tokens":1000}\n' "$t_grade"
} > "$grade_dir/transcript.jsonl"

# Leave a grade-* desk open on na after landing -> desk_leak
bp harness desk prepare 2026-11-23-q1 na --run grade-na-c3-a1 --commit "$sha3" >/dev/null
bp q 2026-11-23-q1 n na e grade --verdict ship --reason "clean" >/dev/null

# Node nb: landed with zero metrics -> coverage_gap
echo nb1 >> a.txt && git add a.txt && git commit -qm "nb c1"
sha_nb=$(git rev-parse HEAD)
bp q 2026-11-23-q1 n nb e handoff --commit "$sha_nb" --reason "nb" >/dev/null
bp q 2026-11-23-q1 n nb e grade --verdict ship --reason "clean" >/dev/null

# Scrape metrics so na has grade + author samples (grade_inversion) and nb has 0 (coverage_gap).
bp q 2026-11-23-q1 metrics scrape --claude-dir "$work/empty" --pi-dir "$work/empty" --agy-dir "$work/agy" >/dev/null

# Plant a status-only demo/ commit after final node_fin -> must NOT fire post_land_bugfix
mkdir -p docs/quests/2026-11-23-q1/demo
printf '#!/usr/bin/env bash\necho demo\n' > docs/quests/2026-11-23-q1/demo/demo.sh
git add docs/quests/2026-11-23-q1/demo/demo.sh && git commit -qm "docs(warden): add landing demo"
out_demo_only=$(bp warden 2026-11-23-q1 --no-sessions)
assert jq -e 'all(.findings[]; .rule != "post_land_bugfix")' <<< "$out_demo_only" >/dev/null

# Plant a non-status post-land bugfix commit after final node_fin -> post_land_bugfix
echo hotfix >> a.txt && git add a.txt && git commit -qm "fix: post-land bugfix"

# Snapshot git refs & status to assert 100% read-only execution.
refs_before=$(git show-ref)
status_before=$(git status --porcelain)

# 1. Full two-layer quest audit: all 12 rules + missing_repo_config + W_NO_REPO_CONFIG fire!
out=$(bp warden 2026-11-23-q1 --dir "$work/empty" --pi-dir "$work/empty" --agy-dir "$work/agy")
assert jq -e '.ok == true and .scope == "quest"' <<< "$out" >/dev/null
assert jq -e '.warnings[0].code == "W_NO_REPO_CONFIG"' <<< "$out" >/dev/null
assert jq -e 'any(.findings[]; .rule == "missing_repo_config" and .severity == "minor" and .evidence_ref == "repo:backpack.toml")' <<< "$out" >/dev/null
assert jq -e '.sessions_scanned >= 2' <<< "$out" >/dev/null
for rule in multi_active_quest cycle_outlier minor_only_bounce vacuous_test_bounce \
            grade_inversion coverage_gap desk_leak post_land_bugfix \
            tool_retry_loop full_gate_in_author context_bloat human_steer; do
  # shellcheck disable=SC2016  # $r is a jq --arg variable, not a shell expansion
  assert jq -e --arg r "$rule" 'any(.findings[]; .rule == $r and (.observed | length > 0) and (.threshold | length > 0) and (.evidence_ref | length > 0) and (.summary | length > 0))' <<< "$out" >/dev/null
done
assert jq -e '.counts.total == (.findings | length) and .counts.by_layer.git > 0 and .counts.by_layer.session > 0' <<< "$out" >/dev/null

# Read-only guarantee: refs & status untouched.
expect_eq "git refs unchanged" "$refs_before" "$(git show-ref)"
expect_eq "git status unchanged" "$status_before" "$(git status --porcelain)"

# 2. --no-sessions runs Layer 1 only with sessions_scanned = 0
out_nos=$(bp warden 2026-11-23-q1 --no-sessions)
assert jq -e '.ok == true and .sessions_scanned == 0 and .counts.by_layer.session == 0 and .counts.by_layer.git >= 8' <<< "$out_nos" >/dev/null

# 3. Empty transcript dirs degrade cleanly to sessions_scanned = 0, exit 0
out_empty=$(bp warden 2026-11-23-q1 --dir "$work/empty" --pi-dir "$work/empty" --agy-dir "$work/empty")
assert jq -e '.ok == true and .sessions_scanned == 0 and .counts.by_layer.session == 0' <<< "$out_empty" >/dev/null

# 4. --format table prints readable table, exit 0
tbl=$(bp warden 2026-11-23-q1 --no-sessions --format table)
assert grep -qF "RULE" <<< "$tbl"
assert grep -qF "OBSERVED" <<< "$tbl"
assert grep -qF "cycle_outlier" <<< "$tbl"

# 5. FEEDBACK.md skip on bare bp3 warden vs --all vs explicit <quest> vs --last N
printf '# Feedback\n' > docs/quests/2026-11-23-q1/FEEDBACK.md
mkdir -p docs/quests/2026-11-23-q3
printf -- '---\nstatus: landed\n---\n# q3\n' > docs/quests/2026-11-23-q3/QUEST.md
bp q c 2026-11-23-q3 --type default >/dev/null

out_bare=$(bp warden --no-sessions)
assert jq -e '.ok == true and .scope == "repo"' <<< "$out_bare" >/dev/null
assert jq -e '(.quests | index("2026-11-23-q1")) == null and (.quests | index("2026-11-23-q2")) != null and (.quests | index("2026-11-23-q3")) != null' <<< "$out_bare" >/dev/null

out_all=$(bp warden --all --no-sessions)
assert jq -e '(.quests | index("2026-11-23-q1")) != null and (.quests | index("2026-11-23-q2")) != null and (.quests | index("2026-11-23-q3")) != null' <<< "$out_all" >/dev/null

out_explicit=$(bp warden 2026-11-23-q1 --no-sessions)
assert jq -e '.scope == "quest" and .quests == ["2026-11-23-q1"]' <<< "$out_explicit" >/dev/null

out_last1=$(bp warden --last 1 --no-sessions)
assert jq -e '.quests == ["2026-11-23-q3"]' <<< "$out_last1" >/dev/null

# 6. Refusal paths: exit 2 with E_USAGE / E_NOT_FOUND
rc=0
err_flag=$(bp warden --bad-flag 2>&1) || rc=$?
expect_eq "bad flag rc" "2" "$rc"
assert jq -e '.ok == false and .error.code == "E_USAGE"' <<< "$err_flag" >/dev/null

rc=0
err_unk=$(bp warden no-such-quest 2>&1) || rc=$?
expect_eq "unknown quest rc" "2" "$rc"
assert jq -e '.ok == false and .error.code == "E_NOT_FOUND"' <<< "$err_unk" >/dev/null

rc=0
err_both=$(bp warden 2026-11-23-q1 --all 2>&1) || rc=$?
expect_eq "quest + --all rc" "2" "$rc"
assert jq -e '.ok == false and .error.code == "E_USAGE"' <<< "$err_both" >/dev/null

# 7. -h prints docstring on stdout, exit 0
help_out=$(bp warden -h)
assert grep -qF "bp3 warden" <<< "$help_out"
assert grep -qF -- "--no-sessions" <<< "$help_out"

# 8. manifest.2: adding backpack.toml clears missing_repo_config & W_NO_REPO_CONFIG and honors [warden].grade_wall_s
bp q 2026-11-23-q3 c nslow >/dev/null
echo slow1 >> a.txt && git add docs/quests a.txt && git commit -qm "nslow c1"
sha_ns=$(git rev-parse HEAD)
bp q 2026-11-23-q3 n nslow e handoff --commit "$sha_ns" --reason "nslow" >/dev/null
bp q 2026-11-23-q3 n nslow e grade --verdict ship --reason "clean" >/dev/null
# Plant a 450s grade.wall_s sample on nslow's state branch so we test the threshold without sleeping 450s
ns_br="bp3/node/2026-11-23-q3/nslow"
ns_tip=$(git rev-parse "$ns_br")
ns_idx=$(mktemp)
GIT_INDEX_FILE="$ns_idx" git read-tree "$ns_tip"
ns_blob=$(printf '{"metric":"grade.wall_s","quest":"2026-11-23-q3","node":"nslow","cycle":1,"run":"agy:c1","model":"gemini-3-pro","value":450.0,"at":"2026-11-25T10:07:30Z","source":"grade-transcripts"}\n' | git hash-object -w --stdin)
GIT_INDEX_FILE="$ns_idx" git update-index --add --cacheinfo "100644,$ns_blob,docs/quests/2026-11-23-q3/nodes/nslow/metrics.jsonl"
ns_tree=$(GIT_INDEX_FILE="$ns_idx" git write-tree)
ns_new=$(git commit-tree "$ns_tree" -p "$ns_tip" -m "fixture: 450s grade.wall_s")
git update-ref "refs/heads/$ns_br" "$ns_new" "$ns_tip"
rm -f "$ns_idx"
# Without backpack.toml (default 300s): 450s grade wall fires cycle_outlier
out_def=$(bp warden 2026-11-23-q3 --no-sessions)
assert jq -e 'any(.findings[]; .rule == "cycle_outlier" and .node == "nslow")' <<< "$out_def" >/dev/null
# With backpack.toml grade_wall_s = 600: clears missing_repo_config, W_NO_REPO_CONFIG, and 450s cycle_outlier
printf 'version = 1\nrepo = "warden-fx"\n\n[warden]\ngrade_wall_s = 600\n' > backpack.toml
out_cfg=$(bp warden 2026-11-23-q3 --no-sessions)
assert jq -e '(has("warnings") | not) and all(.findings[]; .rule != "missing_repo_config" and .rule != "cycle_outlier")' <<< "$out_cfg" >/dev/null
# With grade_wall_s = 400: 450s grade wall fires cycle_outlier with > 400s threshold
printf 'version = 1\nrepo = "warden-fx"\n\n[warden]\ngrade_wall_s = 400\n' > backpack.toml
out_400=$(bp warden 2026-11-23-q3 --no-sessions)
assert jq -e 'any(.findings[]; .rule == "cycle_outlier" and .node == "nslow" and .threshold == "> 400s grade wall")' <<< "$out_400" >/dev/null

printf 'warden tests: ok (%s assertions)\n' "$checks"
