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

let exp_json _q e s =
  `Assoc [
    ("exp", json_str e); ("state", json_str s.st); ("cycle", `Int s.cycle);
    ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
    ("legal_edges", `List (List.map json_str (legal_edges s.st)));
    ("changes", (match commit_changes s.last_commit with
       | Some xs -> `List xs | None -> `Null)); (* null = unsure *)
  ]

let exp_verdict quest e s =
  match exp_json quest e s with
  | `Assoc fs -> `Assoc (("ok", `Bool true) :: ("quest", json_str quest) :: fs)
  | other -> other

let quest_view q =
  match fold_quest q with
  | None -> not_found "quest" q
  | Some (_, qs, _qt, _deps, _) ->
      let exps = list_exps q in
      let exp_states = List.map (fun e ->
        match fold_exp q e with Some (_, s, _) -> (e, s) | None -> (e, fresh_state ())) exps in
      let inbox = List.filter_map (fun (e, s) ->
        if s.st = "blocked" then Some (`Assoc [
          ("quest", json_str q); ("exp", json_str e);
          ("reason", json_str s.blocked_reason);
          ("checkpoint", (match s.blocked_checkpoint with Some c -> json_str c | None -> `Null));
          ("cycle", `Int s.cycle); ("since", json_str s.blocked_since);
        ]) else None) exp_states in
      let rollup =
        if qs.st = "deleted" then "deleted"
        else if exp_states <> [] && List.for_all (fun (_, s) -> s.st = "landed" || s.st = "deleted") exp_states then "landed"
        else if List.exists (fun (_, s) -> s.st = "blocked") exp_states then "blocked"
        else "active" in
      (`Assoc [
        ("quest", json_str q); ("state", json_str qs.st);
        ("exps", `List (List.map (fun (e, s) -> exp_json q e s) exp_states));
        ("rollup", json_str rollup); ("inbox", `List inbox);
      ], inbox, rollup, qs)

let tree_marker = function
  | "todo" -> "+"
  | "submitted" | "approved" | "blocked" -> "u"
  | "deleted" -> "-"
  | _ -> " " (* landed: clean, like git status *)

let short_commit = function
  | Some c when String.length c > 7 -> String.sub c 0 7
  | Some c -> c
  | None -> "-"

(* tree(1)-style rendering: quest is the root, exps are branches,
   and each exp's proposed files expand per directory, like the
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
  Printf.printf "%s [%s] rollup: %s\n" (str "quest") (str "state") (str "rollup");
  let exps = match get "exps" with Some (`List xs) -> xs | _ -> [] in
  let n = List.length exps in
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
        Printf.printf "%s%s %s - %s, cycle %d, commit %s%s%s\n"
          branch (tree_marker state) (s "exp") state cycle (short_commit commit) counts owed;
        file_leaves prefix (g "changes")
    | _ -> ()) exps;
  (match get "inbox" with
   | Some (`List (_ :: _ as xs)) ->
       Printf.printf "human owed:\n";
       List.iter (fun item ->
         match item with
         | `Assoc fs ->
             let s k = match List.assoc_opt k fs with Some (`String x) -> x | _ -> "?" in
             Printf.printf "  u %s - %S (since %s)\n" (s "exp") (s "reason") (s "since")
         | _ -> ()) xs
   | _ -> ())

let render_tree_exp fields =
  let g k = List.assoc_opt k fields in
  let s k = match g k with Some (`String x) -> x | _ -> "?" in
  let state = s "state" in
  let cycle = match g "cycle" with Some (`Int c) -> c | _ -> 0 in
  let commit = match g "commit" with Some (`String c) -> Some c | _ -> None in
  let legal = match g "legal_edges" with
    | Some (`List xs) ->
        String.concat ", " (List.map (function `String x -> x | o -> Yojson.Safe.to_string o) xs)
    | _ -> "" in
  Printf.printf "%s\n└── %s %s - %s, cycle %d, commit %s\n"
    (s "quest") (tree_marker state) (s "exp") state cycle
    (short_commit commit);
  file_leaves_open "    " (g "changes");
  Printf.printf "    └── legal: %s\n" (if legal = "" then "none" else legal)

let print_verdict ~fmt v =
  match fmt, v with
  | "tree", `Assoc fields when List.mem_assoc "exps" fields ->
      render_tree fields
  | "tree", `Assoc fields when List.mem_assoc "exp" fields ->
      render_tree_exp fields
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

