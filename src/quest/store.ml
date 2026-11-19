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
   quest or node carrying one of these slugs could never be
   addressed again (the token would parse as the door or
   verb instead), so creation refuses it; reads stay total. *)
let reserved_slugs =
  [ "harness"; "worktree"; "icebox"; "hooks"; "init-repo"; "config"; "g"; "n"; "e"; "dep";
    "supervisor"; "init-check"; "find-tape"; "watch"; "desk"; "backtest"; "b"; "diagram";
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
  if m = 0 then true
  else if m > n then false
  else
    let rec at i j = j = m || (s.[i + j] = sub.[j] && at i (j + 1)) in
    let rec loop i = i + m <= n && (at i 0 || loop (i + 1)) in
    loop 0

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

let effective_knobs ~quest_type ~node_type =
  if node_type = "default" || node_type = "" then quest_knobs quest_type
  else load_plan_file ("plans/node-" ^ node_type ^ ".yaml")

(* ---------- ledger fold ---------- *)
type node_state = {
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
  mutable node_type : string;
}

let fresh_state () = {
  st = "todo"; cycle = 1; bound = None; has_bound = false;
  grade_ok = false; verify_ok = false;
  blocked_reason = ""; blocked_checkpoint = None; blocked_since = "";
  last_commit = None; node_type = "default";
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

(* The one compat mapping (mig.1, rename.1): pre-rename ledger
   strings fold to the new words here and nowhere else; new ledger
   lines already carry the new words. Verb/state words arrived in
   mig.1; the quest/node type keys arrived in rename.1. *)
let fold_edge = function
  | "submit" -> "handoff" | "review" -> "grade" | "check" -> "verify"
  | e -> e

let fold_state_name = function "submitted" -> "handed_off" | s -> s

(* Pre-rename type keys, read only here: a frozen ledger's create
   line names its plan with the old key; new lines use the new key. *)
let fold_type_key j new_key old_key default =
  match get_opt j new_key with
  | Some v -> v
  | None -> get_str j old_key default

(* Node-ID rename fold (followup.3 scope C): landed ledger
   text keeps exp- IDs; reads map them to node- IDs here. *)
let starts_with s p =
  let n = String.length p in
  String.length s >= n && String.sub s 0 n = p

let canon_node_id e =
  if starts_with e "exp-" then "node-" ^ String.sub e 4 (String.length e - 4)
  else e

let legacy_node_id e =
  if starts_with e "node-" then "exp-" ^ String.sub e 5 (String.length e - 5)
  else e

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
        if edge = "create" || edge = "dep" then begin
          if edge = "create" then begin
            s.node_type <- fold_type_key j "node_type" "exp_type"
              (fold_type_key j "goal_type" "graph_type"
                 (get_str j "quest_type" "default"));
            quest_type := fold_type_key j "goal_type" "graph_type"
              (get_str j "quest_type" !quest_type)
          end;
          (try match Yojson.Safe.Util.member "depends_on" j with
             | `List xs -> depends_on := List.map (function `String x -> canon_node_id x | _ -> "") xs
             | _ -> () with _ -> ())
        end;
        if to_ <> "" then s.st <- to_;
        s.cycle <- cyc;
        (match get_opt j "commit" with Some c -> s.last_commit <- Some c; s.bound <- Some c; s.has_bound <- true | None -> ());
        if edge = "handoff" then begin s.grade_ok <- false; s.verify_ok <- false end;
        if edge = "grade" && get_str j "verdict" "" = "ship" then s.grade_ok <- true;
        if edge = "verify" && get_str j "verdict" "" = "pass" then s.verify_ok <- true;
        if edge = "grade" && get_str j "verify_verdict" "" = "pass" then s.verify_ok <- true;
        if edge = "grade" && get_str j "verify_verdict" "" = "fail" then begin
          s.grade_ok <- false; s.verify_ok <- false
        end;
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

(* Canonical spellings come from Layout; legacy spellings fold
   here only, never in callers. *)
let first_existing_ref canon legacies =
  match List.find_opt (fun r -> ref_tip r <> None) (canon :: legacies) with
  | Some r -> r
  | None -> canon

let quest_branch q =
  first_existing_ref (Layout.quest_ref_of Layout.quest_ref_kind q)
    (List.map (fun k -> Layout.quest_ref_of k q) Layout.legacy_quest_ref_kinds)

let node_branch q e =
  first_existing_ref (Layout.node_ref_prefix_of Layout.node_ref_kind q ^ canon_node_id e)
    (List.map (fun k -> Layout.node_ref_prefix_of k q ^ legacy_node_id e)
       Layout.legacy_node_ref_kinds)

let quest_dir q = Layout.quest_dir q
let ledger_in dir = dir ^ "/" ^ Layout.ledger_file
let node_dir_under root dir q id = Layout.quest_dir_in root q ^ "/" ^ dir ^ "/" ^ id
let node_dir_in root q id = node_dir_under root Layout.nodes_dir q id
let quest_ledger_path q = ledger_in (quest_dir q)
let node_dir q e = node_dir_in Layout.quests_root q (canon_node_id e)
let node_ledger_path q e = ledger_in (node_dir q e)
let node_state_path q e = node_dir q e ^ "/" ^ Layout.state_file

(* Pre-rename ledger paths on the same branch: every legacy root x
   node folder name x node id spelling; canonical path excluded. *)
let all_roots = Layout.quests_root :: Layout.legacy_quests_roots
let legacy_quest_ledger_paths q =
  List.map (fun r -> ledger_in (Layout.quest_dir_in r q)) all_roots
  |> List.filter (fun p -> p <> quest_ledger_path q)
let legacy_node_ledger_paths q e =
  List.concat_map (fun r ->
      List.concat_map (fun dir ->
          List.map (fun id -> ledger_in (node_dir_under r dir q id))
            [canon_node_id e; legacy_node_id e])
        (Layout.nodes_dir :: Layout.legacy_nodes_dirs)) all_roots
  |> List.filter (fun p -> p <> node_ledger_path q e)

(* Renames never rewrote branch trees, so one tip can hold a ledger
   copy per era; ledgers are append-only, so the copy with the most
   lines is the newest. pick_longest is that rule, pure: among the
   (path, text) copies found, canonical first, most lines wins, a tie
   keeps the earlier copy, and no copy reads as empty at the
   canonical path. Returns (text, path). *)
let pick_longest canon found =
  let lines t = List.length (String.split_on_char '\n' (String.trim t)) in
  match found with
  | [] -> ("", canon)
  | first :: rest ->
      let (p, t) = List.fold_left (fun (bp, bt) (p, t) ->
          if lines t > lines bt then (p, t) else (bp, bt)) first rest in
      (t, p)

(* Read a ledger at its canonical path or any pre-rename path on the
   same branch. The third component names the path read, so appends
   write back to the same path. *)
let ledger_read branch canon legacy =
  match ref_tip branch with
  | None -> None
  | Some tip ->
      let found = List.filter_map (fun p ->
          match git_show tip p with Some t -> Some (p, t) | None -> None)
          (canon :: legacy) in
      let (t, p) = pick_longest canon found in
      Some (tip, t, p)

(* Every bp3 prefix lives under refs/heads/bp3/: list that once
   per cache epoch and filter in memory, instead of one
   for-each-ref per prefix (two per quest in the version scan). *)
let refs_cache : (int * string list) option ref = ref None
let list_refs prefix =
  let all = match !refs_cache with
    | Some (epoch, refs) when epoch = !cache_epoch -> refs
    | _ ->
        let out, code = git_out ["for-each-ref"; "--format=%(refname)"; Layout.ref_root] in
        let refs = if code <> 0 then [] else
          String.split_on_char '\n' out |> List.map String.trim |> List.filter (fun s -> s <> "") in
        refs_cache := Some (!cache_epoch, refs); refs in
  List.filter (fun r -> starts_with r prefix) all

let list_quests () =
  (* Legacy storage prefixes fold here only (Layout). *)
  let strip p r = String.sub r (String.length p) (String.length r - String.length p) in
  let dedup xs = List.fold_right (fun x acc -> if List.mem x acc then acc else x :: acc) xs [] in
  dedup (List.concat_map (fun k ->
      let p = Layout.quest_ref_prefix_of k in list_refs p |> List.map (strip p))
    (Layout.quest_ref_kind :: Layout.legacy_quest_ref_kinds))

let list_nodes q =
  let strip p r = String.sub r (String.length p) (String.length r - String.length p) in
  let dedup xs = List.fold_right (fun x acc -> if List.mem x acc then acc else x :: acc) xs [] in
  let under k = let p = Layout.node_ref_prefix_of k q in list_refs p |> List.map (strip p) in
  let canon = under Layout.node_ref_kind in
  let legacy = List.concat_map under Layout.legacy_node_ref_kinds |> List.map canon_node_id in
  dedup (canon @ legacy)

(* newest bp3_version stamped in any quest/node ledger in this repo *)
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
    let acc = match ledger_read (quest_branch q) (quest_ledger_path q) (legacy_quest_ledger_paths q) with
      | Some (_, t, _) -> from_text acc t | None -> acc in
    List.fold_left (fun acc e ->
      match ledger_read (node_branch q e) (node_ledger_path q e) (legacy_node_ledger_paths q e) with
      | Some (_, t, _) -> from_text acc t | None -> acc) acc (list_nodes q))
    None (list_quests ())

