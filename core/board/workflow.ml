open Packet
open Store
open Authority

(* Workflow mutations run only inside Board.apply's transaction. They describe
   outcomes/questions, not process liveness. No function here starts a process. *)
let set_exp db execution state =
  execute db "UPDATE exps SET state=? WHERE id=?"
    [ str state; get execution "exp_id" ]

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

let queue db id execution_id text question =
  execute db
    "INSERT INTO inbox(id,execution_id,text,question_id,created) \
     VALUES(?,?,?,?,?)"
    [
      str (Packet.id id); str execution_id; str text; question; `Float (now ());
    ]

let brief_text execution =
  "You are a bp3 Worker. Frozen brief:\n" ^ field execution "brief"
  ^ {|
Work only in this worktree. No landing, promotion or push.
Report using "$BP3_BIN" --board "$BP3_BOARD" op FILE (v=1, unique op_id,
op, payload). Credentials are added from your environment. Keep report JSON
outside the worktree so it does not dirty the candidate. stdin (op -) also works.
For a missing check or decision: op=block,
payload={id,iiuc,challenge,recommendation}; stop until a Board reply.
On a reply: op=answer-handled, payload={inbox_id}; then continue.
To submit: commit your work, op=report, payload={commit:FULL_SHA,evidence:TEXT}.
Do not replace a missing check by guessing. A candidate is not acceptance.
Stop after reporting. Use stable operation IDs when retrying.
|}

let deliver_brief db payload =
  let execution = Store.execution db (field payload "execution_id") in
  live db execution;
  autonomous execution;
  expect (get execution "ready" = int 1) "bridge not ready";
  let id = "brief-" ^ field execution "id" in
  queue db id (field execution "id") (brief_text execution) `Null;
  obj [ ("queued", str id) ]

let steer db payload =
  let execution = Store.execution db (field payload "execution_id") in
  live db execution;
  let question_id = get payload "question_id" in
  if question_id <> `Null then (
    let question =
      one db "SELECT * FROM questions WHERE id=? AND execution_id=?"
        [ question_id; get execution "id" ]
    in
    expect (field question "state" = "open") "question already answered";
    execute db "UPDATE questions SET state='answered',answer=? WHERE id=?"
      [ get payload "text"; question_id ]);
  expect (String.trim (field payload "text") <> "") "empty steering";
  queue db (field payload "id") (field execution "id") (field payload "text")
    question_id;
  obj [ ("queued", get payload "id") ]

let block db execution payload =
  autonomous execution;
  expect
    (query db "SELECT id FROM results WHERE execution_id=?"
       [ get execution "id" ]
    = [])
    "candidate already submitted";
  List.iter
    (fun key ->
      expect (String.trim (field payload key) <> "") ("empty blocker " ^ key))
    [ "iiuc"; "challenge"; "recommendation" ];
  execute db
    "INSERT INTO questions(id,execution_id,iiuc,challenge,recommendation) \
     VALUES(?,?,?,?,?)"
    [
      str (Packet.id (field payload "id"));
      get execution "id";
      get payload "iiuc";
      get payload "challenge";
      get payload "recommendation";
    ];
  set_exp db execution "blocked";
  obj [ ("question_id", get payload "id") ]

let answer_handled db execution payload =
  autonomous execution;
  let message =
    one db "SELECT * FROM inbox WHERE id=? AND execution_id=?"
      [ get payload "inbox_id"; get execution "id" ]
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
    query db
      "SELECT id FROM questions WHERE execution_id=? AND state!='handled'"
      [ get execution "id" ]
    = []
  then set_exp db execution "working";
  obj [ ("handled", get message "id") ]

let report db execution payload =
  autonomous execution;
  expect (get execution "ready" = int 1) "bridge not ready";
  expect
    (query db
       "SELECT id FROM questions WHERE execution_id=? AND state!='handled'"
       [ get execution "id" ]
    = [])
    "unresolved question";
  expect (String.trim (field payload "evidence") <> "") "evidence required";
  let result_id = "result-" ^ field execution "id" in
  (match
     query db "SELECT * FROM results WHERE execution_id=?"
       [ get execution "id" ]
   with
  | [] ->
      execute db
        "INSERT INTO results(id,execution_id,commit_sha,evidence,brief) \
         VALUES(?,?,?,?,?)"
        [
          str result_id;
          get execution "id";
          get payload "commit";
          get payload "evidence";
          get execution "brief";
        ]
  | [ result ] ->
      (* Also deduplicate a semantic retry under a different operation ID.
         Evidence/commit changes require a new execution, never overwrite. *)
      expect
        (get result "commit_sha" = get payload "commit"
        && get result "evidence" = get payload "evidence")
        "execution already has a different candidate"
  | _ -> assert false);
  set_exp db execution "ready";
  obj [ ("result_id", str result_id) ]

let cancel db payload =
  let execution = Store.execution db (field payload "execution_id") in
  execute db "UPDATE executions SET desired='cancel' WHERE id=?"
    [ get execution "id" ];
  execute db
    "UPDATE exps SET generation=generation+1,state='cancelled' WHERE id=?"
    [ get execution "exp_id" ];
  obj
    [
      ("cancelled", get execution "id");
      ("process", str "not killed; close the owned pane explicitly");
    ]
