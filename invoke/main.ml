(* bp3 invoke: the only reader/writer of quest state.
   A quest is a folder: QUEST.md and fsm.yaml (authored), state.yaml
   and ledger.jsonl (generated here, never hand-edited). State is a
   clean commit plus a stage. Every edge appends exactly one ledger
   line and state.yaml is rebuilt from the ledger tail on every read.
   The ledger wins any disagreement. *)

let fail fmt =
  Printf.ksprintf
    (fun s ->
      prerr_endline ("bp3 invoke: " ^ s);
      exit 1)
    fmt

let root =
  match Sys.getenv_opt "BP3_ROOT" with
  | Some r -> r
  | None -> Sys.getcwd ()

let run_argv argv =
  let out = Filename.temp_file "bp3-invoke-" ".log" in
  let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let pid =
    Unix.create_process (List.hd argv) (Array.of_list argv) Unix.stdin fd fd
  in
  Unix.close fd;
  let _, status = Unix.waitpid [] pid in
  let ic = open_in_bin out in
  let buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_channel buf ic 4096
     done
   with End_of_file -> ());
  close_in ic;
  Sys.remove out;
  match status with
  | Unix.WEXITED 0 -> String.trim (Buffer.contents buf)
  | _ -> fail "%s failed" (List.hd argv)

let git repo args = run_argv ("git" :: "-C" :: repo :: args)

let read_lines path =
  if not (Sys.file_exists path) then []
  else
    let ic = open_in_bin path in
    let rec loop acc =
      match input_line ic with
      | line -> loop (line :: acc)
      | exception End_of_file ->
          close_in ic;
          List.rev acc
    in
    loop []

let write_file path text =
  let oc = open_out_bin path in
  output_string oc text;
  close_out oc


(* Minimal YAML reader for the plan/state subset bp3 itself writes:
   flat scalars, one nested review: map, inline string lists.
   Unknown keys and shapes fail closed. *)
let parse_plan path =
  let quest_type = ref None and max_cycles = ref 1 in
  let review_required = ref true in
  let depends_on = ref [] in
  let in_review = ref false in
  List.iter
    (fun raw ->
      let line = String.trim raw in
      if line = "" || line.[0] = '#' then ()
      else if line = "review:" then in_review := true
      else
        let key, value =
          match String.index_opt line ':' with
          | Some i ->
              ( String.trim (String.sub line 0 i),
                String.trim
                  (String.sub line (i + 1) (String.length line - i - 1)) )
          | None -> fail "bad plan line: %s" raw
        in
        if !in_review && (key = "required" || key = "max_cycles") then (
          if key = "required" then
            review_required := value = "true"
          else if key = "max_cycles" then
            max_cycles :=
              (try int_of_string value with _ -> fail "max_cycles not an int"))
        else (
          in_review := false;
          match key with
          | "quest_type" -> quest_type := Some value
          | "depends_on" ->
              depends_on :=
                value
                |> String.map (fun c -> if c = '[' || c = ']' then ' ' else c)
                |> String.split_on_char ','
                |> List.map String.trim
                |> List.filter (fun s -> s <> "")
          | "stages" | "checks" -> ()
          | k -> fail "unknown plan key: %s" k))
    (read_lines path);
  match !quest_type with
  | Some qt -> (qt, !max_cycles, !review_required, !depends_on)
  | None -> fail "plan missing quest_type"

type state = { stage : string; commit : string option; cycle : int; seq : int }

let ledger qdir =
  read_lines (Filename.concat qdir "ledger.jsonl")
  |> List.filter (fun l -> String.trim l <> "")
  |> List.map Yojson.Safe.from_string

let assoc j k =
  match j with `Assoc xs -> List.assoc_opt k xs | _ -> fail "ledger not object"

let str_field j k =
  match assoc j k with Some (`String s) -> s | _ -> "controller"

