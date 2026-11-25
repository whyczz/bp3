(* Warden read-only I/O edge (warden-v0 cli.1): gathers Layer-1 git/repo
   facts (active QUEST.md statuses, real quests, node ledgers & metrics,
   open desks, post-land commits) and Layer-2 joined Tx session traces via
   Metrics_io. Never writes git refs, state files, or .git/bp3/ records. *)
open Gitx

(* ---------- QUEST.md frontmatter & quest discovery ---------- *)

let frontmatter_status text =
  let lines = String.split_on_char '\n' text in
  match lines with
  | first :: rest when String.trim first = "---" ->
      let rec go = function
        | [] -> ""
        | l :: _ when String.trim l = "---" -> ""
        | l :: r ->
            (match String.index_opt l ':' with
             | Some i when String.trim (String.sub l 0 i) = "status" ->
                 String.trim (String.sub l (i + 1) (String.length l - i - 1))
             | _ -> go r) in
      go rest
  | _ -> ""

let quest_md_path q =
  Filename.concat (Filename.concat (Filename.concat root Layout.quests_root) q) Layout.quest_file

let feedback_md_path q =
  Filename.concat (Filename.concat (Filename.concat root Layout.quests_root) q) Layout.feedback_file

let quest_dirs () =
  let dir = Filename.concat root Layout.quests_root in
  if not (Sys.file_exists dir && Sys.is_directory dir) then []
  else
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun q ->
           let sub = Filename.concat dir q in
           (try Sys.is_directory sub with _ -> false)
           && Sys.file_exists (Filename.concat sub Layout.quest_file))
    |> List.sort String.compare

let active_quests () =
  quest_dirs ()
  |> List.filter (fun q ->
         frontmatter_status (read_file_or (quest_md_path q) "") = "active")

let has_feedback q = Sys.file_exists (feedback_md_path q)

(* Select real quests (those with docs/quests/<q>/QUEST.md AND bp3 state):
   newest first by quest slug, skipping quests with FEEDBACK.md unless ~all. *)
let select_real_quests ~last ~all =
  let real =
    quest_dirs ()
    |> List.filter (fun q -> Store.fold_quest q <> None)
    |> List.sort (fun a b -> String.compare b a) in
  let filtered =
    if all then real
    else List.filter (fun q -> not (has_feedback q)) real in
  let rec take n = function
    | [] -> []
    | _ when n <= 0 -> []
    | x :: xs -> x :: take (n - 1) xs in
  let picked = if all then filtered else take last filtered in
  List.rev picked

(* ---------- desks (read-only via Worktree.load_records) ---------- *)

let open_desks_for q =
  Worktree.load_records ()
  |> List.filter (fun (r : Worktree.record) -> r.r_quest = q)
  |> List.map (fun (r : Worktree.record) ->
         let missing = not (Sys.file_exists (Worktree.abs_path r.r_path)) in
         { Warden.di_run_id = r.r_run; di_quest = r.r_quest; di_node = r.r_node;
           di_path = r.r_path; di_missing = missing })

(* ---------- post-land bugfix commits ---------- *)

let is_status_only_path q path =
  let root_prefix = Layout.quests_root ^ "/" in
  if not (String.starts_with ~prefix:root_prefix path) then false
  else
    let rest = String.sub path (String.length root_prefix) (String.length path - String.length root_prefix) in
    match String.index_opt rest '/' with
    | None -> false
    | Some i ->
        let slug = String.sub rest 0 i in
        let rel = String.sub rest (i + 1) (String.length rest - i - 1) in
        rel = Layout.quest_file || rel = Layout.log_file || rel = Layout.feedback_file
        || (slug = q && (String.starts_with ~prefix:"demo/" rel
                         || String.starts_with ~prefix:"trial/" rel))

let is_release_commit_subject sha =
  let subj, code = git_out [ "show"; "-s"; "--format=%s"; sha ] in
  code = 0 &&
  (String.starts_with ~prefix:"chore(release): v" subj
   || String.starts_with ~prefix:"chore(promote): " subj)

let is_release_only_path q path =
  is_status_only_path q path
  || path = "src/quest/gitx.ml"
  || path = "VERSION"

let commit_is_status_only q sha =
  let out, code = git_out [ "diff-tree"; "--no-commit-id"; "--name-only"; "-r"; sha ] in
  if code <> 0 then true
  else
    let files =
      String.split_on_char '\n' out
      |> List.map String.trim
      |> List.filter (fun s -> s <> "") in
    files = []
    || List.for_all (is_status_only_path q) files
    || (is_release_commit_subject sha && List.for_all (is_release_only_path q) files)

