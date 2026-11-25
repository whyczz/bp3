#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/bin"
cp "$root/bin/bp3" "$work/repo/bin/"
cp "$root/_build/default/src/quest/main.exe" "$work/repo/g-bin"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
SHA=$(git rev-parse HEAD)

export BP3_HARNESS=muse-code BP3_MODEL=test-model
export BP3_DESKS_DIR="$work/desks"
# Since mvp.6 this door is the documented alias of bp3 harness desk;
# this file is its full regression suite (desk parity checked below).
wt() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 worktree "$@"; }
hdesk() { BP3_Q_BIN="$work/repo/g-bin" ./bin/bp3 harness desk "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- derive: exact central path under $BP3_DESKS_DIR/<repo>-<hash8>/runs/... ---
out=$(wt derive demo node-a R1)
p0=$(echo "$out" | jq -r '.path')
echo "$out" | jq -e '.ok == true' >/dev/null || fail "derive ok: $out"
case "$p0" in
  "$work/desks/repo-"*/runs/demo/node-a/R1) ;;
  *) fail "derive central path shape: $out" ;;
esac
repo_dir="${p0%/runs/demo/node-a/R1}"
repo_key="${repo_dir##*/}"
[[ "$repo_key" =~ ^repo-[0-9a-f]{8}$ ]] || fail "derive repo_key shape: $repo_key"
[ ! -e "$work/repo/.bp3" ] || fail "derive created repo .bp3/"

# derive is pure and total over generated slugs, and never escapes the root
for q in demo quest-2 a; do
  for e in node-a node-9 z; do
    for r in R1 run-2 20261114t221957z-handoff-x-c1; do
      p=$(wt derive "$q" "$e" "$r" | jq -r '.path')
      [ "$p" = "$repo_dir/runs/$q/$e/$r" ] || fail "derive generated: $p"
      case "/$p/" in *"/../"*) fail "derive escapes root: $p" ;; esac
    done
  done
done

# escaping or malformed components are refused, always as E_USAGE
for bad in ".." "." "a/b" 'a\b' ".dot" "a..b" "-dash" ""; do
  if out=$(wt derive demo node-a "$bad" 2>&1); then fail "derive accepted run id: [$bad]"; fi
  echo "$out" | jq -e '.ok == false and .error.code == "E_USAGE"' >/dev/null || fail "derive escape code [$bad]: $out"
done
if out=$(wt derive demo ../evil R1 2>&1); then fail "derive accepted escaping node"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "derive node escape code: $out"

# --- create on a branch; inspect reads it back ---
p1=$(wt derive demo node-a R1 | jq -r '.path')
out=$(wt create "$p1" --branch bp3/node/demo/node-a)
echo "$out" | jq -e '.ok == true and .ref == "bp3/node/demo/node-a" and .dirty == false' >/dev/null || fail "create branch: $out"
[ -f "$p1/a.txt" ] || fail "worktree files missing"
[ "$(git -C "$p1" branch --show-current)" = "bp3/node/demo/node-a" ] || fail "branch not checked out"
out=$(wt inspect "$p1")
echo "$out" | jq -e '.ok == true and .ref == "bp3/node/demo/node-a" and .dirty == false and .changed_count == 0' >/dev/null || fail "inspect clean: $out"

# existing path and already-checked-out branch: clean refusals, no raw git error
if out=$(wt create "$p1" --branch other-branch 2>&1); then fail "create on existing path accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_EXISTS"' >/dev/null || fail "existing path code: $out"
p2=$(wt derive demo node-a R2 | jq -r '.path')
if out=$(wt create "$p2" --branch bp3/node/demo/node-a 2>&1); then fail "create on checked-out branch accepted"; fi
echo "$out" | jq -e '.ok == false and .error.code == "E_BRANCH_CHECKED_OUT"' >/dev/null || fail "checked-out code: $out"
case "$out" in *fatal*) fail "raw git error leaked: $out" ;; esac
[ ! -e "$p2" ] || fail "refused create left a worktree"
if out=$(wt create "$p2" --branch master 2>&1); then fail "create on main-worktree branch accepted"; fi
echo "$out" | jq -e '.error.code == "E_BRANCH_CHECKED_OUT"' >/dev/null || fail "main branch code: $out"

