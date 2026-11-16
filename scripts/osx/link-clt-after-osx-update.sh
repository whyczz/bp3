#!/usr/bin/env bash
# After a macOS update, xcode-select can end up pointing at a
# toolchain whose SDK the linker cannot parse (fresh links fail
# with "tapi error: malformed file ... unknown architecture
# arm64e.x1"). Repointing at the CommandLineTools install fixed
# it on 2026-11-16 (dune/OCaml link of src/quest/main.exe).
# Run manually; it needs sudo.
set -euo pipefail

sudo xcode-select -s /Library/Developer/CommandLineTools
echo "developer dir: $(xcode-select -p)"
clang --version | head -1
