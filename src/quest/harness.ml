(* harness — the bp3 harness door: supervisor, init-check,
   find-tape, watch, desk. mvp.1 built the door, the
   verdict/exit contract, the lifecycle fold, and the
   passive supervisor loop; find-tape landed in mvp.2,
   watch in mvp.3, and desk in mvp.6 (a thin delegation to
   the Worktree store; the retired top-level worktree door
   remains as its documented alias).
   Watch is the sole TERM/KILL owner.
   The supervisor never signals a pid and never finalizes
   from a watch outcome: tick phases are tell -> watch ->
   judge (fresh quest read) -> finalize.
   Since mvp.4 the supervisor is bp3's lifecycle mechanism
   for muse-code: it is the sole writer of the per-Run
   derivation logs under run-lifecycle-derivations (one
   .jsonl per Run, keyed by run-id; session-id is only a
   field on the InitRecord) plus a disposable .json cache
   per Run. Since mvp.5 it is also the sole reader: the
   session-keyed shared maps and legacy per-Run event
   files are no longer imported on any path. *)
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

(* Mechanical tape signals only: a close marker, or an
   assistant stop reason, closes a tape; a settle row is a
   fact of its own and never a close by itself. *)
let tape_signals text =
  let closed =
    contains_sub text "session_closed"
    || (contains_sub text "stopReason" && contains_sub text "\"stop\"")
    || (contains_sub text "stop_reason" && contains_sub text "\"stop\"") in
  let settle = contains_sub text "run_settled" in
  (closed, settle)

(* ---------- derivation store (mvp.4: supervisor-written) ---------- *)
let git_common_dir () =
  let out, code = git_out ["rev-parse"; "--git-common-dir"] in
  if code <> 0 || out = "" then None
  else Some (if Filename.is_relative out then Filename.concat root out else out)

let derivations_dir () =
  match git_common_dir () with
  | None -> None
  | Some dir ->
      Some (Filename.concat (Filename.concat dir "bp3") "run-lifecycle-derivations")

let ensure_dir dir =
  let parent = Filename.dirname dir in
  (try Unix.mkdir parent 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> () | _ -> ());
  (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> () | _ -> ())

let pid_alive pid =
  let exists =
    try Unix.kill pid 0; true
    with Unix.Unix_error (Unix.EPERM, _, _) -> true
       | Unix.Unix_error _ -> false in
  if not exists then false
  else
    (* a zombie is an exited child its parent has not reaped:
       kill 0 still sees it, the process state does not *)
    let (out, code) = run_capture ["ps"; "-o"; "stat="; "-p"; string_of_int pid] in
    if code <> 0 || out = "" then exists
    else out.[0] <> 'Z'

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

type run_fold = {
  rf_view : run_view;
  rf_rec : init_record;
  rf_obs : observation option;
  rf_jsonl : string;
}

(* ---------- derived-state cache (disposable) ---------- *)
(* The .json beside each .jsonl is a cache, never truth:
   it is used only while its input fingerprints (derivation
   log size/mtime, tape size/mtime, live pid probe, freshness
   under the caller's silence budget) still match. Deleting
   it changes nothing except speed. *)
let stat_fp path =
  try let st = Unix.stat path in Some (st.Unix.st_size, int_of_float st.Unix.st_mtime)
  with _ -> None

let cache_path dir run_id = Filename.concat dir (run_id ^ ".json")

let write_cache dir (rec_ : init_record) run_id lifecycle warns obs silence_seconds =
  try
    ensure_dir dir;
    let (jsz, jmt) = match stat_fp (Filename.concat dir (run_id ^ ".jsonl")) with
      | Some v -> v | None -> (0, 0) in
    let (tsz, tmt) = match rec_.tape_path with
      | Some tp -> (match stat_fp tp with Some v -> v | None -> (-1, -1))
      | None -> (-1, -1) in
    let j = `Assoc [
      ("kind", json_str "derived_state");
      ("run_id", json_str run_id);
      ("harness", json_str rec_.harness);
      ("session_id", (match rec_.session_id with Some s -> json_str s | None -> `Null));
      ("pid", (match rec_.pid with Some p -> `Int p | None -> `Null));
      ("tape_path", (match rec_.tape_path with Some s -> json_str s | None -> `Null));
      ("quest", (match rec_.quest with Some s -> json_str s | None -> `Null));
      ("exp", (match rec_.exp with Some s -> json_str s | None -> `Null));
      ("lifecycle", (match lifecycle with Some l -> json_str l | None -> `Null));
      ("warnings", `List (List.map json_str warns));
      ("pid_alive", (match obs.pid_alive with Some b -> `Bool b | None -> `Null));
      ("fresh", `Bool obs.fresh);
      ("silence_seconds", `Int silence_seconds);
      ("jsonl_size", `Int jsz); ("jsonl_mtime", `Int jmt);
      ("tape_size", `Int tsz); ("tape_mtime", `Int tmt);
    ] in
    let path = cache_path dir run_id in
    let tmp = path ^ ".tmp" ^ string_of_int (Unix.getpid ()) in
    let oc = open_out_bin tmp in
    output_string oc (Yojson.Safe.to_string j);
    close_out oc;
    Sys.rename tmp path
  with _ -> ()

let read_cache dir run_id silence_seconds =
  try
    let j = Yojson.Safe.from_string (read_file_or (cache_path dir run_id) "") in
    if get_str j "kind" "" <> "derived_state" then None
    else if get_str j "run_id" "" <> run_id then None
    else if get_int j "silence_seconds" (-1) <> silence_seconds then None
    else
      let (jsz, jmt) = match stat_fp (Filename.concat dir (run_id ^ ".jsonl")) with
        | Some v -> v | None -> (0, 0) in
      if get_int j "jsonl_size" (-2) <> jsz || get_int j "jsonl_mtime" (-2) <> jmt then None
      else
        let tape_path = get_opt j "tape_path" in
        let (tsz, tmt) = match tape_path with
          | Some tp -> (match stat_fp tp with Some v -> v | None -> (-1, -1))
          | None -> (-1, -1) in
        if get_int j "tape_size" (-2) <> tsz || get_int j "tape_mtime" (-2) <> tmt then None
        else
          let pid = get_int_opt j "pid" in
          let alive = match pid with Some p -> Some (pid_alive p) | None -> None in
          let cached_alive = try match Yojson.Safe.Util.member "pid_alive" j with
            | `Bool b -> Some b | _ -> None with _ -> None in
          if alive <> cached_alive then None
          else
            let fresh = match tape_path with
              | Some _ when tsz >= 0 ->
                  Unix.time () -. float_of_int tmt <= float_of_int silence_seconds
              | _ -> false in
            if fresh <> get_bool j "fresh" then None
            else
              let rec_ : init_record = {
                run_id; harness = get_str j "harness" "";
                session_id = get_opt j "session_id"; pid;
                tape_path; quest = get_opt j "quest"; exp = get_opt j "exp";
              } in
              let lifecycle = get_opt j "lifecycle" in
              let warns = try match Yojson.Safe.Util.member "warnings" j with
                | `List xs -> List.filter_map (function `String s -> Some s | _ -> None) xs
                | _ -> [] with _ -> [] in
              Some (rec_, lifecycle, warns)
  with _ -> None