# --- create --commit twice: two detached worktrees at the same sha ---
pa=$(wt derive demo node-a GA | jq -r '.path')
pb=$(wt derive demo node-a GB | jq -r '.path')
out=$(wt create "$pa" --commit "$SHA")
echo "$out" | jq -e --arg s "$SHA" '.ok == true and .ref == $s' >/dev/null || fail "create commit A: $out"
out=$(wt create "$pb" --commit "$SHA")
echo "$out" | jq -e --arg s "$SHA" '.ok == true and .ref == $s' >/dev/null || fail "create commit B: $out"
[ "$(git -C "$pa" rev-parse HEAD)" = "$SHA" ] || fail "detached A at wrong sha"
[ "$(git -C "$pb" rev-parse HEAD)" = "$SHA" ] || fail "detached B at wrong sha"
out=$(wt inspect "$pa")
echo "$out" | jq -e --arg s "$SHA" '.ref == $s and .dirty == false' >/dev/null || fail "inspect detached: $out"
if out=$(wt create "$(wt derive demo node-a GC | jq -r '.path')" --commit deadbeefdeadbeef 2>&1); then fail "create on missing commit accepted"; fi
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
  pk=$(wt derive demo node-a "edit-$kind" | jq -r '.path')
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
out=$(wt prepare demo node-a --run RA)
pa_path=$(wt derive demo node-a RA | jq -r '.path')
echo "$out" | jq -e --arg p "$pa_path" '.ok == true and .run_id == "RA" and .path == $p and .ref == "bp3/node/demo/node-a"' >/dev/null || fail "prepare RA: $out"
[ -f "$pa_path/a.txt" ] || fail "prepared worktree files missing"
[ ! -e "$work/repo/.bp3" ] || fail "prepare RA created repo .bp3/"
out=$(wt prepare demo node-a --run RA)
echo "$out" | jq -e --arg p "$pa_path" '.ok == true and .existing == true and .path == $p' >/dev/null || fail "prepare RA again (existing): $out"
[ "$(git worktree list --porcelain | grep -c '^worktree ')" = "2" ] || fail "prepare twice made extra worktrees"

# check recomputes dirty/stale live by Run ID
out=$(wt check --run RA)
echo "$out" | jq -e '.ok == true and .dirty == false and .ref == "bp3/node/demo/node-a" and .stale_s >= 0' >/dev/null || fail "check RA clean: $out"
echo stray >> "$pa_path/a.txt"
out=$(wt check --run RA)
echo "$out" | jq -e '.dirty == true' >/dev/null || fail "check RA dirty: $out"
if out=$(wt check 2>&1); then fail "check without a Run ID accepted"; fi
echo "$out" | jq -e '.error.code == "E_USAGE"' >/dev/null || fail "check no-run code: $out"

# exit and release refuse a dirty worktree; record stays intact
if out=$(cd "$pa_path" && BP3_Q_BIN="$work/repo/g-bin" "$work/repo/bin/bp3" worktree exit 2>&1); then fail "dirty exit accepted"; fi
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
out=$(wt prepare demo node-a --run RA)
echo "$out" | jq -e '.ok == true and (.existing // false) == false' >/dev/null || fail "re-prepare after release (tombstone?): $out"

# exit from inside a clean worktree (without pinned BP3_ROOT) releases it and prints conductor_path = main_root
out=$(cd "$pa_path" && env -u BP3_ROOT "$work/repo/g-bin" worktree exit)
conductor=$(cd "$work/repo" && pwd -P)
echo "$out" | jq -e --arg c "$conductor" '.ok == true and .released == true and .conductor_path == $c' >/dev/null || fail "clean exit: $out"
[ ! -e "$pa_path" ] || fail "clean exit left the worktree"
if out=$(wt check --run RA 2>&1); then fail "check after exit accepted"; fi

# --path override is recorded under the same Run ID
override="$work/override-wt"
out=$(wt prepare demo node-a --run RO --path "$override")
echo "$out" | jq -e --arg p "$override" '.ok == true and .path == $p' >/dev/null || fail "prepare override: $out"
out=$(wt check --run RO)
echo "$out" | jq -e --arg p "$override" '.ok == true and .path == $p and .dirty == false' >/dev/null || fail "check override by Run ID: $out"
out=$(wt release --run RO)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "release override: $out"
[ ! -e "$override" ] || fail "release left the override worktree"

