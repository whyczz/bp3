(* Metrics sink and scrape (metric-collectors sink.1, scrape.1): the
   only writer of metrics.jsonl, a GENERATED file on each node's state
   branch beside its ledger. One append is one commit per node
   (QUEST.md R5). Scrape joins ledger grade spans to Claude Code
   subagent transcripts; the pure parts live in Metrics and Claude_tx. *)
open Gitx

let sink_path q node = Store.node_dir q node ^ "/" ^ Layout.metrics_file

let node_text q node =
  match Store.ledger_read (Store.node_branch q node) (Store.node_ledger_path q node)
          (Store.legacy_node_ledger_paths q node) with
  | Some (_, text, _) -> text
  | None -> ""

let sink_text tip q node = match git_show tip (sink_path q node) with Some t -> t | None -> ""

let read_samples q node =
  match ref_tip (Store.node_branch q node) with
  | None -> []
  | Some tip -> Metrics.of_text (sink_text tip q node)

(* Validate the whole batch first: one bad sample refuses all of it. *)
let append q node batch =
  List.iter (fun s -> match Metrics.validate s with
      | Ok () -> ()
      | Error (code, detail) ->
          err code (`Assoc [ ("node", json_str node); ("detail", json_str detail) ])
            ("Refused sample: " ^ detail) 1) batch;
  let branch = Store.node_branch q node in
  match ref_tip branch with
  | None -> not_found "node" node
  | Some tip ->
      let old = sink_text tip q node in
      let fresh, skipped = Metrics.dedupe ~existing:(Metrics.of_text old) batch in
      if fresh <> [] then
        ignore (commit_files ~branch ~base_tip:tip ~expect_tip:tip
                  ~files:[ (sink_path q node, old ^ Metrics.to_text fresh) ]
                  ~msg:("bp3: metrics " ^ node));
      (List.length fresh, skipped)

(* ---------- where Claude Code keeps transcripts ---------- *)

(* Claude Code names a project dir after the session's cwd, with "/"
   and "." as "-". Sessions in this repo's desks land under the
   desk's own dir, so both are scanned; nothing else is. The cwd may
   be the logical or the real path (/var vs /private/var), so both
   spellings of the repo root match. *)
let slug_of_path p = String.map (function '/' | '.' -> '-' | c -> c) p

let main_root () =
  match git_common_dir () with
  | Some d when Filename.basename d = ".git" -> Filename.dirname d
  | _ -> root

let default_dirs () =
  let base = Filename.concat (match Sys.getenv_opt "HOME" with Some h -> h | None -> "") ".claude/projects" in
  let m = main_root () in
  let mains = List.sort_uniq compare
      (List.map slug_of_path [ m; (try Unix.realpath m with Unix.Unix_error _ -> m) ]) in
  let desk_tail = "-" ^ slug_of_path Layout.desks_root ^ "-" in
  let ours d = List.exists (fun main -> d = main || String.starts_with ~prefix:(main ^ desk_tail) d) mains in
  if not (Sys.file_exists base && Sys.is_directory base) then []
  else
    Sys.readdir base |> Array.to_list |> List.sort compare |> List.filter ours
    |> List.map (Filename.concat base)

(* pi names a session dir after its cwd too, by its own rule (pi docs
   session-format.md): drop the leading separator, turn / \ : into -,
   and wrap in --...--. Dots stay, so a desk is
   --<repo>-.bp3-worktrees-<slug>--. pi writes the files flat in that
   dir. Logical and real paths both match, as for Claude. *)
let pi_slug p =
  let p = if String.length p > 0 && (p.[0] = '/' || p.[0] = '\\') then String.sub p 1 (String.length p - 1) else p in
  "--" ^ String.map (function '/' | '\\' | ':' -> '-' | c -> c) p ^ "--"

let default_pi_dirs () =
  let base = Filename.concat (match Sys.getenv_opt "HOME" with Some h -> h | None -> "") ".pi/agent/sessions" in
  let m = main_root () in
  let roots = List.sort_uniq compare [ m; (try Unix.realpath m with Unix.Unix_error _ -> m) ] in
  let ours d = List.exists (fun r ->
      let main = pi_slug r in
      let desk = pi_slug (r ^ "/" ^ Layout.desks_root ^ "/") in   (* --<repo>-.bp3-worktrees---; less its -- *)
      let desk_prefix = String.sub desk 0 (String.length desk - 2) in
      d = main || (String.starts_with ~prefix:desk_prefix d && String.ends_with ~suffix:"--" d
                   && String.length d > String.length desk_prefix + 2)) roots in
  if not (Sys.file_exists base && Sys.is_directory base) then []
  else
    Sys.readdir base |> Array.to_list |> List.sort compare |> List.filter ours
    |> List.map (Filename.concat base)

let is_dir p = Sys.file_exists p && Sys.is_directory p
let read_file p = In_channel.with_open_bin p In_channel.input_all

let pi_files dir =
  if not (is_dir dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort compare
    |> List.filter (fun f -> Filename.check_suffix f ".jsonl")
    |> List.map (Filename.concat dir)

(* a pi session's run key: its header id, else the id in its file name
   (<ts>_<id>.jsonl) *)
let pi_run_of_path path (tx : Pi_tx.tx) =
  if tx.session <> "" then "pi:" ^ tx.session
  else
    let b = Filename.chop_suffix (Filename.basename path) ".jsonl" in
    "pi:" ^ (match String.index_opt b '_' with Some i -> String.sub b (i + 1) (String.length b - i - 1) | None -> b)

let subagent_files dir =
  if not (is_dir dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort compare
    |> List.concat_map (fun s ->
           let sub = Filename.concat (Filename.concat dir s) "subagents" in
           if not (is_dir sub) then []
           else
             Sys.readdir sub |> Array.to_list |> List.sort compare
             |> List.filter (fun f -> Filename.check_suffix f ".jsonl")
             |> List.map (Filename.concat sub))

(* run key from the path when the file does not name itself:
   <dir>/<session>/subagents/agent-<id>.jsonl *)
let agent_of_path path (tx : Claude_tx.tx) =
  if tx.agent <> "" then tx.agent
  else let b = Filename.chop_suffix (Filename.basename path) ".jsonl" in
    if String.starts_with ~prefix:"agent-" b then String.sub b 6 (String.length b - 6) else b

let run_of_path path (tx : Claude_tx.tx) =
  let session = if tx.session <> "" then tx.session
    else Filename.basename (Filename.dirname (Filename.dirname path)) in
  "claude:" ^ session ^ "/" ^ agent_of_path path tx

(* The harness report for one subagent file lives in the parent
   session file beside the session's folder. Its key is the agent id
   (<task-id>, whose last report covers a resumed agent's whole
   transcript), else the spawning call named in the .meta.json
   (<tool-use-id>, first stop only). Parents are big (tens of MB), so
   each is read once per scrape. *)
let meta_path path = Filename.chop_suffix path ".jsonl" ^ ".meta.json"
let parent_path path = Filename.dirname (Filename.dirname path) ^ ".jsonl"
let reports_cache : (string, (string * Claude_tx.report) list) Hashtbl.t = Hashtbl.create 4

let report_for path tx =
  let parent = parent_path path in
  let reports = match Hashtbl.find_opt reports_cache parent with
    | Some r -> r
    | None ->
        let r = try Claude_tx.reports_of_text (read_file parent) with Sys_error _ -> [] in
        Hashtbl.replace reports_cache parent r; r in
  match List.assoc_opt (agent_of_path path tx) reports with
  | Some r -> Some r
  | None ->
      (match (try Claude_tx.meta_tool_use_id (read_file (meta_path path)) with Sys_error _ -> None) with
       | Some id -> List.assoc_opt id reports
       | None -> None)

let grade_samples q node (sp : Metrics.grade_span) ~run ~at (c : Claude_tx.cost) =
  let mk m v = { Metrics.metric = "grade." ^ m; quest = q; node; cycle = sp.g_cycle;
                 run; model = c.model; value = v; at;
                 source = Metrics.grade_transcripts.c_name } in
  let i = float_of_int in
  [ mk "wall_s" c.wall_s; mk "tool_calls" (i c.tool_calls); mk "context_end" (i c.context_end);
    mk "tokens_in" (i c.tokens_in); mk "tokens_out" (i c.tokens_out);
    mk "tokens_cache_read" (i c.tokens_cache_read); mk "tokens_cache_write" (i c.tokens_cache_write) ]

(* A grade transcript from any harness the scrape reads (pi-metrics
   scrape.1): the join is the same for all, the check is the harness's. *)
type grader = Claude of string * Claude_tx.tx | Pi of string * Pi_tx.tx

let joins g ~node (sp : Metrics.grade_span) =
  let prompt, first_ts, last_ts = match g with
    | Claude (_, tx) -> (tx.first_prompt, tx.first_ts, tx.last_ts)
    | Pi (_, tx) -> (tx.first_prompt, tx.first_ts, tx.last_ts) in
  Claude_tx.prompt_names_grade prompt ~node ~commit:sp.g_commit
  && Claude_tx.span_in_window ~first_ts ~last_ts ~handed_at:sp.handed_at ~graded_at:sp.graded_at

(* One node: each grade span finds its transcript among every harness's,
   or says why not. A Claude transcript is checked against the harness
   report: agreeing is "checked", disagreeing is "mismatched" and writes
   nothing, and no report found is "unchecked" (written, flagged). A pi
   session has no report: one that agrees with itself is "self_checked"
   (written), one that doesn't is "mismatched". *)
let grade_pass q node edges graders =
  let spans = Metrics.grade_spans edges in
  List.fold_left (fun (batch, (t : Metrics.tally)) (sp : Metrics.grade_span) ->
      let t = { t with grades = t.grades + 1 } in
      match List.filter (fun g -> joins g ~node sp) (Lazy.force graders) with
      | [] -> (batch, { t with owner_graded = t.owner_graded + 1 })
      | [ Claude (path, tx) ] ->
          let c = Claude_tx.cost tx in
          let t = { t with skipped_lines = t.skipped_lines + tx.skipped_lines } in
          let samples () = grade_samples q node sp ~run:(run_of_path path tx) ~at:tx.last_ts c in
          (* the check reads the lines the report covers; the samples
             keep the whole in-window cost, follow-up turns included *)
          let covered r = Claude_tx.parse ?until:(Claude_tx.seconds r.Claude_tx.r_at) (read_file path) in
          (match report_for path tx with
           | Some r when not (Claude_tx.checks (covered r) r) -> (batch, { t with mismatched = t.mismatched + 1 })
           | Some _ -> (batch @ samples (), { t with checked = t.checked + 1 })
           | None -> (batch @ samples (), { t with unchecked = t.unchecked + 1 }))
      | [ Pi (path, tx) ] ->
          let t = { t with skipped_lines = t.skipped_lines + tx.skipped_lines } in
          if Pi_tx.self_checks tx then
            (batch @ grade_samples q node sp ~run:(pi_run_of_path path tx) ~at:tx.last_ts (Pi_tx.cost tx),
             { t with self_checked = t.self_checked + 1 })
          else (batch, { t with mismatched = t.mismatched + 1 })
      | _ -> (batch, { t with ambiguous = t.ambiguous + 1 })) ([], Metrics.zero) spans

(* ---------- author windows (scrape.2) ---------- *)

let main_files dir =
  if not (is_dir dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort compare
    |> List.filter (fun f -> Filename.check_suffix f ".jsonl")
    |> List.map (Filename.concat dir)

(* Every handoff of the quest, in time order, finds the one session
   that cast it; each session's windows are then assigned together so
   no message is counted twice. Returns per node (samples, tally). *)
let author_pass q all sessions =
  let secs ts = Option.value (Claude_tx.seconds ts) ~default:0. in
  let spans =
    List.sort_uniq compare (List.map fst all)
    |> List.concat_map (fun n -> List.map (fun s -> (n, s)) (Metrics.author_spans ~node:n all))
    |> List.stable_sort (fun (_, (a : Metrics.author_span)) (_, b) -> compare a.a_upto b.a_upto) in
  (* a window whose stamps do not parse has no session: missing, never
     a window that starts at the epoch *)
  let found = List.map (fun (n, (sp : Metrics.author_span)) ->
      match Claude_tx.seconds sp.a_from, Claude_tx.seconds sp.a_upto with
      | Some from, Some upto ->
          (n, sp, List.filter (fun (s : Claude_tx.session) ->
               Claude_tx.casts_handoff s ~quest:q ~node:n ~commit:sp.a_commit ~from ~upto) sessions)
      | _ -> (n, sp, [])) spans in
  let per_session = Hashtbl.create 4 in
  List.iter (fun (n, (sp : Metrics.author_span), ss) -> match ss with
      | [ (s : Claude_tx.session) ] ->
          let key = n ^ "|" ^ string_of_int sp.a_cycle ^ "|" ^ sp.a_upto in
          let prev = Option.value (Hashtbl.find_opt per_session s.s_id) ~default:(s, []) in
          Hashtbl.replace per_session s.s_id (s, snd prev @ [ (key, secs sp.a_from, secs sp.a_upto) ])
      | _ -> ()) found;
  let assigned = Hashtbl.create 16 in
  Hashtbl.iter (fun _ (s, windows) ->
      List.iter (fun (w : Claude_tx.window_spend) -> Hashtbl.replace assigned w.w_key (s, w))
        (Claude_tx.assign s windows)) per_session;
  let out = Hashtbl.create 8 in
  let add n (batch, (t : Metrics.tally)) =
    let (b0, t0) = Option.value (Hashtbl.find_opt out n) ~default:([], Metrics.zero) in
    Hashtbl.replace out n (b0 @ batch, { t0 with handoffs = t0.handoffs + t.handoffs; authored = t0.authored + t.authored;
                                                 author_missing = t0.author_missing + t.author_missing;
                                                 author_ambiguous = t0.author_ambiguous + t.author_ambiguous;
                                                 author_bad_usage = t0.author_bad_usage + t.author_bad_usage }) in
  List.iter (fun (n, (sp : Metrics.author_span), ss) ->
      let one = { Metrics.zero with handoffs = 1 } in
      match ss with
      | [] -> add n ([], { one with author_missing = 1 })
      | _ :: _ :: _ -> add n ([], { one with author_ambiguous = 1 })
      | [ _ ] ->
          let key = n ^ "|" ^ string_of_int sp.a_cycle ^ "|" ^ sp.a_upto in
          let ((s : Claude_tx.session), (w : Claude_tx.window_spend)) = Hashtbl.find assigned key in
          (* a usage-less line undercounts the window, like a mismatched
             grade: nothing written (usage.1); a window with no messages
             of its own measured nothing: missing, never zero *)
          if w.w_bad > 0 then add n ([], { one with author_bad_usage = 1 }) else
          if w.w_msgs = [] then add n ([], { one with author_missing = 1 }) else
          let c = Claude_tx.author_cost w.w_msgs w.w_tools in
          let mk m v = { Metrics.metric = "author." ^ m; quest = q; node = n; cycle = sp.a_cycle;
                         run = "claude:" ^ s.s_id; model = c.model; value = float_of_int v; at = sp.a_upto;
                         source = Metrics.author_window.c_name } in
          add n ([ mk "tool_calls" c.tool_calls; mk "tokens_in" c.tokens_in; mk "tokens_out" c.tokens_out;
                   mk "tokens_cache_read" c.tokens_cache_read; mk "tokens_cache_write" c.tokens_cache_write ],
                 { one with authored = 1 })) found;
  out

let scrape q ~dirs ~pi_dirs =
  let nodes = Store.list_nodes q in
  let edges = List.map (fun n -> (n, Metrics.edges_of_text (node_text q n))) nodes in
  let all = List.concat_map (fun (n, es) -> List.map (fun e -> (n, e)) es) edges in
  let txs = lazy ((List.concat_map subagent_files dirs
                   |> List.map (fun f -> Claude (f, Claude_tx.parse (read_file f))))
                  @ (List.concat_map pi_files pi_dirs
                     |> List.map (fun f -> Pi (f, Pi_tx.parse (read_file f))))) in
  let sessions = List.concat_map main_files dirs |> List.map (fun f -> Claude_tx.parse_session (read_file f)) in
  let authors = author_pass q all sessions in
  List.map (fun (node, es) ->
      let gb, gt = grade_pass q node es txs in
      let ab, (at : Metrics.tally) = Option.value (Hashtbl.find_opt authors node) ~default:([], Metrics.zero) in
      let batch = gb @ ab in
      let written, skipped = if batch = [] then (0, 0) else append q node batch in
      (node, { gt with written; skipped; handoffs = at.handoffs; authored = at.authored;
                       author_missing = at.author_missing; author_ambiguous = at.author_ambiguous;
                       author_bad_usage = at.author_bad_usage }))
    edges

(* ---------- views ---------- *)

let num v = if Float.is_integer v && Float.abs v < 1e15 then `Int (int_of_float v) else `Float v

(* nodes -> cycles -> grade|author|timing -> fields; grade and author
   carry their model and run, timing (derived from the ledger) none *)
let node_view samples =
  let cycles = List.sort_uniq compare (List.map (fun (s : Metrics.sample) -> s.cycle) samples) in
  `Assoc [ ("cycles", `Assoc (List.map (fun c ->
       let in_c = List.filter (fun (s : Metrics.sample) -> s.cycle = c) samples in
       let kinds = List.sort_uniq compare (List.map (fun (s : Metrics.sample) ->
           List.hd (String.split_on_char '.' s.metric)) in_c) in
       (string_of_int c, `Assoc (List.map (fun k ->
            let mine = List.filter (fun (s : Metrics.sample) ->
                String.starts_with ~prefix:(k ^ ".") s.metric) in_c in
            let field (s : Metrics.sample) =
              (String.sub s.metric (String.length k + 1) (String.length s.metric - String.length k - 1), num s.value) in
            let first = List.hd mine in
            if k = "cycle" then ("timing", `Assoc (List.map field mine))
            else (k, `Assoc (List.map field mine @ [ ("model", json_str first.model); ("run", json_str first.run) ])))
          kinds))) cycles)) ]

