(* Unit tests for src/db/ (bp3_db, sqlite-control-plane db.1).
   case_ = named example or boundary, law_ = QCheck2 property. *)
open OUnit2

let with_temp_dir f =
  let d = Filename.temp_dir "bp3-test-db." "" in
  let rec rm_rf p =
    match Unix.lstat p with
    | { Unix.st_kind = Unix.S_DIR; _ } ->
        Array.iter (fun e -> rm_rf (Filename.concat p e)) (try Sys.readdir p with _ -> [||]);
        (try Unix.rmdir p with _ -> ())
    | _ -> (try Unix.unlink p with _ -> ())
    | exception _ -> ()
  in
  Fun.protect ~finally:(fun () -> rm_rf d) (fun () -> f d)

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

let case_fresh_init_and_idempotent_reopen _ =
  with_temp_dir (fun d ->
      let p = Filename.concat (Filename.concat d "nested") "bp3.sqlite" in
      let i1 = Db.info ~path:p () in
      assert_equal ~printer:Fun.id p i1.db_path;
      assert_equal ~printer:string_of_int 1 i1.schema_version;
      assert_equal ~printer:Fun.id "wal" i1.journal_mode;
      assert_equal ~printer:string_of_int 0 i1.repos_count;
      assert_equal ~printer:string_of_int 0 i1.tickets_open;
      assert_equal ~printer:string_of_int 0 i1.tickets_total;
      (* Re-opening an already-migrated DB is idempotent. *)
      let i2 = Db.info ~path:p () in
      assert_equal ~printer:string_of_int 1 i2.schema_version;
      assert_equal ~printer:Fun.id "wal" i2.journal_mode)

let case_forward_schema_version_refuses_with_db_error _ =
  with_temp_dir (fun d ->
      let p = Filename.concat d "future.sqlite" in
      ignore (Db.info ~path:p ());
      let raw = Sqlite3.db_open p in
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.db_close raw))
        (fun () -> assert_equal Sqlite3.Rc.OK (Sqlite3.exec raw "PRAGMA user_version = 99;"));
      match Db.info ~path:p () with
      | _ -> assert_failure "expected E_DB_ERROR for schema v99"
      | exception Db.Error (code, json) ->
          assert_equal ~printer:string_of_int 1 code;
          let err_code = Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string) in
          assert_equal ~printer:Fun.id "E_DB_ERROR" err_code)

let case_unwritable_parent_path_refuses_with_db_error _ =
  with_temp_dir (fun d ->
      let blocker = Filename.concat d "file-not-dir" in
      let oc = open_out blocker in
      close_out oc;
      let bad_db = Filename.concat blocker "bp3.sqlite" in
      match Db.info ~path:bad_db () with
      | _ -> assert_failure "expected E_DB_ERROR when parent is a regular file"
      | exception Db.Error (code, json) ->
          assert_equal ~printer:string_of_int 1 code;
          let err_code = Yojson.Safe.Util.(json |> member "error" |> member "code" |> to_string) in
          assert_equal ~printer:Fun.id "E_DB_ERROR" err_code)

let case_cli_help_never_creates_db_file _ =
  with_temp_dir (fun d ->
      let p = Filename.concat d "untouched.sqlite" in
      let rc, out = capture_stdout (fun () -> Db_cli.run ~db_path:p [ "-h" ]) in
      assert_equal ~printer:string_of_int 0 rc;
      assert_bool "help mentions bp3 db info" (String.length out > 20);
      assert_bool "db file must not exist after -h" (not (Sys.file_exists p)))

let case_cli_info_json_table_and_usage_errors _ =
  with_temp_dir (fun d ->
      let p = Filename.concat d "cli.sqlite" in
      let rc, out = capture_stdout (fun () -> Db_cli.run ~db_path:p [ "info" ]) in
      assert_equal ~printer:string_of_int 0 rc;
      let j = Yojson.Safe.from_string out in
      assert_bool "ok true" Yojson.Safe.Util.(j |> member "ok" |> to_bool);
      assert_equal ~printer:string_of_int 1 Yojson.Safe.Util.(j |> member "schema_version" |> to_int);
      assert_equal ~printer:Fun.id "wal" Yojson.Safe.Util.(j |> member "journal_mode" |> to_string);
      let rc_t, out_t = capture_stdout (fun () -> Db_cli.run ~db_path:p [ "info"; "--format"; "table" ]) in
      assert_equal ~printer:string_of_int 0 rc_t;
      assert_bool "table header" (String.starts_with ~prefix:"field" out_t);
      let rc_bad, out_bad = capture_stdout (fun () -> Db_cli.run ~db_path:p [ "info"; "--bogus" ]) in
      assert_equal ~printer:string_of_int 2 rc_bad;
      let jb = Yojson.Safe.from_string out_bad in
      assert_equal ~printer:Fun.id "E_USAGE" Yojson.Safe.Util.(jb |> member "error" |> member "code" |> to_string))

let case_slugify_and_reserved_slugs _ =
  assert_equal (Ok "my-app") (Db.slugify "My_App");
  assert_equal (Ok "project-with-spaces") (Db.slugify "project with spaces");
  assert_equal (Ok "bp3-v2") (Db.slugify "  BP3.v2!! ");
  (match Db.slugify "---" with Error _ -> () | Ok s -> assert_failure ("unexpected ok: " ^ s));
  List.iter
    (fun s -> assert_bool ("reserved: " ^ s) (List.mem s Store.reserved_slugs))
    [ "db"; "repo"; "ticket" ]

let law_resolve_path_precedence =
  let open QCheck2.Gen in
  let opt_path = oneof [ return None; return (Some ""); map (fun s -> Some ("/" ^ s)) (string_size ~gen:(char_range 'a' 'z') (int_range 1 8)) ] in
  QCheck2.Test.make ~count:200 ~name:"law_resolve_path_precedence"
    (triple opt_path opt_path opt_path)
    (fun (bp3_db, xdg_data_home, home) ->
      let got = Db.resolve_path_of ~bp3_db ~xdg_data_home ~home in
      match bp3_db with
      | Some p when p <> "" -> got = p
      | _ -> (
          match xdg_data_home with
          | Some x when x <> "" -> got = x ^ "/bp3/bp3.sqlite"
          | _ ->
              let h = match home with Some h when h <> "" -> h | _ -> "." in
              got = h ^ "/.local/share/bp3/bp3.sqlite"))

let () =
  run_test_tt_main
    ("db"
     >::: [
            "case_fresh_init_and_idempotent_reopen" >:: case_fresh_init_and_idempotent_reopen;
            "case_forward_schema_version_refuses_with_db_error" >:: case_forward_schema_version_refuses_with_db_error;
            "case_unwritable_parent_path_refuses_with_db_error" >:: case_unwritable_parent_path_refuses_with_db_error;
            "case_cli_help_never_creates_db_file" >:: case_cli_help_never_creates_db_file;
            "case_cli_info_json_table_and_usage_errors" >:: case_cli_info_json_table_and_usage_errors;
            "case_slugify_and_reserved_slugs" >:: case_slugify_and_reserved_slugs;
            QCheck_ounit.to_ounit2_test law_resolve_path_precedence;
          ])
