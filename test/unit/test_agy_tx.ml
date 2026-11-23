(* agy transcripts (fast-agy-induct agy.1): Agy_tx reads an agy
   transcript.jsonl into the shared Tx.cost record + tool_events +
   author windows, with transcript_full.jsonl fallback on truncation. *)
open OUnit2

let jline fields = Yojson.Safe.to_string (`Assoc fields)
let s v = `String v

let user_line ?(step = 0) ?(trunc = false) ~ts content =
  let base = [ ("step_index", `Int step); ("source", s "USER_EXPLICIT"); ("type", s "USER_INPUT");
               ("status", s "DONE"); ("created_at", s ts); ("content", s content) ] in
  jline (if trunc then base @ [ ("truncated_fields", `List [ s "content" ]) ] else base)

let planner_line ?(step = 1) ?(model = "gemini-4-neon-medium") ?(calls = []) ?(missing_usage = false) ~ts (i, o, cr) =
  let tcs = List.map (fun (name, cmd) ->
      `Assoc [ ("name", s name); ("args", `Assoc [ ("CommandLine", s ("\"" ^ cmd ^ "\"")) ]) ]) calls in
  let base = [ ("step_index", `Int step); ("source", s "MODEL"); ("type", s "PLANNER_RESPONSE");
               ("status", s "DONE"); ("created_at", s ts); ("model", s model);
               ("tool_calls", `List tcs) ] in
  let usage = if missing_usage then [] else
    [ ("input_tokens", `Int i); ("output_tokens", `Int o); ("cache_read_tokens", `Int cr) ] in
  jline (base @ usage)

let generic_line ?(step = 2) ?(status = "DONE") ~ts content =
  jline [ ("step_index", `Int step); ("source", s "TOOL"); ("type", s "GENERIC");
          ("status", s status); ("created_at", s ts); ("content", s content) ]

let case_agy_grader_reads_cost_and_tool_events _ =
  let lines = [
    user_line ~step:0 ~ts:"2026-11-23T19:00:00Z" "Grade nd at abc1234 in quest q1, cycle 1.";
    planner_line ~step:1 ~ts:"2026-11-23T19:00:05Z" ~calls:[ ("run_command", "make check-full") ] (1000, 50, 200);
    generic_line ~step:2 ~status:"ERROR" ~ts:"2026-11-23T19:00:20Z" "exit 1";
    planner_line ~step:3 ~ts:"2026-11-23T19:00:25Z" ~calls:[] (1200, 80, 400);
  ] in
  let tx = Agy_tx.parse ~conv_id:"conv-1" (Gen.text lines) in
  assert_bool "self_checks" (Agy_tx.self_checks tx);
  assert_equal ~printer:Fun.id "conv-1" tx.conv_id;
  assert_equal ~printer:Fun.id "Grade nd at abc1234 in quest q1, cycle 1." tx.first_prompt;
  let c = Agy_tx.cost tx in
  let i = string_of_int in
  assert_equal ~printer:string_of_float 25. c.wall_s;
  assert_equal ~printer:i 1 c.tool_calls;
  assert_equal ~printer:string_of_float 15. c.tool_s;
  assert_equal ~printer:i 1 c.tool_errors;
  assert_equal ~printer:i 2 c.turns;
  assert_equal ~printer:i 2200 c.tokens_in;
  assert_equal ~printer:i 130 c.tokens_out;
  assert_equal ~printer:i 600 c.tokens_cache_read;
  assert_equal ~printer:i 0 c.tokens_cache_write;
  assert_equal ~printer:i 1680 c.context_end;
  assert_equal ~printer:Fun.id "gemini-4-neon-medium" c.model;
  assert_equal ~printer:i 1 (List.length tx.tool_events);
  let ev = List.hd tx.tool_events in
  assert_equal ~printer:Fun.id "run_command" ev.te_name;
  assert_equal ~printer:Fun.id "make check-full" ev.te_cmd_head;
  assert_bool "error flag" ev.te_error;
  assert_equal ~printer:i 1 ev.te_step

let case_truncated_fields_falls_back_to_full_transcript _ =
  let compact = [
    user_line ~step:0 ~trunc:true ~ts:"2026-11-23T19:00:00Z" "Grade nd (truncated)";
    planner_line ~step:1 ~ts:"2026-11-23T19:00:10Z" (500, 20, 0);
  ] in
  let full = [
    user_line ~step:0 ~ts:"2026-11-23T19:00:00Z" "Grade nd at abc1234 (full SHA abc1234567) in quest q1, cycle 1.";
    planner_line ~step:1 ~ts:"2026-11-23T19:00:10Z" (500, 20, 0);
  ] in
  let tx = Agy_tx.parse ~conv_id:"c-trunc" ~full_text:(Gen.text full) (Gen.text compact) in
  assert_bool "prompt came from full" (Tx.prompt_names_grade tx.first_prompt ~node:"nd" ~commit:"abc1234567")

