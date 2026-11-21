(* Metric collectors (metric-collectors): the registry, sample checks,
   dedupe, grade spans, and the Claude Code transcript reader. Pure:
   transcripts are built here as synthetic lines, never real prompts.
   pending_<node>_ tests are the spec of work not built yet: each is an
   OUnit skip naming its node (a todo would fail the run), and that
   node is done when its pending tests are real tests that pass. The
   sink's git writes and the CLI are the fixture tier (test/metrics.sh). *)
open OUnit2

let sample ?(metric = "grade.wall_s") ?(node = "node-a") ?(cycle = 1) ?(run = "claude:s1/a1")
    ?(model = "claude-opus-5-5") ?(value = 1.) ?(at = "2026-11-21T20:53:27.705Z")
    ?(source = "grade-transcripts") () =
  { Metrics.metric; quest = "q"; node; cycle; run; model; value; at; source }

let code = function Ok () -> "ok" | Error (c, _) -> c

(* ---------- registry and validate ---------- *)

let case_registry_names_each_metric_once_with_a_known_owner _ =
  let names = List.map (fun (r : Metrics.row) -> r.name) Metrics.registry in
  assert_equal ~printer:string_of_int (List.length names) (List.length (List.sort_uniq compare names));
  List.iter (fun (r : Metrics.row) ->
      assert_bool (r.name ^ " has an unknown owner") (List.memq r.owner Metrics.collectors)) Metrics.registry;
  List.iter (fun m -> assert_bool m (Metrics.find m <> None))
    [ "grade.wall_s"; "grade.tool_calls"; "grade.context_end"; "grade.tokens_cache_read";
      "author.tool_calls"; "author.tokens_cache_write"; "cycle.todo_s"; "cycle.handed_off_s" ]

let case_validate_refuses_each_bad_sample_with_its_code _ =
  List.iter (fun (label, s, want) -> assert_equal ~msg:label ~printer:Fun.id want (code (Metrics.validate s)))
    [ ("clean", sample (), "ok");
      ("unknown metric", sample ~metric:"grade.nope" (), "E_METRIC_UNKNOWN");
      ("derived metric", sample ~metric:"cycle.todo_s" ~source:"node-cost" (), "E_METRIC_DERIVED");
      ("second owner", sample ~source:"author-window" (), "E_METRIC_OWNER");
      ("negative", sample ~value:(-1.) (), "E_METRIC_VALUE");
      ("nan", sample ~value:Float.nan (), "E_METRIC_VALUE");
      ("cycle 0", sample ~cycle:0 (), "E_METRIC_VALUE");
      ("text in model", sample ~model:"claude opus; rm" (), "E_METRIC_VALUE");
      ("text in run", sample ~run:"claude:s1/a1 please" (), "E_METRIC_VALUE");
      ("bad at", sample ~at:"yesterday" (), "E_METRIC_VALUE");
      ("whole-second at", sample ~at:"2026-11-21T20:53:27Z" (), "ok") ]

(* ---------- dedupe and the sink text ---------- *)

let case_dedupe_writes_a_repeated_sample_once _ =
  let a = sample () and b = sample ~metric:"grade.tool_calls" () in
  let fresh, skipped = Metrics.dedupe ~existing:[] [ a; b; a ] in
  assert_equal ~printer:string_of_int 2 (List.length fresh);
  assert_equal ~printer:string_of_int 1 skipped;
  let fresh, skipped = Metrics.dedupe ~existing:[ a ] [ a; b ] in
  assert_equal [ b ] fresh; assert_equal 1 skipped

let gen_sample =
  let open QCheck2.Gen in
  let id = string_size ~gen:(oneof [ char_range 'a' 'z'; char_range '0' '9' ]) (int_range 1 8) in
  map (fun (m, n, c, r, v) -> sample ~metric:m ~node:("node-" ^ n) ~cycle:c ~run:("claude:" ^ r) ~value:v ())
    (tup5 (oneof_list [ "grade.wall_s"; "grade.tool_calls"; "grade.tokens_out" ]) id (int_range 1 5) id
       (map float_of_int (int_range 0 1_000_000)))

let law_appending_any_batch_twice_writes_it_once =
  QCheck2.Test.make ~count:300 ~name:"law_appending_any_batch_twice_writes_it_once"
    (QCheck2.Gen.list_size (QCheck2.Gen.int_range 0 20) gen_sample)
    (fun batch ->
      let first, _ = Metrics.dedupe ~existing:[] batch in
      let again, skipped = Metrics.dedupe ~existing:first batch in
      again = [] && skipped = List.length batch)

let law_sink_text_round_trips =
  QCheck2.Test.make ~count:300 ~name:"law_sink_text_round_trips"
    (QCheck2.Gen.list_size (QCheck2.Gen.int_range 0 20) gen_sample)
    (fun batch -> Metrics.of_text (Metrics.to_text batch) = batch)

(* ---------- grade spans from ledger edges ---------- *)

(* rules.4's real shape (constraints-context, 2026-11-20..21): each
   needs_fix grade line carries the next cycle's number. *)
let rules4 = Gen.text [
    Gen.edge ~ts:"2026-11-20T22:02:00Z" "create" "" "todo";
    Gen.edge ~ts:"2026-11-20T23:13:58Z" ~commit:"0ccf25d" "handoff" "todo" "handed_off";
    Gen.edge ~ts:"2026-11-20T23:25:00Z" ~cycle:2 ~verdict:"needs_fix" "grade" "handed_off" "todo";
    Gen.edge ~ts:"2026-11-20T23:30:04Z" ~cycle:2 ~commit:"61420a4" "handoff" "todo" "handed_off";
    Gen.edge ~ts:"2026-11-20T23:38:51Z" ~cycle:3 ~verdict:"needs_fix" "grade" "handed_off" "todo";
    Gen.edge ~ts:"2026-11-20T23:51:25Z" ~cycle:3 ~commit:"cc58737" "handoff" "todo" "handed_off";
    Gen.edge ~ts:"2026-11-21T00:01:26Z" ~cycle:3 ~verdict:"needs_fix" "grade" "handed_off" "blocked";
    Gen.edge ~ts:"2026-11-21T20:52:01Z" ~cycle:4 "resume" "blocked" "todo";
    Gen.edge ~ts:"2026-11-21T20:52:09Z" ~cycle:4 ~commit:"d194196" "handoff" "todo" "handed_off";
    Gen.edge ~ts:"2026-11-21T21:14:59Z" ~cycle:4 ~verdict:"ship" "grade" "handed_off" "approved";
    Gen.edge ~ts:"2026-11-21T21:15:03Z" ~cycle:4 "land" "approved" "landed" ]

let case_grade_spans_take_the_cycle_from_the_handoff_not_the_grade_line _ =
  let spans = Metrics.grade_spans (Metrics.edges_of_text rules4) in
  assert_equal ~printer:(fun l -> String.concat "," (List.map string_of_int l))
    [ 1; 2; 3; 4 ] (List.map (fun (s : Metrics.grade_span) -> s.g_cycle) spans);
  assert_equal [ "0ccf25d"; "61420a4"; "cc58737"; "d194196" ]
    (List.map (fun (s : Metrics.grade_span) -> s.g_commit) spans);
  let last = List.nth spans 3 in
  assert_equal ("2026-11-21T20:52:09Z", "2026-11-21T21:14:59Z") (last.handed_at, last.graded_at)

(* ---------- the transcript reader ---------- *)

let jline fields = Yojson.Safe.to_string (`Assoc fields)
let user ?(ts = "2026-11-21T20:53:27.705Z") text =
  jline [ ("type", `String "user"); ("timestamp", `String ts); ("sessionId", `String "s1"); ("agentId", `String "a1");
          ("message", `Assoc [ ("role", `String "user"); ("content", `String text) ]) ]
let assistant ?(model = "claude-opus-5-5") ?(tools = []) ~ts ~id (i, o, cr, cw) =
  jline [ ("type", `String "assistant"); ("timestamp", `String ts); ("isSidechain", `Bool true);
          ("message", `Assoc [ ("id", `String id); ("model", `String model);
                               ("content", `List (List.map (fun t -> `Assoc [ ("type", `String "tool_use"); ("id", `String t) ]) tools));
                               ("usage", `Assoc [ ("input_tokens", `Int i); ("output_tokens", `Int o);
                                                  ("cache_read_input_tokens", `Int cr);
                                                  ("cache_creation_input_tokens", `Int cw) ]) ]) ]

(* m1 streams over three lines that repeat its usage, output growing;
   m2 is one line; a synthetic message and two junk lines ride along. *)
let tx_text = Gen.text [
    user "Grade node-rules-4-lint-hardening at d19419614da69469e0ff65abc921b2406742e2c1.";
    assistant ~ts:"2026-11-21T20:53:31.726Z" ~id:"m1" ~tools:[ "t1" ] (2, 100, 0, 35843);
    assistant ~ts:"2026-11-21T20:53:32.512Z" ~id:"m1" ~tools:[ "t1"; "t2" ] (2, 328, 0, 35843);
    assistant ~ts:"2026-11-21T20:53:33.000Z" ~id:"m1" ~tools:[ "t2" ] (2, 328, 0, 35843);
    "not json";
    jline [ ("type", `String "assistant"); ("timestamp", `String "2026-11-21T20:53:34.000Z"); ("message", `Assoc []) ];
    assistant ~ts:"2026-11-21T21:14:40.000Z" ~id:"m2" ~tools:[ "t3" ] (1, 50, 35843, 120);
    assistant ~model:"<synthetic>" ~ts:"2026-11-21T21:14:47.995Z" ~id:"m3" (0, 0, 0, 0) ]

