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
let has_quest_md q = Sys.file_exists (quest_md_path q)

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
                if (e.le_edge = "land" || e.le_to = "landed") && !last_c <> "" && e.le_ts >= fst !best then
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

(* ---------- full-session discovery, human-log & query (warden-planned-gates session.2) ---------- *)

type session_file = {
  sf_sid : string;
  sf_harness : string;
  sf_path : string;
  sf_mtime : float;
}

let resolved_dirs ~dirs ~pi_dirs ~agy_dirs =
  let ds = if dirs = [] then Metrics_io.default_dirs () else dirs in
  let pds = if pi_dirs = [] then Metrics_io.default_pi_dirs () else pi_dirs in
  let ads = if agy_dirs = [] then Metrics_io.default_agy_dirs () else agy_dirs in
  (ds, pds, ads)

let file_mtime p = try (Unix.stat p).Unix.st_mtime with _ -> 0.

let stem_of_jsonl path =
  let b = Filename.basename path in
  if Filename.check_suffix b ".jsonl" then Filename.chop_suffix b ".jsonl" else b

let pi_sid_of_path path =
  let b = stem_of_jsonl path in
  match String.index_opt b '_' with
  | Some i when i + 1 < String.length b -> String.sub b (i + 1) (String.length b - i - 1)
  | _ -> b

let list_all_session_files ~dirs ~pi_dirs ~agy_dirs =
  let (ds, pds, ads) = resolved_dirs ~dirs ~pi_dirs ~agy_dirs in
  let agy =
    List.concat_map (fun d ->
        List.map (fun (conv, p) ->
            { sf_sid = conv; sf_harness = "agy"; sf_path = p; sf_mtime = file_mtime p })
          (Metrics_io.agy_files d)) ads in
  let claude =
    List.concat_map (fun d ->
        List.map (fun p ->
            { sf_sid = stem_of_jsonl p; sf_harness = "claude"; sf_path = p; sf_mtime = file_mtime p })
          (Metrics_io.main_files d)) ds in
  let pi =
    List.concat_map (fun d ->
        List.map (fun p ->
            { sf_sid = pi_sid_of_path p; sf_harness = "pi"; sf_path = p; sf_mtime = file_mtime p })
          (Metrics_io.pi_files d)) pds in
  let seen = Hashtbl.create 32 in
  List.filter (fun sf ->
      let k = (sf.sf_harness, sf.sf_sid) in
      if Hashtbl.mem seen k then false else (Hashtbl.replace seen k (); true))
    (agy @ claude @ pi)

let find_session_file ~sid ~dirs ~pi_dirs ~agy_dirs =
  let files = list_all_session_files ~dirs ~pi_dirs ~agy_dirs in
  if sid = "latest" then
    List.fold_left (fun best sf ->
        match best with
        | None -> Some sf
        | Some b ->
            if sf.sf_mtime > b.sf_mtime
               || (sf.sf_mtime = b.sf_mtime && String.compare sf.sf_sid b.sf_sid > 0)
            then Some sf else Some b) None files
  else
    List.find_opt (fun sf -> sf.sf_sid = sid || stem_of_jsonl sf.sf_path = sid) files

let read_full_text_opt path =
  let full = Filename.concat (Filename.dirname path) "transcript_full.jsonl" in
  Metrics_io.read_file_opt full

let read_interactions_of_file sf =
  match Metrics_io.read_file_opt sf.sf_path with
  | None -> []
  | Some text ->
      (match sf.sf_harness with
       | "agy" ->
           let full_text = read_full_text_opt sf.sf_path in
           Agy_tx.parse_interactions ?full_text text
       | "claude" -> Claude_tx.parse_interactions text
       | "pi" -> Pi_tx.parse_interactions text
       | _ -> [])

let query_file sf ~around ~window =
  match Metrics_io.read_file_opt sf.sf_path with
  | None -> []
  | Some text ->
      (match sf.sf_harness with
       | "agy" ->
           let full_text = read_full_text_opt sf.sf_path in
           Agy_tx.query_window ?full_text ~around ~window text
       | "claude" -> Claude_tx.query_window ~around ~window text
       | "pi" -> Pi_tx.query_window ~around ~window text
       | _ -> [])

