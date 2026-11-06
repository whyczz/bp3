open Packet
open Store
open Authority

(* Durable launch intent and harness observations. These are separate from exp
   outcomes: an idle process is not Run Outputs, and a missing process is not rework. *)
let reserve db payload =
  let exp = one db "SELECT * FROM exps WHERE id=?" [ get payload "exp_id" ] in
  expect (field exp "state" = "working") "exp not launchable";
  expect
    (number (get exp "generation") = 0)
    "exp already has a run; replacement requires explicit rework design";
  let id = Packet.id (field payload "id") and time = now () in
  let seconds = number (get (decode (field exp "brief")) "max_seconds") in
  execute db "UPDATE exps SET generation=generation+1 WHERE id=?"
    [ get exp "id" ];
  execute db
    "INSERT INTO \
     runs(id,exp_id,generation,token,brief,base,worktree,branch,session_name,created,deadline) \
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
  obj [ ("run_id", str id) ]

let launch_stage db payload =
  let run = Store.run db (field payload "run_id") in
  let stage = field payload "stage" in
  expect
    (List.mem
       (field run "launch_stage", stage)
       [ ("reserved", "worktree"); ("worktree", "spawning") ])
    "invalid launch transition";
  execute db "UPDATE runs SET launch_stage=? WHERE id=?"
    [ str stage; get run "id" ];
  obj [ ("stage", str stage) ]

let next_delivery db run =
  if
    field run "desired" <> "run"
    || get run "ready" <> int 1
    || get run "takeover" <> int 0
    || get run "permission" <> int 0
  then `Null
  else
    match
      query db
        "SELECT * FROM inbox WHERE run_id=? AND stage='queued' ORDER BY \
         created,id LIMIT 1"
        [ get run "id" ]
    with
    | [] -> `Null
    | [ message ] ->
        (* The offer is committed with the poll receipt. Only that same poll can
         replay it; a new poll cannot blindly reinject an ambiguous message. *)
        execute db "UPDATE inbox SET stage='offered' WHERE id=?"
          [ get message "id" ];
        message
    | _ -> assert false

let register_ready db run payload =
  expect
    (List.mem (field run "launch_stage") [ "spawning"; "ready" ])
    "unexpected ready before spawn intent";
  expect (field payload "cwd" = field run "worktree") "bridge in wrong worktree";
  expect (number (get payload "pid") > 1) "invalid process id";
  ignore (field payload "pane_id");
  ignore (field payload "session_id");
  execute db
    "UPDATE runs SET \
     ready=1,idle=?,observed='live',launch_stage='ready',endpoint=? WHERE id=?"
    [ `Bool (boolean (get payload "idle")); payload; get run "id" ]

let observe_message db run payload =
  let message =
    one db "SELECT * FROM inbox WHERE id=? AND run_id=?"
      [ get payload "inbox_id"; get run "id" ]
  in
  expect
    (List.mem (field message "stage") [ "offered"; "observed"; "handled" ])
    "message not offered";
  execute db "UPDATE inbox SET stage='observed' WHERE id=? AND stage='offered'"
    [ get message "id" ]

let signal db run payload =
  let kind = field payload "kind" in
  let endpoint = get run "endpoint" in
  if endpoint <> `Null then
    expect
      (field (decode (string endpoint)) "session_id"
      = field payload "session_id")
      "pi session changed; run fenced";
  let update sql = execute db sql [ get run "id" ] in
  (match kind with
  | "ready" -> register_ready db run payload
  | "heartbeat" -> expect (get run "ready" = int 1) "ready required"
  | "busy" -> update "UPDATE runs SET idle=0 WHERE id=?"
  | "settled" ->
      expect (get payload "idle" = `Bool true) "settled signal requires isIdle";
      update "UPDATE runs SET idle=1 WHERE id=?"
  | "took_over" -> update "UPDATE runs SET takeover=1 WHERE id=?"
  | "release" ->
      expect (get payload "idle" = `Bool true) "release only when pi is idle";
      update "UPDATE runs SET takeover=0 WHERE id=?"
  | "permission-start" -> update "UPDATE runs SET permission=1 WHERE id=?"
  | "permission-end" -> update "UPDATE runs SET permission=0 WHERE id=?"
  | "observed" -> observe_message db run payload
  | "exited" ->
      update "UPDATE runs SET observed='stale',idle=0,ready=0 WHERE id=?"
  | _ -> fail "unknown bridge signal");
  if kind <> "exited" then
    execute db "UPDATE runs SET last_seen=?,observed='live' WHERE id=?"
      [ `Float (now ()); get run "id" ];
  if kind <> "heartbeat" then
    execute db "UPDATE runs SET last_meaningful=? WHERE id=?"
      [ `Float (now ()); get run "id" ];
  let updated = Store.run db (field run "id") in
  obj
    [
      ("inbox", if kind = "heartbeat" then next_delivery db updated else `Null);
      ("takeover", get updated "takeover");
    ]

let reconcile db =
  let time = now () in
  execute db
    "UPDATE runs SET observed='stale',idle=0 WHERE desired='run' AND \
     (last_seen IS NULL OR last_seen<?)"
    [ `Float (time -. 10.) ];
  (* Budget exhaustion fences reports/delivery, not merely a UI label. We do not
     signal a stored PID: it could have been reused by an unrelated process. *)
  execute db
    "UPDATE runs SET desired='expired' WHERE desired='run' AND deadline<?"
    [ `Float time ];
  obj [ ("reconciled", `Bool true) ]
