(* Warden deterministic plugs (warden-v0 plugs.1): positive + negative
   known cases for all 12 plugs across Layer 1 (git/repo) and Layer 2
   (session traces), JSON + table formatters, and QCheck2 invariants. *)
open OUnit2

let sample ?(quest = "q1") ?(node = "n1") ?(cycle = 1) ?(run = "agy:c1")
    ?(model = "gemini-3-pro") ?(at = "2026-11-23T12:00:00Z") metric value =
  let source = if String.starts_with ~prefix:"author." metric then "author-window" else "grade-transcripts" in
  { Metrics.metric; quest; node; cycle; run; model; value; at; source }

let entry ?(ts = "2026-11-23T12:00:00Z") ?(to_ = "") ?(cycle = 1) ?commit
    ?(verdict = "") ?(reason = "") ?(refused = false) ?(err = "") edge =
  { Warden.le_ts = ts; le_edge = edge; le_to = to_; le_cycle = cycle;
    le_commit = commit; le_verdict = verdict; le_reason = reason;
    le_refused = refused; le_error_code = err }

let clean_entries ?(ts = "2026-11-23T12:00:00Z") () = [
  entry ~ts ~to_:"todo" "create";
  entry ~ts ~to_:"handed_off" ~commit:"aaaaaaa" "handoff";
  entry ~ts ~to_:"approved" ~verdict:"ship" ~reason:"clean" "grade";
  entry ~ts ~to_:"landed" "land";
]

let clean_samples ?(node = "n1") () = [
  sample ~node "grade.wall_s" 90.;
  sample ~node "grade.tokens_out" 400.;
  sample ~node "author.wall_s" 200.;
  sample ~node "author.tokens_out" 1200.;
]

let clean_node ?(node = "n1") ?(state = "landed") ?(entries = clean_entries ())
    ?(samples = clean_samples ~node ()) () =
  { Warden.ne_node = node; ne_state = state; ne_entries = entries; ne_samples = samples }

let mk_quest ?(quest = "q1") ?(nodes = [ clean_node () ]) ?(desks = [])
    ?(post_land = []) ?(traces = []) () =
  { Warden.qe_quest = quest; qe_nodes = nodes; qe_open_desks = desks;
    qe_post_land_commits = post_land; qe_traces = traces }

let mk_ev ?(scope = "quest") ?(active = [ "q1" ]) ?(has_repo_config = true)
    ?(grade_wall_s = 300.) quests =
  { Warden.ev_scope = scope; ev_active_quests = active; ev_quests = quests;
    ev_has_repo_config = has_repo_config; ev_grade_wall_s = grade_wall_s }

let ev_tool ?(name = "run_command") ?(cmd = "make check") ?(err = false) ?(step = 1) () =
  { Tx.te_name = name; te_cmd_head = cmd; te_error = err;
    te_start = 100.; te_end = 105.; te_step = step }

let mk_trace ?(node = "n1") ?(cycle = 1) ?(role = "author") ?(path = "/tmp/tx.jsonl")
    ?(run = "agy:s1") ?(ctx = 100_000) ?(turns = 10) ?(errs = 0) ?(events = []) ?(user_steps = []) () =
  { Tx.jt_node = node; jt_cycle = cycle; jt_role = role; jt_path = path; jt_run = run;
    jt_context_end = ctx; jt_turns = turns; jt_tool_errors = errs;
    jt_events = events; jt_user_steps = user_steps }

let rules fs = List.map (fun (f : Warden.finding) -> f.rule) fs
let has_rule r fs = List.exists (fun (f : Warden.finding) -> f.rule = r) fs
let find_rule r fs = List.find (fun (f : Warden.finding) -> f.rule = r) fs

(* ---------- clean & layout ---------- *)

let case_clean_quest_produces_no_findings_and_layout_has_feedback _ =
  assert_equal ~printer:Fun.id "FEEDBACK.md" Layout.feedback_file;
  let tr = mk_trace ~events:[ ev_tool ~cmd:"make check" ~step:2 (); ev_tool ~cmd:"make check-full" ~step:4 () ] () in
  let ev = mk_ev [ mk_quest ~traces:[ tr ] () ] in
  assert_equal ~printer:(String.concat ",") [] (rules (Warden.run ev));
  (* empty traces degrades gracefully *)
  let ev_no_tr = mk_ev [ mk_quest ~traces:[] () ] in
  assert_equal ~printer:(String.concat ",") [] (rules (Warden.run ev_no_tr));
  assert_equal ~printer:string_of_int 0 (Warden.sessions_scanned ev_no_tr)

