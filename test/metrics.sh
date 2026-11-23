#!/usr/bin/env bash
# metric-collectors (sink.1, scrape.1): metrics scrape joins grade
# edges to synthetic Claude Code subagent transcripts and appends
# samples to metrics.jsonl on each node's state branch, one commit
# per node; metrics r reads them back. Covers the outcome buckets
# (unchecked, owner, ambiguous), idempotence, the rollup staying
# untouched, and which ~/.claude/projects dirs are scanned.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans" "$work/home"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model HOME="$work/home"
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
n=0
expect() { # $1 label, $2 want, $3 got
  n=$((n + 1)); [ "$2" = "$3" ] || fail "$1: want '$2', got '$3'"; }
tip() { git rev-parse "refs/heads/bp3/node/q1/$1"; }
count() { git rev-list --count "refs/heads/bp3/node/q1/$1"; }

# a subagent transcript: one prompt naming $node and $sha, two
# messages (one streamed over two lines), three tool calls, one of them
# answered (t1, 0.6 s: grade.tool_s)
transcript() { # $1 file $2 node $3 sha $4 second (YYYY-MM-DDTHH:MM:SS)
  mkdir -p "$(dirname "$1")"
  {
    printf '{"type":"user","timestamp":"%s.100Z","sessionId":"s1","agentId":"a1","message":{"role":"user","content":"Grade %s at %s."}}\n' "$4" "$2" "$3"
    printf '{"type":"assistant","timestamp":"%s.200Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1"}],"usage":{"input_tokens":2,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":500}}}\n' "$4"
    printf '{"type":"assistant","timestamp":"%s.300Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t2"}],"usage":{"input_tokens":2,"output_tokens":40,"cache_read_input_tokens":0,"cache_creation_input_tokens":500}}}\n' "$4"
    printf '{"type":"user","timestamp":"%s.800Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}\n' "$4"
    printf '{"type":"assistant","timestamp":"%s.900Z","message":{"id":"m2","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t3"}],"usage":{"input_tokens":1,"output_tokens":5,"cache_read_input_tokens":500,"cache_creation_input_tokens":20}}}\n' "$4"
  } > "$1"
}

# the harness report: a .meta.json naming the spawning call, and a
# queue-operation enqueue line in the parent session file
harness_report() { # $1 transcript $2 tool-use id $3 context $4 tool uses $5 duration ms $6 second
  printf '{"toolUseId":"%s"}\n' "$2" > "${1%.jsonl}.meta.json"
  printf '{"type":"queue-operation","operation":"enqueue","timestamp":"%s.950Z","content":"<task-notification><tool-use-id>%s</tool-use-id><usage><subagent_tokens>%s</subagent_tokens><tool_uses>%s</tool_uses><duration_ms>%s</duration_ms></usage></task-notification>"}\n' \
    "$6" "$2" "$3" "$4" "$5" >> "$(dirname "$(dirname "$1")").jsonl"
}

