open Packet
open Store
open Authority

type caller = Authority.caller = Controller | Worker | Bridge | Runtime

let request_auth = Authority.request_auth

(* External reads happen before the transaction. They establish Run Outputs
   identity, NOT an independent verification receipt or permission to land. *)
let preflight db operation payload =
  match operation with
  | "quest-create" -> (
      let repo = Process.repo (field payload "repo") in
      let target = field payload "target" in
      expect
        (String.starts_with ~prefix:"refs/heads/quest/" target)
        "target must be refs/heads/quest/<name>";
      ignore (Process.git repo [ "check-ref-format"; target ]);
      expect
        (Process.commit repo target = field payload "base")
        "Quest base does not match target";
      (* Canonicalize filesystem aliases at ingress; receipts still compare the
         original request, not a potentially changing normalized projection. *)
      match payload with
      | `Assoc fields ->
          obj (("repo", str repo) :: List.remove_assoc "repo" fields)
      | _ -> fail "expected payload object")
  | "report" ->
      let run = Store.run db (field payload "run_id") in
      let worktree = field run "worktree" and sha = field payload "commit" in
      expect
        (String.length sha = 40 || String.length sha = 64)
        "Run Outputs commit must be full commit SHA";
      expect (Process.commit worktree sha = sha) "Run Outputs commit not found";
      expect
        (Process.commit worktree "HEAD" = sha)
        "Run Outputs commit is not workspace HEAD";
      expect
        (Process.git worktree [ "status"; "--porcelain" ] = "")
        "Run Outputs workspace is dirty";
      ignore
        (Process.git worktree
           [ "merge-base"; "--is-ancestor"; field run "base"; sha ]);
      payload
  | _ -> payload

let dispatch db caller operation payload auth =
  let owned () =
    let run = run_auth db auth in
    live db run;
    run
  in
  (* Caller permission is checked before this dispatch. Each handler is small
     enough to review its transition and SQL together. *)
  match (caller, operation) with
  | Controller, "quest-create" -> Workflow.create_quest db payload
  | Controller, "exp-create" -> Workflow.create_exp db payload
  | Controller, "brief" -> Workflow.deliver_brief db payload
  | Controller, "steer" -> Workflow.steer db payload
  | Controller, "cancel" -> Workflow.cancel db payload
  | Worker, "block" -> Workflow.block db (owned ()) payload
  | Worker, "answer-handled" -> Workflow.answer_handled db (owned ()) payload
  | Worker, "report" -> Workflow.report db (owned ()) payload
  | Bridge, "signal" -> Run_ops.signal db (owned ()) payload
  | Runtime, "reserve" -> Run_ops.reserve db payload
  | Runtime, "launch-stage" -> Run_ops.launch_stage db payload
  | Runtime, "reconcile" -> Run_ops.reconcile db
  | _ -> fail "operation not permitted for caller"

let cached db operation_id encoded =
  match query db "SELECT * FROM receipts WHERE id=?" [ str operation_id ] with
  | [] -> None
  | [ receipt ] ->
      expect
        (field receipt "request" = encoded)
        "operation ID reused with different payload";
      Some (decode (field receipt "response"))
  | _ -> assert false

let replay db caller auth payload response =
  (* A report receipt acknowledges past work; a bridge offer can START work.
     Replaying that offer must not resurrect withdrawn run authority.
     Fail closed if an in-flight offer became ambiguous during takeover. *)
  (match caller with
  | Bridge ->
      let run = run_auth db auth in
      live db run;
      let endpoint = get run "endpoint" in
      if endpoint <> `Null then
        expect
          (field (decode (string endpoint)) "session_id"
          = field payload "session_id")
          "pi session changed; run fenced";
      if get response "inbox" <> `Null then (
        autonomous run;
        expect (get run "ready" = int 1) "ready required")
  | _ -> ());
  response

let apply db caller request =
  let request = canonical request in
  expect (get request "v" = int 1) "unsupported protocol version";
  let operation_id = Packet.id (field request "op_id")
  and operation = field request "op" in
  expect (allowed caller operation) "operation not permitted for caller";
  let auth =
    match get request "auth" with
    | `Null -> obj []
    | auth -> auth
  in
  let payload = get request "payload" in
  (* Authenticate first. A cancelled Worker may retrieve its old success, but
     not mint another. Bridge replay additionally revalidates live authority. *)
  (match caller with
  | Worker | Bridge ->
      let run = run_auth db auth in
      expect
        (get payload "run_id" = `Null || get payload "run_id" = get run "id")
        "cross-run mutation"
  | _ -> ());
  let encoded = encode request in
  match cached db operation_id encoded with
  | Some response -> replay db caller auth payload response
  | None ->
      let attributed =
        match (caller, payload) with
        | Worker, `Assoc fields ->
            obj
              (("run_id", get auth "run_id")
              :: List.remove_assoc "run_id" fields)
        | _ -> payload
      in
      let prepared = preflight db operation attributed in
      transaction db (fun () ->
          (* Another process may have won while Git preflight was running. *)
          match cached db operation_id encoded with
          | Some response -> replay db caller auth payload response
          | None ->
              let response =
                canonical (dispatch db caller operation prepared auth)
              in
              execute db
                "INSERT INTO receipts(id,request,response) VALUES(?,?,?)"
                [ str operation_id; str encoded; response ];
              event db operation_id operation
                (obj [ ("payload", payload); ("run_id", get auth "run_id") ]);
              response)
