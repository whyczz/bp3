#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/q-bin"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
SHA=$(git rev-parse HEAD)

export BP3_HARNESS=muse-code BP3_MODEL=test-model
wt() { BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 worktree "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- derive: exact hard-coded path ---
out=$(wt derive demo exp-a R1)
echo "$out" | jq -e '.ok == true and .path == ".bp3/worktrees/demo/exp-a/R1"' >/dev/null || fail "derive exact: $out"

# derive is pure and total over generated slugs, and never escapes the root
for q in demo quest-2 a; do
  for e in exp-a exp-9 z; do
    for r in R1 run-2 20261114t221957z-submit-x-c1; do
      p=$(wt derive "$q" "$e" "$r" | jq -r '.path')
      [ "$p" = ".bp3/worktrees/$q/$e/$r" ] || fail "derive generated: $p"
      case "/$p/" in *"/../"*) fail "derive escapes root: $p" ;; esac
    done
  done
done

# escaping or malformed components are refused, always as E_USAGE
for bad in ".." "." "a/b" 'a\b' ".dot" "a..b" "-dash" ""; do
  if out=$(wt derive demo exp-a "$bad" 2>&1); then fail "derive accepted run id: [$bad]"; fi
  echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "derive escape code [$bad]: $out"
done
if out=$(wt derive demo ../evil R1 2>&1); then fail "derive accepted escaping exp"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "derive exp escape code: $out"

# --- create on a branch; inspect reads it back ---
p1=$(wt derive demo exp-a R1 | jq -r '.path')
out=$(wt create "$p1" --branch bp3/exp/demo/exp-a)
echo "$out" | jq -e '.ok == true and .ref == "bp3/exp/demo/exp-a" and .dirty == false' >/dev/null || fail "create branch: $out"
[ -f "$p1/a.txt" ] || fail "worktree files missing"
[ "$(git -C "$p1" branch --show-current)" = "bp3/exp/demo/exp-a" ] || fail "branch not checked out"
out=$(wt inspect "$p1")
echo "$out" | jq -e '.ok == true and .ref == "bp3/exp/demo/exp-a" and .dirty == false and .changed_count == 0' >/dev/null || fail "inspect clean: $out"

# existing path and already-checked-out branch: clean refusals, no raw git error
if out=$(wt create "$p1" --branch other-branch 2>&1); then fail "create on existing path accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_EXISTS"' >/dev/null || fail "existing path code: $out"
p2=$(wt derive demo exp-a R2 | jq -r '.path')
if out=$(wt create "$p2" --branch bp3/exp/demo/exp-a 2>&1); then fail "create on checked-out branch accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_BRANCH_CHECKED_OUT"' >/dev/null || fail "checked-out code: $out"
case "$out" in *fatal*) fail "raw git error leaked: $out" ;; esac
[ ! -e "$p2" ] || fail "refused create left a worktree"
if out=$(wt create "$p2" --branch master 2>&1); then fail "create on main-worktree branch accepted"; fi
echo "$out" | jq -e '.error.code == "E_BRANCH_CHECKED_OUT"' >/dev/null || fail "main branch code: $out"

# --- create --commit twice: two detached worktrees at the same sha ---
pa=$(wt derive demo exp-a GA | jq -r '.path')
pb=$(wt derive demo exp-a GB | jq -r '.path')
out=$(wt create "$pa" --commit "$SHA")
echo "$out" | jq -e --arg s "$SHA" '.ok == true and .ref == $s' >/dev/null || fail "create commit A: $out"
out=$(wt create "$pb" --commit "$SHA")
echo "$out" | jq -e --arg s "$SHA" '.ok == true and .ref == $s' >/dev/null || fail "create commit B: $out"
[ "$(git -C "$pa" rev-parse HEAD)" = "$SHA" ] || fail "detached A at wrong sha"
[ "$(git -C "$pb" rev-parse HEAD)" = "$SHA" ] || fail "detached B at wrong sha"
out=$(wt inspect "$pa")
echo "$out" | jq -e --arg s "$SHA" '.ref == $s and .dirty == false' >/dev/null || fail "inspect detached: $out"
if out=$(wt create "$(wt derive demo exp-a GC | jq -r '.path')" --commit deadbeefdeadbeef 2>&1); then fail "create on missing commit accepted"; fi
echo "$out" | jq -e '.ok == false' >/dev/null || fail "missing commit not refused: $out"
case "$out" in *fatal*) fail "raw git error leaked: $out" ;; esac

