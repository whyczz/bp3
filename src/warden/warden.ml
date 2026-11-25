(* Warden deterministic plug engine (warden-v0 plugs.1):
   12 composable, pure OCaml plugs across two layers:
   - Layer 1 (Git, 8 plugs + block-edge human_steer): always runs over
     ledger entries, metrics samples, QUEST.md active statuses, open desks,
     and post-land commits.
   - Layer 2 (Session, 4 plugs): runs automatically when joined Tx session
     traces are present (or skipped when traces = []).
   Zero I/O, zero git calls, zero mutation. *)

type layer = Git | Session
type severity = Major | Minor

type finding = {
  rule : string;
  layer : layer;
  severity : severity;
  quest : string;
  node : string;
  cycle : int;
  observed : string;
  threshold : string;
  evidence_ref : string;
  summary : string;
}

type ledger_entry = {
  le_ts : string;
  le_edge : string;
  le_to : string;
  le_cycle : int;
  le_commit : string option;
  le_verdict : string;
  le_reason : string;
  le_refused : bool;
  le_error_code : string;
}

type node_evidence = {
  ne_node : string;
  ne_state : string;
  ne_entries : ledger_entry list;
  ne_samples : Metrics.sample list;
}

type desk_info = {
  di_run_id : string;
  di_quest : string;
  di_node : string;
  di_path : string;
  di_missing : bool;
}

type post_land_commit = {
  plc_sha : string;
  plc_subject : string;
}

type quest_evidence = {
  qe_quest : string;
  qe_nodes : node_evidence list;
  qe_open_desks : desk_info list;
  qe_post_land_commits : post_land_commit list;
  qe_traces : Tx.joined_trace list;
}

type evidence = {
  ev_scope : string;
  ev_active_quests : string list;
  ev_quests : quest_evidence list;
  ev_has_repo_config : bool;
  ev_grade_wall_s : float;
}

(* ---------- ledger entry parsing ---------- *)

let str_field k j =
  match j with
  | `Assoc fs -> (match List.assoc_opt k fs with Some (`String s) -> s | _ -> "")
  | _ -> ""

let str_opt_field k j =
  match j with
  | `Assoc fs -> (match List.assoc_opt k fs with Some (`String s) when s <> "" -> Some s | _ -> None)
  | _ -> None

let int_field k default j =
  match j with
  | `Assoc fs -> (match List.assoc_opt k fs with Some (`Int n) -> n | _ -> default)
  | _ -> default

let bool_field k j =
  match j with
  | `Assoc fs -> (match List.assoc_opt k fs with Some (`Bool b) -> b | _ -> false)
  | _ -> false

let extract_error_code j edge reason =
  let candidates = [ str_field "code" j; str_field "error_code" j; str_field "error" j ] in
  let first_e = List.find_opt (fun s -> String.starts_with ~prefix:"E_" s) candidates in
  match first_e with
  | Some c -> c
  | None ->
      if edge = "refused" || bool_field "refused" j then
        (match String.split_on_char ' ' (String.trim reason) with
         | tok :: _ when String.starts_with ~prefix:"E_" tok -> tok
         | _ ->
             let c = str_field "code" j in
             if c <> "" then c else "E_REFUSED")
      else ""

let entries_of_text text =
  String.split_on_char '\n' text
  |> List.filter_map (fun ln ->
         let ln = String.trim ln in
         if ln = "" then None
         else
           try
             let j = Yojson.Safe.from_string ln in
             let raw_edge = str_field "edge" j in
             let edge = Store.fold_edge raw_edge in
             let reason = str_field "reason" j in
             let err_code = extract_error_code j raw_edge reason in
             let refused = raw_edge = "refused" || bool_field "refused" j || err_code <> "" in
             Some {
               le_ts = str_field "ts" j;
               le_edge = edge;
               le_to = Store.fold_state_name (str_field "to" j);
               le_cycle = int_field "cycle" 1 j;
               le_commit = str_opt_field "commit" j;
               le_verdict = str_field "verdict" j;
               le_reason = reason;
               le_refused = refused;
               le_error_code = err_code;
             }
           with _ -> None)

