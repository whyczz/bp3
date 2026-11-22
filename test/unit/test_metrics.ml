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
  assert_bool "lost one" (not (Metrics.buckets_add_up { Metrics.zero with grades = 3; unchecked = 2 }));
  assert_bool "bad usage is a handoff bucket"
    (Metrics.buckets_add_up { Metrics.zero with handoffs = 2; authored = 1; author_bad_usage = 1 });
  assert_bool "lost a handoff" (not (Metrics.buckets_add_up { Metrics.zero with handoffs = 2; authored = 1 }));
  assert_bool "a self-checked pi grade is a grade bucket"
    (Metrics.buckets_add_up { Metrics.zero with grades = 2; checked = 1; self_checked = 1 });
  assert_equal ~printer:string_of_int 1
    (match Metrics.tally_json { Metrics.zero with self_checked = 1 } with
     | `Assoc fs -> (match List.assoc_opt "self_checked" fs with Some (`Int n) -> n | _ -> -1) | _ -> -1)

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

(* ---------- author windows (scrape.2) ---------- *)

(* Two nodes worked one at a time: b was created with a, so b's first
   window must start at a's land, not at b's create; a's cycle 2 window
   starts at the grade, not at the owner's resume after the block. *)
let two_nodes = [
  ("a", Gen.edge ~ts:"2026-11-21T10:00:00Z" "create" "" "todo");
  ("b", Gen.edge ~ts:"2026-11-21T10:00:01Z" ~deps:[ "a" ] "create" "" "todo");
  ("a", Gen.edge ~ts:"2026-11-21T11:00:00Z" ~commit:"aaaaaaa1" "handoff" "todo" "handed_off");
  ("a", Gen.edge ~ts:"2026-11-21T11:10:00Z" ~cycle:2 ~verdict:"needs_fix" "grade" "handed_off" "blocked");
  ("a", Gen.edge ~ts:"2026-11-21T12:00:00Z" ~cycle:2 "resume" "blocked" "todo");
  ("a", Gen.edge ~ts:"2026-11-21T12:00:30Z" ~cycle:2 ~commit:"aaaaaaa2" "handoff" "todo" "handed_off");
  ("a", Gen.edge ~ts:"2026-11-21T12:10:00Z" ~cycle:2 ~verdict:"ship" "grade" "handed_off" "approved");
  ("a", Gen.edge ~ts:"2026-11-21T12:10:05Z" ~cycle:2 "land" "approved" "landed");
  ("b", Gen.edge ~ts:"2026-11-21T13:00:00Z" ~commit:"bbbbbbb1" "handoff" "todo" "handed_off") ]
  |> List.map (fun (n, l) -> (n, List.hd (Metrics.edges_of_text l)))

let case_author_spans_start_at_the_previous_quest_edge_but_never_a_resume _ =
  let span n = List.map (fun (s : Metrics.author_span) -> (s.a_cycle, s.a_from, s.a_upto)) (Metrics.author_spans ~node:n two_nodes) in
  let p = function (c, f, u) -> Printf.sprintf "(%d %s %s)" c f u in
  assert_equal ~printer:(fun l -> String.concat " " (List.map p l))
    [ (1, "2026-11-21T10:00:01Z", "2026-11-21T11:00:00Z"); (2, "2026-11-21T11:10:00Z", "2026-11-21T12:00:30Z") ] (span "a");
  assert_equal ~printer:(fun l -> String.concat " " (List.map p l))
    [ (1, "2026-11-21T12:10:05Z", "2026-11-21T13:00:00Z") ] (span "b")

let session_line ?(side = false) ?(tools = []) ~ts ~id (i, o, cr, cw) =
  jline [ ("type", `String "assistant"); ("timestamp", `String ts); ("isSidechain", `Bool side);
          ("sessionId", `String "main1");
          ("message", `Assoc [ ("id", `String id); ("model", `String "claude-opus-5-5");
                               ("content", `List (List.map (fun (tid, cmd) ->
                                    `Assoc [ ("type", `String "tool_use"); ("id", `String tid); ("name", `String "Bash");
                                             ("input", `Assoc [ ("command", `String cmd) ]) ]) tools));
                               ("usage", `Assoc [ ("input_tokens", `Int i); ("output_tokens", `Int o);
                                                  ("cache_read_input_tokens", `Int cr);
                                                  ("cache_creation_input_tokens", `Int cw) ]) ]) ]
let tool_result ~ts tid text =
  jline [ ("type", `String "user"); ("timestamp", `String ts);
          ("message", `Assoc [ ("content", `List [ `Assoc [ ("type", `String "tool_result"); ("tool_use_id", `String tid);
                                                             ("content", `String text) ] ]) ]) ]

let sha = "bbbbbbb1c0ffee00000000000000000000000000"
let main_session = Gen.text [
    session_line ~ts:"2026-11-21T12:30:00.000Z" ~id:"w1" ~tools:[ ("t1", "make check") ] (2, 10, 100, 5);
    session_line ~ts:"2026-11-21T12:30:01.000Z" ~id:"w1" ~tools:[ ("t1", "make check") ] (2, 40, 100, 5);
    session_line ~side:true ~ts:"2026-11-21T12:31:00.000Z" ~id:"sub" (9, 9999, 9999, 9);
    session_line ~ts:"2026-11-21T12:59:59.000Z" ~id:"w2"
      ~tools:[ ("t2", "./bin/bp3 q quest1 u b handoff --commit \"$(git rev-parse HEAD)\" --reason x") ] (1, 5, 200, 0);
    tool_result ~ts:"2026-11-21T13:00:00.200Z" "t2" ("{\"ok\":true,\"state\":\"handed_off\",\"commit\":\"" ^ sha ^ "\"}");
    tool_result ~ts:"2026-11-21T13:00:00.300Z" "t1" "check ok" ]

let case_parse_session_keeps_the_main_thread_and_handoff_results _ =
  let s = Claude_tx.parse_session main_session in
  assert_equal ~printer:Fun.id "main1" s.s_id;
  assert_equal [ "w1"; "w2" ] (List.map (fun (m : Claude_tx.msg) -> m.id) s.s_msgs);
  assert_equal ~printer:string_of_int 40 (List.hd s.s_msgs).usage.output;
  assert_equal [ "t1"; "t2" ] (List.map fst s.s_tools);
  assert_equal [ "t2" ] (List.map fst s.s_results)

(* b's window (two_nodes): from a's land to b's handoff *)
let b_from = Option.get (Claude_tx.seconds "2026-11-21T12:10:05Z")
let b_upto = Option.get (Claude_tx.seconds "2026-11-21T13:00:00Z")

let case_casts_handoff_by_the_result_commit_or_a_command_prefix_inside_the_window _ =
  let s = Claude_tx.parse_session main_session in
  let casts ?(from = b_from) ?(upto = b_upto) s node commit =
    Claude_tx.casts_handoff s ~quest:"quest1" ~node ~commit ~from ~upto in
  assert_bool "result holds the full commit" (casts s "b" sha);
  assert_bool "another node" (not (casts s "a" sha));
  assert_bool "another commit" (not (casts s "b" "cccccccccccccccc"));
  assert_bool "the call ran before the window" (not (casts ~from:(b_upto +. 10.) ~upto:(b_upto +. 100.) s "b" sha));
  let literal = Claude_tx.parse_session (Gen.text [
      session_line ~ts:"2026-11-21T12:59:59.000Z" ~id:"w9" ~tools:[ ("t9", "bp3 q quest1 u b handoff --commit bbbbbbb1") ] (1, 1, 1, 1) ]) in
  assert_bool "command names the commit" (casts literal "b" sha);
  (* measure.1 cycle 2: the node may be a variable the same command sets, as the quest may *)
  let var cmd = Claude_tx.parse_session (Gen.text [
      session_line ~ts:"2026-11-21T12:59:59.000Z" ~id:"w7" ~tools:[ ("t7", cmd) ] (1, 1, 1, 1) ]) in
  assert_bool "n $N set to b" (casts (var "Q=quest1; N=b; bp3 q $Q n $N e handoff --commit bbbbbbb1") "b" sha);
  assert_bool "n \"${N}\" set to b" (casts (var "N=b; bp3 q quest1 n \"${N}\" e handoff --commit bbbbbbb1") "b" sha);
  assert_bool "u $N set to b" (casts (var "N=b; bp3 q quest1 u $N handoff --commit bbbbbbb1") "b" sha);
  assert_bool "N set to another node" (not (casts (var "N=a; bp3 q quest1 n $N e handoff --commit bbbbbbb1") "b" sha));
  assert_bool "N never set" (not (casts (var "bp3 q quest1 n $N e handoff --commit bbbbbbb1") "b" sha));
  (* grader probe (round 1): a later read that greps the same words *)
  let later = Claude_tx.parse_session (Gen.text [
      session_line ~ts:"2026-11-21T14:00:00.000Z" ~id:"r1" ~tools:[ ("r1t", "./bin/bp3 q quest1 n b r | grep handoff") ] (1, 1, 1, 1);
      tool_result ~ts:"2026-11-21T14:00:01.000Z" "r1t" ("{\"edge\":\"handoff\",\"to\":\"handed_off\",\"commit\":\"" ^ sha ^ "\"}") ]) in
  assert_bool "a later read is not the cast" (not (casts later "b" sha));
  (* test-pyramid tier.2: --commit "$SHA" and a result cut to {ok, state} *)
  let cut ok_text = Claude_tx.parse_session (Gen.text [
      session_line ~ts:"2026-11-21T12:59:59.000Z" ~id:"w8" ~tools:[ ("t8", "bp3 q quest1 u b handoff --commit \"$SHA\" | jq -c '{ok, state}'") ] (1, 1, 1, 1);
      tool_result ~ts:"2026-11-21T13:00:00.200Z" "t8" ok_text ]) in
  assert_bool "a successful move, commit cut away" (casts (cut "{\"ok\":true,\"state\":\"handed_off\"}") "b" sha);
  assert_bool "a refusal that names handed_off" (not (casts (cut "{\"ok\":false,\"error\":{\"facts\":{\"state\":\"handed_off\"}}}") "b" sha));
  (* grader probe (round 2): node ids repeat across quests *)
  let other cmd text = Claude_tx.parse_session (Gen.text [
      session_line ~ts:"2026-11-21T12:59:59.000Z" ~id:"w7" ~tools:[ ("t7", cmd) ] (1, 1, 1, 1);
      tool_result ~ts:"2026-11-21T13:00:00.200Z" "t7" text ]) in
  assert_bool "another quest's node with the same id"
    (not (casts (other "bp3 q other-quest n b e handoff --commit \"$SHA\" | jq -c '{ok, state}'"
                   "{\"ok\":true,\"state\":\"handed_off\"}") "b" sha));
  assert_bool "a result that shows another quest"
    (not (casts (other "bp3 q quest1 n b e handoff --commit \"$SHA\""
                   "{\"ok\":true,\"quest\":\"other-quest\",\"node\":\"b\",\"state\":\"handed_off\"}") "b" sha));
  (* test-pyramid tier.2 cycle 1: the result was cut two hex into the commit *)
  let head_c v = other "bp3 q quest1 n b e handoff --commit \"$SHA\" | head -c 120"
      ("{\"ok\":true,\"quest\":\"quest1\",\"node\":\"b\",\"state\":\"handed_off\",\"cycle\":1,\"commit\":\"" ^ v) in
  assert_bool "cut inside our commit" (casts (head_c "bb") "b" sha);
  (* test-pyramid unit.2 cycle 2: cut mid-commit, then the next output line *)
  assert_bool "cut, then another line" (casts (head_c "bbbbbbb1c0\nbbbbbbb") "b" sha);
  assert_bool "cut after one hex is too little" (not (casts (head_c "b") "b" sha));
  (* grader probe C (round 3): a sibling's cast names b in its reason *)
  assert_bool "a sibling's cast that names b"
    (not (casts (other "bp3 q quest1 n a e handoff --commit \"$C\" --reason 'unblocks b' | jq -c '{ok,state}'"
                   "{\"ok\":true,\"state\":\"handed_off\"}") "b" sha));
  (* grader probe F3: another quest's b cast, then a read of ours *)
  assert_bool "another quest's cast plus a read of ours"
    (not (casts (other "bp3 q other-quest n b e handoff --commit \"$S\" | jq -c '{ok,quest,node,state}'; bp3 q quest1 n b r | jq -c '{quest,node,state}'"
                   "{\"ok\":true,\"quest\":\"other-quest\",\"node\":\"b\",\"state\":\"handed_off\"}\n{\"quest\":\"quest1\",\"node\":\"b\",\"state\":\"handed_off\"}") "b" sha));
  (* real casts set the quest in a variable first *)
  assert_bool "Q=quest1 && bp3 q $Q n b e handoff"
    (casts (other "Q=quest1 && ./bin/bp3 q $Q n b e handoff --commit \"$SHA\" | jq -c '{ok, state}'"
              "{\"ok\":true,\"state\":\"handed_off\"}") "b" sha);
  assert_bool "a variable set to another quest"
    (not (casts (other "Q=other-quest && ./bin/bp3 q \"$Q\" n b e handoff | jq -c '{ok, state}'"
                   "{\"ok\":true,\"state\":\"handed_off\"}") "b" sha));
  assert_bool "cut inside another commit" (not (casts (head_c "cc") "b" sha))

(* A queue-operation line quoting "tool_result" and "handed_off" passes
   the cheap filter and has no message: it must read as nothing. *)
let case_a_line_without_a_message_never_stops_the_reader _ =
  let odd = jline [ ("type", `String "queue-operation"); ("operation", `String "enqueue");
                    ("timestamp", `String "2026-11-21T12:40:00.000Z");
                    ("content", `String "a tool_result said handed_off"); ("message", `Null) ] in
  let s = Claude_tx.parse_session (main_session ^ Gen.text [ odd; "[1,2]"; "{\"type\":\"assistant\",\"message\":[1]}" ]) in
  assert_equal [ "w1"; "w2" ] (List.map (fun (m : Claude_tx.msg) -> m.id) s.s_msgs);
  let tx = Claude_tx.parse (tx_text ^ Gen.text [ odd; "{\"type\":\"assistant\",\"message\":null}" ]) in
  assert_equal ~printer:string_of_int 3 (List.length tx.msgs)

let case_assign_counts_each_message_once_and_never_a_subagents _ =
  let s = Claude_tx.parse_session main_session in
  let secs ts = Option.get (Claude_tx.seconds ts) in
  (* both windows hold 12:59:59..13:00:00; w2 belongs to the first *)
  let ws = Claude_tx.assign s [ ("x", secs "2026-11-21T12:00:00Z", secs "2026-11-21T13:00:00Z");
                                ("y", secs "2026-11-21T12:59:59Z", secs "2026-11-21T14:00:00Z") ] in
  let ids = List.map (fun (w : Claude_tx.window_spend) ->
      (w.w_key, List.map (fun (m : Claude_tx.msg) -> m.id) w.w_msgs, w.w_tools, w.w_bad)) ws in
  let show (k, ms, t, b) = Printf.sprintf "%s:%s/%d/%d" k (String.concat "," ms) t b in
  assert_equal ~printer:(fun l -> String.concat " " (List.map show l)) [ ("x", [ "w1"; "w2" ], 2, 0); ("y", [], 0, 0) ] ids;
  let w = List.hd ws in
  let c = Claude_tx.author_cost w.w_msgs w.w_tools in
  assert_equal ~printer:string_of_int 45 c.tokens_out;    (* w1's last snapshot 40 + w2 5; the sidechain 9999 never *)
  assert_equal ~printer:string_of_int 300 c.tokens_cache_read

(* usage.1: a main-thread line whose usage lacks a count is kept as a
   stamp, and fails the first window that holds it, and only that one *)
let usage_less ~ts ~id =
  jline [ ("type", `String "assistant"); ("timestamp", `String ts); ("sessionId", `String "main1");
          ("message", `Assoc [ ("id", `String id); ("model", `String "claude-opus-5-5"); ("content", `List []);
                               ("usage", `Assoc [ ("input_tokens", `Int 1); ("cache_read_input_tokens", `Int 1);
                                                  ("cache_creation_input_tokens", `Int 1) ]) ]) ]

let case_a_usage_less_line_fails_the_first_window_that_holds_it _ =
  let s = Claude_tx.parse_session (main_session ^ Gen.text [
      usage_less ~ts:"2026-11-21T12:59:59.500Z" ~id:"w3";      (* in both windows *)
      usage_less ~ts:"2026-11-21T15:00:00.000Z" ~id:"w4" ]) in (* in neither *)
  assert_equal [ "2026-11-21T12:59:59.500Z"; "2026-11-21T15:00:00.000Z" ] s.s_bad_at;
  assert_equal [ "w1"; "w2" ] (List.map (fun (m : Claude_tx.msg) -> m.id) s.s_msgs);
  let secs ts = Option.get (Claude_tx.seconds ts) in
  let ws = Claude_tx.assign s [ ("x", secs "2026-11-21T12:00:00Z", secs "2026-11-21T13:00:00Z");
                                ("y", secs "2026-11-21T12:59:59Z", secs "2026-11-21T14:00:00Z") ] in
  assert_equal ~printer:(fun l -> String.concat "," (List.map string_of_int l)) [ 1; 0 ]
    (List.map (fun (w : Claude_tx.window_spend) -> w.w_bad) ws)

(* law: across any windows, every usage-less line inside one of them
   is counted exactly once, and one outside all of them never *)
let law_each_usage_less_line_fails_at_most_one_window =
  let stamp o = Printf.sprintf "2026-11-21T12:00:%02dZ" o in
  let gen = QCheck2.Gen.(pair (list_size (int_range 0 12) (int_range 0 59))
                              (list_size (int_range 0 5) (pair (int_range 0 59) (int_range 0 59)))) in
  QCheck2.Test.make ~count:300 ~name:"law_each_usage_less_line_fails_at_most_one_window" gen
    (fun (bad, spans) ->
       let secs o = Option.get (Claude_tx.seconds (stamp o)) in
       let windows = List.mapi (fun i (a, b) -> (string_of_int i, secs (min a b), secs (max a b))) spans in
       let s = { Claude_tx.s_id = "s"; s_msgs = []; s_tools = []; s_bash = []; s_results = [];
                 s_bad_at = List.map stamp bad; s_marks = []; s_results_at = [] } in
       let held o = List.exists (fun (_, f, u) -> secs o >= f && secs o < u +. 1.) windows in
       let total = List.fold_left (fun acc (w : Claude_tx.window_spend) -> acc + w.w_bad) 0 (Claude_tx.assign s windows) in
       total = List.length (List.filter held bad))

(* ---------- the node-cost deriver (derive.1) ---------- *)

let case_cycle_timing_splits_todo_and_handed_off _ =
  let d = Metrics.cycle_dwell (Metrics.edges_of_text rules4) in
  let at c st = List.fold_left (fun acc (c', st', s) -> if c' = c && st' = st then acc + s else acc) 0 d in
  let p (a, b) = Printf.sprintf "(%d, %d)" a b in
  assert_equal ~msg:"cycle 4" ~printer:p (8, 1370) (at 4 "todo", at 4 "handed_off");
  assert_equal ~msg:"cycle 1: create to handoff" ~printer:p (4318, 662) (at 1 "todo", at 1 "handed_off");
  assert_equal ~msg:"the cap block, cycle 3" ~printer:string_of_int 75035 (at 3 "blocked");
  let ss = Metrics.derive_timing ~quest:"q" ~node:"node-a" (Metrics.edges_of_text rules4) in
  assert_equal ~printer:string_of_int 8 (List.length ss);
  List.iter (fun (s : Metrics.sample) ->
      assert_equal ~msg:"derived samples refuse a write" ~printer:Fun.id "E_METRIC_DERIVED" (code (Metrics.validate s))) ss

let iso t = let g = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (g.tm_year + 1900) (g.tm_mon + 1) g.tm_mday g.tm_hour g.tm_min g.tm_sec

(* A legal FSM walk with growing stamps: the deriver's per-cycle seconds
   add up, state by state, to the dwell bp3 q r reports. *)
let law_cycle_dwell_sums_to_the_rollup_dwell =
  QCheck2.Test.make ~count:300 ~name:"law_cycle_dwell_sums_to_the_rollup_dwell"
    QCheck2.Gen.(pair Gen.fsm_walk (list_size (return 64) (int_range 0 5000)))
    (fun (lines, gaps) ->
      let base = 1795000000. in
      let stamped = List.mapi (fun i l ->
          let t = base +. float_of_int (List.fold_left ( + ) 0 (List.filteri (fun k _ -> k <= i) gaps)) in
          match Yojson.Safe.from_string l with
          | `Assoc fs -> Yojson.Safe.to_string (`Assoc (("ts", `String (iso t)) :: List.remove_assoc "ts" fs))
          | j -> Yojson.Safe.to_string j) lines in
      let text = Gen.text stamped in
      let d = Metrics.cycle_dwell (Metrics.edges_of_text text) in
      let ours st = List.fold_left (fun acc (_, st', s) -> if st' = st then acc + s else acc) 0 d in
      let theirs = (Store.timing_of_text text).t_dwell in
      List.for_all (fun (st, s) -> ours st = s) theirs
      && List.for_all (fun (_, st, _) -> List.mem_assoc st theirs) d)

let law_rollup_ignores_sample_order =
  QCheck2.Test.make ~count:300 ~name:"law_rollup_ignores_sample_order"
    QCheck2.Gen.(pair (list_size (int_range 0 20) gen_sample) (int_range 0 1000))
    (fun (samples, seed) ->
      (* real walls carry milliseconds: a float sum must not depend on order *)
      let samples = List.map (fun (s : Metrics.sample) ->
          if s.metric = "grade.wall_s" then { s with value = s.value /. 1000. } else s) samples in
      let shuffled = List.map snd (List.sort compare
          (List.mapi (fun i s -> ((i * 7919 + seed) mod 1009, s)) samples)) in
      let edges = Metrics.edges_of_text rules4 in
      Metrics.rollup_json (Metrics.rollup ~edges samples) = Metrics.rollup_json (Metrics.rollup ~edges shuffled))

(* node roll-ups add up to the quest's: spend is integer tokens, so the
   sums are exact *)
let law_node_spend_adds_up_to_the_quest =
  QCheck2.Test.make ~count:300 ~name:"law_node_spend_adds_up_to_the_quest"
    (QCheck2.Gen.list_size (QCheck2.Gen.int_range 0 30) gen_sample)
    (fun samples ->
      let nodes = List.sort_uniq compare (List.map (fun (s : Metrics.sample) -> s.node) samples) in
      let spend ss = (Metrics.rollup ~edges:[] ss).r_grade_spend in
      let per_node = List.map (fun n -> spend (List.filter (fun (s : Metrics.sample) -> s.node = n) samples)) nodes in
      List.for_all (fun (k, total) ->
          List.fold_left (fun acc sp -> acc +. List.assoc k sp) 0. per_node = total) (spend samples))

(* a re-scrape appends nothing, so no roll-up moves *)
let law_a_rescrape_changes_no_rollup =
  QCheck2.Test.make ~count:300 ~name:"law_a_rescrape_changes_no_rollup"
    (QCheck2.Gen.list_size (QCheck2.Gen.int_range 0 20) gen_sample)
    (fun samples ->
      let stored, _ = Metrics.dedupe ~existing:[] samples in
      let again, _ = Metrics.dedupe ~existing:stored samples in
      let edges = Metrics.edges_of_text rules4 in
      Metrics.rollup_json (Metrics.rollup ~edges (stored @ again)) = Metrics.rollup_json (Metrics.rollup ~edges stored))

let case_rollup_reports_median_grade_wall_and_spend _ =
  let s m v c = sample ~metric:m ~value:v ~cycle:c () in
  let author m v c = sample ~metric:m ~value:v ~cycle:c ~source:"author-window" () in
  let samples = [ s "grade.wall_s" 100. 1; s "grade.wall_s" 300. 2; s "grade.wall_s" 200. 3;
                  s "grade.tokens_cache_read" 10. 1; s "grade.tokens_cache_read" 5. 2;
                  author "author.tokens_cache_read" 70. 1 ] in
  let j = Metrics.rollup_json (Metrics.rollup ~edges:(Metrics.edges_of_text rules4) samples) in
  let open Yojson.Safe.Util in
  let i k = to_int (member k j) in
  assert_equal ~printer:string_of_int 4 (i "grades");          (* rules.4: four grade edges *)
  assert_equal ~printer:string_of_int 3 (i "grades_measured");
  assert_equal ~printer:string_of_int 4 (i "handoffs");
  assert_equal ~printer:string_of_int 1 (i "handoffs_measured");
  let w k = to_int (member k (member "grade_wall_s" j)) in
  assert_equal ~printer:(fun (a, b, c) -> Printf.sprintf "%d %d %d" a b c) (200, 100, 300) (w "median", w "min", w "max");
  let sp kind k = to_int (member k (member kind (member "spend" j))) in
  assert_equal ~printer:string_of_int 15 (sp "grade" "tokens_cache_read");
  assert_equal ~printer:string_of_int 70 (sp "author" "tokens_cache_read");
  assert_equal (Some 2.5) (Metrics.median [ 1.; 4.; 2.; 3. ])

let pending_tests = []

(* ---------- author time (induct-inline-as-default measure.1) ---------- *)

let jl fields = Yojson.Safe.to_string (`Assoc fields)
let at hms = "2026-11-22T" ^ hms ^ ".000Z"
let a_line ?(stop = "tool_use") ?(tools = []) ~id hms =
  jl [ ("type", `String "assistant"); ("timestamp", `String (at hms)); ("isSidechain", `Bool false);
       ("sessionId", `String "s1");
       ("message", `Assoc [ ("id", `String id); ("model", `String "claude-opus-5-5"); ("stop_reason", `String stop);
                            ("content", `List (List.map (fun t -> `Assoc [ ("type", `String "tool_use"); ("id", `String t);
                                                                          ("name", `String "Bash"); ("input", `Assoc []) ]) tools));
                            ("usage", `Assoc [ ("input_tokens", `Int 1); ("output_tokens", `Int 1);
                                               ("cache_read_input_tokens", `Int 0); ("cache_creation_input_tokens", `Int 0) ]) ]) ]
let r_line ~tool hms =
  jl [ ("type", `String "user"); ("timestamp", `String (at hms)); ("isSidechain", `Bool false);
       ("message", `Assoc [ ("content", `List [ `Assoc [ ("type", `String "tool_result"); ("tool_use_id", `String tool);
                                                         ("content", `String "ok") ] ]) ]) ]
let secs hms = Option.get (Claude_tx.seconds (at hms))

(* The NODE.md trace: tools in parallel, a turn that ended and waited
   for the human, then the handoff cast. *)
let trace_session = Claude_tx.parse_session (String.concat "\n" [
    a_line ~id:"w1" ~tools:[ "t1"; "t2" ] "10:00:05";
    r_line ~tool:"t2" "10:00:20";
    r_line ~tool:"t1" "10:00:35";
    a_line ~id:"w2" ~stop:"end_turn" "10:02:00";
    a_line ~id:"w3" "10:07:00";
    a_line ~id:"w4" ~tools:[ "t3" ] "10:07:10";
    r_line ~tool:"t3" "10:07:40";
    a_line ~id:"w5" ~tools:[ "t9" ] "10:07:05" ])

let times ~from ~upto = Claude_tx.window_times trace_session ~from:(secs from) ~upto:(secs upto)
let triple (w : Claude_tx.window_times) = Printf.sprintf "%g %g %g" w.t_wall w.t_active w.t_tool

let case_author_window_times_follow_the_trace _ =
  assert_equal ~printer:Fun.id "460 155 60" (triple (times ~from:"10:00:00" ~upto:"10:07:40"));
  (* a window opened 2 h before this session's first line: that span is wall, never active *)
  assert_equal ~printer:Fun.id "7660 155 60" (triple (times ~from:"08:00:00" ~upto:"10:07:40"));
  (* an end_turn as the window's last line adds nothing *)
  assert_equal ~printer:Fun.id "150 115 30" (triple (times ~from:"10:00:00" ~upto:"10:02:30"))
  (* t9 (10:07:05) has no result: it adds nothing to the 60 above, a lower bound *)

let case_author_pass_writes_the_window_times _ =
  let cast hms = jl [ ("type", `String "assistant"); ("timestamp", `String (at hms)); ("isSidechain", `Bool false);
                      ("sessionId", `String "s1");
                      ("message", `Assoc [ ("id", `String "w4"); ("model", `String "claude-opus-5-5"); ("stop_reason", `String "tool_use");
                                           ("content", `List [ `Assoc [ ("type", `String "tool_use"); ("id", `String "t3"); ("name", `String "Bash");
                                                                        ("input", `Assoc [ ("command", `String "bp3 q q1 n nd e handoff --commit abc1234") ]) ] ]);
                                           ("usage", `Assoc [ ("input_tokens", `Int 1); ("output_tokens", `Int 1);
                                                              ("cache_read_input_tokens", `Int 0); ("cache_creation_input_tokens", `Int 0) ]) ]) ] in
  let s = Claude_tx.parse_session (String.concat "\n" [
      a_line ~id:"w1" ~tools:[ "t1"; "t2" ] "10:00:05"; r_line ~tool:"t2" "10:00:20"; r_line ~tool:"t1" "10:00:35";
      a_line ~id:"w2" ~stop:"end_turn" "10:02:00"; a_line ~id:"w3" "10:07:00"; cast "10:07:10"; r_line ~tool:"t3" "10:07:40" ]) in
  let edge ts e c = { Metrics.e_ts = "2026-11-22T" ^ ts ^ "Z"; e_edge = e; e_cycle = 1; e_commit = c; e_to = "" } in
  let all = [ ("nd", edge "10:00:00" "create" None); ("nd", edge "10:07:40" "handoff" (Some "abc1234def5678abc1234def5678abc1234def56")) ] in
  let out = Metrics_io.author_pass "q1" all [ s ] in
  let samples, (t : Metrics.tally) = Hashtbl.find out "nd" in
  let v m = match List.find_opt (fun (x : Metrics.sample) -> x.metric = m) samples with
    | Some x -> Printf.sprintf "%g" x.value | None -> "-" in
  assert_equal ~printer:string_of_int 1 t.authored;
  assert_equal ~printer:Fun.id "460 155 60" (String.concat " " (List.map v [ "author.wall_s"; "author.active_s"; "author.tool_s" ]))

let case_grade_tool_time_is_the_union_of_paired_calls _ =
  let tx = Claude_tx.parse (String.concat "\n" [
      jl [ ("type", `String "user"); ("timestamp", `String (at "12:00:00"));
           ("message", `Assoc [ ("role", `String "user"); ("content", `String "Grade nd at abc1234.") ]) ];
      a_line ~id:"g1" ~tools:[ "x1"; "x2" ] "12:00:01";
      r_line ~tool:"x2" "12:00:11";
      r_line ~tool:"x1" "12:00:37";
      a_line ~id:"g2" ~tools:[ "x3" ] "12:00:40";
      a_line ~id:"g3" ~stop:"end_turn" "12:01:30" ]) in
  let c = Claude_tx.cost tx in
  assert_equal ~printer:string_of_float 36. c.tool_s;
  assert_equal ~printer:string_of_float 90. c.wall_s

(* Law: for any lines, turn ends and tool calls, 0 <= tool <= active <=
   wall, and tool time never exceeds the calls' summed durations. *)
let law_author_times_are_ordered =
  let open QCheck2.Gen in
  let gen =
    triple (list_size (int_range 0 30) (pair (int_range 0 600) bool))
      (list_size (int_range 0 10) (pair (int_range 0 600) (int_range 0 120)))
      (pair (int_range 0 300) (int_range 0 900)) in
  QCheck2.Test.make ~count:300 ~name:"law_author_times_are_ordered" gen
    (fun (marks, calls, (from, len)) ->
       let base = secs "10:00:00" in
       let iso s = let x = 36000 + s in
         Printf.sprintf "2026-11-22T%02d:%02d:%02d.000Z" (x / 3600) (x mod 3600 / 60) (x mod 60) in
       let s = { Claude_tx.s_id = "s"; s_msgs = []; s_bash = []; s_results = []; s_bad_at = [];
                 s_marks = List.sort compare (List.map (fun (o, e) -> (base +. float_of_int o, e)) marks);
                 s_tools = List.mapi (fun i (o, _) -> (string_of_int i, iso o)) calls;
                 s_results_at = List.mapi (fun i (o, d) -> (string_of_int i, base +. float_of_int (o + d))) calls } in
       let w = Claude_tx.window_times s ~from:(base +. float_of_int from) ~upto:(base +. float_of_int (from + len)) in
       let summed = float_of_int (List.fold_left (fun acc (_, d) -> acc + d) 0 calls) in
       0. <= w.t_tool && w.t_tool <= w.t_active +. 1e-6 && w.t_active <= w.t_wall +. 1e-6 && w.t_tool <= summed +. 1e-6)

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
       "case_author_spans_start_at_the_previous_quest_edge_but_never_a_resume" >:: case_author_spans_start_at_the_previous_quest_edge_but_never_a_resume;
       "case_parse_session_keeps_the_main_thread_and_handoff_results" >:: case_parse_session_keeps_the_main_thread_and_handoff_results;
       "case_casts_handoff_by_the_result_commit_or_a_command_prefix_inside_the_window" >:: case_casts_handoff_by_the_result_commit_or_a_command_prefix_inside_the_window;
       "case_a_line_without_a_message_never_stops_the_reader" >:: case_a_line_without_a_message_never_stops_the_reader;
       "case_cycle_timing_splits_todo_and_handed_off" >:: case_cycle_timing_splits_todo_and_handed_off;
       "case_rollup_reports_median_grade_wall_and_spend" >:: case_rollup_reports_median_grade_wall_and_spend;
       QCheck_ounit.to_ounit2_test law_cycle_dwell_sums_to_the_rollup_dwell;
       QCheck_ounit.to_ounit2_test law_rollup_ignores_sample_order;
       QCheck_ounit.to_ounit2_test law_node_spend_adds_up_to_the_quest;
       QCheck_ounit.to_ounit2_test law_a_rescrape_changes_no_rollup;
       "case_assign_counts_each_message_once_and_never_a_subagents" >:: case_assign_counts_each_message_once_and_never_a_subagents;
       "case_a_usage_less_line_fails_the_first_window_that_holds_it" >:: case_a_usage_less_line_fails_the_first_window_that_holds_it;
       QCheck_ounit.to_ounit2_test law_each_usage_less_line_fails_at_most_one_window;
       "case_a_usage_line_missing_a_count_is_skipped_and_fails_the_check" >:: case_a_usage_line_missing_a_count_is_skipped_and_fails_the_check;
       "case_agrees_allows_a_small_context_undercount_and_nothing_else" >:: case_agrees_allows_a_small_context_undercount_and_nothing_else;
       "case_parse_until_cuts_the_transcript_at_the_report" >:: case_parse_until_cuts_the_transcript_at_the_report;
       "case_an_off_shape_model_is_recorded_as_other" >:: case_an_off_shape_model_is_recorded_as_other;
       QCheck_ounit.to_ounit2_test law_appending_any_batch_twice_writes_it_once;
       QCheck_ounit.to_ounit2_test law_sink_text_round_trips;
       "case_author_window_times_follow_the_trace" >:: case_author_window_times_follow_the_trace;
       "case_grade_tool_time_is_the_union_of_paired_calls" >:: case_grade_tool_time_is_the_union_of_paired_calls;
       "case_author_pass_writes_the_window_times" >:: case_author_pass_writes_the_window_times;
       QCheck_ounit.to_ounit2_test law_author_times_are_ordered;
     ] @ pending_tests)
