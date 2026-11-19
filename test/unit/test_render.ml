(* Render edges (test-pyramid unit.4): short commits, change counts,
   waves, the ASCII and Mermaid diagrams, and the quest and node tables,
   against golden files derived independently of the code
   (golden/README.md). The tables print to stdout, so [capture] reads
   it back through a pipe; no file, git or process. *)
open OUnit2

let capture f =
  flush stdout;
  let (r, w) = Unix.pipe () in
  let saved = Unix.dup Unix.stdout in
  Unix.dup2 w Unix.stdout; Unix.close w;
  Fun.protect ~finally:(fun () -> flush stdout; Unix.dup2 saved Unix.stdout; Unix.close saved) f;
  let b = Buffer.create 256 and chunk = Bytes.create 4096 in
  let rec go () = let n = Unix.read r chunk 0 4096 in if n > 0 then (Buffer.add_subbytes b chunk 0 n; go ()) in
  go (); Unix.close r; Buffer.contents b

let assoc s = match Yojson.Safe.from_string s with `Assoc fs -> fs | _ -> assert false

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

let eight_node = assoc {|{
    "quest": "q2", "rollup": "active",
    "nodes": [
      {"node": "node-a", "state": "landed", "cycle": 1, "fin": "node_fin", "deps": []},
      {"node": "node-b", "state": "blocked", "cycle": 2, "deps": ["node-a"]},
      {"node": "node-c", "state": "todo", "cycle": 1, "deps": ["node-b"]},
      {"node": "node-d", "state": "todo", "cycle": 1, "deps": ["node-a"]},
      {"node": "node-e", "state": "todo", "cycle": 1, "deps": ["node-a", "node-d"]},
      {"node": "node-f", "state": "todo", "cycle": 1, "deps": ["node-b"]},
      {"node": "node-g", "state": "todo", "deps": []},
      {"node": "node-h", "state": "todo", "cycle": 1, "deps": ["node-g"]}],
    "ready_set_waves": [["node-d", "node-g"], ["node-e", "node-h"]],
    "starved": [{"blocked": "node-b", "starved": ["node-c", "node-f"]}]}|}

let case_emit_ascii_keeps_wave_dep_and_starved_order_in_a_richer_rollup _ =
  assert_equal ~printer:Fun.id (read "golden/eight-node.txt") (Render.emit_ascii eight_node "2026-11-19T00:00:00Z")

let case_emit_mermaid_keeps_wave_dep_and_starved_order_in_a_richer_rollup _ =
  assert_equal ~printer:Fun.id (read "golden/eight-node.mmd") (Render.emit_mermaid eight_node "2026-11-19T00:00:00Z")

let case_diagram_waves_reads_a_non_list_wave_as_one_id _ =
  assert_equal [ [ "x" ]; [ "a"; "b" ] ] (Render.diagram_waves (assoc {|{"ready_set_waves": ["x", ["a", "b"]]}|}))

let case_render_table_quest_prints_the_header_and_padded_node_rows _ =
  let fields = assoc {|{"quest": "q1", "state": "active", "rollup": "active", "ready": ["node-d", "node-e"],
    "nodes": [
      {"node": "node-a", "state": "landed", "cycle": 1, "commit": "e9c2ce3cb4ef0134be55a97156b2024712f9a13b",
       "changes": [{"change": "+"}, {"change": "u"}]},
      {"node": "node-b", "state": "blocked", "cycle": 2}]}|} in
  assert_equal ~printer:Fun.id (read "golden/table-quest.txt") (capture (fun () -> Render.render_table_quest fields))

let case_render_table_node_prints_the_summary_line_and_change_rows _ =
  let fields = assoc {|{"quest": "q1", "node": "node-a", "state": "approved", "cycle": 2,
    "commit": "e9c2ce3cb4ef0134be55a97156b2024712f9a13b", "legal_edges": ["land", "block", "delete"],
    "changes": [{"change": "+", "path": "src/a.ml"}, {"change": "u", "path": "test/b.sh"}]}|} in
  assert_equal ~printer:Fun.id (read "golden/table-node.txt") (capture (fun () -> Render.render_table_node fields))

let case_render_table_node_marks_missing_fields_none_dash_and_unknown _ =
  assert_equal ~printer:Fun.id "q1 / n — todo, cycle 0, commit -, legal: none\n? changes unknown\n"
    (capture (fun () -> Render.render_table_node (assoc {|{"quest": "q1", "node": "n", "state": "todo"}|})))

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
       "case_emit_ascii_keeps_wave_dep_and_starved_order_in_a_richer_rollup" >:: case_emit_ascii_keeps_wave_dep_and_starved_order_in_a_richer_rollup;
       "case_emit_mermaid_keeps_wave_dep_and_starved_order_in_a_richer_rollup" >:: case_emit_mermaid_keeps_wave_dep_and_starved_order_in_a_richer_rollup;
       "case_diagram_waves_reads_a_non_list_wave_as_one_id" >:: case_diagram_waves_reads_a_non_list_wave_as_one_id;
       "case_render_table_quest_prints_the_header_and_padded_node_rows" >:: case_render_table_quest_prints_the_header_and_padded_node_rows;
       "case_render_table_node_prints_the_summary_line_and_change_rows" >:: case_render_table_node_prints_the_summary_line_and_change_rows;
       "case_render_table_node_marks_missing_fields_none_dash_and_unknown" >:: case_render_table_node_marks_missing_fields_none_dash_and_unknown;
     ])
