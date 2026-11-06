open Packet

type t = Sqlite3.db

let check db rc =
  match rc with
  | Sqlite3.Rc.OK | Sqlite3.Rc.DONE -> ()
  | _ -> fail (Sqlite3.errmsg db)

let exec db sql = check db (Sqlite3.exec db sql)

let data = function
  | `Null -> Sqlite3.Data.NULL
  | `String s -> Sqlite3.Data.TEXT s
  | `Int n -> Sqlite3.Data.INT (Int64.of_int n)
  | `Float f -> Sqlite3.Data.FLOAT f
  | `Bool b -> Sqlite3.Data.INT (if b then 1L else 0L)
  | j -> Sqlite3.Data.TEXT (encode j)

let json = function
  | Sqlite3.Data.NULL | Sqlite3.Data.NONE -> `Null
  | Sqlite3.Data.INT n -> `Int (Int64.to_int n)
  | Sqlite3.Data.FLOAT f -> `Float f
  | Sqlite3.Data.TEXT s | Sqlite3.Data.BLOB s -> str s

let statement db sql args f =
  let s = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize s))
    (fun () ->
      check db (Sqlite3.bind_values s (List.map data args));
      f s)

let query db sql args =
  statement db sql args (fun s ->
      let rec loop rows =
        match Sqlite3.step s with
        | Sqlite3.Rc.ROW ->
            let row =
              obj
                (List.init (Sqlite3.column_count s) (fun i ->
                     (Sqlite3.column_name s i, json (Sqlite3.column s i))))
            in
            loop (row :: rows)
        | Sqlite3.Rc.DONE -> List.rev rows
        | rc ->
            check db rc;
            assert false
      in
      loop [])

let one db sql args =
  match query db sql args with
  | [ row ] -> row
  | [] -> fail "record not found"
  | _ -> fail "expected one record"

let execute db sql args =
  statement db sql args (fun s -> check db (Sqlite3.step s))

let transaction db f =
  exec db "BEGIN IMMEDIATE";
  try
    let result = f () in
    exec db "COMMIT";
    result
  with e ->
    exec db "ROLLBACK";
    raise e

let close db = ignore (Sqlite3.db_close db)

let schema_version db =
  one db "PRAGMA user_version" [] |> fun j -> number (get j "user_version")

let open_db path =
  if not (Sys.file_exists path) then
    fail "Board absent; run bp3 --board PATH init";
  let db = Sqlite3.db_open path in
  try
    Sqlite3.busy_timeout db 5000;
    let version = schema_version db in
    if version = 1 then fail "Board schema 1; run bp3 --board PATH migrate";
    if version <> 2 then
      fail (Printf.sprintf "unsupported Board schema %d (expected 2)" version);
    exec db "PRAGMA foreign_keys=ON";
    db
  with e ->
    close db;
    raise e

let with_db path f =
  let db = open_db path in
  Fun.protect ~finally:(fun () -> close db) (fun () -> f db)

let schema =
  {|
CREATE TABLE quests (
 id TEXT PRIMARY KEY, intent TEXT NOT NULL, repo TEXT NOT NULL,
 target TEXT NOT NULL, base TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'working');
CREATE TABLE exps (
 id TEXT PRIMARY KEY, quest_id TEXT NOT NULL REFERENCES quests(id), brief TEXT NOT NULL,
 base TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'working', generation INTEGER NOT NULL DEFAULT 0);
CREATE TABLE runs (
 id TEXT PRIMARY KEY, exp_id TEXT NOT NULL REFERENCES exps(id), generation INTEGER NOT NULL,
 token TEXT NOT NULL, brief TEXT NOT NULL, base TEXT NOT NULL,
 worktree TEXT NOT NULL, branch TEXT NOT NULL, session_name TEXT NOT NULL,
 launch_stage TEXT NOT NULL DEFAULT 'reserved', desired TEXT NOT NULL DEFAULT 'run',
 observed TEXT NOT NULL DEFAULT 'unknown', ready INTEGER NOT NULL DEFAULT 0,
 idle INTEGER NOT NULL DEFAULT 0, takeover INTEGER NOT NULL DEFAULT 0,
 permission INTEGER NOT NULL DEFAULT 0, endpoint TEXT, last_seen REAL,
 last_meaningful REAL, created REAL NOT NULL, deadline REAL NOT NULL,
 UNIQUE(exp_id, generation));
CREATE UNIQUE INDEX one_live_run ON runs((1)) WHERE desired='run';
CREATE TABLE run_outputs (
 id TEXT PRIMARY KEY, run_id TEXT NOT NULL UNIQUE REFERENCES runs(id),
 commit_sha TEXT NOT NULL, evidence TEXT NOT NULL, brief TEXT NOT NULL);
CREATE TABLE questions (
 id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES runs(id),
 iiuc TEXT NOT NULL, challenge TEXT NOT NULL, recommendation TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'open', answer TEXT);
CREATE TABLE inbox (
 id TEXT PRIMARY KEY, run_id TEXT NOT NULL REFERENCES runs(id),
 text TEXT NOT NULL, question_id TEXT REFERENCES questions(id),
 stage TEXT NOT NULL DEFAULT 'queued', created REAL NOT NULL);
CREATE TABLE receipts (id TEXT PRIMARY KEY, request TEXT NOT NULL, response TEXT NOT NULL);
CREATE TABLE events (
 seq INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE,
 kind TEXT NOT NULL, payload TEXT NOT NULL, at REAL NOT NULL);
PRAGMA user_version=2;
|}

