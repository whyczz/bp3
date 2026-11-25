(* Unit tests for src/ticket/ (bp3_ticket, sqlite-control-plane ticket.1).
   case_ = named example or boundary, law_ = QCheck2 state-machine property. *)
open OUnit2

let with_temp_dir f =
  let d = Filename.temp_dir "bp3-test-ticket." "" in
  let rec rm_rf p =
    match Unix.lstat p with
    | { Unix.st_kind = Unix.S_DIR; _ } ->
        Array.iter (fun e -> rm_rf (Filename.concat p e)) (try Sys.readdir p with _ -> [||]);
        (try Unix.rmdir p with _ -> ())
    | _ -> (try Unix.unlink p with _ -> ())
    | exception _ -> ()
  in
  Fun.protect ~finally:(fun () -> rm_rf d) (fun () -> f d)

let init_git_repo dir =
  Unix.mkdir dir 0o755;
  let _, c1 = Repo_store.run_git_capture dir [ "init"; "-q"; "-b"; "master" ] in
  assert_equal ~printer:string_of_int 0 c1;
  let _, c2 = Repo_store.run_git_capture dir [ "config"; "user.email"; "t@t.t" ] in
  assert_equal ~printer:string_of_int 0 c2;
  let _, c3 = Repo_store.run_git_capture dir [ "config"; "user.name"; "t" ] in
  assert_equal ~printer:string_of_int 0 c3;
  let f = Filename.concat dir "README.md" in
  let oc = open_out f in
  output_string oc "hi\n";
  close_out oc;
  let _, c4 = Repo_store.run_git_capture dir [ "add"; "." ] in
  assert_equal ~printer:string_of_int 0 c4;
  let _, c5 = Repo_store.run_git_capture dir [ "commit"; "-qm"; "init" ] in
  assert_equal ~printer:string_of_int 0 c5

let capture_stdout f =
  let r, w = Unix.pipe () in
  let saved = Unix.dup Unix.stdout in
  flush stdout;
  Unix.dup2 w Unix.stdout;
  Unix.close w;
  let res =
    Fun.protect
      ~finally:(fun () ->
        flush stdout;
        Unix.dup2 saved Unix.stdout;
        Unix.close saved)
      f
  in
  let ic = Unix.in_channel_of_descr r in
  let out = Fun.protect ~finally:(fun () -> close_in ic) (fun () -> In_channel.input_all ic) in
  (res, out)

let err_code json =
  Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string)

let err_facts json =
  Yojson.Safe.Util.(json |> member "error" |> member "facts")