let quest_sessions_log_path q =
  match git_common_dir () with
  | Some gd ->
      let canon = try Unix.realpath gd with _ -> gd in
      Some (Filename.concat (Filename.concat (Filename.concat canon "bp3") "quest-sessions") (q ^ ".jsonl"))
  | None -> None

let read_quest_session_events q =
  match quest_sessions_log_path q with
  | Some p when Sys.file_exists p ->
      Warden.parse_quest_session_events (read_file_or p "")
  | _ -> []

let group_events_by_sid events =
  let tbl = Hashtbl.create 8 in
  List.iter (fun (e : Warden.quest_session_event) ->
      let prev = Option.value (Hashtbl.find_opt tbl e.qse_sid) ~default:[] in
      Hashtbl.replace tbl e.qse_sid (prev @ [ e ])) events;
  tbl

let file_mentions_quest q text =
  Tx.contains text ("docs/quests/" ^ q ^ "/")
  || Tx.contains text ("bp3 q " ^ q)
  || Tx.contains text ("--quest " ^ q)
  || Tx.contains text ("--quest=" ^ q)

let infer_retro_phase text =
  if Tx.contains text "QUEST.red-ink.md" || Tx.contains text "QUEST.2b-reviewed.md" then "red-ink"
  else if Tx.contains text "e handoff" || Tx.contains text "e grade" then "induct"
  else if Tx.contains text "FEEDBACK.md" || Tx.contains text "bp3 release" then "fin"
  else "init"

let first_mention_ts q text =
  let lines = String.split_on_char '\n' text in
  let ts_of_line line =
    try
      let j = Yojson.Safe.from_string line in
      let raw =
        match Yojson.Safe.Util.member "created_at" j with
        | `String s when s <> "" -> s
        | _ ->
            (match Yojson.Safe.Util.member "timestamp" j with
             | `String s -> s
             | _ -> "") in
      Tx.seconds raw
    with _ -> None in
  let rec scan = function
    | [] -> None
    | line :: rest ->
        if file_mentions_quest q line then
          (match ts_of_line line with Some _ as hit -> hit | None -> scan rest)
        else scan rest in
  scan lines

let earliest_event_ts (evs : Warden.quest_session_event list) =
  match evs with
  | [] -> None
  | hd :: tl ->
      let earliest = List.fold_left (fun acc (e : Warden.quest_session_event) ->
          Int.min acc e.qse_ts) hd.Warden.qse_ts tl in
      Some (float_of_int earliest)

let strip_run_prefix run =
  match String.index_opt run ':' with
  | Some i when i + 1 < String.length run -> String.sub run (i + 1) (String.length run - i - 1)
  | _ -> run

let earliest_mention_across quests text =
  List.fold_left (fun acc q ->
      match first_mention_ts q text with
      | None -> acc
      | Some t -> (match acc with None -> Some t | Some prev -> Some (Float.min prev t)))
    None quests

let discover_quest_sessions ~allow_retro_scan q ~dirs ~pi_dirs ~agy_dirs =
  let events = read_quest_session_events q in
  let by_sid = group_events_by_sid events in
  let all_files = list_all_session_files ~dirs ~pi_dirs ~agy_dirs in
  let matched = ref [] in
  let seen = Hashtbl.create 16 in
  List.iter (fun sf ->
      match Hashtbl.find_opt by_sid sf.sf_sid with
      | Some evs ->
          Hashtbl.replace seen sf.sf_sid ();
          let event_min_ts = earliest_event_ts evs in
          let mention_min_ts =
            Option.bind (Metrics_io.read_file_opt sf.sf_path) (first_mention_ts q) in
          let min_ts = Warden.session_turn_floor ~event_min_ts ~mention_min_ts () in
          matched := (sf, evs, "init", min_ts) :: !matched
      | None -> ()) all_files;
  if allow_retro_scan then
    List.iter (fun sf ->
        if not (Hashtbl.mem seen sf.sf_sid) then
          match Metrics_io.read_file_opt sf.sf_path with
          | Some text when file_mentions_quest q text ->
              Hashtbl.replace seen sf.sf_sid ();
              let min_ts =
                Warden.session_turn_floor ~event_min_ts:None
                  ~mention_min_ts:(first_mention_ts q text) () in
              matched := (sf, [], infer_retro_phase text, min_ts) :: !matched
          | _ -> ()) all_files;
  List.rev !matched

