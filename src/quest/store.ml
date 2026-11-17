(* store — identity, plans, ledger fold: the truth layer. *)
open Gitx

(* ---------- slugs / identity ---------- *)
let valid_slug s =
  let n = String.length s in
  n >= 1 &&
  (let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-' in
   let rec loop i = i >= n || (ok s.[i] && loop (i + 1)) in
   ((s.[0] >= 'a' && s.[0] <= 'z') || (s.[0] >= '0' && s.[0] <= '9')) && loop 1)

let check_slug s = if not (valid_slug s) then usage ("invalid slug: " ^ s)

(* Door and verb spellings across every bp3 door. A created
   quest or exp carrying one of these slugs could never be
   addressed again (the token would parse as the door or
   verb instead), so creation refuses it; reads stay total. *)
let reserved_slugs =
  [ "harness"; "worktree"; "icebox"; "hooks"; "init-repo"; "config"; "e";
    "supervisor"; "init-check"; "find-tape"; "watch"; "desk"; "backtest"; "b";
    "c"; "create"; "r"; "read"; "u"; "update"; "d"; "delete";
    "s"; "i"; "f"; "w";
    "derive"; "inspect"; "remove"; "prepare"; "check"; "exit";
    "release"; "list" ]

let check_creatable s =
  check_slug s;
  if List.mem s reserved_slugs then
    usage ("reserved slug: " ^ s ^ " names a bp3 door or verb")

type identity = { harness : string; model : string; decider_human : bool; incomplete : bool; run_id : string option }

let run_id_of_env () =
  match Sys.getenv_opt "BP3_RUN_ID" with Some v when v <> "" -> Some v | _ -> None

(* The claimed run-id (mvp.2 context resolution), set by the
   CLI door once per call when a rung resolves. The claim
   wins over the env hint; env alone keeps the legacy
   stamping for unclaimed callers. *)
let resolved_run_id : string option ref = ref None
let context_warnings : string list ref = ref []

let effective_run_id () =
  match !resolved_run_id with Some _ as r -> r | None -> run_id_of_env ()

