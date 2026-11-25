(* Release engine unit + QCheck2 property tests (core.1). Pure: no git,
   no filesystem, no clock. *)
open OUnit2

let sv major minor patch = { Release.major; minor; patch }

let contains_sub hay needle =
  let n = String.length hay and m = String.length needle in
  if m = 0 then true
  else if m > n then false
  else
    let rec at i j = j = m || (hay.[i + j] = needle.[j] && at i (j + 1)) in
    let rec loop i = i + m <= n && (at i 0 || loop (i + 1)) in
    loop 0

(* ---------- bump & semver ---------- *)

let case_parse_bump_accepts_four_levels_and_rejects_others _ =
  assert_equal (Some Release.Major) (Release.parse_bump "major");
  assert_equal (Some Release.Minor) (Release.parse_bump "minor");
  assert_equal (Some Release.Patch) (Release.parse_bump "patch");
  assert_equal (Some Release.None_bump) (Release.parse_bump "none");
  assert_equal None (Release.parse_bump "big");
  assert_equal None (Release.parse_bump "MAJOR");
  assert_equal None (Release.parse_bump "");
  assert_equal "minor" (Release.bump_to_string Release.Minor)

let case_parse_semver_tag_is_strict _ =
  assert_equal (Some (sv 0 2 0)) (Release.parse_semver_tag "v0.2.0");
  assert_equal (Some (sv 1 12 3)) (Release.parse_semver_tag "v1.12.3");
  assert_equal (Some (sv 0 0 0)) (Release.parse_semver_tag "v0.0.0");
  assert_equal None (Release.parse_semver_tag "0.2.0");
  assert_equal None (Release.parse_semver_tag "v0.2");
  assert_equal None (Release.parse_semver_tag "v0.2.0.1");
  assert_equal None (Release.parse_semver_tag "v0.2.0-rc1");
  assert_equal None (Release.parse_semver_tag "v01.2.0");
  assert_equal None (Release.parse_semver_tag "v0.02.0");
  assert_equal None (Release.parse_semver_tag "v 0.2.0");
  assert_equal None (Release.parse_semver_tag "release-1")

let case_latest_semver_tag_uses_numeric_order_and_ignores_noise _ =
  assert_equal None (Release.latest_semver_tag []);
  assert_equal None (Release.latest_semver_tag [ "demo"; "v0.2.0-rc1"; "0.9.0" ]);
  assert_equal (Some (sv 0 10 0))
    (Release.latest_semver_tag [ "v0.2.0"; "v0.9.9"; "v0.10.0"; "misc"; "v0.10.0-alpha" ]);
  assert_equal (Some (sv 2 0 0))
    (Release.latest_semver_tag [ "v1.99.99"; "v2.0.0"; "v0.1.0" ])

let case_next_semver_covers_all_bumps_from_none_and_some _ =
  assert_equal (Some (sv 0 1 0)) (Release.next_semver None Release.Minor);
  assert_equal (Some (sv 1 0 0)) (Release.next_semver None Release.Major);
  assert_equal (Some (sv 0 0 1)) (Release.next_semver None Release.Patch);
  assert_equal None (Release.next_semver None Release.None_bump);
  assert_equal (Some (sv 0 3 0)) (Release.next_semver (Some (sv 0 2 5)) Release.Minor);
  assert_equal (Some (sv 1 0 0)) (Release.next_semver (Some (sv 0 2 5)) Release.Major);
  assert_equal (Some (sv 0 2 6)) (Release.next_semver (Some (sv 0 2 5)) Release.Patch);
  assert_equal None (Release.next_semver (Some (sv 0 2 5)) Release.None_bump)

(* ---------- GitHub remote parser ---------- *)

