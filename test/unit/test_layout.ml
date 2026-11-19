(* Layout and legacy path units (test-pyramid unit.3): every path and
   ref the engine derives, and the legacy spellings it folds on read.
   case_ = named example, law_ = QCheck property. *)
open OUnit2

let case_layout_derives_quest_node_ref_branch_and_desk_paths _ =
  let eq = assert_equal ~printer:Fun.id in
  eq "docs/quests/q1" (Layout.quest_dir "q1");
  eq "docs/quests/q1/ledger.jsonl" (Store.quest_ledger_path "q1");
  eq "docs/quests/q1/nodes/node-2-x/ledger.jsonl" (Store.node_ledger_path "q1" "node-2-x");
  eq "docs/quests/q1/nodes/node-2-x/ledger.jsonl" (Store.node_ledger_path "q1" "exp-2-x");
  eq "refs/heads/bp3/quest/q1" (Layout.quest_ref_of Layout.quest_ref_kind "q1");
  eq "refs/heads/bp3/node/q1/" (Layout.node_ref_prefix_of Layout.node_ref_kind "q1");
  eq "bp3/node/q1/node-2-x" (Layout.node_branch_short "q1" "node-2-x");
  eq "quest/q1" (Layout.work_branch "q1");
  eq ".bp3/worktrees/q1" (Layout.desk_dir "q1")

let case_layout_names_the_legacy_ref_kinds_and_the_per_quest_files _ =
  assert_equal [ "graph"; "goal" ] Layout.legacy_quest_ref_kinds;
  assert_equal [ "exp" ] Layout.legacy_node_ref_kinds;
  assert_equal [ "experiments" ] Layout.legacy_nodes_dirs;
  List.iter (fun (got, want) -> assert_equal ~printer:Fun.id want got)
    [ (Layout.state_file, "state.yaml"); (Layout.runs_dir, "runs"); (Layout.context_file, ".bp3-context.json");
      (Layout.quest_file, "QUEST.md"); (Layout.ledger_file, "ledger.jsonl") ]

let case_legacy_quest_ledger_paths_cover_the_graphs_and_goals_roots_only _ =
  assert_equal ~printer:(String.concat " ")
    [ "docs/graphs/q1/ledger.jsonl"; "docs/goals/q1/ledger.jsonl" ] (Store.legacy_quest_ledger_paths "q1")

(* Split "<root...>/<q>/<dir>/<id>/ledger.jsonl" into (dir, id). *)
let dir_and_id path =
  match List.rev (String.split_on_char '/' path) with
  | "ledger.jsonl" :: id :: dir :: _ -> (dir, id)
  | _ -> ("", "")

let slug = QCheck2.Gen.(string_size ~gen:(oneof [ char_range 'a' 'z'; char_range '0' '9'; return '-' ]) (int_range 1 16))

let law_every_legacy_node_path_folds_to_its_canonical_id =
  QCheck2.Test.make ~count:200 ~name:"law_every_legacy_node_path_folds_to_its_canonical_id"
    ~print:(fun (q, s, legacy) -> Printf.sprintf "%s %s legacy=%b" q s legacy)
    QCheck2.Gen.(triple slug slug bool)
    (fun (q, s, legacy) ->
      let asked = (if legacy then "exp-" else "node-") ^ s in
      let canonical = Store.node_ledger_path q asked in
      let paths = Store.legacy_node_ledger_paths q asked in
      List.length paths = 11
      && not (List.mem canonical paths)
      && List.for_all (fun p ->
             let (dir, id) = dir_and_id p in
             List.mem dir (Layout.nodes_dir :: Layout.legacy_nodes_dirs)
             && Store.canon_node_id id = "node-" ^ s) paths)

let () =
  run_test_tt_main
    ("layout" >::: [
       "case_layout_derives_quest_node_ref_branch_and_desk_paths" >:: case_layout_derives_quest_node_ref_branch_and_desk_paths;
       "case_layout_names_the_legacy_ref_kinds_and_the_per_quest_files" >:: case_layout_names_the_legacy_ref_kinds_and_the_per_quest_files;
       "case_legacy_quest_ledger_paths_cover_the_graphs_and_goals_roots_only" >:: case_legacy_quest_ledger_paths_cover_the_graphs_and_goals_roots_only;
       QCheck_ounit.to_ounit2_test law_every_legacy_node_path_folds_to_its_canonical_id;
     ])