(* ---------- Layer 1 plugs ---------- *)

let case_plug_1_multi_active_quest _ =
  assert_equal [] (Warden.run (mk_ev ~active:[ "q1" ] [ mk_quest () ]));
  let fs = Warden.run (mk_ev ~active:[ "q1"; "q2" ] [ mk_quest () ]) in
  assert_bool "fires on 2 active" (has_rule "multi_active_quest" fs);
  let f = find_rule "multi_active_quest" fs in
  assert_equal ~printer:Fun.id "2 active quests" f.observed;
  assert_equal ~printer:Fun.id "repo:QUEST.md" f.evidence_ref;
  assert_equal Warden.Major f.severity

let case_plug_2_cycle_outlier _ =
  (* 2 cycles & <=300s is clean *)
  let two_c = clean_node ~entries:[
      entry ~to_:"todo" "create";
      entry ~cycle:1 ~to_:"handed_off" ~commit:"1111111" "handoff";
      entry ~cycle:2 ~to_:"todo" ~verdict:"needs_fix" ~reason:"[major] bug" "grade";
      entry ~cycle:2 ~to_:"handed_off" ~commit:"2222222" "handoff";
      entry ~cycle:2 ~to_:"approved" ~verdict:"ship" "grade";
      entry ~cycle:2 ~to_:"landed" "land";
    ] () in
  assert_bool "2 cycles ok" (not (has_rule "cycle_outlier" (Warden.run (mk_ev [ mk_quest ~nodes:[ two_c ] () ]))));
  (* 3 cycles fires *)
  let three_c = clean_node ~entries:[
      entry ~to_:"todo" "create";
      entry ~cycle:1 ~to_:"handed_off" ~commit:"1111111" "handoff";
      entry ~cycle:2 ~to_:"todo" ~verdict:"needs_fix" ~reason:"[major] a" "grade";
      entry ~cycle:2 ~to_:"handed_off" ~commit:"2222222" "handoff";
      entry ~cycle:3 ~to_:"todo" ~verdict:"needs_fix" ~reason:"[major] b" "grade";
      entry ~cycle:3 ~to_:"handed_off" ~commit:"3333333" "handoff";
      entry ~cycle:3 ~to_:"approved" ~verdict:"ship" "grade";
      entry ~cycle:3 ~to_:"landed" "land";
    ] () in
  let fs = Warden.run (mk_ev [ mk_quest ~nodes:[ three_c ] () ]) in
  assert_bool "3 cycles fires" (has_rule "cycle_outlier" fs);
  assert_equal ~printer:Fun.id "3 cycles" (find_rule "cycle_outlier" fs).observed;
  (* single cycle with grade wall > 300s fires *)
  let slow = clean_node ~samples:[ sample "grade.wall_s" 340.; sample "author.wall_s" 500. ] () in
  let fs2 = Warden.run (mk_ev [ mk_quest ~nodes:[ slow ] () ]) in
  assert_bool "slow grade fires" (has_rule "cycle_outlier" fs2);
  assert_equal ~printer:Fun.id "340s grade wall" (find_rule "cycle_outlier" fs2).observed;
  (* manifest.2: custom [warden].grade_wall_s = 600 suppresses 450s and flags 650s *)
  let med = clean_node ~samples:[ sample "grade.wall_s" 450.; sample "author.wall_s" 500. ] () in
  assert_bool "450s ok under 600s cap"
    (not (has_rule "cycle_outlier" (Warden.run (mk_ev ~grade_wall_s:600. [ mk_quest ~nodes:[ med ] () ]))));
  let v_slow = clean_node ~samples:[ sample "grade.wall_s" 650.; sample "author.wall_s" 700. ] () in
  let fs3 = Warden.run (mk_ev ~grade_wall_s:600. [ mk_quest ~nodes:[ v_slow ] () ]) in
  assert_bool "650s fires under 600s cap" (has_rule "cycle_outlier" fs3);
  assert_equal ~printer:Fun.id "> 600s grade wall" (find_rule "cycle_outlier" fs3).threshold

