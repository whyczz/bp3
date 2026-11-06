open Packet
open OUnit2

(* Every test owns its own Git repository and Board. No provider credentials,
   personal pi state or real Zellij session is touched by this suite. *)
type fixture = {
  root : string;
  repo : string;
  path : string;
  db : Store.t;
  sha : string;
}

let remove_tree path = ignore (Process.run [ "rm"; "-rf"; "--"; path ])

let fixture test =
  let root = Filename.temp_file "bp3-test-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let repo = Filename.concat root "repo"
  and path = Filename.concat root "board.sqlite" in
  Unix.mkdir repo 0o700;
  ignore (Process.git repo [ "init"; "-q"; "-b"; "master" ]);
  write_file
    (Filename.concat repo "hello.ml")
    "let () = print_endline \"hello\"\n";
  ignore (Process.git repo [ "add"; "." ]);
  ignore
    (Process.git repo
       [
         "-c";
         "user.name=test";
         "-c";
         "user.email=test@bp3.invalid";
         "commit";
         "-qm";
         "fixture";
       ]);
  ignore (Process.git repo [ "branch"; "quest/test" ]);
  let sha = Process.commit repo "HEAD" in
  Store.init path;
  let db = Store.open_db path in
  Fun.protect
    ~finally:(fun () ->
      Store.close db;
      remove_tree root)
    (fun () -> test { root; repo; path; db; sha })

let brief =
  obj
    [
      ("objective", str "hello");
      ("acceptance", str "prints hello");
      ("scope", str "hello.ml");
      ("non_goals", str "no publishing");
      ("check_argv", `List [ str "dune"; str "runtest" ]);
      ("max_seconds", int 3600);
    ]

let controller f op p = Board.apply f.db Board.Controller (envelope op p)
let runtime f op p = Board.apply f.db Board.Runtime (envelope op p)

let seed f =
  ignore
    (controller f "quest-create"
       (obj
          [
            ("id", str "q");
            ("intent", str "test genesis");
            ("repo", str f.repo);
            ("target", str "refs/heads/quest/test");
            ("base", str f.sha);
          ]));
  ignore
    (controller f "exp-create"
       (obj [ ("id", str "e"); ("quest_id", str "q"); ("brief", brief) ]))

let reserve f =
  ignore
    (runtime f "reserve"
       (obj
          [
            ("id", str "x");
            ("exp_id", str "e");
            ("worktree", str f.repo);
            ("branch", str "bp3/x");
            ("session_name", str "test");
          ]))

let auth f = Board.request_auth (Store.run f.db "x")
let worker_request f op payload = envelope ~auth:(auth f) op payload
let worker f op p = Board.apply f.db Board.Worker (worker_request f op p)

let signal_request f kind fields =
  envelope ~auth:(auth f) "signal"
    (obj ([ ("kind", str kind); ("session_id", str "pi-session") ] @ fields))

let signal f kind fields =
  Board.apply f.db Board.Bridge (signal_request f kind fields)

let ready f =
  List.iter
    (fun stage ->
      ignore
        (runtime f "launch-stage"
           (obj [ ("run_id", str "x"); ("stage", str stage) ])))
    [ "worktree"; "spawning" ];
  ignore
    (signal f "ready"
       [
         ("cwd", str f.repo);
         ("pid", int (Unix.getpid ()));
         ("pane_id", str "1");
         ("idle", `Bool true);
       ])

let started f =
  seed f;
  reserve f;
  ready f

let report f =
  worker_request f "report"
    (obj [ ("commit", str f.sha); ("evidence", str "worker claim only") ])

let count db table =
  Store.one db ("SELECT count(*) AS n FROM " ^ table) [] |> fun j ->
  number (get j "n")

let rejects thunk =
  match thunk () with
  | _ -> assert_failure "expected protocol refusal"
  | exception Error _ -> ()

let assert_field expected j key =
  assert_equal ~printer:encode expected (get j key)

let run f = Store.run f.db "x"
let test name body = name >:: fun _ -> fixture body

let block f =
  ignore
    (worker f "block"
       (obj
          [
            ("id", str "question");
            ("iiuc", str "check missing");
            ("challenge", str "guessing changes acceptance");
            ("recommendation", str "human chooses check");
          ]))

