(* Run-id mint (test-pyramid seam.1): the first field carries UTC to
   the millisecond plus 4 hex, a collision draws again with no sleep,
   and every reader of run-ids still parses the new shape.
   case_ = named example, law_ = QCheck property, char_ = today's
   behavior pinned without blessing it. *)
open OUnit2

let id ~ts ~edge ~harness ~model ~cycle =
  Printf.sprintf "%s-%s-%s-%s-c%d" ts edge (Harness.slug_keep harness) (Harness.slug_keep model) cycle

let case_mint_ts_writes_utc_milliseconds_and_the_random_hex_in_one_field _ =
  assert_equal ~printer:Fun.id "20261118T110640.123a7f3Z" (Harness.mint_ts_of 1_795_000_000.123 "a7f3")

let case_mint_ts_writes_000_on_the_second_and_clamps_the_last_half_millisecond_to_999 _ =
  assert_equal ~printer:Fun.id "20261118T110640.000beefZ" (Harness.mint_ts_of 1_795_000_000. "beef");
  assert_equal ~printer:Fun.id "20261118T110640.999beefZ" (Harness.mint_ts_of 1_795_000_000.9996 "beef")

let case_readers_parse_both_the_old_and_the_new_run_id_shapes _ =
  List.iter (fun (rid, want) ->
      assert_equal ~msg:rid want (Hooks.parse_edge_cycle rid);
      assert_bool ("valid_run_id " ^ rid) (Worktree.valid_run_id rid))
    [ ("20261118T110640Z-handoff-pi-none-c2", ("handoff", 2));
      ("20261118T110640.123a7f3Z-handoff-pi-none-c2", ("handoff", 2));
      ("20261118T110640.000beefZ-grade-muse-code-claude-opus-5-5-c3", ("grade", 3)) ]

let case_a_thousand_mints_under_a_frozen_clock_are_all_distinct_and_never_sleep _ =
  let taken = Hashtbl.create 1024 in
  let claim c = if Hashtbl.mem taken c then false else (Hashtbl.add taken c (); true) in
  let candidate () =
    id ~ts:(Harness.mint_ts_of (Clock.now ()) (Harness.random_hex4 ())) ~edge:"handoff"
      ~harness:"pi" ~model:"m" ~cycle:1 in
  let t0 = Unix.gettimeofday () in
  Clock.with_fixed 1_795_000_000.5 (fun () ->
      for _ = 1 to 1000 do
        match Harness.mint_unique ~tries:8 ~candidate ~claim with
        | Some _ -> ()
        | None -> assert_failure "eight draws all collided"
      done);
  assert_equal ~printer:string_of_int 1000 (Hashtbl.length taken);
  assert_bool "no sleeping: 1000 mints well under a second" (Unix.gettimeofday () -. t0 < 1.0)

let case_mint_unique_gives_up_after_its_tries_without_sleeping _ =
  let draws = ref 0 in
  let r = Harness.mint_unique ~tries:3 ~candidate:(fun () -> incr draws; "same") ~claim:(fun _ -> false) in
  assert_equal None r;
  assert_equal ~printer:string_of_int 3 !draws

let char_a_model_name_with_two_dots_mints_an_id_valid_run_id_refuses _ =
  let rid = id ~ts:"20261118T110640.123a7f3Z" ~edge:"handoff" ~harness:"pi" ~model:"x..y" ~cycle:1 in
  assert_bool "slug_keep keeps dots, valid_run_id refuses '..'" (not (Worktree.valid_run_id rid))

let gen_edge = QCheck2.Gen.(string_size ~gen:(char_range 'a' 'z') (int_range 1 10))
let gen_hex4 = QCheck2.Gen.(string_size ~gen:(oneof [ char_range '0' '9'; char_range 'a' 'f' ]) (return 4))

let law_minted_ids_parse_back_to_their_edge_and_cycle =
  QCheck2.Test.make ~count:500 ~name:"law_minted_ids_parse_back_to_their_edge_and_cycle"
    ~print:(fun (e, h, m, c, t, r) -> id ~ts:(Harness.mint_ts_of t r) ~edge:e ~harness:h ~model:m ~cycle:c)
    QCheck2.Gen.(map (fun ((e, h, m), (c, t, r)) -> (e, h, m, c, t, r))
                   (pair (triple gen_edge string string) (triple (int_range 0 1000) (float_range 0. 4.0e9) gen_hex4)))
    (fun (edge, harness, model, cycle, t, r) ->
      Hooks.parse_edge_cycle (id ~ts:(Harness.mint_ts_of t r) ~edge ~harness ~model ~cycle) = (edge, cycle))

(* Ids sort by mint time: a later mint (one millisecond or more)
   sorts after an earlier one, whatever the random hex. *)
let law_mint_ts_sorts_like_time =
  QCheck2.Test.make ~count:500 ~name:"law_mint_ts_sorts_like_time"
    ~print:(fun (t, d, r1, r2) -> Printf.sprintf "%s < %s" (Harness.mint_ts_of t r1) (Harness.mint_ts_of (t +. d) r2))
    QCheck2.Gen.(quad (float_range 0. 4.0e9)
                   (oneof [ float_range 0.002 0.05; float_range 0.002 1e6 ]) gen_hex4 gen_hex4)
    (fun (t, d, r1, r2) -> compare (Harness.mint_ts_of t r1) (Harness.mint_ts_of (t +. d) r2) < 0)

let () =
  run_test_tt_main
    ("mint" >::: [
       "case_mint_ts_writes_utc_milliseconds_and_the_random_hex_in_one_field" >:: case_mint_ts_writes_utc_milliseconds_and_the_random_hex_in_one_field;
       "case_mint_ts_writes_000_on_the_second_and_clamps_the_last_half_millisecond_to_999" >:: case_mint_ts_writes_000_on_the_second_and_clamps_the_last_half_millisecond_to_999;
       "case_readers_parse_both_the_old_and_the_new_run_id_shapes" >:: case_readers_parse_both_the_old_and_the_new_run_id_shapes;
       "case_a_thousand_mints_under_a_frozen_clock_are_all_distinct_and_never_sleep" >:: case_a_thousand_mints_under_a_frozen_clock_are_all_distinct_and_never_sleep;
       "case_mint_unique_gives_up_after_its_tries_without_sleeping" >:: case_mint_unique_gives_up_after_its_tries_without_sleeping;
       "char_a_model_name_with_two_dots_mints_an_id_valid_run_id_refuses" >:: char_a_model_name_with_two_dots_mints_an_id_valid_run_id_refuses;
       QCheck_ounit.to_ounit2_test law_minted_ids_parse_back_to_their_edge_and_cycle;
       QCheck_ounit.to_ounit2_test law_mint_ts_sorts_like_time;
     ])
