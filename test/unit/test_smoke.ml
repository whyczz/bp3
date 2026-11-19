(* Smoke tests: prove the engine links into dune test (unit.1).
   case_ = named example, law_ = QCheck property over generated input. *)
open OUnit2

let case_valid_slug_accepts_a_dated_kebab_slug _ =
  assert_bool "dated kebab slug" (Store.valid_slug "2026-11-18-test-pyramid")

(* Strings over the slug alphabet with one '/' spliced in somewhere. *)
let gen_slug_with_slash =
  let open QCheck2.Gen in
  let slug_char = oneof [ char_range 'a' 'z'; char_range '0' '9'; return '-' ] in
  map3
    (fun pre post at ->
      let s = pre ^ post in
      let i = if s = "" then 0 else at mod (String.length s + 1) in
      String.sub s 0 i ^ "/" ^ String.sub s i (String.length s - i))
    (string_size ~gen:slug_char (int_range 0 12))
    (string_size ~gen:slug_char (int_range 0 12))
    nat

let law_valid_slug_rejects_every_string_containing_a_slash =
  QCheck2.Test.make ~count:200 ~name:"law_valid_slug_rejects_every_string_containing_a_slash"
    ~print:(fun s -> s) gen_slug_with_slash
    (fun s -> not (Store.valid_slug s))

let () =
  run_test_tt_main
    ("smoke" >::: [
       "case_valid_slug_accepts_a_dated_kebab_slug" >:: case_valid_slug_accepts_a_dated_kebab_slug;
       QCheck_ounit.to_ounit2_test law_valid_slug_rejects_every_string_containing_a_slash;
     ])