# prepare --commit gives a detached worktree addressable by Run ID
out=$(wt prepare demo node-a --run RC --commit "$SHA")
echo "$out" | jq -e --arg s "$SHA" '.ok == true and .ref == $s and .detached == true' >/dev/null || fail "prepare commit: $out"
out=$(wt release RC)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "release positional Run ID: $out"

# parallel detached prepares keep every record in central .meta/ (one file per Run ID)
for i in 1 2 3 4 5; do
  ( wt prepare demo node-a --run "P$i" --commit "$SHA" > "$work/par-P$i.json" ) &
done
wait
for i in 1 2 3 4 5; do
  jq -e '.ok == true' "$work/par-P$i.json" >/dev/null || fail "parallel prepare P$i: $(cat "$work/par-P$i.json")"
  [ -f "$repo_dir/.meta/P$i.json" ] || fail "parallel prepare P$i left no central .meta file"
  out=$(wt check --run "P$i")
  echo "$out" | jq -e '.ok == true and .dirty == false' >/dev/null || fail "parallel check P$i: $out"
done
[ ! -e "$work/repo/.bp3" ] || fail "parallel prepares created repo .bp3/"
out=$(wt list)
echo "$out" | jq -e '[.worktrees[] | select(.run_id | startswith("P"))] | length == 5' >/dev/null || fail "parallel list: $out"
for i in 1 2 3 4 5; do
  out=$(wt release --run "P$i")
  echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "parallel release P$i: $out"
  [ ! -e "$repo_dir/.meta/P$i.json" ] || fail "parallel release P$i left a central .meta file"
done

# list shows every record plus run & quest orphans flagged; --quest filters
out=$(wt prepare demo node-a --run RL)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "prepare RL: $out"
porph=$(wt derive demo node-a ORPH | jq -r '.path')
wt create "$porph" --commit "$SHA" >/dev/null
qorph="$repo_dir/quests/orphq"
wt create "$qorph" --commit "$SHA" >/dev/null
out=$(wt list)
echo "$out" | jq -e '[.worktrees[] | select(.run_id == "RL" and (.orphan == false))] | length == 1' >/dev/null || fail "list record RL: $out"
echo "$out" | jq -e '[.worktrees[] | select(.run_id == "ORPH" and .orphan == true)] | length == 1' >/dev/null || fail "list orphan ORPH: $out"
echo "$out" | jq -e '[.worktrees[] | select(.run_id == "quest-orphq" and .quest == "orphq" and .node == "(quest)" and .orphan == true)] | length == 1' >/dev/null || fail "list quest orphan: $out"
out=$(wt list --quest nope)
echo "$out" | jq -e '.worktrees == []' >/dev/null || fail "list quest filter: $out"
out=$(wt release --run RL)
echo "$out" | jq -e '.ok == true' >/dev/null || fail "release RL: $out"
out=$(wt remove "$porph")
echo "$out" | jq -e '.ok == true' >/dev/null || fail "remove run orphan cleanup: $out"
out=$(wt remove "$qorph")
echo "$out" | jq -e '.ok == true' >/dev/null || fail "remove quest orphan cleanup: $out"
out=$(wt list)
echo "$out" | jq -e '.worktrees == []' >/dev/null || fail "list after all released: $out"
if out=$(wt release --run GONE 2>&1); then fail "release of unknown Run ID accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_FOUND"' >/dev/null || fail "release unknown code: $out"

