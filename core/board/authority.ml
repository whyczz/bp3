open Packet
open Store

(* Authority is deliberately cooperative: these capabilities prevent accidental
   cross-run calls, not a same-user process writing SQLite directly. *)
type caller = Controller | Worker | Bridge | Runtime

let expect condition message = if not condition then fail message

let run_auth db auth =
  let run = Store.run db (field auth "run_id") in
  expect (field auth "token" = field run "token") "invalid run credential";
  expect
    (get auth "generation" = get run "generation")
    "wrong ownership generation";
  run

let live db run =
  expect (field run "desired" = "run") "run is fenced";
  let exp = one db "SELECT * FROM exps WHERE id=?" [ get run "exp_id" ] in
  expect (get run "generation" = get exp "generation") "obsolete ownership";
  let deadline =
    match get run "deadline" with
    | `Float time -> time
    | _ -> 0.
  in
  expect (now () < deadline) "run budget exhausted"

let autonomous run =
  expect (get run "takeover" = int 0) "human takeover: release required";
  expect (get run "permission" = int 0) "permission prompt pending"

let request_auth run =
  obj
    [
      ("run_id", get run "id");
      ("generation", get run "generation");
      ("token", get run "token");
    ]

let allowed caller operation =
  match caller with
  | Controller ->
      List.mem operation
        [ "quest-create"; "exp-create"; "brief"; "steer"; "cancel" ]
  | Worker -> List.mem operation [ "report"; "block"; "answer-handled" ]
  | Bridge -> operation = "signal"
  | Runtime -> List.mem operation [ "reserve"; "launch-stage"; "reconcile" ]