let case_plug_missing_repo_config _ =
  let ev_miss = mk_ev ~has_repo_config:false [ mk_quest () ] in
  let fs = Warden.run ev_miss in
  assert_bool "fires when backpack.toml missing" (has_rule "missing_repo_config" fs);
  let f = find_rule "missing_repo_config" fs in
  assert_equal Warden.Minor f.severity;
  assert_equal ~printer:Fun.id "repo:backpack.toml" f.evidence_ref;
  let j = Warden.to_json ev_miss fs in
  assert_equal (`String Names.w_no_repo_config)
    Yojson.Safe.Util.(j |> member "warnings" |> index 0 |> member "code");
  let ev_ok = mk_ev ~has_repo_config:true [ mk_quest () ] in
  assert_bool "clears when backpack.toml present" (not (has_rule "missing_repo_config" (Warden.run ev_ok)));
  assert_equal `Null (Yojson.Safe.Util.member "warnings" (Warden.to_json ev_ok []))

let case_plug_3_minor_only_bounce _ =
  let bounced reason = clean_node ~entries:[
      entry ~to_:"todo" "create";
      entry ~cycle:1 ~to_:"handed_off" ~commit:"1111111" "handoff";
      entry ~cycle:2 ~to_:"todo" ~verdict:"needs_fix" ~reason "grade";
      entry ~cycle:2 ~to_:"handed_off" ~commit:"2222222" "handoff";
      entry ~cycle:2 ~to_:"approved" ~verdict:"ship" ~reason:"[minor] nit" "grade";
      entry ~cycle:2 ~to_:"landed" "land";
    ] () in
  let fs_hit = Warden.run (mk_ev [ mk_quest ~nodes:[ bounced "[minor] rename variable" ] () ]) in
  assert_bool "minor-only fires" (has_rule "minor_only_bounce" fs_hit);
  assert_equal ~printer:string_of_int 1 (find_rule "minor_only_bounce" fs_hit).cycle;
  (* [major] + [minor] does NOT fire *)
  let fs_major = Warden.run (mk_ev [ mk_quest ~nodes:[ bounced "[major] broken test; [minor] typo" ] () ]) in
  assert_bool "major+minor does not fire" (not (has_rule "minor_only_bounce" fs_major));
  (* [critical] + [minor] does NOT fire *)
  let fs_crit = Warden.run (mk_ev [ mk_quest ~nodes:[ bounced "[critical] crash; [minor] nit" ] () ]) in
  assert_bool "critical+minor does not fire" (not (has_rule "minor_only_bounce" fs_crit))

let case_plug_4_vacuous_test_bounce _ =
  let mk r = clean_node ~entries:[
      entry ~to_:"todo" "create";
      entry ~cycle:1 ~to_:"handed_off" ~commit:"1111111" "handoff";
      entry ~cycle:2 ~to_:"todo" ~verdict:"needs_fix" ~reason:r "grade";
      entry ~cycle:2 ~to_:"handed_off" ~commit:"2222222" "handoff";
      entry ~cycle:2 ~to_:"approved" ~verdict:"ship" "grade";
      entry ~cycle:2 ~to_:"landed" "land";
    ] () in
  List.iter (fun reason ->
      let fs = Warden.run (mk_ev [ mk_quest ~nodes:[ mk reason ] () ]) in
      assert_bool reason (has_rule "vacuous_test_bounce" fs);
      assert_equal ~printer:string_of_int 1 (find_rule "vacuous_test_bounce" fs).cycle)
    [ "[major] test can't fail even when logic deleted";
      "[major] test stays green under mutation";
      "[major] killed 0/1 mutant check" ];
  let fs_ok = Warden.run (mk_ev [ mk_quest ~nodes:[ mk "[major] missing flag validation" ] () ]) in
  assert_bool "non-vacuous does not fire" (not (has_rule "vacuous_test_bounce" fs_ok))

let case_plug_5_grade_inversion _ =
  (* below 180s floor: 170s vs 50s (3.4x) does NOT fire *)
  let fast = clean_node ~samples:[
      sample "grade.wall_s" 170.; sample "author.wall_s" 50.;
      sample "grade.tokens_out" 100.; sample "author.tokens_out" 500.;
    ] () in
  assert_bool "below 180s floor" (not (has_rule "grade_inversion" (Warden.run (mk_ev [ mk_quest ~nodes:[ fast ] () ]))));
  (* > 180s & > 1.5x fires *)
  let slow_inv = clean_node ~samples:[
      sample "grade.wall_s" 240.; sample "author.wall_s" 100.;
      sample "grade.tokens_out" 100.; sample "author.tokens_out" 500.;
    ] () in
  assert_bool "wall inversion fires" (has_rule "grade_inversion" (Warden.run (mk_ev [ mk_quest ~nodes:[ slow_inv ] () ])));
  (* tokens_out inversion requires > 25k floor; small thinking-model grades do not false-fire *)
  let tok_small = clean_node ~samples:[
      sample "grade.wall_s" 100.; sample "author.wall_s" 120.;
      sample "grade.tokens_out" 12_000.; sample "author.tokens_out" 6_000.;
    ] () in
  assert_bool "below 25k tok floor does not invert"
    (not (has_rule "grade_inversion" (Warden.run (mk_ev [ mk_quest ~nodes:[ tok_small ] () ]))));
  let tok_inv = clean_node ~samples:[
      sample "grade.wall_s" 100.; sample "author.wall_s" 120.;
      sample "grade.tokens_out" 30_000.; sample "author.tokens_out" 15_000.;
    ] () in
  assert_bool "token inversion > 25k fires" (has_rule "grade_inversion" (Warden.run (mk_ev [ mk_quest ~nodes:[ tok_inv ] () ])));
  (* missing author metrics (0.) must NOT false-fire *)
  let no_author = clean_node ~samples:[ sample "grade.wall_s" 250.; sample "grade.tokens_out" 900. ] () in
  assert_bool "missing author does not invert"
    (not (has_rule "grade_inversion" (Warden.run (mk_ev [ mk_quest ~nodes:[ no_author ] () ]))))

let case_plug_6_coverage_gap _ =
  (* modern quest with 0 samples fires *)
  let unmeasured = clean_node ~entries:(clean_entries ~ts:"2026-11-23T12:00:00Z" ()) ~samples:[] () in
  assert_bool "modern missing samples fires"
    (has_rule "coverage_gap" (Warden.run (mk_ev [ mk_quest ~nodes:[ unmeasured ] () ])));
  (* legacy pre-2026-11-21 quest with 0 samples is skipped *)
  let legacy = clean_node ~entries:(clean_entries ~ts:"2026-11-18T12:00:00Z" ()) ~samples:[] () in
  assert_bool "legacy pre-metrics skipped"
    (not (has_rule "coverage_gap" (Warden.run (mk_ev [ mk_quest ~nodes:[ legacy ] () ]))))

let case_plug_7_desk_leak _ =
  let open_grade = { Warden.di_run_id = "grade-n1-c1-a1"; di_quest = "q1"; di_node = "n1";
                     di_path = ".bp3/worktrees/grade-n1-c1-a1"; di_missing = false } in
  let missing_grade = { open_grade with di_missing = true } in
  let quest_desk = { open_grade with di_run_id = "quest-q1"; di_node = "(quest)" } in
  assert_bool "open grade desk on landed fires"
    (has_rule "desk_leak" (Warden.run (mk_ev [ mk_quest ~desks:[ open_grade ] () ])));
  assert_bool "missing desk ignored"
    (not (has_rule "desk_leak" (Warden.run (mk_ev [ mk_quest ~desks:[ missing_grade ] () ]))));
  assert_bool "quest desk ignored"
    (not (has_rule "desk_leak" (Warden.run (mk_ev [ mk_quest ~desks:[ quest_desk ] () ]))));
  (* >= 3 identical E_* refusals fires; 2 does not *)
  let mk_ref n =
    let refs = List.init n (fun _ -> entry ~refused:true ~err:"E_DIRTY_TREE" "refused") in
    clean_node ~entries:(clean_entries () @ refs) () in
  assert_bool "2 refusals ok" (not (has_rule "desk_leak" (Warden.run (mk_ev [ mk_quest ~nodes:[ mk_ref 2 ] () ]))));
  assert_bool "3 refusals fires" (has_rule "desk_leak" (Warden.run (mk_ev [ mk_quest ~nodes:[ mk_ref 3 ] () ])))

let case_plug_8_post_land_bugfix _ =
  let plc = [ { Warden.plc_sha = "deadbeef123456"; plc_subject = "fix: missed edge case" } ] in
  let fs = Warden.run (mk_ev [ mk_quest ~post_land:plc () ]) in
  assert_bool "post_land fires" (has_rule "post_land_bugfix" fs);
  let f = find_rule "post_land_bugfix" fs in
  assert_equal ~printer:Fun.id "1 commits" f.observed;
  assert_equal ~printer:Fun.id "git:deadbee" f.evidence_ref

(* ---------- Layer 2 plugs ---------- *)

let case_plug_9_tool_retry_loop _ =
  let errs n = List.init n (fun i -> ev_tool ~cmd:("cmd" ^ string_of_int i) ~err:true ~step:(i + 1) ()) in
  assert_bool "2 consecutive ok"
    (not (has_rule "tool_retry_loop" (Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~events:(errs 2) () ] () ]))));
  let fs3 = Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~events:(errs 3) () ] () ]) in
  assert_bool "3 consecutive fires" (has_rule "tool_retry_loop" fs3);
  assert_equal ~printer:Fun.id "tx:/tmp/tx.jsonl#step:1" (find_rule "tool_retry_loop" fs3).evidence_ref;
  (* non-consecutive 3x same failing command also fires *)
  let non_consec = [
    ev_tool ~cmd:"dune build" ~err:true ~step:2 ();
    ev_tool ~cmd:"ls" ~err:false ~step:3 ();
    ev_tool ~cmd:"dune build" ~err:true ~step:4 ();
    ev_tool ~cmd:"ls" ~err:false ~step:5 ();
    ev_tool ~cmd:"dune build" ~err:true ~step:6 ();
  ] in
  let fs_same = Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~events:non_consec () ] () ]) in
  assert_bool "3x identical cmd fires" (has_rule "tool_retry_loop" fs_same);
  assert_equal ~printer:Fun.id "tx:/tmp/tx.jsonl#step:2" (find_rule "tool_retry_loop" fs_same).evidence_ref