# --- quest-level desk + sibling grade desk non-nesting + worktree-context list + harness desk parity ---
out=$(hdesk prepare --quest demoq)
qpath="$repo_dir/quests/demoq"
echo "$out" | jq -e --arg p "$qpath" '.ok == true and .quest == "demoq" and .node == "(quest)" and .path == $p and .ref == "quest/demoq"' >/dev/null || fail "quest prepare: $out"
[ -d "$qpath" ] || fail "quest desk missing on disk"
out=$(hdesk prepare --quest demoq)
echo "$out" | jq -e '.ok == true and .existing == true' >/dev/null || fail "quest prepare idempotent: $out"
gout=$(hdesk prepare demoq node-a --run grade-node-a-c1-a1 --commit "$SHA")
gpath="$repo_dir/runs/demoq/node-a/grade-node-a-c1-a1"
echo "$gout" | jq -e --arg p "$gpath" '.ok == true and .path == $p and .detached == true' >/dev/null || fail "grade prepare: $gout"
case "$gpath" in "$qpath"/*) fail "grade desk nested inside quest desk: $gpath" ;; esac
[ -z "$(git -C "$qpath" status --short)" ] || fail "quest desk dirty while grade desk open"
# calling list from inside quest desk (without BP3_ROOT) resolves the exact same central bucket
wt_list=$(cd "$qpath" && env -u BP3_ROOT "$work/repo/g-bin" worktree list)
main_list=$(hdesk list)
[ "$(echo "$wt_list" | jq -c '[.worktrees[].run_id]')" = "$(echo "$main_list" | jq -c '[.worktrees[].run_id]')" ] \
  || fail "desk list inside worktree differs: $wt_list vs $main_list"
echo "$main_list" | jq -e '[.worktrees[].run_id] | index("quest-demoq") != null and index("grade-node-a-c1-a1") != null' >/dev/null || fail "both desks in list: $main_list"
out=$(hdesk release --run grade-node-a-c1-a1)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "grade release: $out"
echo stray > "$qpath/stray.txt"
if out=$(hdesk release --quest demoq 2>&1); then fail "dirty quest release accepted"; fi
rm "$qpath/stray.txt"
out=$(hdesk release --quest demoq)
echo "$out" | jq -e '.ok == true and .released == true' >/dev/null || fail "quest release: $out"
[ ! -d "$qpath" ] || fail "quest desk not removed"
[ ! -e "$work/repo/.bp3" ] || fail "central desks created repo .bp3/"

# --- legacy .bp3/desks/ read+release fallback (zero-cliff upgrade, never written to) ---
mkdir -p "$work/repo/.bp3/desks" "$work/repo/.bp3/worktrees"
git worktree add -q --detach "$work/repo/.bp3/worktrees/legq" "$SHA"
printf '{"run_id":"LEGACY1","quest":"legq","node":"(quest)","path":".bp3/worktrees/legq","ref":"%s","detached":true,"created_ts":1700000000}\n' "$SHA" \
  > "$work/repo/.bp3/desks/LEGACY1.json"
out=$(wt list)
echo "$out" | jq -e '[.worktrees[] | select(.run_id == "LEGACY1" and .missing == false and .orphan == false)] | length == 1' >/dev/null || fail "legacy list: $out"
# verify legacy record is also visible from inside a new central worktree (without BP3_ROOT)
cpath=$(wt prepare demo node-a --run NEW1 --commit "$SHA" | jq -r '.path')
[ ! -e "$work/repo/.bp3/desks/NEW1.json" ] || fail "new prepare wrote to legacy .bp3/desks/"
wt_leg=$(cd "$cpath" && env -u BP3_ROOT "$work/repo/g-bin" worktree list)
echo "$wt_leg" | jq -e '[.worktrees[] | select(.run_id == "LEGACY1")] | length == 1' >/dev/null || fail "legacy list from central worktree: $wt_leg"
out=$(cd "$cpath" && env -u BP3_ROOT "$work/repo/g-bin" worktree release --run LEGACY1)
echo "$out" | jq -e '.ok == true and .released == true and .removed == true' >/dev/null || fail "legacy release from worktree: $out"
[ ! -e "$work/repo/.bp3/desks/LEGACY1.json" ] || fail "legacy release left .bp3/desks/LEGACY1.json"
[ ! -e "$work/repo/.bp3/worktrees/legq" ] || fail "legacy release left .bp3/worktrees/legq"
wt release --run NEW1 >/dev/null

# --- draft desks: prepare|release|land --draft + target_dirty + CAS rebase + conflict abort ---
out=$(hdesk list)
echo "$out" | jq -e '.ok == true and .target_branch == "master" and .target_dirty == false' >/dev/null || fail "desk list clean target: $out"
echo dirty >> "$work/repo/a.txt"
out=$(hdesk list)
echo "$out" | jq -e '.target_branch == "master" and .target_dirty == true' >/dev/null || fail "desk list dirty target: $out"
git -C "$work/repo" checkout -- a.txt

# prepare --draft is idempotent, sibling under drafts/<slug>, zero repo .bp3/
out=$(hdesk prepare --draft icebox-demo)
dpath="$repo_dir/drafts/icebox-demo"
echo "$out" | jq -e --arg p "$dpath" '.ok == true and .run_id == "draft-icebox-demo" and .quest == "icebox-demo" and .node == "(draft)" and .path == $p and .ref == "draft/icebox-demo" and .detached == false' >/dev/null || fail "draft prepare: $out"
[ -d "$dpath" ] || fail "draft desk missing on disk"
out=$(hdesk prepare --draft icebox-demo)
echo "$out" | jq -e '.ok == true and .existing == true' >/dev/null || fail "draft prepare idempotent: $out"

# land --draft with 0 commits ahead -> E_NOT_READY
if out=$(hdesk land --draft icebox-demo 2>&1); then fail "land 0-ahead accepted"; fi
echo "$out" | jq -e '.error.code == "E_NOT_READY" and .error.facts.commits_ahead == 0' >/dev/null || fail "land 0-ahead code: $out"

# dirty draft -> release and land both refuse E_DIRTY_TREE
echo wip > "$dpath/draft1.md"
if out=$(hdesk release --draft icebox-demo 2>&1); then fail "dirty draft release accepted"; fi
echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty draft release code: $out"
if out=$(hdesk land --draft icebox-demo 2>&1); then fail "dirty draft land accepted"; fi
echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty draft land code: $out"

# release --draft --force from inside the draft desk itself succeeds (no E_MAIN_WORKTREE) and keeps branch
out=$(cd "$dpath" && env -u BP3_ROOT "$work/repo/g-bin" worktree release --draft icebox-demo --force)
echo "$out" | jq -e '.ok == true and .released == true and .removed == true' >/dev/null || fail "in-desk force draft release: $out"
[ ! -d "$dpath" ] || fail "force draft release left desk"
git -C "$work/repo" show-ref --verify --quiet refs/heads/draft/icebox-demo || fail "release deleted draft branch"

# re-prepare reuses draft/icebox-demo cleanly; commit draft1.md; happy fast-forward land (unmoved target)
out=$(hdesk prepare --draft icebox-demo)
echo "$out" | jq -e '.ok == true and (.existing // false) == false' >/dev/null || fail "re-prepare draft: $out"
echo "draft one" > "$dpath/draft1.md"
git -C "$dpath" add draft1.md && git -C "$dpath" commit -qm "docs: draft1"
# dirty target checkout blocks land --draft with E_DIRTY_TREE
echo dirty >> "$work/repo/a.txt"
if out=$(hdesk land --draft icebox-demo 2>&1); then fail "land onto dirty master accepted"; fi
echo "$out" | jq -e '.error.code == "E_DIRTY_TREE"' >/dev/null || fail "dirty target land code: $out"
git -C "$work/repo" checkout -- a.txt
out=$(hdesk land --draft icebox-demo)
echo "$out" | jq -e --arg c "$conductor" '.ok == true and .draft == "icebox-demo" and .branch == "draft/icebox-demo" and .target == "master" and .rebased == false and .attempts == 1 and .landed == true and .released == true and .branch_deleted == true and .conductor_path == $c' >/dev/null || fail "ff draft land: $out"
[ ! -d "$dpath" ] || fail "land left draft desk"
[ ! -e "$repo_dir/.meta/draft-icebox-demo.json" ] || fail "land left draft meta"
if git -C "$work/repo" show-ref --verify --quiet refs/heads/draft/icebox-demo; then fail "land left draft branch"; fi
[ -f "$work/repo/draft1.md" ] || fail "master checkout not synced after ff draft land"
[ -z "$(git -C "$work/repo" status --short)" ] || fail "master dirty after ff draft land"

# rebased land --draft invoked from INSIDE draft desk while an active quest desk is open (zero starvation!)
hdesk prepare --quest active-q >/dev/null
qactive="$repo_dir/quests/active-q"
echo qwork > "$qactive/qwork.txt"
git -C "$qactive" add qwork.txt && git -C "$qactive" commit -qm "feat: active quest work"
out=$(hdesk prepare --draft quest-two)
dpath2="$repo_dir/drafts/quest-two"
echo "draft two" > "$dpath2/draft2.md"
git -C "$dpath2" add draft2.md && git -C "$dpath2" commit -qm "docs: draft2"
# Advance master with a disjoint commit
echo "other master doc" > "$work/repo/other.md"
git -C "$work/repo" add other.md && git -C "$work/repo" commit -qm "docs: other"
out=$(cd "$dpath2" && env -u BP3_ROOT "$work/repo/g-bin" worktree land --draft quest-two)
echo "$out" | jq -e --arg c "$conductor" '.ok == true and .draft == "quest-two" and .rebased == true and .attempts == 1 and .landed == true and .released == true and .branch_deleted == true and .conductor_path == $c' >/dev/null || fail "rebased in-desk draft land: $out"
[ ! -d "$dpath2" ] || fail "rebased land left draft desk"
[ -f "$work/repo/draft2.md" ] && [ -f "$work/repo/other.md" ] || fail "master missing files after rebased draft land"
[ -z "$(git -C "$work/repo" status --short)" ] || fail "master dirty after rebased draft land"
hdesk release --quest active-q >/dev/null

# rebase conflict -> clean rebase --abort -> E_MERGE_CONFLICT, draft desk stays clean & unconflicted
out=$(hdesk prepare --draft conflict-d)
dpathc="$repo_dir/drafts/conflict-d"
echo "draft-side" > "$dpathc/a.txt"
git -C "$dpathc" add a.txt && git -C "$dpathc" commit -qm "docs: draft conflict"
echo "master-side" > "$work/repo/a.txt"
git -C "$work/repo" add a.txt && git -C "$work/repo" commit -qm "docs: master conflict"
before_m=$(git -C "$work/repo" rev-parse master)
if out=$(hdesk land --draft conflict-d 2>&1); then fail "conflicting draft land accepted"; fi
echo "$out" | jq -e '.error.code == "E_MERGE_CONFLICT"' >/dev/null || fail "conflict land code: $out"
[ "$(git -C "$work/repo" rev-parse master)" = "$before_m" ] || fail "conflict land moved master"
[ -z "$(git -C "$dpathc" status --short)" ] || fail "conflict land left draft desk dirty / mid-rebase"
[ ! -d "$(git -C "$dpathc" rev-parse --git-path rebase-merge)" ] || fail "conflict land left rebase-merge dir"
hdesk release --draft conflict-d >/dev/null

# CAS contention: locked refs/heads/master.lock -> E_STALE_WORLD after 3 attempts
out=$(hdesk prepare --draft race-d)
dpathr="$repo_dir/drafts/race-d"
echo "race" > "$dpathr/race.md"
git -C "$dpathr" add race.md && git -C "$dpathr" commit -qm "docs: race"
before_m=$(git -C "$work/repo" rev-parse master)
mkdir -p "$work/repo/.git/refs/heads"
: > "$work/repo/.git/refs/heads/master.lock"
if out=$(hdesk land --draft race-d 2>&1); then
  rm -f "$work/repo/.git/refs/heads/master.lock"
  fail "locked CAS draft land accepted"
fi
rm -f "$work/repo/.git/refs/heads/master.lock"
echo "$out" | jq -e '.error.code == "E_STALE_WORLD" and .error.facts.attempts == 3' >/dev/null || fail "CAS lock code: $out"
[ "$(git -C "$work/repo" rev-parse master)" = "$before_m" ] || fail "locked CAS moved master"
hdesk release --draft race-d >/dev/null

# --target <non-HEAD branch>: lands onto target, leaves master unmoved, CAS-deletes draft branch
git -C "$work/repo" branch other-target
before_m=$(git -C "$work/repo" rev-parse master)
out=$(hdesk prepare --draft nonhead-d)
dpath_nh="$repo_dir/drafts/nonhead-d"
echo "nonhead" > "$dpath_nh/nonhead.md"
git -C "$dpath_nh" add nonhead.md && git -C "$dpath_nh" commit -qm "docs: nonhead"
out=$(hdesk land --draft nonhead-d --target other-target)
echo "$out" | jq -e '.ok == true and .target == "other-target" and .landed == true and .released == true and .branch_deleted == true' >/dev/null || fail "non-HEAD target land: $out"
[ "$(git -C "$work/repo" rev-parse master)" = "$before_m" ] || fail "non-HEAD land moved master"
[ "$(git -C "$work/repo" rev-parse other-target)" = "$(echo "$out" | jq -r '.commit')" ] || fail "non-HEAD target ref mismatch"
if git -C "$work/repo" show-ref --verify --quiet refs/heads/draft/nonhead-d; then fail "non-HEAD land left draft branch"; fi
git -C "$work/repo" branch -D other-target >/dev/null

# .gitignore covers review scratch patterns in repo root
for pat in '*.red-ink.md' '*.2b-reviewed.md' '*.2b-reviewed.md.snapshot'; do
  grep -qxF "$pat" "$root/.gitignore" || fail ".gitignore missing $pat"
done

echo "worktree tests: ok"
