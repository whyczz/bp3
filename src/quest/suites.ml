(* suites — the pure core of run-suites (test-pyramid tier.1): the
   suite table, selection, launch order, budget decisions and the
   lines the runner prints. No process, clock or file here; the
   executable (run_suites.ml) does the I/O around it. *)

type row = {
  name : string; tier : string; cmd : string; budget_s : int;
  serial : bool; why : string; paths : string;
}

(* A table or usage error; the runner prints it and exits 2. *)
exception Table_error of string

let fail fmt = Printf.ksprintf (fun s -> raise (Table_error s)) fmt

let all_digits s = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s

(* One row: exactly 7 tab-separated fields, '-' for an empty one. *)
let parse_row ~where line =
  let fields = String.split_on_char '\t' line in
  let n = List.length fields in
  if n <> 7 then fail "%s: expected 7 tab-separated fields, got %d" where n;
  if List.mem "" fields then fail "%s: empty field (use '-')" where;
  match fields with
  | [ name; tier; cmd; budget; serial; why; paths ] ->
      (* the name becomes a directory under the run's temp dir, removed
         when the suite passes: no '/', no leading dot, no '..' *)
      let name_ok = name.[0] <> '.' && String.for_all (fun c ->
          (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
          || c = '-' || c = '_' || c = '.') name in
      if not name_ok then fail "%s: suite name must be letters, digits, '-', '_' or '.', not starting with '.': %s" where name;
      if tier <> "fixture" && tier <> "slow" then fail "%s: tier must be fixture or slow: %s" where tier;
      let budget_s = match int_of_string_opt budget with
        | Some b when all_digits budget && b > 0 -> b
        | _ -> fail "%s: budget_s must be a positive integer: %s" where budget in
      let serial = match serial with
        | "0" -> false | "1" -> true
        | s -> fail "%s: serial must be 0 or 1: %s" where s in
      if tier = "slow" && why = "-" then fail "%s: slow row %s needs a why" where name;
      { name; tier; cmd; budget_s; serial; why; paths }
  | _ -> assert false

(* The whole table: '#' lines and blank lines skipped, names unique. *)
let parse_table ~file text =
  let rows = ref [] in
  List.iteri (fun i line ->
      if line <> "" && line.[0] <> '#' then begin
        let r = parse_row ~where:(Printf.sprintf "%s:%d" file (i + 1)) line in
        if List.exists (fun x -> x.name = r.name) !rows then
          fail "%s:%d: duplicate suite name: %s" file (i + 1) r.name;
        rows := r :: !rows
      end)
    (String.split_on_char '\n' text);
  if !rows = [] then fail "empty suite table: %s" file;
  List.rev !rows

let valid_tier t = t = "fixture" || t = "slow"

(* Rows in table order whose tier is listed and, when [only] is given,
   whose name is in it; an unknown [only] name is an error. *)
let select ~tiers ~only rows =
  (match only with
   | Some names ->
       List.iter (fun n -> if not (List.exists (fun r -> r.name = n) rows) then fail "unknown suite: %s" n) names
   | None -> ());
  List.filter (fun r ->
      List.mem r.tier tiers
      && (match only with Some names -> List.mem r.name names | None -> true)) rows

(* Largest budget first (budgets track run time), ties in table order,
   so the longest suite never starts behind short ones. *)
let launch_order rows = List.stable_sort (fun a b -> compare b.budget_s a.budget_s) rows

(* Only a real overrun fails: strictly more than the budget. *)
let over_budget ~now_ms ~start_ms ~budget_s = now_ms - start_ms > budget_s * 1000

(* Milliseconds as seconds with one decimal, truncated: 1234 -> "1.2". *)
let secs ms = Printf.sprintf "%d.%d" (ms / 1000) (ms mod 1000 / 100)

type outcome = Passed | Exit of int | Budget

let result_line r ~took_ms outcome =
  let word, note = match outcome with
    | Passed -> "ok", ""
    | Exit rc -> "FAIL", Printf.sprintf "  rc=%d" rc
    | Budget -> "FAIL", "  budget exceeded, group killed" in
  Printf.sprintf "  %-4s %-22s %6ss  (budget %ds)%s" word r.name (secs took_ms) r.budget_s note

(* The --report table: share of budget used, highest first, ties by name. *)
let report_lines results =
  let rows = List.map (fun (r, took_ms) ->
      (took_ms / 10 / r.budget_s, r.name, Printf.sprintf "%s/%ds" (secs took_ms) r.budget_s)) results in
  let sorted = List.sort (fun (p1, n1, _) (p2, n2, _) -> if p1 <> p2 then compare p2 p1 else compare n1 n2) rows in
  "run-suites: report (actual vs budget, highest share first)"
  :: List.map (fun (pct, n, frac) -> Printf.sprintf "  %3d%%  %-22s %s" pct n frac) sorted

let summary_ok ~count ~wall_ms ~sum_ms =
  Printf.sprintf "run-suites: ok %d/%d  wall %ss  (serial sum %ss)" count count (secs wall_ms) (secs sum_ms)

let summary_fail ~failed ~count ~wall_ms =
  Printf.sprintf "run-suites: FAIL %d/%d:%s  wall %ss" (List.length failed) count
    (String.concat "" (List.map (fun n -> " " ^ n) failed)) (secs wall_ms)

(* The exit code for a signal that stopped the run: 128 + its number. *)
let signal_exit s =
  if s = Sys.sigint then 130 else if s = Sys.sigterm then 143
  else if s = Sys.sighup then 129 else if s = Sys.sigquit then 131 else 1

(* A suite's environment: only the allowlisted variables and every
   LC_*, then its own HOME, TMPDIR and name. Nothing else reaches it. *)
let allowlist = [ "PATH"; "LANG"; "SDKROOT"; "OPAM_SWITCH_PREFIX"; "CAML_LD_LIBRARY_PATH";
                  "OCAMLPATH"; "OCAML_TOPLEVEL_PATH"; "NODE_PATH"; "NODE_OPTIONS" ]

let suite_env ~caller ~home ~name =
  let keep kv = match String.index_opt kv '=' with
    | Some i -> let k = String.sub kv 0 i in
        List.mem k allowlist || (String.length k > 3 && String.sub k 0 3 = "LC_")
    | None -> false in
  List.filter keep caller
  @ [ "HOME=" ^ home; "TMPDIR=" ^ home ^ "/t"; "BP3_SUITE=" ^ name; "GIT_CONFIG_NOSYSTEM=1" ]
