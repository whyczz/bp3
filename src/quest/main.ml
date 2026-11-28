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

let illegal_for kind state edge =
  err Names.e_illegal_edge
    (`Assoc [("state", json_str state); ("edge", json_str edge);
             ("legal_edges", `List (List.map json_str (legal_edges_for kind state)))])
    "Pick a legal edge from legal_edges for the current state." 1

let illegal state edge = illegal_for Code state edge

(* ---------- operations ---------- *)
let do_quest_create quest fl id =
  check_creatable quest;
  let qtype = (match fl.typ with Some t -> t | None -> "default") in
  let _ = quest_knobs qtype in
  if ref_tip (quest_branch quest) <> None then
    err Names.e_exists (`Assoc [("quest", json_str quest)]) "Quest already exists." 1;
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

let rec ensure_dir dir =
  if dir = "" || dir = "." || dir = "/" || Sys.file_exists dir then ()
  else begin
    ensure_dir (Filename.dirname dir);
    try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let do_quest_create_from_file quest_opt file_path fl id =
  if not (Sys.file_exists file_path) then
    err Names.e_not_found (`Assoc [("file", json_str file_path)])
      ("Spec file not found: " ^ file_path) 1;
  let raw = read_file_or file_path "" in
  let spec = match Quest_spec.parse_string raw with
    | Ok s -> s
    | Error errs ->
        err Names.e_invalid_spec
          (`Assoc [("file", json_str file_path); ("errors", `List (List.map json_str errs))])
          ("Invalid quest.json: " ^ String.concat "; " errs) 1 in
  (match quest_opt with
   | Some q when q <> spec.Quest_spec.quest ->
       let msg = Printf.sprintf "CLI quest %s disagrees with quest.json quest %s" q spec.quest in
       err Names.e_invalid_spec
         (`Assoc [("file", json_str file_path); ("errors", `List [json_str msg])])
         msg 1
   | _ -> ());
  let quest = spec.Quest_spec.quest in
  check_creatable quest;
  let qtype = match fl.typ with Some t -> t | None -> spec.goal_type in
  ignore (quest_knobs qtype);
  let extra_deps = match fl.depends_on with
    | Some s when s <> "" -> String.split_on_char ',' s |> List.map String.trim
    | _ -> [] in
  let qdeps =
    List.fold_right (fun d acc -> if d = "" || List.mem d acc then acc else d :: acc)
      (spec.depends_on @ extra_deps) [] in
  List.iter check_slug qdeps;
  if ref_tip (quest_branch quest) <> None then
    err Names.e_exists (`Assoc [("quest", json_str quest)]) "Quest already exists." 1;
  List.iter (fun (n : Quest_spec.node_spec) ->
    if ref_tip (node_branch quest n.id) <> None then
      err Names.e_exists (`Assoc [("quest", json_str quest); ("node", json_str n.id)])
        "Node already exists." 1) spec.nodes;
  let ordered = match Quest_spec.topo_sort spec.nodes with
    | Ok xs -> xs
    | Error errs ->
        err Names.e_invalid_spec
          (`Assoc [("file", json_str file_path); ("errors", `List (List.map json_str errs))])
          ("Invalid quest.json: " ^ String.concat "; " errs) 1 in
  let head = head_sha () in
  let qpath = quest_dir quest ^ "/" ^ Layout.quest_file in
  let qjpath = quest_json_path quest in
  let quest_md = match git_show head qpath with
    | Some c -> c
    | None -> Quest_spec.render_quest_md spec in
  let qline = ledger_line ~edge:"create" ~from:"" ~to_:"proposed" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("goal_type", json_str qtype);
            ("spec_file", json_str file_path);
            ("depends_on", `List (List.map json_str qdeps))] () in
  let existing_ledger = git_show head (quest_ledger_path quest) in
  let qledger = (match existing_ledger with Some t when String.trim t <> "" -> t ^ (if t.[String.length t-1] = '\n' then "" else "\n") | _ -> "") ^ qline ^ "\n" in
  let qtip = create_branch_commit ~branch:(quest_branch quest) ~base_tip:head
    ~files:[(qpath, quest_md); (qjpath, raw); (quest_ledger_path quest, qledger)]
    ~msg:("bp3: create quest " ^ quest) in
  let node_summaries = List.map (fun (n : Quest_spec.node_spec) ->
    let st = { (fresh_state ()) with
               node_kind = n.kind;
               explore_target = n.target;
               explore_max_iterations = n.max_iterations } in
    let explore_extra =
      if n.kind = Explore then
        (match n.target with Some t -> [("target", json_str t)] | None -> []) @
        (match n.max_iterations with Some m -> [("max_iterations", `Int m)] | None -> [])
      else [] in
    let nline = ledger_line ~edge:"create" ~from:"" ~to_:"todo" ~cycle:1
      ~commit:None ~verdict:None ~reason:"" ~id
      ~extra:([("node_type", json_str "default");
               ("node_kind", json_str (node_kind_to_string n.kind));
               ("depends_on", `List (List.map json_str n.depends_on))] @ explore_extra) () in
    ignore (create_branch_commit ~branch:(node_branch quest n.id) ~base_tip:qtip
      ~files:[(node_ledger_path quest n.id, nline ^ "\n");
              (node_state_path quest n.id, state_yaml quest n.id st)]
      ~msg:("bp3: create node " ^ n.id));
    let base = [
      ("node", json_str n.id);
      ("kind", json_str (node_kind_to_string n.kind));
      ("state", json_str "todo");
      ("deps", `List (List.map json_str n.depends_on));
      ("legal_edges", `List (List.map json_str (legal_edges_for n.kind "todo")));
    ] in
    let extra = if n.kind = Explore then [("explore", explore_json st)] else [] in
    `Assoc (base @ extra)) ordered in
  let scaffolded =
    if not fl.scaffold then []
    else
      let wrote = ref [] in
      let write_if_absent rel content =
        let full = Filename.concat (current_root ()) rel in
        if not (Sys.file_exists full) then begin
          ensure_dir (Filename.dirname full);
          let oc = open_out_bin full in
          Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc content);
          wrote := rel :: !wrote
        end in
      write_if_absent qpath (Quest_spec.render_quest_md spec);
      List.iter (fun (n : Quest_spec.node_spec) ->
        write_if_absent (node_dir quest n.id ^ "/NODE.md") (Quest_spec.render_node_md spec n)) ordered;
      List.rev !wrote in
  with_warnings id true [
    ("ok", `Bool true); ("quest", json_str quest); ("state", json_str "proposed");
    ("spec", json_str file_path); ("nodes", `List node_summaries);
    ("scaffolded", `List (List.map json_str scaffolded));
  ]

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
    err Names.e_human_required (`Assoc [("quest", json_str quest)])
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
      err Names.e_dep_cycle (`Assoc [("quest", json_str quest); ("node", json_str self);
        ("cycle", `List (List.map json_str cyc))])
        "Dep cycle refused at write time; break the named cycle." 1
  | None -> ()

