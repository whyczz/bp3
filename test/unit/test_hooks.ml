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

let case_payload_cwd_prefers_cwd_then_workspace_paths_then_fallback _ =
  let j s = Yojson.Safe.from_string s in
  table "payload_cwd" [
    ({|{"cwd": "/repo/a", "workspacePaths": ["/repo/b"]}|}, "/repo/a");
    ({|{"workspacePaths": ["/repo/b", "/repo/c"]}|}, "/repo/b");
    ({|{"cwd": "", "workspacePaths": ["", "/repo/c"]}|}, "/repo/c");
    ({|{"workspacePaths": []}|}, "/fallback");
    ({|{}|}, "/fallback") ]
    (fun s -> Hooks.payload_cwd ~fallback:"/fallback" (j s)) Fun.id

let case_legacy_skills_warning_shape_and_verdict_attachment _ =
  let w = Hooks.legacy_skills_warning [ ".agents/skills/quest/SKILL.md"; ".claude/skills/quest/SKILL.md" ] in
  assert_equal ~printer:Fun.id Names.w_local_skills_legacy (Util.get_str w "code" "");
  let msg = Util.get_str w "message" "" in
  assert_bool "message mentions prune-local" (Util.contains_sub msg "bp3 skills prune-local");
  assert_bool "message mentions count 2" (Util.contains_sub msg "2 legacy");
  (match Yojson.Safe.Util.member "files" w with
   | `List [ `String a; `String b ] ->
       assert_equal ~printer:Fun.id ".agents/skills/quest/SKILL.md" a;
       assert_equal ~printer:Fun.id ".claude/skills/quest/SKILL.md" b
   | _ -> assert_failure "expected 2 files in warning");
  let plain = Hooks.no_write "not a bp3 repo" in
  assert_equal `Null (Yojson.Safe.Util.member "warnings" plain);
  let with_w = Hooks.no_write ~warnings:[ w ] "not a bp3 repo" in
  (match Yojson.Safe.Util.member "warnings" with_w with
   | `List [ _ ] -> ()
   | _ -> assert_failure "expected 1 warning in verdict")

let session_action_printer = function
  | None -> "None"
  | Some (Hooks.Session_clear q) -> "Clear(" ^ q ^ ")"
  | Some (Hooks.Session_bind { quest; mode; red_ink_path }) ->
      Printf.sprintf "Bind(%s,%s,%s)" quest mode (match red_ink_path with Some p -> p | None -> "null")

let case_extract_session_action_matches_explicit_quest_commands_and_red_ink_edits _ =
  let cases = [
    ("bp3 harness desk prepare --quest q1", "",
     Some (Hooks.Session_bind { quest = "q1"; mode = "induct"; red_ink_path = None }));
    ("./bin/bp3 worktree prepare --quest=q-alpha", "",
     Some (Hooks.Session_bind { quest = "q-alpha"; mode = "induct"; red_ink_path = None }));
    ("./bin/bp3 q q1 n node-1 e handoff --commit abc", "",
     Some (Hooks.Session_bind { quest = "q1"; mode = "induct"; red_ink_path = None }));
    ("./bin/bp3 q c q1 --type default", "",
     Some (Hooks.Session_bind { quest = "q1"; mode = "induct"; red_ink_path = None }));
    ("./bin/bp3 q r q1", "",
     Some (Hooks.Session_bind { quest = "q1"; mode = "induct"; red_ink_path = None }));
    ("cd /tmp/desk && ./bin/bp3 q q-compound metrics r", "",
     Some (Hooks.Session_bind { quest = "q-compound"; mode = "induct"; red_ink_path = None }));
    ("./bin/bp3 q r", "", None);
    ("./bin/bp3 q hooks", "", None);
    ("./bin/bp3 warden q1", "", None);
    ("BP3_DECIDER=human ./bin/bp3 release q1", "",
     Some (Hooks.Session_clear "q1"));
    ("BP3_DECIDER=human bp3 release --bump minor q1 --no-gh", "",
     Some (Hooks.Session_clear "q1"));
    ("bp3 release q1 --dry-run", "", None);
    ("BP3_DECIDER=human bp3 release --commit abc1234", "", None);
    ("", "/repo/docs/quests/q1/QUEST.red-ink.md",
     Some (Hooks.Session_bind { quest = "q1"; mode = "red-ink"; red_ink_path = Some "docs/quests/q1/QUEST.red-ink.md" }));
    ("", "docs/quests/q-beta/QUEST.2b-reviewed.md",
     Some (Hooks.Session_bind { quest = "q-beta"; mode = "red-ink"; red_ink_path = Some "docs/quests/q-beta/QUEST.2b-reviewed.md" }));
    ("", "/repo/docs/quests/q1/QUEST.md", None);
    ("", "/repo/my_docs/quests/q1/QUEST.red-ink.md", None);
  ] in
  List.iter (fun (command, file_path, want) ->
    assert_equal ~msg:(command ^ " | " ^ file_path) ~printer:session_action_printer
      want (Hooks.extract_session_action ~command ~file_path)) cases

let case_file_path_of_reads_claude_and_agy_file_arguments _ =
  let j s = Yojson.Safe.from_string s in
  table "file_path_of" [
    ({|{"tool_input": {"file_path": "/a/QUEST.red-ink.md"}}|}, "/a/QUEST.red-ink.md");
    ({|{"tool_input": {"path": "/b/QUEST.2b-reviewed.md"}}|}, "/b/QUEST.2b-reviewed.md");
    ({|{"toolCall": {"name": "edit_file", "args": {"Path": "/c/QUEST.red-ink.md"}}}|}, "/c/QUEST.red-ink.md");
    ({|{"toolCall": {"name": "write_file", "args": {"TargetFile": "/d/QUEST.red-ink.md"}}}|}, "/d/QUEST.red-ink.md");
    ({|{"tool_input": {"command": "ls"}}|}, "") ]
    (fun s -> Hooks.file_path_of (j s)) Fun.id

let law_sanitize_session_id_prevents_path_traversal =
  let gen_sid =
    let open QCheck2.Gen in
    oneof [
      string_size ~gen:(oneof_list [ 'a'; 'Z'; '0'; '.'; '_'; '-'; '/'; '\\'; ' '; ':' ]) (int_range 0 140);
      map (fun s -> "../" ^ s) (string_size ~gen:(char_range 'a' 'z') (int_range 0 10));
      map (fun s -> "." ^ s) (string_size ~gen:(char_range 'a' 'z') (int_range 0 10));
      string_size ~gen:(oneof [ char_range 'a' 'z'; char_range '0' '9'; return '-' ]) (int_range 1 64);
    ] in
  QCheck2.Test.make ~count:500 ~name:"law_sanitize_session_id_prevents_path_traversal"
    ~print:Fun.id gen_sid
    (fun raw ->
      let allowed c =
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9') || c = '.' || c = '_' || c = '-' in
      let all_allowed s =
        let n = String.length s in
        let rec go i = i >= n || (allowed s.[i] && go (i + 1)) in
        go 0 in
      match Hooks.sanitize_session_id raw with
      | Some s ->
          s = raw
          && String.length s >= 1 && String.length s <= 128
          && s.[0] <> '.'
          && not (String.contains s '/')
          && not (String.contains s '\\')
          && not (Util.contains_sub s "..")
          && all_allowed s
      | None ->
          String.length raw = 0
          || String.length raw > 128
          || raw.[0] = '.'
          || Util.contains_sub raw ".."
          || not (all_allowed raw))

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
       "case_payload_cwd_prefers_cwd_then_workspace_paths_then_fallback" >:: case_payload_cwd_prefers_cwd_then_workspace_paths_then_fallback;
       "case_legacy_skills_warning_shape_and_verdict_attachment" >:: case_legacy_skills_warning_shape_and_verdict_attachment;
       "case_extract_session_action_matches_explicit_quest_commands_and_red_ink_edits" >:: case_extract_session_action_matches_explicit_quest_commands_and_red_ink_edits;
       "case_file_path_of_reads_claude_and_agy_file_arguments" >:: case_file_path_of_reads_claude_and_agy_file_arguments;
       QCheck_ounit.to_ounit2_test law_binding_json_round_trips;
       QCheck_ounit.to_ounit2_test law_parse_edge_cycle_reads_the_cycle_from_any_generated_run_id;
       QCheck_ounit.to_ounit2_test law_sanitize_session_id_prevents_path_traversal;
     ])