let reply f =
  ignore
    (controller f "steer"
       (obj
          [
            ("id", str "reply");
            ("run_id", str "x");
            ("question_id", str "question");
            ("text", str "use dune runtest");
          ]))

(* The pre-rename schema, kept only to prove the v1-to-v2 migration. *)
let v1_schema =
  {|
CREATE TABLE quests (
 id TEXT PRIMARY KEY, intent TEXT NOT NULL, repo TEXT NOT NULL,
 target TEXT NOT NULL, base TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'working');
CREATE TABLE exps (
 id TEXT PRIMARY KEY, quest_id TEXT NOT NULL REFERENCES quests(id), brief TEXT NOT NULL,
 base TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'working', generation INTEGER NOT NULL DEFAULT 0);
CREATE TABLE executions (
 id TEXT PRIMARY KEY, exp_id TEXT NOT NULL REFERENCES exps(id), generation INTEGER NOT NULL,
 token TEXT NOT NULL, brief TEXT NOT NULL, base TEXT NOT NULL,
 worktree TEXT NOT NULL, branch TEXT NOT NULL, session_name TEXT NOT NULL,
 launch_stage TEXT NOT NULL DEFAULT 'reserved', desired TEXT NOT NULL DEFAULT 'run',
 observed TEXT NOT NULL DEFAULT 'unknown', ready INTEGER NOT NULL DEFAULT 0,
 idle INTEGER NOT NULL DEFAULT 0, takeover INTEGER NOT NULL DEFAULT 0,
 permission INTEGER NOT NULL DEFAULT 0, endpoint TEXT, last_seen REAL,
 last_meaningful REAL, created REAL NOT NULL, deadline REAL NOT NULL,
 UNIQUE(exp_id, generation));
CREATE UNIQUE INDEX one_live_author ON executions((1)) WHERE desired='run';
CREATE TABLE results (
 id TEXT PRIMARY KEY, execution_id TEXT NOT NULL UNIQUE REFERENCES executions(id),
 commit_sha TEXT NOT NULL, evidence TEXT NOT NULL, brief TEXT NOT NULL);
CREATE TABLE questions (
 id TEXT PRIMARY KEY, execution_id TEXT NOT NULL REFERENCES executions(id),
 iiuc TEXT NOT NULL, challenge TEXT NOT NULL, recommendation TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'open', answer TEXT);
CREATE TABLE inbox (
 id TEXT PRIMARY KEY, execution_id TEXT NOT NULL REFERENCES executions(id),
 text TEXT NOT NULL, question_id TEXT REFERENCES questions(id),
 stage TEXT NOT NULL DEFAULT 'queued', created REAL NOT NULL);
CREATE TABLE receipts (id TEXT PRIMARY KEY, request TEXT NOT NULL, response TEXT NOT NULL);
CREATE TABLE events (
 seq INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE,
 kind TEXT NOT NULL, payload TEXT NOT NULL, at REAL NOT NULL);
PRAGMA user_version=1;
|}

let test_migration _ =
  let root = Filename.temp_file "bp3-migrate-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  Fun.protect
    ~finally:(fun () -> remove_tree root)
    (fun () ->
      let path = Filename.concat root "board.sqlite" in
      let old = Sqlite3.db_open path in
      Store.exec old v1_schema;
      Store.exec old
        "INSERT INTO quests \
         VALUES('q','intent','/repo','refs/heads/quest/test','base','working')";
      Store.exec old "INSERT INTO exps VALUES('e','q','{}','base','working',1)";
      Store.exec old
        "INSERT INTO executions \
         VALUES('x','e',1,'tok','{}','base','/wt','bp3/x','s','ready','run','live',1,1,0,0,NULL,NULL,NULL,0,4102444800)";
      Store.exec old "INSERT INTO results VALUES('r','x','sha','ev','{}')";
      Store.exec old
        "INSERT INTO questions VALUES('qq','x','i','c','rec','open',NULL)";
      Store.exec old "INSERT INTO inbox VALUES('m','x','text',NULL,'queued',0)";
      Store.close old;
      rejects (fun () -> Store.with_db path (fun _ -> ()));
      let backup = Store.migrate path in
      assert_equal (path ^ ".v1-backup") backup;
      assert_bool "v1 backup kept" (Sys.file_exists backup);
      Store.with_db path (fun db ->
          assert_equal 1 (count db "runs");
          assert_equal 1 (count db "run_outputs");
          assert_equal 1 (count db "questions");
          let snapshot = Store.snapshot_json db in
          assert_equal 1 (List.length (list (get snapshot "runs")));
          assert_field (str "x")
            (List.hd (list (get snapshot "run_outputs")))
            "run_id");
      rejects (fun () -> Store.migrate path))

