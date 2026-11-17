(* bp3 g — graph/node FSM CLI. Only writer of graph state.
   Doors and the FSM judge live here; plumbing in Gitx,
   truth in Store, presentation in Render. *)
open Gitx
open Store
open Render

(* ---------- argv parsing ---------- *)
type flags = {
  reason : string option; commit : string option; verdict : string option;
  target : string option; typ : string option; depends_on : string option;
  fmt : string;
}

let parse_flags args =
  let rec loop acc = function
    | [] -> acc
    | "--reason" :: v :: rest -> add acc "reason" v rest
    | "--commit" :: v :: rest -> add acc "commit" v rest
    | "--verdict" :: v :: rest -> add acc "verdict" v rest
    | "--target" :: v :: rest -> add acc "target" v rest
    | "--type" :: v :: rest -> add acc "type" v rest
    | "--depends-on" :: v :: rest -> add acc "depends-on" v rest
    | "--format" :: v :: rest -> add acc "format" v rest
    | "--reason" :: [] | "--commit" :: [] | "--verdict" :: [] | "--target" :: []
    | "--type" :: [] | "--depends-on" :: [] | "--format" :: [] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray)
  and add acc name v rest =
    let has = match name with
      | "reason" -> acc.reason <> None | "commit" -> acc.commit <> None
      | "verdict" -> acc.verdict <> None | "target" -> acc.target <> None
      | "type" -> acc.typ <> None | "depends-on" -> acc.depends_on <> None
      | "format" -> acc.fmt <> "json" || List.mem "--format" [] | _ -> false in
    (* duplicate detection for format needs explicit tracking; handled below *)
    ignore has;
    match name with
    | "reason" -> if acc.reason <> None then usage "duplicate flag --reason" else loop { acc with reason = Some v } rest
    | "commit" -> if acc.commit <> None then usage "duplicate flag --commit" else loop { acc with commit = Some v } rest
    | "verdict" -> if acc.verdict <> None then usage "duplicate flag --verdict" else loop { acc with verdict = Some v } rest
    | "target" -> if acc.target <> None then usage "duplicate flag --target" else loop { acc with target = Some v } rest
    | "type" -> if acc.typ <> None then usage "duplicate flag --type" else loop { acc with typ = Some v } rest
    | "depends-on" -> if acc.depends_on <> None then usage "duplicate flag --depends-on" else loop { acc with depends_on = Some v } rest
    | "format" ->
        if v <> "json" && v <> "table" && v <> "tree" then usage "--format must be json, table, or tree";
        loop { acc with fmt = v } rest
    | _ -> usage ("unknown flag --" ^ name)
  in
  (* pre-scan for duplicate --format *)
  let rec count n = function
    | [] -> n | "--format" :: _ :: r -> count (n + 1) r | _ :: r -> count n r in
  if count 0 args > 1 then usage "duplicate flag --format";
  loop { reason = None; commit = None; verdict = None; target = None;
         typ = None; depends_on = None; fmt = "json" } args

let split_flags args =
  (* separate positionals (before first --flag) from flags; any positional
     after a flag value that is not consumed is stray -> caught in parse *)
  let rec go pos flags = function
    | [] -> (List.rev pos, flags)
    | a :: rest when String.length a >= 2 && a.[0] = '-' && a.[1] = '-' ->
        (List.rev pos, a :: rest @ flags)
    | a :: rest -> go (a :: pos) flags rest in
  let (pos, fl) = go [] [] args in
  (pos, parse_flags fl)

let require_reason fl =
  match fl.reason with Some r when r <> "" -> r | _ -> usage "--reason is required"

(* ---------- config door (config.1) ---------- *)
let parse_config_flags args =
  let rec loop source fmt fmt_set = function
    | [] -> (source, fmt)
    | "--source" :: rest ->
        if source then usage "duplicate flag --source";
        loop true fmt fmt_set rest
    | "--format" :: v :: rest ->
        if fmt_set then usage "duplicate flag --format";
        if v <> "json" && v <> "table" then usage "--format must be json or table";
        loop source v true rest
    | ["--format"] -> usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop false "json" false args