let case_parse_github_repo_handles_ssh_https_and_rejects_non_github _ =
  assert_equal (Some "whyczz/bp3") (Release.parse_github_repo "git@github.com:whyczz/bp3.git");
  assert_equal (Some "whyczz/bp3") (Release.parse_github_repo "git@github.com:whyczz/bp3");
  assert_equal (Some "whyczz/bp3") (Release.parse_github_repo "https://github.com/whyczz/bp3.git");
  assert_equal (Some "whyczz/bp3") (Release.parse_github_repo "https://github.com/whyczz/bp3/");
  assert_equal (Some "whyczz/bp3") (Release.parse_github_repo "ssh://git@github.com/whyczz/bp3.git");
  assert_equal None (Release.parse_github_repo "/tmp/bare.git");
  assert_equal None (Release.parse_github_repo "file:///tmp/bare.git");
  assert_equal None (Release.parse_github_repo "git@gitlab.com:whyczz/bp3.git");
  assert_equal None (Release.parse_github_repo "https://github.com/whyczz/bp3/extra");
  assert_equal None (Release.parse_github_repo "");
  assert_equal (Release.GitHub "whyczz/bp3")
    (Release.classify_remote (Some "git@github.com:whyczz/bp3.git"));
  assert_equal Release.Local_tag (Release.classify_remote (Some "/tmp/bare.git"));
  assert_equal Release.Local_tag (Release.classify_remote None)

(* ---------- QUEST.md frontmatter & status ---------- *)

let sample_quest_md =
  "---\n\
   status: active\n\
   home_repo: bp3\n\
   date: 2026-11-23\n\
   bump: minor\n\
   ---\n\n\
   # quest-promote-release: atomic CAS\n\n\
   TL;DR\n\
   Tie quest promotion to a semver tag\n\
   and cut a GitHub Release automatically.\n\n\
   ELI5\n\
   Plain words.\n\n\
   ## Notes\n\
   status: active stays untouched in body.\n"

let case_parse_quest_md_and_set_status_landed _ =
  let m = Release.parse_quest_md sample_quest_md in
  assert_equal (Some "active") m.Release.status;
  assert_equal (Some "minor") m.Release.bump;
  assert_equal "quest-promote-release: atomic CAS" m.Release.title;
  assert_equal "Tie quest promotion to a semver tag and cut a GitHub Release automatically."
    m.Release.tldr;
  let updated = Release.set_quest_status_landed sample_quest_md in
  assert_equal (Some "landed") (Release.parse_quest_md updated).Release.status;
  assert_bool "body status untouched"
    (contains_sub updated "status: active stays untouched in body.");
  assert_equal updated (Release.set_quest_status_landed updated)

let case_parse_minimal_quest_md_degrades_tldr_cleanly _ =
  let minimal = "---\nstatus: proposed\ngoal_type: default\n---\n\n# demo\n" in
  let m = Release.parse_quest_md minimal in
  assert_equal (Some "proposed") m.Release.status;
  assert_equal None m.Release.bump;
  assert_equal "demo" m.Release.title;
  assert_equal "" m.Release.tldr

(* ---------- gitx.ml version sync ---------- *)

let case_sync_bp3_version_replaces_exact_line_and_fails_closed _ =
  let src = "(* header *)\nlet bp3_version = \"0.2.0\"\nlet x = 1\n" in
  (match Release.sync_bp3_version ~new_version:"0.3.0" src with
   | Ok out ->
       assert_equal "(* header *)\nlet bp3_version = \"0.3.0\"\nlet x = 1\n" out
   | Error e -> assert_failure ("unexpected error: " ^ e));
  (match Release.sync_bp3_version ~new_version:"0.3.0" "let other = 1\n" with
   | Error _ -> ()
   | Ok _ -> assert_failure "expected missing error");
  let dup = "let bp3_version = \"0.2.0\"\nlet bp3_version = \"0.2.0\"\n" in
  (match Release.sync_bp3_version ~new_version:"0.3.0" dup with
   | Error _ -> ()
   | Ok _ -> assert_failure "expected duplicate error")

(* ---------- What changed renderers ---------- *)

