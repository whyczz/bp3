(* Clock seam (test-pyramid unit.2): time decisions with literal
   times, effectful readers under a pinned clock. No sleeps.
   case_ = named example or boundary, law_ = QCheck property.
   Runner: ounit2's default (processes). Each test that pins the
   clock does so through with_fixed, which restores the source even
   on failure, so no test depends on another's clock. *)
open OUnit2

let stale_at age =
  Clock.stale ~now:1_000_000. ~last_seen:(1_000_000. -. age)
    ~stale_after_s:Hooks.stale_after_s

let case_stale_gate_keeps_a_binding_seen_899_seconds_ago _ =
  assert_bool "899s is not stale" (not (stale_at 899.))

let case_stale_gate_keeps_a_binding_seen_exactly_900_seconds_ago _ =
  assert_bool "900s is not stale (strictly more than 900 is)" (not (stale_at 900.))

let case_stale_gate_sweeps_a_binding_seen_901_seconds_ago _ =
  assert_bool "901s is stale" (stale_at 901.)

let case_silence_is_fresh_at_exactly_the_window_and_silent_just_past_it _ =
  assert_bool "1.0s inside a 1s window is fresh"
    (not (Clock.silent ~now:10. ~last:9. ~silence_s:1.));
  assert_bool "1.5s past a 1s window is silent"
    (Clock.silent ~now:10.5 ~last:9. ~silence_s:1.)

let case_a_deadline_is_reached_at_the_deadline_itself _ =
  assert_bool "one tick before" (not (Clock.past_deadline ~now:99.9 ~deadline:100.));
  assert_bool "at the deadline" (Clock.past_deadline ~now:100. ~deadline:100.);
  assert_bool "an hour past it" (Clock.past_deadline ~now:3700. ~deadline:100.)

let case_silence_uses_its_window_and_never_counts_a_future_mtime_as_silent _ =
  assert_bool "600s inside a 600s window is fresh" (not (Clock.silent ~now:1000. ~last:400. ~silence_s:600.));
  assert_bool "601s past a 600s window is silent" (Clock.silent ~now:1000. ~last:399. ~silence_s:600.);
  assert_bool "a day past is silent" (Clock.silent ~now:100_000. ~last:0. ~silence_s:600.);
  assert_bool "an mtime an hour ahead is fresh" (not (Clock.silent ~now:1000. ~last:4600. ~silence_s:600.))

let case_compact_ts_formats_epoch_1795000000_as_20261118T110640Z _ =
  assert_equal ~printer:Fun.id "20261118T110640Z"
    (Clock.with_fixed 1_795_000_000. Harness.compact_ts)

let case_now_ts_formats_epoch_1795000000_as_2026_11_18T11_06_40Z _ =
  assert_equal ~printer:Fun.id "2026-11-18T11:06:40Z"
    (Clock.with_fixed 1_795_000_000. Gitx.now_ts)

let case_time_truncates_a_sub_second_clock_to_whole_seconds_like_unix_time _ =
  Clock.with_fixed 1_795_000_000.987 (fun () ->
    assert_equal ~printer:string_of_float 1_795_000_000. (Clock.time ());
    assert_equal ~printer:string_of_float 1_795_000_000.987 (Clock.now ()))

let case_stale_gate_still_sweeps_a_binding_seen_a_year_ago _ =
  assert_bool "a year past the threshold is stale" (stale_at 31_536_000.)

let case_stale_gate_keeps_a_binding_whose_last_seen_is_in_the_future _ =
  assert_bool "clock skew: seen an hour ahead is not stale" (not (stale_at (-3600.)))

let case_with_fixed_restores_the_previous_clock_even_when_the_body_raises _ =
  let before = !Clock.source in
  (try Clock.with_fixed 5. (fun () -> failwith "boom") with Failure _ -> ());
  assert_bool "source restored" (!Clock.source == before)

(* Once stale, a binding stays stale as time moves forward. The
   generator puts [now] near the threshold (within 5s) or far from it
   on either side, and moves [later] a little or a lot, so cases land
   on both sides of the threshold and cross it. *)
let law_stale_never_reverts_as_now_grows =
  QCheck2.Test.make ~count:500 ~name:"law_stale_never_reverts_as_now_grows"
    ~print:(fun (l, a, o, d) -> Printf.sprintf "last_seen=%g after=%g now=last_seen+after%+g later=+%g" l a o d)
    QCheck2.Gen.(quad (float_range 0. 1e9) (float_range 1. 2000.)
                   (oneof [ float_range (-5.) 5.;
                            (* log-uniform on both sides: 0.1s to 1e7s *)
                            map2 (fun neg u -> (if neg then -1. else 1.) *. (10. ** u)) bool (float_range (-1.) 7.) ])
                   (oneof [ float_range 0. 10.; map (fun u -> 10. ** u) (float_range (-1.) 7.) ]))
    (fun (last_seen, stale_after_s, offset, later) ->
      let now = last_seen +. stale_after_s +. offset in
      (not (Clock.stale ~now ~last_seen ~stale_after_s))
      || Clock.stale ~now:(now +. later) ~last_seen ~stale_after_s)

let () =
  run_test_tt_main
    ("clock" >::: [
       "case_stale_gate_keeps_a_binding_seen_899_seconds_ago" >:: case_stale_gate_keeps_a_binding_seen_899_seconds_ago;
       "case_stale_gate_keeps_a_binding_seen_exactly_900_seconds_ago" >:: case_stale_gate_keeps_a_binding_seen_exactly_900_seconds_ago;
       "case_stale_gate_sweeps_a_binding_seen_901_seconds_ago" >:: case_stale_gate_sweeps_a_binding_seen_901_seconds_ago;
       "case_silence_is_fresh_at_exactly_the_window_and_silent_just_past_it" >:: case_silence_is_fresh_at_exactly_the_window_and_silent_just_past_it;
       "case_a_deadline_is_reached_at_the_deadline_itself" >:: case_a_deadline_is_reached_at_the_deadline_itself;
       "case_silence_uses_its_window_and_never_counts_a_future_mtime_as_silent" >:: case_silence_uses_its_window_and_never_counts_a_future_mtime_as_silent;
       "case_compact_ts_formats_epoch_1795000000_as_20261118T110640Z" >:: case_compact_ts_formats_epoch_1795000000_as_20261118T110640Z;
       "case_now_ts_formats_epoch_1795000000_as_2026_11_18T11_06_40Z" >:: case_now_ts_formats_epoch_1795000000_as_2026_11_18T11_06_40Z;
       "case_time_truncates_a_sub_second_clock_to_whole_seconds_like_unix_time" >:: case_time_truncates_a_sub_second_clock_to_whole_seconds_like_unix_time;
       "case_stale_gate_still_sweeps_a_binding_seen_a_year_ago" >:: case_stale_gate_still_sweeps_a_binding_seen_a_year_ago;
       "case_stale_gate_keeps_a_binding_whose_last_seen_is_in_the_future" >:: case_stale_gate_keeps_a_binding_whose_last_seen_is_in_the_future;
       "case_with_fixed_restores_the_previous_clock_even_when_the_body_raises" >:: case_with_fixed_restores_the_previous_clock_even_when_the_body_raises;
       QCheck_ounit.to_ounit2_test law_stale_never_reverts_as_now_grows;
     ])
