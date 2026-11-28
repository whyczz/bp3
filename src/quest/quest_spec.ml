(* quest_spec — pure parser, validator, topological sorter, brief renderer,
   markdown scaffolder, and Research/Explore JSON diff guard for declarative
   quest.json v1 specs (declarative-json-quest-init spec.1, Ticket #12). *)

type acceptance = {
  objective : string;
  prove_by : string list;
  done_when : string;
  trace : string list;
}

type node_spec = {
  id : string;
  node : string;
  title : string;
  kind : Store.node_kind;
  lane : string;
  depends_on : string list;
  intent : string;
  output : string;
  acceptance : acceptance;
  target : string option;
  max_iterations : int option;
}

type t = {
  version : int;
  quest : string;
  title : string;
  tldr : string;
  goal_type : string;
  bump : string;
  home_repo : string;
  depends_on : string list;
  nodes : node_spec list;
}

let valid_bumps = [ "major"; "minor"; "patch"; "none" ]
let valid_lanes = [ "micro"; "standard"; "high-blast-radius" ]

let assoc_opt k = function
  | `Assoc fs -> List.assoc_opt k fs
  | _ -> None

let non_empty_str = function
  | Some (`String s) ->
      let t = String.trim s in
      if t = "" then None else Some t
  | _ -> None

let dedup xs =
  List.fold_right (fun x acc -> if List.mem x acc then acc else x :: acc) xs []

let parse_string_list ~field ~allow_empty ~errs obj =
  match assoc_opt field obj with
  | None ->
      if allow_empty then []
      else (errs := (field ^ " is required") :: !errs; [])
  | Some (`List xs) ->
      let out = ref [] in
      List.iteri (fun idx item ->
        match item with
        | `String s when String.trim s <> "" -> out := String.trim s :: !out
        | _ -> errs := (Printf.sprintf "%s[%d] must be a non-empty string" field idx) :: !errs) xs;
      let res = List.rev !out in
      if (not allow_empty) && res = [] then
        errs := (field ^ " must be a non-empty array") :: !errs;
      res
  | Some _ ->
      errs := (field ^ " must be an array of strings") :: !errs;
      []

let parse_optional_trace ~errs obj =
  match assoc_opt "trace" obj with
  | None | Some `Null -> []
  | Some (`List xs) ->
      let out = ref [] in
      List.iteri (fun idx item ->
        match item with
        | `String s -> out := s :: !out
        | _ -> errs := (Printf.sprintf "acceptance.trace[%d] must be a string" idx) :: !errs) xs;
      List.rev !out
  | Some _ ->
      errs := "acceptance.trace must be an array of strings" :: !errs;
      []

let parse_acceptance ~prefix ~errs obj =
  match assoc_opt "acceptance" obj with
  | Some (`Assoc _ as a) ->
      let objective = match non_empty_str (assoc_opt "objective" a) with
        | Some s -> s
        | None -> errs := (prefix ^ ".acceptance.objective must be a non-empty string") :: !errs; "" in
      let prove_by = parse_string_list ~field:"prove_by" ~allow_empty:false ~errs a in
      let done_when = match non_empty_str (assoc_opt "done_when" a) with
        | Some s -> s
        | None -> errs := (prefix ^ ".acceptance.done_when must be a non-empty string") :: !errs; "" in
      let trace = parse_optional_trace ~errs a in
      { objective; prove_by; done_when; trace }
  | _ ->
      errs := (prefix ^ ".acceptance must be an object") :: !errs;
      { objective = ""; prove_by = []; done_when = ""; trace = [] }