# --- remove after an edit: refused inside the primitive, edit intact ---
echo edited >> "$p1/a.txt"
out=$(wt inspect "$p1")
echo "$out" | jq -e '.dirty == true and .changed_count >= 1' >/dev/null || fail "inspect dirty: $out"
if out=$(wt remove "$p1" 2>&1); then fail "dirty remove accepted without --force"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty remove code: $out"
[ -d "$p1" ] || fail "dirty remove deleted the worktree"
grep -q edited "$p1/a.txt" || fail "dirty remove lost the edit"
out=$(wt remove "$p1" --force)
echo "$out" | jq -e '.ok == true and .removed == true' >/dev/null || fail "force remove: $out"
[ ! -e "$p1" ] || fail "force remove left the worktree"

# --- a dirty worktree is never removed without --force, for any edit kind ---
for kind in modified untracked staged; do
  pk=$(wt derive demo exp-a "edit-$kind" | jq -r '.path')
  wt create "$pk" --commit "$SHA" >/dev/null
  case "$kind" in
    modified) echo x >> "$pk/a.txt" ;;
    untracked) echo x > "$pk/new-$kind.txt" ;;
    staged) echo x > "$pk/new-$kind.txt"; git -C "$pk" add "new-$kind.txt" ;;
  esac
  if out=$(wt remove "$pk" 2>&1); then fail "dirty ($kind) remove accepted"; fi
  echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty ($kind) code: $out"
  [ -d "$pk" ] || fail "dirty ($kind) worktree deleted"
  out=$(wt remove "$pk" --force)
  echo "$out" | jq -e '.ok == true' >/dev/null || fail "dirty ($kind) force remove: $out"
  [ ! -e "$pk" ] || fail "dirty ($kind) force remove left worktree"
done

# --- clean remove without --force; detached pair removed the same way ---
out=$(wt remove "$pa")
echo "$out" | jq -e '.ok == true and .removed == true' >/dev/null || fail "clean remove: $out"
[ ! -e "$pa" ] || fail "clean remove left the worktree"
out=$(wt remove "$pb")
echo "$out" | jq -e '.ok == true' >/dev/null || fail "clean remove B: $out"
if out=$(wt remove "$pb" 2>&1); then fail "remove of missing worktree accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_NOT_FOUND"' >/dev/null || fail "missing remove code: $out"
if out=$(wt inspect "$pb" 2>&1); then fail "inspect of missing worktree accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "missing inspect code: $out"

# --- bookkeeping: prepare is idempotent per Run ID ---
out=$(wt prepare demo exp-a --run RA)
echo "$out" | jq -e '.ok == true and .run_id == "RA" and .path == ".bp3/worktrees/demo/exp-a/RA" and .ref == "bp3/exp/demo/exp-a"' >/dev/null || fail "prepare RA: $out"
pa_path=$(wt derive demo exp-a RA | jq -r '.path')
[ -f "$pa_path/a.txt" ] || fail "prepared worktree files missing"
out=$(wt prepare demo exp-a --run RA)
echo "$out" | jq -e '.ok == true and .existing == true and .path == ".bp3/worktrees/demo/exp-a/RA"' >/dev/null || fail "prepare RA again (existing): $out"
[ "$(git worktree list --porcelain | grep -c '^worktree ')" = "2" ] || fail "prepare twice made extra worktrees"

# check recomputes dirty/stale live by Run ID
out=$(wt check --run RA)
echo "$out" | jq -e '.ok == true and .dirty == false and .ref == "bp3/exp/demo/exp-a" and .stale_s >= 0' >/dev/null || fail "check RA clean: $out"
echo stray >> "$pa_path/a.txt"
out=$(wt check --run RA)
echo "$out" | jq -e '.dirty == true' >/dev/null || fail "check RA dirty: $out"
if out=$(wt check 2>&1); then fail "check without a Run ID accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "check no-run code: $out"

# exit and release refuse a dirty worktree; record stays intact
if out=$(cd "$pa_path" && BP3_Q_BIN="$work/repo/q-bin" "$work/repo/bin/bp3" worktree exit 2>&1); then fail "dirty exit accepted"; fi
echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty exit code: $out"
[ -d "$pa_path" ] || fail "dirty exit deleted the worktree"
if out=$(wt release --run RA 2>&1); then fail "dirty release accepted"; fi
echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty release code: $out"
out=$(wt check --run RA)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "record lost after dirty release: $out"