let fold_all ~quest ~silence_seconds =
  match derivations_dir () with
  | None -> []
  | Some dir ->
      let names = try Array.to_list (Sys.readdir dir) with _ -> [] in
      List.filter_map (fun n ->
        if not (Filename.check_suffix n ".jsonl") then None
        else
          let path = Filename.concat dir n in
          let file_id = Filename.remove_extension n in
          match read_cache dir file_id silence_seconds with
          | Some (rec_, lifecycle, warns) ->
              if rec_.quest <> None && rec_.quest <> Some quest then None
              else Some {
                rf_view = { rv_id = file_id; rv_lifecycle = lifecycle;
                            rv_harness = rec_.harness; rv_warnings = warns };
                rf_rec = rec_; rf_obs = None; rf_jsonl = path;
              }
          | None ->
              let (init, obs, warns) = fold_run_file ~silence_seconds path in
              (match init with
               | None -> None
               | Some rec_ ->
                   if rec_.quest <> None && rec_.quest <> Some quest then None
                   else
                     let run_id = if rec_.run_id <> "" then rec_.run_id else file_id in
                     let lifecycle = derive_lifecycle init obs in
                     write_cache dir rec_ run_id lifecycle warns obs silence_seconds;
                     Some {
                       rf_view = { rv_id = run_id; rv_lifecycle = lifecycle;
                                   rv_harness = rec_.harness; rv_warnings = warns };
                       rf_rec = { rec_ with run_id }; rf_obs = Some obs; rf_jsonl = path;
                     })) names

(* ---------- per-Run writer (supervisor-owned) ---------- *)
let last_observed_lifecycle path =
  let text = read_file_or path "" in
  let last = ref None in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        if get_str j "kind" "" = "observation" then
          (match get_opt j "lifecycle" with Some _ as v -> last := v | None -> ())
      with _ -> ());
  !last

(* One mechanical probe of a Run: live pid, tape stat, and
   tape signals folded onto the prior observation. Rows carry
   pointers only (tape path, pid probe), never tape content. *)
let probe_observation ~silence_seconds (rec_ : init_record) prior =
  let alive = match rec_.pid with Some p -> Some (pid_alive p) | None -> prior.pid_alive in
  let exit_obs = prior.exit_observed
    || (match rec_.pid with Some p -> not (pid_alive p) | None -> false) in
  let (closed, settle) = match rec_.tape_path with
    | Some tp -> tape_signals (read_file_or tp "") | None -> (false, false) in
  let tape_seen = prior.tape_seen
    || (match rec_.tape_path with Some tp -> Sys.file_exists tp | None -> false) in
  let fresh = match rec_.tape_path with
    | Some tp -> (match stat_fp tp with
        | Some (_, mt) -> Unix.time () -. float_of_int mt <= float_of_int silence_seconds
        | None -> prior.fresh)
    | None -> prior.fresh in
  let blind = match rec_.tape_path with
    | Some tp -> not (Sys.file_exists tp) | None -> false in
  let obs = { pid_alive = alive; exit_observed = exit_obs;
              tape_closed = prior.tape_closed || closed;
              settle_row = prior.settle_row || settle;
              tape_seen; fresh } in
  (obs, if blind then ["W_SUPERVISOR_BLIND"] else [])

(* Append one observation row to the Run's own derivation
   log, only when its derived lifecycle changed. Parallel
   Runs write separate files; no shared file is touched. *)