let parse_node idx ~errs j =
  let prefix = Printf.sprintf "nodes[%d]" idx in
  match j with
  | `Assoc _ ->
      let id = match non_empty_str (assoc_opt "id" j) with
        | Some s ->
            if not (Store.valid_slug s) then
              errs := (prefix ^ ".id is not a valid slug: " ^ s) :: !errs
            else if List.mem s Store.reserved_slugs then
              errs := (prefix ^ ".id uses reserved slug: " ^ s) :: !errs;
            s
        | None -> errs := (prefix ^ ".id must be a non-empty string") :: !errs; "" in
      let label = if id <> "" then "node " ^ id else prefix in
      let node = match assoc_opt "node" j with
        | None | Some `Null -> id
        | Some (`String s) when String.trim s <> "" -> String.trim s
        | Some _ -> errs := (label ^ ".node must be a non-empty string") :: !errs; id in
      let title = match non_empty_str (assoc_opt "title" j) with
        | Some s -> s
        | None -> errs := (label ^ ".title must be a non-empty string") :: !errs; "" in
      let kind = match assoc_opt "kind" j with
        | None | Some `Null -> Store.Code
        | Some (`String k) ->
            (match Store.node_kind_of_string k with
             | Some nk -> nk
             | None ->
                 errs := (label ^ " has invalid kind: " ^ k) :: !errs;
                 Store.Code)
        | Some _ ->
            errs := (label ^ ".kind must be a string") :: !errs;
            Store.Code in
      let lane = match assoc_opt "lane" j with
        | None | Some `Null -> "standard"
        | Some (`String l) when List.mem l valid_lanes -> l
        | Some (`String l) ->
            errs := (label ^ " has invalid lane: " ^ l) :: !errs;
            "standard"
        | Some _ ->
            errs := (label ^ ".lane must be a string") :: !errs;
            "standard" in
      let depends_on =
        parse_string_list ~field:"depends_on" ~allow_empty:true ~errs j
        |> List.map Store.canon_node_id |> dedup in
      List.iter (fun d ->
        if not (Store.valid_slug d) then
          errs := (label ^ " has invalid dep slug: " ^ d) :: !errs) depends_on;
      let intent = match non_empty_str (assoc_opt "intent" j) with
        | Some s -> s
        | None -> errs := (label ^ ".intent must be a non-empty string") :: !errs; "" in
      let output = match non_empty_str (assoc_opt "output" j) with
        | Some s -> s
        | None -> errs := (label ^ ".output must be a non-empty string") :: !errs; "" in
      let target = match assoc_opt "target" j with
        | None | Some `Null -> None
        | Some (`String s) when String.trim s <> "" -> Some (String.trim s)
        | Some _ ->
            errs := (label ^ ".target must be a non-empty string") :: !errs;
            None in
      if kind = Store.Explore && target = None then
        errs := (label ^ " (explore) requires non-empty target") :: !errs;
      let max_iterations = match assoc_opt "max_iterations" j with
        | None | Some `Null -> None
        | Some (`Int n) when n >= 1 -> Some n
        | Some _ ->
            errs := (label ^ ".max_iterations must be a positive integer") :: !errs;
            None in
      let acceptance = parse_acceptance ~prefix:label ~errs j in
      Some { id; node; title; kind; lane; depends_on; intent; output;
             acceptance; target; max_iterations }
  | _ ->
      errs := (prefix ^ " must be an object") :: !errs;
      None