let stamp_run_id = function
  | `Assoc fs ->
      (match effective_run_id () with
       | Some r ->
           `Assoc (List.filter (fun (k, _) -> k <> "run_id") fs
                   @ [("run_id", json_str r)])
       | None -> `Assoc fs)
  | v -> v

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
  { harness; model; decider_human; incomplete; run_id = run_id_of_env () }

let parse_version s =
  try List.map int_of_string (String.split_on_char '.' s) with _ -> [0]

let rec version_cmp a b =
  match a, b with
  | [], [] -> 0
  | [], _ -> version_cmp [0] b
  | _, [] -> version_cmp a [0]
  | x :: xs, y :: ys -> if x <> y then compare x y else version_cmp xs ys

let version_major v = match parse_version v with m :: _ -> m | [] -> 0

(* ---------- plans ---------- *)
type knobs = { max_cycles : int; grade_required : bool; verify_required : bool }

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
  let grade_required =
    (* look at grade section: 'required: false' after 'grade:' *)
    if contains_sub text "required: false" && contains_sub text "grade:" then false
    else if contains_sub text "grade.required: false" then false
    else true in
  let grade_required =
    if contains_sub text "required: false" then
      (* only counts if a grade: key exists or grade_required spelling *)
      grade_required else grade_required in
  let verify_required =
    not (contains_sub text "verify: optional" || contains_sub text "verify: none"
         || contains_sub text "verify:optional" || contains_sub text "verify:none") in
  { max_cycles; grade_required; verify_required }

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
  mutable grade_ok : bool;
  mutable verify_ok : bool;
  mutable blocked_reason : string;
  mutable blocked_checkpoint : string option;
  mutable blocked_since : string;
  mutable last_commit : string option;
  mutable exp_type : string;
}

let fresh_state () = {
  st = "todo"; cycle = 1; bound = None; has_bound = false;
  grade_ok = false; verify_ok = false;
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

(* The one compat mapping (mig.1): pre-rename ledger strings fold
   to the new words here and nowhere else; new ledger lines already
   carry the new words. *)
let fold_edge = function
  | "submit" -> "handoff" | "review" -> "grade" | "check" -> "verify"
  | e -> e

let fold_state_name = function "submitted" -> "handed_off" | s -> s

let fold_ledger text =
  let s = fresh_state () in
  let quest_type = ref "default" in
  let depends_on = ref [] in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        let edge = fold_edge (get_str j "edge" "") in
        let to_ = fold_state_name (get_str j "to" "") in
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
        if edge = "handoff" then begin s.grade_ok <- false; s.verify_ok <- false end;
        if edge = "grade" && get_str j "verdict" "" = "ship" then s.grade_ok <- true;
        if edge = "verify" && get_str j "verdict" "" = "pass" then s.verify_ok <- true;
        if (edge = "grade" && get_str j "verdict" "" = "needs_fix") ||
           (edge = "verify" && get_str j "verdict" "" = "fail") then begin
          s.grade_ok <- false; s.verify_ok <- false
        end;
        if edge = "resume" then begin s.bound <- None; s.has_bound <- false; s.grade_ok <- false; s.verify_ok <- false end;
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

(* newest bp3_version stamped in any quest/exp ledger in this repo *)
let newest_bp3_version () =
  let from_text acc text =
    List.fold_left (fun acc line ->
      try
        match Yojson.Safe.from_string line with
        | `Assoc fs ->
            (match List.assoc_opt "bp3_version" fs with
             | Some (`String v) ->
                 (match acc with
                  | Some cur when version_cmp (parse_version cur) (parse_version v) >= 0 -> acc
                  | _ -> Some v)
             | _ -> acc)
        | _ -> acc
      with _ -> acc) acc (String.split_on_char '\n' text) in
  List.fold_left (fun acc q ->
    let acc = match ledger_text (quest_branch q) (quest_ledger_path q) with
      | Some (_, t) -> from_text acc t | None -> acc in
    List.fold_left (fun acc e ->
      match ledger_text (exp_branch q e) (exp_ledger_path q e) with
      | Some (_, t) -> from_text acc t | None -> acc) acc (list_exps q))
    None (list_quests ())

let version_ahead () =
  match newest_bp3_version () with
  | Some v when version_cmp (parse_version v) (parse_version bp3_version) > 0 -> Some v
  | _ -> None

let warnings_of id is_write =
  (if is_write && id.incomplete then ["W_IDENTITY_UNKNOWN"] else [])
  @ (match version_ahead () with Some _ -> ["W_VERSION_AHEAD"] | None -> [])

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
  | "todo" -> ["handoff"; "block"; "delete"]
  | "handed_off" -> ["grade"; "verify"; "block"; "delete"]
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
  let base = match id.run_id with Some r -> base @ [("run_id", json_str r)] | None -> base in
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

(* ---------- icebox reader ---------- *)
(* Frozen entries are plain files, not state: read-only, dumb
   line parsing, malformed files degrade to [-] fields. *)
type icebox_entry = {
  slug : string; date : string; status : string;
  promoted : string option; title : string; text : string;
}

let parse_icebox_entry slug text =
  let lines = String.split_on_char '\n' text in
  let fm_lines = match lines with
    | first :: rest when String.trim first = "---" ->
        let rec take acc = function
          | [] -> []
          | l :: _ when String.trim l = "---" -> List.rev acc
          | l :: r -> take (l :: acc) r in
        take [] rest
    | _ -> [] in
  let field k =
    let rec go = function
      | [] -> None
      | l :: r ->
          (match String.index_opt l ':' with
           | Some i when String.trim (String.sub l 0 i) = k ->
               let v = String.trim (String.sub l (i + 1) (String.length l - i - 1)) in
               if v = "" then None else Some v
           | _ -> go r) in
    go fm_lines in
  let or_dash = function Some v -> v | None -> "-" in
  let promoted = match field "promoted" with Some "null" -> None | other -> other in
  let title =
    let rec go = function
      | [] -> "-"
      | l :: r when String.length l >= 2 && String.sub l 0 2 = "# " ->
          let t = String.trim (String.sub l 2 (String.length l - 2)) in
          if t = "" then go r else t
      | _ :: r -> go r in
    go lines in
  { slug; date = or_dash (field "date"); status = or_dash (field "status");
    promoted; title; text }

let list_icebox_entries () =
  let dir = Filename.concat root "docs/icebox" in
  let names = try Array.to_list (Sys.readdir dir) with _ -> [] in
  names
  |> List.filter (fun n -> n <> "README.md" && Filename.check_suffix n ".md"
      && not (try Sys.is_directory (Filename.concat dir n) with _ -> false))
  |> List.sort String.compare
  |> List.map (fun n ->
       parse_icebox_entry (Filename.remove_extension n)
         (read_file_or (Filename.concat dir n) ""))

let icebox_matches e terms =
  let hay = String.lowercase_ascii (e.slug ^ "\n" ^ e.title ^ "\n" ^ e.text) in
  List.for_all (fun t -> contains_sub hay (String.lowercase_ascii t)) terms

let icebox_entry_json e =
  `Assoc [("slug", json_str e.slug); ("date", json_str e.date);
          ("status", json_str e.status);
          ("promoted", (match e.promoted with Some p -> json_str p | None -> `Null));
          ("title", json_str e.title)]