(* One scan per process (each bp3 q call is one command). This process
   only stamps bp3_version, so its own writes cannot change the answer. *)
let version_ahead =
  let ahead = lazy (match newest_bp3_version () with
    | Some v when version_cmp (parse_version v) (parse_version bp3_version) > 0 -> Some v
    | _ -> None) in
  fun () -> Lazy.force ahead

let warnings_of id is_write =
  (if is_write && id.incomplete then ["W_IDENTITY_UNKNOWN"] else [])
  @ (match version_ahead () with Some _ -> ["W_VERSION_AHEAD"] | None -> [])

let fold_node q e =
  match ledger_read (node_branch q e) (node_ledger_path q e) (legacy_node_ledger_paths q e) with
  | None -> None
  | Some (tip, text, _) -> let (s, _, _) = fold_ledger text in Some (tip, s, text)

let fold_quest q =
  match ledger_read (quest_branch q) (quest_ledger_path q) (legacy_quest_ledger_paths q) with
  | None -> None
  | Some (tip, text, _) -> let (s, qt, deps) = fold_ledger text in Some (tip, s, qt, deps, text)

let legal_edges st =
  match st with
  | "todo" -> ["handoff"; "block"; "delete"]
  | "handed_off" -> ["grade"; "verify"; "block"; "delete"]
  | "approved" -> ["land"; "block"; "delete"]
  | "blocked" -> ["resume"; "delete"]
  | _ -> []

