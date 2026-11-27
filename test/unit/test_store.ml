(* Store and scheduler units (test-pyramid unit.3): the ledger fold,
   ledger lines, legal edges, slugs, versions, waves, dates, icebox,
   plan knobs, the longest-copy rule, and the frozen samples. No git,
   no process, no clock (the clock is pinned where a function reads
   it). case_ = named example, law_ = QCheck property, char_ = today's
   behavior pinned without blessing it.
   Not here, by decision (each needs git or the filesystem, so it
   stays at the fixture tier):
   - fold_node, fold_quest: read the ledger through ledger_read (git
     show at a ref tip); their pure parts are fold_ledger and
     pick_longest, both tested here; g.sh / ready.sh exercise them.
   - dep_satisfied: folds every node of another quest from git;
     ready.sh's quest-level deps case pins it: handoff refused with
     E_DEPENDENCY while any dependency node is todo or approved,
     accepted once each is landed or deleted.
   - effective_knobs, quest_knobs: read plans/ files from the repo
     root; their pure part is plan_knobs_from_text, tested here. *)
open OUnit2
open Gen

let fold t = let (s, _, _) = Store.fold_ledger t in s

let verdict_code f =
  match f () with
  | _ -> "no verdict"
  | exception Gitx.Verdict (_, j) ->
      Yojson.Safe.Util.(j |> member "error" |> member "code" |> to_string)

(* ---------- fold ---------- *)

let case_fold_walks_create_handoff_grade_land_one_prefix_at_a_time _ =
  let lines = [ edge "create" "" "todo";
                edge ~commit:"c1" "handoff" "todo" "handed_off";
                edge ~verdict:"ship" ~verify:"pass" "grade" "handed_off" "approved";
                edge "land" "approved" "landed" ] in
  let want = [ ("todo", false, false, None); ("handed_off", false, false, Some "c1");
               ("approved", true, true, Some "c1"); ("landed", true, true, Some "c1") ] in
  List.iteri (fun i (st, g, v, b) ->
      let s = fold (text (List.filteri (fun k _ -> k <= i) lines)) in
      let at = Printf.sprintf "prefix %d" (i + 1) in
      assert_equal ~printer:Fun.id ~msg:(at ^ " state") st s.Store.st;
      assert_equal ~msg:(at ^ " grade_ok") g s.Store.grade_ok;
      assert_equal ~msg:(at ^ " verify_ok") v s.Store.verify_ok;
      assert_equal ~msg:(at ^ " bound") b s.Store.bound) want

let case_fold_reads_a_legacy_submitted_line_as_handed_off _ =
  let s = fold (text [ edge "create" "" "todo"; edge ~commit:"c1" "submit" "todo" "submitted" ]) in
  assert_equal ~printer:Fun.id "handed_off" s.Store.st

let case_fold_maps_legacy_review_and_check_edges_to_grade_and_verify _ =
  let s = fold (text [ edge ~commit:"c1" "submit" "todo" "submitted";
                       edge ~verdict:"ship" "review" "submitted" "submitted";
                       edge ~verdict:"pass" "check" "submitted" "approved" ]) in
  assert_bool "review ship counts as grade" s.Store.grade_ok;
  assert_bool "check pass counts as verify" s.Store.verify_ok

let case_fold_resets_both_verdicts_on_a_new_handoff _ =
  let s = fold (text [ edge ~commit:"c1" "handoff" "todo" "handed_off";
                       edge ~verdict:"ship" ~verify:"pass" "grade" "handed_off" "approved";
                       edge ~cycle:2 ~commit:"c2" "handoff" "approved" "handed_off" ]) in
  assert_bool "grade reset" (not s.Store.grade_ok);
  assert_bool "verify reset" (not s.Store.verify_ok);
  assert_equal (Some "c2") s.Store.bound

let case_fold_clears_the_bound_commit_and_both_verdicts_on_resume _ =
  (* approved first, so both verdicts are set when the block lands *)
  let lines = [ edge ~commit:"c1" "handoff" "todo" "handed_off";
                edge ~verdict:"ship" ~verify:"pass" "grade" "handed_off" "approved";
                edge ~reason:"owner pause" "block" "approved" "blocked" ] in
  let before = fold (text lines) in
  assert_bool "verdicts still set while blocked" (before.Store.grade_ok && before.Store.verify_ok);
  let s = fold (text (lines @ [ edge ~cycle:2 "resume" "blocked" "todo" ])) in
  assert_bool "grade cleared on resume" (not s.Store.grade_ok);
  assert_bool "verify cleared on resume" (not s.Store.verify_ok);
  assert_equal None s.Store.bound;
  assert_bool "has_bound cleared" (not s.Store.has_bound);
  assert_equal 2 s.Store.cycle;
  assert_equal (Some "c1") s.Store.last_commit

let case_fold_clears_both_verdicts_on_needs_fix_even_with_a_passing_verify _ =
  let s = fold (text [ edge ~commit:"c1" "handoff" "todo" "handed_off";
                       edge ~cycle:2 ~verdict:"needs_fix" ~verify:"pass" "grade" "handed_off" "todo" ]) in
  assert_bool "grade not ok" (not s.Store.grade_ok);
  assert_bool "verify not ok" (not s.Store.verify_ok)

let case_fold_lets_a_failed_verify_edge_void_an_earlier_ship _ =
  let s = fold (text [ edge ~commit:"c1" "handoff" "todo" "handed_off";
                       edge ~verdict:"ship" "grade" "handed_off" "handed_off";
                       edge ~verdict:"fail" "verify" "handed_off" "handed_off" ]) in
  assert_bool "ship voided" (not s.Store.grade_ok);
  assert_bool "verify not ok" (not s.Store.verify_ok)

let case_fold_captures_reason_checkpoint_and_since_on_blocked _ =
  let s = fold (text [ edge ~reason:"owed: pick a budget" ~checkpoint:"cp1" ~ts:"2026-11-19T01:02:03Z"
                         "block" "todo" "blocked" ]) in
  assert_equal ~printer:Fun.id "owed: pick a budget" s.Store.blocked_reason;
  assert_equal (Some "cp1") s.Store.blocked_checkpoint;
  assert_equal ~printer:Fun.id "2026-11-19T01:02:03Z" s.Store.blocked_since

let case_fold_resets_both_verdicts_on_a_legacy_submit_like_a_handoff _ =
  let s = fold (text [ edge ~commit:"c1" "handoff" "todo" "handed_off";
                       edge ~verdict:"ship" ~verify:"pass" "grade" "handed_off" "approved";
                       edge ~cycle:2 ~commit:"c2" "submit" "approved" "submitted" ]) in
  assert_bool "a legacy submit resets grade" (not s.Store.grade_ok);
  assert_bool "a legacy submit resets verify" (not s.Store.verify_ok);
  assert_equal ~printer:Fun.id "handed_off" s.Store.st

let case_fold_clears_both_verdicts_on_a_ship_cast_whose_verify_failed _ =
  let s = fold (text [ edge ~commit:"c1" "handoff" "todo" "handed_off";
                       edge ~verdict:"ship" ~verify:"fail" "grade" "handed_off" "handed_off" ]) in
  assert_bool "grade not ok" (not s.Store.grade_ok);
  assert_bool "verify not ok" (not s.Store.verify_ok)