new_commit() { # $1 quest $2 node -> a commit sha on the node branch
  local branch="refs/heads/bp3/node/$1/$2" t blob tree idx="$work/idx-$1-$2"
  t=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(printf 'work %s\n' "$2" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$t"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,work-$2.txt"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  t=$(printf 'work %s\n' "$2" | git commit-tree "$tree" -p "$t")
  git update-ref "$branch" "$t"; rm -f "$idx"; printf '%s' "$t"
}

claude="$work/claude"; mkdir -p "$claude"
q c q1 >/dev/null
for node in na nb nc; do q q1 c "$node" >/dev/null; done

# the author's main session: its own messages (one streamed over two
# lines), a subagent's line that must not count, and the Bash call that
# cast the handoff, the commit only in its result
author_lines() { # $1 session file $2 node $3 second
  {
    printf '{"type":"assistant","timestamp":"%s.100Z","isSidechain":false,"sessionId":"s1","message":{"id":"w1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"tw1","name":"Read","input":{}}],"usage":{"input_tokens":3,"output_tokens":30,"cache_read_input_tokens":1000,"cache_creation_input_tokens":100}}}\n' "$3"
    printf '{"type":"assistant","timestamp":"%s.200Z","isSidechain":false,"sessionId":"s1","message":{"id":"w1","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":3,"output_tokens":60,"cache_read_input_tokens":1000,"cache_creation_input_tokens":100}}}\n' "$3"
    printf '{"type":"assistant","timestamp":"%s.300Z","isSidechain":true,"sessionId":"s1","message":{"id":"sub","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":9,"output_tokens":9999,"cache_read_input_tokens":9999,"cache_creation_input_tokens":9}}}\n' "$3"
    # shellcheck disable=SC2016  # the command text is data; nothing expands
    printf '{"type":"assistant","timestamp":"%s.400Z","isSidechain":false,"sessionId":"s1","message":{"id":"w2","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"th1","name":"Bash","input":{"command":"bp3 q q1 u %s handoff --commit \\"$(git rev-parse HEAD)\\" --reason work"}}],"usage":{"input_tokens":1,"output_tokens":5,"cache_read_input_tokens":2000,"cache_creation_input_tokens":10}}}\n' "$3" "$2"
  } >> "$1"
}
author_result() { # $1 session file $2 commit
  printf '{"type":"user","timestamp":"2099-01-01T00:00:00.000Z","isSidechain":false,"message":{"content":[{"type":"tool_result","tool_use_id":"th1","content":"{\\"ok\\":true,\\"state\\":\\"handed_off\\",\\"commit\\":\\"%s\\"}"}]}}\n' "$2" >> "$1"
}

# na: authored in session s1; one grader transcript in the window, its
# harness report agrees, and one junk line rides along; nb: owner
# graded, no author session; nc: two transcripts name it, so the
# grade join refuses
for node in na nb nc; do
  sha=$(new_commit q1 "$node")
  asec=$(date -u +%Y-%m-%dT%H:%M:%S)
  if [ "$node" = na ]; then author_lines "$claude/s1.jsonl" na "$asec"; fi
  q q1 u "$node" handoff --commit "$sha" --reason work >/dev/null
  if [ "$node" = na ]; then author_result "$claude/s1.jsonl" "$sha"; fi
  if [ "$node" = nb ]; then nb_sha=$sha nb_sec=$asec; fi
  sec=$(date -u +%Y-%m-%dT%H:%M:%S)
  case "$node" in
    na) transcript "$claude/s1/subagents/agent-a1.jsonl" "$node" "$sha" "$sec"
        echo 'not json' >> "$claude/s1/subagents/agent-a1.jsonl"
        harness_report "$claude/s1/subagents/agent-a1.jsonl" toolu_a1 526 3 800 "$sec" ;;
    nc) transcript "$claude/s2/subagents/agent-c1.jsonl" "$node" "$sha" "$sec"
        transcript "$claude/s2/subagents/agent-c2.jsonl" "$node" "$sha" "$sec" ;;
  esac
  q q1 u "$node" grade --verdict ship --verify-verdict pass --reason ok >/dev/null
done

# s3: another session that worked during nb's window, then, after every
# handoff, greps nb's ledger; its result names handed_off and nb's
# commit, but it is a read, not the cast (grader, scrape.2 round 1), so
# nb stays author_missing
rsec=2099-01-01T00:00:00   # well after every window: a later read
printf '{"type":"assistant","timestamp":"%s.500Z","isSidechain":false,"sessionId":"s3","message":{"id":"r0","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":1,"output_tokens":7,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n' "$nb_sec" > "$claude/s3.jsonl"
printf '{"type":"assistant","timestamp":"%s.900Z","isSidechain":false,"sessionId":"s3","message":{"id":"r1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"tr1","name":"Bash","input":{"command":"./bin/bp3 q q1 n nb r | jq .ledger[] | grep handoff"}}],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n' "$rsec" >> "$claude/s3.jsonl"
printf '{"type":"user","timestamp":"%s.950Z","isSidechain":false,"message":{"content":[{"type":"tool_result","tool_use_id":"tr1","content":"{\\"edge\\":\\"handoff\\",\\"to\\":\\"handed_off\\",\\"commit\\":\\"%s\\"}"}]}}\n' "$rsec" "$nb_sha" >> "$claude/s3.jsonl"

# s4: inside nb's window, another session hands off ANOTHER quest's
# node nb (ids repeat across quests) and gets a result cut to
# {ok, state}; it never names q1, so it is not nb's cast (grader,
# scrape.2 round 2)
# shellcheck disable=SC2016  # the command text is data; nothing expands
printf '{"type":"assistant","timestamp":"%s.600Z","isSidechain":false,"sessionId":"s4","message":{"id":"o1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"to1","name":"Bash","input":{"command":"bp3 q some-other-quest n nb e handoff --commit \\"$SHA\\" | jq -c ."}}],"usage":{"input_tokens":1,"output_tokens":3,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n' "$nb_sec" > "$claude/s4.jsonl"
printf '{"type":"user","timestamp":"%s.700Z","isSidechain":false,"message":{"content":[{"type":"tool_result","tool_use_id":"to1","content":"{\\"ok\\":true,\\"state\\":\\"handed_off\\"}"}]}}\n' "$nb_sec" >> "$claude/s4.jsonl"