let case_plug_10_full_gate_in_author _ =
  let two_full = [
    ev_tool ~cmd:"make check-full" ~step:5 ();
    ev_tool ~cmd:"make check-full" ~step:12 ();
  ] in
  let fs_a = Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~role:"author" ~events:two_full () ] () ]) in
  assert_bool "2x in author fires" (has_rule "full_gate_in_author" fs_a);
  assert_equal ~printer:Fun.id "tx:/tmp/tx.jsonl#step:12" (find_rule "full_gate_in_author" fs_a).evidence_ref;
  (* grader running make check-full is never flagged *)
  let fs_g = Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~role:"grade" ~events:two_full () ] () ]) in
  assert_bool "grade ignored" (not (has_rule "full_gate_in_author" fs_g))

let case_plug_11_context_bloat_harness_aware _ =
  (* 200k is fine on agy (400k limit) but bloats on claude/pi (150k limit) *)
  assert_bool "agy 200k ok"
    (not (has_rule "context_bloat" (Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~run:"agy:a1" ~ctx:200_000 () ] () ]))));
  assert_bool "agy 420k fires"
    (has_rule "context_bloat" (Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~run:"agy:a1" ~ctx:420_000 () ] () ])));
  assert_bool "claude 160k fires"
    (has_rule "context_bloat" (Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~run:"claude:s1" ~ctx:160_000 () ] () ])));
  assert_bool "pi 140k ok"
    (not (has_rule "context_bloat" (Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~run:"pi:p1" ~ctx:140_000 () ] () ]))));
  (* turns > 30 fires regardless of token count *)
  assert_bool "turns > 30 fires"
    (has_rule "context_bloat" (Warden.run (mk_ev [ mk_quest ~traces:[ mk_trace ~run:"agy:a1" ~ctx:50_000 ~turns:35 () ] () ])));
  (* deduplicated per (quest, jt_run): multi-cycle inline author session emits 1 peak finding *)
  let dup_traces = [
    mk_trace ~node:"n1" ~cycle:1 ~run:"agy:same" ~ctx:420_000 ~turns:10 ();
    mk_trace ~node:"n2" ~cycle:1 ~run:"agy:same" ~ctx:490_000 ~turns:8 ();
    mk_trace ~node:"n2" ~cycle:1 ~role:"grade" ~run:"agy:g1" ~ctx:50_000 ~turns:34 ();
  ] in
  let fs_dup = List.filter (fun (f : Warden.finding) -> f.rule = "context_bloat")
      (Warden.run (mk_ev [ mk_quest ~traces:dup_traces () ])) in
  assert_equal ~printer:string_of_int 2 (List.length fs_dup);
  assert_bool "peak 490k kept" (List.exists (fun (f : Warden.finding) -> Tx.contains f.observed "490k") fs_dup)

