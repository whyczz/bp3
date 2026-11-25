(* Unit & QCheck2 tests for src/quest/backpack.ml (manifest.1):
   strict TOML subset parsing, escaping, comments, validation refusals,
   render_default line budget (<= 15), and serialize->parse round-trip law. *)
open OUnit2

let expect_ok = function
  | Ok v -> v
  | Error e -> assert_failure ("expected Ok, got Error: " ^ e)

let expect_err substr = function
  | Ok _ -> assert_failure ("expected Error containing " ^ substr ^ ", got Ok")
  | Error e ->
      let has =
        try ignore (Str.search_forward (Str.regexp_string substr) e 0); true
        with Not_found -> false in
      assert_bool ("error " ^ e ^ " should contain " ^ substr) has

let case_minimal_manifest _ =
  let cfg = expect_ok (Backpack.parse "version = 1\nrepo = \"bp3\"\n") in
  assert_equal 1 cfg.version;
  assert_equal "bp3" cfg.repo;
  assert_equal None cfg.grade_gate;
  assert_equal None cfg.warden_grade_wall_s;
  assert_equal None cfg.release_target

let case_predictor_full_manifest _ =
  let txt =
    "# predictor repo rules\n\
     version = 1 # schema v1\n\
     repo = \"predictor\"\n\n\
     [grade]\n\
     gate = \"dune build --root . @fmt && dune test --root . --force 4>&-\"\n\n\
     [warden]\n\
     grade_wall_s = 600 # cold OCaml build\n\n\
     [release]\n\
     target = \"master\"\n" in
  let cfg = expect_ok (Backpack.parse txt) in
  assert_equal 1 cfg.version;
  assert_equal "predictor" cfg.repo;
  assert_equal (Some "dune build --root . @fmt && dune test --root . --force 4>&-") cfg.grade_gate;
  assert_equal (Some 600) cfg.warden_grade_wall_s;
  assert_equal (Some "master") cfg.release_target

let case_hash_inside_quotes_and_escapes_preserved _ =
  let txt =
    "version = 1\r\n\
     repo = \"demo-repo\"\r\n\
     [grade]\r\n\
     gate = \"sh -c \\\"echo ok # keep\\\" && echo \\\\done\" # strip this\r\n" in
  let cfg = expect_ok (Backpack.parse txt) in
  assert_equal (Some "sh -c \"echo ok # keep\" && echo \\done") cfg.grade_gate

let case_render_default_under_15_lines_and_parses _ =
  let txt = Backpack.render_default ~repo:"bp3" ~target:"master" in
  let nlines = List.length (String.split_on_char '\n' (String.trim txt)) in
  assert_bool ("expected <= 15 lines, got " ^ string_of_int nlines) (nlines <= 15);
  let cfg = expect_ok (Backpack.parse txt) in
  assert_equal "bp3" cfg.repo;
  assert_equal (Some "make check-full") cfg.grade_gate;
  assert_equal (Some 300) cfg.warden_grade_wall_s;
  assert_equal (Some "master") cfg.release_target

let case_validation_refusals _ =
  expect_err "missing required key: version" (Backpack.parse "repo = \"bp3\"\n");
  expect_err "missing required key: repo" (Backpack.parse "version = 1\n");
  expect_err "unsupported version 2" (Backpack.parse "version = 2\nrepo = \"bp3\"\n");
  expect_err "unknown section [extra]" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[extra]\nx = 1\n");
  expect_err "duplicate section [grade]" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[grade]\ngate = \"a\"\n[grade]\n");
  expect_err "unknown key warden.grade_wall" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[warden]\ngrade_wall = 600\n");
  expect_err "duplicate key repo" (Backpack.parse "version = 1\nrepo = \"a\"\nrepo = \"b\"\n");
  expect_err "grade_wall_s must be > 0" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[warden]\ngrade_wall_s = 0\n");
  expect_err "grade_wall_s must be > 0" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[warden]\ngrade_wall_s = -5\n");
  expect_err "invalid integer" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[warden]\ngrade_wall_s = \"600\"\n");
  expect_err "unterminated string" (Backpack.parse "version = 1\nrepo = \"bp3\n");
  expect_err "expected key = value" (Backpack.parse "version = 1\nnot-a-pair\n");
  expect_err "non-empty slug" (Backpack.parse "version = 1\nrepo = \"has space\"\n");
  expect_err "non-empty branch" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[release]\ntarget = \"bad branch\"\n");
  expect_err "must be non-empty" (Backpack.parse "version = 1\nrepo = \"bp3\"\n[grade]\ngate = \"   \"\n")

let case_warning_and_json_shape _ =
  let w = Backpack.warning_no_repo_config () in
  assert_equal (`String Names.w_no_repo_config) (Yojson.Safe.Util.member "code" w);
  let cfg = Backpack.default_config ~repo:"bp3" ~target:"master" in
  let j = Backpack.to_json cfg in
  assert_equal (`Int 1) (Yojson.Safe.Util.member "version" j);
  assert_equal (`String "bp3") (Yojson.Safe.Util.member "repo" j);
  assert_equal (`Int 300) (Yojson.Safe.Util.(j |> member "warden" |> member "grade_wall_s"))

let gen_slug =
  let open QCheck2.Gen in
  let ch = oneof [ char_range 'a' 'z'; char_range '0' '9'; return '-' ] in
  map (fun s -> "r" ^ s) (string_size ~gen:ch (int_range 0 12))

let gen_gate =
  let open QCheck2.Gen in
  let ch = oneof [ char_range 'a' 'z'; char_range '0' '9';
                   oneof_list [ ' '; '-'; '_'; '.'; '/'; '&'; '|'; '#'; '"'; '\\'; '='; '>' ] ] in
  map (fun s -> "cmd " ^ s) (string_size ~gen:ch (int_range 0 30))

let gen_cfg =
  let open QCheck2.Gen in
  let* repo = gen_slug in
  let* grade_gate = option gen_gate in
  let* warden_grade_wall_s = option (int_range 1 3600) in
  let* release_target = option gen_slug in
  return { Backpack.version = 1; repo; grade_gate; warden_grade_wall_s; release_target }

let law_render_parse_roundtrip_and_line_cap =
  QCheck2.Test.make ~count:300 ~name:"law_render_parse_roundtrip_and_line_cap"
    gen_cfg
    (fun cfg ->
       let rendered = Backpack.render cfg in
       let nlines = List.length (String.split_on_char '\n' (String.trim rendered)) in
       nlines <= 15 && Backpack.parse rendered = Ok cfg)

let () =
  run_test_tt_main
    ("backpack" >::: [
       "case_minimal_manifest" >:: case_minimal_manifest;
       "case_predictor_full_manifest" >:: case_predictor_full_manifest;
       "case_hash_inside_quotes_and_escapes_preserved" >:: case_hash_inside_quotes_and_escapes_preserved;
       "case_render_default_under_15_lines_and_parses" >:: case_render_default_under_15_lines_and_parses;
       "case_validation_refusals" >:: case_validation_refusals;
       "case_warning_and_json_shape" >:: case_warning_and_json_shape;
       QCheck_ounit.to_ounit2_test law_render_parse_roundtrip_and_line_cap;
     ])