let state_yaml q e s =
  Printf.sprintf "quest: %s\nnode: %s\nstate: %s\ncycle: %d\ncommit: %s\n"
    q (canon_node_id e) s.st s.cycle (match s.last_commit with Some c -> c | None -> "none")

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

let append_node_line q e line new_state =
  let branch = node_branch q e in
  match ledger_read branch (node_ledger_path q e) (legacy_node_ledger_paths q e) with
  | None -> not_found "node" e
  | Some (tip, text, lpath) ->
      let new_text = (if String.trim text = "" then "" else
        (if text.[String.length text - 1] = '\n' then text else text ^ "\n")) ^ line ^ "\n" in
      commit_files ~branch ~base_tip:tip ~expect_tip:tip
        ~files:[(lpath, new_text); (node_state_path q e, state_yaml q e new_state)]
        ~msg:("bp3: " ^ canon_node_id e)

let make_checkpoint () =
  let idx = tmp_path "ckpt-index" in
  let env = ["GIT_INDEX_FILE=" ^ idx] in
  let head = head_sha () in
  ignore (run_status ~env (git ["read-tree"; head]));
  ignore (run_status ~env (git ["add"; "-A"]));
  let tree, _ = git_out ~env ["write-tree"] in
  let ckpt, _ = git_out ~input:"bp3 checkpoint" ["commit-tree"; tree; "-p"; head] in
  (try Unix.unlink idx with _ -> ());
  ckpt

let dep_satisfied dep =
  match fold_quest dep with
  | None -> false
  | Some (_, qs, _, _, _) ->
      if qs.st = "deleted" then false
      else
        let nodes = list_nodes dep in
        nodes <> [] && List.for_all (fun e ->
          match fold_node dep e with Some (_, s, _) -> s.st = "landed" || s.st = "deleted" | None -> false) nodes

(* ---------- schedule and timing (mvp.3) ---------- *)
(* Node deps live in node ledger records (create and dep
   lines); ready-set waves, the ready set, starved sets,
   and per-node timing are derived on read from ledger
   timestamps and never written to any committed file. *)
let days_from_civil y m d =
  let y = if m <= 2 then y - 1 else y in
  let era = (if y >= 0 then y else y - 399) / 400 in
  let yoe = y - era * 400 in
  let mp = if m > 2 then m - 3 else m + 9 in
  let doy = (153 * mp + 2) / 5 + d - 1 in
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy in
  era * 146097 + doe - 719468

