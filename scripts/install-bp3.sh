#!/usr/bin/env bash
# install-bp3.sh: install the release artifact as bp3-g, the bin/bp3
# tool script as bp3, and the skills source under share/bp3 (the
# packaging answer for host mode, dogfood.3: the installed tool
# carries its skills; bin/bp3 renders them into the caller's repo).
# Usage: PREFIX=$HOME/.local scripts/install-bp3.sh [artifact]
# Artifact defaults to dist/bp3-g-v<version>-<os>-<arch> in this
# repo; if missing, tries `gh release download v<version>`.
# The install is a copy, never a symlink into _build.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
prefix=${PREFIX:-"$HOME/.local"}
version=$(sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' "$root/src/graph/gitx.ml" | head -1)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
artifact=${1:-"$root/dist/bp3-g-v$version-$os-$arch"}
if [ ! -f "$artifact" ]; then
  if command -v gh >/dev/null 2>&1; then
    mkdir -p "$root/dist"
    gh release download "v$version" --repo "$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's#.*github.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')" \
      --pattern "bp3-g-v$version-$os-$arch*" --dir "$root/dist" 2>/dev/null || true
  fi
fi
[ -f "$artifact" ] || { echo "install: no artifact $artifact; run make release first" >&2; exit 1; }
if [ -f "$artifact.sha256" ]; then
  (cd "$(dirname "$artifact")" && shasum -a 256 -c "$(basename "$artifact").sha256" >/dev/null) \
    || { echo "install: checksum mismatch for $artifact" >&2; exit 1; }
fi
old=none
[ -x "$prefix/bin/bp3-g" ] && old=$("$prefix/bin/bp3-g" --version 2>/dev/null || echo none)
mkdir -p "$prefix/bin" "$prefix/share/bp3/scripts"
rm -f "$prefix/bin/bp3-g" "$prefix/bin/bp3"
cp "$artifact" "$prefix/bin/bp3-g"
cp "$root/bin/bp3" "$prefix/bin/bp3"
rm -rf "$prefix/share/bp3/skills" "$prefix/share/bp3/completions"
cp -R "$root/skills" "$prefix/share/bp3/skills"
cp "$root/scripts/check-skills" "$prefix/share/bp3/scripts/check-skills"
if [ -d "$root/completions" ]; then
  cp -R "$root/completions" "$prefix/share/bp3/completions"
fi
chmod +x "$prefix/bin/bp3-g" "$prefix/bin/bp3" "$prefix/share/bp3/scripts/check-skills"
echo "installed bp3-g $version -> $prefix/bin/bp3-g (was: $old)"
echo "installed bp3 tool + skills -> $prefix/bin/bp3, $prefix/share/bp3/skills"