let do_node_create quest node fl id =
  check_slug quest; check_creatable node;
  let qt = match fold_quest quest with
    | Some (_, _, qt, _, _) -> qt
    | None -> not_found "quest" quest in
  let etype = (match fl.typ with Some t -> t | None -> "default") in
  (* validate node plan exists for non-default *)
  ignore (effective_knobs ~quest_type:qt ~node_type:etype);
  let nkind = match fl.kind with
    | None -> if qt = "direct" || etype = "direct" then Direct else Code
    | Some k ->
        (match node_kind_of_string k with
         | Some nk -> nk
         | None -> usage ("invalid --kind: " ^ k ^ " (expected code, direct, research, explore, or human-gate)")) in
  let explore_target =
    if nkind = Explore then
      (match fl.target with
       | Some t when String.trim t <> "" -> Some (String.trim t)
       | _ -> usage "--target is required for --kind explore")
    else fl.target in
  let explore_max = if nkind = Explore then fl.max_iterations else None in
  if ref_tip (node_branch quest node) <> None then
    err Names.e_exists (`Assoc [("quest", json_str quest); ("node", json_str node)]) "Node already exists." 1;
  let deps = parse_dep_list fl.depends_on in
  validate_deps quest node deps;
  let qtip = (match ref_tip (quest_branch quest) with Some t -> t | None -> not_found "quest" quest) in
  let st = { (fresh_state ()) with
             node_kind = nkind;
             explore_target;
             explore_max_iterations = explore_max } in
  let explore_extra =
    if nkind = Explore then
      (match explore_target with Some t -> [("target", json_str t)] | None -> []) @
      (match explore_max with Some m -> [("max_iterations", `Int m)] | None -> [])
    else [] in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"todo" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:([("node_type", json_str etype);
             ("node_kind", json_str (node_kind_to_string nkind));
             ("depends_on", `List (List.map json_str deps))] @ explore_extra) () in
  let _ = create_branch_commit ~branch:(node_branch quest node) ~base_tip:qtip
    ~files:[(node_ledger_path quest node, line ^ "\n");
            (node_state_path quest node, state_yaml quest node st)]
    ~msg:("bp3: create node " ^ node) in
  let extra_res = if nkind = Explore then [("explore", explore_json st)] else [] in
  with_warnings id true ([("ok", `Bool true); ("quest", json_str quest);
    ("node", json_str node); ("kind", json_str (node_kind_to_string nkind));
    ("state", json_str "todo"); ("cycle", `Int 1);
    ("deps", `List (List.map json_str deps));
    ("legal_edges", `List (List.map json_str (legal_edges_for nkind "todo")))] @ extra_res)

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
         ("legal_edges", `List (List.map json_str (legal_edges_for s.node_kind s.st)))]
   | None -> not_found "node" node)

