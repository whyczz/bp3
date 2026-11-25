(* run-suites' pure core (test-pyramid tier.1): table parsing and
   validation, selection, launch order, the budget decision, the
   lines it prints, and a suite's environment. The process side
   (groups, signals, reaping) is proven black-box by
   test/run-suites.sh.
   case_ = named example or boundary, law_ = QCheck property. *)
open OUnit2

let row ?(tier = "fixture") ?(budget = 10) ?(serial = false) ?(why = "-") name =
  { Suites.name; tier; cmd = "true"; budget_s = budget; serial; why; paths = "-" }

let line fields = String.concat "\t" fields
let ok_line = line [ "a"; "fixture"; "true"; "5"; "0"; "-"; "-" ]

let refuses ~substr f =
  match f () with
  | _ -> assert_failure ("accepted; wanted a refusal naming: " ^ substr)
  | exception Suites.Table_error m ->
      let found = try ignore (Str.search_forward (Str.regexp_string substr) m 0); true with Not_found -> false in
      assert_bool (Printf.sprintf "refusal %S lacks %S" m substr) found

let case_a_well_formed_row_parses_every_field _ =
  let r = Suites.parse_row ~where:"t:1" (line [ "harness-cli"; "slow"; "bash x.sh"; "90"; "1"; "pty"; "src/*" ]) in
  assert_equal ~printer:Fun.id "harness-cli" r.name;
  assert_equal ~printer:Fun.id "slow" r.tier;
  assert_equal ~printer:Fun.id "bash x.sh" r.cmd;
  assert_equal ~printer:string_of_int 90 r.budget_s;
  assert_bool "serial" r.serial;
  assert_equal ~printer:Fun.id "pty" r.why;
  assert_equal ~printer:Fun.id "src/*" r.paths

let case_a_row_with_six_or_eight_fields_is_refused_with_the_count _ =
  refuses ~substr:"got 6" (fun () -> Suites.parse_row ~where:"t:1" (line [ "a"; "fixture"; "true"; "5"; "0"; "-" ]));
  refuses ~substr:"got 8" (fun () -> Suites.parse_row ~where:"t:1" (ok_line ^ "\tx"))

let case_an_empty_field_is_refused_and_points_at_the_dash _ =
  refuses ~substr:"use '-'" (fun () -> Suites.parse_row ~where:"t:1" (line [ "a"; "fixture"; "true"; "5"; "0"; ""; "-" ]))

let case_a_suite_name_never_escapes_the_run_dir _ =
  List.iter (fun n ->
      refuses ~substr:"suite name" (fun () ->
          Suites.parse_row ~where:"t:1" (line [ n; "fixture"; "true"; "5"; "0"; "-"; "-" ])))
    [ ".."; "."; ".hidden"; "a/b"; "/abs"; "../x"; "a b"; "a*" ];
  List.iter (fun n ->
      assert_equal ~printer:Fun.id n (Suites.parse_row ~where:"t:1" (line [ n; "fixture"; "true"; "5"; "0"; "-"; "-" ])).name)
    [ "harness-cli"; "run_suites"; "a.b"; "x1" ]

let case_budget_must_be_a_positive_decimal_integer _ =
  List.iter (fun b ->
      refuses ~substr:"budget_s" (fun () ->
          Suites.parse_row ~where:"t:1" (line [ "a"; "fixture"; "true"; b; "0"; "-"; "-" ])))
    [ "0"; "-5"; "2.5"; "0x10"; "+5"; "5s"; " 5" ]

let case_serial_is_0_or_1_only _ =
  List.iter (fun v ->
      refuses ~substr:"serial" (fun () ->
          Suites.parse_row ~where:"t:1" (line [ "a"; "fixture"; "true"; "5"; v; "-"; "-" ])))
    [ "2"; "yes"; "true"; "-" ]

