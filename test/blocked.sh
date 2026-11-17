#!/usr/bin/env bash
# mvp.5: blocked-fail-fast at the bp3 state layer — failure
# is a state transition, never a waiting process. The node
# read itself carries the decision point (reason,
# checkpoint, since), a stale edge attempt after a block
# refuses naming the current state, dirty work is
# checkpointed only when the tree is dirty at block time,
# and a human resume revives the node for a fresh worker
# that binds a new commit from bp3 reads alone.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/graph/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_G_BIN="$work/repo/g-bin" ./bin/bp3 g "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ledger() { git show "bp3/exp/demo/$1:docs/goals/demo/experiments/$1/ledger.jsonl"; }

q c demo >/dev/null

# --- cap escalation: the decision point rests on the node read ---
q demo c cap-node >/dev/null
echo work > w.txt; git add w.txt; git commit -qm work
W=$(git rev-parse HEAD)
q demo u cap-node handoff --commit "$W" --reason work >/dev/null
out=$(q demo u cap-node grade --verdict needs_fix --reason "choose storage shape")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "cap blocks: $out"
out=$(q demo r cap-node)
echo "$out" | jq -e '.state == "blocked" and .blocked.reason == "choose storage shape" and (.blocked | has("checkpoint")) and (.blocked.since | test("^20")) and (.legal_edges == ["resume", "delete"])' >/dev/null || fail "blocked node read carries decision point: $out"
out=$(q r demo)
echo "$out" | jq -e '([.inbox[] | select(.node == "cap-node")] | length == 1) and (.inbox[] | select(.node == "cap-node") | .reason == "choose storage shape")' >/dev/null || fail "exactly one inbox entry: $out"

# --- stale worker after block: refused with current state, nothing ledgered ---
before=$(ledger cap-node | wc -l)
if out=$(q demo u cap-node handoff --commit "$W" --reason "stale retry" 2>&1); then fail "stale handoff after block accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.state == "blocked" and (.error.facts.legal_edges == ["resume", "delete"]) and (.error.guidance | length > 0)' >/dev/null || fail "stale refusal names current state: $out"
[ "$(ledger cap-node | wc -l)" = "$before" ] || fail "stale refusal ledgered"

# --- revival is fresh: human resume, then a new commit binds from reads alone ---
out=$(BP3_DECIDER=human q demo u cap-node resume --reason "use localStorage")
echo "$out" | jq -e '.ok == true and .state == "todo" and .cycle == 2' >/dev/null || fail "resume revives: $out"
out=$(q demo r cap-node)
echo "$out" | jq -e '.state == "todo" and .blocked == null and (.legal_edges | index("handoff") != null)' >/dev/null || fail "revived read is clean todo: $out"
echo more > w.txt; git add w.txt; git commit -qm more
W2=$(git rev-parse HEAD)
out=$(q demo u cap-node handoff --commit "$W2" --reason "fresh worker")
echo "$out" | jq -e '.ok == true and .state == "handed_off" and .cycle == 2' >/dev/null || fail "fresh handoff after resume: $out"

# --- checkpoint only when the human needs the diff: clean block has none ---
q demo c clean-node >/dev/null
out=$(q demo u clean-node block --reason "pick a name")
echo "$out" | jq -e '.ok == true and .state == "blocked" and .human_action_required == true' >/dev/null || fail "clean block: $out"
out=$(q demo r clean-node)
echo "$out" | jq -e '.blocked.reason == "pick a name" and .blocked.checkpoint == null' >/dev/null || fail "clean block carries no checkpoint: $out"
if out=$(q demo u clean-node resume --reason "named" 2>&1); then fail "resume without human accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_HUMAN_REQUIRED"' >/dev/null || fail "resume human gate: $out"

# --- dirty block checkpoints the exact work the human must see ---
q demo c dirty-node >/dev/null
echo wip > wip.txt
out=$(q demo u dirty-node block --reason "review this diff")
echo "$out" | jq -e '.ok == true and .state == "blocked"' >/dev/null || fail "dirty block: $out"
ckpt=$(q demo r dirty-node | jq -r '.blocked.checkpoint')
[ -n "$ckpt" ] && [ "$ckpt" != "null" ] || fail "dirty block checkpoint missing"
[ "$(git cat-file -t "$ckpt")" = "commit" ] || fail "checkpoint is not a commit: $ckpt"
rm wip.txt

# --- siblings continue: a blocked node starves only its dependents ---
q c blast >/dev/null
q blast c bx >/dev/null; q blast c by --depends-on bx >/dev/null; q blast c bw >/dev/null
q blast u bx block --reason "decide" >/dev/null
out=$(q r blast)
echo "$out" | jq -e '.ready == ["bw"] and .starved == [{"blocked": "bx", "starved": ["by"]}]' >/dev/null || fail "siblings continue, dependents starve: $out"

echo "blocked tests: ok"