(* O(1) count for default bp3 warden: reads ONLY quest-sessions/<q>.jsonl
   plus already-joined trace paths — never scans all transcripts on disk.
   Applies the same per-session min_ts floor as human-log so multi-quest
   sessions report matching turn counts. *)
let count_quest_human_turns_fast ~quests ~q_evs ~dirs ~pi_dirs ~agy_dirs =
  let min_event_by_sid = Hashtbl.create 16 in
  let joined_paths = Hashtbl.create 16 in
  List.iter (fun q ->
      List.iter (fun (e : Warden.quest_session_event) ->
          let ts = float_of_int e.qse_ts in
          match Hashtbl.find_opt min_event_by_sid e.qse_sid with
          | None -> Hashtbl.replace min_event_by_sid e.qse_sid ts
          | Some prev -> if ts < prev then Hashtbl.replace min_event_by_sid e.qse_sid ts)
        (read_quest_session_events q)) quests;
  List.iter (fun (qe : Warden.quest_evidence) ->
      List.iter (fun (tr : Tx.joined_trace) ->
          if tr.jt_path <> "" then Hashtbl.replace joined_paths tr.jt_path tr.jt_run) qe.qe_traces) q_evs;
  if Hashtbl.length min_event_by_sid = 0 && Hashtbl.length joined_paths = 0 then 0
  else
    let seen_paths = Hashtbl.create 16 in
    let total = ref 0 in
    let count_sf sf =
      let event_min_ts = Hashtbl.find_opt min_event_by_sid sf.sf_sid in
      let mention_min_ts =
        Option.bind (Metrics_io.read_file_opt sf.sf_path) (earliest_mention_across quests) in
      let min_ts = Warden.session_turn_floor ~event_min_ts ~mention_min_ts () in
      let kept = Warden.filter_turns_from_floor ~min_ts (read_interactions_of_file sf) in
      total := !total + List.length kept in
    if Hashtbl.length min_event_by_sid > 0 then begin
      let files = list_all_session_files ~dirs ~pi_dirs ~agy_dirs in
      List.iter (fun sf ->
          if Hashtbl.mem min_event_by_sid sf.sf_sid && not (Hashtbl.mem seen_paths sf.sf_path) then begin
            Hashtbl.replace seen_paths sf.sf_path ();
            count_sf sf
          end) files
    end;
    Hashtbl.iter (fun p run ->
        if not (Hashtbl.mem seen_paths p) then begin
          Hashtbl.replace seen_paths p ();
          let harness =
            if String.starts_with ~prefix:"agy:" run then "agy"
            else if String.starts_with ~prefix:"pi:" run then "pi"
            else "claude" in
          let sf = { sf_sid = strip_run_prefix run; sf_harness = harness; sf_path = p; sf_mtime = 0. } in
          count_sf sf
        end) joined_paths;
    !total

let load_human_log_quest q ~phase ~limit ~dirs ~pi_dirs ~agy_dirs =
  let discovered = discover_quest_sessions ~allow_retro_scan:true q ~dirs ~pi_dirs ~agy_dirs in
  let sessions = List.map (fun (sf, _, _, _) -> sf.sf_sid) discovered in
  let raw =
    List.concat_map (fun (sf, evs, fallback, min_ts) ->
        read_interactions_of_file sf
        |> Warden.filter_turns_from_floor ~min_ts
        |> List.map (fun (ht : Tx.human_turn) ->
               { Warden.i_phase = Warden.assign_phase ~turn_ts:ht.ht_ts ~events:evs ~fallback;
                 i_session_id = sf.sf_sid; i_harness = sf.sf_harness;
                 i_step = ht.ht_step; i_ts = ht.ht_ts; i_iso = ht.ht_iso;
                 i_source = ht.ht_source; i_agent_asked = ht.ht_agent_asked;
                 i_human_said = ht.ht_human_said; i_nearby_edges = ht.ht_nearby_edges }))
      discovered in
  let (interactions, truncated) = Warden.build_human_log ?phase ~limit raw in
  (sessions, interactions, truncated)