let parse_json j =
  match j with
  | `Assoc _ ->
      let errs = ref [] in
      let version = match assoc_opt "version" j with
        | Some (`Int 1) -> 1
        | Some (`Int v) ->
            errs := (Printf.sprintf "unsupported spec version: %d (expected 1)" v) :: !errs;
            v
        | _ -> errs := "version must be integer 1" :: !errs; 0 in
      let quest = match non_empty_str (assoc_opt "quest" j) with
        | Some s ->
            if not (Store.valid_slug s) then
              errs := ("quest is not a valid slug: " ^ s) :: !errs
            else if List.mem s Store.reserved_slugs then
              errs := ("quest uses reserved slug: " ^ s) :: !errs;
            s
        | None -> errs := "quest must be a non-empty string" :: !errs; "" in
      let title = match non_empty_str (assoc_opt "title" j) with
        | Some s -> s
        | None -> errs := "title must be a non-empty string" :: !errs; "" in
      let tldr = match non_empty_str (assoc_opt "tldr" j) with
        | Some s -> s
        | None -> errs := "tldr must be a non-empty string" :: !errs; "" in
      let goal_type = match assoc_opt "goal_type" j with
        | None | Some `Null -> "default"
        | Some (`String s) when String.trim s <> "" -> String.trim s
        | Some _ -> errs := "goal_type must be a non-empty string" :: !errs; "default" in
      let bump = match non_empty_str (assoc_opt "bump" j) with
        | Some b when List.mem b valid_bumps -> b
        | Some b -> errs := ("invalid bump: " ^ b ^ " (expected major|minor|patch|none)") :: !errs; b
        | None -> errs := "bump must be one of major, minor, patch, none" :: !errs; "" in
      let home_repo = match assoc_opt "home_repo" j with
        | None | Some `Null -> ""
        | Some (`String s) -> String.trim s
        | Some _ -> errs := "home_repo must be a string" :: !errs; "" in
      let depends_on =
        parse_string_list ~field:"depends_on" ~allow_empty:true ~errs j |> dedup in
      List.iter (fun d ->
        if not (Store.valid_slug d) then
          errs := ("quest depends_on has invalid slug: " ^ d) :: !errs) depends_on;
      let nodes = match assoc_opt "nodes" j with
        | Some (`List ([])) ->
            errs := "nodes must be a non-empty array" :: !errs; []
        | Some (`List xs) ->
            List.mapi (fun i x -> parse_node i ~errs x) xs
            |> List.filter_map Fun.id
        | _ -> errs := "nodes must be a non-empty array" :: !errs; [] in
      (* Duplicate IDs *)
      let seen = Hashtbl.create 16 in
      List.iter (fun n ->
        if n.id <> "" then begin
          let c = Store.canon_node_id n.id in
          if Hashtbl.mem seen c then
            errs := ("duplicate node id: " ^ n.id) :: !errs
          else Hashtbl.add seen c ()
        end) nodes;
      (* Unknown deps *)
      List.iter (fun n ->
        List.iter (fun d ->
          if not (Hashtbl.mem seen (Store.canon_node_id d)) then
            errs := (Printf.sprintf "node %s depends on unknown node %s" n.id d) :: !errs)
          n.depends_on) nodes;
      (* Cycles via Store.dep_cycle_through *)
      if !errs = [] then begin
        let dgraph = List.map (fun (n : node_spec) -> (Store.canon_node_id n.id, n.depends_on)) nodes in
        let rec check_cycles = function
          | [] -> ()
          | (n : node_spec) :: rest ->
              (match Store.dep_cycle_through dgraph (Store.canon_node_id n.id) with
               | Some cyc ->
                   errs := ("dependency cycle: " ^ String.concat " -> " cyc) :: !errs
               | None -> check_cycles rest) in
        check_cycles nodes
      end;
      if !errs <> [] then Error (List.rev !errs)
      else Ok { version; quest; title; tldr; goal_type; bump; home_repo; depends_on; nodes }
  | _ -> Error [ "quest.json root must be a JSON object" ]

let parse_string raw =
  try parse_json (Yojson.Safe.from_string raw)
  with Yojson.Json_error msg -> Error [ "malformed JSON: " ^ msg ]

(* Deterministic topological order preserving input order among ready nodes. *)
let topo_sort (nodes : node_spec list) =
  let rec loop (placed : node_spec list) (remaining : node_spec list) =
    match remaining with
    | [] -> Ok (List.rev placed)
    | _ ->
        let placed_ids = List.map (fun (n : node_spec) -> Store.canon_node_id n.id) placed in
        let ready, blocked =
          List.partition (fun (n : node_spec) ->
            List.for_all (fun d -> List.mem (Store.canon_node_id d) placed_ids) n.depends_on) remaining in
        match ready with
        | [] ->
            let ids = List.map (fun (n : node_spec) -> n.id) blocked in
            Error [ "dependency cycle involving: " ^ String.concat ", " ids ]
        | _ -> loop (List.rev_append ready placed) blocked in
  loop [] nodes

let find_node spec node_id =
  let want = Store.canon_node_id node_id in
  List.find_opt (fun n -> Store.canon_node_id n.id = want) spec.nodes

let render_acceptance n =
  let a = n.acceptance in
  let trace_part =
    match a.trace with
    | [] -> ""
    | lines ->
        "Design trace:\n\n```text\n" ^ String.concat "\n" lines ^ "\n```\n\n" in
  let prove = String.concat "; " a.prove_by in
  Printf.sprintf "%sRunnable goal block:\n- **objective:** %s\n- **prove by:** %s\n- **done when:** %s"
    trace_part a.objective prove a.done_when

(* Owner-settled Research/Explore JSON diff guard (2026-11-27):
   when a Research or Explore node modifies docs/quests/<quest>/quest.json,
   permit edits ONLY to non-self `todo` node entries. Refuses quest-level
   metadata edits, adding/removing nodes, malformed specs, or edits to own
   or non-todo nodes. *)
let json_diff_violations ~quest ~self_node ~node_state_of ~before_json ~after_json =
  let qpath = Store.quest_json_path quest in
  match before_json, after_json with
  | Some b_raw, Some a_raw ->
      (match parse_string b_raw, parse_string a_raw with
       | Ok b, Ok a ->
           let header_same =
             b.version = a.version && b.quest = a.quest && b.title = a.title
             && b.tldr = a.tldr && b.goal_type = a.goal_type && b.bump = a.bump
             && b.home_repo = a.home_repo && b.depends_on = a.depends_on in
           if not header_same then Error [ qpath ]
           else
             let to_map ns =
               let tbl = Hashtbl.create (List.length ns) in
               List.iter (fun n -> Hashtbl.replace tbl (Store.canon_node_id n.id) n) ns;
               tbl in
             let bm = to_map b.nodes and am = to_map a.nodes in
             let all_ids =
               dedup (List.map (fun n -> Store.canon_node_id n.id) (b.nodes @ a.nodes)) in
             let self_canon = Store.canon_node_id self_node in
             let ok_node id =
               match Hashtbl.find_opt bm id, Hashtbl.find_opt am id with
               | Some nb, Some na ->
                   if nb = na then true
                   else id <> self_canon && node_state_of id = Some "todo"
               | _ -> false (* adding or deleting nodes in quest.json is refused *) in
             if List.for_all ok_node all_ids then Ok ()
             else Error [ qpath ]
       | _ -> Error [ qpath ])
  | _ -> Error [ qpath ]

let render_node_md (spec : t) (n : node_spec) =
  let deps_str = match n.depends_on with [] -> "none" | ds -> String.concat ", " ds in
  let target_row = match n.target with
    | Some t -> Printf.sprintf "| Target | %s |\n" t
    | None -> "" in
  let max_iter_row = match n.max_iterations with
    | Some m -> Printf.sprintf "| Max iterations | %d |\n" m
    | None -> "" in
  Printf.sprintf
    "---\nnode: %s\n---\n\n<!-- GENERATED view from docs/quests/%s/quest.json (single source of truth). -->\n\n# %s - %s\n\nTL;DR\n%s\n\n## Acceptance gates\n\n%s\n\n## Tables\n\n| Field | Value |\n|---|---|\n| Intent | %s |\n| Kind | `%s` |\n| Lane | `%s` |\n| Output | %s |\n%s%s| Depends on | %s |\n"
    n.node spec.quest n.node n.title n.intent
    (render_acceptance n)
    n.intent (Store.node_kind_to_string n.kind) n.lane n.output
    target_row max_iter_row deps_str

let render_quest_md (spec : t) =
  let repo_line = if spec.home_repo = "" then "" else "home_repo: " ^ spec.home_repo ^ "\n" in
  let rows =
    List.map (fun (n : node_spec) ->
      Printf.sprintf "| [%s - %s](nodes/%s/NODE.md) | `%s` | %s |"
        n.node n.title n.id (Store.node_kind_to_string n.kind) n.intent) spec.nodes
    |> String.concat "\n" in
  Printf.sprintf
    "---\nstatus: proposed\n%sgoal_type: %s\nbump: %s\n---\n\n<!-- GENERATED view from docs/quests/%s/quest.json (single source of truth). -->\n\n# %s\n\nTL;DR\n%s\n\n## Nodes\n\n| Node | Kind | Intent |\n|---|---|---|\n%s\n"
    repo_line spec.goal_type spec.bump spec.quest spec.title spec.tldr rows