let case_fold_reads_plan_types_from_pre_rename_create_keys _ =
  let (s, qt, _) = Store.fold_ledger (text [ line [ jstr "edge" "create"; jstr "to" "todo";
                                                     jstr "exp_type" "spike"; jstr "graph_type" "direct" ] ]) in
  assert_equal ~printer:Fun.id "spike" s.Store.node_type;
  assert_equal ~printer:Fun.id "direct" qt;
  let (s, qt, _) = Store.fold_ledger (text [ line [ jstr "edge" "create"; jstr "to" "todo";
                                                     jstr "node_type" "n"; jstr "exp_type" "old";
                                                     jstr "goal_type" "g"; jstr "graph_type" "old" ] ]) in
  assert_equal ~printer:Fun.id "n" s.Store.node_type;
  assert_equal ~printer:Fun.id "g" qt;
  let (s, _, _) = Store.fold_ledger (text [ line [ jstr "edge" "create"; jstr "to" "todo"; jstr "goal_type" "g2" ] ]) in
  assert_equal ~msg:"no node key: node_type falls back to the quest type" ~printer:Fun.id "g2" s.Store.node_type

let case_fold_reads_depends_on_with_legacy_exp_ids_as_node_ids _ =
  let (_, _, deps) = Store.fold_ledger (text [ edge ~deps:[ "exp-1-a"; "node-2-b" ] "create" "" "todo" ]) in
  assert_equal ~printer:(String.concat ",") [ "node-1-a"; "node-2-b" ] deps;
  let (_, _, deps) = Store.fold_ledger (text [ edge ~deps:[ "node-1-a" ] "create" "" "todo";
                                              edge ~deps:[ "node-3-c" ] "dep" "todo" "todo" ]) in
  assert_equal ~printer:(String.concat ",") [ "node-3-c" ] deps

let char_fold_moves_state_on_an_unknown_edge_that_carries_a_to_field _ =
  let s = fold (text [ edge "create" "" "todo"; edge "teleport" "todo" "landed" ]) in
  assert_equal ~printer:Fun.id "landed" s.Store.st

let char_fold_keeps_the_previous_cycle_when_cycle_is_not_an_int _ =
  let s = fold (text [ edge ~cycle:3 "create" "" "todo";
                       line [ jstr "edge" "handoff"; jstr "to" "handed_off"; jstr "cycle" "seven" ] ]) in
  assert_equal 3 s.Store.cycle

let char_fold_takes_the_cycle_from_an_event_line_that_carries_one _ =
  let s = fold (text [ edge ~cycle:2 "create" "" "todo";
                       line [ jstr "event" "usage_recorded"; jint "cycle" 5 ] ]) in
  assert_equal ~printer:string_of_int 5 s.Store.cycle;
  assert_equal ~printer:Fun.id "todo" s.Store.st

let char_fold_refuses_a_malformed_json_line_with_E_INVALID_PLAN _ =
  assert_equal ~printer:Fun.id "E_INVALID_PLAN"
    (verdict_code (fun () -> fold (text [ edge "create" "" "todo"; "{\"edge\": \"handoff\"" ])))

(* Every field but the cycle: event lines may carry a cycle (see the char_ above). *)
let observable (s : Store.node_state) =
  (s.st, s.bound, s.has_bound, s.grade_ok, s.verify_ok, s.blocked_reason,
   s.blocked_checkpoint, s.blocked_since, s.last_commit, s.node_type)

(* Raw-text laws (the NODE's generator split): bad lines, not just
   well-formed ones. A non-JSON line spliced in anywhere must refuse
   the ledger: a truncated real line (a proper prefix of a JSON object
   is never valid JSON) or plain garbage such as a merge marker. *)
let garbage = [ "x"; "}"; "<<<<<<< HEAD"; "======="; "{\"edge\": "; "{,}"; "nul"; "'{}'" ]

let law_fold_refuses_a_ledger_with_any_non_json_line_with_E_INVALID_PLAN =
  QCheck2.Test.make ~count:200 ~name:"law_fold_refuses_a_ledger_with_any_non_json_line_with_E_INVALID_PLAN"
    ~print:(fun (b, i, p) -> text b ^ Printf.sprintf "--- bad line %d at %d" i p)
    QCheck2.Gen.(triple fsm_walk nat nat)
    (fun (base, i, p) ->
      let src = List.nth base (i mod List.length base) in
      let bad = if p mod 3 = 0 then List.nth garbage (p mod List.length garbage)
        else String.sub src 0 (1 + p mod (String.length src - 1)) in
      let at = i mod (List.length base + 1) in
      let lines = List.filteri (fun k _ -> k < at) base @ [ bad ] @ List.filteri (fun k _ -> k >= at) base in
      verdict_code (fun () -> fold (text lines)) = "E_INVALID_PLAN")

(* A field of the wrong type reads exactly as if it were absent. *)
let wrong_typed = [ ("edge", `Int 7); ("to", `List []); ("cycle", `String "seven");
                    ("commit", `Int 1); ("verdict", `Assoc []); ("verify_verdict", `Int 0);
                    ("reason", `Null); ("depends_on", `String "a") ]

let law_fold_reads_a_wrong_typed_field_as_if_it_were_absent =
  QCheck2.Test.make ~count:200 ~name:"law_fold_reads_a_wrong_typed_field_as_if_it_were_absent"
    ~print:(fun (b, picks) -> text b ^ "--- corrupt " ^ String.concat "," (List.map string_of_int picks))
    QCheck2.Gen.(pair fsm_walk (list_size (int_range 1 6) nat))
    (fun (base, picks) ->
      let rewrite f l = match Yojson.Safe.from_string l with
        | `Assoc fs -> Yojson.Safe.to_string (`Assoc (f fs)) | j -> Yojson.Safe.to_string j in
      let corrupt = ref base and absent = ref base in
      List.iter (fun p ->
          let i = p mod List.length base and (k, v) = List.nth wrong_typed (p mod List.length wrong_typed) in
          let on f = List.mapi (fun n l -> if n = i then rewrite f l else l) in
          corrupt := on (fun fs -> (k, v) :: List.remove_assoc k fs) !corrupt;
          absent := on (fun fs -> List.remove_assoc k fs) !absent) picks;
      let (a, qa, da) = Store.fold_ledger (text !corrupt) and (b, qb, db) = Store.fold_ledger (text !absent) in
      observable a = observable b && a.Store.cycle = b.Store.cycle && qa = qb && da = db)

let law_fold_ignores_event_lines_spliced_anywhere_in_a_ledger =
  QCheck2.Test.make ~count:200 ~name:"law_fold_ignores_event_lines_spliced_anywhere_in_a_ledger"
    ~print:(fun (b, e, _) -> text b ^ "--- events ---\n" ^ text e)
    QCheck2.Gen.(triple fsm_walk (list_size (int_range 1 4) event_line) (list_size (return 4) nat))
    (fun (base, events, pos) ->
      let pos = List.filteri (fun i _ -> i < List.length events) pos in
      let spliced = splice base events pos in
      let (a, qa, da) = Store.fold_ledger (text base) and (b, qb, db) = Store.fold_ledger (text spliced) in
      observable a = observable b && qa = qb && da = db)

(* ---------- ledger lines ---------- *)

