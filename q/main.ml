(* bp3 q — quest/exp FSM CLI. Only writer of quest state. *)
let bp3_version = "0.2.0"

exception Verdict of (int * Yojson.Safe.t)

let json_str s = `String s
let err code facts guidance exit_code =
  raise (Verdict (exit_code, `Assoc [
    ("ok", `Bool false);
    ("error", `Assoc [
      ("code", json_str code);
      ("facts", facts);
      ("guidance", json_str guidance);
    ]);
  ]))

let usage msg = err "E_USAGE" (`Assoc [("detail", json_str msg)]) ("Fix the call: " ^ msg) 2
let not_found what name =
  err "E_NOT_FOUND" (`Assoc [(what, json_str name)]) (what ^ " not found: " ^ name) 2

(* ---------- shell / git helpers ---------- *)
let root =
  match Sys.getenv_opt "BP3_ROOT" with
  | Some r when r <> "" -> r
  | _ -> Sys.getcwd ()

let tmp_counter = ref 0
let tmp_path tag =
  incr tmp_counter;
  Filename.concat (Filename.get_temp_dir_name ())
    (Printf.sprintf "bp3q-%d-%d-%s" (Unix.getpid ()) !tmp_counter tag)

let read_file_or path default =
  try
    let ic = open_in_bin path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic; s
  with _ -> default

let write_tmp content =
  let p = tmp_path "data" in
  let oc = open_out_bin p in
  output_string oc content; close_out oc; p

let run_capture args =
  let outf = tmp_path "out" in
  let cmd = String.concat " " (List.map Filename.quote args)
    ^ " > " ^ Filename.quote outf ^ " 2>/dev/null" in
  let code = Sys.command cmd in
  let out = read_file_or outf "" in
  (String.trim out, code)

let run_status args = snd (run_capture args)
let git args = "git" :: "-C" :: root :: args
let git_out args = run_capture (git args)
let git_ok args = run_status (git args) = 0

let git_show ref_ path =
  let out, code = git_out ["show"; ref_ ^ ":" ^ path] in
  if code = 0 then Some out else None

let ref_tip refname =
  let out, code = git_out ["rev-parse"; "--verify"; "-q"; refname ^ "^{commit}"] in
  if code = 0 && out <> "" then Some out else None

let resolve_commit sha =
  let out, code = git_out ["rev-parse"; "--verify"; "-q"; sha ^ "^{commit}"] in
  if code = 0 && out <> "" then Some out else None

let worktree_dirty () =
  let out, _ = git_out ["status"; "--porcelain"] in
  String.trim out <> ""

let head_sha () =
  match ref_tip "HEAD" with Some s -> s | None -> usage "repository has no HEAD commit"

let is_ancestor a b = git_ok ["merge-base"; "--is-ancestor"; a; b]

let now_ts () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1) t.Unix.tm_mday
    t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

(* Write files into a branch via plumbing; CAS on old tip.
   files: (path, content) list. Returns new tip or E_STALE_WORLD. *)
let commit_files ~branch ~base_tip ~expect_tip ~files ~msg =
  let idx = tmp_path "index" in
  Unix.putenv "GIT_INDEX_FILE" idx;
  let cleanup () = (try Unix.unlink idx with _ -> ()); Unix.putenv "GIT_INDEX_FILE" "" in
  let fail () = cleanup (); err "E_STALE_WORLD" (`Assoc [("branch", json_str branch)])
    "Branch tip moved; re-read and retry." 1 in
  if run_status (git ["read-tree"; base_tip]) <> 0 then fail ();
  List.iter (fun (path, content) ->
    let cf = write_tmp content in
    let blobfile = tmp_path "blobout" in
    let cmd = String.concat " " (List.map Filename.quote (git ["hash-object"; "-w"; "--stdin"]))
      ^ " < " ^ Filename.quote cf ^ " > " ^ Filename.quote blobfile ^ " 2>/dev/null" in
    if Sys.command cmd <> 0 then fail ();
    let blob = String.trim (read_file_or blobfile "") in
    if run_status (git ["update-index"; "--add"; "--cacheinfo";
                        "100644," ^ blob ^ "," ^ path]) <> 0 then fail ()
  ) files;
  let treef = tmp_path "tree" in
  if Sys.command (String.concat " " (List.map Filename.quote (git ["write-tree"]))
      ^ " > " ^ Filename.quote treef ^ " 2>/dev/null") <> 0 then fail ();
  let tree = String.trim (read_file_or treef "") in
  let msgf = write_tmp msg in
  let commitf = tmp_path "commit" in
  let cargs = git (["commit-tree"; tree; "-p"; base_tip]) in
  if Sys.command (String.concat " " (List.map Filename.quote cargs)
      ^ " < " ^ Filename.quote msgf ^ " > " ^ Filename.quote commitf ^ " 2>/dev/null") <> 0 then fail ();
  let new_tip = String.trim (read_file_or commitf "") in
  cleanup ();
  let code = run_status (git ["update-ref"; branch; new_tip; expect_tip]) in
  if code <> 0 then err "E_STALE_WORLD" (`Assoc [("branch", json_str branch)])
    "Branch tip moved; re-read and retry." 1;
  new_tip

let create_branch_commit ~branch ~base_tip ~files ~msg =
  (* branch must not exist; update-ref with zero old value *)
  commit_files ~branch ~base_tip ~expect_tip:"0000000000000000000000000000000000000000" ~files ~msg