let case_parse_counts_each_message_once_and_keeps_its_last_snapshot _ =
  let tx = Claude_tx.parse tx_text in
  assert_equal ~printer:string_of_int 3 (List.length tx.msgs);
  assert_equal ~printer:string_of_int 328 (List.hd tx.msgs).usage.output;
  assert_equal [ "t1"; "t2"; "t3" ] tx.tool_use_ids;
  assert_equal ~printer:string_of_int 2 tx.skipped_lines;
  assert_equal ("s1", "a1") (tx.session, tx.agent);
  assert_equal ("2026-11-21T20:53:27.705Z", "2026-11-21T21:14:47.995Z") (tx.first_ts, tx.last_ts)

let case_cost_sums_fields_separately_and_ignores_synthetic_models _ =
  let c = Claude_tx.cost (Claude_tx.parse tx_text) in
  assert_equal ~printer:string_of_float 1280.29 c.wall_s;
  assert_equal ~printer:string_of_int 3 c.tool_calls;
  assert_equal ~printer:string_of_int (2 + 1 + 0) c.tokens_in;
  assert_equal ~printer:string_of_int (328 + 50) c.tokens_out;
  assert_equal ~printer:string_of_int 35843 c.tokens_cache_read;
  assert_equal ~printer:string_of_int (35843 + 120) c.tokens_cache_write;
  assert_equal ~printer:string_of_int (1 + 35843 + 120 + 50) c.context_end;   (* m2: the synthetic m3 is skipped *)
  assert_equal ~printer:Fun.id "claude-opus-5-5" c.model

