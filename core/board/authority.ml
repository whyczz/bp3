open Packet
open Store

(* Authority is deliberately cooperative: these capabilities prevent accidental
   cross-execution calls, not a same-user process writing SQLite directly. *)
type caller = Controller | Worker | Bridge | Runtime

let expect condition message = if not condition then fail message

let execution_auth db auth =
  let execution = Store.execution db (field auth "execution_id") in
  expect
    (field auth "token" = field execution "token")
    "invalid execution credential";
  expect
    (get auth "generation" = get execution "generation")
    "wrong ownership generation";
  execution

let live db execution =
  expect (field execution "desired" = "run") "execution is fenced";
  let exp = one db "SELECT * FROM exps WHERE id=?" [ get execution "exp_id" ] in
  expect
    (get execution "generation" = get exp "generation")
    "obsolete ownership";
  let deadline =
    match get execution "deadline" with
    | `Float time -> time
    | _ -> 0.
  in
  expect (now () < deadline) "execution budget exhausted"

let autonomous execution =
  expect (get execution "takeover" = int 0) "human takeover: release required";
  expect (get execution "permission" = int 0) "permission prompt pending"

let request_auth execution =
  obj
    [
      ("execution_id", get execution "id");
      ("generation", get execution "generation");
      ("token", get execution "token");
    ]

let allowed caller operation =
  match caller with
  | Controller ->
      List.mem operation
        [ "quest-create"; "exp-create"; "brief"; "steer"; "cancel" ]
  | Worker -> List.mem operation [ "report"; "block"; "answer-handled" ]
  | Bridge -> operation = "signal"
  | Runtime -> List.mem operation [ "reserve"; "launch-stage"; "reconcile" ]
