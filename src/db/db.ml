(* db — machine-local SQLite WAL store (sqlite-control-plane db.1).
   Bottom-layer plumbing: DB path resolution, WAL/busy_timeout/foreign_keys
   pragmas, PRAGMA user_version migrations, transactional helpers, and
   shared CLI verdict/slug/clock primitives for bp3_db / bp3_repo / bp3_ticket.
   Zero dependency on bp3_quest. *)

let current_version = 1

exception Error of int * Yojson.Safe.t

let json_str s = `String s

let verdict_err code facts guidance exit_code =
  raise
    (Error
       ( exit_code,
         `Assoc
           [
             ("ok", `Bool false);
             ( "error",
               `Assoc
                 [
                   ("code", json_str code);
                   ("facts", facts);
                   ("guidance", json_str guidance);
                 ] );
           ] ))

let usage msg =
  verdict_err "E_USAGE" (`Assoc [ ("detail", json_str msg) ]) ("Fix the call: " ^ msg) 2

let not_found ?(extra = []) what name =
  verdict_err "E_NOT_FOUND"
    (`Assoc ((what, json_str name) :: extra))
    (what ^ " not found: " ^ name) 2

let db_error detail =
  verdict_err "E_DB_ERROR"
    (`Assoc [ ("detail", json_str detail) ])
    ("SQLite error: " ^ detail) 1

let valid_slug s =
  let n = String.length s in
  n >= 1
  &&
  let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' in
  let rec loop i = i >= n || (ok s.[i] && loop (i + 1)) in
  ((s.[0] >= 'a' && s.[0] <= 'z') || (s.[0] >= '0' && s.[0] <= '9')) && loop 1

let slugify raw =
  let b = Buffer.create (String.length raw) in
  let prev_dash = ref true in
  String.iter
    (fun c ->
      let c = Char.lowercase_ascii c in
      if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') then begin
        Buffer.add_char b c;
        prev_dash := false
      end else if not !prev_dash then begin
        Buffer.add_char b '-';
        prev_dash := true
      end)
    raw;
  let s = Buffer.contents b in
  let len = String.length s in
  let s = if len > 0 && s.[len - 1] = '-' then String.sub s 0 (len - 1) else s in
  if valid_slug s then Ok s
  else Error ("cannot derive a valid slug from: " ^ raw)

let now_ts () =
  let t = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let non_empty = function Some s when s <> "" -> Some s | _ -> None

let resolve_path_of ~bp3_db ~xdg_data_home ~home =
  match non_empty bp3_db with
  | Some p -> p
  | None -> (
      match non_empty xdg_data_home with
      | Some xdg -> Filename.concat (Filename.concat xdg "bp3") "bp3.sqlite"
      | None ->
          let h = Option.value ~default:"." (non_empty home) in
          Filename.concat
            (Filename.concat (Filename.concat (Filename.concat h ".local") "share") "bp3")
            "bp3.sqlite")

let resolve_path () =
  resolve_path_of
    ~bp3_db:(Sys.getenv_opt "BP3_DB")
    ~xdg_data_home:(Sys.getenv_opt "XDG_DATA_HOME")
    ~home:(Sys.getenv_opt "HOME")

let rec mkdir_p dir =
  if dir = "" || dir = "." || dir = "/" then ()
  else if Sys.file_exists dir then begin
    if not (Sys.is_directory dir) then
      db_error ("parent path is not a directory: " ^ dir)
  end else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755
    with
    | Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    | Unix.Unix_error (e, _, _) ->
        db_error (Printf.sprintf "mkdir %s: %s" dir (Unix.error_message e))
  end

let check_rc db context rc =
  if not (Sqlite3.Rc.is_success rc) then
    db_error (Printf.sprintf "%s (%s): %s" context (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))

let exec_sql db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> check_rc db "exec" rc

let bind_all db stmt params =
  List.iteri
    (fun i v ->
      let rc = Sqlite3.bind stmt (i + 1) v in
      check_rc db "bind" rc)
    params

let query_rows db sql params =
  let stmt =
    try Sqlite3.prepare db sql
    with Sqlite3.Error m -> db_error ("prepare: " ^ m)
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      bind_all db stmt params;
      let ncols = Sqlite3.data_count stmt in
      let _ = ncols in
      let rec loop acc =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW ->
            let row = Sqlite3.row_data stmt in
            loop (row :: acc)
        | Sqlite3.Rc.DONE -> List.rev acc
        | rc ->
            check_rc db "step" rc;
            List.rev acc
      in
      loop [])

let exec_params db sql params =
  let stmt =
    try Sqlite3.prepare db sql
    with Sqlite3.Error m -> db_error ("prepare: " ^ m)
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      bind_all db stmt params;
      match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE | Sqlite3.Rc.OK | Sqlite3.Rc.ROW -> ()
      | rc -> check_rc db "step" rc)

let data_to_int = function
  | Sqlite3.Data.INT i -> Int64.to_int i
  | Sqlite3.Data.TEXT s -> (try int_of_string s with _ -> 0)
  | _ -> 0

let data_to_str = function
  | Sqlite3.Data.TEXT s -> s
  | Sqlite3.Data.INT i -> Int64.to_string i
  | Sqlite3.Data.FLOAT f -> string_of_float f
  | Sqlite3.Data.BLOB s -> s
  | Sqlite3.Data.NULL | Sqlite3.Data.NONE -> ""

let data_to_str_opt = function
  | Sqlite3.Data.NULL | Sqlite3.Data.NONE -> None
  | d -> Some (data_to_str d)

let query_int db sql params =
  match query_rows db sql params with
  | row :: _ when Array.length row > 0 -> data_to_int row.(0)
  | _ -> 0

let query_str db sql params =
  match query_rows db sql params with
  | row :: _ when Array.length row > 0 -> data_to_str row.(0)
  | _ -> ""

let with_tx_immediate db f =
  exec_sql db "BEGIN IMMEDIATE;";
  try
    let res = f db in
    exec_sql db "COMMIT;";
    res
  with e ->
    (try ignore (Sqlite3.exec db "ROLLBACK;") with _ -> ());
    raise e

let schema_v1_sql =
  {|
CREATE TABLE IF NOT EXISTS repos (
  name         TEXT PRIMARY KEY,
  root_path    TEXT NOT NULL UNIQUE,
  added_at     TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tickets (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  from_repo         TEXT NOT NULL,
  to_repo           TEXT NOT NULL,
  kind              TEXT NOT NULL CHECK (kind IN ('bug', 'feature', 'note')),
  title             TEXT NOT NULL,
  body              TEXT NOT NULL DEFAULT '',
  status            TEXT NOT NULL CHECK (status IN ('open', 'claimed', 'done', 'dismissed')),
  claimed_by        TEXT,
  claimed_at        TEXT,
  resolved_at       TEXT,
  resolution_reason TEXT,
  created_at        TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tickets_to_status ON tickets(to_repo, status);
|}

let migrate db =
  let ver = query_int db "PRAGMA user_version;" [] in
  if ver = current_version then ()
  else
    with_tx_immediate db (fun db ->
        let ver = query_int db "PRAGMA user_version;" [] in
        if ver = 0 then begin
          exec_sql db schema_v1_sql;
          exec_sql db (Printf.sprintf "PRAGMA user_version = %d;" current_version)
        end else if ver = current_version then ()
        else if ver > current_version then
          db_error
            (Printf.sprintf "DB schema v%d is newer than this bp3 (v%d)" ver current_version)
        else
          db_error (Printf.sprintf "unsupported DB schema version: %d" ver))

let with_db ?path f =
  let p = match path with Some p -> p | None -> resolve_path () in
  if p <> ":memory:" then mkdir_p (Filename.dirname p);
  let db =
    try Sqlite3.db_open p
    with
    | Sqlite3.Error m -> db_error (Printf.sprintf "open %s: %s" p m)
    | Sys_error m -> db_error m
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close db))
    (fun () ->
      try
        exec_sql db "PRAGMA busy_timeout = 5000;";
        ignore (query_str db "PRAGMA journal_mode = WAL;" []);
        exec_sql db "PRAGMA foreign_keys = ON;";
        migrate db;
        f db
      with
      | Error _ as e -> raise e
      | Sqlite3.Error m -> db_error m
      | Sys_error m -> db_error m
      | Unix.Unix_error (e, fn, arg) ->
          db_error (Printf.sprintf "%s %s: %s" fn arg (Unix.error_message e)))

type db_info = {
  db_path : string;
  schema_version : int;
  journal_mode : string;
  repos_count : int;
  tickets_open : int;
  tickets_total : int;
}

let info ?path () =
  let p = match path with Some p -> p | None -> resolve_path () in
  with_db ~path:p (fun db ->
      let schema_version = query_int db "PRAGMA user_version;" [] in
      let journal_mode =
        String.lowercase_ascii (query_str db "PRAGMA journal_mode;" [])
      in
      let repos_count = query_int db "SELECT COUNT(*) FROM repos;" [] in
      let tickets_open =
        query_int db "SELECT COUNT(*) FROM tickets WHERE status = 'open';" []
      in
      let tickets_total = query_int db "SELECT COUNT(*) FROM tickets;" [] in
      { db_path = p; schema_version; journal_mode; repos_count; tickets_open; tickets_total })

let info_json (i : db_info) =
  `Assoc
    [
      ("ok", `Bool true);
      ("db_path", json_str i.db_path);
      ("schema_version", `Int i.schema_version);
      ("journal_mode", json_str i.journal_mode);
      ( "counts",
        `Assoc
          [
            ("repos", `Int i.repos_count);
            ("tickets_open", `Int i.tickets_open);
            ("tickets_total", `Int i.tickets_total);
          ] );
    ]

let pad_to w s =
  let n = String.length s in
  if n >= w then s else s ^ String.make (w - n) ' '

let format_table headers rows =
  let widths =
    List.mapi
      (fun i h ->
        List.fold_left
          (fun w row ->
            match List.nth_opt row i with Some c -> max w (String.length c) | None -> w)
          (String.length h) rows)
      headers
  in
  let last = List.length headers - 1 in
  let fmt_line cells =
    String.concat "  "
      (List.mapi
         (fun i c ->
           if i = last then c
           else match List.nth_opt widths i with Some w -> pad_to w c | None -> c)
         cells)
  in
  String.concat "\n" (fmt_line headers :: List.map fmt_line rows) ^ "\n"
