(* Unit + QCheck2 tests for declarative quest.json v1 specs
   (declarative-json-quest-init spec.1, Ticket #12). *)
open OUnit2

let sample_valid = {|
{
  "version": 1,
  "quest": "2026-11-27-demo",
  "title": "Demo JSON quest",
  "tldr": "End-to-end declarative quest test",
  "goal_type": "default",
  "bump": "minor",
  "home_repo": "bp3",
  "depends_on": ["2026-11-23-dag-contracts"],
  "nodes": [
    {
      "id": "node-r-1-research",
      "node": "r.1",
      "title": "Research phase",
      "kind": "research",
      "lane": "micro",
      "depends_on": [],
      "intent": "Gather facts",
      "output": "docs/quests/2026-11-27-demo/research/r1/REPORT.md",
      "acceptance": {
        "objective": "Ground downstream spec",
        "prove_by": ["make check-full"],
        "done_when": "report landed",
        "trace": ["$ bp3 q demo n r1 e handoff -> landed"]
      }
    },
    {
      "id": "node-ex-1-probe",
      "node": "ex.1",
      "title": "Explore perf",
      "kind": "explore",
      "lane": "standard",
      "depends_on": ["node-r-1-research"],
      "target": "p99 < 50ms",
      "max_iterations": 2,
      "intent": "Benchmark prototype",
      "output": "docs/quests/2026-11-27-demo/explores/ex1/REPORT.md",
      "acceptance": {
        "objective": "Prove latency bound",
        "prove_by": ["bench.sh", "make check-full"],
        "done_when": "p99 < 50ms or missed reported"
      }
    },
    {
      "id": "node-g-1-gate",
      "node": "g.1",
      "title": "Pick approach",
      "kind": "human-gate",
      "depends_on": ["node-ex-1-probe"],
      "intent": "Owner picks A or B",
      "output": "ledger approval",
      "acceptance": {
        "objective": "Record choice",
        "prove_by": ["bp3 q r"],
        "done_when": "approved"
      }
    },
    {
      "id": "node-c-1-build",
      "node": "c.1",
      "title": "Build feature",
      "kind": "code",
      "depends_on": ["node-g-1-gate"],
      "intent": "Implement chosen approach",
      "output": "src/quest/feature.ml",
      "acceptance": {
        "objective": "Ship feature",
        "prove_by": ["make check-full"],
        "done_when": "all tests green"
      }
    }
  ]
}
|}

let has s sub = Claude_tx.contains s sub

let case_parse_valid_spec_and_render_acceptance _ =
  match Quest_spec.parse_string sample_valid with
  | Error es -> assert_failure ("unexpected errors: " ^ String.concat "; " es)
  | Ok spec ->
      assert_equal 1 spec.version;
      assert_equal "2026-11-27-demo" spec.quest;
      assert_equal "minor" spec.bump;
      assert_equal 4 (List.length spec.nodes);
      let ex = Option.get (Quest_spec.find_node spec "node-ex-1-probe") in
      assert_equal Store.Explore ex.kind;
      assert_equal (Some "p99 < 50ms") ex.target;
      assert_equal (Some 2) ex.max_iterations;
      let r1 = Option.get (Quest_spec.find_node spec "node-r-1-research") in
      let acc = Quest_spec.render_acceptance r1 in
      assert_bool "trace included" (has acc "Design trace:" && has acc "$ bp3 q demo n r1 e handoff -> landed");
      assert_bool "objective included" (has acc "- **objective:** Ground downstream spec");
      assert_bool "done_when included" (has acc "- **done when:** report landed")

let assert_invalid msg raw want_sub =
  match Quest_spec.parse_string raw with
  | Ok _ -> assert_failure (msg ^ ": expected Error, got Ok")
  | Error es ->
      let joined = String.concat "; " es in
      assert_bool (msg ^ ": got [" ^ joined ^ "] wanting [" ^ want_sub ^ "]") (has joined want_sub)

let case_parse_rejects_malformed_and_invalid_specs _ =
  assert_invalid "malformed" "{broken" "malformed JSON";
  assert_invalid "bad version" {|{"version":2,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[]}|} "unsupported spec version";
  assert_invalid "empty nodes" {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[]}|} "non-empty array";
  assert_invalid "bad bump" {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"huge","nodes":[]}|} "invalid bump";
  assert_invalid "reserved slug" {|{"version":1,"quest":"warden","title":"t","tldr":"x","bump":"patch","nodes":[]}|} "reserved slug";
  assert_invalid "explore missing target"
    {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[{"id":"ex1","title":"e","kind":"explore","intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}}]}|}
    "requires non-empty target";
  assert_invalid "explore bad max_iterations"
    {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[{"id":"ex1","title":"e","kind":"explore","target":"fast","max_iterations":0,"intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}}]}|}
    "positive integer";
  assert_invalid "duplicate id"
    {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[
       {"id":"n1","title":"1","intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}},
       {"id":"n1","title":"2","intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}}]}|}
    "duplicate node id";
  assert_invalid "unknown dep"
    {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[
       {"id":"n1","title":"1","depends_on":["ghost"],"intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}}]}|}
    "unknown node ghost";
  assert_invalid "cycle"
    {|{"version":1,"quest":"a","title":"t","tldr":"x","bump":"patch","nodes":[
       {"id":"n1","title":"1","depends_on":["n2"],"intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}},
       {"id":"n2","title":"2","depends_on":["n1"],"intent":"i","output":"o","acceptance":{"objective":"o","prove_by":["p"],"done_when":"d"}}]}|}
    "dependency cycle"

let case_json_diff_violations_allows_only_non_self_todo_node_edits _ =
  let states = function
    | "node-r-1-research" -> Some "todo"
    | "node-ex-1-probe" -> Some "landed"
    | "node-g-1-gate" -> Some "todo"
    | "node-c-1-build" -> Some "todo"
    | _ -> None in
  let check before after =
    Quest_spec.json_diff_violations ~quest:"2026-11-27-demo"
      ~self_node:"node-r-1-research" ~node_state_of:states
      ~before_json:(Some before) ~after_json:(Some after) in
  (* Editing downstream todo node c.1 is allowed *)
  let edit_todo = Str.global_replace (Str.regexp_string "Implement chosen approach") "Implement option B with tests" sample_valid in
  assert_equal (Ok ()) (check sample_valid edit_todo);
  (* Editing own node r.1 is refused *)
  let edit_self = Str.global_replace (Str.regexp_string "Gather facts") "Weaken own goal" sample_valid in
  assert_equal (Error ["docs/quests/2026-11-27-demo/quest.json"]) (check sample_valid edit_self);
  (* Editing already-landed node ex.1 is refused *)
  let edit_landed = Str.global_replace (Str.regexp_string "Benchmark prototype") "Rewrite landed history" sample_valid in
  assert_equal (Error ["docs/quests/2026-11-27-demo/quest.json"]) (check sample_valid edit_landed);
  (* Editing quest-level field (bump) is refused *)
  let edit_bump = Str.global_replace (Str.regexp_string {|"bump": "minor"|}) {|"bump": "major"|} sample_valid in
  assert_equal (Error ["docs/quests/2026-11-27-demo/quest.json"]) (check sample_valid edit_bump);
  (* Malformed after_json is refused *)
  assert_equal (Error ["docs/quests/2026-11-27-demo/quest.json"]) (check sample_valid "{broken")

let law_topo_sort_places_every_dep_before_dependent =
  let open QCheck2.Gen in
  let mk_node id deps =
    { Quest_spec.id; node = id; title = id; kind = Store.Code; lane = "standard";
      depends_on = deps; intent = "i"; output = "o";
      acceptance = { objective = "o"; prove_by = ["p"]; done_when = "d"; trace = [] };
      target = None; max_iterations = None } in
  let dag_gen =
    int_range 1 6 >>= fun n ->
    let ids = List.init n (fun i -> Printf.sprintf "n%d" i) in
    let dep_gens = List.mapi (fun i id ->
      let earlier = List.filteri (fun j _ -> j < i) ids in
      list_size (int_range 0 (List.length earlier)) (oneof_list (if earlier = [] then [""] else earlier))
      >|= fun ds ->
      let ds = List.filter (fun d -> d <> "") ds |> List.sort_uniq String.compare in
      mk_node id ds) ids in
    flatten_list dep_gens >>= fun nodes ->
    (* reverse input order to stress topo_sort *)
    return (List.rev nodes) in
  QCheck2.Test.make ~count:200 ~name:"law_topo_sort_places_every_dep_before_dependent" dag_gen
    (fun nodes ->
       match Quest_spec.topo_sort nodes with
       | Error _ -> false
       | Ok ordered ->
           let idx id =
             let rec go i = function
               | [] -> -1
               | n :: r -> if n.Quest_spec.id = id then i else go (i + 1) r in
             go 0 ordered in
           List.length ordered = List.length nodes
           && List.for_all (fun (n : Quest_spec.node_spec) ->
                List.for_all (fun d -> idx d >= 0 && idx d < idx n.id) n.depends_on) ordered)

let () =
  run_test_tt_main
    ("quest_spec" >::: [
       "case_parse_valid_spec_and_render_acceptance" >:: case_parse_valid_spec_and_render_acceptance;
       "case_parse_rejects_malformed_and_invalid_specs" >:: case_parse_rejects_malformed_and_invalid_specs;
       "case_json_diff_violations_allows_only_non_self_todo_node_edits" >:: case_json_diff_violations_allows_only_non_self_todo_node_edits;
       QCheck_ounit.to_ounit2_test law_topo_sort_places_every_dep_before_dependent;
     ])