let case_tier_is_unit_fixture_or_slow_and_a_slow_row_needs_a_why _ =
  List.iter (fun t -> assert_equal ~printer:Fun.id t (Suites.parse_row ~where:"t:1" (line [ "a"; t; "true"; "5"; "0"; "-"; "-" ])).tier)
    [ "unit"; "fixture" ];
  List.iter (fun t -> refuses ~substr:"tier must be unit, fixture or slow" (fun () ->
      Suites.parse_row ~where:"t:1" (line [ "a"; t; "true"; "5"; "0"; "-"; "-" ])))
    [ "contract"; "Unit"; "fast" ];
  refuses ~substr:"needs a why" (fun () -> Suites.parse_row ~where:"t:1" (line [ "a"; "slow"; "true"; "5"; "0"; "-"; "-" ]))

let case_the_table_skips_comments_and_blanks_and_names_the_line_it_refuses _ =
  let text = String.concat "\n" [ "# header"; ""; ok_line; "# more"; line [ "b"; "slow"; "x"; "9"; "0"; "pty"; "-" ]; "" ] in
  let rows = Suites.parse_table ~file:"t.tsv" text in
  assert_equal ~printer:(String.concat ",") [ "a"; "b" ] (List.map (fun r -> r.Suites.name) rows);
  refuses ~substr:"t.tsv:3" (fun () -> Suites.parse_table ~file:"t.tsv" ("# c\n\nbad row\n"))

let case_a_duplicate_name_and_an_empty_table_are_refused _ =
  refuses ~substr:"duplicate suite name: a" (fun () -> Suites.parse_table ~file:"t" (ok_line ^ "\n" ^ ok_line));
  refuses ~substr:"empty suite table" (fun () -> Suites.parse_table ~file:"t" "# only comments\n\n")

let case_select_keeps_table_order_and_refuses_an_unknown_only_name _ =
  let rows = [ row "a"; row ~tier:"slow" ~why:"w" "b"; row "c" ] in
  let names l = List.map (fun r -> r.Suites.name) l in
  assert_equal ~printer:(String.concat ",") [ "a"; "c" ] (names (Suites.select ~tiers:[ "fixture" ] ~only:None rows));
  assert_equal ~printer:(String.concat ",") [ "a"; "b" ]
    (names (Suites.select ~tiers:[ "fixture"; "slow" ] ~only:(Some [ "b"; "a" ]) rows));
  assert_equal ~printer:(String.concat ",") [] (names (Suites.select ~tiers:[ "fixture" ] ~only:(Some [ "b" ]) rows));
  refuses ~substr:"unknown suite: zz" (fun () -> Suites.select ~tiers:[ "fixture" ] ~only:(Some [ "a"; "zz" ]) rows)

let case_launch_order_puts_the_largest_budget_first_and_keeps_ties_in_table_order _ =
  let rows = [ row ~budget:5 "s1"; row ~budget:60 "mid"; row ~budget:5 "s2"; row ~budget:90 "long"; row ~budget:60 "mid2" ] in
  assert_equal ~printer:(String.concat ",") [ "long"; "mid"; "mid2"; "s1"; "s2" ]
    (List.map (fun r -> r.Suites.name) (Suites.launch_order rows))

let case_a_budget_fires_only_strictly_past_it _ =
  assert_bool "1999ms inside 2s" (not (Suites.over_budget ~now_ms:1999 ~start_ms:0 ~budget_s:2));
  assert_bool "exactly 2000ms is inside" (not (Suites.over_budget ~now_ms:12_000 ~start_ms:10_000 ~budget_s:2));
  assert_bool "2001ms is over" (Suites.over_budget ~now_ms:12_001 ~start_ms:10_000 ~budget_s:2)

let case_seconds_print_with_one_truncated_decimal _ =
  List.iter (fun (ms, want) -> assert_equal ~printer:Fun.id want (Suites.secs ms))
    [ (0, "0.0"); (99, "0.0"); (1234, "1.2"); (1999, "1.9"); (25_049, "25.0"); (60_000, "60.0") ]

