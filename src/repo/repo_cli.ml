(* repo_cli — CLI door for `bp3 repo` (sqlite-control-plane repo.1).
   Returns an int exit code directly so main.ml dispatches in one line
   with zero dependency on bp3_quest. *)

let help_text =
  {|bp3 repo — machine-local git repository registry in bp3.sqlite.

Usage:
  bp3 repo add [<path>] [--name <slug>]      register or refresh a local git repo (default: current repo)
  bp3 repo list [--format json|table]        list registered repos
  bp3 repo remove <name>                     unregister a repo (preserves historical tickets)
  bp3 repo -h | --help                       show this help (never touches the DB)

Exit codes:
  0  ok
  1  conflict or DB error (E_EXISTS, E_DB_ERROR)
  2  usage or not-found error (E_USAGE, E_NOT_FOUND)
|}

let is_help = function "-h" | "--help" -> true | _ -> false

let parse_add_args args =
  let rec loop path name = function
    | [] -> (path, name)
    | "--name" :: v :: rest ->
        if name <> None then Db.usage "duplicate flag --name";
        if v = "" then Db.usage "--name cannot be empty";
        loop path (Some v) rest
    | [ "--name" ] -> Db.usage "--name needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | p :: rest ->
        if path <> None then Db.usage ("stray positional: " ^ p);
        loop (Some p) name rest
  in
  loop None None args

let parse_list_flags args =
  let rec loop fmt fmt_set = function
    | [] -> fmt
    | "--format" :: v :: rest ->
        if fmt_set then Db.usage "duplicate flag --format";
        if v <> "json" && v <> "table" then Db.usage "--format must be json or table";
        loop v true rest
    | [ "--format" ] -> Db.usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | stray :: _ -> Db.usage ("stray positional: " ^ stray)
  in
  loop "json" false args

let format_list_table repos =
  let rows =
    List.map
      (fun (r : Repo_store.repo) -> [ r.name; r.root_path; r.last_seen_at ])
      repos
  in
  Db.format_table [ "name"; "root_path"; "last_seen_at" ] rows

let run_inner ?db_path = function
  | [] -> Db.usage "repo needs a subcommand: add, list, remove (see bp3 repo -h)"
  | h :: _ when is_help h ->
      print_string help_text;
      0
  | ("add" | "list" | "remove") :: h :: _ when is_help h ->
      print_string help_text;
      0
  | "add" :: rest ->
      let path, name = parse_add_args rest in
      let r = Repo_store.add ?db_path ?path ?name () in
      print_endline
        (Yojson.Safe.to_string (`Assoc [ ("ok", `Bool true); ("repo", Repo_store.repo_json r) ]));
      0
  | "list" :: rest ->
      let fmt = parse_list_flags rest in
      let repos = Repo_store.list ?db_path () in
      (match fmt with
       | "table" -> print_string (format_list_table repos)
       | _ ->
           print_endline
             (Yojson.Safe.to_string
                (`Assoc [ ("ok", `Bool true); ("repos", `List (List.map Repo_store.repo_json repos)) ])));
      0
  | [ "remove"; name ] ->
      Repo_store.remove ?db_path name;
      print_endline
        (Yojson.Safe.to_string (`Assoc [ ("ok", `Bool true); ("removed", Db.json_str name) ]));
      0
  | "remove" :: [] -> Db.usage "repo remove needs <name>"
  | "remove" :: _ :: stray :: _ -> Db.usage ("stray positional: " ^ stray)
  | sub :: _ -> Db.usage ("unknown repo subcommand: " ^ sub ^ " (expected: add, list, remove)")

let run ?db_path args =
  try run_inner ?db_path args
  with Db.Error (code, json) ->
    print_endline (Yojson.Safe.to_string json);
    code
