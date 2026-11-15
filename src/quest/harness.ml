(* harness — the bp3 harness door: supervisor, init-check,
   find-tape, watch, desk. This exp (mvp.1) builds the door,
   the verdict/exit contract, the lifecycle fold, and the
   passive supervisor loop. find-tape (mvp.2), watch (mvp.3),
   and desk (mvp.6) refuse typed until their exps land.
   The supervisor never signals a pid and never finalizes
   from a watch outcome: tick phases are tell -> watch ->
   judge (fresh quest read) -> finalize. *)
open Gitx
open Store

(* ---------- lifecycle fold (pure) ---------- *)
type init_record = {
  run_id : string;
  harness : string;
  session_id : string option;
  pid : int option;
  tape_path : string option;
  quest : string option;
  exp : string option;
}

type observation = {
  pid_alive : bool option;
  exit_observed : bool;
  tape_closed : bool;
  settle_row : bool;
  tape_seen : bool;
  fresh : bool;
}

let no_observation = {
  pid_alive = None; exit_observed = false; tape_closed = false;
  settle_row = false; tape_seen = false; fresh = false;
}

(* Lifecycle is derived, never narrated: init / active /
   finished / orphaned. A settle row alone never finishes a
   live child; stale plus alive stays active; blind probes
   add no fifth word (None means no InitRecord, no claim). *)
let derive_lifecycle init obs =
  match init with
  | None -> None
  | Some _ ->
      if (obs.exit_observed && obs.tape_closed)
         || (obs.settle_row && obs.tape_closed) then Some "finished"
      else if not obs.tape_seen && obs.pid_alive = None
              && not obs.exit_observed && not obs.settle_row then Some "init"
      else if not obs.fresh && obs.pid_alive <> Some true then Some "orphaned"
      else Some "active"

(* Exit classes: settled adopts the success class (0),
   watchdog_killed the terminal domain class (1). No
   retryable or needs-human class existed in the binary
   (call failures are 1 domain / 2 usage), so timeout (3)
   and human_gate (4) extend the outcome classes here. *)
let exit_of_outcome = function
  | "settled" -> 0
  | "watchdog_killed" -> 1
  | "timeout" -> 3
  | "human_gate" -> 4
  | _ -> 1

(* ---------- derivation store (read-only in this exp) ---------- *)
let derivations_dir () =
  let out, code = git_out ["rev-parse"; "--git-common-dir"] in
  if code <> 0 || out = "" then None
  else
    let dir = if Filename.is_relative out then Filename.concat root out else out in
    Some (Filename.concat (Filename.concat dir "bp3") "run-lifecycle-derivations")

let pid_alive pid =
  try Unix.kill pid 0; true
  with Unix.Unix_error (Unix.EPERM, _, _) -> true
     | Unix.Unix_error _ -> false

let get_bool j key =
  try match Yojson.Safe.Util.member key j with `Bool b -> b | _ -> false
  with _ -> false

let get_int_opt j key =
  try match Yojson.Safe.Util.member key j with `Int n -> Some n | _ -> None
  with _ -> None

(* Fold one Run's derivation log. Malformed lines (a torn
   final line included) carry no fact and are skipped. *)
