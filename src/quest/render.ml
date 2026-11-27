(* render — verdict builders and the human tree view. *)
open Gitx
open Store

(* ---------- verdict builders ---------- *)
(* The proposed changeset of the bound commit: what a reviewer is
   actually being asked to judge, visible before land. Diff of the
   commit against its first parent. +/-/u alphabet, same as tree. *)
let commit_changes = function
  | None -> None (* unsure: nothing bound yet *)
  | Some c ->
      let out, code = git_out ["diff-tree"; "--no-commit-id"; "--name-status"; "-r"; c] in
      if code <> 0 then None (* unsure: unreadable diff *) else
      Some (List.filter_map (fun line ->
        match String.split_on_char '\t' line with
        | [st; path] ->
            let kind = if st = "" then "u" else
              (match st.[0] with 'A' -> "+" | 'D' -> "-" | _ -> "u") in
            Some (`Assoc [("change", json_str kind); ("path", json_str path)])
        | [st; _old; path] -> (* rename/copy: show the new path as updated *)
            let kind = if st <> "" && st.[0] = 'C' then "+" else "u" in
            Some (`Assoc [("change", json_str kind); ("path", json_str path)])
        | _ -> None)
      (List.filter (fun l -> l <> "") (String.split_on_char '\n' out)))

(* Every repo-relative path touched by [commit] against its first parent,
   returning BOTH old and new paths on renames/copies so renaming a
   protected file cannot bypass E_PROTECTED_FILE. *)
let commit_touched_paths commit =
  let out, code = git_out ["diff-tree"; "-m"; "--first-parent"; "--root"; "--no-commit-id"; "--name-status"; "-r"; "-M"; commit] in
  if code <> 0 then []
  else
    String.split_on_char '\n' out
    |> List.filter (fun l -> l <> "")
    |> List.concat_map (fun line ->
         match String.split_on_char '\t' line with
         | [_; path] -> [path]
         | [_; old_p; new_p] -> [old_p; new_p]
         | _ -> [])
    |> List.sort_uniq String.compare

(* Report word for an node finish line: state stays [landed]. *)
let node_fin s = if s.st = "landed" then `String "node_fin" else `Null

let opt_int = function Some n -> `Int n | None -> `Null

let explore_json s =
  `Assoc [
    ("target", (match s.explore_target with Some t -> json_str t | None -> `Null));
    ("max_iterations", opt_int s.explore_max_iterations);
    ("iterations", `Int s.explore_iterations);
    ("outcome", (match s.explore_outcome with Some o -> json_str o | None -> `Null));
  ]