let case_plug_12_human_steer _ =
  (* session mid-node USER_INPUT fires *)
  let tr = mk_trace ~role:"author" ~user_steps:[ (14, 1795400000.) ] () in
  let fs = Warden.run (mk_ev [ mk_quest ~traces:[ tr ] () ]) in
  assert_bool "session steer fires" (has_rule "human_steer" fs);
  let f = find_rule "human_steer" fs in
  assert_equal Warden.Session f.layer;
  assert_equal ~printer:Fun.id "tx:/tmp/tx.jsonl#step:14" f.evidence_ref;
  (* Layer-1 block edge fires even with empty traces *)
  let blocked_n = clean_node ~entries:[
      entry ~to_:"todo" "create";
      entry ~cycle:1 ~to_:"blocked" ~reason:"owner decision owed" "block";
      entry ~cycle:1 ~to_:"todo" "resume";
      entry ~cycle:1 ~to_:"handed_off" ~commit:"aaaaaaa" "handoff";
      entry ~cycle:1 ~to_:"approved" ~verdict:"ship" "grade";
      entry ~cycle:1 ~to_:"landed" "land";
    ] () in
  let fs_b = Warden.run (mk_ev [ mk_quest ~nodes:[ blocked_n ] ~traces:[] () ]) in
  assert_bool "block edge fires" (has_rule "human_steer" fs_b);
  assert_equal Warden.Git (find_rule "human_steer" fs_b).layer

