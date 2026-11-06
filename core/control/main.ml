open Packet

let usage =
  {|bp3 --board PATH COMMAND
  init                         Create schema v1 Board (refuses overwrite)
  context                      JSON recovery snapshot, no model call
  op FILE|-                    Apply v1 JSON mutation (stable op_id required)
  runtime --binary PATH --bridge PATH
                               Own signal socket and reconcile until stopped
  launch FILE                  JSON: execution_id, exp_id, root, model?, session_name?
                               BP3_SESSION supplies/binds session_name when set
  ping                         Probe runtime ownership
  snapshot PATH                Consistent SQLite copy (not a Git/session backup)

Controller ops: quest-create, exp-create, brief, steer, cancel.
Worker ops: block, answer-handled, report; credentials supplied by BP3_* env.
No review, auto-land, promotion or push commands exist in genesis.
See docs/exp/2026-11-05-genesis.md for the contract and runbook.
|}

let output j = print_endline (Yojson.Safe.pretty_to_string j)

let read_json path =
  if path <> "-" then decode (read_file path)
  else
    let buffer = Buffer.create 1024 in
    (try
       while true do
         Buffer.add_string buffer (input_line stdin);
         Buffer.add_char buffer '\n'
       done
     with End_of_file -> ());
    decode (Buffer.contents buffer)

let env_auth () =
  match Sys.getenv_opt "BP3_EXECUTION" with
  | None -> None
  | Some execution_id ->
      Some
        (obj
           [
             ("execution_id", str execution_id);
             ("generation", int (int_of_string (Sys.getenv "BP3_GENERATION")));
             ("token", str (Sys.getenv "BP3_TOKEN"));
           ])

let run board args =
  let auth = env_auth () in
  (* Cooperative authority: accidental Controller calls from Worker shells fail.
    A same-user malicious process can bypass env/SQLite; this is not isolation. *)
  if
    auth <> None
    &&
    match args with
    | "op" :: _ | [ "context" ] -> false
    | _ -> true
  then fail "command unavailable to Worker";
  match args with
  | [ "init" ] ->
      Store.init board;
      output (obj [ ("board", str (Unix.realpath board)); ("schema", int 1) ])
  | [ "context" ] ->
      Store.with_db board (fun db -> output (Store.snapshot_json db))
  | [ "op"; path ] ->
      let request = read_json path in
      let caller, request =
        match (auth, request) with
        | Some auth, `Assoc xs ->
            (Board.Worker, obj (("auth", auth) :: List.remove_assoc "auth" xs))
        | None, _ -> (Board.Controller, request)
        | _ -> fail "operation must be an object"
      in
      Store.with_db board (fun db -> output (Board.apply db caller request))
  | [ "runtime"; "--binary"; binary; "--bridge"; bridge ] ->
      Runtime.serve ~board ~binary:(Unix.realpath binary)
        ~bridge:(Unix.realpath bridge)
  | [ "launch"; path ] ->
      let payload =
        Workspace.bind_session
          ~session:(Sys.getenv_opt "BP3_SESSION")
          (read_json path)
      in
      output
        (Lwt_main.run
           (Transport.call board
              (obj [ ("command", str "launch"); ("payload", payload) ])))
  | [ "ping" ] ->
      output
        (Lwt_main.run (Transport.call board (obj [ ("command", str "ping") ])))
  | [ "snapshot"; path ] ->
      Store.with_db board (fun db -> Store.snapshot db path);
      output (obj [ ("snapshot", str (absolute path)) ])
  | [ "--help" ] | [ "help" ] -> print_string usage
  | _ ->
      print_string usage;
      fail "invalid arguments"

let () =
  try
    let args = Array.to_list Sys.argv |> List.tl in
    let board, args =
      match args with
      | "--board" :: path :: rest -> (absolute path, rest)
      | rest ->
          ( absolute
              (Option.value
                 (Sys.getenv_opt "BP3_BOARD")
                 ~default:".bp3/board.sqlite"),
            rest )
    in
    run board args
  with
  | Error message ->
      prerr_endline ("bp3: " ^ message);
      exit 1
  | e ->
      prerr_endline ("bp3: " ^ Printexc.to_string e);
      exit 1