let node_json _q e s deps (t : timing) =
  let base = [
    ("node", json_str e); ("kind", json_str (node_kind_to_string s.node_kind));
    ("state", json_str s.st); ("fin", node_fin s); ("cycle", `Int s.cycle);
    ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
    ("deps", `List (List.map json_str deps));
    ("timing", `Assoc [("wall_s", opt_int t.t_wall); ("wait_s", opt_int t.t_wait);
                       ("dwell_s", `Assoc (List.map (fun (st, secs) -> (st, `Int secs)) t.t_dwell));
                       ("cycles", `Int s.cycle)]);
    ("legal_edges", `List (List.map json_str (legal_edges_for s.node_kind s.st)));
    (* The decision point, on the node read itself (mvp.5):
       a fresh worker resuming after [resume] — or a root
       worker reviving after its own death — reconstructs
       why the node stopped from bp3 alone, never from a
       dead worker's memory. Same field words as the inbox. *)
    ("blocked", (if s.st = "blocked" then `Assoc [
       ("reason", json_str s.blocked_reason);
       ("checkpoint", (match s.blocked_checkpoint with Some c -> json_str c | None -> `Null));
       ("since", json_str s.blocked_since)] else `Null));
    ("changes", (match commit_changes s.last_commit with
       | Some xs -> `List xs | None -> `Null)); (* null = unsure *)
  ] in
  let fields =
    if s.node_kind = Explore then base @ [("explore", explore_json s)]
    else base in
  `Assoc fields

let node_verdict quest e s deps t =
  match node_json quest e s deps t with
  | `Assoc fs -> `Assoc (("ok", `Bool true) :: ("quest", json_str quest) :: fs)
  | other -> other

let quest_view q =
  match fold_quest q with
  | None -> not_found "quest" q
  | Some (_, qs, _qt, _deps, _) ->
      let nodes = list_nodes q in
      let node_infos = List.map (fun e ->
        match ledger_read (node_branch q e) (node_ledger_path q e) (legacy_node_ledger_paths q e) with
        | Some (_, text, _) ->
            let (s, _, deps) = fold_ledger text in (e, s, deps, timing_of_text text)
        | None -> (e, fresh_state (), [], timing_of_text "")) nodes in
      let node_states = List.map (fun (e, s, _, _) -> (e, s)) node_infos in
      let sched = List.map (fun (e, s, deps, _) ->
        { n_id = e; n_state = s.st; n_deps = deps }) node_infos in
      let waves = sched_waves sched in
      let ready = match waves with w :: _ -> w | [] -> [] in
      let starved = sched_starved sched in
      let inbox = List.filter_map (fun (e, s) ->
        if s.st = "blocked" then Some (`Assoc [
          ("quest", json_str q); ("node", json_str e);
          ("reason", json_str s.blocked_reason);
          ("checkpoint", (match s.blocked_checkpoint with Some c -> json_str c | None -> `Null));
          ("cycle", `Int s.cycle); ("since", json_str s.blocked_since);
        ]) else None) node_states in
      let yolo_approvals = List.filter_map (fun (e, s) ->
        match s.approved_decider with
        | Some d when d = decider_to_string Human_approved_llm_yolo ->
            Some (`Assoc [
              ("node", json_str e);
              ("decider", json_str d);
              ("reason", json_str s.approved_reason);
            ])
        | _ -> None) node_states in
      let rollup =
        if qs.st = "deleted" then "deleted"
        else if node_states <> [] && List.for_all (fun (_, s) -> s.st = "landed" || s.st = "deleted") node_states then "landed"
        else if List.exists (fun (_, s) -> s.st = "blocked") node_states then "blocked"
        else "active" in
      (* Report word for the quest finish line: rollup stays [landed];
         [goal_fin] names promotion of that rollup to master. *)
      let fin = if rollup = "landed" then `String "goal_fin" else `Null in
      (`Assoc [
        ("quest", json_str q); ("state", json_str qs.st);
        ("nodes", `List (List.map (fun (e, s, deps, t) -> node_json q e s deps t) node_infos));
        ("ready_set_waves", `List (List.map (fun w -> `List (List.map json_str w)) waves));
        ("ready", `List (List.map json_str ready));
        ("starved", `List (List.map (fun (b, ids) ->
           `Assoc [("blocked", json_str b); ("starved", `List (List.map json_str ids))]) starved));
        ("setup", `List []);
        ("yolo_approvals", `List yolo_approvals);
        ("rollup", json_str rollup); ("fin", fin); ("inbox", `List inbox);
      ],
       inbox, rollup, qs)

let tree_marker = function
  | "todo" -> "+"
  | "handed_off" | "approved" | "blocked" -> "u"
  | "deleted" -> "-"
  | _ -> " " (* landed: clean, like git status *)

let short_commit = function
  | Some c when String.length c > 7 -> String.sub c 0 7
  | Some c -> c
  | None -> "-"

(* tree(1)-style rendering: quest is the root, nodes are branches,
   and each node's proposed files expand per directory, like the
   tree command walks a filesystem. *)
type pnode = { pname : string; pchange : string option; pkids : pnode list ref }

let build_ptree xs =
  let roots : pnode list ref = ref [] in
  let find_dir siblings name =
    match List.find_opt (fun nd -> nd.pname = name && nd.pchange = None) !siblings with
    | Some nd -> nd
    | None ->
        let nd = { pname = name; pchange = None; pkids = ref [] } in
        siblings := !siblings @ [nd]; nd in
  List.iter (fun item ->
    match item with
    | `Assoc fs ->
        let c k = match List.assoc_opt k fs with Some (`String x) -> x | _ -> "?" in
        let rec go siblings = function
          | [] -> ()
          | [f] -> siblings := !siblings @ [{ pname = f; pchange = Some (c "change"); pkids = ref [] }]
          | d :: rest -> go (find_dir siblings d).pkids rest in
        go roots (String.split_on_char '/' (c "path"))
    | _ -> ()) xs;
  !roots

let rec render_ptree ?(keep_open = false) prefix nodes =
  let n = List.length nodes in
  List.iteri (fun i nd ->
    let last = i = n - 1 && not keep_open in
    Printf.printf "%s%s%s\n" prefix (if last then "└── " else "├── ")
      (match nd.pchange with Some ch -> ch ^ " " ^ nd.pname | None -> nd.pname);
    render_ptree ~keep_open:false (prefix ^ (if last then "    " else "│   ")) !(nd.pkids)) nodes

let file_leaves prefix = function
  | Some (`List xs) -> render_ptree prefix (build_ptree xs)
  | _ -> Printf.printf "%s└── ? changes unknown\n" prefix

let file_leaves_open prefix = function
  | Some (`List xs) -> render_ptree ~keep_open:true prefix (build_ptree xs)
  | _ -> Printf.printf "%s├── ? changes unknown\n" prefix

let render_tree fields =
  let get k = List.assoc_opt k fields in
  let str k = match get k with Some (`String s) -> s | _ -> "?" in
  Printf.printf "%s [%s] rollup: %s%s%s\n" (str "quest") (str "state") (str "rollup")
    (match get "fin" with Some (`String f) -> " (" ^ f ^ ")" | _ -> "")
    (match get "ready" with
     | Some (`List (_ :: _ as xs)) ->
         " ready: " ^ String.concat ", "
           (List.map (function `String x -> x | o -> Yojson.Safe.to_string o) xs)
     | _ -> "");
  let nodes = match get "nodes" with Some (`List xs) -> xs | _ -> [] in
  let n = List.length nodes in
  List.iteri (fun i item ->
    match item with
    | `Assoc fs ->
        let g k = List.assoc_opt k fs in
        let s k = match g k with Some (`String x) -> x | _ -> "?" in
        let state = s "state" in
        let cycle = match g "cycle" with Some (`Int c) -> c | _ -> 0 in
        let commit = match g "commit" with Some (`String c) -> Some c | _ -> None in
        let last = i = n - 1 in
        let branch = if last then "└── " else "├── " in
        let prefix = if last then "    " else "│   " in
        let owed = if state = "blocked" then "  (human owed)" else "" in
        let counts = match g "changes" with
          | Some (`List xs) when xs <> [] ->
              let cnt k = List.length (List.filter (fun item ->
                match item with `Assoc fs ->
                  (match List.assoc_opt "change" fs with Some (`String x) -> x = k | _ -> false)
                | _ -> false) xs) in
              Printf.sprintf "  [+%d u%d -%d]" (cnt "+") (cnt "u") (cnt "-")
          | Some (`List []) -> ""
          | _ -> "  [?]" in
        let fin = match g "fin" with Some (`String f) -> " (" ^ f ^ ")" | _ -> "" in
        Printf.printf "%s%s %s - %s%s, cycle %d, commit %s%s%s\n"
          branch (tree_marker state) (s "node") state fin cycle (short_commit commit) counts owed;
        file_leaves prefix (g "changes")
    | _ -> ()) nodes;
  (match get "inbox" with
   | Some (`List (_ :: _ as xs)) ->
       Printf.printf "human owed:\n";
       List.iter (fun item ->
         match item with
         | `Assoc fs ->
             let s k = match List.assoc_opt k fs with Some (`String x) -> x | _ -> "?" in
             Printf.printf "  u %s - %S (since %s)\n" (s "node") (s "reason") (s "since")
         | _ -> ()) xs
   | _ -> ())

let render_tree_node fields =
  let g k = List.assoc_opt k fields in
  let s k = match g k with Some (`String x) -> x | _ -> "?" in
  let state = s "state" in
  let cycle = match g "cycle" with Some (`Int c) -> c | _ -> 0 in
  let commit = match g "commit" with Some (`String c) -> Some c | _ -> None in
  let legal = match g "legal_edges" with
    | Some (`List xs) ->
        String.concat ", " (List.map (function `String x -> x | o -> Yojson.Safe.to_string o) xs)
    | _ -> "" in
  Printf.printf "%s\n└── %s %s - %s%s, cycle %d, commit %s\n"
    (s "quest") (tree_marker state) (s "node") state
    (match g "fin" with Some (`String f) -> " (" ^ f ^ ")" | _ -> "") cycle
    (short_commit commit);
  file_leaves_open "    " (g "changes");
  Printf.printf "    └── legal: %s\n" (if legal = "" then "none" else legal)

(* ---------- table rendering ---------- *)
(* Column model per flat shape: widths come from content, so a long
   path widens the table instead of truncating. Plain ASCII, two
   spaces between columns, last column unpadded. *)
let pad_to w s =
  let n = String.length s in
  if n >= w then s else s ^ String.make (w - n) ' '

let render_rows headers rows =
  let widths = List.mapi (fun i h ->
    List.fold_left (fun w row ->
      match List.nth_opt row i with Some c -> max w (String.length c) | None -> w)
      (String.length h) rows) headers in
  let last = List.length headers - 1 in
  let line cells =
    String.concat "  " (List.mapi (fun i c ->
      if i = last then c
      else match List.nth_opt widths i with Some w -> pad_to w c | None -> c) cells) in
  Printf.printf "%s\n" (line headers);
  List.iter (fun row -> Printf.printf "%s\n" (line row)) rows

(* Same counts word as the tree view: [+n um -d] without brackets. *)
let change_counts = function
  | `List xs ->
      let cnt k = List.length (List.filter (fun item ->
        match item with
        | `Assoc fs ->
            (match List.assoc_opt "change" fs with Some (`String x) -> x = k | _ -> false)
        | _ -> false) xs) in
      Printf.sprintf "+%d u%d -%d" (cnt "+") (cnt "u") (cnt "-")
  | _ -> "?"

let cell_str fs k =
  match List.assoc_opt k fs with Some (`String x) -> x | _ -> "?"

let cell_cycle fs =
  match List.assoc_opt "cycle" fs with Some (`Int c) -> string_of_int c | _ -> "?"

let cell_commit fs =
  match List.assoc_opt "commit" fs with
  | Some (`String c) -> short_commit (Some c)
  | _ -> "-"

let cell_changes fs =
  change_counts (match List.assoc_opt "changes" fs with Some v -> v | None -> `Null)

let render_table_quest fields =
  let get k = List.assoc_opt k fields in
  let str k = match get k with Some (`String s) -> s | _ -> "?" in
  Printf.printf "quest %s [%s] rollup: %s%s\n" (str "quest") (str "state") (str "rollup")
    (match get "ready" with
     | Some (`List (_ :: _ as xs)) ->
         " ready: " ^ String.concat ", "
           (List.map (function `String x -> x | o -> Yojson.Safe.to_string o) xs)
     | _ -> "");
  let nodes = match get "nodes" with Some (`List xs) -> xs | _ -> [] in
  let rows = List.filter_map (fun item ->
    match item with
    | `Assoc fs ->
        Some [cell_str fs "node"; cell_str fs "state"; cell_cycle fs;
              cell_commit fs; cell_changes fs]
    | _ -> None) nodes in
  render_rows ["node"; "state"; "cycle"; "commit"; "changes"] rows

let render_table_node fields =
  let g k = List.assoc_opt k fields in
  let s k = match g k with Some (`String x) -> x | _ -> "?" in
  let cycle = match g "cycle" with Some (`Int c) -> c | _ -> 0 in
  let commit = match g "commit" with Some (`String c) -> Some c | _ -> None in
  let legal = match g "legal_edges" with
    | Some (`List xs) ->
        String.concat ", " (List.map (function `String x -> x | o -> Yojson.Safe.to_string o) xs)
    | _ -> "" in
  Printf.printf "%s / %s — %s, cycle %d, commit %s, legal: %s\n"
    (s "quest") (s "node") (s "state") cycle (short_commit commit)
    (if legal = "" then "none" else legal);
  (match g "changes" with
   | Some (`List xs) ->
       let rows = List.filter_map (fun item ->
         match item with
         | `Assoc fs -> Some [cell_str fs "change"; cell_str fs "path"]
         | _ -> None) xs in
       render_rows ["change"; "path"] rows
   | _ -> Printf.printf "? changes unknown\n")

let render_table_icebox fields =
  let entries = match List.assoc_opt "entries" fields with Some (`List xs) -> xs | _ -> [] in
  let rows = List.filter_map (fun item ->
    match item with
    | `Assoc fs ->
        Some [cell_str fs "slug"; cell_str fs "date"; cell_str fs "status";
              (match List.assoc_opt "promoted" fs with Some (`String p) -> p | _ -> "-");
              cell_str fs "title"]
    | _ -> None) entries in
  render_rows ["slug"; "date"; "status"; "promoted"; "title"] rows

(* ---------- diagram emit (mvp.4) ---------- *)
(* Generated from the live rollup fields at call time: both
   formats render one quest_view snapshot, so ascii and
   mermaid of the same moment carry the same facts. Every
   node is defined once with its state and cycle (landed
   nodes carry node_fin), every dep is drawn once, ready-set
   waves group the todo layers, and a blocked node names
   the dependents it starves. The header states the output
   is generated, with the rollup timestamp. *)
let dget fields k = List.assoc_opt k fields
let dstr fields k = match dget fields k with Some (`String s) -> s | _ -> "?"
let dlist fields k = match dget fields k with Some (`List xs) -> xs | _ -> []
let jstr_of = function `String s -> s | o -> Yojson.Safe.to_string o

type dnode = { d_id : string; d_label : string; d_deps : string list }

let diagram_nodes fields =
  List.filter_map (fun item ->
    match item with
    | `Assoc fs ->
        let fin = match List.assoc_opt "fin" fs with
          | Some (`String f) -> ", " ^ f | _ -> "" in
        let cycle = match List.assoc_opt "cycle" fs with
          | Some (`Int c) -> string_of_int c | _ -> "?" in
        Some { d_id = dstr fs "node";
               d_label = Printf.sprintf "%s (%s, cycle %s%s)"
                 (dstr fs "node") (dstr fs "state") cycle fin;
               d_deps = List.filter_map
                 (function `String s -> Some s | _ -> None) (dlist fs "deps") }
    | _ -> None) (dlist fields "nodes")

let diagram_deps nodes =
  List.concat_map (fun n -> List.map (fun d -> (d, n.d_id)) n.d_deps) nodes

let diagram_waves fields =
  List.map (fun w -> match w with
    | `List xs -> List.map jstr_of xs | o -> [jstr_of o]) (dlist fields "ready_set_waves")

let diagram_starved fields =
  List.filter_map (fun item ->
    match item with
    | `Assoc fs ->
        Some (dstr fs "blocked",
              List.map jstr_of (dlist fs "starved"))
    | _ -> None) (dlist fields "starved")

let emit_ascii fields generated_at =
  let nodes = diagram_nodes fields in
  let deps = diagram_deps nodes in
  let waves = diagram_waves fields in
  let starved = diagram_starved fields in
  let b = Buffer.create 256 in
  Printf.bprintf b "quest %s diagram (generated from live state at %s)\n"
    (dstr fields "quest") generated_at;
  Printf.bprintf b "rollup: %s\n" (dstr fields "rollup");
  Buffer.add_string b "nodes:\n";
  (match nodes with
   | [] -> Buffer.add_string b "  (none)\n"
   | _ -> List.iter (fun n -> Printf.bprintf b "  %s\n" n.d_label) nodes);
  Buffer.add_string b "deps:\n";
  (match deps with
   | [] -> Buffer.add_string b "  (none)\n"
   | _ -> List.iter (fun (d, n) ->
       Printf.bprintf b "  %s \xe2\x94\x80dep\xe2\x94\x80\xe2\x96\xba %s\n" d n) deps);
  Buffer.add_string b "waves:\n";
  (match waves with
   | [] -> Buffer.add_string b "  (none)\n"
   | _ -> List.iteri (fun i w ->
       Printf.bprintf b "  wave %d: %s\n" (i + 1) (String.concat ", " w)) waves);
  Buffer.add_string b "starved:\n";
  (match starved with
   | [] -> Buffer.add_string b "  (none)\n"
   | _ -> List.iter (fun (blocked, ids) ->
       Printf.bprintf b "  %s starves: %s\n" blocked (String.concat ", " ids)) starved);
  Buffer.contents b

let mermaid_id s =
  String.map (fun c ->
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
       || (c >= '0' && c <= '9') || c = '_' then c else '_') s

let emit_mermaid fields generated_at =
  let nodes = diagram_nodes fields in
  let deps = diagram_deps nodes in
  let waves = diagram_waves fields in
  let starved = diagram_starved fields in
  let b = Buffer.create 256 in
  Printf.bprintf b "%%%% generated from live state at %s\n" generated_at;
  Printf.bprintf b "%%%% quest %s rollup: %s\n"
    (dstr fields "quest") (dstr fields "rollup");
  Buffer.add_string b "graph LR\n";
  List.iter (fun n ->
    Printf.bprintf b "  %s[\"%s\"]\n" (mermaid_id n.d_id) n.d_label) nodes;
  List.iter (fun (d, n) ->
    Printf.bprintf b "  %s -->|dep| %s\n" (mermaid_id d) (mermaid_id n)) deps;
  List.iteri (fun i w ->
    Printf.bprintf b "  subgraph wave_%d[\"wave %d\"]\n" (i + 1) (i + 1);
    List.iter (fun id -> Printf.bprintf b "    %s\n" (mermaid_id id)) w;
    Buffer.add_string b "  end\n") waves;
  List.iter (fun (blocked, ids) ->
    Printf.bprintf b "  %%%% %s starves: %s\n" blocked (String.concat ", " ids)) starved;
  Buffer.contents b

let warning_has_code code = function
  | `String s -> s = code
  | `Assoc fs -> (match List.assoc_opt "code" fs with Some (`String s) -> s = code | _ -> false)
  | _ -> false

let merge_warnings ~version_ahead_active v =
  match v with
  | `Assoc fs ->
      let existing = match List.assoc_opt "warnings" fs with
        | Some (`List xs) -> xs
        | _ -> [] in
      let merged =
        if version_ahead_active && not (List.exists (warning_has_code "W_VERSION_AHEAD") existing) then
          existing @ [ json_str "W_VERSION_AHEAD" ]
        else existing in
      if merged = [] then v
      else `Assoc (List.filter (fun (k, _) -> k <> "warnings") fs
                   @ [("warnings", `List merged)])
  | _ -> v

