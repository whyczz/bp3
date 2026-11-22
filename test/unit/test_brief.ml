(* The grader's cold brief (induct-inline-as-default brief.1): Brief.render
   is pure, so every part of the text is checked here from built inputs.
   The verb and its git reads are test/g.sh's. *)
open OUnit2

let sha = "abc1234def5678abc1234def5678abc1234def56"
let node_md = "---\nnode: x.1\n---\n\n# x.1\n\n## TL;DR\n\nsummary\n\n## Acceptance gates\n\n\ngate line one\n\n```text\n$ run it\n```\n\n\n## Diagram\n\nboxes\n"

let base = { Brief.quest = "q1"; node = "nd"; cycle = 1; commit = sha; node_md = Some node_md;
             grading = Some "# Grading\n\nRun `make check-full`.\n"; docs = [ "CLAUDE.md"; "CONSTRAINTS.md" ];
             prev = None; others = [] }

let has s sub = Claude_tx.contains s sub
let lines s = String.split_on_char '\n' s

let case_section_is_the_body_up_to_the_next_h2 _ =
  assert_equal ~printer:(Option.value ~default:"<none>")
    (Some "gate line one\n\n```text\n$ run it\n```") (Brief.section "Acceptance gates" node_md);
  assert_equal None (Brief.section "Acceptance gates" "# x\n\n## TL;DR\n\nno gates\n");
  assert_equal ~printer:(Option.value ~default:"<none>") (Some "last")
    (Brief.section "Tail" "## Tail\nlast\n")

let case_cycle_one_brief_holds_every_part_in_order _ =
  let b = Brief.render base in
  assert_equal ~printer:Fun.id ("Grade nd at abc1234 (full SHA " ^ sha ^ ") in quest q1, cycle 1.") (List.hd (lines b));
  let order = [ "You are a fresh, independent grader"; "Rules:"; "Read first:";
                "- docs/quests/q1/nodes/nd/NODE.md and docs/quests/q1/QUEST.md"; "- CLAUDE.md, CONSTRAINTS.md";
                "- `git show abc1234`"; "Acceptance gates (NODE.md at abc1234):\n\ngate line one";
                "Repo grading rules (GRADING.md at abc1234):\n\n# Grading\n\nRun `make check-full`.";
                "Final message, exactly this shape:"; "VERDICT: ship | needs_fix" ] in
  ignore (List.fold_left (fun from part ->
      match Claude_tx.find_from b from part with
      | Some i -> i + String.length part
      | None -> assert_failure ("missing or out of order: " ^ part)) 0 order);
  assert_bool "no Desk line without --desk" (not (has b "Desk:"));
  assert_bool "no previous round in cycle 1" (not (has b "Previous round"));
  assert_bool "the next section stays out" (not (has b "boxes"))

let case_desk_adds_one_line _ =
  let plain = Brief.render base and desked = Brief.render ~desk:"/d" base in
  let extra = List.filter (fun l -> not (List.mem l (lines plain))) (lines desked) in
  assert_equal ~printer:(String.concat "|") [ "Desk: /d (check that `git rev-parse HEAD` prints " ^ sha ^ ")" ] extra

let case_cycle_two_shows_the_range_and_other_nodes_never_a_reason _ =
  let b = Brief.render { base with cycle = 2; prev = Some "1111111aaaa"; others = [ ("3333333bbbb", "nd2") ] } in
  assert_bool "range" (has b "Previous round: 1111111 was graded needs_fix. Re-judge the gates in full; the change since is `git diff 1111111..abc1234`.");
  assert_bool "others" (has b "Other nodes' commits in that range: 3333333 (nd2).");
  let none = Brief.render { base with cycle = 2; prev = Some "1111111aaaa" } in
  assert_bool "none" (has none "Other nodes' commits in that range: none.")

let case_missing_files_are_named_not_hidden _ =
  let b = Brief.render { base with node_md = None; grading = None; docs = [] } in
  assert_bool "no NODE.md" (has b "(no NODE.md at abc1234: that is a finding)");
  assert_bool "no GRADING.md" (has b "No GRADING.md at abc1234: run the repo's documented test gate and name it.");
  assert_bool "no docs line" (not (has b "CLAUDE.md"));
  let ng = Brief.render { base with node_md = Some "# x\n\n## TL;DR\n\nt\n" } in
  assert_bool "no gates" (has ng "(NODE.md at abc1234 has no Acceptance gates section: that is a finding)")

(* Law: the gates part is the section verbatim, and the first line
   always carries the join key (node id and the commit's first 7). *)
let law_gates_verbatim_and_join_line =
  let open QCheck2.Gen in
  let word = string_size ~gen:(char_range 'a' 'z') (int_range 1 8) in
  let body = list_size (int_range 1 6) word >|= String.concat "\n" in
  QCheck2.Test.make ~count:300 ~name:"law_gates_verbatim_and_join_line"
    (triple body word (string_size ~gen:(char_range 'a' 'f') (return 40)))
    (fun (gates, node, commit) ->
       let md = "## TL;DR\n\nx\n\n## Acceptance gates\n\n" ^ gates ^ "\n\n## Diagram\n\ny\n" in
       let b = Brief.render { base with node; commit; node_md = Some md } in
       let first = List.hd (lines b) in
       Brief.section "Acceptance gates" md = Some gates
       && has b ("Acceptance gates (NODE.md at " ^ String.sub commit 0 7 ^ "):\n\n" ^ gates ^ "\n\n")
       && Claude_tx.prompt_names_grade first ~node ~commit)

let () =
  run_test_tt_main
    ("brief" >::: [
       "case_section_is_the_body_up_to_the_next_h2" >:: case_section_is_the_body_up_to_the_next_h2;
       "case_cycle_one_brief_holds_every_part_in_order" >:: case_cycle_one_brief_holds_every_part_in_order;
       "case_desk_adds_one_line" >:: case_desk_adds_one_line;
       "case_cycle_two_shows_the_range_and_other_nodes_never_a_reason" >:: case_cycle_two_shows_the_range_and_other_nodes_never_a_reason;
       "case_missing_files_are_named_not_hidden" >:: case_missing_files_are_named_not_hidden;
       QCheck_ounit.to_ounit2_test law_gates_verbatim_and_join_line;
     ])
