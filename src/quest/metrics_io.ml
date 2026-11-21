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

let is_dir p = Sys.file_exists p && Sys.is_directory p
let read_file p = In_channel.with_open_bin p In_channel.input_all

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

let grade_samples q node (sp : Metrics.grade_span) path (tx : Claude_tx.tx) (c : Claude_tx.cost) =
  let mk m v = { Metrics.metric = "grade." ^ m; quest = q; node; cycle = sp.g_cycle;
                 run = run_of_path path tx; model = c.model; value = v; at = tx.last_ts;
                 source = Metrics.grade_transcripts.c_name } in
  let i = float_of_int in
  [ mk "wall_s" c.wall_s; mk "tool_calls" (i c.tool_calls); mk "context_end" (i c.context_end);
    mk "tokens_in" (i c.tokens_in); mk "tokens_out" (i c.tokens_out);
    mk "tokens_cache_read" (i c.tokens_cache_read); mk "tokens_cache_write" (i c.tokens_cache_write) ]

(* One node: each grade span finds its transcript, or says why not.
   A found transcript is checked against the harness report: agreeing
   is "checked", disagreeing is "mismatched" and writes nothing, and
   no report found is "unchecked" (written, flagged). *)
let scrape_node q node txs =
  let spans = Metrics.grade_spans (Metrics.edges_of_text (node_text q node)) in
  let batch, t = List.fold_left (fun (batch, (t : Metrics.tally)) (sp : Metrics.grade_span) ->
      let t = { t with grades = t.grades + 1 } in
      let hits = List.filter (fun (_, tx) ->
          Claude_tx.names_grade tx ~node ~commit:sp.g_commit
          && Claude_tx.in_window tx ~handed_at:sp.handed_at ~graded_at:sp.graded_at) (Lazy.force txs) in
      match hits with
      | [] -> (batch, { t with owner_graded = t.owner_graded + 1 })
      | [ (path, tx) ] ->
          let c = Claude_tx.cost tx in
          let t = { t with skipped_lines = t.skipped_lines + tx.skipped_lines } in
          (* the check reads the lines the report covers; the samples
             keep the whole in-window cost, follow-up turns included *)
          let covered r = Claude_tx.parse ?until:(Claude_tx.seconds r.Claude_tx.r_at) (read_file path) in
          (match report_for path tx with
           | Some r when not (Claude_tx.checks (covered r) r) -> (batch, { t with mismatched = t.mismatched + 1 })
           | Some _ -> (batch @ grade_samples q node sp path tx c, { t with checked = t.checked + 1 })
           | None -> (batch @ grade_samples q node sp path tx c, { t with unchecked = t.unchecked + 1 }))
      | _ -> (batch, { t with ambiguous = t.ambiguous + 1 })) ([], Metrics.zero) spans in
  let written, skipped = if batch = [] then (0, 0) else append q node batch in
  { t with written; skipped }

let scrape q ~dirs =
  let txs = lazy (List.concat_map subagent_files dirs
                  |> List.map (fun f -> (f, Claude_tx.parse (read_file f)))) in
  List.map (fun node -> (node, scrape_node q node txs)) (Store.list_nodes q)

(* ---------- views ---------- *)

let num v = if Float.is_integer v && Float.abs v < 1e15 then `Int (int_of_float v) else `Float v

(* nodes -> cycles -> grade|author -> fields, plus model and run *)
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
            (k, `Assoc (List.map field mine @ [ ("model", json_str first.model); ("run", json_str first.run) ])))
          kinds))) cycles)) ]

let view q =
  `Assoc [ ("ok", `Bool true); ("quest", json_str q);
           ("nodes", `Assoc (List.map (fun n -> (n, node_view (read_samples q n))) (Store.list_nodes q))) ]

let scrape_view q ~dirs =
  let res = scrape q ~dirs in
  let mismatched = List.exists (fun (_, (t : Metrics.tally)) -> t.mismatched > 0) res in
  (`Assoc [ ("ok", `Bool (not mismatched)); ("quest", json_str q);
            ("dirs", `List (List.map json_str dirs));
            ("nodes", `Assoc (List.map (fun (n, t) -> (n, Metrics.tally_json t)) res)) ],
   if mismatched then 1 else 0)
