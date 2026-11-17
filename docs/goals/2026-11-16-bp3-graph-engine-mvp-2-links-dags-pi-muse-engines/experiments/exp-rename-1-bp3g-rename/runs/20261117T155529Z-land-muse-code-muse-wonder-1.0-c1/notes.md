# Land — exp-rename-1-bp3g-rename @ 4e0f1bd (cycle 1)

- Claimed link bp3link_b0fe7880eab1c0ab194074fb62d11ff0 -> run_id 20261117T155529Z-land-muse-code-muse-wonder-1.0-c1 (matches expected).
- Pre-land read: state=approved, cycle=1, commit=4e0f1bd0d90f13a12623012b5628f7c38165577c, legal_edges=[land,block,delete].
- Prior evidence: grade ship, verify pass at 4e0f1bd.
- Fresh checks: bound commit exists and is ancestor of HEAD e37190a (later sibling landings on same branch); no ledger paths in 4e0f1bd (history frozen); `./bin/bp3 q foo` exit 2; `sh test/bp3g.sh` ok; `sh test/skills.sh` ok (134 assertions). Tree clean except harness-written untracked `.bp3-context.json`.

Lessons: HEAD need not equal the bound commit at land time when sibling nodes land first on the shared graph branch — check ancestry, not equality. Skills assertion count drifts (128 -> 134) as later nodes add renders; judge pass/fail, not the count.

Land edge returned ok=true, state=landed, fin=node_fin, commit=4e0f1bd; post-land read confirms landed with legal_edges=[].