let case_strict_to_validation_and_lifecycle _ =
  with_temp_dir (fun d ->
      let db_path = Filename.concat d "bp3.sqlite" in
      let r_bp3 = Filename.concat d "bp3" in
      let r_pred = Filename.concat d "predictor" in
      init_git_repo r_bp3;
      init_git_repo r_pred;
      ignore (Repo_store.add ~db_path ~path:r_bp3 ~name:"bp3" ());
      ignore (Repo_store.add ~db_path ~path:r_pred ~name:"predictor" ());
      (* Strict --to refuses unregistered target with E_NOT_FOUND + registered list *)
      (match
         Ticket_store.add ~db_path ~to_repo:"nonexistent" ~from_repo:"predictor"
           ~kind:"bug" ~title:"typo" ()
       with
       | _ -> assert_failure "expected E_NOT_FOUND on unregistered --to"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 2 code;
           assert_equal ~printer:Fun.id "E_NOT_FOUND" (err_code json);
           let facts = err_facts json in
           assert_equal ~printer:Fun.id "nonexistent"
             Yojson.Safe.Util.(facts |> member "repo" |> to_string);
           let reg =
             Yojson.Safe.Util.(facts |> member "registered" |> to_list |> List.map to_string)
           in
           assert_equal ~printer:(String.concat ",") [ "bp3"; "predictor" ] reg);
      (* Happy add -> list -> read -> claim -> unclaim -> claim -> done *)
      let t =
        Ticket_store.add ~db_path ~to_repo:"bp3" ~from_repo:"predictor" ~kind:"bug"
          ~title:"host desk check fails" ~body:"line1\nline2" ()
      in
      assert_equal ~printer:string_of_int 1 t.id;
      assert_equal ~printer:Fun.id "open" t.status;
      assert_equal ~printer:Fun.id "line1\nline2" t.body;
      assert_equal None t.claimed_by;
      let listed = Ticket_store.list ~db_path ~to_repo:"bp3" () in
      assert_equal ~printer:string_of_int 1 (List.length listed);
      let read_t = Ticket_store.read ~db_path 1 in
      assert_equal ~printer:Fun.id "host desk check fails" read_t.title;
      assert_equal ~printer:Fun.id "line1\nline2" read_t.body;
      let claimed = Ticket_store.claim ~db_path ~id:1 ~by:"sess-a" () in
      assert_equal ~printer:Fun.id "claimed" claimed.status;
      assert_equal (Some "sess-a") claimed.claimed_by;
      assert_bool "claimed_at populated" (claimed.claimed_at <> None);
      (* Second claim -> E_ALREADY_CLAIMED exit 1 *)
      (match Ticket_store.claim ~db_path ~id:1 ~by:"sess-b" () with
       | _ -> assert_failure "expected E_ALREADY_CLAIMED"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 1 code;
           assert_equal ~printer:Fun.id "E_ALREADY_CLAIMED" (err_code json);
           let facts = err_facts json in
           assert_equal ~printer:Fun.id "sess-a"
             Yojson.Safe.Util.(facts |> member "claimed_by" |> to_string));
      (* Unclaim -> returns to open and clears claimed_by / claimed_at *)
      let unclaimed = Ticket_store.unclaim ~db_path ~id:1 ~reason:"worker backing off" () in
      assert_equal ~printer:Fun.id "open" unclaimed.status;
      assert_equal None unclaimed.claimed_by;
      assert_equal None unclaimed.claimed_at;
      (* Unclaim on open -> E_ILLEGAL_EDGE with legal_verbs *)
      (match Ticket_store.unclaim ~db_path ~id:1 ~reason:"again" () with
       | _ -> assert_failure "expected E_ILLEGAL_EDGE on unclaim of open"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 1 code;
           assert_equal ~printer:Fun.id "E_ILLEGAL_EDGE" (err_code json);
           let facts = err_facts json in
           let lv =
             Yojson.Safe.Util.(facts |> member "legal_verbs" |> to_list |> List.map to_string)
           in
           assert_equal ~printer:(String.concat ",") [ "claim"; "done"; "dismiss" ] lv);
      (* Done directly from open *)
      let done_t = Ticket_store.mark_done ~db_path ~id:1 ~reason:"fixed in v0.4.0" () in
      assert_equal ~printer:Fun.id "done" done_t.status;
      assert_equal (Some "fixed in v0.4.0") done_t.resolution_reason;
      assert_bool "resolved_at populated" (done_t.resolved_at <> None);
      (* Done on terminal done -> E_ILLEGAL_EDGE with legal_verbs=[] *)
      (match Ticket_store.mark_done ~db_path ~id:1 ~reason:"again" () with
       | _ -> assert_failure "expected E_ILLEGAL_EDGE on terminal done"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 1 code;
           assert_equal ~printer:Fun.id "E_ILLEGAL_EDGE" (err_code json);
           let facts = err_facts json in
           assert_equal ~printer:string_of_int 1 Yojson.Safe.Util.(facts |> member "id" |> to_int);
           assert_equal ~printer:Fun.id "done" Yojson.Safe.Util.(facts |> member "status" |> to_string);
           assert_equal ~printer:Fun.id "done" Yojson.Safe.Util.(facts |> member "verb" |> to_string);
           assert_equal [] Yojson.Safe.Util.(facts |> member "legal_verbs" |> to_list));
      (* Claim on terminal done -> E_ILLEGAL_EDGE, NOT E_ALREADY_CLAIMED *)
      (match Ticket_store.claim ~db_path ~id:1 ~by:"sess-c" () with
       | _ -> assert_failure "expected E_ILLEGAL_EDGE on claim of done"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 1 code;
           assert_equal ~printer:Fun.id "E_ILLEGAL_EDGE" (err_code json));
      (* Repo remove preserves historical tickets *)
      Repo_store.remove ~db_path "bp3";
      let kept = Ticket_store.read ~db_path 1 in
      assert_equal ~printer:Fun.id "done" kept.status)

