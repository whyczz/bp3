open Packet
open Store
open Authority

(* Durable launch intent and harness observations. These are separate from exp
   outcomes: an idle process is not a result, and a missing process is not rework. *)
let reserve db payload =
  let exp = one db "SELECT * FROM exps WHERE id=?" [ get payload "exp_id" ] in
  expect (field exp "state" = "working") "exp not launchable";
  expect
    (number (get exp "generation") = 0)
    "exp already has an execution; replacement requires explicit rework design";
  let id = Packet.id (field payload "id") and time = now () in
  let seconds = number (get (decode (field exp "brief")) "max_seconds") in
  execute db "UPDATE exps SET generation=generation+1 WHERE id=?"
    [ get exp "id" ];
  execute db
    "INSERT INTO \
     executions(id,exp_id,generation,token,brief,base,worktree,branch,session_name,created,deadline) \
     VALUES(?,?,1,?,?,?,?,?,?,?,?)"
    [
      str id;
      get exp "id";
      str (random ());
      get exp "brief";
      get exp "base";
      get payload "worktree";
      get payload "branch";
      get payload "session_name";
      `Float time;
      `Float (time +. float_of_int seconds);
    ];
  obj [ ("execution_id", str id) ]

let launch_stage db payload =
  let execution = Store.execution db (field payload "execution_id") in
  let stage = field payload "stage" in
  expect
    (List.mem
       (field execution "launch_stage", stage)
       [ ("reserved", "worktree"); ("worktree", "spawning") ])
    "invalid launch transition";
  execute db "UPDATE executions SET launch_stage=? WHERE id=?"
    [ str stage; get execution "id" ];
  obj [ ("stage", str stage) ]

let next_delivery db execution =
  if
    field execution "desired" <> "run"
    || get execution "ready" <> int 1
    || get execution "takeover" <> int 0
    || get execution "permission" <> int 0
  then `Null
  else
    match
      query db
        "SELECT * FROM inbox WHERE execution_id=? AND stage='queued' ORDER BY \
         created,id LIMIT 1"
        [ get execution "id" ]
    with
    | [] -> `Null
    | [ message ] ->
        (* The offer is committed with the poll receipt. Only that same poll can
         replay it; a new poll cannot blindly reinject an ambiguous message. *)
        execute db "UPDATE inbox SET stage='offered' WHERE id=?"
          [ get message "id" ];
        message
    | _ -> assert false

let register_ready db execution payload =
  expect
    (List.mem (field execution "launch_stage") [ "spawning"; "ready" ])
    "unexpected ready before spawn intent";
  expect
    (field payload "cwd" = field execution "worktree")
    "bridge in wrong worktree";
  expect (number (get payload "pid") > 1) "invalid process id";
  ignore (field payload "pane_id");
  ignore (field payload "session_id");
  execute db
    "UPDATE executions SET \
     ready=1,idle=?,observed='live',launch_stage='ready',endpoint=? WHERE id=?"
    [ `Bool (boolean (get payload "idle")); payload; get execution "id" ]

let observe_message db execution payload =
  let message =
    one db "SELECT * FROM inbox WHERE id=? AND execution_id=?"
      [ get payload "inbox_id"; get execution "id" ]
  in
  expect
    (List.mem (field message "stage") [ "offered"; "observed"; "handled" ])
    "message not offered";
  execute db "UPDATE inbox SET stage='observed' WHERE id=? AND stage='offered'"
    [ get message "id" ]

let signal db execution payload =
  let kind = field payload "kind" in
  let endpoint = get execution "endpoint" in
  if endpoint <> `Null then
    expect
      (field (decode (string endpoint)) "session_id"
      = field payload "session_id")
      "pi session changed; execution fenced";
  let update sql = execute db sql [ get execution "id" ] in
  (match kind with
  | "ready" -> register_ready db execution payload
  | "heartbeat" -> expect (get execution "ready" = int 1) "ready required"
  | "busy" -> update "UPDATE executions SET idle=0 WHERE id=?"
  | "settled" ->
      expect (get payload "idle" = `Bool true) "settled signal requires isIdle";
      update "UPDATE executions SET idle=1 WHERE id=?"
  | "took_over" -> update "UPDATE executions SET takeover=1 WHERE id=?"
  | "release" ->
      expect (get payload "idle" = `Bool true) "release only when pi is idle";
      update "UPDATE executions SET takeover=0 WHERE id=?"
  | "permission-start" -> update "UPDATE executions SET permission=1 WHERE id=?"
  | "permission-end" -> update "UPDATE executions SET permission=0 WHERE id=?"
  | "observed" -> observe_message db execution payload
  | "exited" ->
      update "UPDATE executions SET observed='stale',idle=0,ready=0 WHERE id=?"
  | _ -> fail "unknown bridge signal");
  if kind <> "exited" then
    execute db "UPDATE executions SET last_seen=?,observed='live' WHERE id=?"
      [ `Float (now ()); get execution "id" ];
  if kind <> "heartbeat" then
    execute db "UPDATE executions SET last_meaningful=? WHERE id=?"
      [ `Float (now ()); get execution "id" ];
  let updated = Store.execution db (field execution "id") in
  obj
    [
      ("inbox", if kind = "heartbeat" then next_delivery db updated else `Null);
      ("takeover", get updated "takeover");
    ]

let reconcile db =
  let time = now () in
  execute db
    "UPDATE executions SET observed='stale',idle=0 WHERE desired='run' AND \
     (last_seen IS NULL OR last_seen<?)"
    [ `Float (time -. 10.) ];
  (* Budget exhaustion fences reports/delivery, not merely a UI label. We do not
     signal a stored PID: it could have been reused by an unrelated process. *)
  execute db
    "UPDATE executions SET desired='expired' WHERE desired='run' AND deadline<?"
    [ `Float time ];
  obj [ ("reconciled", `Bool true) ]