# s5 (grader probe C, round 3): inside nb's window a cast of another node in
# q1 names nb in its --reason; s6 (probe F3): another quest's nb cast and
# a read of ours in one command. Neither casts q1's nb.
# shellcheck disable=SC2016  # the command text is data; nothing expands
printf '{"type":"assistant","timestamp":"%s.650Z","isSidechain":false,"sessionId":"s5","message":{"id":"c1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"tc1","name":"Bash","input":{"command":"bp3 q q1 n nz e handoff --commit \\"$C\\" --reason unblocks-nb | jq -c ."}}],"usage":{"input_tokens":1,"output_tokens":3,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n' "$nb_sec" > "$claude/s5.jsonl"
printf '{"type":"user","timestamp":"%s.660Z","isSidechain":false,"message":{"content":[{"type":"tool_result","tool_use_id":"tc1","content":"{\\"ok\\":true,\\"state\\":\\"handed_off\\"}"}]}}\n' "$nb_sec" >> "$claude/s5.jsonl"
# shellcheck disable=SC2016  # the command text is data; nothing expands
printf '{"type":"assistant","timestamp":"%s.670Z","isSidechain":false,"sessionId":"s6","message":{"id":"f1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"tf1","name":"Bash","input":{"command":"bp3 q other-quest n nb e handoff --commit \\"$S\\" | jq -c .; bp3 q q1 n nb r | jq -c ."}}],"usage":{"input_tokens":1,"output_tokens":3,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n' "$nb_sec" > "$claude/s6.jsonl"
printf '{"type":"user","timestamp":"%s.680Z","isSidechain":false,"message":{"content":[{"type":"tool_result","tool_use_id":"tf1","content":"{\\"ok\\":true,\\"quest\\":\\"other-quest\\",\\"node\\":\\"nb\\",\\"state\\":\\"handed_off\\"}\\n{\\"quest\\":\\"q1\\",\\"node\\":\\"nb\\",\\"state\\":\\"handed_off\\"}"}]}}\n' "$nb_sec" >> "$claude/s6.jsonl"

# q2/nd: the harness report counts 4 tool calls, the transcript 3
q c q2 >/dev/null; q q2 c nd >/dev/null
sha=$(new_commit q2 nd)
q q2 u nd handoff --commit "$sha" --reason work >/dev/null
sec=$(date -u +%Y-%m-%dT%H:%M:%S)
transcript "$work/claude2/s9/subagents/agent-d1.jsonl" nd "$sha" "$sec"
harness_report "$work/claude2/s9/subagents/agent-d1.jsonl" toolu_d1 526 4 800 "$sec"
q q2 u nd grade --verdict ship --verify-verdict pass --reason ok >/dev/null

# --- today's surface: refusals ---
expect "unknown quest" E_NOT_FOUND "$(q nope metrics r | jq -r .error.code || true)"
expect "unknown verb" E_USAGE "$(q q1 metrics nope | jq -r .error.code || true)"
expect "help names scrape" yes "$(q q1 metrics -h | grep -q 'metrics scrape' && echo yes)"

