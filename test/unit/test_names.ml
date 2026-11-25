(* Unit guard for src/quest/names.ml (codebase-diet clean.2):
   1. Zero raw `err "E_..."` literals across src/quest/*.ml outside names.ml.
   2. Store.reserved_slugs covers every surviving door/verb in Names (including "warden").
   3. Retired doors/verbs are freed from Store.reserved_slugs. *)
open OUnit2

let read_all path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let case_no_raw_error_literals_outside_names_ml _ =
  let dir = "../../src/quest" in
  let files = Sys.readdir dir |> Array.to_list |> List.sort String.compare in
  let re = Str.regexp "\\berr[ \t]+\"E_[A-Z_]+\"" in
  let offenders =
    List.filter_map (fun name ->
      if not (Filename.check_suffix name ".ml") || name = "names.ml" then None
      else
        let text = read_all (Filename.concat dir name) in
        match (try Some (Str.search_forward re text 0) with Not_found -> None) with
        | Some _ -> Some (name ^ ": " ^ Str.matched_string text)
        | None -> None) files in
  assert_equal ~printer:(String.concat "; ") [] offenders

let case_reserved_slugs_derived_from_names_includes_warden _ =
  List.iter (fun d ->
    assert_bool ("door missing from reserved_slugs: " ^ d) (List.mem d Store.reserved_slugs))
    Names.all_doors;
  List.iter (fun v ->
    assert_bool ("verb missing from reserved_slugs: " ^ v) (List.mem v Store.reserved_slugs))
    Names.all_verbs;
  assert_bool "warden must be reserved" (List.mem "warden" Store.reserved_slugs)

let case_retired_verbs_freed_from_reserved_slugs _ =
  List.iter (fun retired ->
    assert_bool ("retired slug still reserved: " ^ retired)
      (not (List.mem retired Store.reserved_slugs)))
    [ "supervisor"; "watch"; "backtest"; "init-check"; "find-tape"; "n"; "e" ]

let () =
  run_test_tt_main
    ("names" >::: [
       "case_no_raw_error_literals_outside_names_ml" >:: case_no_raw_error_literals_outside_names_ml;
       "case_reserved_slugs_derived_from_names_includes_warden" >:: case_reserved_slugs_derived_from_names_includes_warden;
       "case_retired_verbs_freed_from_reserved_slugs" >:: case_retired_verbs_freed_from_reserved_slugs;
     ])