let do_node_delete quest node fl id =
  check_slug quest; check_slug node;
  let reason = require_reason fl in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  (match fold_node quest node with
   | None -> not_found "node" node
   | Some (_, s, _) ->
       if s.st = "landed" || s.st = "deleted" then illegal_for s.node_kind s.st "delete";
       if s.st = "blocked" && not id.decider_human then
         err Names.e_human_required (`Assoc [("quest", json_str quest); ("node", json_str node)])
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
          (`Assoc [("state", json_str s.st); ("legal_edges", `List (List.map json_str (legal_edges_for s.node_kind s.st)))])
          "A brief exists only for a commit waiting on its grade; re-read the node." 1) in
  let i = Brief.inputs ~quest ~node ~cycle:s.cycle ~commit ~upto:None in
  `Assoc [("ok", `Bool true); ("quest", json_str quest); ("node", json_str node);
          ("cycle", `Int s.cycle); ("commit", json_str commit);
          ("brief", json_str (Brief.render ?desk i))]

let do_update quest node edge fl id =
  check_slug quest; check_slug node;
  if not (List.mem edge ["handoff"; "grade"; "land"; "approve"; "iterate"; "block"; "resume"]) then
    usage ("unknown edge: " ^ edge);
  let reason =
    if edge = "iterate" then
      (match fl.note with
       | Some n when n <> "" -> n
       | _ -> (match fl.reason with Some r when r <> "" -> r | _ -> usage "--note or --reason is required for iterate"))
    else require_reason fl in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let (_, s, _) = (match fold_node quest node with Some v -> v | None -> not_found "node" node) in
  let (_, qt, deps) = (match fold_quest quest with Some (_, _, a, b, _) -> ((), a, b) | None -> not_found "quest" quest) in
  let knobs = effective_knobs ~quest_type:qt ~node_type:s.node_type in
  let finish ns line =
    ignore (append_node_line quest node line ns);
    with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
      ("node", json_str node); ("kind", json_str (node_kind_to_string ns.node_kind));
      ("state", json_str ns.st); ("cycle", `Int ns.cycle);
      ("commit", (match ns.last_commit with Some c -> json_str c | None -> `Null));
      ("legal_edges", `List (List.map json_str (legal_edges_for ns.node_kind ns.st)))] in
  let land_and_advance ~from_state ~ns ~edge ~verdict ?extra ?(result_extra = []) () =
    let ns_landed = { ns with st = "landed" } in
    let line = ledger_line ~edge ~from:from_state ~to_:"landed" ~cycle:ns.cycle
      ~commit:ns.last_commit ~verdict ~reason ~id ?extra () in
    ignore (append_node_line quest node line ns_landed);
    let node_tip = (match ref_tip (node_branch quest node) with Some t -> t | None -> "") in
    let qbranch = quest_branch quest in
    let qtip = (match ref_tip qbranch with Some t -> t | None -> "") in
    let landed_verdict () =
      with_warnings id true ([("ok", `Bool true); ("quest", json_str quest);
        ("node", json_str node); ("kind", json_str (node_kind_to_string ns.node_kind));
        ("state", json_str "landed"); ("fin", json_str "node_fin"); ("cycle", `Int ns.cycle);
        ("commit", (match ns.last_commit with Some c -> json_str c | None -> `Null));
        ("legal_edges", `List [])] @ result_extra) in
    if is_ancestor qtip node_tip then begin
      if not (move_ref ~branch:qbranch ~new_tip:node_tip ~expect_tip:qtip) then
        err Names.e_stale_world (`Assoc []) "Quest tip moved; re-read and retry." 1;
      landed_verdict ()
    end else begin
      let tree_out, code = git_out ["merge-tree"; "--write-tree"; qtip; node_tip] in
      let tree = (match String.split_on_char '\n' tree_out with t :: _ -> String.trim t | [] -> "") in
      if code <> 0 || tree = "" then begin
        let ns2 = { ns with st = "todo"; grade_ok = false; verify_ok = false } in
        let line2 = ledger_line ~edge:"land" ~from:"landed" ~to_:"todo" ~cycle:ns.cycle
          ~commit:ns.last_commit ~verdict:None ~reason ~id () in
        ignore (append_node_line quest node line2 ns2);
        `Assoc [("ok", `Bool true); ("quest", json_str quest); ("node", json_str node);
          ("state", json_str "todo"); ("cycle", `Int ns.cycle);
          ("facts", `Assoc [("land_conflict", `Bool true)]);
          ("legal_edges", `List (List.map json_str (legal_edges_for ns.node_kind "todo")))]
      end else begin
        let mtip, _ = git_out ~input:("bp3: land " ^ node)
            ["commit-tree"; tree; "-p"; qtip; "-p"; node_tip] in
        if not (move_ref ~branch:qbranch ~new_tip:mtip ~expect_tip:qtip) then
          err Names.e_stale_world (`Assoc []) "Quest tip moved; re-read and retry." 1;
        landed_verdict ()
      end
    end in
  match edge with
  | "handoff" ->
      if s.st <> "todo" || s.node_kind = Human_gate then illegal_for s.node_kind s.st edge;
      let raw = (match fl.commit with Some c -> c | None -> usage "--commit is required for handoff") in
      let full = (match resolve_commit raw with Some f -> f
        | None -> err Names.e_commit_mismatch (`Assoc [("commit", json_str raw)])
            "Commit does not exist; bind an existing commit." 1) in
      if worktree_dirty () then
        err Names.e_dirty_tree (`Assoc []) "Worktree is dirty; clean it and retry." 1;
      let blocked_by = List.filter (fun d -> not (dep_satisfied d)) deps in
      if blocked_by <> [] then
        err Names.e_dependency (`Assoc [("blocked_by", `List (List.map json_str blocked_by))])
          "Dependencies are not landed yet." 1;
      let node_deps = (match fold_node quest node with
        | Some (_, _, text) -> deps_of_text text | None -> []) in
      let node_blocked = List.filter (fun d ->
        match fold_node quest d with
        | Some (_, ds, _) -> ds.st <> "landed" && ds.st <> "deleted"
        | None -> true) node_deps in
      if node_blocked <> [] then
        err Names.e_dependency (`Assoc [("blocked_by", `List (List.map json_str node_blocked))])
          "Node deps are not landed yet." 1;
      let missing = missing_ancestors
        ~is_ancestor
        ~fold_dep:(fun d ->
          match fold_node quest d with
          | Some (_, ds, _) -> Some (ds.st, ds.last_commit)
          | None -> None)
        node_deps full in
      if missing <> [] then
        err Names.e_missing_ancestor
          (`Assoc [("commit", json_str full);
                   ("missing", `List (List.map (fun (d, c) ->
                     `Assoc [("node", json_str d); ("commit", json_str c)]) missing))])
          "Rebase or merge landed dependency commits before handoff." 1;
      let touched = commit_touched_paths full in
      (match s.node_kind with
       | Research | Explore ->
           let node_state_of other =
             match fold_node quest other with Some (_, ds, _) -> Some ds.st | None -> None in
           (match doc_only_violations ~quest ~self_node:node
              ~node_state_of ~allow_protected:fl.allow_protected touched with
            | Ok () -> ()
            | Error (code, bad_paths) when code = Names.e_doc_only_node ->
                err Names.e_doc_only_node
                  (`Assoc [("commit", json_str full);
                           ("paths", `List (List.map json_str bad_paths))])
                  "Research and explore nodes may only modify docs/ paths." 1
            | Error (_, bad_paths) ->
                err Names.e_protected_file
                  (`Assoc [("commit", json_str full);
                           ("paths", `List (List.map json_str bad_paths))])
                  "Commit edits own or non-todo NODE.md; pass --allow-protected if intentional." 1);
           let qj_path = quest_json_path quest in
           if (not fl.allow_protected) && List.mem qj_path touched then
             (match Quest_spec.json_diff_violations ~quest ~self_node:node ~node_state_of
                ~before_json:(git_show (full ^ "^") qj_path)
                ~after_json:(git_show full qj_path) with
              | Ok () -> ()
              | Error bad_paths ->
                  err Names.e_protected_file
                    (`Assoc [("commit", json_str full);
                             ("paths", `List (List.map json_str bad_paths))])
                    "Research/Explore edits to quest.json may only modify non-self todo node entries; pass --allow-protected if intentional." 1)
       | Code | Direct | Human_gate ->
           let bad_prot = protected_violations ~quest ~node ~allow_protected:fl.allow_protected touched in
           if bad_prot <> [] then
             err Names.e_protected_file
               (`Assoc [("commit", json_str full);
                        ("paths", `List (List.map json_str bad_prot))])
               "Commit edits protected file(s); pass --allow-protected if intentional." 1);
      let outcome_opt =
        if s.node_kind = Explore then
          (match fl.outcome with
           | Some o -> Some o
           | None -> usage "--outcome is required for explore handoff (hit, missed, or inconclusive)")
        else None in
      let ns_base = { s with bound = Some full; has_bound = true; last_commit = Some full;
                      grade_ok = false; verify_ok = false;
                      explore_outcome = (match outcome_opt with Some _ -> outcome_opt | None -> s.explore_outcome) } in
      let handoff_extra = match outcome_opt with Some o -> [("outcome", json_str o)] | None -> [] in
      let handoff_res_extra = if s.node_kind = Explore then [("explore", explore_json ns_base)] else [] in
      let skip_grade =
        (not knobs.grade_required) ||
        (match s.node_kind with Direct | Research | Explore -> true | Code | Human_gate -> false) in
      if skip_grade then begin
        if knobs.auto_land then
          land_and_advance ~from_state:s.st ~ns:ns_base ~edge ~verdict:None
            ~extra:handoff_extra ~result_extra:handoff_res_extra ()
        else begin
          let ns = { ns_base with st = "approved" } in
          let line = ledger_line ~edge ~from:s.st ~to_:"approved" ~cycle:s.cycle
            ~commit:(Some full) ~verdict:None ~reason ~id ~extra:handoff_extra () in
          (match finish ns line with
           | `Assoc fs when handoff_res_extra <> [] -> `Assoc (fs @ handoff_res_extra)
           | other -> other)
        end
      end else begin
        let ns = { ns_base with st = "handed_off" } in
        let line = ledger_line ~edge ~from:s.st ~to_:"handed_off" ~cycle:s.cycle
          ~commit:(Some full) ~verdict:None ~reason ~id ~extra:handoff_extra () in
        finish ns line
      end
  | "iterate" ->
      if s.node_kind <> Explore || s.st <> "todo" then illegal_for s.node_kind s.st edge;
      (match s.explore_max_iterations with
       | Some cap when s.explore_iterations >= cap ->
           err Names.e_explore_bound
             (`Assoc [("quest", json_str quest); ("node", json_str node);
                      ("iterations", `Int s.explore_iterations);
                      ("max_iterations", `Int cap)])
             "Explore iteration cap reached; write REPORT.md and close with handoff --outcome hit|missed|inconclusive." 1
       | _ -> ());
      let ns = { s with explore_iterations = s.explore_iterations + 1 } in
      let line = ledger_line ~edge ~from:s.st ~to_:s.st ~cycle:s.cycle
        ~commit:s.last_commit ~verdict:None ~reason ~id () in
      ignore (append_node_line quest node line ns);
      with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
        ("node", json_str node); ("kind", json_str (node_kind_to_string ns.node_kind));
        ("state", json_str ns.st); ("cycle", `Int ns.cycle);
        ("explore", explore_json ns);
        ("legal_edges", `List (List.map json_str (legal_edges_for ns.node_kind ns.st)))]
  | "approve" ->
      if s.node_kind <> Human_gate || s.st <> "todo" then illegal_for s.node_kind s.st edge;
      let decider_str = match id.decider with
        | Human -> decider_to_string Human
        | Human_approved_llm_yolo -> decider_to_string Human_approved_llm_yolo
        | Agent ->
            err Names.e_human_required (`Assoc [("quest", json_str quest); ("node", json_str node)])
              "Approving a human-gate requires BP3_DECIDER=human (or BP3_DECIDER=human-approved-llm-yolo under /induct-yolo)." 1 in
      let blocked_by = List.filter (fun d -> not (dep_satisfied d)) deps in
      if blocked_by <> [] then
        err Names.e_dependency (`Assoc [("blocked_by", `List (List.map json_str blocked_by))])
          "Dependencies are not landed yet." 1;
      let node_deps = (match fold_node quest node with
        | Some (_, _, text) -> deps_of_text text | None -> []) in
      let node_blocked = List.filter (fun d ->
        match fold_node quest d with
        | Some (_, ds, _) -> ds.st <> "landed" && ds.st <> "deleted"
        | None -> true) node_deps in
      if node_blocked <> [] then
        err Names.e_dependency (`Assoc [("blocked_by", `List (List.map json_str node_blocked))])
          "Node deps are not landed yet." 1;
      let ns = { s with bound = None; has_bound = false; last_commit = None;
                        approved_decider = Some decider_str; approved_reason = reason } in
      land_and_advance ~from_state:s.st ~ns ~edge ~verdict:None
        ~extra:[("decider", json_str decider_str)]
        ~result_extra:[("decider", json_str decider_str)] ()
  | "grade" ->
      if s.st <> "handed_off" then illegal_for s.node_kind s.st edge;
      let v = (match fl.verdict with Some v -> v | None -> usage "--verdict is required") in
      if v <> "ship" && v <> "needs_fix" then usage ("invalid verdict for " ^ edge ^ ": " ^ v);
      (match fl.commit with
       | Some c ->
           let rc = (match resolve_commit c with Some f -> f | None -> c) in
           let bound = (match s.bound with Some b -> b | None -> "") in
           if rc <> bound then
             err Names.e_commit_mismatch (`Assoc [("commit", json_str c); ("bound", json_str bound)])
               "Verdict must bind the exact current commit; re-read and retry." 1
       | None -> ());
      (match fl.verify_verdict with
       | Some vv when vv <> "pass" && vv <> "fail" ->
           usage "--verify-verdict must be pass or fail"
       | _ -> ());
      let verify_negative =
        match fl.verify_verdict with Some "fail" -> true | _ -> false in
      let positive = (v = "ship") && not verify_negative in
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
        let ns = { s with grade_ok = true; verify_ok = true } in
        if knobs.auto_land then
          land_and_advance ~from_state:s.st ~ns ~edge ~verdict:(Some v) ~extra:cast_extra ()
        else begin
          let ns = { ns with st = "approved" } in
          let line = ledger_line ~edge ~from:s.st ~to_:"approved" ~cycle:s.cycle
            ~commit:s.last_commit ~verdict:(Some v) ~reason ~id ~extra:cast_extra () in
          finish ns line
        end
      end
  | "land" ->
      if s.st <> "approved" then illegal_for s.node_kind s.st edge;
      (match fl.commit with
       | Some c ->
           let rc = (match resolve_commit c with Some f -> f | None -> c) in
           let bound = (match s.bound with Some b -> b | None -> "") in
           if rc <> bound then
             err Names.e_commit_mismatch (`Assoc [("commit", json_str c)])
               "Verdict must bind the exact current commit." 1
       | None -> ());
      land_and_advance ~from_state:s.st ~ns:s ~edge ~verdict:None ()
  | "block" ->
      if not (List.mem s.st ["todo"; "handed_off"; "approved"]) then illegal_for s.node_kind s.st edge;
      let checkpoint = if worktree_dirty () then Some (make_checkpoint ()) else None in
      let ns = { s with st = "blocked"; blocked_reason = reason;
                 blocked_checkpoint = checkpoint; blocked_since = now_ts () } in
      let line = ledger_line ~edge ~from:s.st ~to_:"blocked" ~cycle:s.cycle
        ~commit:s.last_commit ~verdict:None ~reason ~id ?checkpoint () in
      let base = finish ns line in
      (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
  | "resume" ->
      if s.st <> "blocked" then illegal_for s.node_kind s.st edge;
      if not id.decider_human then
        err Names.e_human_required (`Assoc [("quest", json_str quest); ("node", json_str node)])
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
  bp3 harness desk <verb> ...  desks (machine-local); bp3 worktree is its documented alias\n\
  bp3 config [--format ...]    read-only view of machine-local bp3 config (<git-common-dir>/bp3/)\n\
  bp3 warden [<quest>] [...]   two-layer deterministic plug audit (git + session traces, read-only)\n\
  bp3 q hooks                  harness hook emitter (fail-open)\n\
Run bp3 q <door> -h for that door's verbs, edges, and flags.\n"

let help_quest_door = "bp3 q <quest door> - verbs:\n\
  bp3 q c <quest> [--type <goal_type>] [--depends-on <a,b>]    create a quest\n\
  bp3 q c [<quest>] --file <quest.json> [--scaffold]           atomically initialize quest + nodes from quest.json\n\
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
  edges: handoff grade land approve iterate block resume\n\
  handoff --commit <sha> [--allow-protected] [--outcome hit|missed|inconclusive] --reason <why>    bind a clean commit (auto-lands direct/research/explore)\n\
  grade   --verdict ship|needs_fix [--verify-verdict pass|fail] [--mechanical] --reason <why>   auto-lands on ship (land: auto) or approves (land: manual)\n\
  land    --reason <why>                   land an approved node (land: manual plans)\n\
  approve --reason <why>                   approve a human-gate (BP3_DECIDER=human or human-approved-llm-yolo)\n\
  iterate --note <what>                    record one explore iteration (refuses E_EXPLORE_BOUND at --max-iterations)\n\
  block   --reason <why>                   park for a human decision\n\
  resume  --reason <why>                   human only: unblock\n\
Shared flags: --format json|table|tree, --target <name>, --kind code|direct|research|explore|human-gate, --max-iterations <n>.\n\
Example: bp3 q my-quest u node-1 handoff --commit abc123 --reason \"ready\"\n"

let help_harness = "bp3 harness - machine-local desks:\n\
  bp3 harness desk <verb> ...   verbs: derive, create, inspect, remove, prepare, check, exit, release, land, list\n\
  bp3 harness desk prepare <quest> <node> --run <run-id> [--commit <sha>] [--path <dir>]\n\
  bp3 harness desk prepare --quest <quest>\n\
  bp3 harness desk prepare --draft <slug>\n\
  bp3 harness desk land --draft <slug> [--target <branch>]\n\
  bp3 harness desk release --draft <slug> [--force]\n\
  bp3 harness desk list [--quest <quest>]\n\
Example: bp3 harness desk prepare --quest my-quest\n"

let do_harness = function
  | [] -> print_string help_harness; 0
  | h :: _ when is_help h -> print_string help_harness; 0
  | ("desk" | "d") :: (h :: _) when is_help h -> print_string help_harness; 0
  | ("desk" | "d") :: rest ->
      print_verdict ~fmt:"json" (Worktree.run rest); 0
  | sub :: _ ->
      usage ("bp3 harness supports only: desk <derive|create|inspect|remove|prepare|check|exit|release|land|list> (unknown subcommand: " ^ sub ^ ")")

let help_icebox = "bp3 q icebox r - search frozen icebox entries (read-only):\n\
  bp3 q icebox r [term...] [--format json|table|tree]   list entries matching all terms\n\
  bp3 q icebox r <slug>                                 print one entry in full\n\
Example: bp3 q icebox r table completion\n"

let help_worktree = "bp3 worktree - documented alias of bp3 harness desk, machine-local desks, never ledgered:\n\
  verbs: derive, create, inspect, remove, prepare, check, exit, release, land, list\n\
  bp3 harness desk prepare <quest> <node> --run <run-id> [--commit <sha>] [--path <dir>]\n\
  bp3 harness desk prepare --draft <slug>\n\
  bp3 harness desk land --draft <slug> [--target <branch>]\n\
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

let help_config = "bp3 config - read-only view of machine-local bp3 config (<git-common-dir>/bp3/, never committed):\n\
  bp3 config [--source] [--format json|table]   mode, thresholds, and desks (read-only; never writes .git/bp3/)\n\
  Outside a git repo there is no config store and the call refuses E_NOT_FOUND.\n\
Example: bp3 config --format table\n"

(* Node 5 guard: an older-MAJOR binary never writes in a newer repo.
   Newer MINOR/PATCH only warns (warnings_of carries W_VERSION_AHEAD).
   guard.1: it runs at the write itself (Gitx.write_guard, set at entry),
   so no command shape can skip it; a call that writes nothing never
   reaches it. *)
let refuse_major_ahead () =
  match version_ahead () with
  | Some v when version_major v > version_major bp3_version ->
      err Names.e_version_ahead
        (`Assoc [("binary", json_str bp3_version); ("repo", json_str v)])
        "Repo was stamped by a newer MAJOR bp3; upgrade bp3 before writing." 1
  | _ -> ()

let repo_config_warnings () =
  match Backpack.load_opt root with
  | Ok (Some _) -> []
  | Ok None -> [ ("warnings", `List [ Backpack.warning_no_repo_config () ]) ]
  | Error detail ->
      err Names.e_invalid_config
        (`Assoc [("file", json_str Layout.manifest_file); ("detail", json_str detail)])
        ("Invalid " ^ Layout.manifest_file ^ ": " ^ detail) 1

let rec run argv =
  let id = identity () in
  match argv with
  | "-h" :: _ | "--help" :: _ -> print_string help_q; 0
  | "--version" :: _ -> print_endline bp3_version; 0
  | "q" :: (h :: _) when is_help h -> print_string help_q; 0
  | "q" :: rest -> run rest
  | "n" :: _ -> usage "bp3 n is retired; use bp3 q <quest> n <node> r"
  | "harness" :: rest -> do_harness rest
  | "config" :: (h :: _) when is_help h -> print_string help_config; 0
  | "config" :: rest ->
      let (source, fmt) = parse_config_flags rest in
      print_verdict ~fmt (Config.view ~source); 0
  | "warden" :: rest -> do_warden rest
  | "release" :: rest -> Release_io.run rest id
  | "db" :: rest -> Db_cli.run rest
  | "repo" :: rest -> Repo_cli.run rest
  | "ticket" :: rest -> Ticket_cli.run rest
  | "e" :: _ -> usage "bp3 e is retired; use bp3 q <quest> n <node> e <edge>"
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
      (* Node 6 + manifest.1: validate existing backpack.toml before mutating plans/;
         scaffold plans/ and minimal backpack.toml into the caller's repo idempotently *)
      let manifest_path = Filename.concat root Layout.manifest_file in
      let manifest_exists = Sys.file_exists manifest_path in
      if manifest_exists then
        (match Backpack.load_opt root with
         | Ok (Some _) | Ok None -> ()
         | Error detail ->
             err Names.e_invalid_config
               (`Assoc [("file", json_str Layout.manifest_file); ("detail", json_str detail)])
               ("Existing " ^ Layout.manifest_file ^ " is invalid: " ^ detail) 1);
      let plans = [("plans/default.yaml", "goal_type: default\nmax_cycles: 10\ngrade:\n  required: true\nland: auto\n");
                   ("plans/direct.yaml", "goal_type: direct\nmax_cycles: 0\ngrade:\n  required: false\nland: auto\n")] in
      (try Unix.mkdir (Filename.concat root "plans") 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      List.iter (fun (rel, content) ->
        let path = Filename.concat root rel in
        if Sys.file_exists path then begin
          let existing = let ic = open_in_bin path in
            let s = really_input_string ic (in_channel_length ic) in close_in ic; s in
          if existing <> content then
            err Names.e_exists (`Assoc [("plan", json_str rel)])
              "Plan already exists with different content; refusing to overwrite." 1
        end else begin
          let oc = open_out_bin path in output_string oc content; close_out oc
        end) plans;
      let manifest_created =
        if manifest_exists then false
        else begin
          let repo_slug = Layout.sanitize_repo_slug (Filename.basename (Worktree.main_root ())) in
          let target_br =
            if ref_tip "refs/heads/master" <> None then "master"
            else if ref_tip "refs/heads/main" <> None then "main"
            else "master" in
          let oc = open_out_bin manifest_path in
          Fun.protect ~finally:(fun () -> close_out oc)
            (fun () -> output_string oc (Backpack.render_default ~repo:repo_slug ~target:target_br));
          true
        end in
      if Repo_store.is_git_repo root then
        (try ignore (Repo_store.add ~path:root ())
         with Db.Error (code, json) -> raise (Verdict (code, json)));
      print_verdict ~fmt:"json" (`Assoc [("ok", `Bool true);
        ("manifest", json_str Layout.manifest_file);
        ("manifest_created", `Bool manifest_created);
        ("plans", `List (List.map (fun (p, _) -> json_str p) plans))]); 0
  | "hooks" :: _ ->
      (* fail-open emitter: Hooks.handle never raises, always exit 0 *)
      print_endline (Yojson.Safe.to_string (Hooks.handle ())); 0
  | "icebox" :: rest -> do_icebox rest
  | [] -> usage "no command"
  | first :: rest when is_verb first ->
      let verb = normalize_verb first in
      (match verb, rest with
       | "c", tail ->
           let (pos, fl) = split_flags tail in
           (match fl.file, pos with
            | Some fpath, [] ->
                let v = do_quest_create_from_file None fpath fl id in print_verdict ~fmt:fl.fmt v; 0
            | Some fpath, [quest] ->
                let v = do_quest_create_from_file (Some quest) fpath fl id in print_verdict ~fmt:fl.fmt v; 0
            | Some _, _ -> usage "stray positional in quest create"
            | None, [quest] ->
                if fl.scaffold then usage "--scaffold requires --file <path>";
                let v = do_quest_create quest fl id in print_verdict ~fmt:fl.fmt v; 0
            | None, [] -> usage "quest create needs a quest name"
            | None, _ -> usage "stray positional in quest create")
       | "r", [] ->
           let qs = List.map (fun q ->
             let (view, _, _, _) = quest_view q in view) (list_quests ()) in
           print_verdict ~fmt:"json" (`Assoc ([("ok", `Bool true); ("quests", `List qs)] @ repo_config_warnings ())); 0
       | "r", [quest] ->
           let (pos, fl) = ( [quest], { reason=None; commit=None; verdict=None; target=None; typ=None; kind=None; depends_on=None; fmt="json"; verify_verdict=None; mechanical=false; allow_protected=false; max_iterations=None; outcome=None; note=None; file=None; scaffold=false } ) in
           ignore pos;
           (* re-parse: quest may be followed by --format in original rest; handled below *)
           ignore fl;
           let (view, _, _, _) = quest_view quest in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []) @ repo_config_warnings ())); 0
       | "r", quest :: tail ->
           let (pos, fl) = split_flags (quest :: tail) in
           (match pos with
            | [q] ->
                let (view, _, _, _) = quest_view q in
                print_verdict ~fmt:fl.fmt (`Assoc (("ok", `Bool true) ::
                  (match view with `Assoc fs -> fs | _ -> []) @ repo_config_warnings ())); 0
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
             (match view with `Assoc fs -> fs | _ -> []) @ repo_config_warnings ())); 0
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