# --- guard.1: a repo a newer MAJOR bp3 stamped refuses a scrape that has
# samples to write, E_VERSION_AHEAD, no ref moved. Run in a copy, so the
# cases below still see an unscraped repo. ---
cp -R "$work/repo" "$work/ahead"
ahead_out=$(
  cd "$work/ahead"
  lp=docs/quests/q1/nodes/nc/ledger.jsonl; br=refs/heads/bp3/node/q1/nc
  t0=$(git rev-parse "$br"); idx=$(mktemp)
  GIT_INDEX_FILE="$idx" git read-tree "$t0"
  blob=$({ git show "$t0:$lp"
           printf '{"ts":"2026-01-01T00:00:00Z","edge":"note","from":"todo","to":"todo","cycle":1,"commit":null,"verdict":null,"reason":"fixture stamp","harness":"t","model":"t","bp3_version":"99.0.0"}\n'
         } | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,$lp"
  t1=$(git commit-tree "$(GIT_INDEX_FILE="$idx" git write-tree)" -p "$t0" -m "fixture stamp 99.0.0")
  git update-ref "$br" "$t1" "$t0"; rm -f "$idx"
  refs0=$(git for-each-ref --format='%(refname) %(objectname)' refs/heads/)
  rc=0; out=$(q q1 metrics scrape --claude-dir "$claude" 2>&1) || rc=$?
  refs1=$(git for-each-ref --format='%(refname) %(objectname)' refs/heads/)
  echo "$rc $(jq -r .error.code <<< "$out") $([ "$refs0" = "$refs1" ] && echo unmoved || echo moved)"
)
expect "major-ahead scrape refuses, no ref moved" "1 E_VERSION_AHEAD unmoved" "$ahead_out"

# --- usage.1: a usage-less line inside na's author window means the
# window writes nothing (author_bad_usage, exit 1), as a mismatched grade
# does; the same line outside every window changes nothing. Run in
# copies, so the cases below still see an unscraped repo. ---
na_ts=$(head -1 "$claude/s1.jsonl" | jq -r .timestamp)   # na's first author line
bad_usage_scrape() { # $1 copy name, $2 timestamp of the usage-less line -> "rc authored bad written"
  cp -R "$work/repo" "$work/$1"; cp -R "$claude" "$work/$1-claude"
  printf '{"type":"assistant","timestamp":"%s","isSidechain":false,"sessionId":"s1","message":{"id":"w9","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n' "$2" >> "$work/$1-claude/s1.jsonl"
  ( cd "$work/$1"
    rc=0; out=$(q q1 metrics scrape --claude-dir "$work/$1-claude") || rc=$?
    echo "$rc $(jq -r '.nodes.na | "\(.authored) \(.author_bad_usage) \(.written)"' <<< "$out")" )
}
expect "usage-less line in na's window: nothing authored, exit 1" "1 0 1 8" "$(bad_usage_scrape bad-in "${na_ts%.100Z}.250Z")"
expect "usage-less line outside every window: na authored" "0 1 0 16" "$(bad_usage_scrape bad-out 2098-01-01T00:00:00.000Z)"

# --- scrape: buckets, samples, one commit per node ---
rollup_before=$(q r q1 | jq -S 'del(.nodes[].timing)')
na0=$(count na) nb0=$(count nb) nc0=$(count nc)
out=$(q q1 metrics scrape --claude-dir "$claude")
expect "scrape ok" true "$(jq -r .ok <<< "$out")"
expect "na checked against its report" 1 "$(jq -r .nodes.na.checked <<< "$out")"
expect "na written: 8 grade + 8 author" 16 "$(jq -r .nodes.na.written <<< "$out")"
expect "na junk line counted, not read as zero" 1 "$(jq -r .nodes.na.skipped_lines <<< "$out")"
expect "nb owner" 1 "$(jq -r .nodes.nb.owner <<< "$out")"
expect "nc ambiguous" 1 "$(jq -r .nodes.nc.ambiguous <<< "$out")"
expect "nc writes nothing" 0 "$(jq -r .nodes.nc.written <<< "$out")"
expect "na one commit" $((na0 + 1)) "$(count na)"
expect "nb no commit" "$nb0" "$(count nb)"
expect "nc no commit" "$nc0" "$(count nc)"
expect "rollup untouched" "$rollup_before" "$(q r q1 | jq -S 'del(.nodes[].timing)')"

# --- metrics r: the numbers the transcript holds, counted once ---
grade=$(q q1 metrics r | jq -c '.nodes.na.cycles["1"].grade')
expect "tool calls" 3 "$(jq -r .tool_calls <<< "$grade")"
expect "wall" 0.8 "$(jq -r .wall_s <<< "$grade")"
expect "grade tool time: t1's span, the unanswered calls count nothing" 0.6 "$(jq -r .tool_s <<< "$grade")"
author=$(q q1 metrics r | jq -c '.nodes.na.cycles["1"].author')
expect "author times written" "true true true" "$(jq -r '"\(has("wall_s")) \(has("active_s")) \(has("tool_s"))"' <<< "$author")"
expect "author times: 0 <= tool <= active <= wall" true "$(jq -r '0 <= .tool_s and .tool_s <= .active_s and .active_s <= .wall_s' <<< "$author")"
expect "rollup carries author wall and active stats" "true true" "$(q q1 metrics r | jq -r '"\(.rollup.author_wall_s | type == "object") \(.rollup.author_active_s | type == "object")"')"
expect "output, last snapshot" 45 "$(jq -r .tokens_out <<< "$grade")"
expect "cache write" 520 "$(jq -r .tokens_cache_write <<< "$grade")"
expect "context end" 526 "$(jq -r .context_end <<< "$grade")"
expect "run" claude:s1/a1 "$(jq -r .run <<< "$grade")"
expect "owner node has no samples" false "$(q q1 metrics r | jq -c '.nodes.nb.cycles["1"] | has("grade") or has("author")')"

# --- derive.1: timing from the ledger, roll-ups, computed on read ---
view=$(q q1 metrics r)
expect "per-cycle todo sums to the rollup's dwell" "$(q r q1 | jq -c '[.nodes[] | {(.node): (.timing.dwell_s.todo // 0)}] | add')" \
  "$(jq -c '[.nodes | to_entries[] | {(.key): ([.value.cycles[].timing.todo_s // 0] | add // 0)}] | add' <<< "$view")"
expect "quest rollup: grades and measured" "3 1" "$(jq -r '"\(.rollup.grades) \(.rollup.grades_measured)"' <<< "$view")"
expect "quest rollup: handoffs and measured" "3 1" "$(jq -r '"\(.rollup.handoffs) \(.rollup.handoffs_measured)"' <<< "$view")"
expect "quest rollup: median grade wall" 0.8 "$(jq -r .rollup.grade_wall_s.median <<< "$view")"
expect "na rollup: author cache read" 3000 "$(jq -r .nodes.na.rollup.spend.author.tokens_cache_read <<< "$view")"
expect "derived timing is never written" 16 "$(git show "$(tip na):docs/quests/q1/nodes/na/metrics.jsonl" | wc -l | tr -d ' ')"

# --- author window: the session that cast na's handoff, counted once ---
expect "na authored" 1 "$(jq -r .nodes.na.authored <<< "$out")"
expect "nb no session: author_missing, not zero" 1 "$(jq -r .nodes.nb.author_missing <<< "$out")"
expect "a later read of nb is not its author" 0 "$(jq -r .nodes.nb.authored <<< "$out")"
author=$(q q1 metrics r | jq -c '.nodes.na.cycles["1"].author')
expect "author tool calls" 2 "$(jq -r .tool_calls <<< "$author")"
expect "author output, last snapshot, no subagent line" 65 "$(jq -r .tokens_out <<< "$author")"
expect "author cache read" 3000 "$(jq -r .tokens_cache_read <<< "$author")"
expect "author run is the session" claude:s1 "$(jq -r .run <<< "$author")"
expect "sink is GENERATED json lines" 16 "$(git show "$(tip na):docs/quests/q1/nodes/na/metrics.jsonl" | jq -c . | wc -l | tr -d ' ')"

# --- idempotent: a second scrape writes nothing ---
t=$(tip na)
out=$(q q1 metrics scrape --claude-dir "$claude")
expect "rescrape written" 0 "$(jq -r .nodes.na.written <<< "$out")"
expect "rescrape skipped" 16 "$(jq -r .nodes.na.skipped <<< "$out")"
expect "rescrape no commit" "$t" "$(tip na)"

# --- default dirs: this repo's project dir and its desks, nothing else ---
slug=$(git rev-parse --show-toplevel | tr '/.' '--')
projects="$HOME/.claude/projects"
mkdir -p "$projects"
out=$(q q1 metrics scrape)
expect "no projects dir entries" 0 "$(jq -r '.dirs | length' <<< "$out")"
mkdir -p "$projects/$slug--bp3-worktrees-q1" "$projects/$slug-sibling"
cp -R "$claude/s1" "$projects/$slug--bp3-worktrees-q1/"      # a desk's dir: scanned
cp -R "$claude/s2" "$projects/$slug-sibling/"                # another repo's: never scanned
out=$(q q1 metrics scrape)
expect "desk dir scanned" "$projects/$slug--bp3-worktrees-q1" "$(jq -r '.dirs | join(",")' <<< "$out")"
expect "desk transcript already counted" 8 "$(jq -r .nodes.na.skipped <<< "$out")"
expect "no parent session copied: unchecked" 1 "$(jq -r .nodes.na.unchecked <<< "$out")"
expect "sibling stays out" 1 "$(jq -r .nodes.nc.owner <<< "$out")"

# --- a transcript that disagrees with its report writes nothing, exit 1 ---
nd0=$(git rev-list --count refs/heads/bp3/node/q2/nd)
rc=0; out=$(q q2 metrics scrape --claude-dir "$work/claude2") || rc=$?
expect "mismatch exits 1" 1 "$rc"
expect "mismatch not ok" false "$(jq -r .ok <<< "$out")"
expect "nd mismatched" 1 "$(jq -r .nodes.nd.mismatched <<< "$out")"

# --- pi-metrics scrape.1: pi grader sessions join like Claude transcripts.
# pa: one pi session names it -> self_checked, written as pi:<id>;
# pb: a pi session and a Claude transcript both name it -> ambiguous;
# pc: a pi session whose total is off by one -> mismatched, exit 1 ---
pi_session() { # $1 dir $2 id $3 node $4 sha $5 second $6 total of the last line [$7 prompt, JSON-escaped]
  mkdir -p "$1"
  {
    printf '{"type":"session","version":3,"id":"%s","timestamp":"%s.050Z","cwd":"/r"}\n' "$2" "$5"
    printf '{"type":"message","id":"u1","parentId":null,"timestamp":"%s.100Z","message":{"role":"user","content":"%s"}}\n' "$5" "${7:-Grade $3 at ${4:0:7}.}"
    printf '{"type":"message","id":"a1","parentId":"u1","timestamp":"%s.200Z","message":{"role":"assistant","model":"gpt-6.1-sol","provider":"openai","content":[{"type":"toolCall","id":"c1","name":"bash","arguments":{"command":"make check-full"}}],"usage":{"input":100,"output":10,"cacheRead":0,"cacheWrite":0,"totalTokens":110}}}\n' "$5"
    printf '{"type":"message","id":"r1","parentId":"a1","timestamp":"%s.500Z","message":{"role":"toolResult","toolCallId":"c1","toolName":"bash","content":[],"isError":false}}\n' "$5"
    printf '{"type":"message","id":"a2","parentId":"r1","timestamp":"%s.800Z","message":{"role":"assistant","model":"gpt-6.1-sol","provider":"openai","content":[{"type":"text","text":"VERDICT: ship"}],"usage":{"input":120,"output":5,"cacheRead":40,"cacheWrite":0,"totalTokens":%s}}}\n' "$5" "$6"
  } > "$1/$5_$2.jsonl"
}
pi3="$work/pi3"; claude3="$work/claude3"; mkdir -p "$claude3"
q c q3 >/dev/null
for node in pa pb pc pd pe; do q q3 c "$node" >/dev/null; done
for node in pa pb pc pd pe; do
  sha=$(new_commit q3 "$node")
  q q3 u "$node" handoff --commit "$sha" --reason work >/dev/null
  sec=$(date -u +%Y-%m-%dT%H:%M:%S)
  case "$node" in
    pa) pi_session "$pi3" "grade-pa-1" pa "$sha" "$sec" 165 ;;
    pb) pi_session "$pi3" "grade-pb-1" pb "$sha" "$sec" 165
        transcript "$claude3/s7/subagents/agent-b1.jsonl" pb "$sha" "$sec" ;;
    pc) pi_session "$pi3" "grade-pc-1" pc "$sha" "$sec" 166 ;;
    # measure.1 cycle 2: pd's own grader names it on its first line; another
    # brief names pd's commit only further down (its previous-round part)
    pd) pi_session "$pi3" "grade-pd-1" pd "$sha" "$sec" 165
        pi_session "$pi3" "grade-px-1" pd "$sha" "$sec" 165 "Grade px at 1111111 in quest q3, cycle 2.\\nOther nodes' commits in that range: ${sha:0:7} (pd)." ;;
    # an older hand-written brief: node and commit below the first line, alone
    pe) pi_session "$pi3" "grade-pe-1" pe "$sha" "$sec" 165 "You are a fresh grader.\\nGrade pe at ${sha:0:7}." ;;
  esac
  q q3 u "$node" grade --verdict ship --verify-verdict pass --reason ok >/dev/null