(* ---------- ledger entry parsing + JSON + table ---------- *)

let case_entries_of_text_and_json_table_formatting _ =
  let text = String.concat "\n" [
      {|{"ts":"2026-11-23T12:00:00Z","edge":"handoff","from":"todo","to":"handed_off","cycle":1,"commit":"abc1234","verdict":null,"reason":"ok"}|};
      {|{"ts":"2026-11-23T12:05:00Z","edge":"grade","from":"handed_off","to":"todo","cycle":2,"commit":"abc1234","verdict":"needs_fix","reason":"[minor] nit"}|};
      {|{"ts":"2026-11-23T12:06:00Z","edge":"refused","code":"E_DIRTY_TREE","reason":"dirty"}|};
    ] in
  let es = Warden.entries_of_text text in
  assert_equal ~printer:string_of_int 3 (List.length es);
  assert_bool "3rd entry is refused" (List.nth es 2).le_refused;
  assert_equal ~printer:Fun.id "E_DIRTY_TREE" (List.nth es 2).le_error_code;
  let ev = mk_ev ~active:[ "q1"; "q2" ] [ mk_quest () ] in
  let fs = Warden.run ev in
  let j = Warden.to_json ev fs in
  let open Yojson.Safe.Util in
  assert_bool "ok true" (to_bool (member "ok" j));
  assert_equal ~printer:Fun.id "quest" (to_string (member "scope" j));
  assert_equal ~printer:string_of_int 1 (to_int (member "total" (member "counts" j)));
  let tbl = Warden.to_table ev fs in
  assert_bool "table has header" (Tx.contains tbl "RULE");
  assert_bool "table has rule" (Tx.contains tbl "multi_active_quest");
  let empty_tbl = Warden.to_table (mk_ev [ mk_quest () ]) [] in
  assert_bool "empty table says 0 findings" (Tx.contains empty_tbl "0 findings")