let last_land_commit (nodes : Warden.node_evidence list) =
  let all_terminal = nodes <> [] && List.for_all (fun (ne : Warden.node_evidence) ->
      ne.ne_state = "landed" || ne.ne_state = "deleted") nodes in
  if not all_terminal then None
  else
    let best = ref ("", "") in
    List.iter (fun (ne : Warden.node_evidence) ->
        if ne.ne_state = "landed" then
          let last_c = ref "" in
          List.iter (fun (e : Warden.ledger_entry) ->
              if not e.le_refused then begin
                (match e.le_commit with Some c when c <> "" -> last_c := c | _ -> ());
                if e.le_edge = "land" && !last_c <> "" && e.le_ts >= fst !best then
                  best := (e.le_ts, !last_c)
              end) ne.ne_entries) nodes;
    let sha = snd !best in
    if sha = "" then None else resolve_commit sha

let is_ancestor anc desc =
  run_status (git [ "merge-base"; "--is-ancestor"; anc; desc ]) = 0

(* Find the commit on HEAD that flipped docs/quests/<q>/QUEST.md to
   status: landed, after last_land_sha (if any). *)
let landed_status_commit q last_sha =
  let qpath = Layout.quests_root ^ "/" ^ q ^ "/" ^ Layout.quest_file in
  let out, code = git_out [ "log"; "--format=%H"; "--reverse"; last_sha ^ "..HEAD"; "--"; qpath ] in
  if code <> 0 || String.trim out = "" then None
  else
    String.split_on_char '\n' out
    |> List.map String.trim
    |> List.filter (fun s -> s <> "")
    |> List.find_opt (fun sha ->
           match git_show sha qpath with
           | Some text -> frontmatter_status text = "landed"
           | None -> false)

let post_land_commits_for q nodes =
  match last_land_commit nodes with
  | None -> []
  | Some last_sha ->
      let work_ref = "refs/heads/" ^ Layout.work_branch q in
      let end_ref =
        match ref_tip work_ref with
        | Some tip when is_ancestor last_sha tip -> Some tip
        | _ ->
            if is_ancestor last_sha "HEAD" then
              match landed_status_commit q last_sha with
              | Some landed_sha -> Some landed_sha
              | None ->
                  let st = frontmatter_status (read_file_or (quest_md_path q) "") in
                  if st = "landed" || st = "canceled" then None
                  else Some "HEAD"
            else None in
      match end_ref with
      | None -> []
      | Some er ->
          let out, code = git_out [ "log"; "--no-merges"; "--format=%H\t%s"; last_sha ^ ".." ^ er ] in
          if code <> 0 || String.trim out = "" then []
          else
            String.split_on_char '\n' out
            |> List.filter_map (fun ln ->
                   let ln = String.trim ln in
                   if ln = "" then None
                   else match String.index_opt ln '\t' with
                     | Some i ->
                         let sha = String.sub ln 0 i in
                         let subj = String.sub ln (i + 1) (String.length ln - i - 1) in
                         if commit_is_status_only q sha then None
                         else Some { Warden.plc_sha = sha; plc_subject = subj }
                     | None -> None)

(* ---------- load quest & repo evidence ---------- *)

let load_quest q ~no_sessions ~dirs ~pi_dirs ~agy_dirs =
  let nodes =
    Store.list_nodes q
    |> List.map (fun node ->
           let text = Metrics_io.node_text q node in
           let entries = Warden.entries_of_text text in
           let state = match Store.fold_node q node with
             | Some (_, s, _) -> s.st
             | None -> "todo" in
           let samples = Metrics_io.read_samples q node in
           { Warden.ne_node = node; ne_state = state; ne_entries = entries; ne_samples = samples }) in
  let open_desks = open_desks_for q in
  let post_land = post_land_commits_for q nodes in
  let traces =
    if no_sessions then []
    else
      let ds = if dirs = [] then Metrics_io.default_dirs () else dirs in
      let pds = if pi_dirs = [] then Metrics_io.default_pi_dirs () else pi_dirs in
      let ads = if agy_dirs = [] then Metrics_io.default_agy_dirs () else agy_dirs in
      Metrics_io.joined_traces q ~dirs:ds ~pi_dirs:pds ~agy_dirs:ads in
  { Warden.qe_quest = q; qe_nodes = nodes; qe_open_desks = open_desks;
    qe_post_land_commits = post_land; qe_traces = traces }

let load ~scope ~quests ~no_sessions ~dirs ~pi_dirs ~agy_dirs =
  let (has_cfg, grade_wall_s) =
    match Backpack.load_opt root with
    | Ok (Some cfg) ->
        (true, float_of_int (Option.value cfg.warden_grade_wall_s ~default:300))
    | Ok None -> (false, 300.)
    | Error detail ->
        err Names.e_invalid_config
          (`Assoc [("file", json_str Layout.manifest_file); ("detail", json_str detail)])
          ("Invalid " ^ Layout.manifest_file ^ ": " ^ detail) 1 in
  let active = active_quests () in
  let q_evs = List.map (load_quest ~no_sessions ~dirs ~pi_dirs ~agy_dirs) quests in
  { Warden.ev_scope = scope; ev_active_quests = active; ev_quests = q_evs;
    ev_has_repo_config = has_cfg; ev_grade_wall_s = grade_wall_s }