let char_result_lines_for_pass_exit_and_budget _ =
  let r = row ~budget:2 "sleeper" in
  assert_equal ~printer:Fun.id "  ok   sleeper                   1.5s  (budget 2s)" (Suites.result_line r ~took_ms:1500 Suites.Passed);
  assert_equal ~printer:Fun.id "  FAIL sleeper                   0.3s  (budget 2s)  rc=3" (Suites.result_line r ~took_ms:300 (Suites.Exit 3));
  assert_equal ~printer:Fun.id "  FAIL sleeper                   2.0s  (budget 2s)  budget exceeded, group killed"
    (Suites.result_line r ~took_ms:2049 Suites.Budget)

let char_summaries_and_the_report_sorted_by_share_then_name _ =
  assert_equal ~printer:Fun.id "run-suites: ok 3/3  wall 25.0s  (serial sum 40.1s)"
    (Suites.summary_ok ~count:3 ~wall_ms:25_000 ~sum_ms:40_150);
  assert_equal ~printer:Fun.id "run-suites: FAIL 2/31: forkwin leak  wall 60.3s"
    (Suites.summary_fail ~failed:[ "forkwin"; "leak" ] ~count:31 ~wall_ms:60_300);
  assert_equal ~printer:(String.concat "\n")
    [ "run-suites: report (actual vs budget, highest share first)";
      "   50%  b                      30.0/60s";
      "   50%  c                      5.0/10s";
      "   10%  a                      6.0/60s" ]
    (Suites.report_lines [ (row ~budget:60 "a", 6000); (row ~budget:10 "c", 5000); (row ~budget:60 "b", 30_000) ])

let case_signal_exits_are_128_plus_the_posix_number _ =
  assert_equal ~printer:string_of_int 129 (Suites.signal_exit Sys.sighup);
  assert_equal ~printer:string_of_int 130 (Suites.signal_exit Sys.sigint);
  assert_equal ~printer:string_of_int 131 (Suites.signal_exit Sys.sigquit);
  assert_equal ~printer:string_of_int 143 (Suites.signal_exit Sys.sigterm)

let case_suite_env_drops_home_git_and_bp3_and_keeps_the_allowlist _ =
  let caller = [ "HOME=/Users/me"; "PATH=/bin"; "GIT_DIR=/x"; "BP3_DECIDER=human"; "LC_ALL=C"; "LANG=en";
                 "SECRET=1"; "LC_=odd"; "NOEQUALS" ] in
  let env = Suites.suite_env ~caller ~home:"/tmp/r/a/home" ~name:"a" in
  assert_equal ~printer:(String.concat " ")
    [ "PATH=/bin"; "LC_ALL=C"; "LANG=en";
      "HOME=/tmp/r/a/home"; "TMPDIR=/tmp/r/a/home/t"; "BP3_DB=/tmp/r/a/home/bp3.sqlite";
      "BP3_SUITE=a"; "GIT_CONFIG_NOSYSTEM=1" ] env

(* --- laws --- *)

let gen_rows =
  QCheck2.Gen.(map (List.mapi (fun i (b, s) -> row ~budget:b ~serial:s (Printf.sprintf "r%d" i)))
                 (list_size (int_range 0 30) (pair (int_range 1 120) bool)))

let law_launch_order_is_a_permutation_sorted_by_budget_and_stable =
  QCheck2.Test.make ~name:"law_launch_order_is_a_permutation_sorted_by_budget_and_stable" ~count:500 gen_rows
    (fun rows ->
      let out = Suites.launch_order rows in
      let idx r = int_of_string (String.sub r.Suites.name 1 (String.length r.Suites.name - 1)) in
      let rec sorted = function
        | a :: (b :: _ as rest) ->
            (a.Suites.budget_s > b.Suites.budget_s || (a.Suites.budget_s = b.Suites.budget_s && idx a < idx b)) && sorted rest
        | _ -> true in
      List.sort compare (List.map idx out) = List.sort compare (List.map idx rows) && sorted out)