(* derive.1: per node, the stored samples plus the derived timing, and
   a roll-up; per quest, the roll-up of every node. Nothing derived is
   written: it is computed from samples and ledger at each read. *)
let view q =
  let nodes = List.map (fun n ->
      let edges = Metrics.edges_of_text (node_text q n) in
      (n, edges, read_samples q n, Metrics.derive_timing ~quest:q ~node:n edges)) (Store.list_nodes q) in
  let all_edges = List.concat_map (fun (_, es, _, _) -> es) nodes in
  let all_samples = List.concat_map (fun (_, _, ss, _) -> ss) nodes in
  `Assoc [ ("ok", `Bool true); ("quest", json_str q);
           ("rollup", Metrics.rollup_json (Metrics.rollup ~edges:all_edges all_samples));
           ("nodes", `Assoc (List.map (fun (n, edges, samples, derived) ->
                (n, match node_view (samples @ derived) with
                 | `Assoc fs -> `Assoc (fs @ [ ("rollup", Metrics.rollup_json (Metrics.rollup ~edges samples)) ])
                 | v -> v)) nodes)) ]

let scrape_view q ~dirs ~pi_dirs =
  let res = scrape q ~dirs ~pi_dirs in
  (* a number bp3 could not check was not written: a finding, exit 1 *)
  let unwritten = List.exists (fun (_, (t : Metrics.tally)) -> t.mismatched > 0 || t.author_bad_usage > 0) res in
  (`Assoc [ ("ok", `Bool (not unwritten)); ("quest", json_str q);
            ("dirs", `List (List.map json_str dirs)); ("pi_dirs", `List (List.map json_str pi_dirs));
            ("nodes", `Assoc (List.map (fun (n, t) -> (n, Metrics.tally_json t)) res)) ],
   if unwritten then 1 else 0)
