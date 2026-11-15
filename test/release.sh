#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/repo/scripts" "$work/repo/src/quest"
cp "$root/scripts/release-check" "$work/repo/scripts/"
printf 'let bp3_version = "0.2.0"\n' > "$work/repo/src/quest/gitx.ml"
cd "$work/repo"
git init -q -b master
git config user.email t@t.t; git config user.name t
git add .; git commit -qm base

# no tag -> refuse
if out=$(./scripts/release-check 2>&1); then fail "release-check accepted missing tag: $out"; fi
echo "$out" | grep -q "tag v0.2.0 missing" || fail "missing-tag message: $out"

# lightweight tag -> refuse (must be annotated)
git tag v0.2.0
if out=$(./scripts/release-check 2>&1); then fail "release-check accepted lightweight tag: $out"; fi
echo "$out" | grep -q "not an annotated tag" || fail "lightweight message: $out"
git tag -d v0.2.0 >/dev/null

# annotated tag at HEAD -> ok, prints version
git tag -a v0.2.0 -m "bp3 v0.2.0"
out=$(./scripts/release-check) || fail "release-check refused good tag"
[ "$out" = "0.2.0" ] || fail "release-check version: $out"

# tag behind HEAD -> refuse
echo x >> x.txt; git add .; git commit -qm next
if out=$(./scripts/release-check 2>&1); then fail "release-check accepted stale tag: $out"; fi
echo "$out" | grep -q "HEAD is" || fail "stale-tag message: $out"

# --version prints exactly the constant
mkdir -p bin plans
cp "$root/bin/bp3" bin/
cp "$root/_build/default/src/quest/main.exe" q-bin
out=$(BP3_Q_BIN="$work/repo/q-bin" ./bin/bp3 q --version)
[ "$out" = "0.2.0" ] || fail "--version: $out"

echo "release tests: ok"

# publish-once with a stubbed gh: first create ok, second refuses
mkdir -p "$work/fakebin"
cat > "$work/fakebin/gh" <<'GH'
#!/usr/bin/env bash
state=${GH_STATE:?}
case "$1 $2" in
  "release view") [ -f "$state" ] ;;
  "release create") [ ! -f "$state" ] || exit 1; touch "$state"; echo created ;;
  *) echo "unexpected gh: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$work/fakebin/gh"
cd "$work/repo"
git tag -d v0.2.0 >/dev/null; git tag -a v0.2.0 -m "bp3 v0.2.0"
cp "$root/scripts/release-publish" scripts/
git remote add origin git@github.com:whyczz/bp3.git
echo asset > asset.bin
out=$(GH_STATE="$work/gh1" PATH="$work/fakebin:$PATH" ./scripts/release-publish asset.bin) || fail "publish first: $out"
echo "$out" | grep -q "published v0.2.0" || fail "publish print: $out"
if out=$(GH_STATE="$work/gh1" PATH="$work/fakebin:$PATH" ./scripts/release-publish asset.bin 2>&1); then fail "second publish accepted"; fi
echo "$out" | grep -q "already published" || fail "publish-once message: $out"