let with_warnings id is_write fields =
  match warnings_of id is_write with
  | [] -> `Assoc fields
  | ws -> `Assoc (fields @ [("warnings", `List (List.map json_str ws))])

let illegal state edge =
  err "E_ILLEGAL_EDGE"
    (`Assoc [("state", json_str state); ("edge", json_str edge);
             ("legal_edges", `List (List.map json_str (legal_edges state)))])
    "Pick a legal edge from legal_edges for the current state." 1

(* ---------- operations ---------- *)
let do_graph_create graph fl id =
  check_creatable graph;
  let qtype = (match fl.typ with Some t -> t | None -> "default") in
  let _ = graph_knobs qtype in
  if ref_tip (graph_branch graph) <> None then
    err "E_EXISTS" (`Assoc [("graph", json_str graph)]) "Graph already exists." 1;
  let deps = match fl.depends_on with
    | Some s when s <> "" -> String.split_on_char ',' s |> List.map String.trim
    | _ -> [] in
  List.iter check_slug deps;
  let head = head_sha () in
  let qpath = graph_dir graph ^ "/GRAPH.md" in
  let existing_graph_md = git_show head qpath in
  let graph_md = match existing_graph_md with
    | Some c -> c
    | None -> Printf.sprintf "---\nstatus: proposed\ngraph_type: %s\n---\n\n# %s\n\n## Success picture\n\nTODO\n" qtype graph in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"proposed" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("graph_type", json_str qtype);
            ("depends_on", `List (List.map json_str deps))] () in
  let existing_ledger = git_show head (graph_ledger_path graph) in
  let ledger = (match existing_ledger with Some t when String.trim t <> "" -> t ^ (if t.[String.length t-1] = '\n' then "" else "\n") | _ -> "") ^ line ^ "\n" in
  let _new_tip = create_branch_commit ~branch:(graph_branch graph) ~base_tip:head
    ~files:[(qpath, graph_md); (graph_ledger_path graph, ledger)] ~msg:("bp3: create graph " ^ graph) in
  with_warnings id true [("ok", `Bool true); ("graph", json_str graph); ("state", json_str "proposed")]

let do_graph_delete graph fl id =
  check_slug graph;
  let reason = require_reason fl in
  (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
  let (view, _, _, qs) = graph_view graph in
  ignore view;
  if qs.st = "deleted" then illegal "deleted" "delete";
  let nodes = list_nodes graph in
  let any_blocked = List.exists (fun e ->
    match fold_node graph e with Some (_, s, _) -> s.st = "blocked" | None -> false) nodes in
  if any_blocked && not id.decider_human then
    err "E_HUMAN_REQUIRED" (`Assoc [("graph", json_str graph)])
      "An node is blocked; a human decision is required (BP3_DECIDER=human)." 1;
  (match ledger_text (graph_branch graph) (graph_ledger_path graph) with
   | None -> not_found "graph" graph
   | Some (tip, text) ->
       let line = ledger_line ~edge:"delete" ~from:qs.st ~to_:"deleted" ~cycle:1
         ~commit:None ~verdict:None ~reason ~id () in
       let new_text = text ^ (if text = "" || text.[String.length text-1] = '\n' then "" else "\n") ^ line ^ "\n" in
       ignore (commit_files ~branch:(graph_branch graph) ~base_tip:tip ~expect_tip:tip
         ~files:[(graph_ledger_path graph, new_text)] ~msg:("bp3: delete graph " ^ graph)));
  with_warnings id true [("ok", `Bool true); ("graph", json_str graph); ("state", json_str "deleted")]

(* Node deps (mvp.3): declared at node create, editable
   through the dep verb, always read back from ledger
   records. A dep cycle refuses at write time naming
   the cycle; deps stay mutable-but-logged. *)
let parse_dep_list = function
  | Some s when s <> "" ->
      List.fold_right (fun d acc ->
        let d = String.trim d in if d = "" || List.mem d acc then acc else d :: acc)
        (String.split_on_char ',' s) []
  | _ -> []

let dep_graph graph =
  List.map (fun e ->
    match fold_node graph e with
    | Some (_, _, text) -> (e, deps_of_text text)
    | None -> (e, [])) (list_nodes graph)

let validate_deps graph self deps =
  List.iter check_slug deps;
  List.iter (fun d ->
    if fold_node graph d = None then not_found "node" d) deps;
  let dgraph = (self, deps) :: List.filter (fun (e, _) -> e <> self) (dep_graph graph) in
  match dep_cycle_through dgraph self with
  | Some cyc ->
      err "E_DEP_CYCLE" (`Assoc [("graph", json_str graph); ("node", json_str self);
        ("cycle", `List (List.map json_str cyc))])
        "Dep cycle refused at write time; break the named cycle." 1
  | None -> ()

let do_node_create graph node fl id =
  check_slug graph; check_creatable node;
  (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
  let etype = (match fl.typ with Some t -> t | None -> "default") in
  (* validate node plan exists for non-default *)
  (match fold_graph graph with
   | Some (_, _, qt, _, _) -> ignore (effective_knobs ~graph_type:qt ~node_type:etype)
   | None -> ());
  if ref_tip (node_branch graph node) <> None then
    err "E_EXISTS" (`Assoc [("graph", json_str graph); ("node", json_str node)]) "Node already exists." 1;
  let deps = parse_dep_list fl.depends_on in
  validate_deps graph node deps;
  let qtip = (match ref_tip (graph_branch graph) with Some t -> t | None -> not_found "graph" graph) in
  let st = fresh_state () in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"todo" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("node_type", json_str etype);
            ("depends_on", `List (List.map json_str deps))] () in
  let _ = create_branch_commit ~branch:(node_branch graph node) ~base_tip:qtip
    ~files:[(node_ledger_path graph node, line ^ "\n");
            (node_state_path graph node, state_yaml graph node st)]
    ~msg:("bp3: create node " ^ node) in
  with_warnings id true [("ok", `Bool true); ("graph", json_str graph);
    ("node", json_str node); ("state", json_str "todo"); ("cycle", `Int 1);
    ("deps", `List (List.map json_str deps));
    ("legal_edges", `List (List.map json_str (legal_edges "todo")))]

let do_node_dep graph node fl id =
  check_slug graph; check_slug node;
  let reason = require_reason fl in
  let deps = match fl.depends_on with
    | Some _ -> parse_dep_list fl.depends_on
    | None -> usage "dep needs --depends-on <a,b> (empty clears)" in
  (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
  (match fold_node graph node with
   | None -> not_found "node" node
   | Some (_, s, _) ->
       validate_deps graph node deps;
       let line = ledger_line ~edge:"dep" ~from:s.st ~to_:s.st ~cycle:s.cycle
         ~commit:s.last_commit ~verdict:None ~reason ~id
         ~extra:[("depends_on", `List (List.map json_str deps))] () in
       ignore (append_node_line graph node line s));
  (match fold_node graph node with
   | Some (_, s, text) ->
       with_warnings id true [("ok", `Bool true); ("graph", json_str graph);
         ("node", json_str node); ("state", json_str s.st); ("cycle", `Int s.cycle);
         ("deps", `List (List.map json_str (deps_of_text text)));
         ("legal_edges", `List (List.map json_str (legal_edges s.st)))]
   | None -> not_found "node" node)

let do_node_delete graph node fl id =
  check_slug graph; check_slug node;
  let reason = require_reason fl in
  (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
  (match fold_node graph node with
   | None -> not_found "node" node
   | Some (_, s, _) ->
       if s.st = "landed" || s.st = "deleted" then illegal s.st "delete";
       if s.st = "blocked" && not id.decider_human then
         err "E_HUMAN_REQUIRED" (`Assoc [("graph", json_str graph); ("node", json_str node)])
           "Deleting a blocked node requires a human (BP3_DECIDER=human)." 1;
       let ns = { s with st = "deleted" } in
       let line = ledger_line ~edge:"delete" ~from:s.st ~to_:"deleted" ~cycle:s.cycle
         ~commit:s.last_commit ~verdict:None ~reason ~id () in
       ignore (append_node_line graph node line ns));
  with_warnings id true [("ok", `Bool true); ("graph", json_str graph);
    ("node", json_str node); ("state", json_str "deleted")]

let do_update graph node edge fl id =
  check_slug graph; check_slug node;
  let reason = require_reason fl in
  if not (List.mem edge ["handoff"; "grade"; "verify"; "land"; "block"; "resume"]) then
    usage ("unknown edge: " ^ edge);
  (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
  let (_, s, _) = (match fold_node graph node with Some v -> v | None -> not_found "node" node) in
  let (_, qt, deps) = (match fold_graph graph with Some (_, _, a, b, _) -> ((), a, b) | None -> not_found "graph" graph) in
  let knobs = effective_knobs ~graph_type:qt ~node_type:s.node_type in
  let finish ns line =
    ignore (append_node_line graph node line ns);
    with_warnings id true [("ok", `Bool true); ("graph", json_str graph);
      ("node", json_str node); ("state", json_str ns.st); ("cycle", `Int ns.cycle);
      ("commit", (match ns.last_commit with Some c -> json_str c | None -> `Null));
      ("legal_edges", `List (List.map json_str (legal_edges ns.st)))] in
  match edge with
  | "handoff" ->
      if s.st <> "todo" then illegal s.st edge;
      let raw = (match fl.commit with Some c -> c | None -> usage "--commit is required for handoff") in
      let full = (match resolve_commit raw with Some f -> f
        | None -> err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str raw)])
            "Commit does not exist; bind an existing commit." 1) in
      if worktree_dirty () then
        err "E_DIRTY_TREE" (`Assoc []) "Worktree is dirty; clean it and retry." 1;
      let blocked_by = List.filter (fun d -> not (dep_satisfied d)) deps in
      if blocked_by <> [] then
        err "E_DEPENDENCY" (`Assoc [("blocked_by", `List (List.map json_str blocked_by))])
          "Dependencies are not landed yet." 1;
      let node_deps = (match fold_node graph node with
        | Some (_, _, text) -> deps_of_text text | None -> []) in
      let node_blocked = List.filter (fun d ->
        match fold_node graph d with
        | Some (_, ds, _) -> ds.st <> "landed" && ds.st <> "deleted"
        | None -> true) node_deps in
      if node_blocked <> [] then
        err "E_DEPENDENCY" (`Assoc [("blocked_by", `List (List.map json_str node_blocked))])
          "Node deps are not landed yet." 1;
      let approved_now = (not knobs.grade_required) && (not knobs.verify_required) in
      let ns = { s with st = (if approved_now then "approved" else "handed_off");
                 bound = Some full; has_bound = true; last_commit = Some full;
                 grade_ok = false; verify_ok = false } in
      let line = ledger_line ~edge ~from:s.st ~to_:ns.st ~cycle:s.cycle
        ~commit:(Some full) ~verdict:None ~reason ~id () in
      finish ns line
  | "grade" | "verify" ->
      if s.st <> "handed_off" then illegal s.st edge;
      let v = (match fl.verdict with Some v -> v | None -> usage "--verdict is required") in
      let valid = if edge = "grade" then (v = "ship" || v = "needs_fix") else (v = "pass" || v = "fail") in
      if not valid then usage ("invalid verdict for " ^ edge ^ ": " ^ v);
      (match fl.commit with
       | Some c ->
           let rc = (match resolve_commit c with Some f -> f | None -> c) in
           let bound = (match s.bound with Some b -> b | None -> "") in
           if rc <> bound then
             err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str c); ("bound", json_str bound)])
               "Verdict must bind the exact current commit; re-read and retry." 1
       | None -> ());
      let positive = (v = "ship" || v = "pass") in
      if not positive then begin
        let (nst, ncyc) =
          if s.cycle >= knobs.max_cycles then ("blocked", s.cycle) else ("todo", s.cycle + 1) in
        let ns = { s with st = nst; cycle = ncyc; grade_ok = false; verify_ok = false } in
        if nst = "blocked" then begin ns.blocked_reason <- reason; ns.blocked_since <- now_ts () end;
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:ncyc
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id () in
        let base = finish ns line in
        if nst = "blocked" then
          (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
        else base
      end else begin
        let ns = { s with grade_ok = (if edge = "grade" then true else s.grade_ok);
                          verify_ok = (if edge = "verify" then true else s.verify_ok) } in
        let now_approved =
          ((not knobs.grade_required) || ns.grade_ok) &&
          ((not knobs.verify_required) || ns.verify_ok) in
        let nst = if now_approved then "approved" else "handed_off" in
        let ns = { ns with st = nst } in
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:s.cycle
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id () in
        finish ns line
      end
  | "land" ->
      if s.st <> "approved" then illegal s.st edge;
      (match fl.commit with
       | Some c ->
           let rc = (match resolve_commit c with Some f -> f | None -> c) in
           let bound = (match s.bound with Some b -> b | None -> "") in
           if rc <> bound then
             err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str c)])
               "Verdict must bind the exact current commit." 1
       | None -> ());
      (* 1. landed line on node branch *)
      let ns = { s with st = "landed" } in
      let line = ledger_line ~edge ~from:s.st ~to_:"landed" ~cycle:s.cycle
        ~commit:s.last_commit ~verdict:None ~reason ~id () in
      ignore (append_node_line graph node line ns);
      let node_tip = (match ref_tip (node_branch graph node) with Some t -> t | None -> "") in
      let qbranch = graph_branch graph in
      let qtip = (match ref_tip qbranch with Some t -> t | None -> "") in
      if is_ancestor qtip node_tip then begin
        if run_status (git ["update-ref"; qbranch; node_tip; qtip]) <> 0 then
          err "E_STALE_WORLD" (`Assoc []) "Graph tip moved; re-read and retry." 1;
        with_warnings id true [("ok", `Bool true); ("graph", json_str graph);
          ("node", json_str node); ("state", json_str "landed"); ("fin", json_str "node_fin"); ("cycle", `Int s.cycle);
          ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
          ("legal_edges", `List [])]
      end else begin
        let tree_out, code = git_out ["merge-tree"; "--write-tree"; qtip; node_tip] in
        let tree = (match String.split_on_char '\n' tree_out with t :: _ -> String.trim t | [] -> "") in
        if code <> 0 || tree = "" then begin
          let ns2 = { s with st = "todo" } in
          let line2 = ledger_line ~edge:"land" ~from:"approved" ~to_:"todo" ~cycle:s.cycle
            ~commit:s.last_commit ~verdict:None ~reason ~id () in
          ignore (append_node_line graph node line2 ns2);
          `Assoc [("ok", `Bool true); ("graph", json_str graph); ("node", json_str node);
            ("state", json_str "todo"); ("cycle", `Int s.cycle);
            ("facts", `Assoc [("land_conflict", `Bool true)]);
            ("legal_edges", `List (List.map json_str (legal_edges "todo")))]
        end else begin
          let msgf = write_tmp ("bp3: land " ^ node) in
          let cf = tmp_path "merge-commit" in
          ignore (Sys.command (String.concat " " (List.map Filename.quote
              (git ["commit-tree"; tree; "-p"; qtip; "-p"; node_tip]))
            ^ " < " ^ Filename.quote msgf ^ " > " ^ Filename.quote cf ^ " 2>/dev/null"));
          let mtip = String.trim (read_file_or cf "") in
          if run_status (git ["update-ref"; qbranch; mtip; qtip]) <> 0 then
            err "E_STALE_WORLD" (`Assoc []) "Graph tip moved; re-read and retry." 1;
          with_warnings id true [("ok", `Bool true); ("graph", json_str graph);
            ("node", json_str node); ("state", json_str "landed"); ("fin", json_str "node_fin"); ("cycle", `Int s.cycle);
            ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
            ("legal_edges", `List [])]
        end
      end
  | "block" ->
      if not (List.mem s.st ["todo"; "handed_off"; "approved"]) then illegal s.st edge;
      let checkpoint = if worktree_dirty () then Some (make_checkpoint ()) else None in
      let ns = { s with st = "blocked"; blocked_reason = reason;
                 blocked_checkpoint = checkpoint; blocked_since = now_ts () } in
      let line = ledger_line ~edge ~from:s.st ~to_:"blocked" ~cycle:s.cycle
        ~commit:s.last_commit ~verdict:None ~reason ~id ?checkpoint () in
      let base = finish ns line in
      (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
  | "resume" ->
      if s.st <> "blocked" then illegal s.st edge;
      if not id.decider_human then
        err "E_HUMAN_REQUIRED" (`Assoc [("graph", json_str graph); ("node", json_str node)])
          "Resume requires a human decision (BP3_DECIDER=human)." 1;
      let ncyc = if s.has_bound then s.cycle + 1 else s.cycle in
      let ns = { s with st = "todo"; cycle = ncyc; bound = None; has_bound = false;
                 grade_ok = false; verify_ok = false } in
      let line = ledger_line ~edge ~from:s.st ~to_:"todo" ~cycle:ncyc
        ~commit:None ~verdict:None ~reason ~id () in
      finish ns line
  | _ -> usage ("unknown edge: " ^ edge)

(* ---------- diagram (mvp.4) ---------- *)
(* Read-only: renders the graph_view rollup snapshot at
   call time and writes no ledger line. ascii/mermaid print
   raw text; json prints the same facts as a verdict. *)
let parse_diagram_flags args =
  let rec loop fmt fmt_set = function
    | [] -> fmt
    | "--format" :: v :: rest ->
        if fmt_set then usage "duplicate flag --format";
        if v <> "ascii" && v <> "mermaid" && v <> "json" then
          usage "--format must be ascii, mermaid, or json";
        loop v true rest
    | ["--format"] -> usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop "ascii" false args

let do_diagram graph tail =
  check_slug graph;
  let fmt = parse_diagram_flags tail in
  let (view, _, _, _) = graph_view graph in
  let fields = match view with `Assoc fs -> fs | _ -> [] in
  let generated_at = now_ts () in
  (match fmt with
   | "ascii" -> print_string (emit_ascii fields generated_at)
   | "mermaid" -> print_string (emit_mermaid fields generated_at)
   | _ ->
       print_verdict ~fmt:"json" (`Assoc [
         ("ok", `Bool true); ("graph", json_str graph);
         ("format", json_str "json");
         ("generated_at", json_str generated_at);
         ("rollup", json_str (dstr fields "rollup"));
         ("nodes", `List (dlist fields "nodes"));
         ("deps", `List (List.map (fun (d, n) ->
            `Assoc [("from", json_str d); ("to", json_str n)])
            (diagram_deps (diagram_nodes fields))));
         ("ready_set_waves", `List (dlist fields "ready_set_waves"));
         ("ready", `List (dlist fields "ready"));
         ("starved", `List (dlist fields "starved"));
         ("diagram_ascii", json_str (emit_ascii fields generated_at));
         ("diagram_mermaid", json_str (emit_mermaid fields generated_at));
       ]));
  0

(* ---------- context door (mvp.2: bp3 e) ---------- *)
let no_context amb =
  match amb with
  | Some ids ->
      err "E_NO_CONTEXT"
        (`Assoc [("run_ids", `List (List.map json_str ids));
                 ("live_run_ids", `List (List.map json_str ids));
                 ("desk", json_str (Sys.getcwd ()));
                 ("source", json_str "desk")])
        "Desk holds more than one live claimed run and no session rung resolves; refusing to guess. Claim a link for one run, or address the call explicitly." 1
  | None ->
      err "E_NO_CONTEXT"
        (`Assoc [("desk", json_str (Sys.getcwd ()))])
        "No claimed context resolves for this call (no session claim, no desk context). Claim a link first, or address the call explicitly." 1

let with_context v (rc : Config.run_config) source =
  match v with
  | `Assoc fs ->
      `Assoc (fs @ [("graph", json_str rc.Config.rc_graph);
                    ("node", json_str rc.Config.rc_node);
                    ("source", json_str source);
                    ("source_rung", json_str source);
                    ("context", Config.resolved_context_json rc source)])
  | other -> other

let do_e_bare (rc : Config.run_config) source =
  let graph = rc.Config.rc_graph and node = rc.Config.rc_node in
  let (state, legal) =
    match fold_node graph node with
    | Some (_, s, _) -> (json_str s.st, List.map json_str (legal_edges s.st))
    | None -> (`Null, []) in
  let thresholds =
    match Config.config_dir () with
    | Some dir -> Config.thresholds_json (Config.load_thresholds dir)
    | None -> Config.thresholds_json Config.default_thresholds in
  `Assoc [("ok", `Bool true);
          ("graph", json_str graph);
          ("node", json_str node);
          ("edge", (match rc.Config.rc_edge with Some e -> json_str e | None -> `Null));
          ("run_id", json_str rc.Config.rc_id);
          ("kind", json_str rc.Config.rc_kind);
          ("desk", json_str rc.Config.rc_desk);
          ("session_id", (match rc.Config.rc_session with Some s -> json_str s | None -> `Null));
          ("source", json_str source); ("source_rung", json_str source);
          ("state", state); ("legal_edges", `List legal);
          ("context", Config.resolved_context_json rc source);
          ("thresholds", thresholds)]

let do_e ctx_rc ctx_source ctx_amb id = function
  | [] ->
      (match ctx_rc with
       | Some rc -> print_verdict ~fmt:"json" (do_e_bare rc ctx_source); 0
       | None -> no_context ctx_amb)
  | edge :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in e";
      (match ctx_rc with
       | Some rc ->
           let v = do_update rc.Config.rc_graph rc.Config.rc_node edge fl id in
           print_verdict ~fmt:fl.fmt (with_context v rc ctx_source); 0
       | None -> no_context ctx_amb)

(* ---------- node door (rename.1: bp3 n) ---------- *)
(* Claimed shorthand: reads the claimed run's node, resolved
   exactly like the e door (session rung, then desk rung). *)
let do_n ctx_rc ctx_source ctx_amb = function
  | [] | ["r"] | ["read"] ->
      (match ctx_rc with
       | Some rc ->
           let graph = rc.Config.rc_graph and node = rc.Config.rc_node in
           (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
           (match fold_node graph node with
            | None -> not_found "node" node
            | Some (_, s, text) ->
                print_verdict ~fmt:"json"
                  (with_context
                     (node_verdict graph node s (deps_of_text text)
                        (timing_of_text text)) rc ctx_source); 0)
       | None -> no_context ctx_amb)
  | _ -> usage "node door verbs are r"

(* ---------- main dispatch ---------- *)
let normalize_verb = function
  | "c" | "create" -> "c" | "r" | "read" -> "r"
  | "u" | "update" -> "u" | "d" | "delete" -> "d"
  | other -> other

let is_verb = function "c" | "create" | "r" | "read" | "u" | "update" | "d" | "delete" -> true | _ -> false

(* icebox door: bp3 g icebox r [term...] | r <slug> (read-only) *)
let do_icebox = function
  | verb_raw :: rest when is_verb verb_raw ->
      if normalize_verb verb_raw <> "r" then usage "icebox door is read-only: only r";
      let (terms, fl) = split_flags rest in
      let entries = list_icebox_entries () in
      let print_list () =
        let hits = List.filter (fun e -> icebox_matches e terms) entries in
        print_verdict ~fmt:fl.fmt (`Assoc [("ok", `Bool true);
          ("entries", `List (List.map icebox_entry_json hits))]); 0 in
      (match terms with
       | [slug] ->
           (match List.find_opt (fun e -> e.slug = slug) entries with
            | Some e -> print_string e.text; 0
            | None -> print_list ())
       | _ -> print_list ())
  | _ -> usage "icebox door verbs are r"

(* ---------- help (docstrings beside dispatch; Node 4) ---------- *)
let help_g = "bp3 g - graph/node state. Doors:\n\
  bp3 g c|r|d ...              graph door (create, read, delete)\n\
  bp3 g <graph> c|r|u|d ...    node door for one graph\n\
  bp3 g <graph> n <node> r     read one node (canonical nested address)\n\
  bp3 g <graph> n <node> e <edge> [flags]   take one node's edge (canonical nested address)\n\
  bp3 g <graph> diagram ...    generated graph diagram from the live rollup (mvp.4)\n\
  bp3 g icebox r [term...]     search frozen icebox entries (read-only)\n\
  bp3 n [r]                    claimed node door: read the claimed run's node (rename.1)\n\
  bp3 e [<edge> ...]           claimed edge door: resolved context, no names typed (mvp.2)\n\
  bp3 harness desk <verb> ...  desks (machine-local); bp3 worktree is its documented alias\n\
  bp3 config [--source]        view the machine-local config store (<git-common-dir>/bp3/)\n\
  bp3 g hooks                  harness hook emitter (fail-open)\n\
Run bp3 g <door> -h for that door's verbs, edges, and flags.\n"

let help_graph_door = "bp3 g <graph door> - verbs:\n\
  bp3 g c <graph> [--type <graph_type>] [--depends-on <a,b>]   create a graph\n\
  bp3 g r [<graph>] [--format json|table|tree]                 list graphs, or read one\n\
  bp3 g d <graph> --reason <why>                               delete a graph\n\
Long forms: create, read, delete. Example: bp3 g c my-graph --type default\n"

let help_node_door = "bp3 g <graph> <node door> - verbs:\n\
  bp3 g <graph> c <node> [--type <node_type>] [--depends-on <a,b>]   create an node, deps name nodes in the same graph\n\
  bp3 g <graph> r [<node>] [--format json|table|tree]           read the graph, or one node\n\
  bp3 g <graph> u <node> <edge> [flags]                         take an FSM edge (see u -h)\n\
  bp3 g <graph> d <node> --reason <why>                         delete an node\n\
  bp3 g <graph> dep <node> --depends-on <a,b> --reason <why>    redeclare an node's deps (mutable-but-logged)\n\
  bp3 g <graph> diagram [--format ascii|mermaid|json]          generated diagram from the live rollup (see diagram -h)\n\
Long forms: create, read, update, delete. Example: bp3 g my-graph r node-1\n"

let help_dep = "bp3 g <graph> dep <node> - redeclare an node's node deps (mvp.3):\n\
  bp3 g <graph> dep <node> --depends-on <a,b> --reason <why>   set deps; --depends-on \"\" clears them\n\
  Deps name nodes in the same graph, are read back from the node ledger, and a cycle refuses at write time (E_DEP_CYCLE) naming the cycle. The dep line is logged with the node state and cycle, so a mid-flight edit stays on the record.\n\
Example: bp3 g my-graph dep node-2 --depends-on node-1 --reason \"needs node-1 first\"\n"

let help_diagram = "bp3 g <graph> diagram - generated graph diagram from the live rollup (mvp.4):\n\
  bp3 g <graph> diagram [--format ascii|mermaid|json]   emit the diagram (default ascii)\n\
  Nodes carry state and cycle (landed nodes carry node_fin), deps are drawn once, todo nodes are grouped into ready-set waves, and a blocked node names the dependents it starves. Output is generated at call time from live state; its header carries the rollup timestamp (generated_at). ascii suits terminals and records, mermaid suits rendered docs, json carries the same facts plus both texts for diffing.\n\
Example: bp3 g my-graph diagram --format mermaid\n"

let help_update = "bp3 g <graph> u <node> <edge> - edges and their flags:\n\
  edges: handoff grade verify land block resume\n\
  handoff --commit <sha> --reason <why>    bind a clean commit for grade\n\
  grade  --verdict ship|needs_fix --reason <why>\n\
  verify --verdict pass|fail --reason <why>\n\
  land   --reason <why>                    land an approved node\n\
  block  --reason <why>                    park for a human decision\n\
  resume --reason <why>                    human only: unblock\n\
Shared flags: --format json|table|tree, --target <name>.\n\
Example: bp3 g my-graph u node-1 handoff --commit abc123 --reason \"ready\"\n"

let help_e = "bp3 e - claimed edge door (mvp.2): context is resolved, never carried:\n\
  bp3 e                                    print the resolved context, its source rung (session|desk), state, and legal edges\n\
  bp3 e <edge> [flags]                     take the claimed run's edge: handoff grade verify land block resume (same flags as bp3 g <graph> u <node> <edge>)\n\
  Resolution: session claim first, desk context second, checked against cwd; no rung refuses E_NO_CONTEXT, an ambiguous desk refuses E_NO_CONTEXT naming the live run_ids. Env BP3_RUN_ID is a hint only: a mismatch warns W_CONTEXT_ENV_MISMATCH and the claim wins; an unclaimed explicit edge call warns W_CONTEXT_UNCLAIMED.\n\
Example: bp3 e handoff --commit abc123 --reason \"ready\"\n"

let help_n = "bp3 n - claimed node door (rename.1): context is resolved, never carried:\n\
  bp3 n [r]                        read the claimed run's node (same resolution as bp3 e: session claim first, desk context second)\n\
  No rung resolving refuses E_NO_CONTEXT; address the call explicitly with bp3 g <graph> n <node> r instead.\n\
Example: bp3 n r\n"

let help_icebox = "bp3 g icebox r - search frozen icebox entries (read-only):\n\
  bp3 g icebox r [term...] [--format json|table|tree]   list entries matching all terms\n\
  bp3 g icebox r <slug>                                 print one entry in full\n\
Example: bp3 g icebox r table completion\n"

let help_worktree = "bp3 worktree - documented alias of bp3 harness desk, machine-local desks, never ledgered:\n\
  verbs: derive, create, inspect, remove, prepare, check, exit, release, list\n\
  bp3 harness desk prepare <graph> <node> --run <run-id> [--commit <sha>] [--path <dir>]\n\
  bp3 harness desk list [--graph <graph>]\n\
Example: bp3 harness desk prepare my-graph node-1 --run R1\n"

let help_config = "bp3 config - view the machine-local bp3 config store (<git-common-dir>/bp3/, never committed):\n\
  bp3 config [--source] [--format json|table]   thresholds plus contexts folded from runs/<run_id>.json\n\
  config.json holds machine settings only (thresholds: setup_slow_s, depth_cap); contexts are views, never stored there. The depth cap is enforced at link mint (mvp.1, E_DEPTH); W_SETUP_SLOW fires on the graph rollup when a claimed Run's setup_wall_s exceeds setup_slow_s (mvp.3, local only). First call on a fresh repo creates the store with defaults (zero setup), and every view rebuilds the derived by-session index from runs/, so deleting by-session/ loses nothing. --source names the writing verb and timestamp per context. Outside a git repo there is no store and the call refuses E_NOT_FOUND.\n\
Example: bp3 config --source\n"

let is_help = function "-h" | "--help" -> true | _ -> false

(* Node 5 guard: an older-MAJOR binary never writes in a newer repo.
   Newer MINOR/PATCH only warns (warnings_of carries W_VERSION_AHEAD). *)
let guard_write argv =
  let argv = match argv with "g" :: rest -> rest | other -> other in
  let is_write = match argv with
    | v :: _ when is_verb v -> let n = normalize_verb v in n = "c" || n = "d"
    | _q :: v :: _ when is_verb v -> normalize_verb v <> "r"
    | _ -> false in
  if is_write && not (List.exists is_help (List.filteri (fun i _ -> i < 3) argv)) then
    match version_ahead () with
    | Some v when version_major v > version_major bp3_version ->
        err "E_VERSION_AHEAD"
          (`Assoc [("binary", json_str bp3_version); ("repo", json_str v)])
          "Repo was stamped by a newer MAJOR bp3; upgrade bp3 before writing." 1
    | _ -> ()

let rec run argv =
  let base_id = identity () in
  (* Context resolution (mvp.2): session rung, then desk
     rung. Explicit addresses always win for the target;
     a resolved claim wins the run-id stamp over the env
     hint. Help and the machine doors resolve nothing. *)
  let help_invoked =
    List.exists is_help (List.filteri (fun i _ -> i < 3) argv) in
  let context_door = match argv with
    | "harness" :: _ | "config" :: _ | "worktree" :: _ | "hooks" :: _
    | "init-repo" :: _ | [] -> false
    | _ -> not help_invoked in
  let (ctx_rc, ctx_source, ctx_amb) =
    if not context_door then (None, "", None)
    else match Config.resolve_context () with
      | Config.Resolved (rc, src) -> (Some rc, src, None)
      | Config.Ambiguous (ids, _) -> (None, "", Some ids)
      | Config.No_context -> (None, "", None) in
  let id = match ctx_rc with
    | Some rc -> { base_id with run_id = Some rc.Config.rc_id }
    | None -> base_id in
  Store.resolved_run_id :=
    (match ctx_rc with Some rc -> Some rc.Config.rc_id | None -> None);
  let edge_call = match argv with
    | "e" :: _ :: _ -> true
    | "g" :: _g :: v :: _n :: _edge :: _ when is_verb v && normalize_verb v = "u" -> true
    | "g" :: _g :: "n" :: _n :: "e" :: _edge :: _ -> true
    | _q :: v :: _e :: _edge :: _ when is_verb v && normalize_verb v = "u" -> true
    | _ -> false in
  Store.context_warnings :=
    (match ctx_rc with
     | Some rc ->
         (match base_id.run_id with
          | Some env when env <> "" && env <> rc.Config.rc_id ->
              ["W_CONTEXT_ENV_MISMATCH"]
          | _ -> [])
     | None ->
         if edge_call && ctx_amb = None then ["W_CONTEXT_UNCLAIMED"] else []);
  guard_write argv;
  match argv with
  | "-h" :: _ | "--help" :: _ -> print_string help_g; 0
  | "--version" :: _ -> print_endline bp3_version; 0
  | "g" :: (h :: _) when is_help h -> print_string help_g; 0
  | "g" :: rest -> run rest
  | "n" :: (h :: _) when is_help h -> print_string help_n; 0
  | "n" :: rest -> do_n ctx_rc ctx_source ctx_amb rest
  | "harness" :: rest -> Harness.run rest
  | "config" :: (h :: _) when is_help h -> print_string help_config; 0
  | "config" :: rest ->
      let (source, fmt) = parse_config_flags rest in
      print_verdict ~fmt (Config.view ~source); 0
  | "e" :: (h :: _) when is_help h -> print_string help_e; 0
  | "e" :: _edge :: (h :: _) when is_help h -> print_string help_e; 0
  | "e" :: rest -> do_e ctx_rc ctx_source ctx_amb id rest
  | "worktree" :: (h :: _) when is_help h -> print_string help_worktree; 0
  | "icebox" :: (h :: _) when is_help h -> print_string help_icebox; 0
  | "icebox" :: ("r" | "read") :: (h :: _) when is_help h -> print_string help_icebox; 0
  | first :: (h :: _) when is_verb first && is_help h -> print_string help_graph_door; 0
  | _graph :: (h :: _) when is_help h -> print_string help_node_door; 0
  | _graph :: verb_raw :: (h :: _) when is_verb verb_raw && is_help h ->
      print_string (if normalize_verb verb_raw = "u" then help_update else help_node_door); 0
  | "worktree" :: rest ->
      (* documented alias of harness desk (mvp.6): same store,
         same verdicts; new callers use bp3 harness desk *)
      print_verdict ~fmt:"json" (Worktree.run rest); 0
  | "init-repo" :: _ ->
      (* Node 6: scaffold plans/ into the caller's repo; never clobber differing plans *)
      let plans = [("plans/default.yaml", "graph_type: default\nmax_cycles: 1\ngrade:\n  required: true\nverify: required\n");
                   ("plans/direct.yaml", "graph_type: direct\nmax_cycles: 0\ngrade:\n  required: false\nverify: required\n")] in
      (try Unix.mkdir (Filename.concat root "plans") 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      List.iter (fun (rel, content) ->
        let path = Filename.concat root rel in
        if Sys.file_exists path then begin
          let existing = let ic = open_in_bin path in
            let s = really_input_string ic (in_channel_length ic) in close_in ic; s in
          if existing <> content then
            err "E_EXISTS" (`Assoc [("plan", json_str rel)])
              "Plan already exists with different content; refusing to overwrite." 1
        end else begin
          let oc = open_out_bin path in output_string oc content; close_out oc
        end) plans;
      print_verdict ~fmt:"json" (`Assoc [("ok", `Bool true);
        ("plans", `List (List.map (fun (p, _) -> json_str p) plans))]); 0
  | "hooks" :: _ ->
      (* fail-open emitter: Hooks.handle never raises, always exit 0 *)
      print_endline (Yojson.Safe.to_string (Hooks.handle ())); 0
  | "icebox" :: rest -> do_icebox rest
  | [] -> usage "no command"
  | first :: rest when is_verb first ->
      let verb = normalize_verb first in
      (match verb, rest with
       | "c", graph :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in graph create";
           let v = do_graph_create graph fl id in print_verdict ~fmt:fl.fmt v; 0
       | "c", [] -> usage "graph create needs a graph name"
       | "r", [] ->
           let qs = List.map (fun q ->
             let (view, _, _, _) = graph_view q in view) (list_graphs ()) in
           print_verdict ~fmt:"json" (`Assoc [("ok", `Bool true); ("graphs", `List qs)]); 0
       | "r", [graph] ->
           let (pos, fl) = ( [graph], { reason=None; commit=None; verdict=None; target=None; typ=None; depends_on=None; fmt="json" } ) in
           ignore pos;
           (* re-parse: graph may be followed by --format in original rest; handled below *)
           ignore fl;
           let (view, _, _, _) = graph_view graph in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []))); 0
       | "r", graph :: tail ->
           let (pos, fl) = split_flags (graph :: tail) in
           (match pos with
            | [q] ->
                let (view, _, _, _) = graph_view q in
                print_verdict ~fmt:fl.fmt (`Assoc (("ok", `Bool true) ::
                  (match view with `Assoc fs -> fs | _ -> []))); 0
            | _ -> usage "graph read takes at most one graph")
       | "d", graph :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in graph delete";
           let v = do_graph_delete graph fl id in print_verdict ~fmt:fl.fmt v; 0
       | "d", [] -> usage "graph delete needs a graph name"
       | _ -> usage "graph door verbs are c, r, d")
  | _q :: "diagram" :: (h :: _) when is_help h -> print_string help_diagram; 0
  | graph :: "diagram" :: tail -> do_diagram graph tail
  | _q :: "dep" :: (h :: _) when is_help h -> print_string help_dep; 0
  | graph :: "dep" :: node :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in dep";
      let v = do_node_dep graph node fl id in print_verdict ~fmt:fl.fmt v; 0
  | _g :: "n" :: (h :: _) when is_help h -> print_string help_node_door; 0
  | graph :: "n" :: ("c" | "create") :: node :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in node create";
      let v = do_node_create graph node fl id in print_verdict ~fmt:fl.fmt v; 0
  | graph :: "n" :: node :: ("r" | "read") :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in node read";
      (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
      (match fold_node graph node with
       | None -> not_found "node" node
       | Some (_, s, text) ->
           print_verdict ~fmt:fl.fmt
             (node_verdict graph node s (deps_of_text text) (timing_of_text text)); 0)
  | graph :: "n" :: node :: "e" :: edge :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in nested edge";
      let v = do_update graph node edge fl id in
      let v = match ctx_rc with
        | Some rc -> with_context v rc ctx_source | None -> v in
      print_verdict ~fmt:fl.fmt v; 0
  | graph :: "n" :: node :: [] ->
      (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
      (match fold_node graph node with
       | None -> not_found "node" node
       | Some (_, s, text) ->
           print_verdict ~fmt:"json"
             (node_verdict graph node s (deps_of_text text) (timing_of_text text)); 0)
  | graph :: verb_raw :: rest when is_verb verb_raw ->
      let verb = normalize_verb verb_raw in
      (match verb, rest with
       | "c", node :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in node create";
           let v = do_node_create graph node fl id in print_verdict ~fmt:fl.fmt v; 0
       | "c", [] -> usage "node create needs an node name"
       | "r", [] ->
           let (view, _, _, _) = graph_view graph in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []))); 0
       | "r", [node] ->
           (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
           (match fold_node graph node with
            | None -> not_found "node" node
            | Some (_, s, text) -> print_verdict ~fmt:"json" (node_verdict graph node s (deps_of_text text) (timing_of_text text)); 0)
       | "r", node :: tail ->
           let (pos, fl) = split_flags (node :: tail) in
           (match pos with
            | [e] ->
                (match fold_graph graph with None -> not_found "graph" graph | Some _ -> ());
                (match fold_node graph e with
                 | None -> not_found "node" e
                 | Some (_, s, text) -> print_verdict ~fmt:fl.fmt (node_verdict graph e s (deps_of_text text) (timing_of_text text)); 0)
            | _ -> usage "node read takes at most one node")
       | "u", node :: edge :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in update";
           let v = do_update graph node edge fl id in
           let v = match ctx_rc with
             | Some rc -> with_context v rc ctx_source | None -> v in
           print_verdict ~fmt:fl.fmt v; 0
       | "u", _ -> usage "update needs <node> <edge>"
       | "d", node :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in node delete";
           let v = do_node_delete graph node fl id in print_verdict ~fmt:fl.fmt v; 0
       | "d", [] -> usage "node delete needs an node name"
       | _ -> usage "node door verbs are c, r, u, d")
  | _ -> usage "expected: bp3 g c|r|d ... or bp3 g <graph> c|r|u|d ... (see bp3 g -h)"

let () =
  let argv = List.tl (Array.to_list Sys.argv) in
  try exit (run argv)
  with Verdict (code, v) ->
    print_endline (Yojson.Safe.to_string (stamp_run_id v));
    exit code


