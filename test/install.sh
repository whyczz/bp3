#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export BP3_HARNESS=muse-code BP3_MODEL=test-model

# simulate a release artifact from the built binary
version=$(sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' "$root/src/quest/gitx.ml" | head -1)
os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
mkdir -p "$work/dist"
art="$work/dist/bp3-q-v$version-$os-$arch"
cp "$root/_build/default/src/quest/main.exe" "$art"
(cd "$work/dist" && shasum -a 256 "$(basename "$art")" > "$(basename "$art").sha256")

mkdir -p "$work/agy"
printf '{"keepMe":true}\n' > "$work/agy/settings.json"
out=$(PREFIX="$work/prefix" BP3_AGY_SETTINGS="$work/agy/settings.json" "$root/scripts/install-bp3.sh" "$art")
echo "$out" | grep -q "installed bp3-q $version" || fail "install print: $out"
echo "$out" | grep -q "(was: none)" || fail "install old: $out"
[ -x "$work/prefix/bin/bp3-q" ] || fail "bp3-q not installed"
[ -x "$work/prefix/bin/bp3" ] || fail "bp3 shim not installed"
[ -x "$work/prefix/share/bp3/scripts/agy-statusline" ] || fail "agy-statusline not installed"
jq -e --arg cmd "$work/prefix/share/bp3/scripts/agy-statusline" \
  '.keepMe == true and .statusLine.type == "command" and .statusLine.command == $cmd and .statusLine.enabled == true and .statusLine.stack_with_default == true' \
  "$work/agy/settings.json" >/dev/null || fail "agy statusLine settings: $(cat "$work/agy/settings.json")"
out=$(PREFIX="$work/prefix" BP3_AGY_SETTINGS="$work/agy/settings.json" "$root/scripts/install-bp3.sh" "$art")
echo "$out" | grep -q "(was: $version)" || fail "reinstall old->new: $out"

# dogfood: full quest loop in a scratch repo on the installed binary only
mkdir -p "$work/esc3" && cd "$work/esc3"
git init -q -b master; git config user.email t@t.t; git config user.name t
echo base > a.txt; git add .; git commit -qm base
export PATH="$work/prefix/bin:$PATH"
out=$(bp3-q init-repo) || fail "init-repo: $out"
echo "$out" | jq -e '.ok == true and .manifest == "backpack.toml" and .manifest_created == true' >/dev/null || fail "init-repo verdict: $out"
[ -f backpack.toml ] || fail "backpack.toml not scaffolded"
grep -q '^version = 1$' backpack.toml || fail "backpack.toml version: $(cat backpack.toml)"
grep -q '^repo = "esc3"$' backpack.toml || fail "backpack.toml repo: $(cat backpack.toml)"
[ -f plans/default.yaml ] && [ -f plans/direct.yaml ] || fail "plans not scaffolded"
# manifest.1: second init-repo preserves user edits to backpack.toml byte-for-byte
printf 'version = 1\nrepo = "esc3"\n\n[warden]\ngrade_wall_s = 600\n' > backpack.toml
cp backpack.toml "$work/backpack.want"
out2=$(bp3-q init-repo) || fail "init-repo 2nd run: $out2"
echo "$out2" | jq -e '.ok == true and .manifest_created == false' >/dev/null || fail "init-repo 2nd verdict: $out2"
cmp -s backpack.toml "$work/backpack.want" || fail "init-repo modified backpack.toml"
# malformed existing backpack.toml refuses E_INVALID_CONFIG before touching plans/
printf 'version = 99\n' > backpack.toml
if bad_out=$(bp3-q init-repo 2>&1); then fail "init-repo accepted malformed backpack.toml"; fi
echo "$bad_out" | jq -e '.ok == false and .error.code == "E_INVALID_CONFIG"' >/dev/null || fail "bad manifest code: $bad_out"
cp "$work/backpack.want" backpack.toml
# init.1: a new host repo gets this repo's plans, byte for byte (max_cycles 10)
for p in default direct; do
  cmp -s "plans/$p.yaml" "$root/plans/$p.yaml" || fail "scaffolded plans/$p.yaml differs from bp3's: $(cat "plans/$p.yaml")"
done
out=$(bp3 q c dogfood) || fail "esc3 quest create: $out"
out=$(bp3 q dogfood c node-1) || fail "esc3 node create: $out"
echo change >> a.txt; git add .; git commit -qm change
out=$(bp3 q dogfood u node-1 handoff --commit HEAD --reason "esc3 dogfood") || fail "esc3 handoff: $out"
echo "$out" | grep -q '"state":"handed_off"' || fail "esc3 handed_off: $out"
out=$(bp3 q r dogfood) || fail "esc3 read: $out"
git -C "$root" rev-parse -q --verify refs/heads/bp3/goal/dogfood >/dev/null 2>&1 && fail "dogfood quest leaked into home repo refs"

# init-repo refuses differing plans
echo "quest_type: mine" > plans/default.yaml
if out=$(bp3-q init-repo 2>&1); then fail "init-repo clobbered differing plan"; fi
echo "$out" | grep -q "E_EXISTS" || fail "init-repo refusal: $out"

echo "install tests: ok"