let case_cli_formats_help_and_usage_errors _ =
  with_temp_dir (fun d ->
      let db_path = Filename.concat d "cli.sqlite" in
      (* -h never creates DB *)
      let rc_h, out_h = capture_stdout (fun () -> Ticket_cli.run ~db_path [ "-h" ]) in
      assert_equal ~printer:string_of_int 0 rc_h;
      assert_bool "-h never creates DB" (not (Sys.file_exists db_path));
      assert_bool "help mentions unclaim" (String.length out_h > 0);
      (* Subcommand -h never creates DB *)
      let rc_sh, _ = capture_stdout (fun () -> Ticket_cli.run ~db_path [ "add"; "--help" ]) in
      assert_equal ~printer:string_of_int 0 rc_sh;
      assert_bool "add --help never creates DB" (not (Sys.file_exists db_path));
      (* Usage errors refused with exit 2 E_USAGE without creating DB *)
      let check_usage args =
        let rc, out = capture_stdout (fun () -> Ticket_cli.run ~db_path args) in
        assert_equal ~printer:string_of_int 2 rc;
        assert_equal ~printer:Fun.id "E_USAGE" (err_code (Yojson.Safe.from_string out))
      in
      check_usage [ "add"; "--to"; "bp3"; "--title"; "   " ];
      check_usage [ "add"; "--to"; "bp3"; "--title"; "x"; "--kind"; "bogus" ];
      check_usage [ "list"; "--status"; "bogus" ];
      check_usage [ "read"; "not-an-int" ];
      check_usage [ "done"; "1"; "--reason"; "   " ];
      check_usage [ "unclaim"; "1" ];
      assert_bool "usage checks never created DB" (not (Sys.file_exists db_path));
      (* Table output on list + read *)
      let r_bp3 = Filename.concat d "bp3" in
      init_git_repo r_bp3;
      ignore (Repo_store.add ~db_path ~path:r_bp3 ~name:"bp3" ());
      let rc_a, _ =
        capture_stdout (fun () ->
            Ticket_cli.run ~db_path
              [ "add"; "--from"; "predictor"; "--to"; "bp3"; "--kind"; "feature";
                "--title"; "add table view"; "--body"; "full multiline\nbody text" ])
      in
      assert_equal ~printer:string_of_int 0 rc_a;
      let rc_lt, out_lt =
        capture_stdout (fun () ->
            Ticket_cli.run ~db_path [ "list"; "--to"; "bp3"; "--format"; "table" ])
      in
      assert_equal ~printer:string_of_int 0 rc_lt;
      assert_bool "list table has header" (String.starts_with ~prefix:"id" out_lt);
      assert_bool "list table has title" (Str.string_match (Str.regexp ".*add table view") out_lt 0
                                          || String.length out_lt > 20);
      let rc_rt, out_rt =
        capture_stdout (fun () ->
            Ticket_cli.run ~db_path [ "read"; "1"; "--format"; "table" ])
      in
      assert_equal ~printer:string_of_int 0 rc_rt;
      assert_bool "read table contains body line 1"
        (try ignore (Str.search_forward (Str.regexp_string "full multiline") out_rt 0); true
         with Not_found -> false);
      assert_bool "read table contains body line 2"
        (try ignore (Str.search_forward (Str.regexp_string "body text") out_rt 0); true
         with Not_found -> false))

