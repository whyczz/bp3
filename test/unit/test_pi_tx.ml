(* pi sessions (pi-metrics reader.1): Pi_tx reads a pi session into the
   Claude_tx cost record and checks its own read. Pure: sessions are
   built here as synthetic lines, never real prompts. *)
open OUnit2

let jline fields = Yojson.Safe.to_string (`Assoc fields)
let s v = `String v

let usage ?total (i, o, cr, cw) =
  `Assoc [ ("input", `Int i); ("output", `Int o); ("cacheRead", `Int cr); ("cacheWrite", `Int cw);
           ("reasoning", `Int 0); ("totalTokens", `Int (Option.value total ~default:(i + o + cr + cw)));
           ("cost", `Assoc [ ("total", `Float 0.01) ]) ]

let header id = jline [ ("type", s "session"); ("version", `Int 3); ("id", s id);
                        ("timestamp", s "2026-11-21T12:00:00.000Z"); ("cwd", s "/r") ]
let msg ~id ~ts m = jline [ ("type", s "message"); ("id", s id); ("parentId", `Null); ("timestamp", s ts); ("message", `Assoc m) ]
let user ~ts text = msg ~id:"u1" ~ts [ ("role", s "user"); ("content", s text) ]
let assistant ?(model = "gpt-6.1-sol") ?(calls = []) ?u ~id ~ts counts =
  msg ~id ~ts ([ ("role", s "assistant"); ("model", s model); ("provider", s "openai"); ("durationMs", `Int 900);
                 ("content", `List (`Assoc [ ("type", s "text"); ("text", s "ok") ]
                                    :: List.map (fun c -> `Assoc [ ("type", s "toolCall"); ("id", s c); ("name", s "bash");
                                                                   ("arguments", `Assoc [ ("command", s "make check-full") ]) ]) calls)) ]
               @ [ ("usage", Option.value u ~default:(usage counts)) ])
let result ~ts call = msg ~id:("r" ^ call) ~ts [ ("role", s "toolResult"); ("toolCallId", s call); ("toolName", s "bash");
                                                ("content", `List []); ("isError", `Bool false) ]
let usage_entry ~ts counts = jline [ ("type", s "usage"); ("id", s "ue1"); ("parentId", `Null); ("timestamp", s ts);
                                     ("kind", s "cache_warm"); ("model", s "gpt-6.1-sol"); ("usage", usage counts) ]

let grader = [
  header "g1";
  msg ~id:"sys" ~ts:"2026-11-21T12:00:00.100Z" [ ("role", s "system"); ("content", s "") ];
  user ~ts:"2026-11-21T12:00:01.000Z" "Grade nd at abc1234.";
  assistant ~id:"a1" ~ts:"2026-11-21T12:00:05.000Z" ~calls:[ "t1" ] (100, 10, 0, 0);
  result ~ts:"2026-11-21T12:00:40.000Z" "t1";
  usage_entry ~ts:"2026-11-21T12:00:41.000Z" (0, 0, 50, 0);
  assistant ~id:"a2" ~ts:"2026-11-21T12:00:43.500Z" (120, 5, 0, 0) ]

let case_a_pi_session_reads_into_the_claude_cost_record _ =
  let tx = Pi_tx.parse (Gen.text grader) in
  assert_equal ~printer:Fun.id "g1" tx.session;
  assert_equal ~printer:Fun.id "/r" tx.cwd;
  assert_equal ~printer:Fun.id "Grade nd at abc1234." tx.first_prompt;
  assert_equal ~printer:Fun.id "2026-11-21T12:00:01.000Z" tx.first_ts;
  assert_equal ~printer:Fun.id "2026-11-21T12:00:43.500Z" tx.last_ts;
  assert_equal [ "t1" ] tx.tool_calls;
  let c = Pi_tx.cost tx in
  let i = string_of_int in
  assert_equal ~printer:string_of_float 42.5 c.wall_s;
  assert_equal ~printer:i 1 c.tool_calls;
  assert_equal ~printer:i 220 c.tokens_in;
  assert_equal ~printer:i 15 c.tokens_out;
  assert_equal ~printer:i 50 c.tokens_cache_read;       (* the usage entry counts, as in pi's own totals *)
  assert_equal ~printer:i 0 c.tokens_cache_write;
  assert_equal ~printer:i 125 c.context_end;            (* the last assistant's prompt plus its output, as Claude's *)
  assert_equal ~printer:Fun.id "gpt-6.1-sol" c.model;
  assert_bool "self-checks" (Pi_tx.self_checks tx)

let case_self_check_fails_on_a_bad_total_a_missing_count_or_an_unpaired_call _ =
  let swap i line l = List.mapi (fun j x -> if j = i then line else x) l in
  let off_by_one = swap 6 (assistant ~id:"a2" ~ts:"2026-11-21T12:00:43.500Z" ~u:(usage ~total:126 (120, 5, 0, 0)) (120, 5, 0, 0)) grader in
  let missing = swap 6 (assistant ~id:"a2" ~ts:"2026-11-21T12:00:43.500Z"
                          ~u:(`Assoc [ ("input", `Int 120); ("cacheRead", `Int 0); ("cacheWrite", `Int 0); ("totalTokens", `Int 120) ])
                          (120, 0, 0, 0)) grader in
  let unpaired = List.filteri (fun j _ -> j <> 4) grader in
  List.iter (fun (name, lines) ->
      let tx = Pi_tx.parse (Gen.text lines) in
      assert_bool name (not (Pi_tx.self_checks tx)))
    [ ("total off by one", off_by_one); ("a count missing", missing); ("a call with no result", unpaired) ];
  (* a bad line never counts as zero spend: it is left out and flagged *)
  let tx = Pi_tx.parse (Gen.text off_by_one) in
  assert_equal ~printer:string_of_int 1 tx.bad_usage;
  assert_equal ~printer:string_of_int 100 (Pi_tx.cost tx).tokens_in

let case_junk_lines_are_skipped_never_read_as_zero _ =
  let tx = Pi_tx.parse (Gen.text (grader @ [ "not json"; "[1,2]"; "" ])) in
  assert_equal ~printer:string_of_int 2 tx.skipped_lines;
  assert_equal ~printer:string_of_int 220 (Pi_tx.cost tx).tokens_in;
  assert_bool "still self-checks" (Pi_tx.self_checks tx)

let case_model_ok_knows_four_families_and_nothing_else _ =
  List.iter (fun m -> assert_bool m (Metrics.model_ok m))
    [ "gpt-6.1-sol"; "claude-opus-5-5"; "gemini-3-pro"; "grok-5"; "unknown"; "other" ];
  List.iter (fun m -> assert_bool m (not (Metrics.model_ok m)))
    [ "sk-proj-abc"; "GPT-6"; "gpt 6"; "gpt-"; "openai/gpt-6"; "mlx-local-qwen"; "gpt-6\nsecret" ];
  let tx = Pi_tx.parse (Gen.text [ header "g2"; user ~ts:"2026-11-21T12:00:01.000Z" "x";
                                   assistant ~model:"mlx-local-qwen" ~id:"a1" ~ts:"2026-11-21T12:00:02.000Z" (1, 1, 0, 0) ]) in
  assert_equal ~printer:Fun.id "other" (Pi_tx.cost tx).model

(* law: for any assistant usages, the cost sums are the sums of the
   lines, and corrupting any one total fails the self-check *)
let law_cost_sums_the_lines_and_one_bad_total_fails_the_check =
  let gen = QCheck2.Gen.(pair (list_size (int_range 1 8) (quad (int_range 0 9999) (int_range 0 999) (int_range 0 9999) (int_range 0 999)))
                              nat) in
  QCheck2.Test.make ~count:300 ~name:"law_cost_sums_the_lines_and_one_bad_total_fails_the_check" gen
    (fun (counts, k) ->
       let line ?total j c = assistant ~id:(Printf.sprintf "a%d" j) ~ts:(Printf.sprintf "2026-11-21T12:00:%02d.000Z" (j + 2))
           ~u:(usage ?total c) c in
       let good = header "g" :: user ~ts:"2026-11-21T12:00:01.000Z" "x" :: List.mapi (fun j c -> line j c) counts in
       let tx = Pi_tx.parse (Gen.text good) in
       let c = Pi_tx.cost tx in
       let sum f = List.fold_left (fun acc q -> acc + f q) 0 counts in
       let bad_at = k mod List.length counts in
       let bad = header "g" :: user ~ts:"2026-11-21T12:00:01.000Z" "x"
                 :: List.mapi (fun j ((i, o, cr, cw) as q) -> if j = bad_at then line ~total:(i + o + cr + cw + 1) j q else line j q) counts in
       Pi_tx.self_checks tx
       && c.tokens_in = sum (fun (i, _, _, _) -> i) && c.tokens_out = sum (fun (_, o, _, _) -> o)
       && c.tokens_cache_read = sum (fun (_, _, cr, _) -> cr) && c.tokens_cache_write = sum (fun (_, _, _, cw) -> cw)
       && not (Pi_tx.self_checks (Pi_tx.parse (Gen.text bad))))

let () =
  run_test_tt_main
    ("pi_tx" >::: [
       "case_a_pi_session_reads_into_the_claude_cost_record" >:: case_a_pi_session_reads_into_the_claude_cost_record;
       "case_self_check_fails_on_a_bad_total_a_missing_count_or_an_unpaired_call" >:: case_self_check_fails_on_a_bad_total_a_missing_count_or_an_unpaired_call;
       "case_junk_lines_are_skipped_never_read_as_zero" >:: case_junk_lines_are_skipped_never_read_as_zero;
       "case_model_ok_knows_four_families_and_nothing_else" >:: case_model_ok_knows_four_families_and_nothing_else;
       QCheck_ounit.to_ounit2_test law_cost_sums_the_lines_and_one_bad_total_fails_the_check;
     ])
