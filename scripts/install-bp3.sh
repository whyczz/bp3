#!/usr/bin/env bash
# install-bp3.sh: install the release artifact as bp3-q, the bin/bp3
# tool script as bp3, and the skills source under share/bp3 (the
# packaging answer for host mode, dogfood.3: the installed tool
# carries its skills; bin/bp3 renders them into the caller's repo).
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
mkdir -p "$prefix/bin" "$prefix/share/bp3/scripts"
rm -f "$prefix/bin/bp3-q" "$prefix/bin/bp3"
cp "$artifact" "$prefix/bin/bp3-q"
cp "$root/bin/bp3" "$prefix/bin/bp3"
rm -rf "$prefix/share/bp3/skills" "$prefix/share/bp3/completions"
cp -R "$root/skills" "$prefix/share/bp3/skills"
cp "$root/scripts/check-skills" "$prefix/share/bp3/scripts/check-skills"
cp "$root/scripts/agy-statusline" "$prefix/share/bp3/scripts/agy-statusline"
if [ -d "$root/completions" ]; then
  cp -R "$root/completions" "$prefix/share/bp3/completions"
fi
chmod +x "$prefix/bin/bp3-q" "$prefix/bin/bp3" "$prefix/share/bp3/scripts/check-skills" "$prefix/share/bp3/scripts/agy-statusline"
tag_commit=$(git -C "$root" rev-parse -q --verify "v$version^{commit}" 2>/dev/null || true)
head_commit=$(git -C "$root" rev-parse HEAD 2>/dev/null || true)
tag_type=$(git -C "$root" cat-file -t "v$version" 2>/dev/null || true)
if [ -n "$tag_commit" ] && [ "$tag_commit" = "$head_commit" ] && [ "$tag_type" = "tag" ]; then
  src_repo="$root"
  common_dir=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ -n "$common_dir" ] && [ "$(basename "$common_dir")" = ".git" ]; then
    src_repo="$(dirname "$common_dir")"
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg tag "v$version" --arg ver "$version" --arg src "$src_repo" --arg sha "$head_commit" \
      '{tag:$tag, version:$ver, source:$src, commit:$sha}' > "$prefix/share/bp3/RELEASE"
  else
    printf '{"tag":"v%s","version":"%s","source":"%s","commit":"%s"}\n' \
      "$version" "$version" "$src_repo" "$head_commit" > "$prefix/share/bp3/RELEASE"
  fi
else
  rm -f "$prefix/share/bp3/RELEASE"
fi
echo "installed bp3-q $version -> $prefix/bin/bp3-q (was: $old)"
echo "installed bp3 tool + skills -> $prefix/bin/bp3, $prefix/share/bp3/skills"

# Install user-global CORE_SKILLS + non-clobbering hooks in lockstep with bp3-q (global.1).
if [ "${BP3_SKIP_GLOBAL_SKILLS:-}" != "1" ]; then
  BP3_SKIP_COMPLETIONS=1 \
  BP3_SHARE_DIR="$prefix/share/bp3" \
  BP3_SKILLS_DIR="$prefix/share/bp3/skills" \
  BP3_CHECK_SKILLS="$prefix/share/bp3/scripts/check-skills" \
  "$prefix/bin/bp3" skills install --global --harness=all >/dev/null
  echo "installed global bp3 skills + hooks -> ${BP3_GLOBAL_HOME:-$HOME}"
fi

# Wire agy statusLine (stacked below default) when agy config dir exists or BP3_AGY_SETTINGS is set.
agy_settings="${BP3_AGY_SETTINGS:-${BP3_GLOBAL_HOME:-$HOME}/.gemini/antigravity-cli/settings.json}"
agy_dir="$(dirname "$agy_settings")"
if command -v jq >/dev/null 2>&1 && { [ -n "${BP3_AGY_SETTINGS:-}" ] || [ -d "$agy_dir" ]; }; then
  mkdir -p "$agy_dir"
  [ -f "$agy_settings" ] || printf '{}\n' > "$agy_settings"
  tmp_agy="$(mktemp "${agy_dir}/settings.json.XXXXXX")"
  if jq --arg cmd "$prefix/share/bp3/scripts/agy-statusline" \
    '.statusLine = {"type":"command","command":$cmd,"enabled":true,"padding":0,"stack_with_default":true}' \
    "$agy_settings" > "$tmp_agy"; then
    mv "$tmp_agy" "$agy_settings"
    echo "installed agy statusLine -> $agy_settings"
  else
    rm -f "$tmp_agy"
    echo "install: invalid JSON in $agy_settings; left untouched" >&2
    exit 1
  fi
fi