let ledger_stage qdir =
  match
    ledger qdir
    |> List.filter (fun e -> assoc e "result" <> Some (`String "refused"))
    |> List.rev
  with
  | [] -> "author"
  | last :: _ -> str_field last "to_stage"

let unmet_deps qdir depends_on =
  let qroot = Filename.dirname qdir in
  List.filter
    (fun dep ->
      let dep_dir = Filename.concat qroot dep in
      not (Sys.file_exists (Filename.concat dep_dir "fsm.yaml"))
      || ledger_stage dep_dir <> "landed")
    depends_on


let load_state qdir =
  let entries = ledger qdir in
  let st =
    match List.rev entries with
    | [] -> { stage = "author"; commit = None; cycle = 0; seq = 0 }
    | last :: _ ->
        let commit =
          match assoc last "to_commit" with
          | Some (`String s) -> Some s
          | _ -> None
        in
        let cycle =
          match assoc last "cycle" with Some (`Int n) -> n | _ -> 0
        in
        let seq =
          match assoc last "seq" with Some (`Int n) -> n | _ -> 0
        in
        { stage = str_field last "to_stage"; commit; cycle; seq }
  in
  write_file
    (Filename.concat qdir "state.yaml")
    (Printf.sprintf
       "# GENERATED by bp3 invoke. Do not edit.\nstage: %s\ncommit: %s\n\
        cycle: %d\nledger_seq: %d\n"
       st.stage
       (Option.value st.commit ~default:"null")
       st.cycle st.seq);
  st

let legal_moves st =
  match st.stage with
  | "author" | "fix" | "blocked" -> [ "submit"; "block"; "cancel" ]
  | "review" -> [ "review"; "check"; "block"; "cancel" ]
  | "ready" -> [ "check"; "land"; "cancel" ]
  | _ -> []

let has_passing_check qdir st =
  match st.commit with
  | None -> false
  | Some c ->
      ledger qdir
      |> List.exists (fun e ->
             assoc e "edge" = Some (`String "check")
             && assoc e "verdict" = Some (`String "pass")
             && assoc e "to_commit" = Some (`String c))

let append_ledger qdir fields =
  (* Count and write on the locked fd itself: opening any second fd
     on this file (even to read) drops POSIX locks on macOS/Linux. *)
  let path = Filename.concat qdir "ledger.jsonl" in
  let fd =
    Unix.openfile path [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_APPEND ] 0o644
  in
  Fun.protect
    ~finally:(fun () -> Unix.close fd)
    (fun () ->
      Unix.lockf fd Unix.F_LOCK 0;
      Fun.protect
        ~finally:(fun () -> Unix.lockf fd Unix.F_ULOCK 0)
        (fun () ->
          ignore (Unix.lseek fd 0 Unix.SEEK_SET);
          let buf = Buffer.create 1024 in
          let chunk = Bytes.create 4096 in
          let rec rd () =
            let n = Unix.read fd chunk 0 4096 in
            if n > 0 then (
              Buffer.add_subbytes buf chunk 0 n;
              rd ())
          in
          rd ();
          let seq =
            Buffer.contents buf
            |> String.split_on_char '\n'
            |> List.filter (fun l -> String.trim l <> "")
            |> List.length
            |> ( + ) 1
          in
          let entry = `Assoc (("seq", `Int seq) :: fields) in
          let line = Yojson.Safe.to_string entry ^ "\n" in
          ignore (Unix.write_substring fd line 0 (String.length line));
          seq))

(* QUEST.md status is authored frontmatter, but cancel is a binary
   move: sync the field so quest list filtering sees the terminal
   state the ledger already recorded. The plan in fsm.yaml is never
   touched by a move. *)
let set_quest_status qdir status =
  let path = Filename.concat qdir "QUEST.md" in
  let lines = read_lines path in
  let seen = ref false in
  let lines =
    List.map
      (fun l ->
        if (not !seen) && String.starts_with ~prefix:"status:" (String.trim l)
        then (
          seen := true;
          "status: " ^ status)
        else l)
      lines
  in
  let lines =
    if !seen then
      match lines with
      | "---" :: rest -> "---" :: ("status: " ^ status) :: rest
      | _ -> ("status: " ^ status) :: lines
    else lines
  in
  write_file path (String.concat "\n" lines ^ "\n")

let json_state qdir st moves =
  Printf.printf "%s\n%!"
    (Yojson.Safe.to_string
       (`Assoc
         [
           ("quest", `String (Filename.basename qdir));
           ("stage", `String st.stage);
           ( "commit",
             match st.commit with Some c -> `String c | None -> `Null );
           ("cycle", `Int st.cycle);
           ("ledger_seq", `Int st.seq);
           ("legal_moves", `List (List.map (fun m -> `String m) moves));
         ]))

let check_commit repo qdir st new_commit =
  let full = git repo [ "rev-parse"; "--verify"; new_commit ^ "^{commit}" ] in
  (match st.commit with
  | Some cur ->
      let pid =
        Unix.create_process "git"
          [| "git"; "-C"; repo; "merge-base"; "--is-ancestor"; cur; full |]
          Unix.stdin Unix.stdout Unix.stderr
      in
      let _, status = Unix.waitpid [] pid in
      (match status with
      | Unix.WEXITED 0 -> ()
      | _ -> fail "commit %s does not descend from current %s" full cur)
  | None -> ());
  let quests_rel =
    let rel = Filename.dirname qdir in
    let rl = String.length root and ll = String.length rel in
    if ll > rl && String.sub rel 0 rl = root then
      String.sub rel (rl + 1) (ll - rl - 1)
    else rel
  in
  let dirty =
    git repo [ "status"; "--porcelain"; "--"; "."; ":(exclude)" ^ quests_rel ^ "/" ]
  in
  if dirty <> "" then
    fail "worktree is dirty (outside the quest folder); commit or stash first";
  full

let opt_arg args name =
  let rec go = function
    | k :: v :: _ when k = name -> Some v
    | _ :: rest -> go rest
    | [] -> None
  in
  go args

let resolve_quest arg =
  let direct = Filename.concat arg "fsm.yaml" in
  if Sys.file_exists direct then arg
  else
    let cand = Filename.concat (Filename.concat (Filename.concat root "docs") "quests") arg in
    if Sys.file_exists (Filename.concat cand "fsm.yaml") then cand
    else fail "quest not found: %s" arg

let init name qtype engine deps =
  let plan_path = Filename.concat (Filename.concat root "plans") (qtype ^ ".yaml") in
  if not (Sys.file_exists plan_path) then fail "unknown quest_type: %s" qtype;
  let qdir =
    Filename.concat (Filename.concat (Filename.concat root "docs") "quests") name
  in
  if Sys.file_exists qdir then fail "quest folder already exists: %s" qdir;
  ignore (run_argv [ "mkdir"; "-p"; Filename.concat qdir "runs" ]);
  write_file (Filename.concat qdir "QUEST.md")
    (Printf.sprintf
       "---\nquest_type: %s\nengine: %s\nstatus: proposed\n---\n\n\
        # %s\n\n\
        TL;DR\n<what will be true when this Quest lands, and the one decision it makes>\n\n\
        ELI5\n<the whole Quest in plain words>\n\n\
        ## Goal and why\n<the outcome pursued>\n\n\
        ## Success picture\n<what the human will see, run, and judge at Quest-to-master>\n\n\
        ## Scope\nIn: <...>\nOut: <...>\n\n\
        ## Human touchpoints\n<framing, escalations, Quest-to-master promotion>\n\n\
        ## Exps\n### Exp 1 — <name>\n\
        - Intent: <bounded contribution>\n\
        - Lane: micro | standard | high-blast-radius\n\
        - Output: <inspectable artifact>\n\
        - Acceptance: <check that fails today>\n\
        - Depends on: none\n\n\
        ## Scorecard\n<what gets measured, where recorded>\n\n\
        ## Risks and red chair\n<strongest attacks, what changed, what remains open>\n\n\
        ## Open questions\n<ranked, each with an owner>\n"
       qtype engine name);
  write_file (Filename.concat qdir "fsm.yaml")
    (String.concat "\n" (read_lines plan_path)
    ^ (match deps with
       | Some d -> "\ndepends_on: [" ^ d ^ "]"
       | None -> "")
    ^ "\n");
  write_file (Filename.concat qdir "ledger.jsonl") "";
  let _ = load_state qdir in
  let seq =
    append_ledger qdir
      [
        ("edge", `String "init");
        ("actor", `String "controller");
        ("to_stage", `String "author");
        ("to_commit", `Null);
        ("cycle", `Int 0);
        ("reason", `String (Printf.sprintf "quest_type=%s engine=%s" qtype engine));
      ]
  in
  let st = load_state qdir in
  json_state qdir { st with seq } (legal_moves st)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  let args =
    match args with
    | "quest" :: "list" :: rest -> "list" :: rest
    | "quest" :: "create" :: rest -> "init" :: rest
    | "quest" :: "show" :: q :: _ -> [ q ]
    | "quest" :: "invoke" :: rest -> rest
    | "quest" :: q :: rest -> q :: rest
    | "tools" :: "worktree" :: verb :: q :: rest -> q :: verb :: rest
    | other -> other
  in
  match args with
  | [] -> fail "usage: bp3 quest list|create|show|invoke, or bp3 invoke <quest> [edge]"
  | "list" :: rest ->
      let qroot = Filename.concat (Filename.concat root "docs") "quests" in
      let names =
        if Sys.file_exists qroot then Sys.readdir qroot |> Array.to_list else []
      in
      let rows =
        List.filter_map
          (fun name ->
            let qdir = Filename.concat qroot name in
            if Sys.file_exists (Filename.concat qdir "fsm.yaml") then
              let status =
                read_lines (Filename.concat qdir "QUEST.md")
                |> List.find_map (fun l ->
                       let l = String.trim l in
                       if String.starts_with ~prefix:"status:" l then
                         Some
                           (String.trim
                              (String.sub l 7 (String.length l - 7)))
                       else None)
                |> Option.value ~default:"unknown"
              in
              let st = load_state qdir in
              if
                (not (List.mem "--all" rest))
                && status <> "proposed" && status <> "active"
              then None
              else
                Some
                  (`Assoc
                  [
                    ("quest", `String name);
                    ("status", `String status);
                    ("stage", `String st.stage);
                    ( "commit",
                      match st.commit with Some c -> `String c | None -> `Null );
                  ])
            else None)
          names
      in
      Printf.printf "%s\n%!" (Yojson.Safe.to_string (`List rows))
  | "init" :: rest ->
      let name = match rest with n :: _ -> n | [] -> fail "init needs a name" in
      let qtype = Option.value (opt_arg rest "--type") ~default:"default" in
      let engine = Option.value (opt_arg rest "--engine") ~default:"single" in
      init name qtype engine (opt_arg rest "--depends-on")
  | q :: rest ->
      let qdir = resolve_quest q in
      let quest_type, max_cycles, review_required, depends_on =
        parse_plan (Filename.concat qdir "fsm.yaml")
      in
      ignore quest_type;
      let st = load_state qdir in
      let repo = git qdir [ "rev-parse"; "--show-toplevel" ] in
      (match rest with
      | [] ->
          Printf.printf "%s\n%!"
            (Yojson.Safe.to_string
               (`Assoc
                 [
                   ("quest", `String (Filename.basename qdir));
                   ("quest_type", `String quest_type);
                   ("stage", `String st.stage);
                   ( "commit",
                     match st.commit with Some c -> `String c | None -> `Null );
                   ("cycle", `Int st.cycle);
                   ("ledger_seq", `Int st.seq);
                   ( "depends_on",
                     `List (List.map (fun d -> `String d) depends_on) );
                   ( "blocked_by",
                     `List
                       (List.map (fun d -> `String d) (unmet_deps qdir depends_on)) );
                   ("legal_moves", `List (List.map (fun m -> `String m) (legal_moves st)));
                 ]))
      | edge :: eargs ->
          let reason = Option.value (opt_arg eargs "--reason") ~default:"" in
          let actor =
            Option.value (opt_arg eargs "--actor") ~default:"controller"
          in
          (match edge with
          | "prepare" | "release" ->
              let run_id =
                match opt_arg eargs "--run" with
                | Some r -> r
                | None -> fail "%s needs --run" edge
              in
              let wt =
                Filename.concat
                  (Filename.concat repo ".bp3/worktrees")
                  (Filename.basename qdir ^ "-" ^ run_id)
              in
              if edge = "prepare" then (
                let base =
                  Option.value st.commit
                    ~default:(git repo [ "rev-parse"; "HEAD" ])
                in
                ignore
                  (run_argv
                     [
                       "git"; "-C"; repo; "worktree"; "add"; "-b";
                       "bp3/" ^ Filename.basename qdir ^ "-" ^ run_id;
                       wt; base;
                     ]);
                Printf.printf "worktree %s\n%!" wt)
              else ignore (run_argv [ "git"; "-C"; repo; "worktree"; "remove"; "--force"; wt ]);
              let seq =
                append_ledger qdir
                  [
                    ("edge", `String edge);
                    ("actor", `String actor);
                    ("from_stage", `String st.stage);
                    ("to_stage", `String st.stage);
                    ( "to_commit",
                      match st.commit with Some c -> `String c | None -> `Null );
                    ("cycle", `Int st.cycle);
                    ("run", `String run_id);
                    ("reason", `String reason);
                  ]
              in
              let st2 = load_state qdir in
              json_state qdir { st2 with seq } (legal_moves st2);
              exit 0
          | _ -> ());
          if not (List.mem edge (legal_moves st)) then (
            let seq =
              append_ledger qdir
                [
                  ("edge", `String edge);
                  ("actor", `String actor);
                  ("result", `String "refused");
                  ("from_stage", `String st.stage);
                  ("to_stage", `String st.stage);
                  ( "to_commit",
                    match st.commit with Some c -> `String c | None -> `Null );
                  ("cycle", `Int st.cycle);
                  ("reason", `String ("illegal move from " ^ st.stage));
                ]
            in
            ignore (load_state qdir);
            fail "refused: %s is not a legal move from %s (ledger seq %d)" edge st.stage seq);
          let cycle = ref st.cycle in
          let to_commit = ref st.commit in
          let to_stage =
            match edge with
            | "submit" ->
                let c =
                  match opt_arg eargs "--commit" with
                  | Some c -> c
                  | None -> fail "submit needs --commit"
                in
                (match unmet_deps qdir depends_on with
                | [] -> ()
                | deps ->
                    fail "dependency not landed: %s" (String.concat ", " deps));
                to_commit := Some (check_commit repo qdir st c);
                if review_required then "review" else "ready"
            | "check" ->
                if reason = "" then fail "check needs --reason";
                (match opt_arg eargs "--verdict" with
                | Some ("pass" | "fail") -> st.stage
                | _ -> fail "check needs --verdict pass|fail")
            | "review" ->
                let verdict = opt_arg eargs "--verdict" in
                if reason = "" then fail "review needs --reason";
                if opt_arg eargs "--actor" = None then
                  fail "review needs --actor (who is judging?)";
                (match verdict with
                | Some "ship" -> "ready"
                | Some "fix_first" ->
                    if !cycle < max_cycles then (
                      incr cycle;
                      "fix")
                    else "blocked"
                | _ -> fail "review needs --verdict ship|fix_first")
            | "land" ->
                if reason = "" then fail "land needs --reason";
                if not (has_passing_check qdir st) then
                  fail "land refused: no passing check for current commit";
                let cur = Option.get st.commit in
                let head = git repo [ "rev-parse"; "HEAD" ] in
                if head <> cur then
                  fail "land refused: HEAD %s is not state commit %s" head cur;
                let branch =
                  git repo [ "rev-parse"; "--abbrev-ref"; "HEAD" ]
                in
                let target =
                  Option.value (opt_arg eargs "--target") ~default:branch
                in
                if target <> branch then (
                  let old = git repo [ "rev-parse"; target ] in
                  let pid =
                    Unix.create_process "git"
                      [|
                        "git"; "-C"; repo; "merge-base"; "--is-ancestor"; old;
                        cur;
                      |]
                      Unix.stdin Unix.stdout Unix.stderr
                  in
                  match snd (Unix.waitpid [] pid) with
                  | Unix.WEXITED 0 ->
                      ignore
                        (git repo
                           [ "update-ref"; "refs/heads/" ^ target; cur; old ])
                  | _ ->
                      fail "land refused: %s moved or diverged" target);
                "landed"
            | "block" ->
                if reason = "" then fail "block needs --reason";
                "blocked"
            | "cancel" ->
                if reason = "" then fail "cancel needs --reason";
                "canceled"
            | _ -> st.stage
          in
          let verdict_field =
            match opt_arg eargs "--verdict" with
            | Some v -> [ ("verdict", `String v) ]
            | None -> []
          in
          let seq =
            append_ledger qdir
              ([
                 ("edge", `String edge);
                 ("actor", `String actor);
                 ("from_stage", `String st.stage);
                 ("to_stage", `String to_stage);
                 ( "to_commit",
                   match !to_commit with Some c -> `String c | None -> `Null );
                 ("cycle", `Int !cycle);
                 ("reason", `String reason);
               ]
              @ verdict_field)
          in
          if edge = "cancel" then set_quest_status qdir "canceled";
          let st2 = load_state qdir in
          json_state qdir { st2 with seq } (legal_moves st2))