let append_observation dir (rf : run_fold) ~silence_seconds =
  let run_id = rf.rf_view.rv_id in
  if run_id = "" || contains_sub run_id "/" || contains_sub run_id ".." then ()
  else
    try
      ensure_dir dir;
      let prior = match rf.rf_obs with
        | Some o -> o
        | None -> let (_, o, _) = fold_run_file ~silence_seconds rf.rf_jsonl in o in
      let (obs, blind_warns) = probe_observation ~silence_seconds rf.rf_rec prior in
      let lifecycle = derive_lifecycle (Some rf.rf_rec) obs in
      let lifecycle_s = match lifecycle with Some l -> l | None -> "" in
      if last_observed_lifecycle rf.rf_jsonl = Some lifecycle_s then ()
      else
        let warns = List.fold_left
          (fun acc x -> if List.mem x acc then acc else acc @ [x]) []
          (rf.rf_view.rv_warnings @ blind_warns) in
        let row = `Assoc [
          ("kind", json_str "observation");
          ("ts", json_str (now_ts ()));
          ("run_id", json_str run_id);
          ("lifecycle", json_str lifecycle_s);
          ("pid_alive", (match obs.pid_alive with Some b -> `Bool b | None -> `Null));
          ("exit_observed", `Bool obs.exit_observed);
          ("tape_closed", `Bool obs.tape_closed);
          ("settle_row", `Bool obs.settle_row);
          ("tape_seen", `Bool obs.tape_seen);
          ("tape_path", (match rf.rf_rec.tape_path with Some s -> json_str s | None -> `Null));
          ("pid", (match rf.rf_rec.pid with Some p -> `Int p | None -> `Null));
          ("warnings", `List (List.map json_str warns));
        ] in
        let oc = open_out_gen [Open_append; Open_creat] 0o644 rf.rf_jsonl in
        output_string oc (Yojson.Safe.to_string row ^ "\n");
        close_out oc
    with _ -> ()

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
  let folds0 = fold_all ~quest ~silence_seconds:fl.silence_seconds in
  let runs0 = List.map (fun f -> f.rf_view) folds0 in
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
    let folds = fold_all ~quest ~silence_seconds:fl.silence_seconds in
    let runs = List.map (fun f -> f.rf_view) folds in
    let run_warns = List.concat_map (fun v -> v.rv_warnings) runs in
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
      flush stdout;
      (* mechanism: persist this tick's probe as one
         observation row per derived Run *)
      (match derivations_dir () with
       | Some dir ->
           List.iter (fun f -> append_observation dir f
             ~silence_seconds:fl.silence_seconds) folds
       | None -> ())
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

(* ---------- find-tape (mvp.2) ---------- *)
(* SHA-256 over the exact entry line: pointer digests are
   verified from the tape bytes themselves, never trusted. *)
let sha256_hex s =
  let k = [|
    0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l; 0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
    0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l; 0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
    0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl; 0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
    0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l; 0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
    0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l; 0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
    0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l; 0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
    0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l; 0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
    0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l; 0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l |] in
  let h = [| 0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
             0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l |] in
  let rotr x n = Int32.logor (Int32.shift_right_logical x n) (Int32.shift_left x (32 - n)) in
  let len = String.length s in
  let bitlen = Int64.mul (Int64.of_int len) 8L in
  let pad_zeros = (56 - (len + 1) mod 64 + 64) mod 64 in
  let total = len + 1 + pad_zeros + 8 in
  let buf = Bytes.make total '\x00' in
  Bytes.blit_string s 0 buf 0 len;
  Bytes.set buf len '\x80';
  for i = 0 to 7 do
    Bytes.set buf (total - 1 - i)
      (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical bitlen (8 * i)) 0xffL)))
  done;
  let w = Array.make 64 0l in
  for chunk = 0 to total / 64 - 1 do
    let base = chunk * 64 in
    for i = 0 to 15 do
      let o = base + i * 4 in
      w.(i) <- Int32.logor (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf o))) 24)
        (Int32.logor (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf (o + 1)))) 16)
        (Int32.logor (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf (o + 2)))) 8)
           (Int32.of_int (Char.code (Bytes.get buf (o + 3))))))
    done;
    for i = 16 to 63 do
      let s0 = Int32.logxor (rotr w.(i - 15) 7) (Int32.logxor (rotr w.(i - 15) 18) (Int32.shift_right_logical w.(i - 15) 3)) in
      let s1 = Int32.logxor (rotr w.(i - 2) 17) (Int32.logxor (rotr w.(i - 2) 19) (Int32.shift_right_logical w.(i - 2) 10)) in
      w.(i) <- Int32.add w.(i - 16) (Int32.add s0 (Int32.add w.(i - 7) s1))
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2) and d = ref h.(3) in
    let e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and hh = ref h.(7) in
    for i = 0 to 63 do
      let s1 = Int32.logxor (rotr !e 6) (Int32.logxor (rotr !e 11) (rotr !e 25)) in
      let ch = Int32.logxor (Int32.logand !e !f) (Int32.logand (Int32.lognot !e) !g) in
      let t1 = Int32.add !hh (Int32.add s1 (Int32.add ch (Int32.add k.(i) w.(i)))) in
      let s0 = Int32.logxor (rotr !a 2) (Int32.logxor (rotr !a 13) (rotr !a 22)) in
      let maj = Int32.logxor (Int32.logand !a !b) (Int32.logxor (Int32.logand !a !c) (Int32.logand !b !c)) in
      let t2 = Int32.add s0 maj in
      hh := !g; g := !f; f := !e; e := Int32.add !d t1;
      d := !c; c := !b; b := !a; a := Int32.add t1 t2
    done;
    h.(0) <- Int32.add h.(0) !a; h.(1) <- Int32.add h.(1) !b;
    h.(2) <- Int32.add h.(2) !c; h.(3) <- Int32.add h.(3) !d;
    h.(4) <- Int32.add h.(4) !e; h.(5) <- Int32.add h.(5) !f;
    h.(6) <- Int32.add h.(6) !g; h.(7) <- Int32.add h.(7) !hh
  done;
  let hex = Buffer.create 64 in
  Array.iter (fun x ->
    for i = 7 downto 0 do
      let nib = Int32.to_int (Int32.logand (Int32.shift_right_logical x (i * 4)) 0xfl) in
      Buffer.add_char hex ("0123456789abcdef".[nib])
    done) h;
  Buffer.contents hex

let all_init_records () =
  match derivations_dir () with
  | None -> []
  | Some dir ->
      let names = try Array.to_list (Sys.readdir dir) with _ -> [] in
      List.sort String.compare names |> List.concat_map (fun n ->
        if not (Filename.check_suffix n ".jsonl") then []
        else
          let text = read_file_or (Filename.concat dir n) "" in
          let found = ref [] in
          String.split_on_char '\n' text |> List.iter (fun ln ->
            let ln = String.trim ln in
            if ln <> "" then
              try
                let j = Yojson.Safe.from_string ln in
                if get_str j "kind" "" = "init_record" then
                  found := {
                    run_id = (let r = get_str j "run_id" "" in
                              if r <> "" then r else Filename.remove_extension n);
                    harness = get_str j "harness" "";
                    session_id = get_opt j "session_id";
                    pid = get_int_opt j "pid";
                    tape_path = get_opt j "tape_path";
                    quest = get_opt j "quest";
                    exp = get_opt j "exp";
                  } :: !found
              with _ -> ());
          List.rev !found)

let tape_roots = function
  | "pi" ->
      (match Sys.getenv_opt "BP3_PI_TAPE_DIR" with
       | Some d when d <> "" -> [d]
       | _ -> (match Sys.getenv_opt "HOME" with
               | Some home -> [Filename.concat home ".pi/agent/sessions";
                               Filename.concat home ".pi/sessions"]
               | None -> [".pi/agent/sessions"; ".pi/sessions"]))
  | _ ->
      (match Sys.getenv_opt "BP3_MUSE_TAPE_DIR" with
       | Some d when d <> "" -> [d]
       | _ -> (match Sys.getenv_opt "HOME" with
               | Some home -> [Filename.concat home ".local/share/muse/sessions"]
               | None -> [".local/share/muse/sessions"]))

let rec collect_tapes dir acc =
  let entries = try Array.to_list (Sys.readdir dir) with _ -> [] in
  List.fold_left (fun acc n ->
    let p = Filename.concat dir n in
    if try Sys.is_directory p with _ -> false then collect_tapes p acc
    else if Filename.check_suffix n ".jsonl" then p :: acc else acc) acc entries

let member_str_opt j key =
  try match Yojson.Safe.Util.member key j with `String s -> Some s | _ -> None
  with _ -> None

let entry_id_of_line ln =
  try
    let j = Yojson.Safe.from_string ln in
    (match member_str_opt j "id" with Some _ as v -> v | None ->
     match member_str_opt j "uuid" with Some _ as v -> v | None ->
     match member_str_opt j "session_id" with Some _ as v -> v | None ->
     (* muse retained frames wrap the real record as a string *)
     try match Yojson.Safe.Util.member "children" j with
       | `List (first :: _) ->
           (match member_str_opt first "record_json" with
            | Some raw ->
                (try let inner = Yojson.Safe.from_string raw in
                     member_str_opt inner "id"
                 with _ -> None)
            | None -> None)
       | _ -> None
     with _ -> None)
  with _ -> None

(* A tape references a Run only through a binding, never a
   bare mention: BP3_RUN_ID=<id> in a command or a stamped
   "run_id" field. A session is referenced by owning it. *)
let tape_references_run text run =
  contains_sub text ("BP3_RUN_ID=" ^ run)
  || contains_sub text ("\"run_id\":\"" ^ run ^ "\"")
  || contains_sub text ("\"run_id\": \"" ^ run ^ "\"")

let tape_references_session text session =
  contains_sub text ("\"session_id\":\"" ^ session ^ "\"")
  || contains_sub text ("\"session_id\": \"" ^ session ^ "\"")

let session_id_of_tape path =
  let text = read_file_or path "" in
  let lines = String.split_on_char '\n' text in
  let from_lines =
    List.fold_left (fun acc ln ->
      match acc with Some _ -> acc | None ->
        (try
           let j = Yojson.Safe.from_string (String.trim ln) in
           (match member_str_opt j "type" with
            | Some "session" -> member_str_opt j "id"
            | _ ->
                (match member_str_opt j "session_id" with Some _ as v -> v | None ->
                 try match Yojson.Safe.Util.member "children" j with
                   | `List (first :: _) ->
                       (match member_str_opt first "record_json" with
                        | Some raw ->
                            (try let inner = Yojson.Safe.from_string raw in
                                 (try match Yojson.Safe.Util.member "stream" inner with
                                    | `Assoc fs -> (match List.assoc_opt "id" fs with
                                                    | Some (`String s) -> Some s | _ -> None)
                                    | _ -> None
                                  with _ -> None)
                             with _ -> None)
                        | None -> None)
                   | _ -> None
                 with _ -> None))
         with _ -> None)) None lines in
  match from_lines with
  | Some _ as v -> v
  | None ->
      if Filename.basename path = "session.jsonl"
      then Some (Filename.basename (Filename.dirname path)) else None

