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
let legacy_desks_root = ".bp3/worktrees"
let legacy_desks_meta_dir = ".bp3/desks"
(* Kept as alias to legacy_desks_root until metrics_io.ml switches to dual-prefix. *)
let desks_root = legacy_desks_root
let desks_env_var = "BP3_DESKS_DIR"
let default_desks_rel = ".bp3/desks"
let quests_desks_subdir = "quests"
let runs_desks_subdir = "runs"
let desks_meta_subdir = ".meta"
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

(* ---------- central desks (pure) ---------- *)
let strip_trailing_slashes s =
  let rec loop i =
    if i > 1 && s.[i - 1] = '/' then loop (i - 1) else String.sub s 0 i in
  loop (String.length s)

let join_path a b =
  let a = strip_trailing_slashes a in
  if a = "/" then "/" ^ b else a ^ "/" ^ b

let sanitize_repo_slug name =
  let n = String.length name in
  let buf = Buffer.create n in
  let prev_dash = ref true in
  for i = 0 to n - 1 do
    let c = Char.lowercase_ascii name.[i] in
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then begin
      Buffer.add_char buf c;
      prev_dash := false
    end else if not !prev_dash then begin
      Buffer.add_char buf '-';
      prev_dash := true
    end
  done;
  let raw = Buffer.contents buf in
  let len = String.length raw in
  let trimmed =
    if len > 0 && raw.[len - 1] = '-' then String.sub raw 0 (len - 1) else raw in
  if trimmed = "" then "repo" else trimmed

let repo_key repo_name canon_common_dir =
  let slug = sanitize_repo_slug repo_name in
  let hex = Digest.to_hex (Digest.string canon_common_dir) in
  slug ^ "-" ^ String.sub hex 0 8

let desks_base_of env_desks home =
  match env_desks with
  | Some d when String.trim d <> "" -> strip_trailing_slashes d
  | _ ->
      (match home with
       | Some h when String.trim h <> "" -> join_path h default_desks_rel
       | _ -> default_desks_rel)

let repo_desks_dir base key =
  join_path base key

let quest_desk_dir repo_dir quest =
  join_path repo_dir (quests_desks_subdir ^ "/" ^ quest)

let run_desk_dir repo_dir quest node run_id =
  join_path repo_dir (String.concat "/" [ runs_desks_subdir; quest; node; run_id ])

let desks_meta_dir repo_dir =
  join_path repo_dir desks_meta_subdir