# force release removes worktree and record (no tombstone)
out=$(wt release --run RA --force)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "force release RA: $out"
[ ! -e "$pa_path" ] || fail "force release left the worktree"
if out=$(wt check --run RA 2>&1); then fail "check after release accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "check released code: $out"
out=$(wt prepare demo exp-a --run RA)
echo "$out" | jq -e '.ok == true and (.existing // false) == false' >/dev/null || fail "re-prepare after release (tombstone?): $out"

# exit from inside a clean worktree releases it and prints the conductor path
out=$(cd "$pa_path" && BP3_Q_BIN="$work/repo/q-bin" "$work/repo/bin/bp3" worktree exit)
conductor=$(cd "$work/repo" && pwd -P)
echo "$out" | jq -e --arg c "$conductor" '.ok == true and .released == true and .conductor_path == $c' >/dev/null || fail "clean exit: $out"
[ ! -e "$pa_path" ] || fail "clean exit left the worktree"
if out=$(wt check --run RA 2>&1); then fail "check after exit accepted"; fi

# --path override is recorded under the same Run ID
override="$work/override-wt"
out=$(wt prepare demo exp-a --run RO --path "$override")
echo "$out" | jq -e --arg p "$override" '.ok == true and .path == $p' >/dev/null || fail "prepare override: $out"
out=$(wt check --run RO)
echo "$out" | jq -e --arg p "$override" '.ok == true and .path == $p and .dirty == false' >/dev/null || fail "check override by Run ID: $out"
out=$(wt release --run RO)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "release override: $out"
[ ! -e "$override" ] || fail "release left the override worktree"

# prepare --commit gives a detached worktree addressable by Run ID
out=$(wt prepare demo exp-a --run RC --commit "$SHA")
echo "$out" | jq -e --arg s "$SHA" '.ok == true and .ref == $s and .detached == true' >/dev/null || fail "prepare commit: $out"
out=$(wt release RC)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "release positional Run ID: $out"

# parallel detached prepares keep every record (one file per Run ID)
for i in 1 2 3 4 5; do
  ( wt prepare demo exp-a --run "P$i" --commit "$SHA" > "$work/par-P$i.json" ) &
done
wait
for i in 1 2 3 4 5; do
  jq -e '.ok == true' "$work/par-P$i.json" >/dev/null || fail "parallel prepare P$i: $(cat "$work/par-P$i.json")"
  [ -f ".bp3/desks/P$i.json" ] || fail "parallel prepare P$i left no desk file"
  out=$(wt check --run "P$i")
  echo "$out" | jq -e '.ok == true and .dirty == false' >/dev/null || fail "parallel check P$i: $out"
done
[ ! -e ".bp3/worktree-registry.json" ] || fail "shared registry file still written"
out=$(wt list)
echo "$out" | jq -e '[.worktrees[] | select(.run_id | startswith("P"))] | length == 5' >/dev/null || fail "parallel list: $out"
for i in 1 2 3 4 5; do
  out=$(wt release --run "P$i")
  echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "parallel release P$i: $out"
  [ ! -e ".bp3/desks/P$i.json" ] || fail "parallel release P$i left a desk file"
done

# list shows every record plus orphans flagged; --quest filters
out=$(wt prepare demo exp-a --run RL)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "prepare RL: $out"
porph=$(wt derive demo exp-a ORPH | jq -r '.path')
wt create "$porph" --commit "$SHA" >/dev/null
out=$(wt list)
echo "$out" | jq -e '[.worktrees[] | select(.run_id == "RL" and (.orphan == false))] | length == 1' >/dev/null || fail "list record RL: $out"
echo "$out" | jq -e '[.worktrees[] | select(.run_id == "ORPH" and .orphan == true)] | length == 1' >/dev/null || fail "list orphan ORPH: $out"
out=$(wt list --quest nope)
echo "$out" | jq -e '.worktrees == []' >/dev/null || fail "list quest filter: $out"
out=$(wt release --run RL)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "release RL: $out"
out=$(wt remove "$porph")
echo "$out" | jq -e '.ok == true' >/dev/null || fail "remove orphan cleanup: $out"
out=$(wt list)
echo "$out" | jq -e '.worktrees == []' >/dev/null || fail "list after all released: $out"
if out=$(wt release --run GONE 2>&1); then fail "release of unknown Run ID accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "release unknown code: $out"

echo "worktree tests: ok"
