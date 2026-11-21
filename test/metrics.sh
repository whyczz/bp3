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
# messages (one streamed over two lines), three tool calls
transcript() { # $1 file $2 node $3 sha $4 second (YYYY-MM-DDTHH:MM:SS)
  mkdir -p "$(dirname "$1")"
  {
    printf '{"type":"user","timestamp":"%s.100Z","sessionId":"s1","agentId":"a1","message":{"role":"user","content":"Grade %s at %s."}}\n' "$4" "$2" "$3"
    printf '{"type":"assistant","timestamp":"%s.200Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1"}],"usage":{"input_tokens":2,"output_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":500}}}\n' "$4"
    printf '{"type":"assistant","timestamp":"%s.300Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t2"}],"usage":{"input_tokens":2,"output_tokens":40,"cache_read_input_tokens":0,"cache_creation_input_tokens":500}}}\n' "$4"
    printf '{"type":"assistant","timestamp":"%s.900Z","message":{"id":"m2","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t3"}],"usage":{"input_tokens":1,"output_tokens":5,"cache_read_input_tokens":500,"cache_creation_input_tokens":20}}}\n' "$4"
  } > "$1"
}

new_commit() { # $1 node -> a commit sha on the node branch
  local branch="refs/heads/bp3/node/q1/$1" t blob tree idx="$work/idx-$1"
  t=$(git rev-parse "$branch"); rm -f "$idx"
  blob=$(printf 'work %s\n' "$1" | git hash-object -w --stdin)
  GIT_INDEX_FILE="$idx" git read-tree "$t"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "100644,$blob,work-$1.txt"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  t=$(printf 'work %s\n' "$1" | git commit-tree "$tree" -p "$t")
  git update-ref "$branch" "$t"; rm -f "$idx"; printf '%s' "$t"
}

claude="$work/claude"
q c q1 >/dev/null
for node in na nb nc; do q q1 c "$node" >/dev/null; done

# na: one grader transcript in the window; nb: owner graded (no
# transcript); nc: two transcripts name it, so the join refuses
for node in na nb nc; do
  sha=$(new_commit "$node")
  q q1 u "$node" handoff --commit "$sha" --reason work >/dev/null
  sec=$(date -u +%Y-%m-%dT%H:%M:%S)
  case "$node" in
    na) transcript "$claude/s1/subagents/agent-a1.jsonl" "$node" "$sha" "$sec" ;;
    nc) transcript "$claude/s2/subagents/agent-c1.jsonl" "$node" "$sha" "$sec"
        transcript "$claude/s2/subagents/agent-c2.jsonl" "$node" "$sha" "$sec" ;;
  esac
  q q1 u "$node" grade --verdict ship --verify-verdict pass --reason ok >/dev/null
done

# --- today's surface: refusals ---
expect "unknown quest" E_NOT_FOUND "$(q nope metrics r | jq -r .error.code || true)"
expect "unknown verb" E_USAGE "$(q q1 metrics nope | jq -r .error.code || true)"
expect "help names scrape" yes "$(q q1 metrics -h | grep -q 'metrics scrape' && echo yes)"

# --- scrape: buckets, samples, one commit per node ---
rollup_before=$(q r q1 | jq -S 'del(.nodes[].timing)')
na0=$(count na) nb0=$(count nb) nc0=$(count nc)
out=$(q q1 metrics scrape --claude-dir "$claude")
expect "scrape ok" true "$(jq -r .ok <<< "$out")"
expect "na unchecked" 1 "$(jq -r .nodes.na.unchecked <<< "$out")"
expect "na written" 7 "$(jq -r .nodes.na.written <<< "$out")"
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
expect "output, last snapshot" 45 "$(jq -r .tokens_out <<< "$grade")"
expect "cache write" 520 "$(jq -r .tokens_cache_write <<< "$grade")"
expect "context end" 526 "$(jq -r .context_end <<< "$grade")"
expect "run" claude:s1/a1 "$(jq -r .run <<< "$grade")"
expect "owner node has no samples" '{}' "$(q q1 metrics r | jq -c .nodes.nb.cycles)"
expect "sink is GENERATED json lines" 7 "$(git show "$(tip na):docs/quests/q1/nodes/na/metrics.jsonl" | jq -c . | wc -l | tr -d ' ')"

# --- idempotent: a second scrape writes nothing ---
t=$(tip na)
out=$(q q1 metrics scrape --claude-dir "$claude")
expect "rescrape written" 0 "$(jq -r .nodes.na.written <<< "$out")"
expect "rescrape skipped" 7 "$(jq -r .nodes.na.skipped <<< "$out")"
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
expect "desk transcript already counted" 7 "$(jq -r .nodes.na.skipped <<< "$out")"
expect "sibling stays out" 1 "$(jq -r .nodes.nc.owner <<< "$out")"

echo "metrics tests: ok ($n assertions)"