let case_render_what_changed_quest_and_commit _ =
  let meta = Release.parse_quest_md sample_quest_md in
  let nodes = [
    { Release.node_id = "node-core-1-release-engine"; state = "landed";
      commit = Some "abcdef1234567890"; subject = "feat(core.1): pure release engine" };
  ] in
  let r =
    Release.render_what_changed ~quest:"2026-11-23-quest-promote-release"
      ~tag:"v0.3.0" ~prev_tag:(Some "v0.2.0") ~meta ~nodes ~commit_subjects:[] in
  assert_equal "v0.3.0" r.Release.tag;
  assert_bool "has title" (contains_sub r.Release.body "# v0.3.0 — quest-promote-release: atomic CAS");
  assert_bool "has tldr" (contains_sub r.Release.body "Tie quest promotion to a semver tag");
  assert_bool "has node bullet" (contains_sub r.Release.body "- `node-core-1-release-engine`: feat(core.1): pure release engine (abcdef1)");
  assert_bool "has prev tag" (contains_sub r.Release.body "Previous tag: v0.2.0");

  let rc =
    Release.render_commit_what_changed ~sha:"1234567890abcdef"
      ~subject:"fix(hooks): handle empty payload" ~body:"Guard empty stdin."
      ~tag:"v0.3.1" ~prev_tag:(Some "v0.3.0") ~commit_subjects:[] in
  assert_equal "v0.3.1 — fix(hooks): handle empty payload" rc.Release.title;
  assert_bool "commit body" (contains_sub rc.Release.body "Guard empty stdin.");
  assert_bool "commit sha7" (contains_sub rc.Release.body "Commit: `1234567`")

(* ---------- QCheck2 properties ---------- *)

let gen_sv =
  QCheck2.Gen.(map3 sv (int_range 0 99) (int_range 0 99) (int_range 0 99))

let gen_active_bump =
  QCheck2.Gen.oneof_list [ Release.Major; Release.Minor; Release.Patch ]

let law_semver_tag_roundtrip =
  QCheck2.Test.make ~count:300 ~name:"law_semver_tag_roundtrip"
    ~print:Release.format_tag gen_sv
    (fun v -> Release.parse_semver_tag (Release.format_tag v) = Some v)

let law_next_semver_is_strictly_greater_and_obeys_reset_laws =
  QCheck2.Test.make ~count:500 ~name:"law_next_semver_is_strictly_greater_and_obeys_reset_laws"
    ~print:(fun (v, b) -> Release.format_semver v ^ " + " ^ Release.bump_to_string b)
    QCheck2.Gen.(pair gen_sv gen_active_bump)
    (fun (v, b) ->
      match Release.next_semver (Some v) b with
      | None -> false
      | Some n ->
          Release.compare_semver n v > 0
          && (match b with
              | Release.Major -> n.major = v.major + 1 && n.minor = 0 && n.patch = 0
              | Release.Minor -> n.major = v.major && n.minor = v.minor + 1 && n.patch = 0
              | Release.Patch -> n.major = v.major && n.minor = v.minor && n.patch = v.patch + 1
              | Release.None_bump -> false))

let () =
  run_test_tt_main
    ("release" >::: [
       "case_parse_bump_accepts_four_levels_and_rejects_others" >:: case_parse_bump_accepts_four_levels_and_rejects_others;
       "case_parse_semver_tag_is_strict" >:: case_parse_semver_tag_is_strict;
       "case_latest_semver_tag_uses_numeric_order_and_ignores_noise" >:: case_latest_semver_tag_uses_numeric_order_and_ignores_noise;
       "case_next_semver_covers_all_bumps_from_none_and_some" >:: case_next_semver_covers_all_bumps_from_none_and_some;
       "case_parse_github_repo_handles_ssh_https_and_rejects_non_github" >:: case_parse_github_repo_handles_ssh_https_and_rejects_non_github;
       "case_parse_quest_md_and_set_status_landed" >:: case_parse_quest_md_and_set_status_landed;
       "case_parse_minimal_quest_md_degrades_tldr_cleanly" >:: case_parse_minimal_quest_md_degrades_tldr_cleanly;
       "case_sync_bp3_version_replaces_exact_line_and_fails_closed" >:: case_sync_bp3_version_replaces_exact_line_and_fails_closed;
       "case_render_what_changed_quest_and_commit" >:: case_render_what_changed_quest_and_commit;
       QCheck_ounit.to_ounit2_test law_semver_tag_roundtrip;
       QCheck_ounit.to_ounit2_test law_next_semver_is_strictly_greater_and_obeys_reset_laws;
     ])
