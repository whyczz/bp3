#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal jq expressions using $vars.
# Quest-level functional fixtures for `bp3 ticket` (sqlite-control-plane ticket.1):
#   1. Happy path across two repos (bp3 init auto-register, add/list/read/claim/unclaim/claim/done/db info)
#   2. Refusal & 10-way concurrent claim race (strict --to, 1 ok + 9 E_ALREADY_CLAIMED + 0 E_DB_ERROR, terminal E_ILLEGAL_EDGE)
#   3. Restart persistence & cross-surface consistency (read/list json/list table/db info agree; real DB untouched)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-ticket-tests.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export BP3_DB="${BP3_DB:-$work/bp3.sqlite}"
export BP3_COMPLETIONS_DIR="$work/completions"
export BP3_Q_BIN="$repo/_build/default/src/quest/main.exe"
[ -x "$BP3_Q_BIN" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

checks=0
assert() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; checks=$((checks + 1)); }
rejects() {
  local want_rc="$1"; shift
  local rc=0
  "$@" >"$work/out" 2>"$work/err" || rc=$?
  [ "$rc" -eq "$want_rc" ] || {
    printf 'FAIL: expected rc %s, got %s for %s (out=%s err=%s)\n' \
      "$want_rc" "$rc" "$*" "$(cat "$work/out")" "$(cat "$work/err")" >&2
    exit 1
  }
  checks=$((checks + 1))
}

mk_repo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b master
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  echo hi > "$d/README.md"
  git -C "$d" add .
  git -C "$d" commit -qm init
}

# Record real ~/.local/share/bp3/bp3.sqlite existence/mtime before tests
real_db="${HOME}/.local/share/bp3/bp3.sqlite"
real_db_before="absent"
if [ -e "$real_db" ]; then
  real_db_before=$(stat -f '%m:%z' "$real_db" 2>/dev/null || stat -c '%Y:%s' "$real_db")
fi

# 0. -h creates no DB
out=$("$repo/bin/bp3" ticket -h)
assert test ! -e "$BP3_DB"
assert grep -q 'bp3 ticket unclaim' <<< "$out"

# =====================================================================
# Fixture 1: Happy path — cross-repo lifecycle across two repos
# =====================================================================
fake_bp3="$work/fake-bp3"
fake_pred="$work/fake-predictor"
mk_repo "$fake_bp3"
mk_repo "$fake_pred"

BP3_TARGET="$fake_bp3" "$repo/bin/bp3" init --harness=claude >/dev/null
BP3_TARGET="$fake_pred" "$repo/bin/bp3" init --harness=claude >/dev/null
# Commit rendered skills so fake-bp3 starts clean before any ticket commands
git -C "$fake_bp3" add . && git -C "$fake_bp3" commit -qm "init bp3 skills"
git -C "$fake_pred" add . && git -C "$fake_pred" commit -qm "init bp3 skills"

repos_json=$("$repo/bin/bp3" repo list)
assert jq -e '([.repos[].name] | index("fake-bp3") != null) and ([.repos[].name] | index("fake-predictor") != null)' <<< "$repos_json" >/dev/null

# File ticket from fake-predictor (omitting --from to verify auto-inference)
body_text=$'line1\nline2'
add_res=$(cd "$fake_pred" && "$repo/bin/bp3" ticket add --to fake-bp3 --kind bug --title "host desk check fails" --body "$body_text")
assert jq -e '.ok == true and .ticket.id == 1 and .ticket.from_repo == "fake-predictor" and .ticket.to_repo == "fake-bp3" and .ticket.kind == "bug" and .ticket.status == "open"' <<< "$add_res" >/dev/null

# Inspect & transition from fake-bp3
list_tbl=$(cd "$fake_bp3" && "$repo/bin/bp3" ticket list --to fake-bp3 --format table)
assert grep -q '^id' <<< "$list_tbl"
assert grep -q 'fake-bp3' <<< "$list_tbl"
assert grep -q 'host desk check fails' <<< "$list_tbl"

read_tbl=$(cd "$fake_bp3" && "$repo/bin/bp3" ticket read 1 --format table)
assert grep -q 'line1' <<< "$read_tbl"
assert grep -q 'line2' <<< "$read_tbl"

c1=$(cd "$fake_bp3" && "$repo/bin/bp3" ticket claim 1 --by worker-a)
assert jq -e '.ok == true and .ticket.status == "claimed" and .ticket.claimed_by == "worker-a" and (.ticket.claimed_at != null)' <<< "$c1" >/dev/null

u1=$(cd "$fake_bp3" && "$repo/bin/bp3" ticket unclaim 1 --reason "handoff")
assert jq -e '.ok == true and .ticket.status == "open" and .ticket.claimed_by == null and .ticket.claimed_at == null' <<< "$u1" >/dev/null

c2=$(cd "$fake_bp3" && "$repo/bin/bp3" ticket claim 1 --by worker-b)
assert jq -e '.ok == true and .ticket.status == "claimed" and .ticket.claimed_by == "worker-b"' <<< "$c2" >/dev/null

d1=$(cd "$fake_bp3" && "$repo/bin/bp3" ticket "done" 1 --reason "fixed")
assert jq -e '.ok == true and .ticket.status == "done" and .ticket.resolution_reason == "fixed" and (.ticket.resolved_at != null)' <<< "$d1" >/dev/null

