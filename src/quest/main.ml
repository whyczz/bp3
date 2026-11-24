(* bp3 q — quest/node FSM CLI. Only writer of quest state.
   Doors and the FSM judge live here; plumbing in Gitx,
   truth in Store, presentation in Render. *)
open Gitx
open Store
open Render
include Cli

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
let do_quest_create quest fl id =
  check_creatable quest;
  let qtype = (match fl.typ with Some t -> t | None -> "default") in
  let _ = quest_knobs qtype in
  if ref_tip (quest_branch quest) <> None then
    err "E_EXISTS" (`Assoc [("quest", json_str quest)]) "Quest already exists." 1;
  let deps = match fl.depends_on with
    | Some s when s <> "" -> String.split_on_char ',' s |> List.map String.trim
    | _ -> [] in
  List.iter check_slug deps;
  let head = head_sha () in
  let qpath = quest_dir quest ^ "/" ^ Layout.quest_file in
  let existing_quest_md = git_show head qpath in
  let quest_md = match existing_quest_md with
    | Some c -> c
    | None -> Printf.sprintf "---\nstatus: proposed\ngoal_type: %s\n---\n\n# %s\n\n## Success picture\n\nTODO\n" qtype quest in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"proposed" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("goal_type", json_str qtype);
            ("depends_on", `List (List.map json_str deps))] () in
  let existing_ledger = git_show head (quest_ledger_path quest) in
  let ledger = (match existing_ledger with Some t when String.trim t <> "" -> t ^ (if t.[String.length t-1] = '\n' then "" else "\n") | _ -> "") ^ line ^ "\n" in
  let _new_tip = create_branch_commit ~branch:(quest_branch quest) ~base_tip:head
    ~files:[(qpath, quest_md); (quest_ledger_path quest, ledger)] ~msg:("bp3: create quest " ^ quest) in
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest); ("state", json_str "proposed")]

