open Packet
open Store
open Authority

(* Workflow mutations run only inside Board.apply's transaction. They describe
   outcomes/questions, not process liveness. No function here starts a process. *)
let set_exp db run state =
  execute db "UPDATE exps SET state=? WHERE id=?"
    [ str state; get run "exp_id" ]

let create_quest db payload =
  let id = Packet.id (field payload "id") in
  expect (String.trim (field payload "intent") <> "") "empty Quest intent";
  execute db "INSERT INTO quests(id,intent,repo,target,base) VALUES(?,?,?,?,?)"
    [
      str id;
      get payload "intent";
      get payload "repo";
      get payload "target";
      get payload "base";
    ];
  obj [ ("quest_id", str id) ]

let create_exp db payload =
  let id = Packet.id (field payload "id") and brief = get payload "brief" in
  validate_brief brief;
  let quest =
    one db "SELECT * FROM quests WHERE id=?" [ get payload "quest_id" ]
  in
  execute db "INSERT INTO exps(id,quest_id,brief,base) VALUES(?,?,?,?)"
    [ str id; get payload "quest_id"; brief; get quest "base" ];
  obj [ ("exp_id", str id) ]

let queue db id run_id text question =
  execute db
    "INSERT INTO inbox(id,run_id,text,question_id,created) VALUES(?,?,?,?,?)"
    [ str (Packet.id id); str run_id; str text; question; `Float (now ()) ]

let brief_text run =
  "You are a bp3 Worker. Frozen brief:\n" ^ field run "brief"
  ^ {|
Work only in this worktree. No landing, promotion or push.
Report using "$BP3_BIN" --board "$BP3_BOARD" op FILE (v=1, unique op_id,
op, payload). Credentials are added from your environment. Keep report JSON
outside the worktree so it does not dirty the Run Outputs. stdin (op -) also works.
For a missing check or decision: op=block,
payload={id,iiuc,challenge,recommendation}; stop until a Board reply.
On a reply: op=answer-handled, payload={inbox_id}; then continue.
To submit: commit your work, op=report, payload={commit:FULL_SHA,evidence:TEXT}.
Do not replace a missing check by guessing. Run Outputs are not acceptance.
Stop after reporting. Use stable operation IDs when retrying.
|}

let deliver_brief db payload =
  let run = Store.run db (field payload "run_id") in
  live db run;
  autonomous run;
  expect (get run "ready" = int 1) "bridge not ready";
  let id = "brief-" ^ field run "id" in
  queue db id (field run "id") (brief_text run) `Null;
  obj [ ("queued", str id) ]

let steer db payload =
  let run = Store.run db (field payload "run_id") in
  live db run;
  let question_id = get payload "question_id" in
  if question_id <> `Null then (
    let question =
      one db "SELECT * FROM questions WHERE id=? AND run_id=?"
        [ question_id; get run "id" ]
    in
    expect (field question "state" = "open") "question already answered";
    execute db "UPDATE questions SET state='answered',answer=? WHERE id=?"
      [ get payload "text"; question_id ]);
  expect (String.trim (field payload "text") <> "") "empty steering";
  queue db (field payload "id") (field run "id") (field payload "text")
    question_id;
  obj [ ("queued", get payload "id") ]

let block db run payload =
  autonomous run;
  expect
    (query db "SELECT id FROM run_outputs WHERE run_id=?" [ get run "id" ] = [])
    "Run Outputs already submitted";
  List.iter
    (fun key ->
      expect (String.trim (field payload key) <> "") ("empty blocker " ^ key))
    [ "iiuc"; "challenge"; "recommendation" ];
  execute db
    "INSERT INTO questions(id,run_id,iiuc,challenge,recommendation) \
     VALUES(?,?,?,?,?)"
    [
      str (Packet.id (field payload "id"));
      get run "id";
      get payload "iiuc";
      get payload "challenge";
      get payload "recommendation";
    ];
  set_exp db run "blocked";
  obj [ ("question_id", get payload "id") ]

let answer_handled db run payload =
  autonomous run;
  let message =
    one db "SELECT * FROM inbox WHERE id=? AND run_id=?"
      [ get payload "inbox_id"; get run "id" ]
  in
  (* Observation is a bridge fact; handling is an explicit Worker assertion.
     A settled turn, successful send or Controller reply cannot substitute. *)
  expect (field message "stage" = "observed") "reply has not been observed";
  expect (get message "question_id" <> `Null) "not a question reply";
  execute db
    "UPDATE questions SET state='handled' WHERE id=? AND state='answered'"
    [ get message "question_id" ];
  execute db "UPDATE inbox SET stage='handled' WHERE id=?" [ get message "id" ];
  if
    query db "SELECT id FROM questions WHERE run_id=? AND state!='handled'"
      [ get run "id" ]
    = []
  then set_exp db run "working";
  obj [ ("handled", get message "id") ]

let report db run payload =
  autonomous run;
  expect (get run "ready" = int 1) "bridge not ready";
  expect
    (query db "SELECT id FROM questions WHERE run_id=? AND state!='handled'"
       [ get run "id" ]
    = [])
    "unresolved question";
  expect (String.trim (field payload "evidence") <> "") "evidence required";
  let run_output_id = "run-output-" ^ field run "id" in
  (match
     query db "SELECT * FROM run_outputs WHERE run_id=?" [ get run "id" ]
   with
  | [] ->
      execute db
        "INSERT INTO run_outputs(id,run_id,commit_sha,evidence,brief) \
         VALUES(?,?,?,?,?)"
        [
          str run_output_id;
          get run "id";
          get payload "commit";
          get payload "evidence";
          get run "brief";
        ]
  | [ output ] ->
      (* Also deduplicate a semantic retry under a different operation ID.
         Evidence/commit changes require a new run, never overwrite. *)
      expect
        (get output "commit_sha" = get payload "commit"
        && get output "evidence" = get payload "evidence")
        "run already has different Run Outputs"
  | _ -> assert false);
  set_exp db run "ready";
  obj [ ("run_output_id", str run_output_id) ]

let cancel db payload =
  let run = Store.run db (field payload "run_id") in
  execute db "UPDATE runs SET desired='cancel' WHERE id=?" [ get run "id" ];
  execute db
    "UPDATE exps SET generation=generation+1,state='cancelled' WHERE id=?"
    [ get run "exp_id" ];
  obj
    [
      ("cancelled", get run "id");
      ("process", str "not killed; close the owned pane explicitly");
    ]