(* Pair each grade entry with the cycle of its preceding handoff so
   needs_fix lines (which carry cycle + 1 in bp3 ledgers) report the
   cycle actually bounced. *)
let grade_entries_with_cycle entries =
  let rec go last_c acc = function
    | [] -> List.rev acc
    | e :: rest when e.le_refused -> go last_c acc rest
    | e :: rest when e.le_edge = "handoff" -> go (Some e.le_cycle) acc rest
    | e :: rest when e.le_edge = "grade" ->
        let c = Option.value last_c ~default:e.le_cycle in
        go None ((c, e) :: acc) rest
    | _ :: rest -> go last_c acc rest in
  go None [] entries

let contains_ci haystack needle =
  Tx.contains (String.lowercase_ascii haystack) (String.lowercase_ascii needle)

let short_sha s = String.sub s 0 (min 7 (String.length s))

(* ---------- Layer 1 plugs (git/repo) ---------- *)

(* 1. multi_active_quest: > 1 docs/quests/*/QUEST.md has status: active *)
let plug_multi_active_quest ev =
  let active = List.sort_uniq compare ev.ev_active_quests in
  let n = List.length active in
  if n > 1 then
    [ { rule = "multi_active_quest"; layer = Git; severity = Major;
        quest = ""; node = ""; cycle = 0;
        observed = Printf.sprintf "%d active quests" n;
        threshold = "> 1 active quest";
        evidence_ref = "repo:QUEST.md";
        summary = Printf.sprintf "%d quests have status: active (%s)" n (String.concat ", " active) } ]
  else []

(* 1b. missing_repo_config: backpack.toml absent at repo root (minor repo-hygiene) *)
let plug_missing_repo_config ev =
  if ev.ev_has_repo_config then []
  else
    [ { rule = "missing_repo_config"; layer = Git; severity = Minor;
        quest = ""; node = ""; cycle = 0;
        observed = "backpack.toml absent";
        threshold = "backpack.toml present at repo root";
        evidence_ref = "repo:" ^ Layout.manifest_file;
        summary = "backpack.toml missing at repo root; run bp3 init-repo" } ]

(* 2. cycle_outlier: max_cycle > 2 or any grade.wall_s > ev.ev_grade_wall_s (default 300s) *)
let plug_cycle_outlier ev =
  let limit = ev.ev_grade_wall_s in
  List.concat_map (fun qe ->
      List.filter_map (fun ne ->
          let non_refused = List.filter (fun e -> not e.le_refused) ne.ne_entries in
          let max_cycle = List.fold_left (fun acc e ->
              if e.le_edge = "handoff" || e.le_edge = "grade" || e.le_edge = "land" then
                max acc e.le_cycle
              else acc) 0 non_refused in
          let slow_grade = List.fold_left (fun acc (s : Metrics.sample) ->
              if s.metric = "grade.wall_s" then
                match acc with
                | None -> Some (s.cycle, s.value)
                | Some (_, best) -> if s.value > best then Some (s.cycle, s.value) else acc
              else acc) None ne.ne_samples in
          let slow_over = match slow_grade with Some (c, v) when v > limit -> Some (c, v) | _ -> None in
          if max_cycle > 2 then
            let extra = match slow_over with
              | Some (_, v) -> Printf.sprintf " (max grade wall %.0fs)" v
              | None -> "" in
            Some { rule = "cycle_outlier"; layer = Git; severity = Major;
                   quest = qe.qe_quest; node = ne.ne_node; cycle = max_cycle;
                   observed = Printf.sprintf "%d cycles" max_cycle;
                   threshold = "> 2 cycles";
                   evidence_ref = Printf.sprintf "ledger:%s:c%d" ne.ne_node max_cycle;
                   summary = Printf.sprintf "node took %d cycles%s" max_cycle extra }
          else match slow_over with
            | Some (c, v) ->
                Some { rule = "cycle_outlier"; layer = Git; severity = Major;
                       quest = qe.qe_quest; node = ne.ne_node; cycle = c;
                       observed = Printf.sprintf "%.0fs grade wall" v;
                       threshold = Printf.sprintf "> %.0fs grade wall" limit;
                       evidence_ref = Printf.sprintf "metrics:%s:c%d" ne.ne_node c;
                       summary = Printf.sprintf "grade cycle %d took %.0fs (> %.0fs)" c v limit }
            | None -> None) qe.qe_nodes) ev.ev_quests

(* 3. minor_only_bounce: needs_fix with [minor] and neither [critical] nor [major] *)
let plug_minor_only_bounce ev =
  List.concat_map (fun qe ->
      List.concat_map (fun ne ->
          List.filter_map (fun (c, e) ->
              if e.le_verdict = "needs_fix"
                 && contains_ci e.le_reason "[minor]"
                 && not (contains_ci e.le_reason "[critical]")
                 && not (contains_ci e.le_reason "[major]") then
                Some { rule = "minor_only_bounce"; layer = Git; severity = Minor;
                       quest = qe.qe_quest; node = ne.ne_node; cycle = c;
                       observed = "needs_fix ([minor] only)";
                       threshold = "no [critical]/[major]";
                       evidence_ref = Printf.sprintf "ledger:%s:c%d" ne.ne_node c;
                       summary = Printf.sprintf "cycle %d bounced on [minor]-only finding(s)" c }
              else None) (grade_entries_with_cycle ne.ne_entries)) qe.qe_nodes) ev.ev_quests

(* 4. vacuous_test_bounce: needs_fix mentioning vacuous / mutant / can't-fail tests *)
let vacuous_terms = [ "can't fail"; "cannot fail"; "stays green"; "mutant"; "vacuous" ]

let plug_vacuous_test_bounce ev =
  List.concat_map (fun qe ->
      List.concat_map (fun ne ->
          List.filter_map (fun (c, e) ->
              if e.le_verdict = "needs_fix" then
                match List.find_opt (contains_ci e.le_reason) vacuous_terms with
                | Some term ->
                    Some { rule = "vacuous_test_bounce"; layer = Git; severity = Major;
                           quest = qe.qe_quest; node = ne.ne_node; cycle = c;
                           observed = Printf.sprintf "matched %S" term;
                           threshold = "vacuous/mutant test bounce";
                           evidence_ref = Printf.sprintf "ledger:%s:c%d" ne.ne_node c;
                           summary = Printf.sprintf "cycle %d bounced for weak/vacuous test (%s)" c term }
                | None -> None
              else None) (grade_entries_with_cycle ne.ne_entries)) qe.qe_nodes) ev.ev_quests

(* 5. grade_inversion: sum(grade.wall_s) > 180s && > 1.5x sum(author.wall_s),
      or sum(grade.tokens_out) > 25k && > sum(author.tokens_out) when both > 0 *)
let plug_grade_inversion ev =
  List.concat_map (fun qe ->
      List.filter_map (fun ne ->
          let gw = Metrics.sum_metric ne.ne_samples "grade.wall_s" in
          let aw = Metrics.sum_metric ne.ne_samples "author.wall_s" in
          let go = Metrics.sum_metric ne.ne_samples "grade.tokens_out" in
          let ao = Metrics.sum_metric ne.ne_samples "author.tokens_out" in
          let wall_inv = gw > 180. && aw > 0. && gw > 1.5 *. aw in
          let tok_inv = go > 25_000. && ao > 0. && go > ao in
          if wall_inv then
            let ratio = gw /. aw in
            Some { rule = "grade_inversion"; layer = Git; severity = Major;
                   quest = qe.qe_quest; node = ne.ne_node; cycle = 0;
                   observed = Printf.sprintf "grade %.0fs vs author %.0fs (%.2fx)" gw aw ratio;
                   threshold = "> 180s & > 1.5x author";
                   evidence_ref = Printf.sprintf "metrics:%s" ne.ne_node;
                   summary = Printf.sprintf "grading wall (%.0fs) exceeded 1.5x author wall (%.0fs)" gw aw }
          else if tok_inv then
            Some { rule = "grade_inversion"; layer = Git; severity = Major;
                   quest = qe.qe_quest; node = ne.ne_node; cycle = 0;
                   observed = Printf.sprintf "grade %.0f vs author %.0f tok_out" go ao;
                   threshold = "> 25k & grade.tokens_out > author.tokens_out";
                   evidence_ref = Printf.sprintf "metrics:%s" ne.ne_node;
                   summary = Printf.sprintf "grader output tokens (%.0f) exceeded author output tokens (%.0f)" go ao }
          else None) qe.qe_nodes) ev.ev_quests

(* 6. coverage_gap: grade/handoff edges > 0 with 0 samples; skips legacy pre-metrics quests *)
let metrics_era_cutoff = "2026-11-21T00:00:00Z"

let is_legacy_pre_metrics qe =
  let any_samples = List.exists (fun ne -> ne.ne_samples <> []) qe.qe_nodes in
  if any_samples then false
  else
    let latest_ts = List.fold_left (fun acc ne ->
        List.fold_left (fun a e -> if e.le_ts > a then e.le_ts else a) acc ne.ne_entries) "" qe.qe_nodes in
    latest_ts <> "" && latest_ts < metrics_era_cutoff

let plug_coverage_gap ev =
  List.concat_map (fun qe ->
      if is_legacy_pre_metrics qe then []
      else
        List.filter_map (fun ne ->
            let non_refused = List.filter (fun e -> not e.le_refused) ne.ne_entries in
            let n_grades = List.length (List.filter (fun e -> e.le_edge = "grade") non_refused) in
            let n_handoffs = List.length (List.filter (fun e -> e.le_edge = "handoff") non_refused) in
            let has_grade_sample = List.exists (fun (s : Metrics.sample) ->
                String.starts_with ~prefix:"grade." s.metric) ne.ne_samples in
            let has_author_sample = List.exists (fun (s : Metrics.sample) ->
                String.starts_with ~prefix:"author." s.metric) ne.ne_samples in
            let miss_g = n_grades > 0 && not has_grade_sample in
            let miss_a = n_handoffs > 0 && not has_author_sample in
            if miss_g || miss_a then
              let parts =
                (if miss_g then [ Printf.sprintf "0/%d grades" n_grades ] else [])
                @ (if miss_a then [ Printf.sprintf "0/%d handoffs" n_handoffs ] else []) in
              let obs = String.concat ", " parts ^ " measured" in
              Some { rule = "coverage_gap"; layer = Git; severity = Minor;
                     quest = qe.qe_quest; node = ne.ne_node; cycle = 0;
                     observed = obs;
                     threshold = "> 0 samples per grade/handoff";
                     evidence_ref = Printf.sprintf "metrics:%s" ne.ne_node;
                     summary = Printf.sprintf "metrics missing for node (%s)" obs }
            else None) qe.qe_nodes) ev.ev_quests

(* 7. desk_leak: unreleased grade-* desk for landed/deleted node, or >=3 identical E_* refusals *)
let plug_desk_leak ev =
  List.concat_map (fun qe ->
      let state_of = Hashtbl.create 8 in
      List.iter (fun ne -> Hashtbl.replace state_of ne.ne_node ne.ne_state) qe.qe_nodes;
      let all_terminal = qe.qe_nodes <> [] && List.for_all (fun ne ->
          ne.ne_state = "landed" || ne.ne_state = "deleted") qe.qe_nodes in
      let desk_findings = List.filter_map (fun d ->
          if d.di_missing then None
          else if String.starts_with ~prefix:"grade-" d.di_run_id then
            let node_done = match Hashtbl.find_opt state_of d.di_node with
              | Some ("landed" | "deleted") -> true
              | _ -> all_terminal in
            if node_done then
              Some { rule = "desk_leak"; layer = Git; severity = Minor;
                     quest = qe.qe_quest; node = d.di_node; cycle = 0;
                     observed = d.di_run_id;
                     threshold = "0 unreleased grade desks";
                     evidence_ref = "desk:" ^ d.di_path;
                     summary = Printf.sprintf "grade desk %s still open after node landed" d.di_run_id }
            else None
          else None) qe.qe_open_desks in
      let refusal_findings = List.concat_map (fun ne ->
          let counts = Hashtbl.create 4 in
          List.iter (fun e ->
              if e.le_refused && e.le_error_code <> "" then
                let prev = Option.value (Hashtbl.find_opt counts e.le_error_code) ~default:0 in
                Hashtbl.replace counts e.le_error_code (prev + 1)) ne.ne_entries;
          Hashtbl.fold (fun code n acc ->
              if n >= 3 then
                { rule = "desk_leak"; layer = Git; severity = Minor;
                  quest = qe.qe_quest; node = ne.ne_node; cycle = 0;
                  observed = Printf.sprintf "%dx %s" n code;
                  threshold = ">= 3 identical E_* refusals";
                  evidence_ref = Printf.sprintf "ledger:%s:%s" ne.ne_node code;
                  summary = Printf.sprintf "repeated %s refusal (%dx) in ledger" code n } :: acc
              else acc) counts []) qe.qe_nodes in
      desk_findings @ refusal_findings) ev.ev_quests

(* 8. post_land_bugfix: > 0 non-status commits after final node_fin commit *)
let plug_post_land_bugfix ev =
  List.filter_map (fun qe ->
      match qe.qe_post_land_commits with
      | [] -> None
      | first :: _ as cs ->
          let n = List.length cs in
          let sha = short_sha first.plc_sha in
          Some { rule = "post_land_bugfix"; layer = Git; severity = Major;
                 quest = qe.qe_quest; node = ""; cycle = 0;
                 observed = Printf.sprintf "%d commits" n;
                 threshold = "> 0 post-land commits";
                 evidence_ref = "git:" ^ sha;
                 summary = Printf.sprintf "%d non-status fix commit(s) after final node_fin (e.g. %s: %s)"
                             n sha first.plc_subject }) ev.ev_quests

(* Layer-1 side of human_steer: explicit block edges / blocked escalations *)
let plug_human_steer_block ev =
  List.concat_map (fun qe ->
      List.concat_map (fun ne ->
          List.filter_map (fun e ->
              if not e.le_refused && (e.le_edge = "block" || e.le_to = "blocked") then
                Some { rule = "human_steer"; layer = Git; severity = Major;
                       quest = qe.qe_quest; node = ne.ne_node; cycle = e.le_cycle;
                       observed = (if e.le_edge = "block" then "block edge" else "escalated to blocked");
                       threshold = "0 human escalations";
                       evidence_ref = Printf.sprintf "ledger:%s:c%d" ne.ne_node e.le_cycle;
                       summary = Printf.sprintf "node blocked on cycle %d (%s)" e.le_cycle
                                   (if e.le_reason = "" then "human decision owed" else e.le_reason) }
              else None) ne.ne_entries) qe.qe_nodes) ev.ev_quests

(* ---------- Layer 2 plugs (session-trace) ---------- *)

(* 9. tool_retry_loop: >= 3 consecutive failing tool_events or >= 3 identical failing cmd_head *)
let plug_tool_retry_loop ev =
  List.concat_map (fun qe ->
      List.filter_map (fun (tr : Tx.joined_trace) ->
          let best_streak = ref (0, 0) in
          let cur_streak = ref (0, 0) in
          let by_cmd = Hashtbl.create 8 in
          List.iter (fun (e : Tx.tool_event) ->
              if e.te_error then begin
                let (cnt, st) = !cur_streak in
                let next = if cnt = 0 then (1, e.te_step) else (cnt + 1, st) in
                cur_streak := next;
                if fst next > fst !best_streak then best_streak := next;
                if e.te_cmd_head <> "" then begin
                  let k = (e.te_name, e.te_cmd_head) in
                  match Hashtbl.find_opt by_cmd k with
                  | None -> Hashtbl.replace by_cmd k (1, e.te_step)
                  | Some (c, fs) -> Hashtbl.replace by_cmd k (c + 1, fs)
                end
              end else
                cur_streak := (0, 0)) tr.jt_events;
          let best_cmd = Hashtbl.fold (fun (_, cmd) (c, fs) acc ->
              match acc with
              | None -> Some (c, fs, cmd)
              | Some (bc, _, _) -> if c > bc then Some (c, fs, cmd) else acc) by_cmd None in
          let streak_n, streak_step = !best_streak in
          let cmd_hit = match best_cmd with Some (c, fs, cmd) when c >= 3 -> Some (c, fs, cmd) | _ -> None in
          if streak_n >= 3 then
            Some { rule = "tool_retry_loop"; layer = Session; severity = Major;
                   quest = qe.qe_quest; node = tr.jt_node; cycle = tr.jt_cycle;
                   observed = Printf.sprintf "%d consecutive errors" streak_n;
                   threshold = ">= 3 failing retries";
                   evidence_ref = Printf.sprintf "tx:%s#step:%d" tr.jt_path streak_step;
                   summary = Printf.sprintf "%s hit %d consecutive failing tool calls" tr.jt_role streak_n }
          else match cmd_hit with
            | Some (c, fs, cmd) ->
                Some { rule = "tool_retry_loop"; layer = Session; severity = Major;
                       quest = qe.qe_quest; node = tr.jt_node; cycle = tr.jt_cycle;
                       observed = Printf.sprintf "%dx failing %S" c cmd;
                       threshold = ">= 3 identical failing cmd";
                       evidence_ref = Printf.sprintf "tx:%s#step:%d" tr.jt_path fs;
                       summary = Printf.sprintf "%s repeated failing command %dx (%s)" tr.jt_role c cmd }
            | None -> None) qe.qe_traces) ev.ev_quests

(* 10. full_gate_in_author: author window ran `make check-full` > 1x before handoff *)
let plug_full_gate_in_author ev =
  List.concat_map (fun qe ->
      List.filter_map (fun (tr : Tx.joined_trace) ->
          if tr.jt_role <> "author" then None
          else
            let hits = List.filter (fun (e : Tx.tool_event) ->
                Tx.contains e.te_cmd_head "make check-full") tr.jt_events in
            let n = List.length hits in
            if n > 1 then
              let second_step = (List.nth hits 1).te_step in
              Some { rule = "full_gate_in_author"; layer = Session; severity = Minor;
                     quest = qe.qe_quest; node = tr.jt_node; cycle = tr.jt_cycle;
                     observed = Printf.sprintf "%dx make check-full" n;
                     threshold = "> 1x in author window";
                     evidence_ref = Printf.sprintf "tx:%s#step:%d" tr.jt_path second_step;
                     summary = Printf.sprintf "author ran make check-full %dx in one cycle; use make check for inner loop" n }
            else None) qe.qe_traces) ev.ev_quests

(* 11. context_bloat: harness-aware (>150k claude/pi, >400k agy) or turns > 30.
       Deduplicated per (quest, jt_run) keeping peak context/turns so one
       multi-node inline author session emits one peak finding, not one per cycle. *)
let plug_context_bloat ev =
  List.concat_map (fun qe ->
      let best_by_run = Hashtbl.create 8 in
      List.iter (fun (tr : Tx.joined_trace) ->
          let is_agy = String.starts_with ~prefix:"agy:" tr.jt_run in
          let ctx_limit = if is_agy then 400_000 else 150_000 in
          let turn_limit = 30 in
          let last_step = match List.rev tr.jt_events with
            | e :: _ -> e.te_step
            | [] -> tr.jt_turns in
          let cand =
            if tr.jt_context_end > ctx_limit then
              Some ((tr.jt_context_end, tr.jt_turns),
                    { rule = "context_bloat"; layer = Session; severity = Minor;
                      quest = qe.qe_quest; node = tr.jt_node; cycle = tr.jt_cycle;
                      observed = Printf.sprintf "%dk tok (%d turns)" (tr.jt_context_end / 1000) tr.jt_turns;
                      threshold = Printf.sprintf "> %dk tok (%s)" (ctx_limit / 1000) (if is_agy then "agy" else "claude/pi");
                      evidence_ref = Printf.sprintf "tx:%s#step:%d" tr.jt_path last_step;
                      summary = Printf.sprintf "%s context reached %dk tokens (> %dk %s limit)"
                                  tr.jt_role (tr.jt_context_end / 1000) (ctx_limit / 1000) (if is_agy then "agy" else "claude/pi") })
            else if tr.jt_turns > turn_limit then
              Some ((tr.jt_context_end, tr.jt_turns),
                    { rule = "context_bloat"; layer = Session; severity = Minor;
                      quest = qe.qe_quest; node = tr.jt_node; cycle = tr.jt_cycle;
                      observed = Printf.sprintf "%d turns (%dk tok)" tr.jt_turns (tr.jt_context_end / 1000);
                      threshold = "> 30 turns";
                      evidence_ref = Printf.sprintf "tx:%s#step:%d" tr.jt_path last_step;
                      summary = Printf.sprintf "%s session took %d turns (> 30)" tr.jt_role tr.jt_turns })
            else None in
          match cand with
          | None -> ()
          | Some (score, finding) ->
              let key = if tr.jt_run <> "" then tr.jt_run else tr.jt_node ^ "|" ^ string_of_int tr.jt_cycle in
              (match Hashtbl.find_opt best_by_run key with
               | Some (prev_score, _) when prev_score >= score -> ()
               | _ -> Hashtbl.replace best_by_run key (score, finding))) qe.qe_traces;
      Hashtbl.fold (fun _ (_, f) acc -> f :: acc) best_by_run []) ev.ev_quests

(* 12. human_steer (Layer 2 session side): > 0 mid-node USER_INPUT inside author window *)
let plug_human_steer_session ev =
  List.concat_map (fun qe ->
      List.filter_map (fun (tr : Tx.joined_trace) ->
          if tr.jt_role <> "author" then None
          else match tr.jt_user_steps with
            | [] -> None
            | (first_step, _) :: _ as steps ->
                let n = List.length steps in
                Some { rule = "human_steer"; layer = Session; severity = Major;
                       quest = qe.qe_quest; node = tr.jt_node; cycle = tr.jt_cycle;
                       observed = Printf.sprintf "%d mid-node user inputs" n;
                       threshold = "> 0 mid-node steers";
                       evidence_ref = Printf.sprintf "tx:%s#step:%d" tr.jt_path first_step;
                       summary = Printf.sprintf "human steered author %dx mid-node (first at step %d)" n first_step })
        qe.qe_traces) ev.ev_quests

(* ---------- pipeline & sorting ---------- *)

let layer1_plugs = [
  plug_multi_active_quest;
  plug_missing_repo_config;
  plug_cycle_outlier;
  plug_minor_only_bounce;
  plug_vacuous_test_bounce;
  plug_grade_inversion;
  plug_coverage_gap;
  plug_desk_leak;
  plug_post_land_bugfix;
  plug_human_steer_block;
]

let layer2_plugs = [
  plug_tool_retry_loop;
  plug_full_gate_in_author;
  plug_context_bloat;
  plug_human_steer_session;
]

let sev_rank = function Major -> 0 | Minor -> 1
let layer_rank = function Git -> 0 | Session -> 1

let compare_finding a b =
  let c = compare (sev_rank a.severity) (sev_rank b.severity) in
  if c <> 0 then c else
  let c = compare (layer_rank a.layer) (layer_rank b.layer) in
  if c <> 0 then c else
  let c = String.compare a.quest b.quest in
  if c <> 0 then c else
  let c = String.compare a.node b.node in
  if c <> 0 then c else
  let c = compare a.cycle b.cycle in
  if c <> 0 then c else
  let c = String.compare a.rule b.rule in
  if c <> 0 then c else
  String.compare a.evidence_ref b.evidence_ref

let sort_findings fs = List.sort compare_finding fs

let run ev =
  let l1 = List.concat_map (fun p -> p ev) layer1_plugs in
  let has_traces = List.exists (fun q -> q.qe_traces <> []) ev.ev_quests in
  let l2 = if has_traces then List.concat_map (fun p -> p ev) layer2_plugs else [] in
  sort_findings (l1 @ l2)

(* ---------- serialization (JSON + table) ---------- *)

let layer_str = function Git -> "git" | Session -> "session"
let severity_str = function Major -> "major" | Minor -> "minor"

let sessions_scanned ev =
  let seen = Hashtbl.create 16 in
  List.iter (fun qe ->
      List.iter (fun (tr : Tx.joined_trace) ->
          Hashtbl.replace seen (tr.jt_run, tr.jt_path) ()) qe.qe_traces) ev.ev_quests;
  Hashtbl.length seen

let finding_to_json f =
  `Assoc [
    ("rule", `String f.rule);
    ("layer", `String (layer_str f.layer));
    ("severity", `String (severity_str f.severity));
    ("quest", `String f.quest);
    ("node", `String f.node);
    ("cycle", `Int f.cycle);
    ("observed", `String f.observed);
    ("threshold", `String f.threshold);
    ("evidence_ref", `String f.evidence_ref);
    ("summary", `String f.summary);
  ]

let counts_json findings =
  let by_rule = Hashtbl.create 16 in
  let git_n = ref 0 and ses_n = ref 0 in
  List.iter (fun f ->
      let prev = Option.value (Hashtbl.find_opt by_rule f.rule) ~default:0 in
      Hashtbl.replace by_rule f.rule (prev + 1);
      match f.layer with Git -> incr git_n | Session -> incr ses_n) findings;
  let rule_pairs =
    Hashtbl.fold (fun k v acc -> (k, `Int v) :: acc) by_rule []
    |> List.sort (fun (a, _) (b, _) -> String.compare a b) in
  `Assoc [
    ("by_rule", `Assoc rule_pairs);
    ("by_layer", `Assoc [ ("git", `Int !git_n); ("session", `Int !ses_n) ]);
    ("total", `Int (List.length findings));
  ]

let to_json ev findings =
  let warnings_field =
    if ev.ev_has_repo_config then []
    else [ ("warnings", `List [ Backpack.warning_no_repo_config () ]) ] in
  `Assoc ([
    ("ok", `Bool true);
    ("scope", `String ev.ev_scope);
    ("quests", `List (List.map (fun q -> `String q.qe_quest) ev.ev_quests));
    ("sessions_scanned", `Int (sessions_scanned ev));
    ("findings", `List (List.map finding_to_json findings));
    ("counts", counts_json findings);
  ] @ warnings_field)

let pad w s =
  let n = String.length s in
  if n >= w then s else s ^ String.make (w - n) ' '

let to_table ev findings =
  let nq = List.length ev.ev_quests in
  let ns = sessions_scanned ev in
  if findings = [] then
    Printf.sprintf "warden (%s): 0 findings across %d quest(s), %d session(s) scanned\n" ev.ev_scope nq ns
  else
    let rows = List.map (fun f ->
        [| f.rule; layer_str f.layer; severity_str f.severity;
           (if f.node <> "" then f.node else if f.quest <> "" then f.quest else "(repo)");
           (if f.cycle > 0 then Printf.sprintf "c%d" f.cycle else "-");
           f.observed; f.summary |]) findings in
    let hdr = [| "RULE"; "LAYER"; "SEV"; "NODE"; "CYCLE"; "OBSERVED"; "SUMMARY" |] in
    let widths = Array.init 7 (fun i ->
        List.fold_left (fun acc r -> max acc (String.length r.(i))) (String.length hdr.(i)) rows) in
    let fmt_row r =
      Printf.sprintf "%s  %s  %s  %s  %s  %s  %s"
        (pad widths.(0) r.(0)) (pad widths.(1) r.(1)) (pad widths.(2) r.(2))
        (pad widths.(3) r.(3)) (pad widths.(4) r.(4)) (pad widths.(5) r.(5)) r.(6) in
    String.concat "\n" (fmt_row hdr :: List.map fmt_row rows) ^ "\n"
