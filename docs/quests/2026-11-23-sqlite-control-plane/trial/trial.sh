#!/usr/bin/env bash
# Runnable landing trial for 2026-11-23-sqlite-control-plane.
# Scratch sandbox only (mktemp -d + BP3_DB + BP3_COMPLETIONS_DIR);
# never mutates this repo or ~/.local/share/bp3/bp3.sqlite.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../../../.." && pwd)
qbin="$repo/_build/default/src/quest/main.exe"
[ -x "$qbin" ] || { echo "build main.exe first: make check" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

export BP3_DB="$work/bp3.sqlite"
export BP3_COMPLETIONS_DIR="$work/completions"
export BP3_Q_BIN="$qbin"
unset BP3_ROOT || true

say() { printf '\n=== %s ===\n' "$*"; }

mk_repo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b master
  git -C "$d" config user.email trial@bp3.local
  git -C "$d" config user.name "bp3 Trial"
  echo base > "$d/README.md"
  git -C "$d" add . && git -C "$d" commit -qm "chore: init"
}

say "1. Happy path: SQLite init (WAL v1), auto-register on bp3 init, cross-repo ticket lifecycle"
echo "$ bp3 db info"
info0=$("$repo/bin/bp3" db info)
echo "$info0" | jq -c '{ok, schema_version, journal_mode, counts}'
echo "$info0" | jq -e '.ok == true and .schema_version == 1 and .journal_mode == "wal"' >/dev/null

fake_bp3="$work/fake-bp3"
fake_pred="$work/fake-predictor"
mk_repo "$fake_bp3"
mk_repo "$fake_pred"

BP3_TARGET="$fake_bp3" "$repo/bin/bp3" init --harness=claude >/dev/null
BP3_TARGET="$fake_pred" "$repo/bin/bp3" init --harness=claude >/dev/null
git -C "$fake_bp3" add . && git -C "$fake_bp3" commit -qm "chore: init bp3 skills"
git -C "$fake_pred" add . && git -C "$fake_pred" commit -qm "chore: init bp3 skills"

echo "$ bp3 repo list --format table"
"$repo/bin/bp3" repo list --format table

echo "$ (cd fake-predictor && bp3 ticket add --to fake-bp3 --kind bug --title ...)"
body=$'repro step 1\nrepro step 2'
t1=$(cd "$fake_pred" && "$repo/bin/bp3" ticket add --to fake-bp3 --kind bug --title "host desk check fails" --body "$body")
echo "$t1" | jq -c '{ok, id: .ticket.id, from: .ticket.from_repo, to: .ticket.to_repo, status: .ticket.status}'
echo "$t1" | jq -e '.ok == true and .ticket.id == 1 and .ticket.from_repo == "fake-predictor"' >/dev/null

echo "$ bp3 ticket list --to fake-bp3 --format table"
"$repo/bin/bp3" ticket list --to fake-bp3 --format table

echo "$ bp3 ticket read 1 --format table"
"$repo/bin/bp3" ticket read 1 --format table

echo "$ bp3 ticket claim 1 --by worker-a -> unclaim -> claim worker-b -> done"
"$repo/bin/bp3" ticket claim 1 --by worker-a | jq -c '{ok, status: .ticket.status, claimed_by: .ticket.claimed_by}'
"$repo/bin/bp3" ticket unclaim 1 --reason "worker-a backing off" | jq -c '{ok, status: .ticket.status, claimed_by: .ticket.claimed_by}'
"$repo/bin/bp3" ticket claim 1 --by worker-b | jq -c '{ok, status: .ticket.status, claimed_by: .ticket.claimed_by}'
"$repo/bin/bp3" ticket "done" 1 --reason "fixed in trial" | jq -c '{ok, status: .ticket.status, resolution_reason: .ticket.resolution_reason}'

# Verify fake-bp3 working tree and refs/heads/bp3/* untouched
[ -z "$(git -C "$fake_bp3" status --porcelain)" ]
[ -z "$(git -C "$fake_bp3" for-each-ref --format='%(refname)' 'refs/heads/bp3/')" ]
echo "fake-bp3 git status: clean, refs/heads/bp3/*: 0"