let fixed_id run_id = { Store.harness = "muse-code"; model = "m-1"; decider = Store.Agent; decider_human = false; incomplete = false; run_id }

let decode l = Yojson.Safe.from_string l
let field j k = Yojson.Safe.Util.member k j

let case_ledger_line_writes_null_commit_and_verdict_when_absent _ =
  let l = Clock.with_fixed 1_795_000_000. (fun () ->
      Store.ledger_line ~edge:"create" ~from:"" ~to_:"todo" ~cycle:1 ~commit:None ~verdict:None
        ~reason:"c" ~id:(fixed_id None) ()) in
  let j = decode l in
  assert_equal `Null (field j "commit");
  assert_equal `Null (field j "verdict");
  assert_equal (`String "2026-11-18T11:06:40Z") (field j "ts");
  assert_equal `Null (field j "run_id")

(* Extra fields use keys the base line never writes. *)
let gen_extra =
  QCheck2.Gen.(list_size (int_range 0 3)
                 (pair (map (fun s -> "x_" ^ s) (string_size ~gen:(char_range 'a' 'z') (int_range 1 6)))
                       (string_size ~gen:printable (int_range 0 8))))

let gen_ledger_fields =
  let open QCheck2.Gen in
  let any_string = string_size ~gen:(char_range '\000' '\255') (int_range 0 30) in
  let pick xs = oneof [ oneof_list xs; any_string ] in
  pair (tup9 (pick [ "create"; "handoff"; "grade"; "verify"; "land"; "block"; "resume"; "" ])
    (pick [ "todo"; "handed_off"; "approved"; "blocked"; "landed" ])
    (pick [ "todo"; "handed_off"; "approved"; "blocked"; "landed" ])
    (int_range (-3) 1000)
    (option (oneof [ hex; return ""; any_string ]))
    (option (pick [ "ship"; "needs_fix"; "pass"; "fail" ]))
    any_string (pair any_string any_string) (option any_string)) (pair (option any_string) gen_extra)

let law_ledger_line_decodes_back_to_the_same_fields_it_encoded =
  QCheck2.Test.make ~count:300 ~name:"law_ledger_line_decodes_back_to_the_same_fields_it_encoded"
    gen_ledger_fields
    (fun ((e, from, to_, cycle, commit, verdict, reason, (harness, model), run_id), (checkpoint, extra)) ->
      let extra = List.sort_uniq (fun (a, _) (b, _) -> compare a b) extra in
      let id = { Store.harness; model; decider = Store.Agent; decider_human = false; incomplete = false; run_id } in
      let l = Clock.with_fixed 1_795_000_000. (fun () ->
          Store.ledger_line ~edge:e ~from ~to_ ~cycle ~commit ~verdict ~reason ~id ?checkpoint
            ~extra:(List.map (fun (k, v) -> (k, `String v)) extra) ()) in
      let j = decode l in
      let s k = match field j k with `String v -> Some v | _ -> None in
      not (String.contains l '\n')
      && s "edge" = Some e && s "from" = Some from && s "to" = Some to_
      && field j "cycle" = `Int cycle && s "commit" = commit && s "verdict" = verdict
      && s "reason" = Some reason && s "harness" = Some harness && s "model" = Some model
      && s "run_id" = run_id && s "checkpoint" = checkpoint && s "ts" = Some "2026-11-18T11:06:40Z"
      && List.for_all (fun (k, v) -> s k = Some v) extra
      && s "bp3_version" = Some Gitx.bp3_version)

(* ---------- legal edges, slugs, ids ---------- *)

let case_legal_edges_name_the_moves_each_state_allows _ =
  List.iter (fun (st, want) ->
      assert_equal ~msg:st ~printer:(String.concat ",") want (Store.legal_edges st))
    [ ("todo", [ "handoff"; "block"; "delete" ]);
      ("handed_off", [ "grade"; "block"; "delete" ]);
      ("approved", [ "land"; "block"; "delete" ]);
      ("blocked", [ "resume"; "delete" ]);
      ("landed", []); ("deleted", []); ("submitted", []) ]

let case_valid_slug_accepts_lowercase_kebab_and_refuses_everything_else _ =
  List.iter (fun (s, ok) -> assert_equal ~msg:(Printf.sprintf "%S" s) ok (Store.valid_slug s))
    [ ("a", true); ("0-day", true); ("2026-11-18-test-pyramid", true); ("a--b-", true);
      ("", false); ("-a", false); ("A", false); ("a_b", false); ("a.b", false); ("a b", false); ("é", false) ]

let case_check_slug_refuses_an_invalid_slug_with_E_USAGE _ =
  assert_equal ~printer:Fun.id "E_USAGE" (verdict_code (fun () -> Store.check_slug "Bad/Slug"));
  assert_equal ~printer:Fun.id "no verdict" (verdict_code (fun () -> Store.check_slug "good-slug"))

let case_check_creatable_refuses_a_reserved_door_slug_with_E_USAGE _ =
  assert_equal ~printer:Fun.id "E_USAGE" (verdict_code (fun () -> Store.check_creatable "warden"));
  assert_equal ~printer:Fun.id "no verdict" (verdict_code (fun () -> Store.check_creatable "wardens"))

let case_canon_node_id_maps_exp_ids_and_leaves_other_ids_alone _ =
  assert_equal ~printer:Fun.id "node-3-fsm" (Store.canon_node_id "exp-3-fsm");
  assert_equal ~printer:Fun.id "node-3-fsm" (Store.canon_node_id "node-3-fsm");
  assert_equal ~printer:Fun.id "e1" (Store.canon_node_id "e1")

let law_canon_node_id_undoes_legacy_node_id_for_every_node_id =
  QCheck2.Test.make ~count:200 ~name:"law_canon_node_id_undoes_legacy_node_id_for_every_node_id" ~print:Fun.id
    QCheck2.Gen.(map (fun s -> "node-" ^ s) (string_size ~gen:slug_char (int_range 0 20)))
    (fun id -> Store.legacy_node_id id <> id && Store.canon_node_id (Store.legacy_node_id id) = id)

(* ---------- versions ---------- *)

let case_parse_version_reads_dotted_numbers_and_falls_back_to_zero _ =
  assert_equal [ 0; 2; 0 ] (Store.parse_version "0.2.0");
  assert_equal [ 1; 10 ] (Store.parse_version "1.10");
  assert_equal [ 0 ] (Store.parse_version "v1");
  assert_equal ~printer:string_of_int 1 (Store.version_major "1.4.2")

let case_version_cmp_orders_numerically_and_pads_missing_parts_with_zero _ =
  let c a b = Store.version_cmp (Store.parse_version a) (Store.parse_version b) in
  assert_bool "1.10 > 1.9" (c "1.10" "1.9" > 0);
  assert_equal 0 (c "1" "1.0.0");
  assert_bool "0.2.0 < 0.2.1" (c "0.2.0" "0.2.1" < 0)

let gen_version = QCheck2.Gen.(list_size (int_range 0 4) (int_range 0 3))
let pad n v = v @ List.init (max 0 (n - List.length v)) (fun _ -> 0)
let sign x = compare x 0

let law_version_cmp_agrees_with_numeric_order_after_zero_padding =
  QCheck2.Test.make ~count:500 ~name:"law_version_cmp_agrees_with_numeric_order_after_zero_padding"
    ~print:(fun (a, b) -> String.concat "." (List.map string_of_int a) ^ " vs " ^ String.concat "." (List.map string_of_int b))
    QCheck2.Gen.(pair gen_version gen_version)
    (fun (a, b) ->
      let n = max (List.length a) (List.length b) in
      sign (Store.version_cmp a b) = sign (compare (pad n a) (pad n b)))

let law_version_cmp_is_a_total_order =
  QCheck2.Test.make ~count:500 ~name:"law_version_cmp_is_a_total_order"
    QCheck2.Gen.(triple gen_version gen_version gen_version)
    (fun (a, b, c) ->
      let ( <=. ) x y = Store.version_cmp x y <= 0 in
      Store.version_cmp a a = 0
      && sign (Store.version_cmp a b) = - (sign (Store.version_cmp b a))
      && (not (a <=. b && b <=. c) || a <=. c))

(* ---------- schedule ---------- *)

let node id st deps = { Store.n_id = id; n_state = st; n_deps = deps }

(* A random DAG over every node state: node i depends only on
   lower-numbered nodes, so deps can be done (landed, deleted), still
   waiting (todo), or in flight (handed_off, approved, blocked). *)
let gen_dag =
  let open QCheck2.Gen in
  int_range 1 8 >>= fun n ->
  let id i = Printf.sprintf "n%d" i in
  let one i =
    map2 (fun st mask -> node (id i) st (List.filteri (fun j _ -> j < i && mask land (1 lsl j) <> 0) (List.init n id)))
      (oneof_list_weighted [ (6, "todo"); (2, "landed"); (1, "deleted"); (1, "handed_off");
                             (1, "approved"); (1, "blocked") ]) (int_bound 255) in
  flatten_list (List.init n one)

let print_dag ns =
  String.concat " " (List.map (fun n -> n.Store.n_id ^ ":" ^ n.Store.n_state ^ "<-[" ^ String.concat "," n.Store.n_deps ^ "]") ns)

(* A todo node can be scheduled iff each dep is done (landed or
   deleted) or is itself a todo node that can be scheduled; a dep in
   flight holds back it and everything behind it. *)
let law_sched_waves_place_every_dep_in_an_earlier_wave =
  QCheck2.Test.make ~count:500 ~name:"law_sched_waves_place_every_dep_in_an_earlier_wave"
    ~print:print_dag gen_dag
    (fun nodes ->
      let waves = Store.sched_waves nodes in
      let wave_of id = let rec go k = function [] -> None | w :: r -> if List.mem id w then Some k else go (k + 1) r in go 0 waves in
      let find id = List.find_opt (fun n -> n.Store.n_id = id) nodes in
      let is_done id = match find id with Some n -> n.Store.n_state = "landed" || n.Store.n_state = "deleted" | None -> false in
      let rec placeable id = match find id with
        | Some n when n.Store.n_state = "todo" ->
            List.for_all (fun d -> is_done d || placeable d) n.Store.n_deps
        | _ -> false in
      let todo = List.filter (fun n -> n.Store.n_state = "todo") nodes in
      List.for_all (fun w -> w <> []) waves
      && List.for_all (fun id -> match find id with Some n -> n.Store.n_state = "todo" | None -> false) (List.concat waves)
      && List.for_all (fun n ->
             match wave_of n.Store.n_id with
             | None -> not (placeable n.Store.n_id)
             | Some k ->
                 placeable n.Store.n_id
                 && List.for_all (fun d -> is_done d || (match wave_of d with Some k' -> k' < k | None -> false)) n.Store.n_deps)
           todo)

let case_sched_waves_count_landed_deps_as_done _ =
  let ns = [ node "a" "landed" []; node "b" "todo" [ "a" ]; node "c" "todo" [ "b" ]; node "d" "todo" [] ] in
  assert_equal [ [ "b"; "d" ]; [ "c" ] ] (Store.sched_waves ns)

let case_sched_waves_count_a_deleted_dep_as_done_and_hold_back_an_in_flight_one _ =
  let ns = [ node "x" "deleted" []; node "y" "handed_off" []; node "a" "todo" [ "x" ];
             node "b" "todo" [ "y" ]; node "c" "todo" [ "a"; "b" ] ] in
  assert_equal [ [ "a" ] ] (Store.sched_waves ns)

let case_sched_waves_sort_each_wave_and_never_place_a_node_with_a_dangling_dep _ =
  let ns = [ node "zeta" "todo" []; node "alpha" "todo" []; node "orphan" "todo" [ "ghost" ] ] in
  assert_equal [ [ "alpha"; "zeta" ] ] (Store.sched_waves ns)

let case_sched_starved_names_the_todo_dependents_of_a_blocked_node _ =
  let ns = [ node "a" "blocked" []; node "b" "todo" [ "a" ]; node "c" "todo" [ "b" ];
             node "d" "landed" [ "a" ]; node "e" "todo" []; node "f" "handed_off" [ "a" ] ] in
  assert_equal [ ("a", [ "b"; "c" ]) ] (Store.sched_starved ns)

let case_dep_cycle_through_names_the_cycle_it_closes _ =
  let q = [ ("a", [ "b" ]); ("b", [ "a" ]); ("c", [ "a" ]) ] in
  assert_equal (Some [ "a"; "b"; "a" ]) (Store.dep_cycle_through q "a");
  assert_equal None (Store.dep_cycle_through q "c")

let case_missing_ancestors_flags_only_diverged_landed_deps_with_commits _ =
  let deps_map = [
    ("landed-ok", ("landed", Some "sha-a"));
    ("landed-stale", ("landed", Some "sha-b"));
    ("landed-nocommit", ("landed", None));
    ("deleted-dep", ("deleted", Some "sha-del"));
    ("todo-dep", ("todo", Some "sha-todo"));
  ] in
  let fold_dep d = List.assoc_opt d deps_map in
  let is_ancestor anc desc = (anc = "sha-a" && desc = "sha-head") in
  let got = Store.missing_ancestors ~is_ancestor ~fold_dep
    [ "landed-ok"; "landed-stale"; "landed-nocommit"; "deleted-dep"; "todo-dep"; "unknown" ] "sha-head" in
  assert_equal [ ("landed-stale", "sha-b") ] got;
  let got_all_ok = Store.missing_ancestors ~is_ancestor:(fun _ _ -> true) ~fold_dep
    [ "landed-ok"; "landed-stale" ] "sha-head" in
  assert_equal [] got_all_ok

let law_missing_ancestors_never_flags_deleted_or_commitless_deps =
  QCheck2.Test.make ~count:200 ~name:"law_missing_ancestors_never_flags_deleted_or_commitless_deps"
    QCheck2.Gen.(list_size (int_range 0 6)
      (triple (oneof_list [ "a"; "b"; "c"; "d" ])
              (oneof_list [ "landed"; "deleted"; "todo"; "blocked" ])
              (option (oneof_list [ "c1"; "c2" ]))))
    (fun entries ->
      let entries = List.sort_uniq (fun (a, _, _) (b, _, _) -> String.compare a b) entries in
      let fold_dep d = List.find_map (fun (k, st, c) -> if k = d then Some (st, c) else None) entries in
      let deps = List.map (fun (k, _, _) -> k) entries in
      let got = Store.missing_ancestors ~is_ancestor:(fun _ _ -> false) ~fold_dep deps "head" in
      let want = List.filter_map (fun (k, st, c) ->
        match (st, c) with ("landed", Some sha) -> Some (k, sha) | _ -> None) entries in
      got = want)

let law_dep_cycle_through_finds_no_cycle_in_a_dag =
  QCheck2.Test.make ~count:200 ~name:"law_dep_cycle_through_finds_no_cycle_in_a_dag" gen_dag
    (fun nodes ->
      let q = List.map (fun n -> (n.Store.n_id, n.Store.n_deps)) nodes in
      List.for_all (fun (id, _) -> Store.dep_cycle_through q id = None) q)

(* ---------- dates and timing ---------- *)

let case_days_from_civil_matches_known_dates _ =
  (* expected values from Python's datetime, not from this code *)
  List.iter (fun ((y, m, d), want) ->
      assert_equal ~msg:(Printf.sprintf "%04d-%02d-%02d" y m d) ~printer:string_of_int want (Store.days_from_civil y m d))
    [ ((1970, 1, 1), 0); ((1969, 12, 31), -1); ((2000, 3, 1), 11017); ((2026, 11, 18), 20775);
      ((1600, 2, 29), -135081); ((2400, 12, 31), 157419) ]

let case_ts_epoch_parses_utc_timestamps_and_refuses_other_shapes _ =
  assert_equal (Some 1_795_000_000) (Store.ts_epoch "2026-11-18T11:06:40Z");
  assert_equal (Some 1_795_046_399) (Store.ts_epoch "2026-11-18T23:59:59Z");
  List.iter (fun s -> assert_equal ~msg:s None (Store.ts_epoch s))
    [ ""; "2026-11-18 11:06:40Z"; "2026-11-18T11:06:40"; "2026-11-18T11:06:40.5Z"; "yyyy-mm-ddThh:mm:ssZ";
      "2026/11/18T11:06:40Z"; "2026-11-18T11-06-40Z"; "2026-11-18T11:06:40+";
      (* one separator wrong at a time, and a trailing tail *)
      "2026x11-18T11:06:40Z"; "2026-11x18T11:06:40Z"; "2026-11-18T11x06:40Z"; "2026-11-18T11:06x40Z";
      "2026-11-18T11:06:40Zjunk" ]

let law_ts_epoch_reads_back_the_second_now_ts_wrote =
  QCheck2.Test.make ~count:300 ~name:"law_ts_epoch_reads_back_the_second_now_ts_wrote"
    ~print:string_of_float QCheck2.Gen.(float_range 0. 7.0e9)
    (fun t -> Store.ts_epoch (Clock.with_fixed t Gitx.now_ts) = Some (truncate t))

let case_timing_of_text_counts_the_first_handoff_and_reads_a_legacy_submit_as_one _ =
  let t = Store.timing_of_text (text [
      edge ~ts:"2026-11-18T00:00:00Z" "create" "" "todo";
      edge ~ts:"2026-11-18T00:02:00Z" ~commit:"c" "submit" "todo" "submitted";
      edge ~ts:"2026-11-18T00:03:00Z" ~cycle:2 ~verdict:"needs_fix" "grade" "submitted" "todo";
      edge ~ts:"2026-11-18T00:05:00Z" ~cycle:2 ~commit:"d" "handoff" "todo" "handed_off" ]) in
  assert_equal ~msg:"wait counts to the first (legacy) handoff" (Some 120) t.Store.t_wait;
  assert_equal None t.Store.t_wall

let case_timing_of_text_derives_wall_wait_and_dwell_from_timestamps _ =
  let t = Store.timing_of_text (text [
      edge ~ts:"2026-11-18T00:00:00Z" "create" "" "todo";
      edge ~ts:"2026-11-18T00:01:00Z" ~commit:"c" "handoff" "todo" "handed_off";
      edge ~ts:"2026-11-18T00:03:00Z" ~verdict:"ship" ~verify:"pass" "grade" "handed_off" "approved";
      edge ~ts:"2026-11-18T00:04:00Z" "land" "approved" "landed" ]) in
  assert_equal (Some 180) t.Store.t_wall;
  assert_equal (Some 60) t.Store.t_wait;
  assert_equal [ ("approved", 60); ("handed_off", 120); ("todo", 60) ] t.Store.t_dwell

(* ---------- icebox and plans ---------- *)

let case_parse_icebox_entry_reads_frontmatter_title_and_treats_null_promoted_as_none _ =
  let e = Store.parse_icebox_entry "2026-11-18-x"
      "---\ndate: 2026-11-18\nstatus: frozen\npromoted: null\n---\n\n# A frozen idea\n\nbody\n" in
  assert_equal ~printer:Fun.id "2026-11-18" e.Store.date;
  assert_equal ~printer:Fun.id "frozen" e.Store.status;
  assert_equal None e.Store.promoted;
  assert_equal ~printer:Fun.id "A frozen idea" e.Store.title;
  let bare = Store.parse_icebox_entry "s" "no frontmatter" in
  assert_equal ~printer:Fun.id "-" bare.Store.date

let case_icebox_matches_needs_every_term_case_insensitively _ =
  let e = Store.parse_icebox_entry "2026-11-18-sqlite-store" "---\n---\n# SQLite store\nruntime state off JSON\n" in
  assert_bool "both terms" (Store.icebox_matches e [ "sqlite"; "JSON" ]);
  assert_bool "one missing" (not (Store.icebox_matches e [ "sqlite"; "postgres" ]))

let default_plan = "goal_type: default\nmax_cycles: 1\ngrade:\n  required: true\nverify: required\n"

let case_plan_knobs_read_the_default_plan_as_one_round_grade_and_verify_required _ =
  let k = Store.plan_knobs_from_text default_plan in
  assert_equal ~printer:string_of_int 1 k.Store.max_cycles;
  assert_bool "grade" k.Store.grade_required;
  assert_bool "verify" k.Store.verify_required;
  let k = Store.plan_knobs_from_text "max_cycles: 3\ngrade:\n  required: false\nverify: optional\n" in
  assert_equal 3 k.Store.max_cycles;
  assert_bool "grade optional" (not k.Store.grade_required);
  assert_bool "verify optional" (not k.Store.verify_required)

let case_plan_knobs_refuse_stages_and_edges_keys_with_E_INVALID_PLAN _ =
  assert_equal ~printer:Fun.id "E_INVALID_PLAN" (verdict_code (fun () -> Store.plan_knobs_from_text "stages:\n  - a\n"));
  assert_equal ~printer:Fun.id "E_INVALID_PLAN" (verdict_code (fun () -> Store.plan_knobs_from_text "  edges: []\n"))

let case_plan_knobs_default_to_one_round_and_read_verify_none_as_optional _ =
  let k = Store.plan_knobs_from_text "grade:\n  required: true\nverify: none\n" in
  assert_equal ~printer:string_of_int 1 k.Store.max_cycles;
  assert_bool "verify none is optional" (not k.Store.verify_required);
  assert_bool "auto_land defaults true" k.Store.auto_land

let case_plan_knobs_parse_land_auto_and_manual _ =
  let k_default = Store.plan_knobs_from_text "goal_type: default\nmax_cycles: 10\ngrade:\n  required: true\n" in
  assert_bool "omitted land defaults to auto" k_default.Store.auto_land;
  let k_auto = Store.plan_knobs_from_text "goal_type: default\nland: auto\n" in
  assert_bool "explicit land: auto" k_auto.Store.auto_land;
  let k_manual = Store.plan_knobs_from_text "goal_type: default\nland: manual\n" in
  assert_bool "explicit land: manual" (not k_manual.Store.auto_land);
  let k_manual_nospace = Store.plan_knobs_from_text "goal_type: default\n  land:manual  \n" in
  assert_bool "land:manual without space" (not k_manual_nospace.Store.auto_land)

let case_fold_reads_two_edge_auto_land_and_timing _ =
  let lines = [
    edge ~ts:"2026-11-26T00:00:00Z" "create" "" "todo";
    edge ~ts:"2026-11-26T00:01:00Z" ~commit:"c1" "handoff" "todo" "handed_off";
    edge ~ts:"2026-11-26T00:03:00Z" ~verdict:"ship" "grade" "handed_off" "landed";
  ] in
  let s = fold (text lines) in
  assert_equal ~printer:Fun.id "landed" s.Store.st;
  assert_bool "grade_ok set on ship" s.Store.grade_ok;
  assert_equal (Some "c1") s.Store.bound;
  let t = Store.timing_of_text (text lines) in
  assert_equal (Some 60) t.Store.t_wait;
  assert_equal (Some 120) t.Store.t_wall;
  assert_equal [ ("handed_off", 120); ("todo", 60) ] t.Store.t_dwell

let case_plan_knobs_scope_required_false_to_its_own_section _ =
  let k = Store.plan_knobs_from_text "grade:\n  required: true\nverify:\n  required: false\n" in
  assert_bool "grade stays required when only verify.required is false" k.Store.grade_required;
  assert_bool "verify becomes optional" (not k.Store.verify_required);
  let k2 = Store.plan_knobs_from_text "grade:\n  required: false # comment\nland:   manual # trailing\n" in
  assert_bool "grade.required false honored with comment" (not k2.Store.grade_required);
  assert_bool "land: manual honored with extra spaces and comment" (not k2.Store.auto_land)

let case_node_kind_roundtrip_and_legal_edges _ =
  List.iter (fun (s, k) ->
      assert_equal ~msg:s (Some k) (Store.node_kind_of_string s);
      assert_equal ~printer:Fun.id s (Store.node_kind_to_string k))
    [ ("code", Store.Code); ("direct", Store.Direct); ("research", Store.Research);
      ("explore", Store.Explore); ("human-gate", Store.Human_gate) ];
  assert_equal None (Store.node_kind_of_string "spike");
  assert_equal [ "approve"; "block"; "delete" ] (Store.legal_edges_for Store.Human_gate "todo");
  assert_equal [ "iterate"; "handoff"; "block"; "delete" ] (Store.legal_edges_for Store.Explore "todo");
  assert_equal [ "handoff"; "block"; "delete" ] (Store.legal_edges_for Store.Research "todo");
  assert_equal [ "handoff"; "block"; "delete" ] (Store.legal_edges_for Store.Direct "todo");
  assert_equal [] (Store.legal_edges_for Store.Human_gate "landed")

let case_decider_of_string_maps_human_and_yolo_and_defaults_agent _ =
  assert_equal Store.Human (Store.decider_of_string (Some "human"));
  assert_equal Store.Human_approved_llm_yolo (Store.decider_of_string (Some "human-approved-llm-yolo"));
  assert_equal Store.Agent (Store.decider_of_string (Some "yolo"));
  assert_equal Store.Agent (Store.decider_of_string None)

let case_protected_violations_blocks_locked_paths_unless_allowed _ =
  let bad = Store.protected_violations ~quest:"q1" ~node:"n1" ~allow_protected:false
    [ "src/quest/main.ml"; "GRADING.md"; "docs/quests/q1/nodes/n1/NODE.md"; "scripts/receipt" ] in
  assert_equal [ "GRADING.md"; "docs/quests/q1/nodes/n1/NODE.md"; "scripts/receipt" ] bad;
  let ok = Store.protected_violations ~quest:"q1" ~node:"n1" ~allow_protected:true
    [ "GRADING.md"; "CONSTRAINTS.md" ] in
  assert_equal [] ok;
  let clean = Store.protected_violations ~quest:"q1" ~node:"n1" ~allow_protected:false
    [ "src/quest/main.ml"; "docs/quests/q1/nodes/n2/NODE.md" ] in
  assert_equal [] clean

let case_fold_reads_node_kind_and_human_gate_yolo_approval _ =
  let (s_leg, _, _) = Store.fold_ledger (text [ line [ jstr "edge" "create"; jstr "to" "todo"; jstr "goal_type" "direct" ] ]) in
  assert_equal Store.Direct s_leg.Store.node_kind;
  let (s_gate, _, _) = Store.fold_ledger (text [
    line [ jstr "edge" "create"; jstr "to" "todo"; jstr "node_kind" "human-gate" ];
    line [ jstr "edge" "approve"; jstr "from" "todo"; jstr "to" "landed";
           jstr "decider" "human-approved-llm-yolo"; jstr "reason" "picked B" ] ]) in
  assert_equal Store.Human_gate s_gate.Store.node_kind;
  assert_equal "landed" s_gate.Store.st;
  assert_equal (Some "human-approved-llm-yolo") s_gate.Store.approved_decider;
  assert_equal "picked B" s_gate.Store.approved_reason

let case_doc_only_violations_enforces_docs_prefix_and_todo_node_md _ =
  let states = function
    | "d1" -> Some "landed"
    | "c2" -> Some "todo"
    | "r1" -> Some "todo"
    | _ -> None in
  assert_equal (Error (Names.e_doc_only_node, ["src/quest/main.ml"]))
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:true ["docs/quests/demo/research/r1/REPORT.md"; "src/quest/main.ml"]);
  assert_equal (Error (Names.e_doc_only_node, ["GRADING.md"]))
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:false ["GRADING.md"]);
  assert_equal (Error (Names.e_protected_file, ["docs/quests/demo/nodes/r1/NODE.md"]))
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:false ["docs/quests/demo/nodes/r1/NODE.md"]);
  assert_equal (Error (Names.e_protected_file, ["docs/quests/demo/nodes/d1/NODE.md"]))
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:false ["docs/quests/demo/nodes/d1/NODE.md"]);
  assert_equal (Error (Names.e_protected_file, ["docs/quests/demo/nodes/unknown/NODE.md"]))
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:false ["docs/quests/demo/nodes/unknown/NODE.md"]);
  assert_equal (Ok ())
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:false
       ["docs/quests/demo/research/r1/REPORT.md"; "docs/quests/demo/QUEST.md";
        "docs/quests/demo/nodes/c2/NODE.md"]);
  assert_equal (Ok ())
    (Store.doc_only_violations ~quest:"demo" ~self_node:"r1" ~node_state_of:states
       ~allow_protected:true ["docs/quests/demo/nodes/d1/NODE.md"])

let case_fold_reads_explore_target_max_iterations_iterate_count_and_outcome _ =
  let (s, _, _) = Store.fold_ledger (text [
    line [ jstr "edge" "create"; jstr "to" "todo"; jstr "node_kind" "explore";
           jstr "target" "make check < 10s"; ("max_iterations", `Int 2) ];
    line [ jstr "edge" "iterate"; jstr "from" "todo"; jstr "to" "todo"; jstr "reason" "run 1: 14.2s" ];
    line [ jstr "edge" "iterate"; jstr "from" "todo"; jstr "to" "todo"; jstr "reason" "run 2: 8.7s" ];
    line [ jstr "edge" "handoff"; jstr "from" "todo"; jstr "to" "landed";
           jstr "commit" "abc1234"; jstr "outcome" "hit"; jstr "reason" "8.7s verified" ] ]) in
  assert_equal Store.Explore s.Store.node_kind;
  assert_equal (Some "make check < 10s") s.Store.explore_target;
  assert_equal (Some 2) s.Store.explore_max_iterations;
  assert_equal 2 s.Store.explore_iterations;
  assert_equal (Some "hit") s.Store.explore_outcome;
  assert_equal "landed" s.Store.st

(* ---------- the longest-copy rule ---------- *)

let case_pick_longest_keeps_the_copy_with_the_most_lines _ =
  assert_equal ("a\nb\nc", "old/l") (Store.pick_longest "canon/l" [ ("canon/l", "a\nb"); ("old/l", "a\nb\nc") ])

let case_pick_longest_breaks_a_tie_in_favor_of_the_earlier_canonical_copy _ =
  assert_equal ("x\ny", "canon/l") (Store.pick_longest "canon/l" [ ("canon/l", "x\ny"); ("old/l", "a\nb") ])

let case_pick_longest_reads_no_copy_as_empty_at_the_canonical_path _ =
  assert_equal ("", "canon/l") (Store.pick_longest "canon/l" [])

let char_pick_longest_counts_an_empty_copy_as_one_line _ =
  assert_equal ("", "canon/l") (Store.pick_longest "canon/l" [ ("canon/l", ""); ("old/l", "one line") ])

let law_pick_longest_returns_a_found_copy_no_shorter_than_any_other =
  let lines t = List.length (String.split_on_char '\n' (String.trim t)) in
  QCheck2.Test.make ~count:300 ~name:"law_pick_longest_returns_a_found_copy_no_shorter_than_any_other"
    QCheck2.Gen.(list_size (int_range 1 5)
                   (pair (map (Printf.sprintf "p%d") (int_range 0 9))
                         (map (String.concat "\n") (list_size (int_range 0 6) (oneof_list [ "{}"; "x"; "" ])))))
    (fun found ->
      let (t, p) = Store.pick_longest "canon" found in
      List.mem (p, t) found
      && List.for_all (fun (_, t') -> lines t' <= lines t) found
      && (let first_max = List.find (fun (_, t') -> lines t' = lines t) found in first_max = (p, t)))

(* ---------- samples: real ledgers, one per era ---------- *)

let case_fold_reads_the_exp_era_sample_with_submitted_edges_as_landed_in_cycle_1 _ =
  let s = fold (read_sample "exp-era.ledger.jsonl") in
  assert_equal ~printer:Fun.id "landed" s.Store.st;
  assert_equal 1 s.Store.cycle;
  assert_bool "review+check folded as grade+verify" (s.Store.grade_ok && s.Store.verify_ok)

let case_fold_reads_the_graph_era_sample_as_landed_after_four_cycles _ =
  let s = fold (read_sample "graph-era.ledger.jsonl") in
  assert_equal ~printer:Fun.id "landed" s.Store.st;
  assert_equal ~printer:string_of_int 4 s.Store.cycle;
  assert_bool "final combined cast" (s.Store.grade_ok && s.Store.verify_ok)

let case_fold_reads_the_quest_era_sample_as_landed_in_cycle_1 _ =
  let s = fold (read_sample "quest-era.ledger.jsonl") in
  assert_equal ~printer:Fun.id "landed" s.Store.st;
  assert_equal 1 s.Store.cycle;
  assert_equal (Some "e9c2ce3cb4ef0134be55a97156b2024712f9a13b") s.Store.bound

let () =
  run_test_tt_main
    ("store" >::: [
       "case_fold_walks_create_handoff_grade_land_one_prefix_at_a_time" >:: case_fold_walks_create_handoff_grade_land_one_prefix_at_a_time;
       "case_fold_reads_a_legacy_submitted_line_as_handed_off" >:: case_fold_reads_a_legacy_submitted_line_as_handed_off;
       "case_fold_maps_legacy_review_and_check_edges_to_grade_and_verify" >:: case_fold_maps_legacy_review_and_check_edges_to_grade_and_verify;
       "case_fold_resets_both_verdicts_on_a_new_handoff" >:: case_fold_resets_both_verdicts_on_a_new_handoff;
       "case_fold_clears_the_bound_commit_and_both_verdicts_on_resume" >:: case_fold_clears_the_bound_commit_and_both_verdicts_on_resume;
       "case_fold_captures_reason_checkpoint_and_since_on_blocked" >:: case_fold_captures_reason_checkpoint_and_since_on_blocked;
       "case_fold_resets_both_verdicts_on_a_legacy_submit_like_a_handoff" >:: case_fold_resets_both_verdicts_on_a_legacy_submit_like_a_handoff;
       "case_fold_clears_both_verdicts_on_needs_fix_even_with_a_passing_verify" >:: case_fold_clears_both_verdicts_on_needs_fix_even_with_a_passing_verify;
       "case_fold_lets_a_failed_verify_edge_void_an_earlier_ship" >:: case_fold_lets_a_failed_verify_edge_void_an_earlier_ship;
       QCheck_ounit.to_ounit2_test law_fold_refuses_a_ledger_with_any_non_json_line_with_E_INVALID_PLAN;
       QCheck_ounit.to_ounit2_test law_fold_reads_a_wrong_typed_field_as_if_it_were_absent;
       "case_fold_clears_both_verdicts_on_a_ship_cast_whose_verify_failed" >:: case_fold_clears_both_verdicts_on_a_ship_cast_whose_verify_failed;
       "case_fold_reads_plan_types_from_pre_rename_create_keys" >:: case_fold_reads_plan_types_from_pre_rename_create_keys;
       "case_fold_reads_depends_on_with_legacy_exp_ids_as_node_ids" >:: case_fold_reads_depends_on_with_legacy_exp_ids_as_node_ids;
       "char_fold_moves_state_on_an_unknown_edge_that_carries_a_to_field" >:: char_fold_moves_state_on_an_unknown_edge_that_carries_a_to_field;
       "char_fold_keeps_the_previous_cycle_when_cycle_is_not_an_int" >:: char_fold_keeps_the_previous_cycle_when_cycle_is_not_an_int;
       "char_fold_takes_the_cycle_from_an_event_line_that_carries_one" >:: char_fold_takes_the_cycle_from_an_event_line_that_carries_one;
       "char_fold_refuses_a_malformed_json_line_with_E_INVALID_PLAN" >:: char_fold_refuses_a_malformed_json_line_with_E_INVALID_PLAN;
       QCheck_ounit.to_ounit2_test law_fold_ignores_event_lines_spliced_anywhere_in_a_ledger;
       "case_ledger_line_writes_null_commit_and_verdict_when_absent" >:: case_ledger_line_writes_null_commit_and_verdict_when_absent;
       QCheck_ounit.to_ounit2_test law_ledger_line_decodes_back_to_the_same_fields_it_encoded;
       "case_legal_edges_name_the_moves_each_state_allows" >:: case_legal_edges_name_the_moves_each_state_allows;
       "case_valid_slug_accepts_lowercase_kebab_and_refuses_everything_else" >:: case_valid_slug_accepts_lowercase_kebab_and_refuses_everything_else;
       "case_check_slug_refuses_an_invalid_slug_with_E_USAGE" >:: case_check_slug_refuses_an_invalid_slug_with_E_USAGE;
       "case_check_creatable_refuses_a_reserved_door_slug_with_E_USAGE" >:: case_check_creatable_refuses_a_reserved_door_slug_with_E_USAGE;
       "case_canon_node_id_maps_exp_ids_and_leaves_other_ids_alone" >:: case_canon_node_id_maps_exp_ids_and_leaves_other_ids_alone;
       QCheck_ounit.to_ounit2_test law_canon_node_id_undoes_legacy_node_id_for_every_node_id;
       "case_parse_version_reads_dotted_numbers_and_falls_back_to_zero" >:: case_parse_version_reads_dotted_numbers_and_falls_back_to_zero;
       "case_version_cmp_orders_numerically_and_pads_missing_parts_with_zero" >:: case_version_cmp_orders_numerically_and_pads_missing_parts_with_zero;
       QCheck_ounit.to_ounit2_test law_version_cmp_agrees_with_numeric_order_after_zero_padding;
       QCheck_ounit.to_ounit2_test law_version_cmp_is_a_total_order;
       QCheck_ounit.to_ounit2_test law_sched_waves_place_every_dep_in_an_earlier_wave;
       "case_sched_waves_count_landed_deps_as_done" >:: case_sched_waves_count_landed_deps_as_done;
       "case_sched_waves_count_a_deleted_dep_as_done_and_hold_back_an_in_flight_one" >:: case_sched_waves_count_a_deleted_dep_as_done_and_hold_back_an_in_flight_one;
       "case_sched_waves_sort_each_wave_and_never_place_a_node_with_a_dangling_dep" >:: case_sched_waves_sort_each_wave_and_never_place_a_node_with_a_dangling_dep;
       "case_sched_starved_names_the_todo_dependents_of_a_blocked_node" >:: case_sched_starved_names_the_todo_dependents_of_a_blocked_node;
       "case_dep_cycle_through_names_the_cycle_it_closes" >:: case_dep_cycle_through_names_the_cycle_it_closes;
       "case_missing_ancestors_flags_only_diverged_landed_deps_with_commits" >:: case_missing_ancestors_flags_only_diverged_landed_deps_with_commits;
       QCheck_ounit.to_ounit2_test law_missing_ancestors_never_flags_deleted_or_commitless_deps;
       QCheck_ounit.to_ounit2_test law_dep_cycle_through_finds_no_cycle_in_a_dag;
       "case_days_from_civil_matches_known_dates" >:: case_days_from_civil_matches_known_dates;
       "case_ts_epoch_parses_utc_timestamps_and_refuses_other_shapes" >:: case_ts_epoch_parses_utc_timestamps_and_refuses_other_shapes;
       QCheck_ounit.to_ounit2_test law_ts_epoch_reads_back_the_second_now_ts_wrote;
       "case_timing_of_text_derives_wall_wait_and_dwell_from_timestamps" >:: case_timing_of_text_derives_wall_wait_and_dwell_from_timestamps;
       "case_timing_of_text_counts_the_first_handoff_and_reads_a_legacy_submit_as_one" >:: case_timing_of_text_counts_the_first_handoff_and_reads_a_legacy_submit_as_one;
       "case_parse_icebox_entry_reads_frontmatter_title_and_treats_null_promoted_as_none" >:: case_parse_icebox_entry_reads_frontmatter_title_and_treats_null_promoted_as_none;
       "case_icebox_matches_needs_every_term_case_insensitively" >:: case_icebox_matches_needs_every_term_case_insensitively;
       "case_plan_knobs_read_the_default_plan_as_one_round_grade_and_verify_required" >:: case_plan_knobs_read_the_default_plan_as_one_round_grade_and_verify_required;
       "case_plan_knobs_refuse_stages_and_edges_keys_with_E_INVALID_PLAN" >:: case_plan_knobs_refuse_stages_and_edges_keys_with_E_INVALID_PLAN;
       "case_plan_knobs_default_to_one_round_and_read_verify_none_as_optional" >:: case_plan_knobs_default_to_one_round_and_read_verify_none_as_optional;
       "case_plan_knobs_parse_land_auto_and_manual" >:: case_plan_knobs_parse_land_auto_and_manual;
       "case_fold_reads_two_edge_auto_land_and_timing" >:: case_fold_reads_two_edge_auto_land_and_timing;
       "case_plan_knobs_scope_required_false_to_its_own_section" >:: case_plan_knobs_scope_required_false_to_its_own_section;
       "case_node_kind_roundtrip_and_legal_edges" >:: case_node_kind_roundtrip_and_legal_edges;
       "case_decider_of_string_maps_human_and_yolo_and_defaults_agent" >:: case_decider_of_string_maps_human_and_yolo_and_defaults_agent;
       "case_protected_violations_blocks_locked_paths_unless_allowed" >:: case_protected_violations_blocks_locked_paths_unless_allowed;
       "case_fold_reads_node_kind_and_human_gate_yolo_approval" >:: case_fold_reads_node_kind_and_human_gate_yolo_approval;
       "case_doc_only_violations_enforces_docs_prefix_and_todo_node_md" >:: case_doc_only_violations_enforces_docs_prefix_and_todo_node_md;
       "case_fold_reads_explore_target_max_iterations_iterate_count_and_outcome" >:: case_fold_reads_explore_target_max_iterations_iterate_count_and_outcome;
       "case_pick_longest_keeps_the_copy_with_the_most_lines" >:: case_pick_longest_keeps_the_copy_with_the_most_lines;
       "case_pick_longest_breaks_a_tie_in_favor_of_the_earlier_canonical_copy" >:: case_pick_longest_breaks_a_tie_in_favor_of_the_earlier_canonical_copy;
       "case_pick_longest_reads_no_copy_as_empty_at_the_canonical_path" >:: case_pick_longest_reads_no_copy_as_empty_at_the_canonical_path;
       "char_pick_longest_counts_an_empty_copy_as_one_line" >:: char_pick_longest_counts_an_empty_copy_as_one_line;
       QCheck_ounit.to_ounit2_test law_pick_longest_returns_a_found_copy_no_shorter_than_any_other;
       "case_fold_reads_the_exp_era_sample_with_submitted_edges_as_landed_in_cycle_1" >:: case_fold_reads_the_exp_era_sample_with_submitted_edges_as_landed_in_cycle_1;
       "case_fold_reads_the_graph_era_sample_as_landed_after_four_cycles" >:: case_fold_reads_the_graph_era_sample_as_landed_after_four_cycles;
       "case_fold_reads_the_quest_era_sample_as_landed_in_cycle_1" >:: case_fold_reads_the_quest_era_sample_as_landed_in_cycle_1;
     ])
