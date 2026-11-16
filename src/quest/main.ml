(* bp3 q — quest/exp FSM CLI. Only writer of quest state.
   Doors and the FSM judge live here; plumbing in Gitx,
   truth in Store, presentation in Render. *)
open Gitx
open Store
open Render

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

(* ---------- config door (config.1) ---------- *)
let parse_config_flags args =
  let rec loop source fmt fmt_set = function
    | [] -> (source, fmt)
    | "--source" :: rest ->
        if source then usage "duplicate flag --source";
        loop true fmt fmt_set rest
    | "--format" :: v :: rest ->
        if fmt_set then usage "duplicate flag --format";
        if v <> "json" && v <> "table" then usage "--format must be json or table";
        loop source v true rest
    | ["--format"] -> usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop false "json" false args

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
  check_creatable quest;
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
  check_slug quest; check_creatable exp;
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
  if not (List.mem edge ["handoff"; "grade"; "verify"; "land"; "block"; "resume"]) then
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
  | "handoff" ->
      if s.st <> "todo" then illegal s.st edge;
      let raw = (match fl.commit with Some c -> c | None -> usage "--commit is required for handoff") in
      let full = (match resolve_commit raw with Some f -> f
        | None -> err "E_COMMIT_MISMATCH" (`Assoc [("commit", json_str raw)])
            "Commit does not exist; bind an existing commit." 1) in
      if worktree_dirty () then
        err "E_DIRTY_TREE" (`Assoc []) "Worktree is dirty; clean it and retry." 1;
      let blocked_by = List.filter (fun d -> not (dep_satisfied d)) deps in
      if blocked_by <> [] then
        err "E_DEPENDENCY" (`Assoc [("blocked_by", `List (List.map json_str blocked_by))])
          "Dependencies are not landed yet." 1;
      let approved_now = (not knobs.grade_required) && (not knobs.verify_required) in
      let ns = { s with st = (if approved_now then "approved" else "handed_off");
                 bound = Some full; has_bound = true; last_commit = Some full;
                 grade_ok = false; verify_ok = false } in
      let line = ledger_line ~edge ~from:s.st ~to_:ns.st ~cycle:s.cycle
        ~commit:(Some full) ~verdict:None ~reason ~id () in
      finish ns line
  | "grade" | "verify" ->
      if s.st <> "handed_off" then illegal s.st edge;
      let v = (match fl.verdict with Some v -> v | None -> usage "--verdict is required") in
      let valid = if edge = "grade" then (v = "ship" || v = "needs_fix") else (v = "pass" || v = "fail") in
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
        let ns = { s with st = nst; cycle = ncyc; grade_ok = false; verify_ok = false } in
        if nst = "blocked" then begin ns.blocked_reason <- reason; ns.blocked_since <- now_ts () end;
        let line = ledger_line ~edge ~from:s.st ~to_:nst ~cycle:ncyc
          ~commit:s.last_commit ~verdict:(Some v) ~reason ~id () in
        let base = finish ns line in
        if nst = "blocked" then
          (match base with `Assoc fs -> `Assoc (fs @ [("human_action_required", `Bool true)]) | o -> o)
        else base
      end else begin
        let ns = { s with grade_ok = (if edge = "grade" then true else s.grade_ok);
                          verify_ok = (if edge = "verify" then true else s.verify_ok) } in
        let now_approved =
          ((not knobs.grade_required) || ns.grade_ok) &&
          ((not knobs.verify_required) || ns.verify_ok) in
        let nst = if now_approved then "approved" else "handed_off" in
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
          ("exp", json_str exp); ("state", json_str "landed"); ("fin", json_str "exp_fin"); ("cycle", `Int s.cycle);
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
            ("exp", json_str exp); ("state", json_str "landed"); ("fin", json_str "exp_fin"); ("cycle", `Int s.cycle);
            ("commit", (match s.last_commit with Some c -> json_str c | None -> `Null));
            ("legal_edges", `List [])]
        end
      end
  | "block" ->
      if not (List.mem s.st ["todo"; "handed_off"; "approved"]) then illegal s.st edge;
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
                 grade_ok = false; verify_ok = false } in
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

(* icebox door: bp3 q icebox r [term...] | r <slug> (read-only) *)
let do_icebox = function
  | verb_raw :: rest when is_verb verb_raw ->
      if normalize_verb verb_raw <> "r" then usage "icebox door is read-only: only r";
      let (terms, fl) = split_flags rest in
      let entries = list_icebox_entries () in
      let print_list () =
        let hits = List.filter (fun e -> icebox_matches e terms) entries in
        print_verdict ~fmt:fl.fmt (`Assoc [("ok", `Bool true);
          ("entries", `List (List.map icebox_entry_json hits))]); 0 in
      (match terms with
       | [slug] ->
           (match List.find_opt (fun e -> e.slug = slug) entries with
            | Some e -> print_string e.text; 0
            | None -> print_list ())
       | _ -> print_list ())
  | _ -> usage "icebox door verbs are r"

(* ---------- help (docstrings beside dispatch; Exp 4) ---------- *)
let help_q = "bp3 q - quest/exp state. Doors:\n\
  bp3 q c|r|d ...              quest door (create, read, delete)\n\
  bp3 q <quest> c|r|u|d ...    exp door for one quest\n\
  bp3 q icebox r [term...]     search frozen icebox entries (read-only)\n\
  bp3 harness desk <verb> ...  desks (machine-local); bp3 worktree is its documented alias\n\
  bp3 config [--source]        view the machine-local config store (<git-common-dir>/bp3/)\n\
  bp3 q hooks                  harness hook emitter (fail-open)\n\
Run bp3 q <door> -h for that door's verbs, edges, and flags.\n"

let help_quest_door = "bp3 q <quest door> - verbs:\n\
  bp3 q c <quest> [--type <quest_type>] [--depends-on <a,b>]   create a quest\n\
  bp3 q r [<quest>] [--format json|table|tree]                 list quests, or read one\n\
  bp3 q d <quest> --reason <why>                               delete a quest\n\
Long forms: create, read, delete. Example: bp3 q c my-quest --type default\n"

let help_exp_door = "bp3 q <quest> <exp door> - verbs:\n\
  bp3 q <quest> c <exp> [--type <exp_type>]                    create an exp\n\
  bp3 q <quest> r [<exp>] [--format json|table|tree]           read the quest, or one exp\n\
  bp3 q <quest> u <exp> <edge> [flags]                         take an FSM edge (see u -h)\n\
  bp3 q <quest> d <exp> --reason <why>                         delete an exp\n\
Long forms: create, read, update, delete. Example: bp3 q my-quest r exp-1\n"

let help_update = "bp3 q <quest> u <exp> <edge> - edges and their flags:\n\
  edges: handoff grade verify land block resume\n\
  handoff --commit <sha> --reason <why>    bind a clean commit for grade\n\
  grade  --verdict ship|needs_fix --reason <why>\n\
  verify --verdict pass|fail --reason <why>\n\
  land   --reason <why>                    land an approved exp\n\
  block  --reason <why>                    park for a human decision\n\
  resume --reason <why>                    human only: unblock\n\
Shared flags: --format json|table|tree, --target <name>.\n\
Example: bp3 q my-quest u exp-1 handoff --commit abc123 --reason \"ready\"\n"

let help_icebox = "bp3 q icebox r - search frozen icebox entries (read-only):\n\
  bp3 q icebox r [term...] [--format json|table|tree]   list entries matching all terms\n\
  bp3 q icebox r <slug>                                 print one entry in full\n\
Example: bp3 q icebox r table completion\n"

let help_worktree = "bp3 worktree - documented alias of bp3 harness desk, machine-local desks, never ledgered:\n\
  verbs: derive, create, inspect, remove, prepare, check, exit, release, list\n\
  bp3 harness desk prepare <quest> <exp> --run <run-id> [--commit <sha>] [--path <dir>]\n\
  bp3 harness desk list [--quest <quest>]\n\
Example: bp3 harness desk prepare my-quest exp-1 --run R1\n"

let help_config = "bp3 config - view the machine-local bp3 config store (<git-common-dir>/bp3/, never committed):\n\
  bp3 config [--source] [--format json|table]   thresholds plus contexts folded from runs/<run_id>.json\n\
  config.json holds machine settings only (thresholds: setup_slow_s, depth_cap); contexts are views, never stored there. The depth cap is enforced at link mint (mvp.1, E_DEPTH); W_SETUP_SLOW enforcement lands with mvp.3. First call on a fresh repo creates the store with defaults (zero setup), and every view rebuilds the derived by-session index from runs/, so deleting by-session/ loses nothing. --source names the writing verb and timestamp per context. Outside a git repo there is no store and the call refuses E_NOT_FOUND.\n\
Example: bp3 config --source\n"

let is_help = function "-h" | "--help" -> true | _ -> false

(* Exp 5 guard: an older-MAJOR binary never writes in a newer repo.
   Newer MINOR/PATCH only warns (warnings_of carries W_VERSION_AHEAD). *)
let guard_write argv =
  let is_write = match argv with
    | v :: _ when is_verb v -> let n = normalize_verb v in n = "c" || n = "d"
    | _q :: v :: _ when is_verb v -> normalize_verb v <> "r"
    | _ -> false in
  if is_write && not (List.exists is_help (List.filteri (fun i _ -> i < 3) argv)) then
    match version_ahead () with
    | Some v when version_major v > version_major bp3_version ->
        err "E_VERSION_AHEAD"
          (`Assoc [("binary", json_str bp3_version); ("repo", json_str v)])
          "Repo was stamped by a newer MAJOR bp3; upgrade bp3 before writing." 1
    | _ -> ()

let run argv =
  let id = identity () in
  guard_write argv;
  match argv with
  | "-h" :: _ | "--help" :: _ -> print_string help_q; 0
  | "--version" :: _ -> print_endline bp3_version; 0
  | "harness" :: rest -> Harness.run rest
  | "config" :: (h :: _) when is_help h -> print_string help_config; 0
  | "config" :: rest ->
      let (source, fmt) = parse_config_flags rest in
      print_verdict ~fmt (Config.view ~source); 0
  | "worktree" :: (h :: _) when is_help h -> print_string help_worktree; 0
  | "icebox" :: (h :: _) when is_help h -> print_string help_icebox; 0
  | "icebox" :: ("r" | "read") :: (h :: _) when is_help h -> print_string help_icebox; 0
  | first :: (h :: _) when is_verb first && is_help h -> print_string help_quest_door; 0
  | _quest :: (h :: _) when is_help h -> print_string help_exp_door; 0
  | _quest :: verb_raw :: (h :: _) when is_verb verb_raw && is_help h ->
      print_string (if normalize_verb verb_raw = "u" then help_update else help_exp_door); 0
  | "worktree" :: rest ->
      (* documented alias of harness desk (mvp.6): same store,
         same verdicts; new callers use bp3 harness desk *)
      print_verdict ~fmt:"json" (Worktree.run rest); 0
  | "init-repo" :: _ ->
      (* Exp 6: scaffold plans/ into the caller's repo; never clobber differing plans *)
      let plans = [("plans/default.yaml", "quest_type: default\nmax_cycles: 1\ngrade:\n  required: true\nverify: required\n");
                   ("plans/direct.yaml", "quest_type: direct\nmax_cycles: 0\ngrade:\n  required: false\nverify: required\n")] in
      (try Unix.mkdir (Filename.concat root "plans") 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      List.iter (fun (rel, content) ->
        let path = Filename.concat root rel in
        if Sys.file_exists path then begin
          let existing = let ic = open_in_bin path in
            let s = really_input_string ic (in_channel_length ic) in close_in ic; s in
          if existing <> content then
            err "E_EXISTS" (`Assoc [("plan", json_str rel)])
              "Plan already exists with different content; refusing to overwrite." 1
        end else begin
          let oc = open_out_bin path in output_string oc content; close_out oc
        end) plans;
      print_verdict ~fmt:"json" (`Assoc [("ok", `Bool true);
        ("plans", `List (List.map (fun (p, _) -> json_str p) plans))]); 0
  | "hooks" :: _ ->
      (* fail-open emitter: Hooks.handle never raises, always exit 0 *)
      print_endline (Yojson.Safe.to_string (Hooks.handle ())); 0
  | "icebox" :: rest -> do_icebox rest
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
    print_endline (Yojson.Safe.to_string (stamp_run_id v));
    exit code