let do_quest_delete quest fl id =
  check_slug quest;
  let reason = require_reason fl in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let (view, _, _, qs) = quest_view quest in
  ignore view;
  if qs.st = "deleted" then illegal "deleted" "delete";
  let nodes = list_nodes quest in
  let any_blocked = List.exists (fun e ->
    match fold_node quest e with Some (_, s, _) -> s.st = "blocked" | None -> false) nodes in
  if any_blocked && not id.decider_human then
    err "E_HUMAN_REQUIRED" (`Assoc [("quest", json_str quest)])
      "An node is blocked; a human decision is required (BP3_DECIDER=human)." 1;
  (match ledger_read (quest_branch quest) (quest_ledger_path quest) (legacy_quest_ledger_paths quest) with
   | None -> not_found "quest" quest
   | Some (tip, text, lpath) ->
       let line = ledger_line ~edge:"delete" ~from:qs.st ~to_:"deleted" ~cycle:1
         ~commit:None ~verdict:None ~reason ~id () in
       let new_text = text ^ (if text = "" || text.[String.length text-1] = '\n' then "" else "\n") ^ line ^ "\n" in
       ignore (commit_files ~branch:(quest_branch quest) ~base_tip:tip ~expect_tip:tip
         ~files:[(lpath, new_text)] ~msg:("bp3: delete quest " ^ quest)));
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest); ("state", json_str "deleted")]

(* Node deps (mvp.3): declared at node create, editable
   through the dep verb, always read back from ledger
   records. A dep cycle refuses at write time naming
   the cycle; deps stay mutable-but-logged. *)
let dep_quest quest =
  List.map (fun e ->
    match fold_node quest e with
    | Some (_, _, text) -> (e, deps_of_text text)
    | None -> (e, [])) (list_nodes quest)

let validate_deps quest self deps =
  List.iter check_slug deps;
  List.iter (fun d ->
    if fold_node quest d = None then not_found "node" d) deps;
  let dgraph = (self, deps) :: List.filter (fun (e, _) -> e <> self) (dep_quest quest) in
  match dep_cycle_through dgraph self with
  | Some cyc ->
      err "E_DEP_CYCLE" (`Assoc [("quest", json_str quest); ("node", json_str self);
        ("cycle", `List (List.map json_str cyc))])
        "Dep cycle refused at write time; break the named cycle." 1
  | None -> ()

let do_node_create quest node fl id =
  check_slug quest; check_creatable node;
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let etype = (match fl.typ with Some t -> t | None -> "default") in
  (* validate node plan exists for non-default *)
  (match fold_quest quest with
   | Some (_, _, qt, _, _) -> ignore (effective_knobs ~quest_type:qt ~node_type:etype)
   | None -> ());
  if ref_tip (node_branch quest node) <> None then
    err "E_EXISTS" (`Assoc [("quest", json_str quest); ("node", json_str node)]) "Node already exists." 1;
  let deps = parse_dep_list fl.depends_on in
  validate_deps quest node deps;
  let qtip = (match ref_tip (quest_branch quest) with Some t -> t | None -> not_found "quest" quest) in
  let st = fresh_state () in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"todo" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("node_type", json_str etype);
            ("depends_on", `List (List.map json_str deps))] () in
  let _ = create_branch_commit ~branch:(node_branch quest node) ~base_tip:qtip
    ~files:[(node_ledger_path quest node, line ^ "\n");
            (node_state_path quest node, state_yaml quest node st)]
    ~msg:("bp3: create node " ^ node) in
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
    ("node", json_str node); ("state", json_str "todo"); ("cycle", `Int 1);
    ("deps", `List (List.map json_str deps));
    ("legal_edges", `List (List.map json_str (legal_edges "todo")))]

let do_node_dep quest node fl id =
  check_slug quest; check_slug node;
  let reason = require_reason fl in
  let deps = match fl.depends_on with
    | Some _ -> parse_dep_list fl.depends_on
    | None -> usage "dep needs --depends-on <a,b> (empty clears)" in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  (match fold_node quest node with
   | None -> not_found "node" node
   | Some (_, s, _) ->
       validate_deps quest node deps;
       let line = ledger_line ~edge:"dep" ~from:s.st ~to_:s.st ~cycle:s.cycle
         ~commit:s.last_commit ~verdict:None ~reason ~id
         ~extra:[("depends_on", `List (List.map json_str deps))] () in
       ignore (append_node_line quest node line s));
  (match fold_node quest node with
   | Some (_, s, text) ->
       with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
         ("node", json_str node); ("state", json_str s.st); ("cycle", `Int s.cycle);
         ("deps", `List (List.map json_str (deps_of_text text)));
         ("legal_edges", `List (List.map json_str (legal_edges s.st)))]
   | None -> not_found "node" node)

let do_node_delete quest node fl id =
  check_slug quest; check_slug node;
  let reason = require_reason fl in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  (match fold_node quest node with
   | None -> not_found "node" node
   | Some (_, s, _) ->
       if s.st = "landed" || s.st = "deleted" then illegal s.st "delete";
       if s.st = "blocked" && not id.decider_human then
         err "E_HUMAN_REQUIRED" (`Assoc [("quest", json_str quest); ("node", json_str node)])
           "Deleting a blocked node requires a human (BP3_DECIDER=human)." 1;
       let ns = { s with st = "deleted" } in
       let line = ledger_line ~edge:"delete" ~from:s.st ~to_:"deleted" ~cycle:s.cycle
         ~commit:s.last_commit ~verdict:None ~reason ~id () in
       ignore (append_node_line quest node line ns));
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
    ("node", json_str node); ("state", json_str "deleted")]

(* The grader's cold brief (induct-inline-as-default brief.1): a read.
   It exists only while the bound commit waits on its grade; the one
   caller input is a desk path, checked so it can carry nothing else. *)
let do_brief quest node tail =
  check_slug quest; check_slug node;
  let desk = match tail with
    | [] -> None
    | [ f; d ] when f = Names.flag_desk ->
        if not (Brief.desk_shape d) || not (Sys.file_exists d && Sys.is_directory d)
        then usage (Names.flag_desk ^ " needs an absolute path to an existing directory, printable ASCII with no space")
        else Some d
    | _ -> usage (Names.verb_brief ^ " takes only " ^ Names.flag_desk ^ " <path>") in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let (_, s, _) = (match fold_node quest node with Some v -> v | None -> not_found "node" node) in
  let commit = (match s.st, s.bound with
    | "handed_off", Some c -> c
    | _ ->
        err Names.e_not_handed_off
          (`Assoc [("state", json_str s.st); ("legal_edges", `List (List.map json_str (legal_edges s.st)))])
          "A brief exists only for a commit waiting on its grade; re-read the node." 1) in
  let i = Brief.inputs ~quest ~node ~cycle:s.cycle ~commit ~upto:None in
  `Assoc [("ok", `Bool true); ("quest", json_str quest); ("node", json_str node);
          ("cycle", `Int s.cycle); ("commit", json_str commit);
          ("brief", json_str (Brief.render ?desk i))]

let do_update quest node edge fl id =
  check_slug quest; check_slug node;
  let reason = require_reason fl in
  if not (List.mem edge ["handoff"; "grade"; "verify"; "land"; "block"; "resume"]) then
    usage ("unknown edge: " ^ edge);
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let (_, s, _) = (match fold_node quest node with Some v -> v | None -> not_found "node" node) in
  let (_, qt, deps) = (match fold_quest quest with Some (_, _, a, b, _) -> ((), a, b) | None -> not_found "quest" quest) in
  let knobs = effective_knobs ~quest_type:qt ~node_type:s.node_type in
  let finish ns line =
    ignore (append_node_line quest node line ns);
    with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
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
      let node_deps = (match fold_node quest node with
        | Some (_, _, text) -> deps_of_text text | None -> []) in
      let node_blocked = List.filter (fun d ->
        match fold_node quest d with
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
      (match (edge, fl.verify_verdict) with
       | ("verify", Some _) -> usage "--verify-verdict is only valid on the grade edge"
       | (_, Some vv) when vv <> "pass" && vv <> "fail" ->
           usage "--verify-verdict must be pass or fail"
       | _ -> ());
      let verify_negative =
        match fl.verify_verdict with Some "fail" -> true | _ -> false in
      let positive = (v = "ship" || v = "pass") && not verify_negative in
      let cast_extra =
        (match fl.verify_verdict with Some vv -> [("verify_verdict", json_str vv)] | None -> []) @
        (if fl.mechanical then [("fix_class", json_str "mechanical")] else []) in
      if not positive then begin
        (* Pure-grade (followup.5): a named mechanical fix never
           blocks; the cycle cap counts disagreement cycles only,
           so a mechanical needs_fix always returns to todo. *)
        let (nst, ncyc) =
          if fl.mechanical then ("todo", s.cycle + 1)
          else if s.cycle >= knobs.max_cycles then ("blocked", s.cycle)
          else ("todo", s.cycle + 1) in
        let ns = { s with st = nst; cycle = ncyc; grade_ok = false; verify_ok = false } in
        if nst = "blocked" then begin ns.blocked_reason <- reason; ns.blocked_since <- now_ts () end;
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:ncyc
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id ~extra:cast_extra () in
        let base = finish ns line in
        if nst = "blocked" then
          (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
        else base
      end else begin
        let ns = { s with grade_ok = (if edge = "grade" then true else s.grade_ok);
                          verify_ok = (if edge = "verify" then true
                                       else if fl.verify_verdict = Some "pass" then true
                                       else s.verify_ok) } in
        let now_approved =
          ((not knobs.grade_required) || ns.grade_ok) &&
          ((not knobs.verify_required) || ns.verify_ok) in
        let nst = if now_approved then "approved" else "handed_off" in
        let ns = { ns with st = nst } in
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:s.cycle
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id ~extra:cast_extra () in
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
      ignore (append_node_line quest node line ns);
      let node_tip = (match ref_tip (node_branch quest node) with Some t -> t | None -> "") in
      let qbranch = quest_branch quest in
      let qtip = (match ref_tip qbranch with Some t -> t | None -> "") in
      if is_ancestor qtip node_tip then begin
        if not (move_ref ~branch:qbranch ~new_tip:node_tip ~expect_tip:qtip) then
          err "E_STALE_WORLD" (`Assoc []) "Quest tip moved; re-read and retry." 1;
        with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
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
          ignore (append_node_line quest node line2 ns2);
          `Assoc [("ok", `Bool true); ("quest", json_str quest); ("node", json_str node);
            ("state", json_str "todo"); ("cycle", `Int s.cycle);
            ("facts", `Assoc [("land_conflict", `Bool true)]);
            ("legal_edges", `List (List.map json_str (legal_edges "todo")))]
        end else begin
          let mtip, _ = git_out ~input:("bp3: land " ^ node)
              ["commit-tree"; tree; "-p"; qtip; "-p"; node_tip] in
          if not (move_ref ~branch:qbranch ~new_tip:mtip ~expect_tip:qtip) then
            err "E_STALE_WORLD" (`Assoc []) "Quest tip moved; re-read and retry." 1;
          with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
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
        err "E_HUMAN_REQUIRED" (`Assoc [("quest", json_str quest); ("node", json_str node)])
          "Resume requires a human decision (BP3_DECIDER=human)." 1;
      let ncyc = if s.has_bound then s.cycle + 1 else s.cycle in
      let ns = { s with st = "todo"; cycle = ncyc; bound = None; has_bound = false;
                 grade_ok = false; verify_ok = false } in
      let line = ledger_line ~edge ~from:s.st ~to_:"todo" ~cycle:ncyc
        ~commit:None ~verdict:None ~reason ~id () in
      finish ns line
  | _ -> usage ("unknown edge: " ^ edge)

(* ---------- diagram (mvp.4) ---------- *)
(* Read-only: renders the quest_view rollup snapshot at
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

let do_diagram quest tail =
  check_slug quest;
  let fmt = parse_diagram_flags tail in
  let (view, _, _, _) = quest_view quest in
  let fields = match view with `Assoc fs -> fs | _ -> [] in
  let generated_at = now_ts () in
  (match fmt with
   | "ascii" -> print_string (emit_ascii fields generated_at)
   | "mermaid" -> print_string (emit_mermaid fields generated_at)
   | _ ->
       print_verdict ~fmt:"json" (`Assoc [
         ("ok", `Bool true); ("quest", json_str quest);
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
      `Assoc (fs @ [("quest", json_str rc.Config.rc_quest);
                    ("node", json_str rc.Config.rc_node);
                    ("source", json_str source);
                    ("source_rung", json_str source);
                    ("context", Config.resolved_context_json rc source)])
  | other -> other

let do_e_bare (rc : Config.run_config) source =
  let quest = rc.Config.rc_quest and node = rc.Config.rc_node in
  let (state, legal) =
    match fold_node quest node with
    | Some (_, s, _) -> (json_str s.st, List.map json_str (legal_edges s.st))
    | None -> (`Null, []) in
  let thresholds =
    match Config.config_dir () with
    | Some dir -> Config.thresholds_json (Config.load_thresholds dir)
    | None -> Config.thresholds_json Config.default_thresholds in
  `Assoc [("ok", `Bool true);
          ("quest", json_str quest);
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
           let v = do_update rc.Config.rc_quest rc.Config.rc_node edge fl id in
           print_verdict ~fmt:fl.fmt (with_context v rc ctx_source); 0
       | None -> no_context ctx_amb)

(* ---------- node door (rename.1: bp3 n) ---------- *)
(* Claimed shorthand: reads the claimed run's node, resolved
   exactly like the e door (session rung, then desk rung). *)
let do_n ctx_rc ctx_source ctx_amb = function
  | [] | ["r"] | ["read"] ->
      (match ctx_rc with
       | Some rc ->
           let quest = rc.Config.rc_quest and node = rc.Config.rc_node in
           (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
           (match fold_node quest node with
            | None -> not_found "node" node
            | Some (_, s, text) ->
                print_verdict ~fmt:"json"
                  (with_context
                     (node_verdict quest node s (deps_of_text text)
                        (timing_of_text text)) rc ctx_source); 0)
       | None -> no_context ctx_amb)
  | _ -> usage "node door verbs are r"

(* ---------- main dispatch ---------- *)
(* icebox door: bp3 q icebox r [term...] | r <slug> (read-only) *)
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
let help_q = "bp3 q - quest/node state. Doors:\n\
  bp3 q c|r|d ...              quest door (create, read, delete)\n\
  bp3 q <quest> c|r|u|d ...    node door for one quest\n\
  bp3 q <quest> n <node> r     read one node (canonical nested address)\n\
  bp3 q <quest> n <node> e <edge> [flags]   take one node's edge (canonical nested address)\n\
  bp3 q <quest> n <node> " ^ Names.verb_brief ^ " [" ^ Names.flag_desk ^ " <path>]   the grader's cold brief for a handed_off node, rendered from the bound commit\n\
  bp3 q <quest> diagram ...    generated quest diagram from the live rollup (mvp.4)\n\
  bp3 q <quest> metrics r|scrape   what each grade and author cycle cost (metric-collectors)\n\
  bp3 q icebox r [term...]     search frozen icebox entries (read-only)\n\
  bp3 n [r]                    claimed node door: read the claimed run's node (rename.1)\n\
  bp3 e [<edge> ...]           claimed edge door: resolved context, no names typed (mvp.2)\n\
  bp3 harness desk <verb> ...  desks (machine-local); bp3 worktree is its documented alias\n\
  bp3 config [--source]        view the machine-local config store (<git-common-dir>/bp3/)\n\
  bp3 warden [<quest>] [...]   two-layer deterministic plug audit (git + session traces, read-only)\n\
  bp3 q hooks                  harness hook emitter (fail-open)\n\
Run bp3 q <door> -h for that door's verbs, edges, and flags.\n"

let help_quest_door = "bp3 q <quest door> - verbs:\n\
  bp3 q c <quest> [--type <goal_type>] [--depends-on <a,b>]   create a quest\n\
  bp3 q r [<quest>] [--format json|table|tree]                 list quests, or read one\n\
  bp3 q d <quest> --reason <why>                               delete a quest\n\
Long forms: create, read, delete. Example: bp3 q c my-quest --type default\n"

let help_node_door = "bp3 q <quest> <node door> - verbs:\n\
  bp3 q <quest> c <node> [--type <node_type>] [--depends-on <a,b>]   create an node, deps name nodes in the same quest\n\
  bp3 q <quest> r [<node>] [--format json|table|tree]           read the quest, or one node\n\
  bp3 q <quest> u <node> <edge> [flags]                         take an FSM edge (see u -h)\n\
  bp3 q <quest> d <node> --reason <why>                         delete an node\n\
  bp3 q <quest> dep <node> --depends-on <a,b> --reason <why>    redeclare an node's deps (mutable-but-logged)\n\
  bp3 q <quest> diagram [--format ascii|mermaid|json]          generated diagram from the live rollup (see diagram -h)\n\
Long forms: create, read, update, delete. Example: bp3 q my-quest r node-1\n"

let help_dep = "bp3 q <quest> dep <node> - redeclare an node's node deps (mvp.3):\n\
  bp3 q <quest> dep <node> --depends-on <a,b> --reason <why>   set deps; --depends-on \"\" clears them\n\
  Deps name nodes in the same quest, are read back from the node ledger, and a cycle refuses at write time (E_DEP_CYCLE) naming the cycle. The dep line is logged with the node state and cycle, so a mid-flight edit stays on the record.\n\
Example: bp3 q my-quest dep node-2 --depends-on node-1 --reason \"needs node-1 first\"\n"

let help_diagram = "bp3 q <quest> diagram - generated quest diagram from the live rollup (mvp.4):\n\
  bp3 q <quest> diagram [--format ascii|mermaid|json]   emit the diagram (default ascii)\n\
  Nodes carry state and cycle (landed nodes carry node_fin), deps are drawn once, todo nodes are grouped into ready-set waves, and a blocked node names the dependents it starves. Output is generated at call time from live state; its header carries the rollup timestamp (generated_at). ascii suits terminals and records, mermaid suits rendered docs, json carries the same facts plus both texts for diffing.\n\
Example: bp3 q my-quest diagram --format mermaid\n"

(* ---------- metrics door (metric-collectors sink.1) ---------- *)
let do_metrics quest tail =
  check_slug quest;
  if fold_quest quest = None then not_found "quest" quest;
  (* --claude-dir, --pi-dir, and --agy-dir each replace their own default set *)
  let rec dirs (cl, pi, agy) = function
    | [] -> (List.rev cl, List.rev pi, List.rev agy)
    | "--claude-dir" :: d :: rest -> dirs (d :: cl, pi, agy) rest
    | "--pi-dir" :: d :: rest -> dirs (cl, d :: pi, agy) rest
    | "--agy-dir" :: d :: rest -> dirs (cl, pi, d :: agy) rest
    | [ ("--claude-dir" | "--pi-dir" | "--agy-dir") as f ] -> usage (f ^ " needs a value")
    | f :: _ -> usage ("unknown metrics scrape argument: " ^ f) in
  match tail with
  | [ ("r" | "read") ] -> print_verdict ~fmt:"json" (Metrics_io.view quest); 0
  | "scrape" :: rest ->
      let (cl, pi, agy) = dirs ([], [], []) rest in
      let ds = match cl with [] -> Metrics_io.default_dirs () | ds -> ds in
      let pds = match pi with [] -> Metrics_io.default_pi_dirs () | ds -> ds in
      let ads = match agy with [] -> Metrics_io.default_agy_dirs () | ds -> ds in
      let (v, rc) = Metrics_io.scrape_view quest ~dirs:ds ~pi_dirs:pds ~agy_dirs:ads () in
      print_verdict ~fmt:"json" v; rc
  | _ -> usage "metrics verbs are r and scrape"

let help_metrics = "bp3 q <quest> metrics - what each grade and author cycle cost (metric-collectors):\n\
  bp3 q <quest> metrics r                              samples per node, cycle, and kind (grade, author)\n\
  bp3 q <quest> metrics scrape [--claude-dir <dir>]... [--pi-dir <dir>]... [--agy-dir <dir>]...   collect from Claude Code, pi, and agy transcripts; idempotent\n\
  Samples live in metrics.jsonl on each node's state branch (GENERATED, written only here); a second scrape writes nothing new. Without --claude-dir, scrape reads ~/.claude/projects/<this repo's dir and its desks>; without --pi-dir, ~/.pi/agent/sessions/<the same, by pi's naming>; without --agy-dir, ~/.gemini/antigravity-cli/brain. A pi or agy grade has no harness report: one whose usage adds up counts as self_checked. Exit 1 when a number could not be checked and was not written: a grade transcript that disagrees with the harness report or fails its self-check (mismatched), or an author window holding a usage-less line (author_bad_usage).\n\
Example: bp3 q my-quest metrics scrape && bp3 q my-quest metrics r\n"

let help_update = "bp3 q <quest> u <node> <edge> - edges and their flags:\n\
  edges: handoff grade verify land block resume\n\
  handoff --commit <sha> --reason <why>    bind a clean commit for grade\n\
  grade  --verdict ship|needs_fix [--verify-verdict pass|fail] [--mechanical] --reason <why>   one combined cast (pure-grade); --mechanical never blocks\n\
  verify --verdict pass|fail [--mechanical] --reason <why>\n\
  land   --reason <why>                    land an approved node\n\
  block  --reason <why>                    park for a human decision\n\
  resume --reason <why>                    human only: unblock\n\
Shared flags: --format json|table|tree, --target <name>.\n\
Example: bp3 q my-quest u node-1 handoff --commit abc123 --reason \"ready\"\n"

let help_e = "bp3 e - claimed edge door (mvp.2): context is resolved, never carried:\n\
  bp3 e                                    print the resolved context, its source rung (session|desk), state, and legal edges\n\
  bp3 e <edge> [flags]                     take the claimed run's edge: handoff grade verify land block resume (same flags as bp3 q <quest> u <node> <edge>)\n\
  Resolution: session claim first, desk context second, checked against cwd; no rung refuses E_NO_CONTEXT, an ambiguous desk refuses E_NO_CONTEXT naming the live run_ids. Env BP3_RUN_ID is a hint only: a mismatch warns W_CONTEXT_ENV_MISMATCH and the claim wins; an unclaimed explicit edge call warns W_CONTEXT_UNCLAIMED.\n\
Example: bp3 e handoff --commit abc123 --reason \"ready\"\n"

let help_n = "bp3 n - claimed node door (rename.1): context is resolved, never carried:\n\
  bp3 n [r]                        read the claimed run's node (same resolution as bp3 e: session claim first, desk context second)\n\
  No rung resolving refuses E_NO_CONTEXT; address the call explicitly with bp3 q <quest> n <node> r instead.\n\
Example: bp3 n r\n"

let help_icebox = "bp3 q icebox r - search frozen icebox entries (read-only):\n\
  bp3 q icebox r [term...] [--format json|table|tree]   list entries matching all terms\n\
  bp3 q icebox r <slug>                                 print one entry in full\n\
Example: bp3 q icebox r table completion\n"

let help_worktree = "bp3 worktree - documented alias of bp3 harness desk, machine-local desks, never ledgered:\n\
  verbs: derive, create, inspect, remove, prepare, check, exit, release, list\n\
  bp3 harness desk prepare <quest> <node> --run <run-id> [--commit <sha>] [--path <dir>]\n\
  bp3 harness desk list [--quest <quest>]\n\
Example: bp3 harness desk prepare my-quest node-1 --run R1\n"

let help_warden = "bp3 warden - two-layer deterministic plug audit (git + session traces, read-only):\n\
  bp3 warden [<quest>] [--last N|--all] [--no-sessions] [--format json|table]\n\
    [--dir <claude-dir>] [--pi-dir <pi-dir>] [--agy-dir <agy-dir>]\n\
  With <quest>, audits that quest (always, even if FEEDBACK.md exists).\n\
  With no <quest>, runs repo checks (>1 active quest, leaked desks) plus the last N (default 5)\n\
  unreviewed real quests (with docs/quests/<q>/QUEST.md and no FEEDBACK.md); --all sweeps all real quests.\n\
  Layer 2 (session traces) auto-enables when local Claude/Pi/agy transcripts match; --no-sessions runs Layer 1 only.\n\
  Always read-only; exit 0 on clean read (findings are evidence, never a gate), exit 2 on usage/not-found.\n\
Example: bp3 warden 2026-11-22-induct-inline-as-default-measure-author --format table\n"

let do_warden rest =
  if List.exists is_help rest then (print_string help_warden; 0)
  else
    let rec parse pos last_n all_flag no_sessions fmt dirs pi_dirs agy_dirs = function
      | [] -> (List.rev pos, last_n, all_flag, no_sessions, fmt, List.rev dirs, List.rev pi_dirs, List.rev agy_dirs)
      | "--all" :: tl -> parse pos last_n true no_sessions fmt dirs pi_dirs agy_dirs tl
      | "--no-sessions" :: tl -> parse pos last_n all_flag true fmt dirs pi_dirs agy_dirs tl
      | "--last" :: n :: tl ->
          (match int_of_string_opt n with
           | Some k when k >= 1 -> parse pos (Some k) all_flag no_sessions fmt dirs pi_dirs agy_dirs tl
           | _ -> usage ("--last must be a positive integer: " ^ n))
      | [ "--last" ] -> usage "--last needs a value"
      | "--format" :: f :: tl ->
          if f <> "json" && f <> "table" then usage ("--format must be json or table: " ^ f);
          parse pos last_n all_flag no_sessions f dirs pi_dirs agy_dirs tl
      | [ "--format" ] -> usage "--format needs a value"
      | s :: tl when String.starts_with ~prefix:"--format=" s ->
          let f = String.sub s 9 (String.length s - 9) in
          if f <> "json" && f <> "table" then usage ("--format must be json or table: " ^ f);
          parse pos last_n all_flag no_sessions f dirs pi_dirs agy_dirs tl
      | ("--dir" | "--claude-dir") :: d :: tl ->
          parse pos last_n all_flag no_sessions fmt (d :: dirs) pi_dirs agy_dirs tl
      | "--pi-dir" :: d :: tl ->
          parse pos last_n all_flag no_sessions fmt dirs (d :: pi_dirs) agy_dirs tl
      | "--agy-dir" :: d :: tl ->
          parse pos last_n all_flag no_sessions fmt dirs pi_dirs (d :: agy_dirs) tl
      | [ ("--dir" | "--claude-dir" | "--pi-dir" | "--agy-dir") as f ] -> usage (f ^ " needs a value")
      | f :: _ when String.length f > 0 && f.[0] = '-' -> usage ("unknown warden flag: " ^ f)
      | p :: tl -> parse (p :: pos) last_n all_flag no_sessions fmt dirs pi_dirs agy_dirs tl in
    let (pos, last_n, all_flag, no_sessions, fmt, dirs, pi_dirs, agy_dirs) =
      parse [] None false false "json" [] [] [] rest in
    let quest_opt = match pos with
      | [] -> None
      | [ q ] -> Some q
      | _ -> usage "bp3 warden takes at most one <quest>" in
    if quest_opt <> None && (all_flag || last_n <> None) then
      usage "pass either <quest> or --last/--all, not both";
    if all_flag && last_n <> None then
      usage "pass either --last or --all, not both";
    let (scope, quests) = match quest_opt with
      | Some q ->
          check_slug q;
          if fold_quest q = None then not_found "quest" q;
          ("quest", [ q ])
      | None ->
          let last = Option.value last_n ~default:5 in
          ("repo", Warden_io.select_real_quests ~last ~all:all_flag) in
    let ev = Warden_io.load ~scope ~quests ~no_sessions ~dirs ~pi_dirs ~agy_dirs in
    let findings = Warden.run ev in
    if fmt = "table" then print_string (Warden.to_table ev findings)
    else print_endline (Yojson.Safe.to_string (Warden.to_json ev findings));
    0

let help_config = "bp3 config - view the machine-local bp3 config store (<git-common-dir>/bp3/, never committed):\n\
  bp3 config [--source] [--format json|table]   thresholds plus contexts folded from runs/<run_id>.json\n\
  config.json holds machine settings only (thresholds: setup_slow_s, depth_cap); contexts are views, never stored there. The depth cap is enforced at link mint (mvp.1, E_DEPTH); W_SETUP_SLOW fires on the quest rollup when a claimed Run's setup_wall_s exceeds setup_slow_s (mvp.3, local only). First call on a fresh repo creates the store with defaults (zero setup), and every view rebuilds the derived by-session index from runs/, so deleting by-session/ loses nothing. --source names the writing verb and timestamp per context. Outside a git repo there is no store and the call refuses E_NOT_FOUND.\n\
Example: bp3 config --source\n"

(* Node 5 guard: an older-MAJOR binary never writes in a newer repo.
   Newer MINOR/PATCH only warns (warnings_of carries W_VERSION_AHEAD).
   guard.1: it runs at the write itself (Gitx.write_guard, set at entry),
   so no command shape can skip it; a call that writes nothing never
   reaches it. *)
let refuse_major_ahead () =
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
    | "init-repo" :: _ | "warden" :: _ | [] -> false
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
    | "q" :: _q :: v :: _n :: _edge :: _ when is_verb v && normalize_verb v = "u" -> true
    | "q" :: _q :: "n" :: _n :: "e" :: _edge :: _ -> true
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
  match argv with
  | "-h" :: _ | "--help" :: _ -> print_string help_q; 0
  | "--version" :: _ -> print_endline bp3_version; 0
  | "q" :: (h :: _) when is_help h -> print_string help_q; 0
  | "q" :: rest -> run rest
  | "n" :: (h :: _) when is_help h -> print_string help_n; 0
  | "n" :: rest -> do_n ctx_rc ctx_source ctx_amb rest
  | "harness" :: rest -> Harness.run rest
  | "config" :: (h :: _) when is_help h -> print_string help_config; 0
  | "config" :: rest ->
      let (source, fmt) = parse_config_flags rest in
      print_verdict ~fmt (Config.view ~source); 0
  | "warden" :: rest -> do_warden rest
  | "e" :: (h :: _) when is_help h -> print_string help_e; 0
  | "e" :: _edge :: (h :: _) when is_help h -> print_string help_e; 0
  | "e" :: rest -> do_e ctx_rc ctx_source ctx_amb id rest
  | "worktree" :: (h :: _) when is_help h -> print_string help_worktree; 0
  | "icebox" :: (h :: _) when is_help h -> print_string help_icebox; 0
  | "icebox" :: ("r" | "read") :: (h :: _) when is_help h -> print_string help_icebox; 0
  | first :: (h :: _) when is_verb first && is_help h -> print_string help_quest_door; 0
  | _quest :: (h :: _) when is_help h -> print_string help_node_door; 0
  | _quest :: verb_raw :: (h :: _) when is_verb verb_raw && is_help h ->
      print_string (if normalize_verb verb_raw = "u" then help_update else help_node_door); 0
  | "worktree" :: rest ->
      (* documented alias of harness desk (mvp.6): same store,
         same verdicts; new callers use bp3 harness desk *)
      print_verdict ~fmt:"json" (Worktree.run rest); 0
  | "init-repo" :: _ ->
      (* Node 6: scaffold plans/ into the caller's repo; never clobber differing plans *)
      let plans = [("plans/default.yaml", "goal_type: default\nmax_cycles: 10\ngrade:\n  required: true\nverify: required\n");
                   ("plans/direct.yaml", "goal_type: direct\nmax_cycles: 0\ngrade:\n  required: false\nverify: required\n")] in
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
       | "c", quest :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in quest create";
           let v = do_quest_create quest fl id in print_verdict ~fmt:fl.fmt v; 0
       | "c", [] -> usage "quest create needs a quest name"
       | "r", [] ->
           let qs = List.map (fun q ->
             let (view, _, _, _) = quest_view q in view) (list_quests ()) in
           print_verdict ~fmt:"json" (`Assoc [("ok", `Bool true); ("quests", `List qs)]); 0
       | "r", [quest] ->
           let (pos, fl) = ( [quest], { reason=None; commit=None; verdict=None; target=None; typ=None; depends_on=None; fmt="json"; verify_verdict=None; mechanical=false } ) in
           ignore pos;
           (* re-parse: quest may be followed by --format in original rest; handled below *)
           ignore fl;
           let (view, _, _, _) = quest_view quest in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []))); 0
       | "r", quest :: tail ->
           let (pos, fl) = split_flags (quest :: tail) in
           (match pos with
            | [q] ->
                let (view, _, _, _) = quest_view q in
                print_verdict ~fmt:fl.fmt (`Assoc (("ok", `Bool true) ::
                  (match view with `Assoc fs -> fs | _ -> []))); 0
            | _ -> usage "quest read takes at most one quest")
       | "d", quest :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in quest delete";
           let v = do_quest_delete quest fl id in print_verdict ~fmt:fl.fmt v; 0
       | "d", [] -> usage "quest delete needs a quest name"
       | _ -> usage "quest door verbs are c, r, d")
  | _q :: "diagram" :: (h :: _) when is_help h -> print_string help_diagram; 0
  | quest :: "diagram" :: tail -> do_diagram quest tail
  | _q :: "metrics" :: (h :: _) when is_help h -> print_string help_metrics; 0
  | _q :: "metrics" :: _ :: (h :: _) when is_help h -> print_string help_metrics; 0
  | quest :: "metrics" :: tail -> do_metrics quest tail
  | _q :: "dep" :: (h :: _) when is_help h -> print_string help_dep; 0
  | quest :: "dep" :: node :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in dep";
      let v = do_node_dep quest node fl id in print_verdict ~fmt:fl.fmt v; 0
  | _g :: "n" :: (h :: _) when is_help h -> print_string help_node_door; 0
  | quest :: "n" :: ("c" | "create") :: node :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in node create";
      let v = do_node_create quest node fl id in print_verdict ~fmt:fl.fmt v; 0
  | quest :: "n" :: node :: ("r" | "read") :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in node read";
      (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
      (match fold_node quest node with
       | None -> not_found "node" node
       | Some (_, s, text) ->
           print_verdict ~fmt:fl.fmt
             (node_verdict quest node s (deps_of_text text) (timing_of_text text)); 0)
  | quest :: "n" :: node :: v :: tail when v = Names.verb_brief ->
      print_verdict ~fmt:"json" (do_brief quest node tail); 0
  | quest :: "n" :: node :: "e" :: edge :: tail ->
      let (pos, fl) = split_flags tail in
      if pos <> [] then usage "stray positional in nested edge";
      let v = do_update quest node edge fl id in
      let v = match ctx_rc with
        | Some rc -> with_context v rc ctx_source | None -> v in
      print_verdict ~fmt:fl.fmt v; 0
  | quest :: "n" :: node :: [] ->
      (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
      (match fold_node quest node with
       | None -> not_found "node" node
       | Some (_, s, text) ->
           print_verdict ~fmt:"json"
             (node_verdict quest node s (deps_of_text text) (timing_of_text text)); 0)
  | quest :: verb_raw :: rest when is_verb verb_raw ->
      let verb = normalize_verb verb_raw in
      (match verb, rest with
       | "c", node :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in node create";
           let v = do_node_create quest node fl id in print_verdict ~fmt:fl.fmt v; 0
       | "c", [] -> usage "node create needs an node name"
       | "r", [] ->
           let (view, _, _, _) = quest_view quest in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []))); 0
       | "r", [node] ->
           (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
           (match fold_node quest node with
            | None -> not_found "node" node
            | Some (_, s, text) -> print_verdict ~fmt:"json" (node_verdict quest node s (deps_of_text text) (timing_of_text text)); 0)
       | "r", node :: tail ->
           let (pos, fl) = split_flags (node :: tail) in
           (match pos with
            | [e] ->
                (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
                (match fold_node quest e with
                 | None -> not_found "node" e
                 | Some (_, s, text) -> print_verdict ~fmt:fl.fmt (node_verdict quest e s (deps_of_text text) (timing_of_text text)); 0)
            | _ -> usage "node read takes at most one node")
       | "u", node :: edge :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in update";
           let v = do_update quest node edge fl id in
           let v = match ctx_rc with
             | Some rc -> with_context v rc ctx_source | None -> v in
           print_verdict ~fmt:fl.fmt v; 0
       | "u", _ -> usage "update needs <node> <edge>"
       | "d", node :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in node delete";
           let v = do_node_delete quest node fl id in print_verdict ~fmt:fl.fmt v; 0
       | "d", [] -> usage "node delete needs an node name"
       | _ -> usage "node door verbs are c, r, u, d")
  | _ -> usage "expected: bp3 q c|r|d ... or bp3 q <quest> c|r|u|d ... (see bp3 q -h)"

let () =
  let argv = List.tl (Array.to_list Sys.argv) in
  Gitx.write_guard := refuse_major_ahead;
  try exit (run argv)
  with Verdict (code, v) ->
    print_endline (Yojson.Safe.to_string (stamp_run_id v));
    exit code