let init path =
  mkdir (Filename.dirname path);
  let fd =
    Unix.openfile path [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ] 0o600
  in
  Unix.close fd;
  let db = Sqlite3.db_open path in
  Fun.protect
    ~finally:(fun () -> close db)
    (fun () ->
      exec db "PRAGMA journal_mode=WAL";
      exec db "PRAGMA synchronous=FULL";
      transaction db (fun () -> exec db schema))

let snapshot db destination =
  let fd =
    Unix.openfile destination [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ] 0o600
  in
  Unix.close fd;
  let dst = Sqlite3.db_open destination in
  Fun.protect
    ~finally:(fun () -> close dst)
    (fun () ->
      let backup =
        Sqlite3.Backup.init ~dst ~dst_name:"main" ~src:db ~src_name:"main"
      in
      Fun.protect
        ~finally:(fun () -> check dst (Sqlite3.Backup.finish backup))
        (fun () -> check dst (Sqlite3.Backup.step backup (-1))))

(* Rename-only v1-to-v2 migration: executions -> runs, results -> run_outputs,
   execution_id -> run_id. No rows, receipts or obligations change meaning.
   The caller must stop the runtime first; a consistent v1 backup is kept. *)
let migrate path =
  if not (Sys.file_exists path) then
    fail "Board absent; run bp3 --board PATH init";
  let backup = path ^ ".v1-backup" in
  if Sys.file_exists backup then fail ("migration backup exists: " ^ backup);
  let db = Sqlite3.db_open path in
  Fun.protect
    ~finally:(fun () -> close db)
    (fun () ->
      Sqlite3.busy_timeout db 5000;
      let version = schema_version db in
      if version = 2 then fail "Board already schema 2";
      if version <> 1 then
        fail (Printf.sprintf "unsupported Board schema %d (expected 1)" version);
      snapshot db backup;
      transaction db (fun () ->
          exec db "ALTER TABLE executions RENAME TO runs";
          exec db "DROP INDEX one_live_author";
          exec db
            "CREATE UNIQUE INDEX one_live_run ON runs((1)) WHERE desired='run'";
          exec db "ALTER TABLE results RENAME TO run_outputs";
          exec db "ALTER TABLE run_outputs RENAME COLUMN execution_id TO run_id";
          exec db "ALTER TABLE questions RENAME COLUMN execution_id TO run_id";
          exec db "ALTER TABLE inbox RENAME COLUMN execution_id TO run_id";
          exec db "PRAGMA user_version=2");
      backup)

let run db id = one db "SELECT * FROM runs WHERE id=?" [ str id ]

let event db op_id kind payload =
  execute db "INSERT INTO events(op_id,kind,payload,at) VALUES(?,?,?,?)"
    [ str op_id; str kind; payload; `Float (now ()) ]

let snapshot_json db =
  (* One read transaction: the event cursor and all projections agree. *)
  exec db "BEGIN";
  Fun.protect
    ~finally:(fun () -> exec db "COMMIT")
    (fun () ->
      let rows sql = `List (query db sql []) in
      obj
        [
          ("schema", int 2);
          ("at", `Float (now ()));
          ( "cursor",
            get
              (one db "SELECT coalesce(max(seq),0) AS cursor FROM events" [])
              "cursor" );
          ("quests", rows "SELECT * FROM quests ORDER BY id");
          ("exps", rows "SELECT * FROM exps ORDER BY id");
          ( "runs",
            rows
              "SELECT \
               id,exp_id,generation,brief,base,worktree,branch,session_name,launch_stage,desired,observed,ready,idle,takeover,permission,endpoint,last_seen,last_meaningful,created,deadline \
               FROM runs ORDER BY created" );
          ("run_outputs", rows "SELECT * FROM run_outputs ORDER BY id");
          ("questions", rows "SELECT * FROM questions ORDER BY id");
          ("inbox", rows "SELECT * FROM inbox ORDER BY created,id");
          ("cost", `Null);
        ])
