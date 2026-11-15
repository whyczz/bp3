#!/usr/bin/env bash
# install-bp3.sh: install the release artifact as bp3-q (+ bp3 shim).
# Usage: PREFIX=$HOME/.local scripts/install-bp3.sh [artifact]
# Artifact defaults to dist/bp3-q-v<version>-<os>-<arch> in this
# repo; if missing, tries `gh release download v<version>`.
# The install is a copy, never a symlink into _build.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
prefix=${PREFIX:-"$HOME/.local"}
version=$(sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' "$root/src/quest/gitx.ml" | head -1)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
artifact=${1:-"$root/dist/bp3-q-v$version-$os-$arch"}
if [ ! -f "$artifact" ]; then
  if command -v gh >/dev/null 2>&1; then
    mkdir -p "$root/dist"
    gh release download "v$version" --repo "$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's#.*github.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')" \
      --pattern "bp3-q-v$version-$os-$arch*" --dir "$root/dist" 2>/dev/null || true
  fi
fi
[ -f "$artifact" ] || { echo "install: no artifact $artifact; run make release first" >&2; exit 1; }
if [ -f "$artifact.sha256" ]; then
  (cd "$(dirname "$artifact")" && shasum -a 256 -c "$(basename "$artifact").sha256" >/dev/null) \
    || { echo "install: checksum mismatch for $artifact" >&2; exit 1; }
fi
old=none
[ -x "$prefix/bin/bp3-q" ] && old=$("$prefix/bin/bp3-q" --version 2>/dev/null || echo none)
mkdir -p "$prefix/bin"
rm -f "$prefix/bin/bp3-q" "$prefix/bin/bp3"
cp "$artifact" "$prefix/bin/bp3-q"
cp "$root/scripts/bp3-shim" "$prefix/bin/bp3"
chmod +x "$prefix/bin/bp3-q" "$prefix/bin/bp3"
echo "installed bp3-q $version -> $prefix/bin/bp3-q (was: $old)"
