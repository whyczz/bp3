(* Hook edges (test-pyramid unit.4): run-id parsing, the edge a
   command attempts, presets, refusal codes, lint detection, and the
   registry binding's JSON round trip. Tables of (input, expected),
   one row per case. Not here: load_registry / save_registry and the
   stale sweep inside handle () read and write the registry file (the
   fixture tier, hooks.sh); the stale predicate itself is
   Clock.stale (test_clock.ml). *)
open OUnit2

let table name rows f printer =
  List.iter (fun (input, want) -> assert_equal ~msg:(name ^ ": " ^ input) ~printer want (f input)) rows

let opt = function Some s -> "Some " ^ s | None -> "None"

let case_parse_edge_cycle_reads_the_edge_from_field_2_and_the_cycle_from_the_last_field _ =
  table "parse_edge_cycle" [
    ("20261118T120000Z-handoff-pi-none-c2", ("handoff", 2));
    ("20261118T110640.123a7f3Z-grade-muse-code-opus-c3", ("grade", 3));
    ("20261118T120000Z-verify-pi-m", ("verify", 1));
    ("20261118T120000Z-land-pi-m-cx", ("land", 1));
    ("bare", ("", 1)) ]
    Hooks.parse_edge_cycle (fun (e, c) -> Printf.sprintf "(%s, %d)" e c)

let case_attempted_edge_finds_the_edge_after_the_u_or_update_verb _ =
  table "attempted_edge" [
    ("bp3 q quest1 u node-1 handoff --commit abc", Some "handoff");
    ("BP3_Q_BIN=x ./bin/bp3 q g update n grade --verdict ship", Some "grade");
    ("bp3   q  g  u  n   land", Some "land");
    ("bp3 q g r n", None);
    ("bp3 q g u n", None) ]
    Hooks.attempted_edge opt

let case_extract_preset_reads_a_key_value_up_to_a_space_or_quote _ =
  table "extract_preset" [
    ("BP3_MODEL=opus-5 bp3 q g u n handoff", Some "opus-5");
    ("env 'BP3_MODEL=haiku' x", Some "haiku");
    ("BP3_MODEL=sonnet\tbp3 q", Some "sonnet");
    ("BP3_MODEL= bp3", None);
    ("bp3 q g u n handoff", None) ]
    (fun c -> Hooks.extract_preset c "BP3_MODEL") opt

let case_payload_strings_reads_the_six_output_keys_in_order_and_nothing_else _ =
  let j = Yojson.Safe.from_string {|{"tool_input": "IN", "tool_response": "1", "tool_output": "2", "output": "3",
                                     "response": "4", "result": "5", "error": "6", "other": "X"}|} in
  assert_equal ~printer:(String.concat ",") [ "1"; "2"; "3"; "4"; "5"; "6" ] (Hooks.payload_strings j);
  let nested = Hooks.payload_strings (Yojson.Safe.from_string {|{"output": ["a", {"k": ["b", 7]}], "result": {"x": "c"}}|}) in
  assert_equal ~printer:(String.concat ",") [ "a"; "b"; "c" ] (List.sort compare nested)

let case_refusal_code_finds_an_error_code_anywhere_in_the_tool_output _ =
  let j s = Yojson.Safe.from_string s in
  table "refusal_code" [
    ({|{"tool_response": "{\"ok\":false,\"error\":{\"code\":\"E_DEPTH\"}}"}|}, Some "E_DEPTH");
    ({|{"tool_output": ["noise", {"text": "\"code\" : \"E_LINK_SPENT\""}]}|}, Some "E_LINK_SPENT");
    ({|{"error": "\"code\":\"e_lower\""}|}, None);
    ({|{"result": "\"code\":\"E_lower\""}|}, None);
    ({|{"response": "\"code\":\"EXISTS\""}|}, None);
    ({|{"output": "\"code\":\"E_DIRTY_TREE\""}|}, Some "E_DIRTY_TREE");
    ({|{"tool_input": {"command": "\"code\":\"E_NOT_OUTPUT\""}}|}, None) ]
    (fun s -> Hooks.refusal_code (j s)) opt

let case_command_of_reads_tool_input_command_and_nothing_else _ =
  let j s = Yojson.Safe.from_string s in
  table "command_of" [
    ({|{"tool_input": {"command": "make check"}}|}, "make check");
    ({|{"tool_input": "make check"}|}, "");
    ({|{"command": "make check"}|}, "") ]
    (fun s -> Hooks.command_of (j s)) Fun.id

let case_lint_check_of_names_the_check_a_command_runs _ =
  table "lint_check_of" [
    ("make check", Some "make check");
    ("SDKROOT=x make lint", Some "make lint");
    ("shellcheck bin/bp3", Some "shellcheck");
    ("bash ./test/g.sh", Some "g.sh");
    ("cat test/notes.md", None);
    ("ls", None) ]
    Hooks.lint_check_of opt

let char_binding_of_json_reads_a_pre_rename_graph_key_as_the_quest _ =
  let b = Hooks.binding_of_json "S1" (Yojson.Safe.from_string {|{"graph": "old-q", "node": "n"}|}) in
  assert_equal ~printer:Fun.id "old-q" b.Hooks.quest

