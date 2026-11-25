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
  eq ".bp3/worktrees" Layout.legacy_desks_root;
  eq ".bp3/desks" Layout.legacy_desks_meta_dir;
  eq "/d/bp3-01234567" (Layout.repo_desks_dir "/d/" "bp3-01234567");
  eq "/d/bp3-01234567/quests/q1" (Layout.quest_desk_dir "/d/bp3-01234567" "q1");
  eq "/d/bp3-01234567/runs/q1/node-2-x/R1" (Layout.run_desk_dir "/d/bp3-01234567" "q1" "node-2-x" "R1");
  eq "/d/bp3-01234567/.meta" (Layout.desks_meta_dir "/d/bp3-01234567")

let case_central_desks_base_and_repo_key _ =
  let eq = assert_equal ~printer:Fun.id in
  eq "bp3" (Layout.sanitize_repo_slug "bp3");
  eq "my-cool-app" (Layout.sanitize_repo_slug "  My_Cool.App!! ");
  eq "repo" (Layout.sanitize_repo_slug "...");
  eq "repo" (Layout.sanitize_repo_slug "");
  eq "/custom" (Layout.desks_base_of (Some "/custom/") (Some "/u/me"));
  eq "/u/me/.bp3/desks" (Layout.desks_base_of None (Some "/u/me/"));
  eq "/u/me/.bp3/desks" (Layout.desks_base_of (Some "") (Some "/u/me"));
  eq ".bp3/desks" (Layout.desks_base_of None None);
  let k1 = Layout.repo_key "bp3" "/a/bp3/.git" in
  let k2 = Layout.repo_key "bp3" "/b/bp3/.git" in
  assert_bool "same repo name in distinct dirs yields distinct repo_key" (k1 <> k2);
  eq k1 (Layout.repo_key "bp3" "/a/bp3/.git");
  assert_bool "repo_key starts with slug-" (String.starts_with ~prefix:"bp3-" k1);
  assert_equal ~printer:string_of_int (String.length "bp3-" + 8) (String.length k1)

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

let is_lower_hex c =
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')

let is_slug_char c =
  (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-'

let law_run_desk_never_nests_inside_quest_desk =
  QCheck2.Test.make ~count:200 ~name:"law_run_desk_never_nests_inside_quest_desk"
    ~print:(fun (q, n, r) -> Printf.sprintf "%s %s %s" q n r)
    QCheck2.Gen.(triple slug slug slug)
    (fun (q, n, r) ->
      let repo_dir = "/tmp/desks/bp3-01234567" in
      let qd = Layout.quest_desk_dir repo_dir q in
      let rd = Layout.run_desk_dir repo_dir q n r in
      rd <> qd
      && not (String.starts_with ~prefix:(qd ^ "/") rd)
      && not (String.starts_with ~prefix:(rd ^ "/") qd))

let any_ascii = QCheck2.Gen.(string_size ~gen:(char_range ' ' '~') (int_range 0 24))

let law_repo_key_matches_slug_dash_8hex =
  QCheck2.Test.make ~count:200 ~name:"law_repo_key_matches_slug_dash_8hex"
    ~print:(fun (name, common) -> Printf.sprintf "%S %S" name common)
    QCheck2.Gen.(pair any_ascii any_ascii)
    (fun (name, common) ->
      let k = Layout.repo_key name common in
      let len = String.length k in
      len >= 10
      && k.[len - 9] = '-'
      && (let slug_part = String.sub k 0 (len - 9) in
          let hex_part = String.sub k (len - 8) 8 in
          String.length slug_part >= 1
          && slug_part.[0] <> '-'
          && slug_part.[String.length slug_part - 1] <> '-'
          && String.for_all is_slug_char slug_part
          && String.for_all is_lower_hex hex_part))

let () =
  run_test_tt_main
    ("layout" >::: [
       "case_layout_derives_quest_node_ref_branch_and_desk_paths" >:: case_layout_derives_quest_node_ref_branch_and_desk_paths;
       "case_central_desks_base_and_repo_key" >:: case_central_desks_base_and_repo_key;
       "case_layout_names_the_legacy_ref_kinds_and_the_per_quest_files" >:: case_layout_names_the_legacy_ref_kinds_and_the_per_quest_files;
       "case_legacy_quest_ledger_paths_cover_the_graphs_and_goals_roots_only" >:: case_legacy_quest_ledger_paths_cover_the_graphs_and_goals_roots_only;
       QCheck_ounit.to_ounit2_test law_every_legacy_node_path_folds_to_its_canonical_id;
       QCheck_ounit.to_ounit2_test law_run_desk_never_nests_inside_quest_desk;
       QCheck_ounit.to_ounit2_test law_repo_key_matches_slug_dash_8hex;
     ])
