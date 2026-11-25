(* Unit tests for src/repo/ (bp3_repo, sqlite-control-plane repo.1).
   case_ = named example or boundary, law_ = QCheck2 property. *)
open OUnit2

let with_temp_dir f =
  let d = Filename.temp_dir "bp3-test-repo." "" in
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

let case_add_list_dedup_conflict_and_remove _ =
  with_temp_dir (fun d ->
      let db_path = Filename.concat d "bp3.sqlite" in
      let r1 = Filename.concat d "My_Predictor" in
      let r2 = Filename.concat d "other-app" in
      let wt = Filename.concat d "wt-predictor" in
      init_git_repo r1;
      init_git_repo r2;
      let _, cw = Repo_store.run_git_capture r1 [ "worktree"; "add"; "-q"; "-b"; "feat"; wt ] in
      assert_equal ~printer:string_of_int 0 cw;
      (* Auto-derived slug lowercases and replaces underscores *)
      let a = Repo_store.add ~db_path ~path:r1 () in
      assert_equal ~printer:Fun.id "my-predictor" a.name;
      assert_equal ~printer:Fun.id (Unix.realpath r1) a.root_path;
      (* Adding from a worktree resolves to the exact same main root -> idempotent upsert *)
      let a_wt = Repo_store.add ~db_path ~path:wt () in
      assert_equal ~printer:Fun.id "my-predictor" a_wt.name;
      assert_equal ~printer:Fun.id a.root_path a_wt.root_path;
      (* Duplicate name bound to different path -> E_EXISTS *)
      (match Repo_store.add ~db_path ~path:r2 ~name:"my-predictor" () with
       | _ -> assert_failure "expected E_EXISTS on duplicate name"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 1 code;
           assert_equal ~printer:Fun.id "E_EXISTS"
             Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string));
      (* Duplicate path bound to different name -> E_EXISTS *)
      (match Repo_store.add ~db_path ~path:r1 ~name:"alias-pred" () with
       | _ -> assert_failure "expected E_EXISTS on duplicate path"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 1 code;
           assert_equal ~printer:Fun.id "E_EXISTS"
             Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string));
      let b = Repo_store.add ~db_path ~path:r2 ~name:"esc3" () in
      assert_equal ~printer:Fun.id "esc3" b.name;
      let all = Repo_store.list ~db_path () in
      assert_equal ~printer:(String.concat ",") [ "esc3"; "my-predictor" ]
        (List.map (fun (x : Repo_store.repo) -> x.name) all);
      (* CLI table + remove + E_NOT_FOUND *)
      let rc_t, out_t = capture_stdout (fun () -> Repo_cli.run ~db_path [ "list"; "--format"; "table" ]) in
      assert_equal ~printer:string_of_int 0 rc_t;
      assert_bool "table lists esc3" (String.starts_with ~prefix:"name" out_t);
      Repo_store.remove ~db_path "esc3";
      (match Repo_store.remove ~db_path "esc3" with
       | () -> assert_failure "expected E_NOT_FOUND on second remove"
       | exception Db.Error (code, json) ->
           assert_equal ~printer:string_of_int 2 code;
           assert_equal ~printer:Fun.id "E_NOT_FOUND"
             Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string)))

let case_non_git_path_and_help _ =
  with_temp_dir (fun d ->
      let db_path = Filename.concat d "no-create.sqlite" in
      let rc_h, _ = capture_stdout (fun () -> Repo_cli.run ~db_path [ "-h" ]) in
      assert_equal ~printer:string_of_int 0 rc_h;
      assert_bool "-h never creates DB" (not (Sys.file_exists db_path));
      let plain = Filename.concat d "not-a-repo" in
      Unix.mkdir plain 0o755;
      match Repo_store.add ~db_path ~path:plain () with
      | _ -> assert_failure "expected E_NOT_FOUND for non-git dir"
      | exception Db.Error (code, json) ->
          assert_equal ~printer:string_of_int 2 code;
          assert_equal ~printer:Fun.id "E_NOT_FOUND"
            Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string))

let case_project_with_spaces_regression _ =
  with_temp_dir (fun d ->
      let db_path = Filename.concat d "spaces.sqlite" in
      let spaced = Filename.concat d "project with spaces" in
      init_git_repo spaced;
      assert_equal (Ok "project-with-spaces") (Db.slugify "project with spaces");
      let r = Repo_store.add ~db_path ~path:spaced () in
      assert_equal ~printer:Fun.id "project-with-spaces" r.name;
      assert_equal ~printer:Fun.id (Unix.realpath spaced) r.root_path)

let law_slugify_always_produces_valid_slug_or_error =
  let open QCheck2.Gen in
  let ascii_dir =
    string_size
      ~gen:(oneof [ char_range 'a' 'z'; char_range 'A' 'Z'; char_range '0' '9';
                    return ' '; return '_'; return '.'; return '-'; return '!' ])
      (int_range 1 24)
  in
  QCheck2.Test.make ~count:300 ~name:"law_slugify_always_produces_valid_slug_or_error" ascii_dir
    (fun raw ->
      let has_alnum =
        String.exists
          (fun c ->
            let c = Char.lowercase_ascii c in
            (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
          raw
      in
      match Db.slugify raw with
      | Ok s -> has_alnum && Db.valid_slug s && Db.slugify s = Ok s
      | Error _ -> not has_alnum)

let () =
  run_test_tt_main
    ("repo"
     >::: [
            "case_add_list_dedup_conflict_and_remove" >:: case_add_list_dedup_conflict_and_remove;
            "case_non_git_path_and_help" >:: case_non_git_path_and_help;
            "case_project_with_spaces_regression" >:: case_project_with_spaces_regression;
            QCheck_ounit.to_ounit2_test law_slugify_always_produces_valid_slug_or_error;
          ])