# fake-bp3 working tree untouched and zero bp3/* branches created
assert test -z "$(git -C "$fake_bp3" status --porcelain)"
assert test -z "$(git -C "$fake_bp3" for-each-ref --format='%(refname)' 'refs/heads/bp3/')"

info1=$("$repo/bin/bp3" db info)
assert jq -e '.ok == true and .counts.repos == 2 and .counts.tickets_open == 0 and .counts.tickets_total == 1' <<< "$info1" >/dev/null

# =====================================================================
# Fixture 2: Refusal & 10-way concurrent claim race
# =====================================================================
race_db="$work/race.sqlite"
BP3_DB="$race_db" "$repo/bin/bp3" repo add "$fake_bp3" --name fake-bp3 >/dev/null
t_race=$(BP3_DB="$race_db" "$repo/bin/bp3" ticket add --from fake-predictor --to fake-bp3 --kind bug --title "race target")
assert jq -e '.ok == true and .ticket.id == 1' <<< "$t_race" >/dev/null

# (a) Unregistered --to -> exit 2 E_NOT_FOUND with facts.registered
rejects 2 env BP3_DB="$race_db" "$repo/bin/bp3" ticket add --to nonexistent --title "x"
assert jq -e '.ok == false and .error.code == "E_NOT_FOUND" and .error.facts.repo == "nonexistent" and .error.facts.registered == ["fake-bp3"]' "$work/out" >/dev/null
info_after_refusal=$(BP3_DB="$race_db" "$repo/bin/bp3" db info)
assert jq -e '.counts.tickets_total == 1 and .counts.tickets_open == 1' <<< "$info_after_refusal" >/dev/null

# (b) 10 concurrent background claims on ticket 1
mkdir -p "$work/race"
pids=()
for i in $(seq 1 10); do
  (
    rc=0
    BP3_DB="$race_db" "$repo/bin/bp3" ticket claim 1 --by "worker-$i" >"$work/race/$i.out" 2>"$work/race/$i.err" || rc=$?
    printf '%s\n' "$rc" >"$work/race/$i.rc"
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done

ok_count=0
already_count=0
db_err_count=0
for i in $(seq 1 10); do
  rc=$(cat "$work/race/$i.rc")
  out_file="$work/race/$i.out"
  if [ "$rc" -eq 0 ] && jq -e '.ok == true and .ticket.status == "claimed"' "$out_file" >/dev/null 2>&1; then
    ok_count=$((ok_count + 1))
  elif [ "$rc" -eq 1 ] && jq -e '.ok == false and .error.code == "E_ALREADY_CLAIMED"' "$out_file" >/dev/null 2>&1; then
    already_count=$((already_count + 1))
  elif jq -e '.error.code == "E_DB_ERROR"' "$out_file" >/dev/null 2>&1; then
    db_err_count=$((db_err_count + 1))
  else
    printf 'FAIL: unexpected race result #%s rc=%s out=%s err=%s\n' "$i" "$rc" "$(cat "$out_file")" "$(cat "$work/race/$i.err")" >&2
    exit 1
  fi
done
assert test "$ok_count" -eq 1
assert test "$already_count" -eq 9
assert test "$db_err_count" -eq 0

# (c) Done once succeeds, done twice refuses E_ILLEGAL_EDGE with legal_verbs:[] and leaves row unchanged
done_once=$(BP3_DB="$race_db" "$repo/bin/bp3" ticket "done" 1 --reason "shipped")
assert jq -e '.ok == true and .ticket.status == "done"' <<< "$done_once" >/dev/null
rejects 1 env BP3_DB="$race_db" "$repo/bin/bp3" ticket "done" 1 --reason "again"
assert jq -e '.ok == false and .error.code == "E_ILLEGAL_EDGE" and .error.facts.id == 1 and .error.facts.status == "done" and .error.facts.verb == "done" and .error.facts.legal_verbs == []' "$work/out" >/dev/null
after_done=$(BP3_DB="$race_db" "$repo/bin/bp3" ticket read 1)
assert jq -e '.ticket.resolution_reason == "shipped"' <<< "$after_done" >/dev/null

# =====================================================================
# Fixture 3: Cross-process restart persistence & cross-surface consistency
# =====================================================================
r_json=$("$repo/bin/bp3" ticket read 1)
l_json=$("$repo/bin/bp3" ticket list --status all)
l_tbl=$("$repo/bin/bp3" ticket list --status all --format table)
d_info=$("$repo/bin/bp3" db info)

assert jq -e '.ok == true and .ticket.id == 1 and .ticket.status == "done" and .ticket.claimed_by == "worker-b" and .ticket.resolution_reason == "fixed"' <<< "$r_json" >/dev/null
assert jq -e '.ok == true and (.tickets | length) == 1 and .tickets[0].id == 1 and .tickets[0].status == "done" and .tickets[0].claimed_by == "worker-b" and .tickets[0].resolution_reason == "fixed"' <<< "$l_json" >/dev/null
assert grep -q 'worker-b' <<< "$l_tbl"
assert grep -q 'done' <<< "$l_tbl"
assert jq -e '.counts.repos == 2 and .counts.tickets_open == 0 and .counts.tickets_total == 1' <<< "$d_info" >/dev/null

real_db_after="absent"
if [ -e "$real_db" ]; then
  real_db_after=$(stat -f '%m:%z' "$real_db" 2>/dev/null || stat -c '%Y:%s' "$real_db")
fi
assert test "$real_db_before" = "$real_db_after"

printf 'ticket tests: ok (%s assertions)\n' "$checks"