(* ---------- slugs / identity ---------- *)
let valid_slug s =
  let n = String.length s in
  n >= 1 &&
  (let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' in
   let rec loop i = i >= n || (ok s.[i] && loop (i + 1)) in
   ((s.[0] >= 'a' && s.[0] <= 'z') || (s.[0] >= '0' && s.[0] <= '9')) && loop 1)

let check_slug s = if not (valid_slug s) then usage ("invalid slug: " ^ s)

type identity = { harness : string; model : string; decider_human : bool; incomplete : bool }

let identity () =
  let h = Sys.getenv_opt "BP3_HARNESS" in
  (match h with
   | Some v when v <> "" ->
       if not (List.mem v ["muse-code"; "codex"; "muse"; "human"]) then
         err "E_IDENTITY" (`Assoc [("harness", json_str v)])
           "BP3_HARNESS must be one of muse-code, codex, muse, human." 2
   | _ -> ());
  let decider_human = (Sys.getenv_opt "BP3_DECIDER" = Some "human") in
  let harness = match h with Some v when v <> "" -> v | _ -> "unknown" in
  let model =
    if decider_human then "none"
    else match Sys.getenv_opt "BP3_MODEL" with Some v when v <> "" -> v | _ -> "unknown" in
  let incomplete = harness = "unknown" || model = "unknown" in
  { harness; model; decider_human; incomplete }

let warnings_of id is_write =
  if is_write && id.incomplete then ["W_IDENTITY_UNKNOWN"] else []

(* ---------- plans ---------- *)
type knobs = { max_cycles : int; review_required : bool; checks_required : bool }

let contains_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec loop i = i + m <= n && (String.sub s i m = sub || loop (i + 1)) in
  m = 0 || loop 0

let plan_knobs_from_text text =
  (* reject stages:/edges: keys at line start (after spaces) *)
  let lines = String.split_on_char '\n' text in
  List.iter (fun ln ->
    let t = String.trim ln in
    if t = "stages:" || (String.length t > 7 && String.sub t 0 7 = "stages:") ||
       t = "edges:" || (String.length t > 6 && String.sub t 0 6 = "edges:") then
      err "E_INVALID_PLAN" (`Assoc []) "Plan contains stages:/edges: keys; plans carry knobs only." 1
  ) lines;
  let max_cycles =
    try
      let re = Str.regexp "max_cycles:[ \t]*\\([0-9]+\\)" in
      ignore (Str.search_forward re text 0);
      int_of_string (Str.matched_group 1 text)
    with _ -> 1 in
  let review_required =
    (* look at review section: 'required: false' after 'review:' *)
    if contains_sub text "required: false" && contains_sub text "review:" then false
    else if contains_sub text "review.required: false" then false
    else true in
  let review_required =
    if contains_sub text "required: false" then
      (* only counts if a review: key exists or review_required spelling *)
      review_required else review_required in
  let checks_required =
    not (contains_sub text "checks: optional" || contains_sub text "checks: none"
         || contains_sub text "checks:optional" || contains_sub text "checks:none") in
  { max_cycles; review_required; checks_required }