done
rc=0; out=$(q q3 metrics scrape --claude-dir "$claude3" --pi-dir "$pi3") || rc=$?
expect "pi: a bad total exits 1" 1 "$rc"
expect "pi: pi_dirs reported" "$pi3" "$(jq -r '.pi_dirs | join(",")' <<< "$out")"
expect "pa self_checked, not checked" "1 0 0" "$(jq -r '.nodes.pa | "\(.self_checked) \(.checked) \(.unchecked)"' <<< "$out")"
expect "pa written: 8 grade samples" 8 "$(jq -r .nodes.pa.written <<< "$out")"
expect "pb claimed by pi and Claude: ambiguous" "1 0" "$(jq -r '.nodes.pb | "\(.ambiguous) \(.written)"' <<< "$out")"
expect "pc bad total: mismatched, nothing written" "1 0" "$(jq -r '.nodes.pc | "\(.mismatched) \(.written)"' <<< "$out")"
expect "pd: the join line beats a later mention" "1 0" "$(jq -r '.nodes.pd | "\(.self_checked) \(.ambiguous)"' <<< "$out")"
expect "pe: a lone claimant still joins below the first line" "1 0" "$(jq -r '.nodes.pe | "\(.self_checked) \(.ambiguous)"' <<< "$out")"
view=$(q q3 metrics r)
expect "pa sample run and model" "pi:grade-pa-1 gpt-6.1-sol" "$(jq -r '.nodes.pa.cycles."1".grade | "\(.run) \(.model)"' <<< "$view")"
expect "pa cost read from pi" "1 220 15 40 165" "$(jq -r '.nodes.pa.cycles."1".grade | "\(.tool_calls) \(.tokens_in) \(.tokens_out) \(.tokens_cache_read) \(.context_end)"' <<< "$view")"
expect "pa wall: first user line to last entry" 0.7 "$(jq -r '.nodes.pa.cycles."1".grade.wall_s' <<< "$view")"
expect "pa tool time: toolCall to toolResult" 0.3 "$(jq -r '.nodes.pa.cycles."1".grade.tool_s' <<< "$view")"

