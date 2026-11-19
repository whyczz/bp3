#!/usr/bin/env bash
# Shared setup for the test/harness/ pieces (test-pyramid tier.1).
# The prelude and fixture lines are copied verbatim from the
# single-file harness.sh; only root (resolved from this file)
# and the EXIT trap (also reaps background jobs) changed.
# Sourced by each piece; never run directly.
# shellcheck disable=SC2034  # work/root/store/LIVE are read by pieces
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin" "$work/repo/plans"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cp "$root"/plans/*.yaml "$work/repo/plans/"
perl -pi -e 's/^max_cycles: .*/max_cycles: 1/' "$work/repo/plans/default.yaml"  # fixtures assert one review round
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base

export BP3_HARNESS=muse-code BP3_MODEL=test-model
q() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 q "$@"; }
h() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# fake children: quests done-q (landed), gate-q (blocked), toy (todo)
fixture_quests() {
  q c done-q >/dev/null; q done-q c e1 >/dev/null
  q c gate-q >/dev/null; q gate-q c e1 >/dev/null
  q c toy >/dev/null; q toy c e1 >/dev/null
  echo work > b.txt; git add b.txt; git commit -qm work
  B=$(git rev-parse HEAD)
  q done-q u e1 handoff --commit "$B" --reason work >/dev/null
  q done-q u e1 grade --verdict ship --reason ok >/dev/null
  q done-q u e1 verify --verdict pass --reason ok >/dev/null
  q done-q u e1 land --reason "done" >/dev/null
  q gate-q u e1 handoff --commit "$B" --reason work >/dev/null
  q gate-q u e1 grade --verdict needs_fix --reason broken >/dev/null
}

# lifecycle derivation store, fixtures, the live pid LIVE, and run records
fixture_runs() {
  store=".git/bp3/run-lifecycle-derivations"
  mkdir -p "$store" fixtures
  echo tape > fixtures/fresh.log
  touch -t 202001010000 fixtures/stale.log
  sleep 60 & LIVE=$!
  printf '%s\n' '{"kind":"init_record","run_id":"R-init","harness":"muse-code","quest":"toy"}' > "$store/R-init.jsonl"
  printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-active\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/fresh.log\"}" > "$store/R-active.jsonl"
  printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-orphan\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":999999,\"tape_path\":\"$work/repo/fixtures/stale.log\"}" > "$store/R-orphan.jsonl"
  printf '%s\n' '{"kind":"init_record","run_id":"R-fin","harness":"pi","quest":"toy"}' '{"kind":"observation","exit_observed":true,"tape_closed":true}' > "$store/R-fin.jsonl"
  printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-settle-live\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/fresh.log\"}" '{"kind":"observation","settle_row":true,"tape_closed":false}' > "$store/R-settle-live.jsonl"
  printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-blind\",\"harness\":\"pi\",\"quest\":\"toy\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/missing.log\"}" > "$store/R-blind.jsonl"
  printf '%s\n' '{"kind":"init_record","run_id":"R-torn","harness":"pi","quest":"toy"}' '{"kind":"observation","tape_seen":tru' > "$store/R-torn.jsonl"
}

# pi and muse tape stores, find-tape records, tape-dir exports
fixture_tapes() {
  mkdir -p fixtures/pi-store fixtures/muse-store/S-muse
  printf '%s\n' '{"type":"session","version":3,"id":"S-pi","timestamp":"2026-01-01T00:00:00Z","cwd":"/tmp"}' '{"type":"message","id":"e1","message":{"role":"user","content":"BP3_RUN_ID=R-pi-run work"}}' '{"type":"message","id":"e2","message":{"role":"assistant","content":"done"}}' '{"type":"message","id":"e3","message":{"role":"assistant","content":"bye"}}' > fixtures/pi-store/pi1.jsonl
  printf '%s\n' '{"session_id":"S-muse","id":"m1","content":"BP3_RUN_ID=R-muse-run work"}' > fixtures/muse-store/S-muse/session.jsonl
  printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-find\",\"harness\":\"pi\",\"session_id\":\"S-pi\",\"pid\":$LIVE,\"tape_path\":\"$work/repo/fixtures/pi-store/pi1.jsonl\",\"quest\":\"toy\"}" > "$store/R-find.jsonl"
  printf '%s\n' "{\"kind\":\"init_record\",\"run_id\":\"R-bad\",\"harness\":\"pi\",\"tape_path\":\"$work/repo/fixtures/pi-store/pi1.jsonl\",\"quest\":\"toy\"}" > "$store/R-bad.jsonl"
  export BP3_PI_TAPE_DIR="$work/repo/fixtures/pi-store" BP3_MUSE_TAPE_DIR="$work/repo/fixtures/muse-store"
}

# watch fixture dir, created by the watch section in the single file
fixture_watch_dir() {
  mkdir -p fixtures/watch
}
