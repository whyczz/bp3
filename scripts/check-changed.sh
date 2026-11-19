#!/bin/bash
# check-changed — change-scoped verification (node-followup-6-check-tiers).
# Runs the retired-term sweep first (seconds, before any suite),
# prints the chosen suites, then runs only those. Unknown or
# unmapped paths fail safe to the fast tier: never zero suites.
#
# Usage:
#   scripts/check-changed.sh [--list] [--fast] [path ...]
#   make check-changed        # paths from git diff vs HEAD + untracked
#   make check-fast           # the fast tier below
# --list prints the chosen suite ids, runs nothing (fixture door).
# -h/--help prints this text, exit 0, reads no state.
#
# Suite table (single source; ids name Makefile check suites).
#   id            command
#   lint          make lint
#   check-skills  ./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
#   skills-check  ./bin/bp3 skills check
#   skills        ./test/skills.sh
#   build         dune build src/quest/main.exe (Makefile SDK rule)
#   g             ./test/g.sh
#   js-unit       ./test/js-unit.sh (JS unit tier: workflows + bp3-pi on the fake bp3)
#   pi-tree       scripts/run-suites --only pi-tree (slow tier, through run-suites)
#   bp3-pi        node --test extensions/bp3-pi/test/bp3-pi-real.test.mjs
#   transcripts   ./test/transcripts.sh (fake bp3 drift check)
#   induct          ./test/induct.sh (all workflow node tests)
#   wf:<name>     node test/<name>.test.mjs (one workflow test)
#   check-tiers   ./test/check-tiers.sh (selector fixtures)
#   test:<path>   the changed test file itself
#
# Fast tier (check-fast): lint + skills checks + unit/workflow
# tests, zero wall-clock timer fixtures. Membership (one table):
#   lint check-skills skills build induct js-unit bp3-pi check-tiers
# test/harness.sh is the wall-clock suite (sleep/watch cases)
# and stays full-tier only; so do the integration drives
# (g, ready, dogfood-*, worktree, tape, release, install),
# reached through the mapping below or full make check.
#
# Path -> suite mapping (first match wins):
#   skills/induct/workflows/*.js, .agents/workflows/*.js
#       -> skills-check + the one matching wf:<name> test
#   skills/**, .pi/skills/**, .agents/skills/**, .claude/skills/**
#       -> check-skills skills induct        (never harness)
#   src/**  -> build g bp3-pi transcripts  (never skills suites)
#   test/pi-tree.test.mjs -> build pi-tree (through run-suites)
#   test/fake-bp3/**, scripts/record-transcripts -> build js-unit transcripts
#   test/** -> build + the changed suite itself
#   extensions/** -> build js-unit bp3-pi transcripts
#   bin/**, scripts/**, completions/**, Makefile -> fast tier
#   anything else (docs/** included)        -> fast tier
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
list_only=0; fast=0; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list_only=1 ;;
    --fast) fast=1 ;;
    -h|--help) grep '^#' "$0" | head -50; exit 0 ;;
    *) paths+=("$1") ;;
  esac
  shift
done
# Makefile's SDK rule, mirrored: 26.5 SDK links on this host.
dune_build="dune build"
[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ] && dune_build="SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk dune build"
case "$root" in */.bp3/worktrees/*) dune_build="$dune_build --root=." ;; esac
cmd_for() {
  case "$1" in
    lint) echo "make lint" ;;
    check-skills) echo "./scripts/check-skills skills .pi/skills .agents/skills .claude/skills" ;;
    skills-check) echo "./bin/bp3 skills check" ;;
    skills) echo "./test/skills.sh" ;;
    build) echo "$dune_build src/quest/main.exe" ;;
    g) echo "./test/g.sh" ;;
    js-unit) echo "./test/js-unit.sh" ;;
    pi-tree) echo "scripts/run-suites --only pi-tree" ;;
    bp3-pi) echo "node --test extensions/bp3-pi/test/bp3-pi-real.test.mjs" ;;
    transcripts) echo "./test/transcripts.sh" ;;
    induct) echo "./test/induct.sh" ;;
    check-tiers) echo "./test/check-tiers.sh" ;;
    wf:*) echo "node test/${1#wf:}.test.mjs" ;;
    test:*) local p=${1#test:}; case "$p" in *.sh) echo "./$p" ;; *) echo "node $p" ;; esac ;;
    *) echo "unknown suite: $1" >&2; return 1 ;;
  esac
}
order="lint check-skills skills-check skills build g js-unit pi-tree bp3-pi transcripts induct check-tiers"
declare -a want=()
add() { local s; for s in "${want[@]:-}"; do [ "$s" = "$1" ] && return 0; done; want+=("$1"); }
add_fast() { local s; for s in lint check-skills skills build induct js-unit bp3-pi check-tiers; do add "$s"; done; }
if [ "$fast" = 1 ]; then
  add_fast
else
  if [ ${#paths[@]} -eq 0 ]; then
    while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done < <({ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
  fi
  if [ ${#paths[@]} -eq 0 ]; then
    echo "check-changed: no changed paths; fast tier (fail-safe)" >&2
    add_fast
  fi
  for p in "${paths[@]:-}"; do
    [ -n "$p" ] || continue
    case "$p" in
      skills/induct/workflows/*.js|.agents/workflows/*.js)
        add skills-check
        case "$(basename "$p")" in
          node-loop.js) add wf:node-loop ;;
          induct-node.js) add wf:induct-node ;;
          induct-grade.js) add wf:induct-grade ;;
          induct-land.js) add wf:induct-land ;;
          *) add induct ;;
        esac ;;
      skills/*|.pi/skills/*|.agents/skills/*|.claude/skills/*)
        add check-skills; add skills; add induct ;;
      src/*) add build; add g; add bp3-pi; add transcripts ;;
      test/pi-tree.test.mjs) add build; add pi-tree ;;
      test/fake-bp3/*|scripts/record-transcripts) add build; add js-unit; add transcripts ;;
      test/*) add build; add "test:$p" ;;
      extensions/*) add build; add js-unit; add bp3-pi; add transcripts ;;
      bin/*|scripts/*|completions/*|Makefile) add_fast ;;
      *) add_fast ;;
    esac
  done
fi
# Emit in canonical order, then any wf:/test: ids sorted.
declare -a suites=()
for s in $order; do for w in "${want[@]:-}"; do [ "$w" = "$s" ] && suites+=("$s"); done; done
while IFS= read -r s; do [ -n "$s" ] && suites+=("$s"); done < <(printf '%s\n' "${want[@]:-}" | grep -E '^(wf:|test:)' | LC_ALL=C sort -u || true)
[ ${#suites[@]} -gt 0 ] || { echo "check-changed: zero suites selected (bug)" >&2; exit 1; }
if [ "$list_only" = 1 ]; then printf '%s\n' "${suites[@]}"; exit 0; fi
echo "check-changed: suites: ${suites[*]}"
# Retired-term sweep first: a stale term fails in seconds,
# before any suite runs (fast tier and check-changed alike).
./scripts/check-retired-terms.sh
for s in "${suites[@]}"; do
  c=$(cmd_for "$s")
  echo "check-changed: run $s: $c"
  bash -c "$c"
done
echo "check-changed: ok (${#suites[@]} suites)"