let load_plan_file path =
  let full = Filename.concat root path in
  if not (Sys.file_exists full) then
    err "E_INVALID_PLAN" (`Assoc [("plan", json_str path)]) ("Plan file missing: " ^ path) 1;
  plan_knobs_from_text (read_file_or full "")

let quest_knobs quest_type = load_plan_file ("plans/" ^ quest_type ^ ".yaml")

let effective_knobs ~quest_type ~exp_type =
  if exp_type = "default" || exp_type = "" then quest_knobs quest_type
  else load_plan_file ("plans/exp-" ^ exp_type ^ ".yaml")

(* ---------- ledger fold ---------- *)
type exp_state = {
  mutable st : string;
  mutable cycle : int;
  mutable bound : string option;
  mutable has_bound : bool;
  mutable review_ok : bool;
  mutable check_ok : bool;
  mutable blocked_reason : string;
  mutable blocked_checkpoint : string option;
  mutable blocked_since : string;
  mutable last_commit : string option;
  mutable exp_type : string;
}

let fresh_state () = {
  st = "todo"; cycle = 1; bound = None; has_bound = false;
  review_ok = false; check_ok = false;
  blocked_reason = ""; blocked_checkpoint = None; blocked_since = "";
  last_commit = None; exp_type = "default";
}

let get_str j key default =
  try match Yojson.Safe.Util.member key j with `String s -> s | _ -> default
  with _ -> default
let get_int j key default =
  try match Yojson.Safe.Util.member key j with `Int n -> n | _ -> default
  with _ -> default
let get_opt j key =
  try match Yojson.Safe.Util.member key j with `String s -> Some s | _ -> None
  with _ -> None

let fold_ledger text =
  let s = fresh_state () in
  let quest_type = ref "default" in
  let depends_on = ref [] in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        let edge = get_str j "edge" "" in
        let to_ = get_str j "to" "" in
        let cyc = get_int j "cycle" s.cycle in
        if edge = "create" then begin
          s.exp_type <- get_str j "exp_type" (get_str j "quest_type" "default");
          quest_type := get_str j "quest_type" !quest_type;
          (try match Yojson.Safe.Util.member "depends_on" j with
             | `List xs -> depends_on := List.map (function `String x -> x | _ -> "") xs
             | _ -> () with _ -> ())
        end;
        if to_ <> "" then s.st <- to_;
        s.cycle <- cyc;
        (match get_opt j "commit" with Some c -> s.last_commit <- Some c; s.bound <- Some c; s.has_bound <- true | None -> ());
        if edge = "submit" then begin s.review_ok <- false; s.check_ok <- false end;
        if edge = "review" && get_str j "verdict" "" = "ship" then s.review_ok <- true;
        if edge = "check" && get_str j "verdict" "" = "pass" then s.check_ok <- true;
        if (edge = "review" && get_str j "verdict" "" = "needs_fix") ||
           (edge = "check" && get_str j "verdict" "" = "fail") then begin
          s.review_ok <- false; s.check_ok <- false
        end;
        if edge = "resume" then begin s.bound <- None; s.has_bound <- false; s.review_ok <- false; s.check_ok <- false end;
        if to_ = "blocked" then begin
          s.blocked_reason <- get_str j "reason" "";
          s.blocked_checkpoint <- get_opt j "checkpoint";
          s.blocked_since <- get_str j "ts" ""
        end
      with _ ->
        err "E_INVALID_PLAN" (`Assoc []) "Malformed ledger line." 1
  );
  (s, !quest_type, !depends_on)

let ledger_text branch path =
  match ref_tip branch with
  | None -> None
  | Some tip -> (match git_show tip path with Some t -> Some (tip, t) | None -> Some (tip, ""))

let quest_branch q = "refs/heads/bp3/quest/" ^ q
let exp_branch q e = "refs/heads/bp3/exp/" ^ q ^ "/" ^ e
let quest_dir q = "docs/quests/" ^ q
let quest_ledger_path q = quest_dir q ^ "/ledger.jsonl"
let exp_dir q e = quest_dir q ^ "/experiments/" ^ e
let exp_ledger_path q e = exp_dir q e ^ "/ledger.jsonl"
let exp_state_path q e = exp_dir q e ^ "/state.yaml"

let list_refs prefix =
  let out, code = git_out ["for-each-ref"; "--format=%(refname)"; prefix] in
  if code <> 0 then [] else
  String.split_on_char '\n' out |> List.map String.trim |> List.filter (fun s -> s <> "")

let list_quests () =
  list_refs "refs/heads/bp3/quest/" |> List.map (fun r ->
    let p = "refs/heads/bp3/quest/" in String.sub r (String.length p) (String.length r - String.length p))

let list_exps q =
  let p = "refs/heads/bp3/exp/" ^ q ^ "/" in
  list_refs p |> List.map (fun r -> String.sub r (String.length p) (String.length r - String.length p))

let fold_exp q e =
  match ledger_text (exp_branch q e) (exp_ledger_path q e) with
  | None -> None
  | Some (tip, text) -> let (s, _, _) = fold_ledger text in Some (tip, s, text)

let fold_quest q =
  match ledger_text (quest_branch q) (quest_ledger_path q) with
  | None -> None
  | Some (tip, text) -> let (s, qt, deps) = fold_ledger text in Some (tip, s, qt, deps, text)

let legal_edges st =
  match st with
  | "todo" -> ["submit"; "block"; "delete"]
  | "submitted" -> ["review"; "check"; "block"; "delete"]
  | "approved" -> ["land"; "block"; "delete"]
  | "blocked" -> ["resume"; "delete"]
  | _ -> []

let state_yaml q e s =
  Printf.sprintf "quest: %s\nexp: %s\nstate: %s\ncycle: %d\ncommit: %s\n"
    q e s.st s.cycle (match s.last_commit with Some c -> c | None -> "none")

let ledger_line ~edge ~from ~to_ ~cycle ~commit ~verdict ~reason ~id
    ?checkpoint ?extra () =
  let base = [
    ("ts", json_str (now_ts ()));
    ("edge", json_str edge);
    ("from", json_str from);
    ("to", json_str to_);
    ("cycle", `Int cycle);
    ("commit", (match commit with Some c -> json_str c | None -> `Null));
    ("verdict", (match verdict with Some v -> json_str v | None -> `Null));
    ("reason", json_str reason);
    ("harness", json_str id.harness);
    ("model", json_str id.model);
    ("bp3_version", json_str bp3_version);
  ] in
  let base = match checkpoint with Some c -> base @ [("checkpoint", json_str c)] | None -> base in
  let base = base @ (match extra with Some xs -> xs | None -> []) in
  Yojson.Safe.to_string (`Assoc base)

let append_exp_line q e line new_state =
  let branch = exp_branch q e in
  match ledger_text branch (exp_ledger_path q e) with
  | None -> not_found "exp" e
  | Some (tip, text) ->
      let new_text = (if String.trim text = "" then "" else
        (if text.[String.length text - 1] = '\n' then text else text ^ "\n")) ^ line ^ "\n" in
      commit_files ~branch ~base_tip:tip ~expect_tip:tip
        ~files:[(exp_ledger_path q e, new_text); (exp_state_path q e, state_yaml q e new_state)]
        ~msg:("bp3: " ^ e)

let make_checkpoint () =
  let idx = tmp_path "ckpt-index" in
  Unix.putenv "GIT_INDEX_FILE" idx;
  let head = head_sha () in
  ignore (run_status (git ["read-tree"; head]));
  ignore (run_status (git ["add"; "-A"]));
  let treef = tmp_path "ckpt-tree" in
  ignore (Sys.command (String.concat " " (List.map Filename.quote (git ["write-tree"]))
      ^ " > " ^ Filename.quote treef ^ " 2>/dev/null"));
  let tree = String.trim (read_file_or treef "") in
  let msgf = write_tmp "bp3 checkpoint" in
  let cf = tmp_path "ckpt-commit" in
  ignore (Sys.command (String.concat " " (List.map Filename.quote (git ["commit-tree"; tree; "-p"; head]))
      ^ " < " ^ Filename.quote msgf ^ " > " ^ Filename.quote cf ^ " 2>/dev/null"));
  Unix.putenv "GIT_INDEX_FILE" "";
  String.trim (read_file_or cf "")

let dep_satisfied dep =
  match fold_quest dep with
  | None -> false
  | Some (_, qs, _, _, _) ->
      if qs.st = "deleted" then false
      else
        let exps = list_exps dep in
        exps <> [] && List.for_all (fun e ->
          match fold_exp dep e with Some (_, s, _) -> s.st = "landed" || s.st = "deleted" | None -> false) exps

(* ---------- verdict builders ---------- *)
(* The proposed changeset of the bound commit: what a reviewer is
   actually being asked to judge, visible before land. Diff of the
   commit against its first parent. +/-/u alphabet, same as tree. *)
let commit_changes = function
  | None -> None (* unsure: nothing bound yet *)
  | Some c ->
      let out, code = git_out ["diff-tree"; "--no-commit-id"; "--name-status"; "-r"; c] in
      if code <> 0 then None (* unsure: unreadable diff *) else
      Some (List.filter_map (fun line ->
        match String.split_on_char '\t' line with
        | [st; path] ->
            let kind = if st = "" then "u" else
              (match st.[0] with 'A' -> "+" | 'D' -> "-" | _ -> "u") in
            Some (`Assoc [("change", json_str kind); ("path", json_str path)])
        | [st; _old; path] -> (* rename/copy: show the new path as updated *)
            let kind = if st <> "" && st.[0] = 'C' then "+" else "u" in
            Some (`Assoc [("change", json_str kind); ("path", json_str path)])
        | _ -> None)
      (List.filter (fun l -> l <> "") (String.split_on_char '\n' out)))

let exp_json _q e s =
  `Assoc [
    ("exp", json_str e); ("state", json_str s.st); ("cycle", `Int s.cycle);
    ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
    ("legal_edges", `List (List.map json_str (legal_edges s.st)));
    ("changes", (match commit_changes s.last_commit with
       | Some xs -> `List xs | None -> `Null)); (* null = unsure *)
  ]

let exp_verdict quest e s =
  match exp_json quest e s with
  | `Assoc fs -> `Assoc (("ok", `Bool true) :: ("quest", json_str quest) :: fs)
  | other -> other

let quest_view q =
  match fold_quest q with
  | None -> not_found "quest" q
  | Some (_, qs, _qt, _deps, _) ->
      let exps = list_exps q in
      let exp_states = List.map (fun e ->
        match fold_exp q e with Some (_, s, _) -> (e, s) | None -> (e, fresh_state ())) exps in
      let inbox = List.filter_map (fun (e, s) ->
        if s.st = "blocked" then Some (`Assoc [
          ("quest", json_str q); ("exp", json_str e);
          ("reason", json_str s.blocked_reason);
          ("checkpoint", (match s.blocked_checkpoint with Some c -> json_str c | None -> `Null));
          ("cycle", `Int s.cycle); ("since", json_str s.blocked_since);
        ]) else None) exp_states in
      let rollup =
        if qs.st = "deleted" then "deleted"
        else if exp_states <> [] && List.for_all (fun (_, s) -> s.st = "landed" || s.st = "deleted") exp_states then "landed"
        else if List.exists (fun (_, s) -> s.st = "blocked") exp_states then "blocked"
        else "active" in
      (`Assoc [
        ("quest", json_str q); ("state", json_str qs.st);
        ("exps", `List (List.map (fun (e, s) -> exp_json q e s) exp_states));
        ("rollup", json_str rollup); ("inbox", `List inbox);
      ], inbox, rollup, qs)

let tree_marker = function
  | "todo" -> "+"
  | "submitted" | "approved" | "blocked" -> "u"
  | "deleted" -> "-"
  | _ -> " " (* landed: clean, like git status *)

let short_commit = function
  | Some c when String.length c > 7 -> String.sub c 0 7
  | Some c -> c
  | None -> "-"

let render_tree fields =
  let get k = List.assoc_opt k fields in
  let str k = match get k with Some (`String s) -> s | _ -> "?" in
  Printf.printf "%s [%s] rollup: %s\n" (str "quest") (str "state") (str "rollup");
  let exps = match get "exps" with Some (`List xs) -> xs | _ -> [] in
  let n = List.length exps in
  List.iteri (fun i item ->
    match item with
    | `Assoc fs ->
        let g k = List.assoc_opt k fs in
        let s k = match g k with Some (`String x) -> x | _ -> "?" in
        let state = s "state" in
        let cycle = match g "cycle" with Some (`Int c) -> c | _ -> 0 in
        let commit = match g "commit" with Some (`String c) -> Some c | _ -> None in
        let branch = if i = n - 1 then "`___> " else "|___> " in
        let owed = if state = "blocked" then "  (human owed)" else "" in
        let counts = match g "changes" with
          | Some (`List xs) when xs <> [] ->
              let cnt k = List.length (List.filter (fun item ->
                match item with `Assoc fs ->
                  (match List.assoc_opt "change" fs with Some (`String x) -> x = k | _ -> false)
                | _ -> false) xs) in
              Printf.sprintf "  [+%d u%d -%d]" (cnt "+") (cnt "u") (cnt "-")
          | Some (`List []) -> ""
          | _ -> "  [?]" in
        Printf.printf "%s%s %s - %s, cycle %d, commit %s%s%s\n"
          branch (tree_marker state) (s "exp") state cycle (short_commit commit) counts owed
    | _ -> ()) exps;
  (match get "inbox" with
   | Some (`List (_ :: _ as xs)) ->
       Printf.printf "human owed:\n";
       List.iter (fun item ->
         match item with
         | `Assoc fs ->
             let s k = match List.assoc_opt k fs with Some (`String x) -> x | _ -> "?" in
             Printf.printf "  u %s - %S (since %s)\n" (s "exp") (s "reason") (s "since")
         | _ -> ()) xs
   | _ -> ())

let render_tree_exp fields =
  let g k = List.assoc_opt k fields in
  let s k = match g k with Some (`String x) -> x | _ -> "?" in
  let state = s "state" in
  let cycle = match g "cycle" with Some (`Int c) -> c | _ -> 0 in
  let commit = match g "commit" with Some (`String c) -> Some c | _ -> None in
  let legal = match g "legal_edges" with
    | Some (`List xs) ->
        String.concat ", " (List.map (function `String x -> x | o -> Yojson.Safe.to_string o) xs)
    | _ -> "" in
  Printf.printf "%s\n`___> %s %s - %s, cycle %d, commit %s\n    legal: %s\n"
    (s "quest") (tree_marker state) (s "exp") state cycle
    (short_commit commit) (if legal = "" then "none" else legal);
  (match g "changes" with
   | Some (`List (_ :: _ as xs)) ->
       Printf.printf "    changes (%d):\n" (List.length xs);
       List.iter (fun item ->
         match item with
         | `Assoc fs ->
             let c k = match List.assoc_opt k fs with Some (`String x) -> x | _ -> "?" in
             Printf.printf "      %s %s\n" (c "change") (c "path")
         | _ -> ()) xs
   | Some (`List []) -> Printf.printf "    changes: none\n"
   | _ -> Printf.printf "    changes: ?\n")

let print_verdict ~fmt v =
  match fmt, v with
  | "tree", `Assoc fields when List.mem_assoc "exps" fields ->
      render_tree fields
  | "tree", `Assoc fields when List.mem_assoc "exp" fields ->
      render_tree_exp fields
  | "table", `Assoc fields ->
      List.iter (fun (k, v) ->
        match v with
        | `List xs ->
            Printf.printf "%s:\n" k;
            List.iter (fun item ->
              match item with
              | `Assoc fs -> Printf.printf "  %s\n" (String.concat " " (List.map (fun (a, b) -> a ^ "=" ^ Yojson.Safe.to_string b) fs))
              | other -> Printf.printf "  %s\n" (Yojson.Safe.to_string other)) xs
        | other -> Printf.printf "%s: %s\n" k (match other with `String s -> s | o -> Yojson.Safe.to_string o)
      ) fields
  | _, _ -> print_endline (Yojson.Safe.to_string v)

(* ---------- argv parsing ---------- *)
type flags = {
  reason : string option; commit : string option; verdict : string option;
  target : string option; typ : string option; depends_on : string option;
  fmt : string;
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
    | "--reason" :: [] | "--commit" :: [] | "--verdict" :: [] | "--target" :: []
    | "--type" :: [] | "--depends-on" :: [] | "--format" :: [] ->
        usage "flag needs a value"
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
         typ = None; depends_on = None; fmt = "json" } args

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

let require_reason fl =
  match fl.reason with Some r when r <> "" -> r | _ -> usage "--reason is required"

let with_warnings id is_write fields =
  match warnings_of id is_write with
  | [] -> `Assoc fields
  | ws -> `Assoc (fields @ [("warnings", `List (List.map json_str ws))])

let illegal state edge =
  err "E_ILLEGAL_EDGE"
    (`Assoc [("state", json_str state); ("edge", json_str edge);
             ("legal_edges", `List (List.map json_str (legal_edges state)))])
    "Pick a legal edge from legal_edges for the current state." 1

(* ---------- operations ---------- *)
let do_quest_create quest fl id =
  check_slug quest;
  let qtype = (match fl.typ with Some t -> t | None -> "default") in
  let _ = quest_knobs qtype in
  if ref_tip (quest_branch quest) <> None then
    err "E_EXISTS" (`Assoc [("quest", json_str quest)]) "Quest already exists." 1;
  let deps = match fl.depends_on with
    | Some s when s <> "" -> String.split_on_char ',' s |> List.map String.trim
    | _ -> [] in
  List.iter check_slug deps;
  let head = head_sha () in
  let qpath = quest_dir quest ^ "/QUEST.md" in
  let existing_quest_md = git_show head qpath in
  let quest_md = match existing_quest_md with
    | Some c -> c
    | None -> Printf.sprintf "---\nstatus: proposed\nquest_type: %s\n---\n\n# %s\n\n## Success picture\n\nTODO\n" qtype quest in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"proposed" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("quest_type", json_str qtype);
            ("depends_on", `List (List.map json_str deps))] () in
  let existing_ledger = git_show head (quest_ledger_path quest) in
  let ledger = (match existing_ledger with Some t when String.trim t <> "" -> t ^ (if t.[String.length t-1] = '\n' then "" else "\n") | _ -> "") ^ line ^ "\n" in
  let _new_tip = create_branch_commit ~branch:(quest_branch quest) ~base_tip:head
    ~files:[(qpath, quest_md); (quest_ledger_path quest, ledger)] ~msg:("bp3: create quest " ^ quest) in
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest); ("state", json_str "proposed")]

let do_quest_delete quest fl id =
  check_slug quest;
  let reason = require_reason fl in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let (view, _, _, qs) = quest_view quest in
  ignore view;
  if qs.st = "deleted" then illegal "deleted" "delete";
  let exps = list_exps quest in
  let any_blocked = List.exists (fun e ->
    match fold_exp quest e with Some (_, s, _) -> s.st = "blocked" | None -> false) exps in
  if any_blocked && not id.decider_human then
    err "E_HUMAN_REQUIRED" (`Assoc [("quest", json_str quest)])
      "An exp is blocked; a human decision is required (BP3_DECIDER=human)." 1;
  (match ledger_text (quest_branch quest) (quest_ledger_path quest) with
   | None -> not_found "quest" quest
   | Some (tip, text) ->
       let line = ledger_line ~edge:"delete" ~from:qs.st ~to_:"deleted" ~cycle:1
         ~commit:None ~verdict:None ~reason ~id () in
       let new_text = text ^ (if text = "" || text.[String.length text-1] = '\n' then "" else "\n") ^ line ^ "\n" in
       ignore (commit_files ~branch:(quest_branch quest) ~base_tip:tip ~expect_tip:tip
         ~files:[(quest_ledger_path quest, new_text)] ~msg:("bp3: delete quest " ^ quest)));
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest); ("state", json_str "deleted")]

let do_exp_create quest exp fl id =
  check_slug quest; check_slug exp;
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let etype = (match fl.typ with Some t -> t | None -> "default") in
  (* validate exp plan exists for non-default *)
  (match fold_quest quest with
   | Some (_, _, qt, _, _) -> ignore (effective_knobs ~quest_type:qt ~exp_type:etype)
   | None -> ());
  if ref_tip (exp_branch quest exp) <> None then
    err "E_EXISTS" (`Assoc [("quest", json_str quest); ("exp", json_str exp)]) "Exp already exists." 1;
  let qtip = (match ref_tip (quest_branch quest) with Some t -> t | None -> not_found "quest" quest) in
  let st = fresh_state () in
  let line = ledger_line ~edge:"create" ~from:"" ~to_:"todo" ~cycle:1
    ~commit:None ~verdict:None ~reason:"" ~id
    ~extra:[("exp_type", json_str etype)] () in
  let _ = create_branch_commit ~branch:(exp_branch quest exp) ~base_tip:qtip
    ~files:[(exp_ledger_path quest exp, line ^ "\n");
            (exp_state_path quest exp, state_yaml quest exp st)]
    ~msg:("bp3: create exp " ^ exp) in
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
    ("exp", json_str exp); ("state", json_str "todo"); ("cycle", `Int 1);
    ("legal_edges", `List (List.map json_str (legal_edges "todo")))]

let do_exp_delete quest exp fl id =
  check_slug quest; check_slug exp;
  let reason = require_reason fl in
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  (match fold_exp quest exp with
   | None -> not_found "exp" exp
   | Some (_, s, _) ->
       if s.st = "landed" || s.st = "deleted" then illegal s.st "delete";
       if s.st = "blocked" && not id.decider_human then
         err "E_HUMAN_REQUIRED" (`Assoc [("quest", json_str quest); ("exp", json_str exp)])
           "Deleting a blocked exp requires a human (BP3_DECIDER=human)." 1;
       let ns = { s with st = "deleted" } in
       let line = ledger_line ~edge:"delete" ~from:s.st ~to_:"deleted" ~cycle:s.cycle
         ~commit:s.last_commit ~verdict:None ~reason ~id () in
       ignore (append_exp_line quest exp line ns));
  with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
    ("exp", json_str exp); ("state", json_str "deleted")]

let do_update quest exp edge fl id =
  check_slug quest; check_slug exp;
  let reason = require_reason fl in
  if not (List.mem edge ["submit"; "review"; "check"; "land"; "block"; "resume"]) then
    usage ("unknown edge: " ^ edge);
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  let (_, s, _) = (match fold_exp quest exp with Some v -> v | None -> not_found "exp" exp) in
  let (_, qt, deps) = (match fold_quest quest with Some (_, _, a, b, _) -> ((), a, b) | None -> not_found "quest" quest) in
  let knobs = effective_knobs ~quest_type:qt ~exp_type:s.exp_type in
  let finish ns line =
    ignore (append_exp_line quest exp line ns);
    with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
      ("exp", json_str exp); ("state", json_str ns.st); ("cycle", `Int ns.cycle);
      ("commit", (match ns.last_commit with Some c -> json_str c | None -> `Null));
      ("legal_edges", `List (List.map json_str (legal_edges ns.st)))] in
  match edge with
  | "submit" ->
      if s.st <> "todo" then illegal s.st edge;
      let raw = (match fl.commit with Some c -> c | None -> usage "--commit is required for submit") in
      let full = (match resolve_commit raw with Some f -> f
        | None -> err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str raw)])
            "Commit does not exist; bind an existing commit." 1) in
      if worktree_dirty () then
        err "E_DIRTY_TREE" (`Assoc []) "Worktree is dirty; clean it and retry." 1;
      let blocked_by = List.filter (fun d -> not (dep_satisfied d)) deps in
      if blocked_by <> [] then
        err "E_DEPENDENCY" (`Assoc [("blocked_by", `List (List.map json_str blocked_by))])
          "Dependencies are not landed yet." 1;
      let approved_now = (not knobs.review_required) && (not knobs.checks_required) in
      let ns = { s with st = (if approved_now then "approved" else "submitted");
                 bound = Some full; has_bound = true; last_commit = Some full;
                 review_ok = false; check_ok = false } in
      let line = ledger_line ~edge ~from:s.st ~to_:ns.st ~cycle:s.cycle
        ~commit:(Some full) ~verdict:None ~reason ~id () in
      finish ns line
  | "review" | "check" ->
      if s.st <> "submitted" then illegal s.st edge;
      let v = (match fl.verdict with Some v -> v | None -> usage "--verdict is required") in
      let valid = if edge = "review" then (v = "ship" || v = "needs_fix") else (v = "pass" || v = "fail") in
      if not valid then usage ("invalid verdict for " ^ edge ^ ": " ^ v);
      (match fl.commit with
       | Some c ->
           let rc = (match resolve_commit c with Some f -> f | None -> c) in
           let bound = (match s.bound with Some b -> b | None -> "") in
           if rc <> bound then
             err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str c); ("bound", json_str bound)])
               "Verdict must bind the exact current commit; re-read and retry." 1
       | None -> ());
      let positive = (v = "ship" || v = "pass") in
      if not positive then begin
        let (nst, ncyc) =
          if s.cycle >= knobs.max_cycles then ("blocked", s.cycle) else ("todo", s.cycle + 1) in
        let ns = { s with st = nst; cycle = ncyc; review_ok = false; check_ok = false } in
        if nst = "blocked" then begin ns.blocked_reason <- reason; ns.blocked_since <- now_ts () end;
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:ncyc
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id () in
        let base = finish ns line in
        if nst = "blocked" then
          (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
        else base
      end else begin
        let ns = { s with review_ok = (if edge = "review" then true else s.review_ok);
                          check_ok = (if edge = "check" then true else s.check_ok) } in
        let now_approved =
          ((not knobs.review_required) || ns.review_ok) &&
          ((not knobs.checks_required) || ns.check_ok) in
        let nst = if now_approved then "approved" else "submitted" in
        let ns = { ns with st = nst } in
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:s.cycle
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id () in
        finish ns line
      end
  | "land" ->
      if s.st <> "approved" then illegal s.st edge;
      (match fl.commit with
       | Some c ->
           let rc = (match resolve_commit c with Some f -> f | None -> c) in
           let bound = (match s.bound with Some b -> b | None -> "") in
           if rc <> bound then
             err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str c)])
               "Verdict must bind the exact current commit." 1
       | None -> ());
      (* 1. landed line on exp branch *)
      let ns = { s with st = "landed" } in
      let line = ledger_line ~edge ~from:s.st ~to_:"landed" ~cycle:s.cycle
        ~commit:s.last_commit ~verdict:None ~reason ~id () in
      ignore (append_exp_line quest exp line ns);
      let exp_tip = (match ref_tip (exp_branch quest exp) with Some t -> t | None -> "") in
      let qbranch = quest_branch quest in
      let qtip = (match ref_tip qbranch with Some t -> t | None -> "") in
      if is_ancestor qtip exp_tip then begin
        if run_status (git ["update-ref"; qbranch; exp_tip; qtip]) <> 0 then
          err "E_STALE_WORLD" (`Assoc []) "Quest tip moved; re-read and retry." 1;
        with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
          ("exp", json_str exp); ("state", json_str "landed"); ("cycle", `Int s.cycle);
          ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
          ("legal_edges", `List [])]
      end else begin
        let tree_out, code = git_out ["merge-tree"; "--write-tree"; qtip; exp_tip] in
        let tree = (match String.split_on_char '\n' tree_out with t :: _ -> String.trim t | [] -> "") in
        if code <> 0 || tree = "" then begin
          let ns2 = { s with st = "todo" } in
          let line2 = ledger_line ~edge:"land" ~from:"approved" ~to_:"todo" ~cycle:s.cycle
            ~commit:s.last_commit ~verdict:None ~reason ~id () in
          ignore (append_exp_line quest exp line2 ns2);
          `Assoc [("ok", `Bool true); ("quest", json_str quest); ("exp", json_str exp);
            ("state", json_str "todo"); ("cycle", `Int s.cycle);
            ("facts", `Assoc [("land_conflict", `Bool true)]);
            ("legal_edges", `List (List.map json_str (legal_edges "todo")))]
        end else begin
          let msgf = write_tmp ("bp3: land " ^ exp) in
          let cf = tmp_path "merge-commit" in
          ignore (Sys.command (String.concat " " (List.map Filename.quote
              (git ["commit-tree"; tree; "-p"; qtip; "-p"; exp_tip]))
            ^ " < " ^ Filename.quote msgf ^ " > " ^ Filename.quote cf ^ " 2>/dev/null"));
          let mtip = String.trim (read_file_or cf "") in
          if run_status (git ["update-ref"; qbranch; mtip; qtip]) <> 0 then
            err "E_STALE_WORLD" (`Assoc []) "Quest tip moved; re-read and retry." 1;
          with_warnings id true [("ok", `Bool true); ("quest", json_str quest);
            ("exp", json_str exp); ("state", json_str "landed"); ("cycle", `Int s.cycle);
            ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
            ("legal_edges", `List [])]
        end
      end
  | "block" ->
      if not (List.mem s.st ["todo"; "submitted"; "approved"]) then illegal s.st edge;
      let checkpoint = if worktree_dirty () then Some (make_checkpoint ()) else None in
      let ns = { s with st = "blocked"; blocked_reason = reason;
                 blocked_checkpoint = checkpoint; blocked_since = now_ts () } in
      let line = ledger_line ~edge ~from:s.st ~to_:"blocked" ~cycle:s.cycle
        ~commit:s.last_commit ~verdict:None ~reason ~id ?checkpoint () in
      let base = finish ns line in
      (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
  | "resume" ->
      if s.st <> "blocked" then illegal s.st edge;
      if not id.decider_human then
        err "E_HUMAN_REQUIRED" (`Assoc [("quest", json_str quest); ("exp", json_str exp)])
          "Resume requires a human decision (BP3_DECIDER=human)." 1;
      let ncyc = if s.has_bound then s.cycle + 1 else s.cycle in
      let ns = { s with st = "todo"; cycle = ncyc; bound = None; has_bound = false;
                 review_ok = false; check_ok = false } in
      let line = ledger_line ~edge ~from:s.st ~to_:"todo" ~cycle:ncyc
        ~commit:None ~verdict:None ~reason ~id () in
      finish ns line
  | _ -> usage ("unknown edge: " ^ edge)

(* ---------- main dispatch ---------- *)
let normalize_verb = function
  | "c" | "create" -> "c" | "r" | "read" -> "r"
  | "u" | "update" -> "u" | "d" | "delete" -> "d"
  | other -> other

let is_verb = function "c" | "create" | "r" | "read" | "u" | "update" | "d" | "delete" -> true | _ -> false

let run argv =
  let id = identity () in
  match argv with
  | [] -> usage "no command"
  | first :: rest when is_verb first ->
      let verb = normalize_verb first in
      (match verb, rest with
       | "c", quest :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in quest create";
           let v = do_quest_create quest fl id in print_verdict ~fmt:fl.fmt v; 0
       | "c", [] -> usage "quest create needs a quest name"
       | "r", [] ->
           let qs = List.map (fun q ->
             let (view, _, _, _) = quest_view q in view) (list_quests ()) in
           print_verdict ~fmt:"json" (`Assoc [("ok", `Bool true); ("quests", `List qs)]); 0
       | "r", [quest] ->
           let (pos, fl) = ( [quest], { reason=None; commit=None; verdict=None; target=None; typ=None; depends_on=None; fmt="json" } ) in
           ignore pos;
           (* re-parse: quest may be followed by --format in original rest; handled below *)
           ignore fl;
           let (view, _, _, _) = quest_view quest in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []))); 0
       | "r", quest :: tail ->
           let (pos, fl) = split_flags (quest :: tail) in
           (match pos with
            | [q] ->
                let (view, _, _, _) = quest_view q in
                print_verdict ~fmt:fl.fmt (`Assoc (("ok", `Bool true) ::
                  (match view with `Assoc fs -> fs | _ -> []))); 0
            | _ -> usage "quest read takes at most one quest")
       | "d", quest :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in quest delete";
           let v = do_quest_delete quest fl id in print_verdict ~fmt:fl.fmt v; 0
       | "d", [] -> usage "quest delete needs a quest name"
       | _ -> usage "quest door verbs are c, r, d")
  | quest :: verb_raw :: rest when is_verb verb_raw ->
      let verb = normalize_verb verb_raw in
      (match verb, rest with
       | "c", exp :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in exp create";
           let v = do_exp_create quest exp fl id in print_verdict ~fmt:fl.fmt v; 0
       | "c", [] -> usage "exp create needs an exp name"
       | "r", [] ->
           let (view, _, _, _) = quest_view quest in
           print_verdict ~fmt:"json" (`Assoc (("ok", `Bool true) ::
             (match view with `Assoc fs -> fs | _ -> []))); 0
       | "r", [exp] ->
           (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
           (match fold_exp quest exp with
            | None -> not_found "exp" exp
            | Some (_, s, _) -> print_verdict ~fmt:"json" (exp_verdict quest exp s); 0)
       | "r", exp :: tail ->
           let (pos, fl) = split_flags (exp :: tail) in
           (match pos with
            | [e] ->
                (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
                (match fold_exp quest e with
                 | None -> not_found "exp" e
                 | Some (_, s, _) -> print_verdict ~fmt:fl.fmt (exp_verdict quest e s); 0)
            | _ -> usage "exp read takes at most one exp")
       | "u", exp :: edge :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in update";
           let v = do_update quest exp edge fl id in print_verdict ~fmt:fl.fmt v; 0
       | "u", _ -> usage "update needs <exp> <edge>"
       | "d", exp :: tail ->
           let (pos, fl) = split_flags tail in
           if pos <> [] then usage "stray positional in exp delete";
           let v = do_exp_delete quest exp fl id in print_verdict ~fmt:fl.fmt v; 0
       | "d", [] -> usage "exp delete needs an exp name"
       | _ -> usage "exp door verbs are c, r, u, d")
  | _ -> usage "expected: q c|r|d ... or q <quest> c|r|u|d ..."

let () =
  let argv = List.tl (Array.to_list Sys.argv) in
  try exit (run argv)
  with Verdict (code, v) ->
    print_endline (Yojson.Safe.to_string v);
    exit code


