(* repo_store — machine-local git repo registry in bp3.sqlite (sqlite-control-plane repo.1).
   Zero dependency on bp3_quest; uses only one read-only git call
   (`git -C <path> rev-parse --git-common-dir`) plus Unix.realpath so worktrees
   and symlinks resolve to the same canonical main repository root. *)

type repo = {
  name : string;
  root_path : string;
  added_at : string;
  last_seen_at : string;
}

let run_git_capture dir args =
  let argv = Array.of_list ("git" :: "-C" :: dir :: args) in
  let null_in = Unix.openfile "/dev/null" [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
  let null_err = Unix.openfile "/dev/null" [ Unix.O_WRONLY; Unix.O_CLOEXEC ] 0 in
  let out_r, out_w = Unix.pipe ~cloexec:true () in
  let pid =
    try Some (Unix.create_process "git" argv null_in out_w null_err)
    with Unix.Unix_error _ -> None
  in
  Unix.close null_in;
  Unix.close null_err;
  Unix.close out_w;
  let ic = Unix.in_channel_of_descr out_r in
  let out = Fun.protect ~finally:(fun () -> close_in ic) (fun () -> In_channel.input_all ic) in
  let rec wait p =
    try snd (Unix.waitpid [] p) with Unix.Unix_error (Unix.EINTR, _, _) -> wait p
  in
  let code =
    match pid with
    | None -> 127
    | Some p -> ( match wait p with Unix.WEXITED n -> n | _ -> 255)
  in
  (String.trim out, code)

let canon p = try Unix.realpath p with _ -> p

let resolve_main_root path =
  if not (Sys.file_exists path) then Db.not_found "path" path;
  let out, code = run_git_capture path [ "rev-parse"; "--git-common-dir" ] in
  if code <> 0 || out = "" then Db.not_found "git repository" path;
  let abs_common =
    let joined = if Filename.is_relative out then Filename.concat path out else out in
    canon joined
  in
  let main =
    if Filename.basename abs_common = ".git" then Filename.dirname abs_common
    else abs_common
  in
  canon main

let is_git_repo path =
  try
    ignore (resolve_main_root path);
    true
  with Db.Error _ -> false

let row_to_repo row =
  {
    name = Db.data_to_str row.(0);
    root_path = Db.data_to_str row.(1);
    added_at = Db.data_to_str row.(2);
    last_seen_at = Db.data_to_str row.(3);
  }

let find_by_name_in db name =
  match
    Db.query_rows db
      "SELECT name, root_path, added_at, last_seen_at FROM repos WHERE name = ?;"
      [ Sqlite3.Data.TEXT name ]
  with
  | row :: _ -> Some (row_to_repo row)
  | [] -> None

let find_by_path_in db root_path =
  match
    Db.query_rows db
      "SELECT name, root_path, added_at, last_seen_at FROM repos WHERE root_path = ?;"
      [ Sqlite3.Data.TEXT root_path ]
  with
  | row :: _ -> Some (row_to_repo row)
  | [] -> None

let list_in db =
  Db.query_rows db
    "SELECT name, root_path, added_at, last_seen_at FROM repos ORDER BY name ASC;" []
  |> List.map row_to_repo

let list_names_in db = list_in db |> List.map (fun r -> r.name)

let exists_in db name = find_by_name_in db name <> None

let default_caller_path () =
  match Sys.getenv_opt "BP3_ROOT" with
  | Some r when r <> "" -> r
  | _ -> Sys.getcwd ()

let add ?db_path ?path ?name () =
  let target =
    match path with Some p when p <> "" -> p | _ -> default_caller_path ()
  in
  let root_path = resolve_main_root target in
  let repo_name =
    match name with
    | Some n ->
        if Db.valid_slug n then n
        else Db.usage ("invalid repo name (must be kebab-case [a-z0-9-]): " ^ n)
    | None -> (
        match Db.slugify (Filename.basename root_path) with
        | Ok s -> s
        | Error m -> Db.usage m)
  in
  let ts = Db.now_ts () in
  Db.with_db ?path:db_path (fun db ->
      Db.with_tx_immediate db (fun db ->
          (* When --name is omitted and root_path is already registered (e.g. under a
             custom alias), refresh last_seen_at on the existing entry instead of
             failing E_EXISTS on auto-register. *)
          match (name, find_by_path_in db root_path) with
          | None, Some existing ->
              Db.exec_params db "UPDATE repos SET last_seen_at = ? WHERE name = ?;"
                [ Sqlite3.Data.TEXT ts; Sqlite3.Data.TEXT existing.name ];
              { existing with last_seen_at = ts }
          | _ -> (
              (match find_by_name_in db repo_name with
               | Some existing when existing.root_path <> root_path ->
                   Db.verdict_err "E_EXISTS"
                     (`Assoc
                        [
                          ("name", Db.json_str repo_name);
                          ("existing_path", Db.json_str existing.root_path);
                          ("requested_path", Db.json_str root_path);
                        ])
                     (Printf.sprintf "Repo name %S already points to %s." repo_name existing.root_path)
                     1
               | _ -> ());
              (match find_by_path_in db root_path with
               | Some existing when existing.name <> repo_name ->
                   Db.verdict_err "E_EXISTS"
                     (`Assoc
                        [
                          ("root_path", Db.json_str root_path);
                          ("existing_name", Db.json_str existing.name);
                          ("requested_name", Db.json_str repo_name);
                        ])
                     (Printf.sprintf "Repo path %s is already registered as %S." root_path existing.name)
                     1
               | _ -> ());
              match find_by_name_in db repo_name with
              | Some existing ->
                  Db.exec_params db "UPDATE repos SET last_seen_at = ? WHERE name = ?;"
                    [ Sqlite3.Data.TEXT ts; Sqlite3.Data.TEXT repo_name ];
                  { existing with last_seen_at = ts }
              | None ->
                  Db.exec_params db
                    "INSERT INTO repos (name, root_path, added_at, last_seen_at) VALUES (?, ?, ?, ?);"
                    [
                      Sqlite3.Data.TEXT repo_name;
                      Sqlite3.Data.TEXT root_path;
                      Sqlite3.Data.TEXT ts;
                      Sqlite3.Data.TEXT ts;
                    ];
                  { name = repo_name; root_path; added_at = ts; last_seen_at = ts })))

let list ?db_path () = Db.with_db ?path:db_path list_in

let remove ?db_path name =
  if not (Db.valid_slug name) then Db.usage ("invalid repo name: " ^ name);
  Db.with_db ?path:db_path (fun db ->
      Db.with_tx_immediate db (fun db ->
          Db.exec_params db "DELETE FROM repos WHERE name = ?;" [ Sqlite3.Data.TEXT name ];
          if Sqlite3.changes db = 0 then Db.not_found "repo" name))

let infer_from_root_in db path =
  try
    let root_path = resolve_main_root path in
    match find_by_path_in db root_path with
    | Some r -> Some r.name
    | None -> (
        match Db.slugify (Filename.basename root_path) with
        | Ok s -> Some s
        | Error _ -> None)
  with Db.Error _ -> None

let repo_json (r : repo) =
  `Assoc
    [
      ("name", Db.json_str r.name);
      ("root_path", Db.json_str r.root_path);
      ("added_at", Db.json_str r.added_at);
      ("last_seen_at", Db.json_str r.last_seen_at);
    ]
