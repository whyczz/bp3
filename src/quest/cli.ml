(* cli — argv helpers for the bp3 q door: flag parsing, verb
   spellings, dep lists. Pure but for typed usage refusals;
   moved out of main.ml (test-pyramid unit.4) so unit tests
   can link them. main.ml includes this module. *)
open Gitx

type flags = {
  reason : string option; commit : string option; verdict : string option;
  target : string option; typ : string option; depends_on : string option;
  fmt : string; verify_verdict : string option; mechanical : bool;
}

let parse_flags args =
  let rec loop acc = function
    | [] -> acc
    | "--reason" :: v :: rest -> add acc "reason" v rest
    | "--commit" :: v :: rest -> add acc "commit" v rest
    | "--verdict" :: v :: rest -> add acc "verdict" v rest
    | "--target" :: v :: rest -> add acc "target" v rest
    | "--type" :: v :: rest -> add acc "type" v rest
    | "--depends-on" :: v :: rest -> add acc "depends-on" v rest
    | "--format" :: v :: rest -> add acc "format" v rest
    | "--verify-verdict" :: v :: rest -> add acc "verify-verdict" v rest
    | "--mechanical" :: rest ->
        if acc.mechanical then usage "duplicate flag --mechanical"
        else loop { acc with mechanical = true } rest
    | "--reason" :: [] | "--commit" :: [] | "--verdict" :: [] | "--target" :: []
    | "--type" :: [] | "--depends-on" :: [] | "--format" :: []
    | "--verify-verdict" :: [] ->
        usage "flag needs a value"
    | "--mode" :: _ -> usage mode_flag_usage
    | f :: _ when String.length f >= 7 && String.sub f 0 7 = "--mode=" ->
        usage mode_flag_usage
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray)
  and add acc name v rest =
    let has = match name with
      | "reason" -> acc.reason <> None | "commit" -> acc.commit <> None
      | "verdict" -> acc.verdict <> None | "target" -> acc.target <> None
      | "type" -> acc.typ <> None | "depends-on" -> acc.depends_on <> None
      | "verify-verdict" -> acc.verify_verdict <> None
      | "format" -> acc.fmt <> "json" || List.mem "--format" [] | _ -> false in
    (* duplicate detection for format needs explicit tracking; handled below *)
    ignore has;
    match name with
    | "reason" -> if acc.reason <> None then usage "duplicate flag --reason" else loop { acc with reason = Some v } rest
    | "commit" -> if acc.commit <> None then usage "duplicate flag --commit" else loop { acc with commit = Some v } rest
    | "verdict" -> if acc.verdict <> None then usage "duplicate flag --verdict" else loop { acc with verdict = Some v } rest
    | "target" -> if acc.target <> None then usage "duplicate flag --target" else loop { acc with target = Some v } rest
    | "type" -> if acc.typ <> None then usage "duplicate flag --type" else loop { acc with typ = Some v } rest
    | "depends-on" -> if acc.depends_on <> None then usage "duplicate flag --depends-on" else loop { acc with depends_on = Some v } rest
    | "verify-verdict" -> if acc.verify_verdict <> None then usage "duplicate flag --verify-verdict" else loop { acc with verify_verdict = Some v } rest
    | "format" ->
        if v <> "json" && v <> "table" && v <> "tree" then usage "--format must be json, table, or tree";
        loop { acc with fmt = v } rest
    | _ -> usage ("unknown flag --" ^ name)
  in
  (* pre-scan for duplicate --format *)
  let rec count n = function
    | [] -> n | "--format" :: _ :: r -> count (n + 1) r | _ :: r -> count n r in
  if count 0 args > 1 then usage "duplicate flag --format";
  loop { reason = None; commit = None; verdict = None; target = None;
         typ = None; depends_on = None; fmt = "json";
         verify_verdict = None; mechanical = false } args

let split_flags args =
  (* separate positionals (before first --flag) from flags; any positional
     after a flag value that is not consumed is stray -> caught in parse *)
  let rec go pos flags = function
    | [] -> (List.rev pos, flags)
    | a :: rest when String.length a >= 2 && a.[0] = '-' && a.[1] = '-' ->
        (List.rev pos, a :: rest @ flags)
    | a :: rest -> go (a :: pos) flags rest in
  let (pos, fl) = go [] [] args in
  (pos, parse_flags fl)


let parse_dep_list = function
  | Some s when s <> "" ->
      List.fold_right (fun d acc ->
        let d = String.trim d in if d = "" || List.mem d acc then acc else d :: acc)
        (String.split_on_char ',' s) []
  | _ -> []


let normalize_verb = function
  | "c" | "create" -> "c" | "r" | "read" -> "r"
  | "u" | "update" -> "u" | "d" | "delete" -> "d"
  | other -> other

let is_verb = function "c" | "create" | "r" | "read" | "u" | "update" | "d" | "delete" -> true | _ -> false


let is_help = function "-h" | "--help" -> true | _ -> false

