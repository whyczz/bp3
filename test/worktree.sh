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

echo "worktree tests: ok"
