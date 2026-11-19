(* Run-id mint (test-pyramid seam.1): the first field carries UTC to
   the millisecond plus 4 hex, a collision draws again with no sleep,
   and every reader of run-ids still parses the new shape. The real
   mint path (Harness.mint_run_id, which do_link_mint calls) runs here
   against an in-memory writer that raises EEXIST like write_minted's
   O_EXCL; the file write itself is link.sh's. No wall clock: time is
   pinned with Clock.with_fixed. "Never sleeps" is timed only in
   link.sh's burst, where load can't fail a unit test.
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
      ("20261118T120000Z-grade-muse-code-opus-c1", ("grade", 1));
      ("20261118T110640.123a7f3Z-handoff-pi-none-c2", ("handoff", 2));
      ("20261118T110640.000beefZ-grade-muse-code-claude-opus-5-5-c3", ("grade", 3)) ]

(* An in-memory run store: write raises EEXIST on a taken id, like
   write_minted's O_EXCL open. *)
let store () =
  let taken = Hashtbl.create 1024 in
  let write c =
    if Hashtbl.mem taken c then raise (Unix.Unix_error (Unix.EEXIST, "open", c))
    else Hashtbl.add taken c () in
  (taken, write)

let mint write = Harness.mint_run_id ~write ~edge_label:"handoff" ~harness:"pi" ~model:"m" ~cycle:1 ()

let case_a_thousand_mints_at_one_frozen_instant_are_distinct_and_carry_its_millisecond _ =
  let (taken, write) = store () in
  let ids = Clock.with_fixed 1_795_000_000.5 (fun () -> List.init 1000 (fun _ -> mint write)) in
  assert_equal ~printer:string_of_int 1000 (Hashtbl.length taken);
  List.iter (fun rid ->
      assert_equal ~msg:rid ~printer:Fun.id "20261118T110640.500" (String.sub rid 0 19);
      assert_equal ~msg:rid ("handoff", 1) (Hooks.parse_edge_cycle rid)) ids

let case_mint_run_id_gives_up_with_E_EXISTS_naming_the_last_candidate_after_eight_draws _ =
  let draws = ref [] in
  let write c = draws := c :: !draws; raise (Unix.Unix_error (Unix.EEXIST, "open", c)) in
  match Clock.with_fixed 1_795_000_000. (fun () -> mint write) with
  | _ -> assert_failure "a fully colliding store minted an id"
  | exception Gitx.Verdict (_, j) ->
      let open Yojson.Safe.Util in
      assert_equal ~printer:Fun.id "E_EXISTS" (j |> member "error" |> member "code" |> to_string);
      assert_equal ~printer:string_of_int 8 (List.length !draws);
      assert_equal ~printer:Fun.id (List.hd !draws) (j |> member "error" |> member "facts" |> member "run_id" |> to_string)

let case_the_random_hex_fallback_gives_four_lowercase_hex_digits _ =
  for _ = 1 to 50 do
    let h = Harness.random_hex4_fallback () in
    assert_bool h (String.length h = 4 && String.for_all (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) h)
  done

let case_mint_unique_gives_up_after_its_tries_without_sleeping _ =
  let draws = ref 0 in
  let r = Harness.mint_unique ~tries:3 ~candidate:(fun () -> incr draws; "same") ~claim:(fun _ -> false) in
  assert_equal None r;
  assert_equal ~printer:string_of_int 3 !draws

let char_a_model_name_with_two_dots_mints_an_id_valid_run_id_refuses _ =
  let rid = id ~ts:"20261118T110640.123a7f3Z" ~edge:"handoff" ~harness:"pi" ~model:"x..y" ~cycle:1 in
  assert_bool "slug_keep keeps dots, valid_run_id refuses '..'" (not (Worktree.valid_run_id rid))

(* Under any frozen instant, the real mint path gives distinct ids
   stamped with that instant to the millisecond. *)
let law_minted_ids_are_unique_under_a_frozen_clock =
  QCheck2.Test.make ~count:50 ~name:"law_minted_ids_are_unique_under_a_frozen_clock"
    ~print:string_of_float QCheck2.Gen.(float_range 0. 4.0e9)
    (fun t ->
      let (taken, write) = store () in
      let stamp = String.sub (Harness.mint_ts_of t "0000") 0 19 in
      let ids = Clock.with_fixed t (fun () -> List.init 200 (fun _ -> mint write)) in
      Hashtbl.length taken = 200 && List.for_all (fun rid -> String.sub rid 0 19 = stamp) ids)

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
       "case_a_thousand_mints_at_one_frozen_instant_are_distinct_and_carry_its_millisecond" >:: case_a_thousand_mints_at_one_frozen_instant_are_distinct_and_carry_its_millisecond;
       "case_mint_run_id_gives_up_with_E_EXISTS_naming_the_last_candidate_after_eight_draws" >:: case_mint_run_id_gives_up_with_E_EXISTS_naming_the_last_candidate_after_eight_draws;
       "case_the_random_hex_fallback_gives_four_lowercase_hex_digits" >:: case_the_random_hex_fallback_gives_four_lowercase_hex_digits;
       QCheck_ounit.to_ounit2_test law_minted_ids_are_unique_under_a_frozen_clock;
       "case_mint_unique_gives_up_after_its_tries_without_sleeping" >:: case_mint_unique_gives_up_after_its_tries_without_sleeping;
       "char_a_model_name_with_two_dots_mints_an_id_valid_run_id_refuses" >:: char_a_model_name_with_two_dots_mints_an_id_valid_run_id_refuses;
       QCheck_ounit.to_ounit2_test law_minted_ids_parse_back_to_their_edge_and_cycle;
       QCheck_ounit.to_ounit2_test law_mint_ts_sorts_like_time;
     ])