let case_missing_usage_fails_self_check _ =
  let lines = [
    user_line ~step:0 ~ts:"2026-11-23T19:00:00Z" "Grade nd at abc1234.";
    planner_line ~step:1 ~missing_usage:true ~ts:"2026-11-23T19:00:05Z" (0, 0, 0);
  ] in
  let tx = Agy_tx.parse ~conv_id:"c-bad" (Gen.text lines) in
  assert_bool "self_checks must fail" (not (Agy_tx.self_checks tx));
  assert_equal ~printer:string_of_int 1 tx.bad_usage

let case_agy_author_window_casts_handoff_and_active_time _ =
  let lines = [
    user_line ~step:0 ~ts:"2026-11-23T19:00:00Z" "implement nd";
    planner_line ~step:1 ~ts:"2026-11-23T19:00:10Z" ~calls:[ ("run_command", "make check") ] (800, 40, 100);
    generic_line ~step:2 ~ts:"2026-11-23T19:00:25Z" "ok";
    (* end_turn gap: tool_calls=[] at 19:00:30 -> idle until 19:05:00 *)
    planner_line ~step:3 ~ts:"2026-11-23T19:00:30Z" ~calls:[] (900, 30, 100);
    planner_line ~step:4 ~ts:"2026-11-23T19:05:00Z" ~calls:[ ("run_command", "./bin/bp3 q q1 n nd e handoff --commit abc1234 --reason ok") ] (1000, 20, 100);
    generic_line ~step:5 ~ts:"2026-11-23T19:05:05Z" "{\"ok\":true,\"state\":\"handed_off\"}";
  ] in
  let tx = Agy_tx.parse ~conv_id:"auth-1" (Gen.text lines) in
  let from = Option.get (Tx.seconds "2026-11-23T19:00:00Z") in
  let upto = Option.get (Tx.seconds "2026-11-23T19:05:05Z") in
  assert_bool "casts_handoff" (Agy_tx.casts_handoff tx ~quest:"q1" ~node:"nd" ~commit:"abc1234567" ~from ~upto);
  let tm = Agy_tx.window_times tx ~from ~upto in
  assert_equal ~printer:string_of_float 305. tm.t_wall;
  (* active: [19:00:10..19:00:30] (20s) + [19:05:00..19:05:05] (5s) = 25s *)
  assert_equal ~printer:string_of_float 25. tm.t_active;
  (* tool: [19:00:10..19:00:25] (15s) + [19:05:00..19:05:05] (5s) = 20s *)
  assert_equal ~printer:string_of_float 20. tm.t_tool

let case_subagent_system_message_prompt_unwraps_and_joins _ =
  let prompt = "Grade nd at abc1234 (full SHA abc1234567) in quest q1, cycle 1.\n\nRules:\n- ok" in
  let wrapped =
    "The following is a <SYSTEM_MESSAGE> not actually sent by the user.\n\n<SYSTEM_MESSAGE>\n"
    ^ "[Message] timestamp=2026-11-23T21:06:45Z sender=parent priority=HIGH content=" ^ prompt ^ "\n</SYSTEM_MESSAGE>" in
  let compact = [
    jline [ ("step_index", `Int 0); ("source", s "SYSTEM"); ("type", s "SYSTEM_MESSAGE");
            ("status", s "DONE"); ("created_at", s "2026-11-23T19:00:00Z");
            ("content", s "The following is a <SYSTEM_MESSAGE> ... truncated");
            ("truncated_fields", `List [ s "content" ]) ];
    planner_line ~step:1 ~ts:"2026-11-23T19:00:10Z" (600, 30, 100);
  ] in
  let full = [
    jline [ ("step_index", `Int 0); ("source", s "SYSTEM"); ("type", s "SYSTEM_MESSAGE");
            ("status", s "DONE"); ("created_at", s "2026-11-23T19:00:00Z"); ("content", s wrapped) ];
    planner_line ~step:1 ~ts:"2026-11-23T19:00:10Z" (600, 30, 100);
  ] in
  let tx = Agy_tx.parse ~conv_id:"sub-1" ~full_text:(Gen.text full) (Gen.text compact) in
  assert_equal ~printer:Fun.id prompt tx.first_prompt;
  assert_bool "join_line_names" (Tx.join_line_names tx.first_prompt ~node:"nd" ~commit:"abc1234567")

let suite =
  "agy_tx" >::: [
    "case_agy_grader_reads_cost_and_tool_events" >:: case_agy_grader_reads_cost_and_tool_events;
    "case_truncated_fields_falls_back_to_full_transcript" >:: case_truncated_fields_falls_back_to_full_transcript;
    "case_missing_usage_fails_self_check" >:: case_missing_usage_fails_self_check;
    "case_agy_author_window_casts_handoff_and_active_time" >:: case_agy_author_window_casts_handoff_and_active_time;
    "case_subagent_system_message_prompt_unwraps_and_joins" >:: case_subagent_system_message_prompt_unwraps_and_joins;
  ]

let () = run_test_tt_main suite