let case_seconds_reads_milliseconds_and_whole_seconds _ =
  let s ts = match Claude_tx.seconds ts with Some f -> Printf.sprintf "%.3f" f | None -> "None" in
  assert_equal ~printer:Fun.id "1795294407.705" (s "2026-11-21T20:53:27.705Z");
  assert_equal ~printer:Fun.id "1795294407.000" (s "2026-11-21T20:53:27Z");
  assert_equal ~printer:Fun.id "None" (s "2026-11-21 20:53:27");
  assert_equal ~printer:Fun.id "None" (s "")

let case_a_grade_transcript_names_its_node_and_commit_inside_the_window _ =
  let tx = Claude_tx.parse tx_text in
  let node = "node-rules-4-lint-hardening" and commit = "d19419614da69469e0ff65abc921b2406742e2c1" in
  assert_bool "names it" (Claude_tx.names_grade tx ~node ~commit);
  assert_bool "other node" (not (Claude_tx.names_grade tx ~node:"node-rules-2-constraints-lint" ~commit));
  assert_bool "other commit" (not (Claude_tx.names_grade tx ~node ~commit:"cc58737c992ae02910da9fce81399b55ac958ad3"));
  assert_bool "short commit" (not (Claude_tx.names_grade tx ~node ~commit:"d19"));
  let w h g = Claude_tx.in_window tx ~handed_at:h ~graded_at:g in
  assert_bool "real window" (w "2026-11-21T20:52:09Z" "2026-11-21T21:14:59Z");
  assert_bool "grade stamped in the last line's second" (w "2026-11-21T20:52:09Z" "2026-11-21T21:14:47Z");
  assert_bool "starts before the handoff" (not (w "2026-11-21T20:53:28Z" "2026-11-21T21:14:59Z"));
  assert_bool "ends after the grade" (not (w "2026-11-21T20:52:09Z" "2026-11-21T21:14:46Z"))