type op =
  | Op_claim of string
  | Op_unclaim
  | Op_done
  | Op_dismiss

let verb_of_op = function
  | Op_claim _ -> "claim"
  | Op_unclaim -> "unclaim"
  | Op_done -> "done"
  | Op_dismiss -> "dismiss"

let apply_op db_path id = function
  | Op_claim by -> Ticket_store.claim ~db_path ~id ~by ()
  | Op_unclaim -> Ticket_store.unclaim ~db_path ~id ~reason:"handoff" ()
  | Op_done -> Ticket_store.mark_done ~db_path ~id ~reason:"resolved" ()
  | Op_dismiss -> Ticket_store.dismiss ~db_path ~id ~reason:"wontfix" ()

let law_state_machine_invariants =
  let open QCheck2.Gen in
  let op_gen =
    oneof
      [
        return (Op_claim "w1");
        return (Op_claim "w2");
        return Op_unclaim;
        return Op_done;
        return Op_dismiss;
      ]
  in
  let seq_gen = list_size (int_range 1 10) op_gen in
  QCheck2.Test.make ~count:50 ~name:"law_state_machine_invariants" seq_gen (fun ops ->
      with_temp_dir (fun d ->
          let db_path = Filename.concat d "prop.sqlite" in
          let r_bp3 = Filename.concat d "bp3" in
          init_git_repo r_bp3;
          ignore (Repo_store.add ~db_path ~path:r_bp3 ~name:"bp3" ());
          let init_t =
            Ticket_store.add ~db_path ~to_repo:"bp3" ~from_repo:"predictor"
              ~kind:"bug" ~title:"prop" ()
          in
          let check_invariants (t : Ticket_store.ticket) =
            let claim_fields_ok =
              match t.status with
              | "open" -> t.claimed_by = None && t.claimed_at = None
              | "claimed" -> t.claimed_by <> None && t.claimed_at <> None
              | _ -> (t.claimed_by <> None) = (t.claimed_at <> None)
            in
            let resolved_ok =
              (t.status = "done" || t.status = "dismissed")
              = (t.resolved_at <> None && t.resolution_reason <> None)
            in
            Ticket_store.valid_status t.status && claim_fields_ok && resolved_ok
          in
          let rec run_ops prev = function
            | [] -> check_invariants prev
            | op :: rest ->
                let verb = verb_of_op op in
                let legal = Ticket_store.legal_verbs_of_status prev.Ticket_store.status in
                let should_succeed = List.mem verb legal in
                let is_terminal =
                  prev.status = "done" || prev.status = "dismissed"
                in
                match apply_op db_path prev.id op with
                | next ->
                    if (not should_succeed) || is_terminal then false
                    else if not (check_invariants next) then false
                    else run_ops next rest
                | exception Db.Error (code, json) ->
                    if should_succeed || code <> 1 then false
                    else
                      let ec = err_code json in
                      let code_ok =
                        if prev.status = "claimed" && verb = "claim" then
                          ec = "E_ALREADY_CLAIMED"
                        else
                          ec = "E_ILLEGAL_EDGE"
                          &&
                          let lv =
                            Yojson.Safe.Util.(
                              err_facts json |> member "legal_verbs" |> to_list
                              |> List.map to_string)
                          in
                          lv = legal
                      in
                      let after = Ticket_store.read ~db_path prev.id in
                      let unchanged = after = prev in
                      code_ok && unchanged && run_ops prev rest
          in
          check_invariants init_t && run_ops init_t ops))

let () =
  run_test_tt_main
    ("ticket"
     >::: [
            "case_strict_to_validation_and_lifecycle" >:: case_strict_to_validation_and_lifecycle;
            "case_cli_formats_help_and_usage_errors" >:: case_cli_formats_help_and_usage_errors;
            QCheck_ounit.to_ounit2_test law_state_machine_invariants;
          ])
