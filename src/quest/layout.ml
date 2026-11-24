(* layout — every repo path, file name and ref prefix bp3 spells,
   in one place. A rename edits this file; callers never spell a
   path or ref themselves. Legacy spellings are read-only: folded
   on read, never written. *)

(* ---------- repo tree ---------- *)
let engine_src = "src/quest"
let quests_root = "docs/quests"
(* Storage-branch trees were never rewritten by earlier renames:
   a tip may hold its ledgers under any of these, in any era. *)
let legacy_quests_roots = ["docs/graphs"; "docs/goals"]
let quest_file = "QUEST.md"
let log_file = "LOG.md"
let feedback_file = "FEEDBACK.md"
let nodes_dir = "nodes"
let legacy_nodes_dirs = ["experiments"]
let ledger_file = "ledger.jsonl"
let state_file = "state.yaml"
let metrics_file = "metrics.jsonl"
let runs_dir = "runs"
let icebox_dir = "docs/icebox"
let desks_root = ".bp3/worktrees"
let context_file = ".bp3-context.json"

(* ---------- refs ---------- *)
(* Storage branches live under refs/heads/bp3/<kind>/; work
   branches are <kind>/<quest> beside the integration branch. *)
let ref_root = "refs/heads/bp3/"
let quest_ref_kind = "quest"
let legacy_quest_ref_kinds = ["graph"; "goal"]
let node_ref_kind = "node"
let legacy_node_ref_kinds = ["exp"]
let work_branch_kind = "quest"

(* ---------- derived ---------- *)
let quest_dir_in root q = root ^ "/" ^ q
let quest_dir q = quest_dir_in quests_root q
let quest_ref_prefix_of kind = ref_root ^ kind ^ "/"
let quest_ref_of kind q = quest_ref_prefix_of kind ^ q
let node_ref_prefix_of kind q = ref_root ^ kind ^ "/" ^ q ^ "/"
(* short branch name (no refs/heads/), as worktree add takes it *)
let node_branch_short q node = "bp3/" ^ node_ref_kind ^ "/" ^ q ^ "/" ^ node
let work_branch q = work_branch_kind ^ "/" ^ q
let desk_dir q = desks_root ^ "/" ^ q