let extract_run_ids text =
  let ids = ref [] in
  let add v = if v <> "" && not (List.mem v !ids) then ids := v :: !ids in
  let scan marker parse =
    let rec go from =
      if from < String.length text then
        match (try Some (Str.search_forward (Str.regexp_string marker) text from) with _ -> None) with
        | Some i -> parse (i + String.length marker); go (i + String.length marker)
        | None -> () in
    go 0 in
  scan "BP3_RUN_ID=" (fun start ->
    let rec take j = if j < String.length text &&
      ((text.[j] >= 'a' && text.[j] <= 'z') || (text.[j] >= 'A' && text.[j] <= 'Z') ||
       (text.[j] >= '0' && text.[j] <= '9') || text.[j] = '-' || text.[j] = '_' || text.[j] = '.')
      then take (j + 1) else j in
    let stop = take start in
    if stop > start then add (String.sub text start (stop - start)));
  scan "\"run_id\":\"" (fun start ->
    match (try Some (String.index_from text start '"') with _ -> None) with
    | Some stop -> add (String.sub text start (stop - start))
    | None -> ());
  List.rev !ids

type ft_flags = {
  mutable ft_run : string option; mutable ft_session : string option;
  mutable ft_entry : string option;
  mutable ft_before : int; mutable ft_after : int;
  mutable ft_before_set : bool; mutable ft_after_set : bool;
}

let nonneg_int flag v =
  let n = try int_of_string v with _ -> -1 in
  if n < 0 || string_of_int n <> v then
    usage (flag ^ " needs a non-negative integer, got: " ^ v)
  else n

let parse_ft_flags args =
  let fl = { ft_run = None; ft_session = None; ft_entry = None;
             ft_before = 0; ft_after = 0; ft_before_set = false; ft_after_set = false } in
  let rec loop = function
    | [] -> fl
    | "--run-id" :: v :: rest ->
        if fl.ft_run <> None then usage "duplicate flag --run-id";
        fl.ft_run <- Some v; loop rest
    | "--session-id" :: v :: rest ->
        if fl.ft_session <> None then usage "duplicate flag --session-id";
        fl.ft_session <- Some v; loop rest
    | "--entry" :: v :: rest ->
        if fl.ft_entry <> None then usage "duplicate flag --entry";
        fl.ft_entry <- Some v; loop rest
    | "--before-entries" :: v :: rest ->
        if fl.ft_before_set then usage "duplicate flag --before-entries";
        fl.ft_before <- nonneg_int "--before-entries" v; fl.ft_before_set <- true; loop rest
    | "--after-entries" :: v :: rest ->
        if fl.ft_after_set then usage "duplicate flag --after-entries";
        fl.ft_after <- nonneg_int "--after-entries" v; fl.ft_after_set <- true; loop rest
    | ["--run-id"] | ["--session-id"] | ["--entry"] | ["--before-entries"] | ["--after-entries"] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop args

type tape_entry = {
  te_index : int; te_id : string option; te_offset : int; te_line : string;
}

let tape_entries path =
  let text = read_file_or path "" in
  let n = String.length text in
  let rec go idx off acc =
    if off >= n then List.rev acc
    else
      let stop = try String.index_from text off '\n' with _ -> n in
      let ln = String.sub text off (stop - off) in
      if String.trim ln = "" then go idx (stop + 1) acc
      else go (idx + 1) (stop + 1)
        ({ te_index = idx; te_id = entry_id_of_line ln; te_offset = off; te_line = ln } :: acc) in
  go 0 0 []