let case_binding_to_json_writes_the_registry_keys_the_engine_reads_back _ =
  let b = { Hooks.quest = "q"; node = "n"; run_id = "R"; session_id = "S"; started_ts = "t0"; started_epoch = 1.;
            last_seen_ts = "t1"; last_seen_epoch = 2.; settled = true; unsettled = false; emitted = [ "e" ];
            in_tok = 3; out_tok = 4; cached_tok = 5; reasoning_tok = 6; llm_calls = 7 } in
  let (sid, j) = Hooks.binding_to_json b in
  assert_equal ~printer:Fun.id "S" sid;
  assert_equal ~printer:Fun.id
    {|{"quest":"q","node":"n","run_id":"R","started_ts":"t0","started_epoch":1.0,"last_seen_ts":"t1","last_seen_epoch":2.0,"settled":true,"unsettled":false,"emitted":["e"],"input_tokens":3,"output_tokens":4,"cached_tokens":5,"reasoning_tokens":6,"llm_calls":7}|}
    (Yojson.Safe.to_string j)

let case_binding_of_json_falls_back_to_started_epoch_when_last_seen_is_missing _ =
  let b = Hooks.binding_of_json "S1" (Yojson.Safe.from_string {|{"quest": "q", "started_epoch": 1795000000}|}) in
  assert_equal ~printer:string_of_float 1_795_000_000. b.Hooks.last_seen_epoch

let gen_binding =
  let open QCheck2.Gen in
  let s = string_size ~gen:printable (int_range 0 12) in
  let nat_tok = int_range 0 1_000_000 in
  let epoch = float_range 1. 4.0e9 in
  map (fun ((quest, node, run_id, sid, started_ts, last_seen_ts), (started, last, settled, unsettled, emitted), (i, o, c, r, l)) ->
      { Hooks.quest = (if quest = "" then "q" else quest); node; run_id; session_id = sid; started_ts;
        started_epoch = started; last_seen_ts; last_seen_epoch = last; settled; unsettled; emitted;
        in_tok = i; out_tok = o; cached_tok = c; reasoning_tok = r; llm_calls = l })
    (triple (tup6 s s s s s s) (tup5 epoch epoch bool bool (list_size (int_range 0 3) s))
       (tup5 nat_tok nat_tok nat_tok nat_tok nat_tok))

let law_binding_json_round_trips =
  QCheck2.Test.make ~count:300 ~name:"law_binding_json_round_trips" gen_binding
    (fun b ->
      let (sid, j) = Hooks.binding_to_json b in
      let text = Yojson.Safe.to_string j in
      sid = b.Hooks.session_id && Hooks.binding_of_json sid (Yojson.Safe.from_string text) = b)

let law_parse_edge_cycle_reads_the_cycle_from_any_generated_run_id =
  QCheck2.Test.make ~count:300 ~name:"law_parse_edge_cycle_reads_the_cycle_from_any_generated_run_id"
    ~print:(fun (e, r, c, ts) -> Printf.sprintf "%s-%s-%s-c%d" ts e r c)
    QCheck2.Gen.(quad (string_size ~gen:(char_range 'a' 'z') (int_range 1 8))
                   (* middle fields may hold dashes, digits, even a c<digits> field *)
                   (map (String.concat "-") (list_size (int_range 0 4)
                      (oneof [ string_size ~gen:(oneof [ char_range 'a' 'z'; char_range '0' '9' ]) (int_range 0 6);
                               map (fun n -> "c" ^ string_of_int n) (int_range 0 99) ])))
                   (oneof [ int_range 0 9; int_range 0 9999 ])
                   (oneof_list [ "20261118T000000Z"; "20261118T110640.123a7f3Z" ]))
    (fun (edge, rest, cycle, ts) ->
      Hooks.parse_edge_cycle (Printf.sprintf "%s-%s-%s-c%d" ts edge rest cycle) = (edge, cycle))

let () =
  run_test_tt_main
    ("hooks" >::: [
       "case_parse_edge_cycle_reads_the_edge_from_field_2_and_the_cycle_from_the_last_field" >:: case_parse_edge_cycle_reads_the_edge_from_field_2_and_the_cycle_from_the_last_field;
       "case_attempted_edge_finds_the_edge_after_the_u_or_update_verb" >:: case_attempted_edge_finds_the_edge_after_the_u_or_update_verb;
       "case_extract_preset_reads_a_key_value_up_to_a_space_or_quote" >:: case_extract_preset_reads_a_key_value_up_to_a_space_or_quote;
       "case_payload_strings_reads_the_six_output_keys_in_order_and_nothing_else" >:: case_payload_strings_reads_the_six_output_keys_in_order_and_nothing_else;
       "case_refusal_code_finds_an_error_code_anywhere_in_the_tool_output" >:: case_refusal_code_finds_an_error_code_anywhere_in_the_tool_output;
       "case_command_of_reads_tool_input_command_and_nothing_else" >:: case_command_of_reads_tool_input_command_and_nothing_else;
       "case_lint_check_of_names_the_check_a_command_runs" >:: case_lint_check_of_names_the_check_a_command_runs;
       "char_binding_of_json_reads_a_pre_rename_graph_key_as_the_quest" >:: char_binding_of_json_reads_a_pre_rename_graph_key_as_the_quest;
       "case_binding_to_json_writes_the_registry_keys_the_engine_reads_back" >:: case_binding_to_json_writes_the_registry_keys_the_engine_reads_back;
       "case_binding_of_json_falls_back_to_started_epoch_when_last_seen_is_missing" >:: case_binding_of_json_falls_back_to_started_epoch_when_last_seen_is_missing;
       QCheck_ounit.to_ounit2_test law_binding_json_round_trips;
       QCheck_ounit.to_ounit2_test law_parse_edge_cycle_reads_the_cycle_from_any_generated_run_id;
     ])