let print_verdict ~fmt v =
  let v = stamp_run_id v in
  (* Warnings merge once, in order: the verdict's own (string or structured
     object), then Node 5's version warning. No warnings keeps the field absent. *)
  let v = merge_warnings ~version_ahead_active:(version_ahead () <> None) v in
  match fmt, v with
  | "tree", `Assoc fields when List.mem_assoc "nodes" fields ->
      render_tree fields
  | "tree", `Assoc fields when List.mem_assoc "node" fields ->
      render_tree_node fields
  | "table", `Assoc fields when List.mem_assoc "nodes" fields ->
      render_table_quest fields
  | "table", `Assoc fields when List.mem_assoc "node" fields
      && List.mem_assoc "changes" fields ->
      render_table_node fields
  | "table", `Assoc fields when List.mem_assoc "entries" fields ->
      render_table_icebox fields
  | "table", `Assoc fields ->
      List.iter (fun (k, v) ->
        match v with
        | `List xs ->
            Printf.printf "%s:\n" k;
            List.iter (fun item ->
              match item with
              | `Assoc fs -> Printf.printf "  %s\n" (String.concat " " (List.map (fun (a, b) -> a ^ "=" ^ Yojson.Safe.to_string b) fs))
              | other -> Printf.printf "  %s\n" (Yojson.Safe.to_string other)) xs
        | other -> Printf.printf "%s: %s\n" k (match other with `String s -> s | o -> Yojson.Safe.to_string o)
      ) fields
  | _, _ -> print_endline (Yojson.Safe.to_string v)

