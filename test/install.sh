#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export BP3_HARNESS=muse-code BP3_MODEL=test-model

# simulate a release artifact from the built binary
version=$(sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' "$root/src/graph/gitx.ml" | head -1)
os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
mkdir -p "$work/dist"
art="$work/dist/bp3-g-v$version-$os-$arch"
cp "$root/_build/default/src/graph/main.exe" "$art"
(cd "$work/dist" && shasum -a 256 "$(basename "$art")" > "$(basename "$art").sha256")

out=$(PREFIX="$work/prefix" "$root/scripts/install-bp3.sh" "$art")
echo "$out" | grep -q "installed bp3-g $version" || fail "install print: $out"
echo "$out" | grep -q "(was: none)" || fail "install old: $out"
[ -x "$work/prefix/bin/bp3-g" ] || fail "bp3-g not installed"
[ -x "$work/prefix/bin/bp3" ] || fail "bp3 shim not installed"
out=$(PREFIX="$work/prefix" "$root/scripts/install-bp3.sh" "$art")
echo "$out" | grep -q "(was: $version)" || fail "reinstall old->new: $out"

# dogfood: full graph loop in a scratch repo on the installed binary only
mkdir -p "$work/esc3" && cd "$work/esc3"
git init -q -b master; git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
export PATH="$work/prefix/bin:$PATH"
out=$(bp3-g init-repo) || fail "init-repo: $out"
echo "$out" | grep -q '"ok":true' || fail "init-repo verdict: $out"
[ -f plans/default.yaml ] && [ -f plans/direct.yaml ] || fail "plans not scaffolded"
out=$(bp3 g c dogfood) || fail "esc3 graph create: $out"
out=$(bp3 g dogfood c node-1) || fail "esc3 node create: $out"
echo change >> a.txt; git add .; git commit -qm change
out=$(bp3 g dogfood u node-1 handoff --commit HEAD --reason "esc3 dogfood") || fail "esc3 handoff: $out"
echo "$out" | grep -q '"state":"handed_off"' || fail "esc3 handed_off: $out"
out=$(bp3 g r dogfood) || fail "esc3 read: $out"
git -C "$root" rev-parse -q --verify refs/heads/bp3/quest/dogfood >/dev/null 2>&1 && fail "dogfood graph leaked into home repo refs"

# init-repo refuses differing plans
echo "graph_type: mine" > plans/default.yaml
if out=$(bp3-g init-repo 2>&1); then fail "init-repo clobbered differing plan"; fi
echo "$out" | grep -q "E_EXISTS" || fail "init-repo refusal: $out"

echo "install tests: ok"
