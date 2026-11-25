#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal jq expressions using $p.
# Fixture tests for `bp3 repo` + fail-fast auto-registration on bp3 init / init-repo (sqlite-control-plane repo.1).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-repo-tests.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export BP3_DB="${BP3_DB:-$work/bp3.sqlite}"
export BP3_COMPLETIONS_DIR="$work/completions"
export BP3_GLOBAL_HOME="$work/home"
export BP3_Q_BIN="$repo/_build/default/src/quest/main.exe"
[ -x "$BP3_Q_BIN" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

checks=0
assert() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; checks=$((checks + 1)); }
rejects() {
  local want_rc="$1"; shift
  local rc=0
  "$@" >"$work/out" 2>"$work/err" || rc=$?
  [ "$rc" -eq "$want_rc" ] || { printf 'FAIL: expected rc %s, got %s for %s (out=%s err=%s)\n' "$want_rc" "$rc" "$*" "$(cat "$work/out")" "$(cat "$work/err")" >&2; exit 1; }
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

# 1. -h creates no DB file
out=$("$repo/bin/bp3" repo -h)
assert test ! -e "$BP3_DB"
assert grep -q 'bp3 repo add' <<< "$out"

# 2. Explicit add + idempotent re-add + worktree dedup
pred="$work/predictor"
mk_repo "$pred"
wt="$work/predictor-wt"
git -C "$pred" worktree add -q -b feat "$wt"

res=$("$repo/bin/bp3" repo add "$pred" --name predictor)
assert jq -e '.ok == true and .repo.name == "predictor"' <<< "$res" >/dev/null
canon_pred=$(cd "$pred" && pwd -P)
assert jq -e --arg p "$canon_pred" '.repo.root_path == $p' <<< "$res" >/dev/null

res_wt=$("$repo/bin/bp3" repo add "$wt")
assert jq -e --arg p "$canon_pred" '.ok == true and .repo.name == "predictor" and .repo.root_path == $p' <<< "$res_wt" >/dev/null

# 2b. cwd default (no <path>) via bin/bp3 registers caller's cwd repo, NOT bp3
cwd_repo="$work/cwd-default-app"
mk_repo "$cwd_repo"
canon_cwd=$(cd "$cwd_repo" && pwd -P)
res_cwd=$(cd "$cwd_repo" && "$repo/bin/bp3" repo add)
assert jq -e --arg p "$canon_cwd" '.ok == true and .repo.name == "cwd-default-app" and .repo.root_path == $p' <<< "$res_cwd" >/dev/null

# 2c. Aliased repo refreshed cleanly by subsequent `bp3 init` (omitted --name)
aliased="$work/aliased-dir"
mk_repo "$aliased"
"$repo/bin/bp3" repo add "$aliased" --name custom-alias >/dev/null
BP3_TARGET="$aliased" "$repo/bin/bp3" init --harness=claude >/dev/null
alias_list=$("$repo/bin/bp3" repo list)
assert jq -e '([.repos[].name] | index("custom-alias") != null) and ([.repos[].name] | index("aliased-dir") == null)' <<< "$alias_list" >/dev/null

# 3. Duplicate name conflict -> exit 1 E_EXISTS
other="$work/other-app"
mk_repo "$other"
rejects 1 "$repo/bin/bp3" repo add "$other" --name predictor
assert jq -e '.ok == false and .error.code == "E_EXISTS"' "$work/out" >/dev/null

# 4. Auto-registration on `bp3 init` (skills install) and `bp3 init-repo`
esc="$work/esc3"
mk_repo "$esc"
BP3_TARGET="$esc" "$repo/bin/bp3" init --harness=claude >/dev/null
list_json=$("$repo/bin/bp3" repo list)
assert jq -e '.ok == true and ([.repos[].name] | index("esc3") != null)' <<< "$list_json" >/dev/null

app4="$work/app4"
mk_repo "$app4"
(cd "$app4" && BP3_ROOT="$app4" "$BP3_Q_BIN" init-repo >/dev/null)
list_json2=$("$repo/bin/bp3" repo list)
assert jq -e '([.repos[].name] | index("app4") != null)' <<< "$list_json2" >/dev/null

# 5. Fail-fast on name collision during `bp3 init`
dup_dir="$work/nested/esc3"
mk_repo "$dup_dir"
rejects 1 env BP3_TARGET="$dup_dir" "$repo/bin/bp3" init --harness=claude

# 6. Table format + remove + E_NOT_FOUND
tbl=$("$repo/bin/bp3" repo list --format table)
assert grep -q '^name' <<< "$tbl"
assert grep -q 'predictor' <<< "$tbl"
assert grep -q 'esc3' <<< "$tbl"

rm_res=$("$repo/bin/bp3" repo remove esc3)
assert jq -e '.ok == true and .removed == "esc3"' <<< "$rm_res" >/dev/null
rejects 2 "$repo/bin/bp3" repo remove esc3
assert jq -e '.ok == false and .error.code == "E_NOT_FOUND"' "$work/out" >/dev/null

# 7. Non-git dir refused with exit 2 E_NOT_FOUND
mkdir -p "$work/not-git"
rejects 2 "$repo/bin/bp3" repo add "$work/not-git"
assert jq -e '.ok == false and .error.code == "E_NOT_FOUND"' "$work/out" >/dev/null

printf 'repo tests: ok (%s assertions)\n' "$checks"
