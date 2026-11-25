#!/usr/bin/env bash
# Runnable sandbox demo for 2026-11-25-desk-auto-cleanup.
# Exercises:
#   1. Happy path: bp3 release <quest> auto-releases clean quest/grade desks + deletes merged quest/<slug> branch
#   2. Refusal/guard path: bp3 harness desk prune --dry-run previews and real prune keeps dirty desks untouched
#   3. Recovery: cleaning the dirty desk lets bp3 harness desk prune finish the sweep cleanly
set -euo pipefail

repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
bp3_bin="$repo/_build/default/src/quest/main.exe"
[ -x "$bp3_bin" ] || { echo "build first: dune build src/quest/main.exe" >&2; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/bp3-demo-cleanup.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

export BP3_DESKS_DIR="$work/desks"
export BP3_Q_BIN="$bp3_bin"
export BP3_DB="$work/bp3.sqlite"

proj="$work/repo"
mkdir -p "$proj/bin" "$proj/plans" "$proj/src/quest" "$proj/docs/quests/demo-q/nodes/node-1"
cp "$repo/bin/bp3" "$proj/bin/bp3"
chmod +x "$proj/bin/bp3"
cp "$repo/plans/default.yaml" "$proj/plans/default.yaml"
touch "$proj/src/quest/main.ml"
git -C "$proj" init -q -b master
git -C "$proj" config user.email demo@bp3
git -C "$proj" config user.name demo
printf -- '---\nstatus: proposed\nbump: minor\n---\n# demo-q: demo auto-cleanup\n' > "$proj/docs/quests/demo-q/QUEST.md"
git -C "$proj" add -A && git -C "$proj" commit -qm init
git -C "$proj" tag v0.1.0

echo "== 1. Prepare quest desk, land node, and run bp3 release demo-q =="
(cd "$proj" && ./bin/bp3 q c demo-q >/dev/null)
(cd "$proj" && ./bin/bp3 q demo-q c node-1 >/dev/null)
qdesk="$(cd "$proj" && ./bin/bp3 harness desk prepare --quest demo-q | jq -r '.path')"
echo "quest desk: $qdesk"
echo "hello" > "$qdesk/feature.txt"
git -C "$qdesk" add feature.txt && git -C "$qdesk" commit -qm "feat: demo change"
sha="$(git -C "$qdesk" rev-parse HEAD)"
(cd "$qdesk" && ./bin/bp3 q demo-q n node-1 e handoff --commit "$sha" --reason "demo" >/dev/null)
(cd "$qdesk" && ./bin/bp3 q demo-q n node-1 e grade --verdict ship --verify-verdict pass --reason "demo" >/dev/null)
(cd "$qdesk" && ./bin/bp3 q demo-q n node-1 e land --reason "demo" >/dev/null)

rel_json="$(cd "$proj" && BP3_DECIDER=human ./bin/bp3 release demo-q --no-gh --no-install)"
printf '%s\n' "$rel_json" | jq '{tag, released_desks, kept_desks, branch_deleted}'
printf '%s' "$rel_json" | jq -e '.ok == true and (.released_desks | length) == 1 and .branch_deleted == true' >/dev/null
[ ! -e "$qdesk" ] || { echo "FAIL: quest desk still exists" >&2; exit 1; }

echo "== 2. Plant a dirty leftover desk, preview with prune --dry-run =="
(cd "$proj" && ./bin/bp3 q c stale-q >/dev/null)
sdesk="$(cd "$proj" && ./bin/bp3 harness desk prepare --quest stale-q | jq -r '.path')"
mkdir -p "$proj/docs/quests/stale-q"
printf -- '---\nstatus: landed\n---\n# stale-q\n' > "$proj/docs/quests/stale-q/QUEST.md"
echo "dirty-work" > "$sdesk/wip.txt"

dry_json="$(cd "$proj" && ./bin/bp3 harness desk prune --dry-run)"
printf '%s\n' "$dry_json" | jq '{dry_run, kept}'
printf '%s' "$dry_json" | jq -e '.dry_run == true and (.kept[] | select(.reason == "dirty")) != null' >/dev/null

echo "== 3. Real prune keeps dirty desk safe; once cleaned, prune sweeps it =="
keep_json="$(cd "$proj" && ./bin/bp3 harness desk prune)"
printf '%s' "$keep_json" | jq -e '.dry_run == false and (.kept[] | select(.reason == "dirty")) != null' >/dev/null
[ -d "$sdesk" ] || { echo "FAIL: dirty desk was removed" >&2; exit 1; }

rm -f "$sdesk/wip.txt"
clean_json="$(cd "$proj" && ./bin/bp3 harness desk prune)"
printf '%s\n' "$clean_json" | jq '{released, deleted_branches}'
printf '%s' "$clean_json" | jq -e '(.released | index("quest-stale-q") != null)' >/dev/null
[ ! -e "$sdesk" ] || { echo "FAIL: cleaned desk not swept" >&2; exit 1; }

echo "demo ok: release auto-cleanup + desk prune verified!"