# --- brief.2: each joined grade says whether its brief was bp3's own ---
pi_brief() { # $1 dir $2 id $3 second $4 prompt (raw text; jq escapes it)
  mkdir -p "$1"
  { jq -cn --arg id "$2" --arg ts "$3.050Z" '{type:"session",version:3,id:$id,timestamp:$ts,cwd:"/r"}'
    jq -cn --arg ts "$3.100Z" --arg p "$4" '{type:"message",id:"u1",parentId:null,timestamp:$ts,message:{role:"user",content:$p}}'
    printf '{"type":"message","id":"a1","parentId":"u1","timestamp":"%s.200Z","message":{"role":"assistant","model":"gpt-6.1-sol","provider":"openai","content":[{"type":"toolCall","id":"c1","name":"bash","arguments":{"command":"make check-full"}}],"usage":{"input":100,"output":10,"cacheRead":0,"cacheWrite":0,"totalTokens":110}}}\n' "$3"
    printf '{"type":"message","id":"r1","parentId":"a1","timestamp":"%s.500Z","message":{"role":"toolResult","toolCallId":"c1","toolName":"bash","content":[],"isError":false}}\n' "$3"
    printf '{"type":"message","id":"a2","parentId":"r1","timestamp":"%s.800Z","message":{"role":"assistant","model":"gpt-6.1-sol","provider":"openai","content":[{"type":"text","text":"VERDICT: ship"}],"usage":{"input":120,"output":5,"cacheRead":40,"cacheWrite":0,"totalTokens":165}}}\n' "$3"
  } > "$1/$3_$2.jsonl"
}
pi4="$work/pi4"
q c q4 >/dev/null
for node in va vb vc vd ve vf vg vh; do q q4 c "$node" >/dev/null; mkdir -p "docs/quests/q4/nodes/$node"
  printf '# %s\n\n## Acceptance gates\n\nGATE %s\n\n## Diagram\n\nx\n' "$node" "$node" > "docs/quests/q4/nodes/$node/NODE.md"; done
