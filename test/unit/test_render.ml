(* Render edges (test-pyramid unit.4): short commits, change counts,
   waves, and the ASCII and Mermaid diagrams against hand-written
   golden files (golden/README.md). Not here: render_table_quest and
   render_table_node print whole verdicts (fixture tier, g.sh). *)
open OUnit2

let read path = let ic = open_in_bin path in let s = really_input_string ic (in_channel_length ic) in close_in ic; s

let four_node : (string * Yojson.Safe.t) list =
  match Yojson.Safe.from_string {|{
    "quest": "q1", "rollup": "active",
    "nodes": [
      {"node": "node-a", "state": "landed", "cycle": 1, "fin": "node_fin", "deps": []},
      {"node": "node-b", "state": "blocked", "cycle": 2, "deps": ["node-a"]},
      {"node": "node-c", "state": "todo", "cycle": 1, "deps": ["node-b"]},
      {"node": "node-d", "state": "todo", "cycle": 1, "deps": ["node-a"]}],
    "ready_set_waves": [["node-d"]],
    "starved": [{"blocked": "node-b", "starved": ["node-c"]}]}|} with
  | `Assoc fs -> fs | _ -> assert false

let case_short_commit_keeps_seven_characters_and_dashes_a_missing_commit _ =
  List.iter (fun (c, want) -> assert_equal ~printer:Fun.id want (Render.short_commit c))
    [ (Some "e9c2ce3cb4ef0134be55a97156b2024712f9a13b", "e9c2ce3"); (Some "abc", "abc"); (None, "-") ]

let case_change_counts_tallies_added_updated_and_removed_paths _ =
  let j = Yojson.Safe.from_string {|[{"change":"+"},{"change":"u"},{"change":"u"},{"change":"-"},{"x":1}]|} in
  assert_equal ~printer:Fun.id "+1 u2 -1" (Render.change_counts j);
  assert_equal ~printer:Fun.id "?" (Render.change_counts `Null)

let case_diagram_waves_reads_each_wave_as_a_list_of_ids _ =
  assert_equal [ [ "node-d" ] ] (Render.diagram_waves four_node);
  assert_equal [] (Render.diagram_waves [])

let case_emit_ascii_draws_the_fixed_four_node_rollup _ =
  assert_equal ~printer:Fun.id (read "golden/four-node.txt") (Render.emit_ascii four_node "2026-11-19T00:00:00Z")

let case_emit_mermaid_draws_the_fixed_four_node_rollup _ =
  assert_equal ~printer:Fun.id (read "golden/four-node.mmd") (Render.emit_mermaid four_node "2026-11-19T00:00:00Z")

let case_emit_ascii_writes_none_for_every_empty_section _ =
  let s = Render.emit_ascii [ ("quest", `String "q0"); ("rollup", `String "proposed") ] "T" in
  assert_equal ~printer:Fun.id
    "quest q0 diagram (generated from live state at T)\nrollup: proposed\nnodes:\n  (none)\ndeps:\n  (none)\nwaves:\n  (none)\nstarved:\n  (none)\n" s

let () =
  run_test_tt_main
    ("render" >::: [
       "case_short_commit_keeps_seven_characters_and_dashes_a_missing_commit" >:: case_short_commit_keeps_seven_characters_and_dashes_a_missing_commit;
       "case_change_counts_tallies_added_updated_and_removed_paths" >:: case_change_counts_tallies_added_updated_and_removed_paths;
       "case_diagram_waves_reads_each_wave_as_a_list_of_ids" >:: case_diagram_waves_reads_each_wave_as_a_list_of_ids;
       "case_emit_ascii_draws_the_fixed_four_node_rollup" >:: case_emit_ascii_draws_the_fixed_four_node_rollup;
       "case_emit_mermaid_draws_the_fixed_four_node_rollup" >:: case_emit_mermaid_draws_the_fixed_four_node_rollup;
       "case_emit_ascii_writes_none_for_every_empty_section" >:: case_emit_ascii_writes_none_for_every_empty_section;
     ])