let ts_epoch s =
  try
    if String.length s <> 20 || s.[4] <> '-' || s.[7] <> '-' || s.[10] <> 'T'
       || s.[13] <> ':' || s.[16] <> ':' || s.[19] <> 'Z' then None
    else
      let num a b = int_of_string (String.sub s a b) in
      let days = days_from_civil (num 0 4) (num 5 2) (num 8 2) in
      Some (days * 86400 + (num 11 2) * 3600 + (num 14 2) * 60 + (num 17 2))
  with _ -> None

let deps_of_text text = let (_, _, deps) = fold_ledger text in deps

type timing = { t_wall : int option; t_wait : int option;
                t_dwell : (string * int) list }

let timing_of_text text =
  let created = ref None and first_handoff = ref None and landed = ref None in
  let dwell : (string, int) Hashtbl.t = Hashtbl.create 8 in
  let order = ref [] in
  let cur = ref "" and since = ref None in
  let add_dwell st secs =
    if not (Hashtbl.mem dwell st) then order := !order @ [st];
    Hashtbl.replace dwell st ((try Hashtbl.find dwell st with _ -> 0) + secs) in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        let edge = fold_edge (get_str j "edge" "") in
        let to_ = fold_state_name (get_str j "to" "") in
        (match ts_epoch (get_str j "ts" "") with
         | None -> ()
         | Some t ->
             if edge = "create" && !created = None then created := Some t;
             if edge = "handoff" && !first_handoff = None then first_handoff := Some t;
             if to_ = "landed" && !landed = None then landed := Some t;
             if to_ <> "" then begin
               (match !since with
                | Some t0 when !cur <> "" -> add_dwell !cur (t - t0)
                | _ -> ());
               cur := to_; since := Some t
             end)
      with _ -> ());
  let sub a b = match a, b with Some x, Some y -> Some (x - y) | _ -> None in
  { t_wall = sub !landed !first_handoff; t_wait = sub !first_handoff !created;
    t_dwell = List.sort compare
      (List.map (fun st -> (st, Hashtbl.find dwell st)) !order) }

let dep_cycle_through quest start =
  let deps_of n = match List.assoc_opt n quest with Some ds -> ds | None -> [] in
  let rec visit path n =
    if n = start && path <> [] then Some (List.rev (n :: path))
    else if List.mem n path then None
    else List.fold_left (fun acc d ->
      match acc with Some _ -> acc | None -> visit (n :: path) d) None (deps_of n) in
  (match visit [] start with
   | Some (_ :: _ :: _ as cyc) -> Some cyc
   | _ -> None)

type sched_node = { n_id : string; n_state : string; n_deps : string list }

let sched_waves nodes =
  let done0 = List.filter_map (fun n ->
    if n.n_state = "landed" || n.n_state = "deleted" then Some n.n_id else None) nodes in
  let todo = List.filter (fun n -> n.n_state = "todo") nodes in
  let rec loop finished acc =
    let layer = List.filter (fun n ->
      not (List.mem n.n_id finished)
      && List.for_all (fun d -> List.mem d finished) n.n_deps) todo in
    match layer with
    | [] -> List.rev acc
    | _ -> loop (finished @ List.map (fun n -> n.n_id) layer)
             ((List.sort String.compare (List.map (fun n -> n.n_id) layer)) :: acc) in
  loop done0 []

let sched_starved nodes =
  let dependents d =
    List.filter_map (fun n -> if List.mem d n.n_deps then Some n.n_id else None) nodes in
  List.filter_map (fun b ->
    if b.n_state <> "blocked" then None
    else
      let seen = ref [b.n_id] and frontier = ref [b.n_id] in
      while !frontier <> [] do
        let next = List.concat_map dependents !frontier in
        frontier := List.filter (fun x -> not (List.mem x !seen)) next;
        seen := !seen @ !frontier
      done;
      let starved = List.sort String.compare
        (List.filter (fun id ->
           id <> b.n_id
           && (match List.find_opt (fun n -> n.n_id = id) nodes with
               | Some n -> n.n_state = "todo" | None -> false)) !seen) in
      if starved = [] then None else Some (b.n_id, starved)) nodes

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
  let dir = Filename.concat root Layout.icebox_dir in
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

