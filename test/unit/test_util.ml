(* Unit tests for src/quest/util.ml (codebase-diet clean.1):
   known cases + QCheck2 roundtrip properties over shared primitives. *)
open OUnit2

let with_temp_dir f =
  let base = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "bp3-util-test-%d-%d" (Unix.getpid ()) (Random.int 1_000_000)) in
  Util.mkdir_p base;
  let rec rm_rf p =
    match Unix.lstat p with
    | { Unix.st_kind = Unix.S_DIR; _ } ->
        Array.iter (fun e -> rm_rf (Filename.concat p e)) (try Sys.readdir p with _ -> [||]);
        (try Unix.rmdir p with _ -> ())
    | _ -> (try Unix.unlink p with _ -> ())
    | exception _ -> () in
  Fun.protect ~finally:(fun () -> rm_rf base) (fun () -> f base)

let read_all path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let case_contains_sub _ =
  assert_bool "empty needle" (Util.contains_sub "" "");
  assert_bool "empty needle in non-empty" (Util.contains_sub "abc" "");
  assert_bool "non-empty needle in empty" (not (Util.contains_sub "" "a"));
  assert_bool "start" (Util.contains_sub "hello world" "hello");
  assert_bool "middle" (Util.contains_sub "hello world" "lo wo");
  assert_bool "end" (Util.contains_sub "hello world" "world");
  assert_bool "miss" (not (Util.contains_sub "hello" "world"));
  assert_bool "needle longer" (not (Util.contains_sub "hi" "hii"))

let case_strip_prefix _ =
  assert_equal (Some "bar") (Util.strip_prefix ~prefix:"foo" "foobar");
  assert_equal (Some "") (Util.strip_prefix ~prefix:"foo" "foo");
  assert_equal (Some "abc") (Util.strip_prefix ~prefix:"" "abc");
  assert_equal None (Util.strip_prefix ~prefix:"foo" "fo");
  assert_equal None (Util.strip_prefix ~prefix:"foo" "barfoo")

let case_mkdir_p_and_write_file_atomic _ =
  with_temp_dir (fun dir ->
    let nested = Filename.concat dir "a/b/c" in
    Util.mkdir_p nested;
    Util.mkdir_p nested; (* idempotent *)
    assert_bool "nested dir exists" (Sys.is_directory nested);
    let target = Filename.concat nested "data.txt" in
    Util.write_file_atomic target "first\n";
    assert_equal ~printer:Fun.id "first\n" (read_all target);
    Util.write_file_atomic target "second\n";
    assert_equal ~printer:Fun.id "second\n" (read_all target);
    let entries = Sys.readdir nested |> Array.to_list in
    assert_equal [ "data.txt" ] entries)

let case_epoch_of_iso _ =
  assert_equal (Some 0.) (Util.epoch_of_iso "1970-01-01T00:00:00Z");
  assert_equal (Some 1_795_000_000.) (Util.epoch_of_iso "2026-11-18T11:06:40Z");
  assert_equal None (Util.epoch_of_iso "not-a-date");
  assert_equal None (Util.epoch_of_iso "2026-13-01T00:00:00Z");
  assert_equal None (Util.epoch_of_iso "2026-11-18T25:00:00Z");
  assert_equal None (Util.epoch_of_iso "2026-11-18T11:06:40+00:00")

let case_total_json_getters _ =
  let j = Yojson.Safe.from_string {|{"s":"hi","n":42,"b":true,"o":{"k":1},"nil":null}|} in
  assert_equal (Some "hi") (Util.get_str_opt j "s");
  assert_equal None (Util.get_str_opt j "n");
  assert_equal None (Util.get_str_opt j "nil");
  assert_equal None (Util.get_str_opt `Null "s");
  assert_equal ~printer:Fun.id "hi" (Util.get_str j "s" "def");
  assert_equal ~printer:Fun.id "def" (Util.get_str j "n" "def");
  assert_equal ~printer:Fun.id "def" (Util.get_str (`List []) "s" "def");
  assert_equal (Some 42) (Util.get_int_opt j "n");
  assert_equal None (Util.get_int_opt j "s");
  assert_equal ~printer:string_of_int 42 (Util.get_int j "n" 7);
  assert_equal ~printer:string_of_int 7 (Util.get_int j "s" 7);
  assert_equal true (Util.get_bool j "b" false);
  assert_equal false (Util.get_bool j "s" false);
  assert_bool "obj present" (Util.get_obj j "o" <> None);
  assert_equal None (Util.get_obj j "s");
  assert_equal `Null (Util.member "missing" j);
  assert_equal `Null (Util.member "s" (`Int 1))

let law_strip_prefix_roundtrip =
  QCheck2.Test.make ~count:300 ~name:"law_strip_prefix_roundtrip"
    QCheck2.Gen.(pair string string)
    (fun (prefix, s) -> Util.strip_prefix ~prefix (prefix ^ s) = Some s)

let law_contains_sub_always_finds_embedded_substring =
  QCheck2.Test.make ~count:300 ~name:"law_contains_sub_always_finds_embedded_substring"
    QCheck2.Gen.(triple string string string)
    (fun (a, b, c) -> Util.contains_sub (a ^ b ^ c) b)

let () =
  Random.self_init ();
  run_test_tt_main
    ("util" >::: [
       "case_contains_sub" >:: case_contains_sub;
       "case_strip_prefix" >:: case_strip_prefix;
       "case_mkdir_p_and_write_file_atomic" >:: case_mkdir_p_and_write_file_atomic;
       "case_epoch_of_iso" >:: case_epoch_of_iso;
       "case_total_json_getters" >:: case_total_json_getters;
       QCheck_ounit.to_ounit2_test law_strip_prefix_roundtrip;
       QCheck_ounit.to_ounit2_test law_contains_sub_always_finds_embedded_substring;
     ])
