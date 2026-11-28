#!/usr/bin/env bash
# Sandboxed runnable demo for quest 2026-11-27-predictor-tickets-bundle.
# Uses a scratch mktemp directory and never mutates the real repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BP3_BIN="${BP3_BIN:-$REPO_ROOT/_build/default/src/quest/main.exe}"
if [ ! -x "$BP3_BIN" ]; then
  echo "error: build main.exe first (dune build src/quest/main.exe): $BP3_BIN" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/plans" "$REPO/docs/quests/demo/nodes/node-a-1"
cp "$REPO_ROOT/plans/default.yaml" "$REPO/plans/default.yaml"

git -C "$REPO" init -q -b master
git -C "$REPO" config user.email "demo@bp3.local"
git -C "$REPO" config user.name "bp3 demo"
cat > "$REPO/backpack.toml" <<'EOF'
version = 1
repo = "demo/repo"
EOF
git -C "$REPO" add backpack.toml plans/default.yaml
git -C "$REPO" commit -q -m "chore: init demo repo"

bp3_demo() {
  (cd "$REPO" && BP3_ROOT="$REPO" BP3_HARNESS=agy BP3_MODEL=demo "$BP3_BIN" "$@")
}

bp3_demo q c demo --type default >/dev/null
bp3_demo q demo c node-a-1 >/dev/null

echo "=== 1. Happy path: NODE.md with ## Acceptance test fallback (Ticket #10) ==="
cat > "$REPO/docs/quests/demo/nodes/node-a-1/NODE.md" <<'EOF'
# a.1 - test-only-heading

## Acceptance test

- proof: fallback body inlined cleanly
EOF
echo "impl v1" > "$REPO/app.txt"
git -C "$REPO" add docs/quests/demo/nodes/node-a-1/NODE.md app.txt
git -C "$REPO" commit -q -m "feat: add app v1 with Acceptance test heading"
SHA1="$(git -C "$REPO" rev-parse HEAD)"
bp3_demo q demo n node-a-1 e handoff --commit "$SHA1" --allow-protected --reason "demo fallback" >/dev/null
BRIEF1="$(bp3_demo q demo n node-a-1 brief | jq -r '.brief')"
echo "$BRIEF1" | grep -A 3 "Acceptance gates (NODE.md at"
echo "$BRIEF1" | grep -qF "fallback body inlined cleanly"
if echo "$BRIEF1" | grep -qF "has no Acceptance gates section"; then exit 1; fi

echo ""
echo "=== 2. Precedence: ## Acceptance gates wins over ## Acceptance test ==="
bp3_demo q demo n node-a-1 e grade --verdict needs_fix --reason "advance to cycle 2" >/dev/null
cat > "$REPO/docs/quests/demo/nodes/node-a-1/NODE.md" <<'EOF'
# a.1 - both-headings

## Acceptance gates

- primary: gates heading wins

## Acceptance test

- secondary: fallback ignored
EOF
echo "impl v2" > "$REPO/app.txt"
git -C "$REPO" add docs/quests/demo/nodes/node-a-1/NODE.md app.txt
git -C "$REPO" commit -q -m "feat: add both headings"
SHA2="$(git -C "$REPO" rev-parse HEAD)"
bp3_demo q demo n node-a-1 e handoff --commit "$SHA2" --allow-protected --reason "demo precedence" >/dev/null
BRIEF2="$(bp3_demo q demo n node-a-1 brief | jq -r '.brief')"
echo "$BRIEF2" | grep -A 3 "Acceptance gates (NODE.md at"
echo "$BRIEF2" | grep -qF "primary: gates heading wins"
if echo "$BRIEF2" | grep -qF "secondary: fallback ignored"; then exit 1; fi

echo ""
echo "=== 3. Refusal & recovery: neither heading emits finding; adding gates clears it ==="
bp3_demo q demo n node-a-1 e grade --verdict needs_fix --reason "advance to cycle 3" >/dev/null
cat > "$REPO/docs/quests/demo/nodes/node-a-1/NODE.md" <<'EOF'
# a.1 - missing-headings

## Notes

No gates heading here.
EOF
echo "impl v3" > "$REPO/app.txt"
git -C "$REPO" add docs/quests/demo/nodes/node-a-1/NODE.md app.txt
git -C "$REPO" commit -q -m "feat: strip gates headings"
SHA3="$(git -C "$REPO" rev-parse HEAD)"
bp3_demo q demo n node-a-1 e handoff --commit "$SHA3" --allow-protected --reason "demo missing" >/dev/null
BRIEF3="$(bp3_demo q demo n node-a-1 brief | jq -r '.brief')"
echo "$BRIEF3" | grep -F "has no Acceptance gates section: that is a finding"

bp3_demo q demo n node-a-1 e grade --verdict needs_fix --reason "recover on cycle 4" >/dev/null
cat > "$REPO/docs/quests/demo/nodes/node-a-1/NODE.md" <<'EOF'
# a.1 - recovered

## Acceptance gates

- recovered: gates restored
EOF
echo "impl v4" > "$REPO/app.txt"
git -C "$REPO" add docs/quests/demo/nodes/node-a-1/NODE.md app.txt
git -C "$REPO" commit -q -m "fix: restore Acceptance gates heading"
SHA4="$(git -C "$REPO" rev-parse HEAD)"
bp3_demo q demo n node-a-1 e handoff --commit "$SHA4" --allow-protected --reason "demo recovered" >/dev/null
BRIEF4="$(bp3_demo q demo n node-a-1 brief | jq -r '.brief')"
echo "$BRIEF4" | grep -A 3 "Acceptance gates (NODE.md at"
echo "$BRIEF4" | grep -qF "recovered: gates restored"

echo ""
echo "=== 4. Skill invariants (Tickets #7, #8, #9, #10, #11a) ==="
grep -qF 'Explicit owner LGTM before advancing' "$REPO_ROOT/skills/red-ink/SKILL.md"
grep -qF '| Internals: layout |' "$REPO_ROOT/skills/red-ink/SKILL.md"
grep -qF '| Acceptance gates |' "$REPO_ROOT/skills/red-ink/SKILL.md"
if grep -qF '| Acceptance test |' "$REPO_ROOT/skills/red-ink/SKILL.md"; then exit 1; fi
if grep -qF 'parallel waves' "$REPO_ROOT/skills/red-ink/SKILL.md"; then exit 1; fi
if grep -qF '/swarm' "$REPO_ROOT/skills/induct/SKILL.md"; then exit 1; fi
grep -qF 'mechanical delta re-grades' "$REPO_ROOT/skills/induct/SKILL.md"
echo "skills/red-ink/SKILL.md: LGTM gate, Internals: layout, Acceptance gates OK (0 Acceptance test, 0 parallel waves)"
echo "skills/induct/SKILL.md:  0 /swarm refs, c2+ mechanical delta -> flash OK"

echo ""
echo "DEMO PASS: all 4 scenarios verified in scratch sandbox."