let load_human_log_session sid ~phase ~limit ~dirs ~pi_dirs ~agy_dirs =
  match find_session_file ~sid ~dirs ~pi_dirs ~agy_dirs with
  | None -> None
  | Some sf ->
      let raw =
        read_interactions_of_file sf
        |> List.map (fun (ht : Tx.human_turn) ->
               { Warden.i_phase = "standalone";
                 i_session_id = sf.sf_sid; i_harness = sf.sf_harness;
                 i_step = ht.ht_step; i_ts = ht.ht_ts; i_iso = ht.ht_iso;
                 i_source = ht.ht_source; i_agent_asked = ht.ht_agent_asked;
                 i_human_said = ht.ht_human_said; i_nearby_edges = ht.ht_nearby_edges }) in
      let (interactions, truncated) = Warden.build_human_log ?phase ~limit raw in
      Some (sf.sf_sid, [ sf.sf_sid ], interactions, truncated)

let load_query_session sid ~around ~window ~dirs ~pi_dirs ~agy_dirs =
  match find_session_file ~sid ~dirs ~pi_dirs ~agy_dirs with
  | None -> None
  | Some sf -> Some (sf.sf_sid, sf.sf_harness, query_file sf ~around ~window)

let load_session_evidence sid ~dirs ~pi_dirs ~agy_dirs =
  match find_session_file ~sid ~dirs ~pi_dirs ~agy_dirs with
  | None -> None
  | Some sf ->
      let text = Option.value (Metrics_io.read_file_opt sf.sf_path) ~default:"" in
      let (cost, events, run) = match sf.sf_harness with
        | "agy" ->
            let full_text = read_full_text_opt sf.sf_path in
            let tx = Agy_tx.parse ~conv_id:sf.sf_sid ?full_text text in
            (Agy_tx.cost tx, tx.tool_events, "agy:" ^ sf.sf_sid)
        | "claude" ->
            let tx = Claude_tx.parse text in
            (Claude_tx.cost tx, tx.tool_events, "claude:" ^ sf.sf_sid)
        | "pi" ->
            let tx = Pi_tx.parse text in
            (Pi_tx.cost tx, tx.tool_events, "pi:" ^ sf.sf_sid)
        | _ ->
            ({ Tx.wall_s = 0.; tool_calls = 0; context_end = 0; tokens_in = 0;
               tokens_out = 0; tokens_cache_read = 0; tokens_cache_write = 0;
               model = "unknown"; tool_s = 0.; tool_errors = 0; turns = 0 }, [], sf.sf_sid) in
      let tr = {
        Tx.jt_node = "(session)"; jt_cycle = 0; jt_role = "session";
        jt_path = sf.sf_path; jt_run = run; jt_context_end = cost.context_end;
        jt_turns = cost.turns; jt_tool_errors = cost.tool_errors;
        jt_events = events; jt_user_steps = [];
      } in
      let ht_count = List.length (read_interactions_of_file sf) in
      let qe = {
        Warden.qe_quest = ""; qe_nodes = []; qe_open_desks = [];
        qe_post_land_commits = []; qe_traces = [ tr ];
      } in
      let ev = {
        Warden.ev_scope = "session"; ev_active_quests = []; ev_quests = [ qe ];
        ev_has_repo_config = true; ev_grade_wall_s = 300.;
        ev_human_turns_count = ht_count;
      } in
      Some (sf.sf_sid, ev)

(* ---------- load quest & repo evidence ---------- *)

let load_quest q ~no_sessions ~dirs ~pi_dirs ~agy_dirs =
  let has_ledger = Store.fold_quest q <> None in
  let nodes =
    if not has_ledger then []
    else
      Store.list_nodes q
      |> List.map (fun node ->
             let text = Metrics_io.node_text q node in
             let entries = Warden.entries_of_text text in
             let (state, kind) = match Store.fold_node q node with
               | Some (_, s, _) -> (s.st, Store.node_kind_to_string s.node_kind)
               | None -> ("todo", "code") in
             let samples = Metrics_io.read_samples q node in
             { Warden.ne_node = node; ne_kind = kind; ne_state = state;
               ne_entries = entries; ne_samples = samples }) in
  let open_desks = open_desks_for q in
  let post_land = if has_ledger then post_land_commits_for q nodes else [] in
  let traces =
    if no_sessions || not has_ledger then []
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
  let ht_count =
    if no_sessions then 0
    else count_quest_human_turns_fast ~quests ~q_evs ~dirs ~pi_dirs ~agy_dirs in
  { Warden.ev_scope = scope; ev_active_quests = active; ev_quests = q_evs;
    ev_has_repo_config = has_cfg; ev_grade_wall_s = grade_wall_s;
    ev_human_turns_count = ht_count }
