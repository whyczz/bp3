(* CLI and config edges (test-pyramid unit.4): flag parsing and its
   typed refusals, verb spellings, dep lists, index keys. Cli holds
   main.ml's argv helpers (moved there so tests can link them). Not
   here: Config.canon_path, desk_matches and load_thresholds read the
   filesystem or git (fixture tier, config.sh / worktree.sh). *)
open OUnit2

let code f =
  match f () with
  | _ -> "no verdict"
  | exception Gitx.Verdict (_, j) -> Yojson.Safe.Util.(j |> member "error" |> member "code" |> to_string)

let case_split_flags_separates_positionals_from_flags _ =
  let (pos, fl) = Cli.split_flags [ "n1"; "handoff"; "--commit"; "abc"; "--reason"; "r" ] in
  assert_equal [ "n1"; "handoff" ] pos;
  assert_equal (Some "abc") fl.Cli.commit;
  assert_equal (Some "r") fl.Cli.reason;
  assert_equal ~printer:Fun.id "json" fl.Cli.fmt;
  let (_, fl) = Cli.split_flags [ "--mechanical"; "--format"; "table" ] in
  assert_bool "mechanical" fl.Cli.mechanical;
  assert_equal ~printer:Fun.id "table" fl.Cli.fmt

let case_parse_flags_refuses_each_bad_form_with_E_USAGE _ =
  List.iter (fun args ->
      assert_equal ~msg:(String.concat " " args) ~printer:Fun.id "E_USAGE" (code (fun () -> Cli.parse_flags args)))
    [ [ "--reason" ]; [ "--reason"; "a"; "--reason"; "b" ]; [ "--bogus"; "x" ]; [ "--reason=a" ];
      [ "stray" ]; [ "--mode"; "self" ]; [ "--mode=self" ]; [ "--format"; "yaml" ];
      [ "--format"; "json"; "--format"; "json" ]; [ "--mechanical"; "--mechanical" ] ]

let case_parse_dep_list_trims_names_and_drops_blanks _ =
  assert_equal [ "a"; "node-1" ] (Cli.parse_dep_list (Some " a ,, node-1 ,"));
  assert_equal [] (Cli.parse_dep_list (Some ""));
  assert_equal [] (Cli.parse_dep_list None)

let char_parse_dep_list_keeps_each_duplicate_at_its_last_position _ =
  assert_equal [ "a"; "c"; "b" ] (Cli.parse_dep_list (Some " a, b,,a ,c,b"))

let law_parse_dep_list_has_no_blanks_or_duplicates =
  QCheck2.Test.make ~count:300 ~name:"law_parse_dep_list_has_no_blanks_or_duplicates"
    QCheck2.Gen.(list_size (int_range 0 8) (oneof_list [ "a"; "b"; " c"; ""; "  "; "node-1" ]))
    (fun parts ->
      let ds = Cli.parse_dep_list (Some (String.concat "," parts)) in
      List.for_all (fun d -> d <> "" && String.trim d = d) ds
      && List.length (List.sort_uniq compare ds) = List.length ds)

let case_verbs_normalize_long_and_short_spellings_and_help_flags _ =
  List.iter (fun (v, n) -> assert_equal ~printer:Fun.id n (Cli.normalize_verb v); assert_bool v (Cli.is_verb v))
    [ ("c", "c"); ("create", "c"); ("r", "r"); ("read", "r"); ("u", "u"); ("update", "u"); ("d", "d"); ("delete", "d") ];
  assert_equal ~printer:Fun.id "diagram" (Cli.normalize_verb "diagram");
  assert_bool "dep is not a verb" (not (Cli.is_verb "dep"));
  assert_bool "-h" (Cli.is_help "-h"); assert_bool "--help" (Cli.is_help "--help"); assert_bool "help" (not (Cli.is_help "help"))

let case_valid_index_key_refuses_paths_and_dot_names _ =
  List.iter (fun (k, ok) -> assert_equal ~msg:(Printf.sprintf "%S" k) ok (Config.valid_index_key k))
    [ ("S-abc123", true); ("sess.1", true); ("", false); (".", false); ("..", false); (".hidden", false);
      ("a/b", false); ("a\\b", false); ("a..b", false) ]

let () =
  run_test_tt_main
    ("main" >::: [
       "case_split_flags_separates_positionals_from_flags" >:: case_split_flags_separates_positionals_from_flags;
       "case_parse_flags_refuses_each_bad_form_with_E_USAGE" >:: case_parse_flags_refuses_each_bad_form_with_E_USAGE;
       "case_parse_dep_list_trims_names_and_drops_blanks" >:: case_parse_dep_list_trims_names_and_drops_blanks;
       "char_parse_dep_list_keeps_each_duplicate_at_its_last_position" >:: char_parse_dep_list_keeps_each_duplicate_at_its_last_position;
       QCheck_ounit.to_ounit2_test law_parse_dep_list_has_no_blanks_or_duplicates;
       "case_verbs_normalize_long_and_short_spellings_and_help_flags" >:: case_verbs_normalize_long_and_short_spellings_and_help_flags;
       "case_valid_index_key_refuses_paths_and_dot_names" >:: case_valid_index_key_refuses_paths_and_dot_names;
     ])