let law_a_printed_row_parses_back_to_itself =
  let field = QCheck2.Gen.(string_size ~gen:(oneof [ char_range 'a' 'z'; return '-'; return ' '; return '/' ]) (int_range 1 12)) in
  let gen = QCheck2.Gen.(tup6 field field (int_range 1 9999) bool (oneof [ return "fixture"; return "slow" ]) field) in
  QCheck2.Test.make ~name:"law_a_printed_row_parses_back_to_itself" ~count:500 gen
    (fun (name, cmd, budget, serial, tier, why) ->
      let name = "n" ^ String.map (fun c -> if c = ' ' || c = '/' then '_' else c) name in
      let why = if tier = "slow" && why = "-" then "w" else why in
      let text = line [ name; tier; cmd; string_of_int budget; (if serial then "1" else "0"); why; "-" ] in
      let r = Suites.parse_row ~where:"t" text in
      r = { Suites.name; tier; cmd; budget_s = budget; serial; why; paths = "-" })

let law_over_budget_never_reverts_as_time_grows =
  QCheck2.Test.make ~name:"law_over_budget_never_reverts_as_time_grows" ~count:500
    QCheck2.Gen.(quad (int_range 0 1_000_000) (int_range 1 600) (int_range 0 1_000_000) (int_range 0 1_000_000))
    (fun (start_ms, budget_s, a, b) ->
      let now1 = start_ms + min a b and now2 = start_ms + max a b in
      (not (Suites.over_budget ~now_ms:now1 ~start_ms ~budget_s)) || Suites.over_budget ~now_ms:now2 ~start_ms ~budget_s)

let () =
  run_test_tt_main
    ("suites" >::: [
       "case_a_well_formed_row_parses_every_field" >:: case_a_well_formed_row_parses_every_field;
       "case_a_row_with_six_or_eight_fields_is_refused_with_the_count" >:: case_a_row_with_six_or_eight_fields_is_refused_with_the_count;
       "case_an_empty_field_is_refused_and_points_at_the_dash" >:: case_an_empty_field_is_refused_and_points_at_the_dash;
       "case_a_suite_name_never_escapes_the_run_dir" >:: case_a_suite_name_never_escapes_the_run_dir;
       "case_budget_must_be_a_positive_decimal_integer" >:: case_budget_must_be_a_positive_decimal_integer;
       "case_serial_is_0_or_1_only" >:: case_serial_is_0_or_1_only;
       "case_tier_is_unit_fixture_or_slow_and_a_slow_row_needs_a_why" >:: case_tier_is_unit_fixture_or_slow_and_a_slow_row_needs_a_why;
       "case_the_table_skips_comments_and_blanks_and_names_the_line_it_refuses" >:: case_the_table_skips_comments_and_blanks_and_names_the_line_it_refuses;
       "case_a_duplicate_name_and_an_empty_table_are_refused" >:: case_a_duplicate_name_and_an_empty_table_are_refused;
       "case_select_keeps_table_order_and_refuses_an_unknown_only_name" >:: case_select_keeps_table_order_and_refuses_an_unknown_only_name;
       "case_launch_order_puts_the_largest_budget_first_and_keeps_ties_in_table_order" >:: case_launch_order_puts_the_largest_budget_first_and_keeps_ties_in_table_order;
       "case_a_budget_fires_only_strictly_past_it" >:: case_a_budget_fires_only_strictly_past_it;
       "case_seconds_print_with_one_truncated_decimal" >:: case_seconds_print_with_one_truncated_decimal;
       "char_result_lines_for_pass_exit_and_budget" >:: char_result_lines_for_pass_exit_and_budget;
       "char_summaries_and_the_report_sorted_by_share_then_name" >:: char_summaries_and_the_report_sorted_by_share_then_name;
       "case_signal_exits_are_128_plus_the_posix_number" >:: case_signal_exits_are_128_plus_the_posix_number;
       "case_suite_env_drops_home_git_and_bp3_and_keeps_the_allowlist" >:: case_suite_env_drops_home_git_and_bp3_and_keeps_the_allowlist;
       QCheck_ounit.to_ounit2_test law_launch_order_is_a_permutation_sorted_by_budget_and_stable;
       QCheck_ounit.to_ounit2_test law_a_printed_row_parses_back_to_itself;
       QCheck_ounit.to_ounit2_test law_over_budget_never_reverts_as_time_grows;
     ])