say "2. Refusal path & 10-way concurrent claim race"
echo "$ bp3 ticket add --to nonexistent --title typo   # strict --to -> E_NOT_FOUND (rc 2)"
rc=0
out=$("$repo/bin/bp3" ticket add --to nonexistent --title "typo") || rc=$?
echo "rc=$rc $(echo "$out" | jq -c '{ok, code: .error.code, registered: .error.facts.registered}')"
[ "$rc" -eq 2 ]
echo "$out" | jq -e '.error.code == "E_NOT_FOUND" and (.error.facts.registered | length) == 2' >/dev/null

t2=$("$repo/bin/bp3" ticket add --from fake-predictor --to fake-bp3 --kind feature --title "concurrent claim target")
tid=$(echo "$t2" | jq -r '.ticket.id')
echo "$ spawning 10 concurrent: bp3 ticket claim $tid --by worker-{1..10}"
mkdir -p "$work/race"
pids=()
for i in $(seq 1 10); do
  (
    r=0
    "$repo/bin/bp3" ticket claim "$tid" --by "worker-$i" >"$work/race/$i.out" 2>"$work/race/$i.err" || r=$?
    printf '%s\n' "$r" >"$work/race/$i.rc"
  ) &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done

ok_n=0 already_n=0 db_err_n=0
for i in $(seq 1 10); do
  r=$(cat "$work/race/$i.rc")
  if [ "$r" -eq 0 ] && jq -e '.ok == true and .ticket.status == "claimed"' "$work/race/$i.out" >/dev/null; then
    ok_n=$((ok_n + 1))
  elif [ "$r" -eq 1 ] && jq -e '.error.code == "E_ALREADY_CLAIMED"' "$work/race/$i.out" >/dev/null; then
    already_n=$((already_n + 1))
  else
    db_err_n=$((db_err_n + 1))
  fi
done
echo "race result: ok=$ok_n E_ALREADY_CLAIMED=$already_n other/E_DB_ERROR=$db_err_n"
[ "$ok_n" -eq 1 ] && [ "$already_n" -eq 9 ] && [ "$db_err_n" -eq 0 ]

echo "$ bp3 ticket done 1 --reason again   # terminal -> E_ILLEGAL_EDGE (rc 1)"
rc=0
out=$("$repo/bin/bp3" ticket "done" 1 --reason "again") || rc=$?
echo "rc=$rc $(echo "$out" | jq -c '{ok, code: .error.code, facts: .error.facts}')"
[ "$rc" -eq 1 ]
echo "$out" | jq -e '.error.code == "E_ILLEGAL_EDGE" and .error.facts.legal_verbs == []' >/dev/null

say "3. Recovery & worktree dedup + historical ticket preservation"
wt="$work/fake-bp3-wt"
git -C "$fake_bp3" worktree add -q -b trial-wt "$wt"
wt_add=$("$repo/bin/bp3" repo add "$wt")
echo "$ bp3 repo add <worktree> -> dedupes to main repo:"
echo "$wt_add" | jq -c '{ok, name: .repo.name, root_path: .repo.root_path}'
echo "$wt_add" | jq -e '.ok == true and .repo.name == "fake-bp3"' >/dev/null

"$repo/bin/bp3" ticket unclaim "$tid" --reason "handoff recovery" >/dev/null
"$repo/bin/bp3" ticket dismiss "$tid" --reason "covered in trial" | jq -c '{ok, id: .ticket.id, status: .ticket.status}'
"$repo/bin/bp3" repo remove fake-bp3 | jq -c '{ok, removed}'
kept=$("$repo/bin/bp3" ticket read 1)
echo "$ bp3 ticket read 1 (after repo remove fake-bp3):"
echo "$kept" | jq -c '{ok, id: .ticket.id, to_repo: .ticket.to_repo, status: .ticket.status}'
echo "$kept" | jq -e '.ok == true and .ticket.status == "done"' >/dev/null

echo "$ bp3 db info --format table"
"$repo/bin/bp3" db info --format table

printf '\ntrial: ALL 3 SCENARIOS PASSED\n'