let fold_run_file ~silence_seconds path =
  let text = read_file_or path "" in
  let init = ref None in
  let obs = ref no_observation in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        match get_str j "kind" "" with
        | "init_record" ->
            init := Some {
              run_id = get_str j "run_id" "";
              harness = get_str j "harness" "";
              session_id = get_opt j "session_id";
              pid = get_int_opt j "pid";
              tape_path = get_opt j "tape_path";
              quest = get_opt j "quest";
              exp = get_opt j "exp";
            }
        | "observation" ->
            let o = !obs in
            obs := {
              pid_alive = (match Yojson.Safe.Util.member "pid_alive" j with
                | `Bool b -> Some b | _ -> o.pid_alive);
              exit_observed = o.exit_observed || get_bool j "exit_observed";
              tape_closed = o.tape_closed || get_bool j "tape_closed";
              settle_row = o.settle_row || get_bool j "settle_row";
              tape_seen = o.tape_seen || get_bool j "tape_seen";
              fresh = o.fresh;
            }
        | _ -> ()
      with _ -> ());
  (match !init with
   | None -> (!init, !obs, [])
   | Some rec_ ->
       let o = !obs in
       let alive = match rec_.pid with
         | Some p -> Some (pid_alive p) | None -> o.pid_alive in
       let blind = ref false in
       let tape_seen, fresh = match rec_.tape_path with
         | None -> (o.tape_seen, o.fresh)
         | Some tp ->
             (try
                let st = Unix.stat tp in
                (true, Unix.time () -. st.Unix.st_mtime
                        <= float_of_int silence_seconds)
              with _ -> blind := true; (o.tape_seen, o.fresh)) in
       let o = { o with pid_alive = alive; tape_seen; fresh } in
       (!init, o, if !blind then ["W_SUPERVISOR_BLIND"] else []))

type run_view = {
  rv_id : string;
  rv_lifecycle : string option;
  rv_harness : string;
  rv_warnings : string list;
}

let fold_runs ~quest ~silence_seconds =
  match derivations_dir () with
  | None -> ([], [])
  | Some dir ->
      let names = try Array.to_list (Sys.readdir dir) with _ -> [] in
      let views = List.filter_map (fun n ->
        if not (Filename.check_suffix n ".jsonl") then None
        else
          let path = Filename.concat dir n in
          let (init, obs, warns) = fold_run_file ~silence_seconds path in
          match init with
          | None -> None
          | Some rec_ ->
              if rec_.quest <> None && rec_.quest <> Some quest then None
              else Some {
                rv_id = if rec_.run_id <> "" then rec_.run_id
                        else Filename.remove_extension n;
                rv_lifecycle = derive_lifecycle init obs;
                rv_harness = rec_.harness;
                rv_warnings = warns;
              }) names in
      let warns = List.concat_map (fun v -> v.rv_warnings) views in
      (views, warns)

(* ---------- argv ---------- *)
let positive_seconds flag v =
  let n = try int_of_string v with _ -> -1 in
  if n <= 0 || string_of_int n <> v then
    usage (flag ^ " needs a bare positive integer, got: " ^ v)
  else n

type sup_flags = {
  engine : string option;
  timeout_seconds : int;
  silence_seconds : int;
  grace_seconds : int option;
}

let parse_sup_flags args =
  let rec loop acc = function
    | [] -> acc
    | "--engine" :: v :: rest ->
        if acc.engine <> None then usage "duplicate flag --engine";
        if v <> "muse-code" && v <> "pi" then
          usage "--engine must be muse-code or pi";
        loop { acc with engine = Some v } rest
    | "--timeout-seconds" :: v :: rest ->
        loop { acc with timeout_seconds = positive_seconds "--timeout-seconds" v } rest
    | "--silence-seconds" :: v :: rest ->
        loop { acc with silence_seconds = positive_seconds "--silence-seconds" v } rest
    | "--grace-seconds" :: v :: rest ->
        if acc.grace_seconds <> None then usage "duplicate flag --grace-seconds";
        loop { acc with grace_seconds = Some (positive_seconds "--grace-seconds" v) } rest
    | ["--engine"] | ["--timeout-seconds"] | ["--silence-seconds"] | ["--grace-seconds"] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop { engine = None; timeout_seconds = 30; silence_seconds = 600;
         grace_seconds = None } args

let split_positional args =
  let rec go pos flags = function
    | [] -> (List.rev pos, flags)
    | a :: rest when String.length a >= 2 && a.[0] = '-' && a.[1] = '-' ->
        (List.rev pos, a :: rest @ flags)
    | a :: rest -> go (a :: pos) flags rest in
  go [] [] args

(* ---------- verdict helpers ---------- *)
let run_json v =
  `Assoc [
    ("run_id", json_str v.rv_id);
    ("lifecycle", (match v.rv_lifecycle with Some l -> json_str l | None -> `Null));
    ("harness", json_str v.rv_harness);
  ]

let dedup xs =
  List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [x]) [] xs

(* ---------- supervisor ---------- *)
let do_supervisor quest args =
  check_slug quest;
  let (pos, fl) = split_positional args in
  if pos <> [] then usage "stray positional in supervisor";
  let fl = parse_sup_flags fl in
  ignore fl.grace_seconds;
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  (* engine stated here (no single Run); a contradiction with
     any folded InitRecord is a usage error *)
  let (runs0, _) = fold_runs ~quest ~silence_seconds:fl.silence_seconds in
  (match fl.engine with
   | Some e ->
       if List.exists (fun v -> v.rv_harness <> "" && v.rv_harness <> e) runs0 then
         usage "--engine contradicts a Run InitRecord"
   | None -> ());
  let deadline = Unix.time () +. float_of_int fl.timeout_seconds in
  let last_key = ref "" in
  let streamed = ref [] in
  let rec tick () =
    (* tell: derive Runs; watch: passive observation only,
       this loop never signals a pid *)
    let (runs, run_warns) = fold_runs ~quest ~silence_seconds:fl.silence_seconds in
    (* judge: fresh quest read, never a cached view *)
    let (view, inbox, rollup, _qs) = Render.quest_view quest in
    ignore view;
    let key = String.concat ";" (
      List.map (fun v -> v.rv_id ^ "=" ^
        (match v.rv_lifecycle with Some l -> l | None -> "?")) runs)
      ^ "|" ^ rollup ^ "|" ^ string_of_int (List.length inbox) in
    if key <> !last_key then begin
      last_key := key;
      let row = `Assoc [
        ("kind", json_str "lifecycle_change");
        ("quest", json_str quest);
        ("rollup", json_str rollup);
        ("runs", `List (List.map run_json runs));
      ] in
      streamed := row :: !streamed;
      print_endline (Yojson.Safe.to_string row);
      flush stdout
    end;
    let finish outcome =
      let orphans = List.filter_map (fun v ->
        if v.rv_lifecycle = Some "orphaned" then Some (json_str v.rv_id)
        else None) runs in
      let warnings = dedup run_warns in
      let fields = [
        ("ok", `Bool true); ("quest", json_str quest);
        ("outcome", json_str outcome);
        ("settled", `Bool (outcome = "settled"));
        ("rollup", json_str rollup);
        ("runs", `List (List.map run_json runs));
        ("inbox", `List inbox);
        ("orphans", `List orphans);
      ] in
      let fields = if warnings = [] then fields
        else fields @ [("warnings", `List (List.map json_str warnings))] in
      print_endline (Yojson.Safe.to_string (`Assoc fields));
      exit_of_outcome outcome in
    if rollup = "landed" then finish "settled"
    else if inbox <> [] then finish "human_gate"
    else if Unix.time () >= deadline then finish "timeout"
    else begin
      ignore (Unix.select [] [] [] 1.0);
      tick ()
    end in
  tick ()

(* ---------- init-check ---------- *)
let tape_source = function
  | "muse-code" ->
      (match Sys.getenv_opt "HOME" with
       | Some h -> Filename.concat h ".local/share/muse/sessions"
       | None -> ".local/share/muse/sessions")
  | _ ->
      (match Sys.getenv_opt "HOME" with
       | Some h -> Filename.concat h ".pi/sessions"
       | None -> ".pi/sessions")

let do_init_check args =
  let (pos, fl) = split_positional args in
  if pos <> [] then usage "stray positional in init-check";
  let engines = match fl with
    | [] -> ["muse-code"; "pi"]
    | ["--engine"; e] ->
        if e <> "muse-code" && e <> "pi" then
          usage "--engine must be muse-code or pi";
        [e]
    | ["--engine"] -> usage "flag needs a value"
    | f :: _ -> usage ("unknown flag: " ^ f) in
  let checks = List.map (fun e ->
    let src = tape_source e in
    let present = try Sys.is_directory src with _ -> false in
    (`Assoc [
       ("harness", json_str e); ("tape_source", json_str src);
       ("present", `Bool present);
     ], present)) engines in
  let blind = List.exists (fun (_, p) -> not p) checks in
  let fields = [
    ("ok", `Bool true);
    ("checks", `List (List.map fst checks));
  ] in
  let fields = if blind then
    fields @ [("warnings", `List [json_str "W_SUPERVISOR_BLIND"])] else fields in
  print_endline (Yojson.Safe.to_string (`Assoc fields));
  0

(* ---------- later-exps door ---------- *)
let not_yet verb =
  err "E_UNSUPPORTED" (`Assoc [("verb", json_str verb)])
    ("bp3 harness " ^ verb ^ " is not implemented yet; its exp owns it.") 1

(* ---------- help (docstrings beside dispatch) ---------- *)
let help_harness = "bp3 harness - harness machinery door. Verbs:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]   passive loop: tell -> watch -> judge -> finalize\n\
  bp3 harness init-check [--engine muse-code|pi]   probe tape sources; blindness is W_SUPERVISOR_BLIND, never blocking\n\
  bp3 harness find-tape --run-id <id>              run-id -> tape (owned by a later exp)\n\
  bp3 harness watch --run-id <id>                  blocking watch (owned by a later exp)\n\
  bp3 harness desk <verb> ...                      desks (owned by a later exp)\n\
Aliases: s=supervisor, i=init-check, f=find-tape, w=watch, d=desk. Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_supervisor = "bp3 harness supervisor - passive supervisor loop for one quest:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]\n\
  Streams NDJSON lifecycle_change rows on stdout, ends with one JSON verdict {ok, quest, outcome, settled, rollup, runs, inbox, orphans}.\n\
  Outcomes and exit classes: settled=0, watchdog_killed=1 (terminal), timeout=3 (retryable), human_gate=4 (needs-human).\n\
  Durations are bare positive integers; 0, negatives, and suffixed values are usage errors.\n\
Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_init_check = "bp3 harness init-check - probe tape sources per harness:\n\
  bp3 harness init-check [--engine muse-code|pi]\n\
  Emits {ok, checks}; a missing or reshaped tape source adds W_SUPERVISOR_BLIND to warnings and never blocks work.\n\
Example: bp3 harness init-check --engine muse-code\n"

let is_help = function "-h" | "--help" -> true | _ -> false

let normalize_verb = function
  | "s" | "supervisor" -> "supervisor"
  | "i" | "init-check" -> "init-check"
  | "f" | "find-tape" -> "find-tape"
  | "w" | "watch" -> "watch"
  | "d" | "desk" -> "desk"
  | other -> other

let run = function
  | [] -> usage "harness needs a verb: supervisor, init-check, find-tape, watch, or desk"
  | [h] when is_help h -> print_string help_harness; 0
  | verb :: (h :: _) when is_help h ->
      print_string (match normalize_verb verb with
        | "supervisor" -> help_supervisor
        | "init-check" -> help_init_check
        | _ -> help_harness); 0
  | verb_raw :: rest ->
      (match normalize_verb verb_raw with
       | "supervisor" ->
           (match rest with
            | quest :: tail -> do_supervisor quest tail
            | [] -> usage "supervisor needs a quest")
       | "init-check" -> do_init_check rest
       | "find-tape" -> not_yet "find-tape"
       | "watch" -> not_yet "watch"
       | "desk" -> not_yet "desk"
       | other -> usage ("unknown harness verb: " ^ other))