let tests =
  [
    test "create/read frozen brief" (fun f ->
        seed f;
        let snapshot = Store.snapshot_json f.db in
        assert_equal 1 (List.length (list (get snapshot "quests")));
        assert_equal (encode brief)
          (field (List.hd (list (get snapshot "exps"))) "brief"));
    test "invalid brief rolls back event and receipt" (fun f ->
        seed f;
        let before = count f.db "events" in
        rejects (fun () ->
            controller f "exp-create"
              (obj
                 [ ("id", str "bad"); ("quest_id", str "q"); ("brief", obj []) ]));
        assert_equal before (count f.db "events");
        assert_equal 1 (count f.db "exps"));
    test "unsupported lane and dependencies refused" (fun _ ->
        let add k v =
          match brief with
          | `Assoc xs -> obj ((k, v) :: xs)
          | _ -> assert false
        in
        rejects (fun () -> validate_brief (add "lane" (str "micro")));
        rejects (fun () ->
            validate_brief (add "prerequisites" (`List [ str "missing" ]))));
    test "duplicate keys and invalid IDs refused" (fun _ ->
        rejects (fun () -> decode "{\"v\":1,\"v\":2}");
        List.iter
          (fun s -> rejects (fun () -> Packet.id s))
          [ ""; "../escape"; "space id" ]);
    test "same receipt retries once" (fun f ->
        started f;
        let request = report f in
        let first = Board.apply f.db Board.Worker request in
        assert_equal first (Board.apply f.db Board.Worker request);
        assert_equal 1 (count f.db "run_outputs"));
    test "semantic duplicate report has one Run Outputs" (fun f ->
        started f;
        ignore (Board.apply f.db Board.Worker (report f));
        ignore (Board.apply f.db Board.Worker (report f));
        assert_equal 1 (count f.db "run_outputs"));
    test "operation identity conflict refused" (fun f ->
        started f;
        let request = report f in
        ignore (Board.apply f.db Board.Worker request);
        let altered =
          match request with
          | `Assoc xs ->
              obj
                (( "payload",
                   obj [ ("commit", str f.sha); ("evidence", str "changed") ] )
                :: List.remove_assoc "payload" xs)
          | _ -> assert false
        in
        rejects (fun () -> Board.apply f.db Board.Worker altered));
    test "Run Outputs immutability" (fun f ->
        started f;
        ignore (Board.apply f.db Board.Worker (report f));
        rejects (fun () ->
            worker f "report"
              (obj
                 [ ("commit", str f.sha); ("evidence", str "different claim") ])));
    test "dirty Run Outputs refused" (fun f ->
        started f;
        write_file (Filename.concat f.repo "untracked") "not in commit";
        rejects (fun () -> Board.apply f.db Board.Worker (report f)));
    test "Run Outputs SHA must be exact" (fun f ->
        started f;
        rejects (fun () ->
            worker f "report"
              (obj [ ("commit", str "HEAD"); ("evidence", str "test") ])));
    test "wrong credentials cannot replay receipt" (fun f ->
        started f;
        let request = report f in
        ignore (Board.apply f.db Board.Worker request);
        let wrong =
          obj
            [
              ("run_id", str "x"); ("generation", int 1); ("token", str "wrong");
            ]
        in
        let altered =
          match request with
          | `Assoc xs -> obj (("auth", wrong) :: List.remove_assoc "auth" xs)
          | _ -> assert false
        in
        rejects (fun () -> Board.apply f.db Board.Worker altered));
    test "receipt replay survives cancel but new mutation fenced" (fun f ->
        started f;
        let request = report f in
        let response = Board.apply f.db Board.Worker request in
        ignore (controller f "cancel" (obj [ ("run_id", str "x") ]));
        assert_equal response (Board.apply f.db Board.Worker request);
        rejects (fun () -> Board.apply f.db Board.Worker (report f)));
    test "cross-run report refused" (fun f ->
        started f;
        rejects (fun () ->
            worker f "report"
              (obj
                 [
                   ("run_id", str "somebody-else");
                   ("commit", str f.sha);
                   ("evidence", str "test");
                 ])));
    test "Worker cannot manufacture Controller authority" (fun f ->
        started f;
        rejects (fun () -> worker f "cancel" (obj [ ("run_id", str "x") ])));
    test "not ready cannot receive brief" (fun f ->
        seed f;
        reserve f;
        rejects (fun () -> controller f "brief" (obj [ ("run_id", str "x") ])));
    test "session change rejected" (fun f ->
        started f;
        let request =
          envelope ~auth:(auth f) "signal"
            (obj
               [ ("kind", str "heartbeat"); ("session_id", str "replacement") ])
        in
        rejects (fun () -> Board.apply f.db Board.Bridge request));
    test "takeover blocks autonomous delivery and report" (fun f ->
        started f;
        ignore (controller f "brief" (obj [ ("run_id", str "x") ]));
        ignore (signal f "took_over" []);
        assert_field `Null (signal f "heartbeat" []) "inbox";
        rejects (fun () -> Board.apply f.db Board.Worker (report f));
        ignore (signal f "release" [ ("idle", `Bool true) ]);
        assert_bool "queued brief offered after release"
          (get (signal f "heartbeat" []) "inbox" <> `Null));
    test "busy release refused and permission distinct" (fun f ->
        started f;
        ignore (signal f "busy" []);
        rejects (fun () -> signal f "release" [ ("idle", `Bool false) ]);
        ignore (signal f "permission-start" []);
        assert_field (int 1) (run f) "permission";
        assert_field (int 0) (run f) "idle";
        ignore (signal f "permission-end" []);
        assert_field (int 0) (run f) "idle");
    test "settled must attest actual idle" (fun f ->
        started f;
        rejects (fun () -> signal f "settled" [ ("idle", `Bool false) ]);
        ignore (signal f "settled" [ ("idle", `Bool true) ]);
        assert_field (int 1) (run f) "idle");
    test "lost offer response replays but fresh poll never duplicates" (fun f ->
        started f;
        ignore (controller f "brief" (obj [ ("run_id", str "x") ]));
        let request = signal_request f "heartbeat" [] in
        let offered = Board.apply f.db Board.Bridge request in
        assert_bool "got inbox" (get offered "inbox" <> `Null);
        assert_equal offered (Board.apply f.db Board.Bridge request);
        assert_field `Null (signal f "heartbeat" []) "inbox";
        assert_equal "offered"
          (field (Store.one f.db "SELECT * FROM inbox" []) "stage"));
    test "cancelled bridge cannot replay an old delivery offer" (fun f ->
        started f;
        ignore (controller f "brief" (obj [ ("run_id", str "x") ]));
        let request = signal_request f "heartbeat" [] in
        ignore (Board.apply f.db Board.Bridge request);
        ignore (controller f "cancel" (obj [ ("run_id", str "x") ]));
        rejects (fun () -> Board.apply f.db Board.Bridge request));
    test "expired bridge cannot replay an old delivery offer" (fun f ->
        started f;
        ignore (controller f "brief" (obj [ ("run_id", str "x") ]));
        let request = signal_request f "heartbeat" [] in
        ignore (Board.apply f.db Board.Bridge request);
        Store.execute f.db "UPDATE runs SET deadline=0" [];
        rejects (fun () -> Board.apply f.db Board.Bridge request));
    test "takeover or permission cannot replay an old delivery offer" (fun f ->
        started f;
        ignore (controller f "brief" (obj [ ("run_id", str "x") ]));
        let request = signal_request f "heartbeat" [] in
        ignore (Board.apply f.db Board.Bridge request);
        ignore (signal f "took_over" []);
        rejects (fun () -> Board.apply f.db Board.Bridge request);
        ignore (signal f "release" [ ("idle", `Bool true) ]);
        ignore (signal f "permission-start" []);
        rejects (fun () -> Board.apply f.db Board.Bridge request));
    test "blocker answer requires explicit handling, not ACK" (fun f ->
        started f;
        block f;
        reply f;
        rejects (fun () -> Board.apply f.db Board.Worker (report f));
        ignore (signal f "heartbeat" []);
        rejects (fun () ->
            worker f "answer-handled" (obj [ ("inbox_id", str "reply") ]));
        ignore (signal f "observed" [ ("inbox_id", str "reply") ]);
        ignore (signal f "settled" [ ("idle", `Bool true) ]);
        rejects (fun () -> Board.apply f.db Board.Worker (report f));
        ignore (worker f "answer-handled" (obj [ ("inbox_id", str "reply") ]));
        ignore (Board.apply f.db Board.Worker (report f));
        assert_equal "handled"
          (field (Store.one f.db "SELECT * FROM questions" []) "state"));
    test "cancellation preserves unresolved questions" (fun f ->
        started f;
        block f;
        ignore (controller f "cancel" (obj [ ("run_id", str "x") ]));
        assert_equal "open"
          (field (Store.one f.db "SELECT * FROM questions" []) "state"));
    test "snapshot has no credentials and persists obligations" (fun f ->
        started f;
        block f;
        let snapshot = Store.snapshot_json f.db in
        let r = List.hd (list (get snapshot "runs")) in
        assert_field `Null r "token";
        Store.with_db f.path (fun reopened ->
            assert_equal 1
              (List.length
                 (list (get (Store.snapshot_json reopened) "questions")))));
    test "expired budget fences and never respawns" (fun f ->
        started f;
        Store.execute f.db "UPDATE runs SET deadline=0" [];
        ignore (runtime f "reconcile" (obj []));
        assert_field (str "expired") (run f) "desired";
        rejects (fun () -> signal f "heartbeat" []);
        assert_equal 1 (count f.db "runs"));
    test "stale heartbeat does not erase question or spawn" (fun f ->
        started f;
        block f;
        Store.execute f.db "UPDATE runs SET last_seen=0" [];
        ignore (runtime f "reconcile" (obj []));
        assert_field (str "stale") (run f) "observed";
        assert_equal 1 (count f.db "questions");
        assert_equal 1 (count f.db "runs");
        ignore (signal f "heartbeat" []);
        assert_field (str "live") (run f) "observed");
    test "Board copy is consistent and refuses overwrite" (fun f ->
        started f;
        block f;
        let destination = Filename.concat f.root "copy.sqlite" in
        Store.snapshot f.db destination;
        Store.with_db destination (fun copy ->
            assert_equal 1 (count copy "questions"));
        try
          Store.snapshot f.db destination;
          assert_failure "snapshot overwrote destination"
        with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    test "future schema fails closed" (fun f ->
        Store.exec f.db "PRAGMA user_version=3";
        rejects (fun () -> Store.with_db f.path (fun _ -> ())));
    test "partial steering failure rolls back answer and event" (fun f ->
        started f;
        block f;
        let before = count f.db "events" in
        rejects (fun () ->
            controller f "steer"
              (obj
                 [
                   ("id", str "bad-reply");
                   ("run_id", str "x");
                   ("question_id", str "question");
                   ("text", str "");
                 ]));
        assert_equal before (count f.db "events");
        assert_equal "open"
          (field (Store.one f.db "SELECT * FROM questions" []) "state"));
    test "single-author reservation rollback preserves second generation"
      (fun f ->
        started f;
        ignore
          (controller f "exp-create"
             (obj
                [
                  ("id", str "second"); ("quest_id", str "q"); ("brief", brief);
                ]));
        rejects (fun () ->
            runtime f "reserve"
              (obj
                 [
                   ("id", str "second-worker");
                   ("exp_id", str "second");
                   ("worktree", str f.root);
                   ("branch", str "bp3/second");
                   ("session_name", str "test");
                 ]));
        assert_equal 1 (count f.db "runs");
        assert_field (int 0)
          (Store.one f.db "SELECT * FROM exps WHERE id='second'" [])
          "generation");
    test "ambiguous launch reservation is returned, never respawned" (fun f ->
        seed f;
        let path = Filename.concat (Unix.realpath f.root) "x" in
        ignore
          (runtime f "reserve"
             (obj
                [
                  ("id", str "x");
                  ("exp_id", str "e");
                  ("worktree", str path);
                  ("branch", str "bp3/x");
                  ("session_name", str "test");
                ]));
        let payload =
          obj
            [
              ("run_id", str "x");
              ("exp_id", str "e");
              ("session_name", str "test");
              ("root", str f.root);
            ]
        in
        let result =
          Launcher.launch f.db ~board:f.path ~binary:"absent" ~bridge:"absent"
            payload
        in
        assert_field (`Bool true) result "replayed";
        assert_field (str "reserved") result "stage";
        assert_bool "no worktree side effect on ambiguous retry"
          (not (Sys.file_exists path)));
    test "runtime singleton, death and reconnect preserve obligations" (fun f ->
        started f;
        block f;
        let log =
          Unix.openfile
            (Filename.concat f.root "runtime.log")
            [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND ]
            0o600
        in
        let children = ref [] in
        let start () =
          let pid =
            Unix.create_process Sys.executable_name
              [| Sys.executable_name; "runtime-client"; f.path |]
              Unix.stdin log log
          in
          children := pid :: !children;
          pid
        in
        let call request = Lwt_main.run (Transport.call f.path request) in
        let ping = obj [ ("command", str "ping") ] in
        let rec await attempts predicate =
          if attempts = 0 then
            assert_failure
              ("runtime readiness timeout: "
              ^ read_file (Filename.concat f.root "runtime.log"))
          else if try predicate () with _ -> false then ()
          else (
            Unix.sleepf 0.05;
            await (attempts - 1) predicate)
        in
        let stop pid =
          Unix.kill pid Sys.sigkill;
          ignore (Process.wait pid);
          children := List.filter (( <> ) pid) !children
        in
        Fun.protect
          ~finally:(fun () ->
            List.iter
              (fun pid ->
                try
                  Unix.kill pid Sys.sigkill;
                  ignore (Process.wait pid)
                with _ -> ())
              !children;
            Unix.close log;
            let socket = Transport.socket_path f.path in
            if Sys.file_exists socket then Sys.remove socket)
          (fun () ->
            let first = start () in
            await 100 (fun () -> get (call ping) "pid" = int first);
            let duplicate = start () in
            assert_equal (Unix.WEXITED 1) (Process.wait duplicate);
            children := List.filter (( <> ) duplicate) !children;
            assert_field (int first) (call ping) "pid";
            stop first;
            assert_equal 1 (count f.db "questions");
            let second = start () in
            await 100 (fun () -> get (call ping) "pid" = int second);
            ignore
              (call
                 (obj
                    [
                      ("command", str "signal");
                      ("request", signal_request f "heartbeat" []);
                    ]));
            assert_field (str "live") (run f) "observed";
            Store.execute f.db "UPDATE runs SET last_seen=0" [];
            await 100 (fun () -> get (run f) "observed" = str "stale");
            assert_equal 1 (count f.db "runs");
            assert_equal 1 (count f.db "questions");
            stop second));
    test "concurrent report retries commit one receipt" (fun f ->
        started f;
        let request = report f in
        let request_path = Filename.concat f.root "retry.json" in
        write_file request_path (encode request);
        (* SQLite connections cannot be inherited across fork. Exec a fresh
           client, exactly as six independent Worker shells would do. *)
        let children =
          List.init 6 (fun _ ->
              Unix.create_process Sys.executable_name
                [| Sys.executable_name; "replay-client"; f.path; request_path |]
                Unix.stdin Unix.stdout Unix.stderr)
        in
        List.iter
          (fun pid -> assert_equal (Unix.WEXITED 0) (Process.wait pid))
          children;
        assert_equal 1 (count f.db "run_outputs");
        assert_equal 1
          (List.length
             (Store.query f.db "SELECT * FROM receipts WHERE id=?"
                [ get request "op_id" ])));
    "schema v1 migrates to runs and run_outputs" >:: test_migration;
  ]

let () =
  match Array.to_list Sys.argv with
  | [ _; "replay-client"; board; request ] ->
      Store.with_db board (fun db ->
          ignore (Board.apply db Board.Worker (decode (read_file request))))
  | [ _; "runtime-client"; board ] -> (
      try
        Runtime.serve ~board ~binary:Sys.executable_name
          ~bridge:Sys.executable_name
      with Packet.Error message ->
        prerr_endline message;
        exit 1)
  | _ -> run_test_tt_main ("genesis" >::: tests)