(* ---------- QCheck2 property laws ---------- *)

let gen_finding =
  let open QCheck2.Gen in
  let rule = oneof_list [ "multi_active_quest"; "cycle_outlier"; "minor_only_bounce";
                          "vacuous_test_bounce"; "grade_inversion"; "coverage_gap";
                          "desk_leak"; "post_land_bugfix"; "tool_retry_loop";
                          "full_gate_in_author"; "context_bloat"; "human_steer" ] in
  let layer = oneof_list [ Warden.Git; Warden.Session ] in
  let sev = oneof_list [ Warden.Major; Warden.Minor ] in
  let id = oneof_list [ ""; "q1"; "q2"; "n1"; "n2" ] in
  map (fun ((r, l, s), (q, n, c), ref_id) ->
      { Warden.rule = r; layer = l; severity = s; quest = q; node = n; cycle = c;
        observed = "obs"; threshold = "thr"; evidence_ref = "ref:" ^ string_of_int ref_id;
        summary = "sum" })
    (triple (triple rule layer sev) (triple id id (int_range 0 5)) (int_range 0 20))

let law_sort_findings_is_ordered_and_idempotent =
  QCheck2.Test.make ~count:200 ~name:"law_sort_findings_is_ordered_and_idempotent"
    (QCheck2.Gen.list_size (QCheck2.Gen.int_range 0 25) gen_finding)
    (fun fs ->
      let sorted = Warden.sort_findings fs in
      let rec ordered = function
        | a :: (b :: _ as rest) -> Warden.compare_finding a b <= 0 && ordered rest
        | _ -> true in
      ordered sorted && Warden.sort_findings sorted = sorted && List.length sorted = List.length fs)

let law_counts_total_matches_findings_and_layers =
  QCheck2.Test.make ~count:200 ~name:"law_counts_total_matches_findings_and_layers"
    (QCheck2.Gen.list_size (QCheck2.Gen.int_range 0 25) gen_finding)
    (fun fs ->
      let j = Warden.counts_json fs in
      let open Yojson.Safe.Util in
      let total = to_int (member "total" j) in
      let bl = member "by_layer" j in
      let g = to_int (member "git" bl) and s = to_int (member "session" bl) in
      let br_sum = match member "by_rule" j with
        | `Assoc xs -> List.fold_left (fun acc (_, v) -> acc + to_int v) 0 xs
        | _ -> -1 in
      total = List.length fs && g + s = total && br_sum = total)

let suite =
  "warden" >::: [
    "case_clean_quest_produces_no_findings_and_layout_has_feedback" >:: case_clean_quest_produces_no_findings_and_layout_has_feedback;
    "case_plug_1_multi_active_quest" >:: case_plug_1_multi_active_quest;
    "case_plug_missing_repo_config" >:: case_plug_missing_repo_config;
    "case_plug_2_cycle_outlier" >:: case_plug_2_cycle_outlier;
    "case_plug_3_minor_only_bounce" >:: case_plug_3_minor_only_bounce;
    "case_plug_4_vacuous_test_bounce" >:: case_plug_4_vacuous_test_bounce;
    "case_plug_5_grade_inversion" >:: case_plug_5_grade_inversion;
    "case_plug_6_coverage_gap" >:: case_plug_6_coverage_gap;
    "case_plug_7_desk_leak" >:: case_plug_7_desk_leak;
    "case_plug_8_post_land_bugfix" >:: case_plug_8_post_land_bugfix;
    "case_plug_9_tool_retry_loop" >:: case_plug_9_tool_retry_loop;
    "case_plug_10_full_gate_in_author" >:: case_plug_10_full_gate_in_author;
    "case_plug_11_context_bloat_harness_aware" >:: case_plug_11_context_bloat_harness_aware;
    "case_plug_12_human_steer" >:: case_plug_12_human_steer;
    "case_entries_of_text_and_json_table_formatting" >:: case_entries_of_text_and_json_table_formatting;
    QCheck_ounit.to_ounit2_test law_sort_findings_is_ordered_and_idempotent;
    QCheck_ounit.to_ounit2_test law_counts_total_matches_findings_and_layers;
  ]

let () = run_test_tt_main suite