let entry_json e =
  let parsed = try Yojson.Safe.from_string e.te_line with _ -> json_str e.te_line in
  `Assoc [
    ("id", (match e.te_id with Some i -> json_str i | None -> `Null));
    ("index", `Int e.te_index);
    ("byte_offset", `Int e.te_offset);
    ("byte_length", `Int (String.length e.te_line));
    ("digest", json_str ("sha256:" ^ sha256_hex e.te_line));
    ("entry", parsed);
  ]

let ambiguous what candidates =
  err "E_AMBIGUOUS" (`Assoc [(what, `List (List.map json_str candidates))])
    ("Ambiguous " ^ what ^ "; refusing to pick: " ^ String.concat ", " candidates) 1

let do_find_tape args =
  let fl = parse_ft_flags args in
  if (fl.ft_before_set || fl.ft_after_set) && fl.ft_entry = None then
    usage "--before-entries/--after-entries need --entry";
  (match fl.ft_run, fl.ft_session with
   | None, None -> usage "find-tape needs --run-id or --session-id"
   | Some "", _ | _, Some "" -> usage "identity flags need a non-empty value"
   | _ -> ());
  let records = all_init_records () in
  let by_run = match fl.ft_run with
    | Some r -> List.filter (fun (rec_ : init_record) -> rec_.run_id = r) records
    | None -> [] in
  let by_sess = match fl.ft_session with
    | Some s -> List.filter (fun (rec_ : init_record) -> rec_.session_id = Some s) records
    | None -> [] in
  let sess_runs = dedup (List.map (fun (rec_ : init_record) -> rec_.run_id) by_sess) in
  if List.length sess_runs > 1 then ambiguous "session-id" sess_runs;
  (match fl.ft_run, fl.ft_session with
   | Some r, Some s ->
       if by_run <> [] && by_sess <> [] && sess_runs <> [r] then
         usage "--run-id and --session-id disagree";
       List.iter (fun (rec_ : init_record) ->
         if rec_.session_id <> None && rec_.session_id <> Some s then
           usage "--run-id and --session-id disagree") by_run
   | _ -> ());
  let record = match by_run with
    | rec_ :: _ -> Some rec_
    | [] -> (match by_sess with rec_ :: _ -> Some rec_ | [] -> None) in
  (match by_run with
   | _ :: _ :: _ ->
       let tapes = dedup (List.filter_map (fun (rec_ : init_record) -> rec_.tape_path) by_run) in
       let sessions = dedup (List.filter_map (fun (rec_ : init_record) -> rec_.session_id) by_run) in
       if List.length tapes > 1 || List.length sessions > 1 then
         ambiguous "run-id" (tapes @ sessions)
   | _ -> ());
  let run_needles = dedup (
    (match fl.ft_run with Some r -> [r] | None -> []) @
    (match record with Some rec_ -> [rec_.run_id] | None -> [])) in
  let sess_needles = dedup (
    (match fl.ft_session with Some s -> [s] | None -> []) @
    (match record with Some rec_ -> (match rec_.session_id with Some s -> [s] | None -> []) | None -> [])) in
  let tape_matches text path =
    List.exists (fun nd -> tape_references_run text nd) run_needles
    || List.exists (fun nd -> tape_references_session text nd
                              || session_id_of_tape path = Some nd) sess_needles in
  (* resolve (wal, harness, session_id, pid, run_id) *)
  let record_hit =
    match record with
    | Some rec_ ->
        (match rec_.tape_path with
         | Some tp when Sys.file_exists tp ->
             let text = read_file_or tp "" in
             if tape_matches text tp
             then Some (tp, rec_.harness, rec_.session_id, rec_.pid, rec_.run_id)
             else None
         | Some tp ->
             err "E_NOT_FOUND" (`Assoc [("wal", json_str tp); ("run_id", json_str rec_.run_id)])
               ("Tape named by the InitRecord does not exist: " ^ tp) 1
         | None -> None)
    | None -> None in
  let (wal, harness, session_id, pid, run_id) =
    match record_hit with
    | Some hit -> hit
    | None ->
        let harnesses = match record with
          | Some rec_ when rec_.harness <> "" -> [rec_.harness]
          | _ -> ["muse-code"; "pi"] in
        let candidates = List.concat_map (fun h ->
          List.concat_map (fun root_ -> collect_tapes root_ []) (tape_roots h)
          |> List.filter_map (fun p ->
               let text = read_file_or p "" in
               if tape_matches text p
               then Some (p, h, text) else None)) harnesses in
        let paths = dedup (List.map (fun (p, _, _) -> p) candidates) in
        (match paths with
         | [] ->
             let facts = match fl.ft_run with
               | Some r -> `Assoc [("run_id", json_str r)]
               | None -> `Assoc [("session_id", json_str (match fl.ft_session with Some s -> s | None -> ""))] in
             err "E_NOT_FOUND" facts "No tape references that run; no guess made." 1
         | _ :: _ :: _ -> ambiguous "tape" paths
         | [p] ->
             let (_, h, text) = List.find (fun (cp, _, _) -> cp = p) candidates in
             let sess = (match record with Some rec_ -> rec_.session_id | None -> None) in
             let sess = match sess with Some _ -> sess | None -> session_id_of_tape p in
             let sess = match sess with Some _ -> sess | None -> fl.ft_session in
             let run = (match record with Some rec_ -> rec_.run_id | None ->
                        match fl.ft_run with Some r -> r | None ->
                        match extract_run_ids text with
                        | [r] -> r
                        | _ :: _ :: _ -> ambiguous "session-id" (extract_run_ids text)
                        | [] -> (match fl.ft_session with Some s -> s | None -> "")) in
             let pid = match record with Some rec_ -> rec_.pid | None -> None in
             (p, h, sess, pid, run)) in
  (match fl.ft_session, session_id with
   | Some s, Some found when s <> found ->
       err "E_NOT_FOUND" (`Assoc [("session_id", json_str s)])
         "The tape for that run carries a different session-id." 1
   | _ -> ());
  let base = [
    ("ok", `Bool true);
    ("run_id", json_str run_id);
    ("harness", json_str harness);
    ("session_id", (match session_id with Some s -> json_str s | None -> `Null));
    ("wal", json_str wal);
    ("tape_path", json_str wal);
    ("pid", (match pid with Some p -> `Int p | None -> `Null));
  ] in
  (match fl.ft_entry with
   | None -> print_endline (Yojson.Safe.to_string (`Assoc base)); 0
   | Some wanted ->
       let entries = tape_entries wal in
       (match List.find_opt (fun e -> e.te_id = Some wanted) entries with
        | None ->
            err "E_NOT_FOUND" (`Assoc [("entry", json_str wanted); ("wal", json_str wal)])
              ("No entry with that id in the tape: " ^ wanted) 1
        | Some hit ->
            let lo = max 0 (hit.te_index - fl.ft_before) in
            let hi = min (List.length entries - 1) (hit.te_index + fl.ft_after) in
            let window = List.filter (fun e -> e.te_index >= lo && e.te_index <= hi) entries in
            let fields = base @ [
              ("entry", entry_json hit);
              ("entries", `List (List.map entry_json window));
            ] in
            print_endline (Yojson.Safe.to_string (`Assoc fields)); 0))

(* ---------- watch (mvp.3) ---------- *)
type wt_flags = {
  mutable wt_run : string option; mutable wt_session : string option;
  mutable wt_silence : int; mutable wt_timeout : int; mutable wt_grace : int;
  mutable wt_silence_set : bool; mutable wt_timeout_set : bool;
  mutable wt_grace_set : bool;
}

let parse_wt_flags args =
  let fl = { wt_run = None; wt_session = None;
             wt_silence = 600; wt_timeout = 1800; wt_grace = 1;
             wt_silence_set = false; wt_timeout_set = false;
             wt_grace_set = false } in
  let rec loop = function
    | [] -> fl
    | "--run-id" :: v :: rest ->
        if fl.wt_run <> None then usage "duplicate flag --run-id";
        fl.wt_run <- Some v; loop rest
    | "--session-id" :: v :: rest ->
        if fl.wt_session <> None then usage "duplicate flag --session-id";
        fl.wt_session <- Some v; loop rest
    | "--silence-seconds" :: v :: rest ->
        if fl.wt_silence_set then usage "duplicate flag --silence-seconds";
        fl.wt_silence <- positive_seconds "--silence-seconds" v;
        fl.wt_silence_set <- true; loop rest
    | "--timeout-seconds" :: v :: rest ->
        if fl.wt_timeout_set then usage "duplicate flag --timeout-seconds";
        fl.wt_timeout <- positive_seconds "--timeout-seconds" v;
        fl.wt_timeout_set <- true; loop rest
    | "--grace-seconds" :: v :: rest ->
        if fl.wt_grace_set then usage "duplicate flag --grace-seconds";
        fl.wt_grace <- positive_seconds "--grace-seconds" v;
        fl.wt_grace_set <- true; loop rest
    | ["--run-id"] | ["--session-id"] | ["--silence-seconds"]
    | ["--timeout-seconds"] | ["--grace-seconds"] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop args

(* InitRecord-first resolution, like find-tape, except a
   missing or untrusted tape does not end the call: the Run
   is watched blind (W_SUPERVISOR_BLIND) on its pid alone.
   Only a Run with no record and no referencing tape is a
   typed miss. Returns (wal, harness, session_id, pid,
   run_id, blind). *)
let resolve_watch fl =
  (match fl.wt_run, fl.wt_session with
   | None, None -> usage "watch needs --run-id or --session-id"
   | Some "", _ | _, Some "" -> usage "identity flags need a non-empty value"
   | _ -> ());
  (match fl.wt_run with
   | Some r when contains_sub r "/" || contains_sub r " " ->
       usage ("invalid run-id: " ^ r)
   | _ -> ());
  let records = all_init_records () in
  let by_run = match fl.wt_run with
    | Some r -> List.filter (fun (rec_ : init_record) -> rec_.run_id = r) records
    | None -> [] in
  let by_sess = match fl.wt_session with
    | Some s -> List.filter (fun (rec_ : init_record) -> rec_.session_id = Some s) records
    | None -> [] in
  let sess_runs = dedup (List.map (fun (rec_ : init_record) -> rec_.run_id) by_sess) in
  if List.length sess_runs > 1 then ambiguous "session-id" sess_runs;
  (match fl.wt_run, fl.wt_session with
   | Some r, Some s ->
       if by_run <> [] && by_sess <> [] && sess_runs <> [r] then
         usage "--run-id and --session-id disagree";
       List.iter (fun (rec_ : init_record) ->
         if rec_.session_id <> None && rec_.session_id <> Some s then
           usage "--run-id and --session-id disagree") by_run
   | _ -> ());
  let record = match by_run with
    | rec_ :: _ -> Some rec_
    | [] -> (match by_sess with rec_ :: _ -> Some rec_ | [] -> None) in
  (match by_run with
   | _ :: _ :: _ ->
       let tapes = dedup (List.filter_map (fun (rec_ : init_record) -> rec_.tape_path) by_run) in
       let sessions = dedup (List.filter_map (fun (rec_ : init_record) -> rec_.session_id) by_run) in
       if List.length tapes > 1 || List.length sessions > 1 then
         ambiguous "run-id" (tapes @ sessions)
   | _ -> ());
  let run_needles = dedup (
    (match fl.wt_run with Some r -> [r] | None -> []) @
    (match record with Some rec_ -> [rec_.run_id] | None -> [])) in
  let sess_needles = dedup (
    (match fl.wt_session with Some s -> [s] | None -> []) @
    (match record with Some rec_ -> (match rec_.session_id with Some s -> [s] | None -> []) | None -> [])) in
  let tape_matches text path =
    List.exists (fun nd -> tape_references_run text nd) run_needles
    || List.exists (fun nd -> tape_references_session text nd
                              || session_id_of_tape path = Some nd) sess_needles in
  match record with
  | Some rec_ when rec_.tape_path <> None ->
      let tp = (match rec_.tape_path with Some t -> t | None -> "") in
      if not (Sys.file_exists tp) then
        (Some tp, rec_.harness, rec_.session_id, rec_.pid, rec_.run_id, true)
      else
        let text = read_file_or tp "" in
        if tape_matches text tp then
          (Some tp, rec_.harness, rec_.session_id, rec_.pid, rec_.run_id, false)
        else
          (match rec_.pid with
           | Some _ -> (None, rec_.harness, rec_.session_id, rec_.pid, rec_.run_id, true)
           | None -> (None, rec_.harness, rec_.session_id, None, rec_.run_id, true))
  | _ ->
      let harnesses = match record with
        | Some rec_ when rec_.harness <> "" -> [rec_.harness]
        | _ -> ["muse-code"; "pi"] in
      let candidates = List.concat_map (fun h ->
        List.concat_map (fun root_ -> collect_tapes root_ []) (tape_roots h)
        |> List.filter_map (fun p ->
             let text = read_file_or p "" in
             if tape_matches text p
             then Some (p, h, text) else None)) harnesses in
      let paths = dedup (List.map (fun (p, _, _) -> p) candidates) in
      (match paths with
       | [] ->
           (match record with
            | Some rec_ ->
                (None, rec_.harness, rec_.session_id, rec_.pid, rec_.run_id, true)
            | None ->
                let facts = match fl.wt_run with
                  | Some r -> `Assoc [("run_id", json_str r)]
                  | None -> `Assoc [("session_id", json_str (match fl.wt_session with Some s -> s | None -> ""))] in
                err "E_NOT_FOUND" facts "No tape references that run; no guess made." 1)
       | _ :: _ :: _ -> ambiguous "tape" paths
       | [p] ->
           let (_, h, text) = List.find (fun (cp, _, _) -> cp = p) candidates in
           let sess = (match record with Some rec_ -> rec_.session_id | None -> None) in
           let sess = match sess with Some _ -> sess | None -> session_id_of_tape p in
           let sess = match sess with Some _ -> sess | None -> fl.wt_session in
           let run = (match record with Some rec_ -> rec_.run_id | None ->
                      match fl.wt_run with Some r -> r | None ->
                      match extract_run_ids text with
                      | [r] -> r
                      | _ :: _ :: _ -> ambiguous "session-id" (extract_run_ids text)
                      | [] -> (match fl.wt_session with Some s -> s | None -> "")) in
           let pid = match record with Some rec_ -> rec_.pid | None -> None in
           (Some p, h, sess, pid, run, false))

(* Watch-local lifecycle: derivation words only. Watch
   observes pid exit directly, so a dead pid without close
   evidence is orphaned at once; a settle row or a close
   marker alone never finishes a live child. *)
let watch_lifecycle ~alive ~exit_obs ~closed ~settle ~tape_seen ~fresh =
  if ((exit_obs || settle) && closed && alive <> Some true) then "finished"
  else if alive = Some false then "orphaned"
  else if not tape_seen && alive = None && not exit_obs && not settle then "init"
  else if not fresh && alive <> Some true then "orphaned"
  else "active"

let do_watch args =
  let fl = parse_wt_flags args in
  let (wal, harness, session_id, pid, run_id, blind0) = resolve_watch fl in
  let start = Unix.time () in
  let deadline = start +. float_of_int fl.wt_timeout in
  let last_growth = ref start in
  let last_size = ref (-1) in
  let seen_once = ref false in
  let exit_obs = ref false in
  let closed = ref false in
  let settle = ref false in
  let blind = ref blind0 in
  let last_key = ref "" in
  let wait_dead secs =
    let until = Unix.time () +. secs in
    let rec go () =
      match pid with
      | Some p when pid_alive p && Unix.time () < until ->
          ignore (Unix.select [] [] [] 0.05); go ()
      | _ -> () in
    go () in
  let rec loop () =
    let now = Unix.time () in
    (* derivation fold for this Run: sticky mechanical facts *)
    (match derivations_dir () with
     | Some dir ->
         let path = Filename.concat dir (run_id ^ ".jsonl") in
         if Sys.file_exists path then begin
           let (_, dobs, dwarns) = fold_run_file ~silence_seconds:fl.wt_silence path in
           if dobs.exit_observed then exit_obs := true;
           if dobs.tape_closed then closed := true;
           if dobs.settle_row then settle := true;
           if dwarns <> [] then blind := true
         end
     | None -> ());
    (* tape: growth resets silence; signals are sticky *)
    let tape_seen = ref false in
    (match wal with
     | Some tp ->
         (try
            let st = Unix.stat tp in
            tape_seen := true;
            if not !seen_once then begin
              seen_once := true; last_size := st.Unix.st_size;
              last_growth := now
            end else if st.Unix.st_size <> !last_size then begin
              last_size := st.Unix.st_size; last_growth := now
            end;
            let (c, s) = tape_signals (read_file_or tp "") in
            if c then closed := true;
            if s then settle := true
          with _ -> blind := true)
     | None -> blind := true);
    let alive = match pid with Some p -> Some (pid_alive p) | None -> None in
    if alive = Some false then exit_obs := true;
    let fresh = now -. !last_growth <= float_of_int fl.wt_silence in
    let lifecycle = watch_lifecycle ~alive ~exit_obs:!exit_obs
      ~closed:!closed ~settle:!settle ~tape_seen:!tape_seen ~fresh in
    if lifecycle <> !last_key then begin
      last_key := lifecycle;
      let row = `Assoc [
        ("kind", json_str "lifecycle_change");
        ("run_id", json_str run_id);
        ("lifecycle", json_str lifecycle);
        ("harness", json_str harness);
      ] in
      print_endline (Yojson.Safe.to_string row);
      flush stdout
    end;
    let finish outcome fin_lifecycle =
      let warnings = if !blind then ["W_SUPERVISOR_BLIND"] else [] in
      let fields = [
        ("ok", `Bool true);
        ("run_id", json_str run_id);
        ("harness", json_str harness);
        ("session_id", (match session_id with Some s -> json_str s | None -> `Null));
        ("wal", (match wal with Some w -> json_str w | None -> `Null));
        ("tape_path", (match wal with Some w -> json_str w | None -> `Null));
        ("pid", (match pid with Some p -> `Int p | None -> `Null));
        ("outcome", json_str outcome);
        ("settled", `Bool (outcome = "settled"));
        ("lifecycle", json_str fin_lifecycle);
        ("last_growth_seconds_ago", `Int (int_of_float (now -. !last_growth)));
      ] in
      let fields = if warnings = [] then fields
        else fields @ [("warnings", `List (List.map json_str warnings))] in
      print_endline (Yojson.Safe.to_string (`Assoc fields));
      exit_of_outcome outcome in
    if (!exit_obs || !settle) && !closed && alive <> Some true then
      finish "settled" "finished"
    else if alive = Some true && not !closed && not !settle
            && now -. !last_growth > float_of_int fl.wt_silence then begin
      (* sole killer: silence past budget, no settling grace *)
      (match pid with
       | Some p ->
           (try Unix.kill p Sys.sigterm with _ -> ());
           wait_dead (float_of_int fl.wt_grace);
           if pid_alive p then begin
             (try Unix.kill p Sys.sigkill with _ -> ());
             wait_dead (float_of_int fl.wt_grace)
           end
       | None -> ());
      finish "watchdog_killed" "orphaned"
    end
    else if now >= deadline then
      finish "timeout" lifecycle
    else begin
      ignore (Unix.select [] [] [] 0.05);
      loop ()
    end in
  loop ()

(* ---------- help (docstrings beside dispatch) ---------- *)
let help_harness = "bp3 harness - harness machinery door. Verbs:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]   passive loop: tell -> watch -> judge -> finalize\n\
  bp3 harness init-check [--engine muse-code|pi]   probe tape sources; blindness is W_SUPERVISOR_BLIND, never blocking\n\
  bp3 harness find-tape --run-id <id> [--entry <id>] [--before-entries <n>] [--after-entries <n>]   InitRecord-first run-id -> tape; --session-id <id> is a reverse lookup\n\
  bp3 harness watch --run-id <id> [--silence-seconds <n>] [--timeout-seconds <n>] [--grace-seconds <n>]   blocking watch: sole TERM/KILL owner\n\
  bp3 harness desk <verb> ...                      machine-local desks: derive, create, inspect, remove, prepare, check, exit, release, list\n\
Aliases: s=supervisor, i=init-check, f=find-tape, w=watch, d=desk. Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_supervisor = "bp3 harness supervisor - passive supervisor loop for one quest:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]\n\
  Streams NDJSON lifecycle_change rows on stdout, ends with one JSON verdict {ok, quest, outcome, settled, rollup, runs, inbox, orphans}.\n\
  Outcomes and exit classes: settled=0, watchdog_killed=1 (terminal), timeout=3 (retryable), human_gate=4 (needs-human).\n\
  Durations are bare positive integers; 0, negatives, and suffixed values are usage errors.\n\
  Mechanism (mvp.4): each changed tick appends one pointer-only observation row to the Run's own <git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl (keyed by run-id; session-id is only an InitRecord field) and refreshes its disposable <run-id>.json cache. Since mvp.5 the derivation logs are the sole lifecycle read path; the retired shared maps are never read or written.\n\
Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_init_check = "bp3 harness init-check - probe tape sources per harness:\n\
  bp3 harness init-check [--engine muse-code|pi]\n\
  Emits {ok, checks}; a missing or reshaped tape source adds W_SUPERVISOR_BLIND to warnings and never blocks work.\n\
Example: bp3 harness init-check --engine muse-code\n"

let help_find_tape = "bp3 harness find-tape - InitRecord-first tape lookup:\n\
  bp3 harness find-tape --run-id <id> [--entry <id>] [--before-entries <n>] [--after-entries <n>]\n\
  bp3 harness find-tape --session-id <id>\n\
  Run-id is the sole primary key; --session-id is a reverse lookup that must resolve to exactly one run-id. Both, neither, or disagreeing identity flags are E_USAGE; misses are E_NOT_FOUND; ambiguity is E_AMBIGUOUS and names every candidate.\n\
  --entry returns the one digest-verified entry (sha256 over its exact line, with byte range), widened by --before-entries/--after-entries (non-negative integers, default 0).\n\
  Emits {ok, run_id, harness, session_id, wal, pid} or, with --entry, plus {entry, entries}.\n\
Example: bp3 harness find-tape --run-id 20261115T000000Z-submit-pi-model-c1\n"

let help_watch = "bp3 harness watch - blocking watch on one Run:\n\
  bp3 harness watch --run-id <id> [--silence-seconds <n>] [--timeout-seconds <n>] [--grace-seconds <n>]\n\
  bp3 harness watch --session-id <id> [--silence-seconds <n>] [--timeout-seconds <n>] [--grace-seconds <n>]\n\
  Engine is derived from the Run InitRecord, never stated. Finds the tape like find-tape, then blocks in code: streams NDJSON lifecycle_change rows and ends with one verdict {ok, run_id, harness, session_id, wal, pid, outcome, settled, lifecycle}.\n\
  A tape closes on a session_closed marker or an assistant stop reason; exit plus closed (or settle plus closed) with no live pid is settled. Silence past --silence-seconds (default 600) sends SIGTERM, waits --grace-seconds (default 1), then SIGKILL: outcome watchdog_killed, lifecycle orphaned, settled false. A closed tape or a settle row suspends the silence kill; the overall timeout (--timeout-seconds, default 1800) still applies and leaves the pid alone. A missing tape is blindness: W_SUPERVISOR_BLIND in warnings, the pid is still watched, and blindness is never an outcome.\n\
  Identity flags follow find-tape: both, neither, or disagreeing flags are E_USAGE; misses are E_NOT_FOUND; ambiguity is E_AMBIGUOUS. Durations are bare positive integers; 0, negatives, and suffixed values are E_USAGE.\n\
  Outcomes and exit classes: settled=0, watchdog_killed=1 (terminal), timeout=3 (retryable), human_gate=4 (needs-human).\n\
Example: bp3 harness watch --run-id 20261115T000000Z-submit-pi-model-c1 --silence-seconds 600\n"

let help_desk = "bp3 harness desk - machine-local desks, never ledgered (same Worktree store as the retired bp3 worktree door, which remains its documented alias):\n\
  verbs: derive, create, inspect, remove, prepare, check, exit, release, list\n\
  bp3 harness desk prepare <quest> <exp> --run <run-id> [--commit <sha>] [--path <dir>]\n\
  bp3 harness desk prepare --quest <quest>   one desk for a whole quest\n\
  bp3 harness desk check --run <run-id>      recompute dirty/stale live by Run ID\n\
  bp3 harness desk release --run <run-id> [--force]   a dirty desk refuses without --force\n\
  bp3 harness desk list [--quest <quest>]\n\
Example: bp3 harness desk prepare my-quest exp-1 --run R1\n"

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
        | "find-tape" -> help_find_tape
        | "watch" -> help_watch
        | "desk" -> help_desk
        | _ -> help_harness); 0
  | verb_raw :: rest ->
      (match normalize_verb verb_raw with
       | "supervisor" ->
           (match rest with
            | quest :: tail -> do_supervisor quest tail
            | [] -> usage "supervisor needs a quest")
       | "init-check" -> do_init_check rest
       | "find-tape" -> do_find_tape rest
       | "watch" -> do_watch rest
       | "desk" ->
           (match rest with
            | [] -> usage "desk needs a verb: derive, create, inspect, remove, prepare, check, exit, release, or list"
            | _ -> Render.print_verdict ~fmt:"json" (Worktree.run rest); 0)
       | other -> usage ("unknown harness verb: " ^ other))