printf '# Grading\n\nRun the gate.\n' > GRADING.md
git add -A; git commit -qm "q4 nodes"; c4=$(git rev-parse HEAD)
brief4() { q q4 n "$1" brief --desk /tmp | jq -r .brief; }   # a fixed desk: a random mktemp path can hold "vd"
for node in va vb vc vd ve vg vh; do q q4 u "$node" handoff --commit "$c4" --reason work >/dev/null; done
sec=$(date -u +%Y-%m-%dT%H:%M:%S)
pi_brief "$pi4" grade-va-1 "$sec" "$(brief4 va)"
pi_brief "$pi4" grade-vb-1 "$sec" "$(brief4 vb)
Focus on parse.ml only."
pi_brief "$pi4" grade-vc-1 "$sec" "$(brief4 vc)"   # vc's first round: graded, then sent back
q q4 u vc grade --verdict needs_fix --mechanical --reason "SENTINEL-REASON" >/dev/null
echo fix > vc-fix.txt; git add vc-fix.txt; git commit -qm "vc: fix"; c4b=$(git rev-parse HEAD)
q q4 u vc handoff --commit "$c4b" --reason fix >/dev/null
sec2=$(date -u +%Y-%m-%dT%H:%M:%S)
pi_brief "$pi4" grade-vc-2 "$sec2" "$(brief4 vc)"
# ve: another node (vf) hands off a commit inside ve's range after ve's own
# handoff; the verb, run later, and the scrape both cut at ve's handoff
q q4 u ve grade --verdict needs_fix --mechanical --reason x >/dev/null
echo vf > vf.txt; git add vf.txt; git commit -qm "vf: work"; cvf=$(git rev-parse HEAD)
echo ve > ve-fix.txt; git add ve-fix.txt; git commit -qm "ve: fix"; cve=$(git rev-parse HEAD)
q q4 u ve handoff --commit "$cve" --reason fix >/dev/null
s0=$(date -u +%s); while [ "$(date -u +%s)" = "$s0" ]; do :; done   # vf's stamp a whole second later
q q4 u vf handoff --commit "$cvf" --reason work >/dev/null
b_ve=$(brief4 ve)
expect "ve's brief, rendered after vf's handoff, leaves vf out" 0 "$(grep -c "${cvf:0:7} (vf)" <<< "$b_ve" || true)"
pi_brief "$pi4" grade-ve-2 "$(date -u +%Y-%m-%dT%H:%M:%S)" "$b_ve"
# vg, vh: the Claude subagent path (no harness report: unchecked, still written)
claude_brief() { # $1 file $2 second $3 prompt
  mkdir -p "$(dirname "$1")"
  { jq -cn --arg ts "$2.100Z" --arg p "$3" '{type:"user",timestamp:$ts,sessionId:"s9",agentId:"g9",message:{role:"user",content:$p}}'
    printf '{"type":"assistant","timestamp":"%s.200Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1"}],"usage":{"input_tokens":2,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":500}}}\n' "$2"
  } > "$1"
}
sec3=$(date -u +%Y-%m-%dT%H:%M:%S)
claude_brief "$work/claude4/s9/subagents/agent-g9.jsonl" "$sec3" "$(brief4 vg)"
harness_report "$work/claude4/s9/subagents/agent-g9.jsonl" tu-g9 512 1 100 "$sec3"   # vg: checked; vh: no report, unchecked
claude_brief "$work/claude4/s9/subagents/agent-h9.jsonl" "$sec3" "$(brief4 vh)
Ship it if make check passes."
for node in va vb vc vd ve vf vg vh; do q q4 u "$node" grade --verdict ship --verify-verdict pass --reason ok >/dev/null; done
rc=0; out=$(q q4 metrics scrape --claude-dir "$work/claude4" --pi-dir "$pi4") || rc=$?
expect "brief check never fails the scrape" 0 "$rc"
expect "va: the rendered brief, desk included: verbatim" "1 1 0" "$(jq -r '.nodes.va | "\(.self_checked) \(.brief_verbatim) \(.brief_edited)"' <<< "$out")"
expect "vb: one added line: edited, grade still written" "1 0 1 8" "$(jq -r '.nodes.vb | "\(.self_checked) \(.brief_verbatim) \(.brief_edited) \(.written)"' <<< "$out")"
expect "vc: each round rendered as of its own handoff: both verbatim" "2 2 0" "$(jq -r '.nodes.vc | "\(.self_checked) \(.brief_verbatim) \(.brief_edited)"' <<< "$out")"
expect "vd: owner-graded: neither" "1 0 0" "$(jq -r '.nodes.vd | "\(.owner) \(.brief_verbatim) \(.brief_edited)"' <<< "$out")"
expect "ve: a later handoff in range changes neither side: verbatim" "1 1 0" "$(jq -r '.nodes.ve | "\(.self_checked) \(.brief_verbatim) \(.brief_edited)"' <<< "$out")"
expect "vg: a Claude subagent given the brief, checked: verbatim" "1 1 0" "$(jq -r '.nodes.vg | "\(.checked) \(.brief_verbatim) \(.brief_edited)"' <<< "$out")"
expect "vh: a Claude subagent given one more line: edited" "1 0 1" "$(jq -r '.nodes.vh | "\(.unchecked) \(.brief_verbatim) \(.brief_edited)"' <<< "$out")"

# default pi dirs: pi's own naming of this repo and its desks, nothing else
pslug="--$(git rev-parse --show-toplevel | sed 's#^/##; s#[/:\\]#-#g')--"
pisessions="$HOME/.pi/agent/sessions"
mkdir -p "$pisessions/$pslug" "$pisessions/${pslug%--}-.bp3-worktrees-q3--" "$pisessions/${pslug%--}-sibling--" "$pisessions/${pslug%--}-.bp3-worktreesX--"
rc=0; out=$(q q3 metrics scrape --claude-dir "$claude3") || rc=$?
expect "default pi dirs: the repo and its desk only" "$pisessions/$pslug,$pisessions/${pslug%--}-.bp3-worktrees-q3--" "$(jq -r '.pi_dirs | join(",")' <<< "$out")"
expect "nd writes nothing" "$nd0" "$(git rev-list --count refs/heads/bp3/node/q2/nd)"

echo "metrics tests: ok ($n assertions)"