let case_meta_names_the_parent_tool_call _ =
  assert_equal (Some "toolu_01") (Claude_tx.meta_tool_use_id {|{"agentType":"general-purpose","toolUseId":"toolu_01"}|});
  assert_equal None (Claude_tx.meta_tool_use_id {|{"agentType":"x"}|});
  assert_equal None (Claude_tx.meta_tool_use_id "not json")

let case_tally_buckets_add_up_to_the_grades _ =
  assert_bool "zero" (Metrics.buckets_add_up Metrics.zero);
  assert_bool "mixed" (Metrics.buckets_add_up { Metrics.zero with grades = 3; unchecked = 2; owner_graded = 1 });
  assert_bool "lost one" (not (Metrics.buckets_add_up { Metrics.zero with grades = 3; unchecked = 2 }))

(* ---------- the harness report (scrape.1) ---------- *)

(* ?task adds the <task-id> key; ~tool:"" leaves out <tool-use-id>,
   the shape of a resumed agent's later report *)
let notification ?(ts = "2026-11-21T21:14:48.003Z") ?(op = "enqueue") ?task id (st, tu, ms) =
  let key k v = if v = "" then "" else Printf.sprintf "<%s>%s</%s>\n" k v k in
  jline [ ("type", `String "queue-operation"); ("operation", `String op); ("timestamp", `String ts);
          ("content", `String (Printf.sprintf
             "<task-notification>\n%s%s<status>completed</status>\n<usage><subagent_tokens>%d</subagent_tokens><tool_uses>%d</tool_uses><duration_ms>%d</duration_ms></usage>\n</task-notification>"
             (key "task-id" (Option.value task ~default:"")) (key "tool-use-id" id) st tu ms)) ]

let case_reports_come_from_enqueue_lines_and_the_last_one_wins _ =
  let quoting = jline [ ("type", `String "assistant"); ("timestamp", `String "2026-11-21T22:00:00.000Z");
                        ("message", `Assoc [ ("id", `String "mx"); ("content", `String
                          "<tool-use-id>toolu_a</tool-use-id><usage><subagent_tokens>1</subagent_tokens><tool_uses>1</tool_uses><duration_ms>1</duration_ms></usage>") ]) ] in
  let text = Gen.text [
      notification "toolu_a" (173523, 52, 1280300);
      notification ~op:"remove" "toolu_b" (9, 9, 9);
      quoting;
      notification "toolu_c" (100, 1, 1000);
      notification ~ts:"2026-11-21T23:00:00.000Z" "toolu_c" (200, 2, 2000);
      "not json \"queue-operation\"" ] in
  let rs = Claude_tx.reports_of_text text in
  assert_equal ~printer:(String.concat ",") [ "toolu_a"; "toolu_c" ] (List.map fst rs);
  let a = List.assoc "toolu_a" rs and c = List.assoc "toolu_c" rs in
  assert_equal (52, 1280300, 173523, "2026-11-21T21:14:48.003Z")
    (a.r_tool_uses, a.r_duration_ms, a.r_subagent_tokens, a.r_at);
  assert_equal ~printer:string_of_int 2 c.r_tool_uses

(* The first stop reports under both keys; a resumed agent's later
   stop reports under its task id alone, and that later one wins. *)
let case_a_resumed_agents_later_report_wins_under_its_task_id _ =
  let rs = Claude_tx.reports_of_text (Gen.text [
      notification ~task:"a1" "toolu_a" (100, 3, 1000);
      notification ~ts:"2026-11-21T23:00:00.000Z" ~task:"a1" "" (150, 5, 9000) ]) in
  assert_equal ~printer:string_of_int 3 (List.assoc "toolu_a" rs).r_tool_uses;
  assert_equal ~printer:string_of_int 5 (List.assoc "a1" rs).r_tool_uses;
  assert_equal ~printer:Fun.id "2026-11-21T23:00:00.000Z" (List.assoc "a1" rs).r_at

let report ?(at = "2026-11-21T21:14:48.003Z") (st, tu, ms) =
  { Claude_tx.r_at = at; r_tool_uses = tu; r_duration_ms = ms; r_subagent_tokens = st }

let case_agrees_allows_a_small_context_undercount_and_nothing_else _ =
  let c = Claude_tx.cost (Claude_tx.parse tx_text) in   (* tools 3, wall 1280.29, context 36014 *)
  let ok label want r = assert_equal ~msg:label ~printer:string_of_bool want (Claude_tx.agrees c r) in
  ok "exact" true (report (36014, 3, 1280300));
  ok "final output logged short, under 1% (seen: at most 0.74%)" true (report (36014 + 360, 3, 1280300));
  ok "wall within a second" true (report (36014, 3, 1281200));
  ok "one tool call off" false (report (36014, 4, 1280300));
  ok "context over the report" false (report (36013, 3, 1280300));
  ok "context more than 1% short" false (report (36014 + 400, 3, 1280300));
  ok "wall off by 2 s" false (report (36014, 3, 1282300))

(* A renamed usage key must never read as 0 tokens and pass the check. *)
let case_a_usage_line_missing_a_count_is_skipped_and_fails_the_check _ =
  let renamed = jline [ ("type", `String "assistant"); ("timestamp", `String "2026-11-21T21:14:40.500Z");
                        ("message", `Assoc [ ("id", `String "m9"); ("model", `String "claude-opus-5-5");
                                             ("content", `List []);
                                             ("usage", `Assoc [ ("input_tokens", `Int 1); ("output_tokenz", `Int 9);
                                                                ("cache_read_input_tokens", `Int 0);
                                                                ("cache_creation_input_tokens", `Int 0) ]) ]) ] in
  let tx = Claude_tx.parse (tx_text ^ Gen.text [ renamed ]) in
  assert_equal ~printer:string_of_int 1 tx.bad_usage;
  assert_equal ~printer:string_of_int 3 tx.skipped_lines;
  assert_equal ~printer:string_of_int 3 (List.length tx.msgs);
  assert_bool "same cost, but it does not check" (not (Claude_tx.checks tx (report (36014, 3, 1280300))));
  assert_bool "the clean transcript checks" (Claude_tx.checks (Claude_tx.parse tx_text) (report (36014, 3, 1280300)))

(* A grader resumed by a follow-up writes after its report: the cut
   at r_at must reproduce the report, the full file keeps the rest. *)
let case_parse_until_cuts_the_transcript_at_the_report _ =
  let resumed = tx_text ^ Gen.text [
      assistant ~ts:"2026-11-21T21:20:00.000Z" ~id:"m4" ~tools:[ "t4" ] (1, 9, 36000, 10) ] in
  let full = Claude_tx.cost (Claude_tx.parse resumed) in
  let cut = Claude_tx.cost (Claude_tx.parse ?until:(Claude_tx.seconds "2026-11-21T21:14:48.003Z") resumed) in
  assert_equal ~printer:string_of_int 4 full.tool_calls;
  assert_equal ~printer:string_of_int 3 cut.tool_calls;
  assert_equal ~printer:string_of_float 1280.29 cut.wall_s;
  assert_bool "cut agrees with its report" (Claude_tx.agrees cut (report (36014, 3, 1280300)))

let case_an_off_shape_model_is_recorded_as_other _ =
  let text = Gen.text [ user "x"; assistant ~model:"sk-ant-api03-secret" ~ts:"2026-11-21T20:53:31.726Z" ~id:"m1" (1, 1, 1, 1) ] in
  assert_equal ~printer:Fun.id "other" (Claude_tx.cost (Claude_tx.parse text)).model;
  assert_equal ~printer:Fun.id "E_METRIC_VALUE" (code (Metrics.validate (sample ~model:"sk-ant-api03-secret" ())));
  assert_equal ~printer:Fun.id "ok" (code (Metrics.validate (sample ~model:"other" ())));
  (* Str's $ matches before a newline: nothing may ride after one *)
  List.iter (fun m ->
      assert_equal ~msg:(String.escaped m) ~printer:Fun.id "E_METRIC_VALUE" (code (Metrics.validate (sample ~model:m ())));
      let t = Gen.text [ user "x"; assistant ~model:m ~ts:"2026-11-21T20:53:31.726Z" ~id:"m1" (1, 1, 1, 1) ] in
      assert_equal ~msg:(String.escaped m) ~printer:Fun.id "other" (Claude_tx.cost (Claude_tx.parse t)).model)
    [ "other\nhunter2-secret"; "claude-a\nx"; "unknown\n" ];
  assert_equal ~printer:Fun.id "E_METRIC_VALUE" (code (Metrics.validate (sample ~at:"2026-11-21T20:53:27Z\nx" ())))

(* ---------- the spec still to build ---------- *)

let pending node what _ = skip_if true ("pending " ^ node ^ ": " ^ what)

let pending_tests = [
  "pending_scrape_2_finds_the_session_that_cast_the_handoff" >::
    pending "scrape.2" "a Bash tool_use naming handoff, the node and --commit <sha[:7+]>";
  "pending_scrape_2_windows_of_one_session_never_overlap" >::
    pending "scrape.2" "start = max(cycle entered todo, last edge on any other node before the handoff)";
  "pending_scrape_2_subagent_messages_stay_out_of_an_author_window" >::
    pending "scrape.2" "isSidechain messages and subagent files are never author spend";
  "pending_scrape_2_a_missing_session_is_author_missing_never_zero" >::
    pending "scrape.2" "author_missing and author_ambiguous buckets";
  "pending_derive_1_cycle_timing_splits_todo_and_handed_off" >::
    pending "derive.1" "rules.4 cycle 4: todo_s 8, handed_off_s 1370";
  "pending_derive_1_law_derive_ignores_sample_order" >::
    pending "derive.1" "derive xs = derive (shuffle xs)";
  "pending_derive_1_law_cycle_todo_sums_to_the_rollup_dwell" >::
    pending "derive.1" "sum of cycle.todo_s = bp3 q r timing.dwell_s.todo";
  "pending_derive_1_quest_rollup_reports_median_grade_wall" >::
    pending "derive.1" "median, min, max of grade.wall_s and spend by token field";
]

let () =
  run_test_tt_main
    ("metrics" >::: [
       "case_registry_names_each_metric_once_with_a_known_owner" >:: case_registry_names_each_metric_once_with_a_known_owner;
       "case_validate_refuses_each_bad_sample_with_its_code" >:: case_validate_refuses_each_bad_sample_with_its_code;
       "case_dedupe_writes_a_repeated_sample_once" >:: case_dedupe_writes_a_repeated_sample_once;
       "case_grade_spans_take_the_cycle_from_the_handoff_not_the_grade_line" >:: case_grade_spans_take_the_cycle_from_the_handoff_not_the_grade_line;
       "case_parse_counts_each_message_once_and_keeps_its_last_snapshot" >:: case_parse_counts_each_message_once_and_keeps_its_last_snapshot;
       "case_cost_sums_fields_separately_and_ignores_synthetic_models" >:: case_cost_sums_fields_separately_and_ignores_synthetic_models;
       "case_seconds_reads_milliseconds_and_whole_seconds" >:: case_seconds_reads_milliseconds_and_whole_seconds;
       "case_a_grade_transcript_names_its_node_and_commit_inside_the_window" >:: case_a_grade_transcript_names_its_node_and_commit_inside_the_window;
       "case_meta_names_the_parent_tool_call" >:: case_meta_names_the_parent_tool_call;
       "case_tally_buckets_add_up_to_the_grades" >:: case_tally_buckets_add_up_to_the_grades;
       "case_reports_come_from_enqueue_lines_and_the_last_one_wins" >:: case_reports_come_from_enqueue_lines_and_the_last_one_wins;
       "case_a_resumed_agents_later_report_wins_under_its_task_id" >:: case_a_resumed_agents_later_report_wins_under_its_task_id;
       "case_a_usage_line_missing_a_count_is_skipped_and_fails_the_check" >:: case_a_usage_line_missing_a_count_is_skipped_and_fails_the_check;
       "case_agrees_allows_a_small_context_undercount_and_nothing_else" >:: case_agrees_allows_a_small_context_undercount_and_nothing_else;
       "case_parse_until_cuts_the_transcript_at_the_report" >:: case_parse_until_cuts_the_transcript_at_the_report;
       "case_an_off_shape_model_is_recorded_as_other" >:: case_an_off_shape_model_is_recorded_as_other;
       QCheck_ounit.to_ounit2_test law_appending_any_batch_twice_writes_it_once;
       QCheck_ounit.to_ounit2_test law_sink_text_round_trips;
     ] @ pending_tests)
