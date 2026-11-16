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
   files are no longer imported on any path. Since mvp.8
   the InitRecord has a named writer: record-init, called
   by the induct workflow launcher before it spawns each
   workflow child (the child never writes its own proof).
   followup.1 fixed the writer discipline for parallel
   supervisors: one write() per derivation row on an
   O_APPEND descriptor, the derived-state cache written
   to a uniquely named temp file in the same directory
   and renamed over the old cache, and a torn final line
   ignored by readers and reported as W_TORN_TAIL.
   followup.2 replaced the assumed close marker with
   per-harness finish evidence proved on the real
   corpora: muse-code closes on a session.end entry and
   a muse child tape ends on a runtime terminal entry
   with no close marker at all; pi never closes, so a
   final assistant entry that stopped is its clean end
   and process exit is its exit entry. Only the last
   whole tape entry can carry the evidence. *)
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
  finish_evidence : bool;
  settle_row : bool;
  tape_seen : bool;
  fresh : bool;
}

let no_observation = {
  pid_alive = None; exit_observed = false; finish_evidence = false;
  settle_row = false; tape_seen = false; fresh = false;
}

(* Lifecycle is derived, never narrated: init / active /
   finished / orphaned. A live pid is never finished,
   whatever the tape tail says; a settle row alone never
   finishes a live child; stale plus alive stays active;
   blind probes add no fifth word (None means no
   InitRecord, no claim). *)
let derive_lifecycle init obs =
  match init with
  | None -> None
  | Some _ ->
      if obs.pid_alive <> Some true
         && ((obs.exit_observed && obs.finish_evidence)
             || (obs.settle_row && obs.finish_evidence)) then Some "finished"
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

(* A settle row named in tape text is a fact of its own
   and never finish evidence by itself. Finish evidence
   is per-harness and tail-scoped: tape_evidence below. *)
let tape_settle text = contains_sub text "run_settled"

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

(* ---------- writer discipline (followup.1) ---------- *)
(* Parallel supervisors fold the same Run, so the store
   stays safe with no locks and no daemon. A derivation
   row is exactly one write() on an O_APPEND descriptor:
   the kernel moves the offset as part of that write, so
   rows from concurrent writers interleave whole or not
   at all and no row is lost to a tear. The derived-state
   cache is written to a uniquely named temp file in the
   same directory, fsynced, then renamed over the cache:
   a reader sees the old snapshot or the new one, never
   a torn one, and the last writer wins whole. Readers
   in turn fold only newline-terminated rows; a final
   unterminated fragment is a torn tail — ignored, and
   reported as W_TORN_TAIL, never folded as fact. *)
let write_one fd path s =
  let n = Unix.write_substring fd s 0 (String.length s) in
  if n <> String.length s then
    raise (Unix.Unix_error (Unix.EIO, "write", path))

let append_row path row =
  let fd = Unix.openfile path
    [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND] 0o644 in
  (try write_one fd path (row ^ "\n")
   with e -> (try Unix.close fd with _ -> ()); raise e);
  Unix.close fd

(* Create-only sibling of append_row for the InitRecord:
   O_EXCL makes a racing second writer fail, never append. *)
let create_row path row =
  let fd = Unix.openfile path
    [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_APPEND] 0o644 in
  (try write_one fd path (row ^ "\n")
   with e -> (try Unix.close fd with _ -> ()); raise e);
  Unix.close fd

let cache_tmp_counter = ref 0

let write_cache_file path content =
  incr cache_tmp_counter;
  let tmp = Printf.sprintf "%s.tmp.%d.%d" path
    (Unix.getpid ()) !cache_tmp_counter in
  let fd = Unix.openfile tmp
    [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o644 in
  (try write_one fd tmp content; Unix.fsync fd
   with e ->
     (try Unix.close fd with _ -> ());
     (try Unix.unlink tmp with _ -> ());
     raise e);
  Unix.close fd;
  Sys.rename tmp path

(* Only newline-terminated lines are whole rows; the
   second result is true when an unterminated, non-blank
   final fragment (a torn tail) was dropped. *)
let whole_lines text =
  if text = "" then ([], false)
  else if text.[String.length text - 1] = '\n' then
    (String.split_on_char '\n' text, false)
  else
    match List.rev (String.split_on_char '\n' text) with
    | tail :: rest -> (List.rev rest, String.trim tail <> "")
    | [] -> ([], false)

let nested_str j outer key =
  try match Yojson.Safe.Util.member outer j with
    | `Assoc _ as o -> get_str o key ""
    | _ -> ""
  with _ -> ""

(* Per-harness finish evidence (followup.2), read off the
   last whole tape entry only: a marker named mid-tape is
   content, not an ending. muse-code: a session.end entry
   closes the tape; a runtime terminal entry is a child
   tape's exit entry (its tapes carry no close marker).
   pi: no tape ever closes; a session_closed entry or a
   final assistant entry that stopped is the clean end,
   and the exit itself is the pid's. Returns (finish
   evidence, exit entry, torn tail): a torn final entry —
   unterminated or unparseable — is evidence of nothing. *)
let tape_evidence harness text =
  let (lines, torn) = whole_lines text in
  let tail = List.fold_left (fun acc ln ->
    if String.trim ln = "" then acc else Some ln) None lines in
  match tail with
  | None -> (false, false, torn)
  | Some ln ->
      (try
         let j = Yojson.Safe.from_string ln in
         if harness = "pi" then
           let msg = try Yojson.Safe.Util.member "message" j with _ -> `Null in
           let stopped = get_str j "type" "" = "message"
             && get_str msg "role" "" = "assistant"
             && get_str msg "stopReason" "" = "stop" in
           (get_str j "type" "" = "session_closed" || stopped, false, torn)
         else
           let ended = get_str j "payload_type" "" = "session.end" in
           let terminal = get_str j "payload_type" "" = "runtime.session"
             && nested_str j "payload" "kind" = "run"
             && (try match Yojson.Safe.Util.member "payload" j with
                  | `Assoc _ as p ->
                      (match Yojson.Safe.Util.member "event" p with
                       | `Assoc _ as e -> get_str e "kind" "" = "terminal"
                       | _ -> false)
                  | _ -> false
                with _ -> false) in
           let fin = ended || terminal in
           (fin, fin, torn)
       with _ -> (false, false, true))

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

(* Fold one Run's derivation log. Only whole rows carry
   fact: a malformed whole line is skipped, and a torn
   tail (an unterminated final fragment left by a reader
   racing an append) is skipped and reported, never folded. *)
let fold_run_file ~silence_seconds path =
  let text = read_file_or path "" in
  let (lines, torn) = whole_lines text in
  let tail_warns = if torn then ["W_TORN_TAIL"] else [] in
  let init = ref None in
  let obs = ref no_observation in
  lines |> List.iter (fun ln ->
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
              finish_evidence = o.finish_evidence
                || get_bool j "finish_evidence"
                (* rows written before followup.2 named the
                   same fact tape_closed; they still fold *)
                || get_bool j "tape_closed";
              settle_row = o.settle_row || get_bool j "settle_row";
              tape_seen = o.tape_seen || get_bool j "tape_seen";
              fresh = o.fresh;
            }
        | _ -> ()
      with _ -> ());
  (match !init with
   | None -> (!init, !obs, tail_warns)
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
       (* the tape tail itself is folded live, so a Run
          derives finished from files + pid alone, with no
          probe row written first and no memory carried *)
       let (fin, exit_e, torn_t) = match rec_.tape_path with
         | Some tp -> tape_evidence rec_.harness (read_file_or tp "")
         | None -> (false, false, false) in
       let o = { o with pid_alive = alive; tape_seen; fresh;
                 exit_observed = o.exit_observed || exit_e
                  || alive = Some false;
                 finish_evidence = o.finish_evidence || fin } in
       (!init, o,
        (if !blind then ["W_SUPERVISOR_BLIND"] else [])
        @ (if torn_t then ["W_TORN_TAIL"] else []) @ tail_warns))

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
    write_cache_file (cache_path dir run_id) (Yojson.Safe.to_string j)
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
  let (lines, _torn) = whole_lines text in
  let last = ref None in
  lines |> List.iter (fun ln ->
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
  let tape_text = match rec_.tape_path with
    | Some tp -> read_file_or tp "" | None -> "" in
  let (fin, exit_e, torn_t) = match rec_.tape_path with
    | Some _ -> tape_evidence rec_.harness tape_text | None -> (false, false, false) in
  let exit_obs = prior.exit_observed || exit_e
    || (match rec_.pid with Some p -> not (pid_alive p) | None -> false) in
  let settle = tape_settle tape_text in
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
              finish_evidence = prior.finish_evidence || fin;
              settle_row = prior.settle_row || settle;
              tape_seen; fresh } in
  (obs, (if blind then ["W_SUPERVISOR_BLIND"] else [])
        @ (if torn_t then ["W_TORN_TAIL"] else []))

(* Append one observation row to the Run's own derivation
   log, only when its derived lifecycle changed. Parallel
   Runs write separate files; parallel supervisors folding
   the same Run append whole rows only (append_row). *)
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
          ("finish_evidence", `Bool obs.finish_evidence);
          ("settle_row", `Bool obs.settle_row);
          ("tape_seen", `Bool obs.tape_seen);
          ("tape_path", (match rf.rf_rec.tape_path with Some s -> json_str s | None -> `Null));
          ("pid", (match rf.rf_rec.pid with Some p -> `Int p | None -> `Null));
          ("warnings", `List (List.map json_str warns));
        ] in
        append_row rf.rf_jsonl (Yojson.Safe.to_string row)
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
          let (lines, _torn) = whole_lines text in
          let found = ref [] in
          lines |> List.iter (fun ln ->
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
   observes pid exit directly, so a dead pid without
   finish evidence is orphaned at once; a settle row or
   finish evidence alone never finishes a live child. *)
let watch_lifecycle ~alive ~exit_obs ~evidence ~settle ~tape_seen ~fresh =
  if ((exit_obs || settle) && evidence && alive <> Some true) then "finished"
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
  let evidence = ref false in
  let torn_t = ref false in
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
           if dobs.finish_evidence then evidence := true;
           if dobs.settle_row then settle := true;
           if List.mem "W_SUPERVISOR_BLIND" dwarns then blind := true
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
            let text = read_file_or tp "" in
            let (fin, exit_e, tr) = tape_evidence harness text in
            if fin then evidence := true;
            if exit_e then exit_obs := true;
            if tr then torn_t := true;
            if tape_settle text then settle := true
          with _ -> blind := true)
     | None -> blind := true);
    let alive = match pid with Some p -> Some (pid_alive p) | None -> None in
    if alive = Some false then exit_obs := true;
    let fresh = now -. !last_growth <= float_of_int fl.wt_silence in
    let lifecycle = watch_lifecycle ~alive ~exit_obs:!exit_obs
      ~evidence:!evidence ~settle:!settle ~tape_seen:!tape_seen ~fresh in
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
      let warnings = (if !blind then ["W_SUPERVISOR_BLIND"] else [])
        @ (if !torn_t then ["W_TORN_TAIL"] else []) in
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
    if (!exit_obs || !settle) && !evidence && alive <> Some true then
      finish "settled" "finished"
    else if alive = Some true && not !evidence && not !settle
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

(* ---------- record-init (mvp.8: the InitRecord writer) ---------- *)
(* The induct workflow launcher is the named writer: it is
   the only actor present before a workflow child exists, so
   it calls this verb before spawning the child. The child
   never writes its own proof. Create-only: an existing
   derivation log for the run-id is E_EXISTS, never an
   overwrite or a second init row. *)
type ri_flags = {
  mutable ri_run : string option; mutable ri_harness : string option;
  mutable ri_session : string option; mutable ri_pid : int option;
  mutable ri_tape : string option; mutable ri_quest : string option;
  mutable ri_exp : string option; mutable ri_desk : string option;
  mutable ri_model : string option;
}

let parse_ri_flags args =
  let fl = { ri_run = None; ri_harness = None; ri_session = None;
             ri_pid = None; ri_tape = None; ri_quest = None;
             ri_exp = None; ri_desk = None; ri_model = None } in
  let rec loop = function
    | [] -> fl
    | "--run-id" :: v :: rest ->
        if fl.ri_run <> None then usage "duplicate flag --run-id";
        fl.ri_run <- Some v; loop rest
    | "--harness" :: v :: rest ->
        if fl.ri_harness <> None then usage "duplicate flag --harness";
        fl.ri_harness <- Some v; loop rest
    | "--session-id" :: v :: rest ->
        if fl.ri_session <> None then usage "duplicate flag --session-id";
        fl.ri_session <- Some v; loop rest
    | "--pid" :: v :: rest ->
        if fl.ri_pid <> None then usage "duplicate flag --pid";
        fl.ri_pid <- Some (positive_seconds "--pid" v); loop rest
    | "--tape-path" :: v :: rest ->
        if fl.ri_tape <> None then usage "duplicate flag --tape-path";
        fl.ri_tape <- Some v; loop rest
    | "--quest" :: v :: rest ->
        if fl.ri_quest <> None then usage "duplicate flag --quest";
        fl.ri_quest <- Some v; loop rest
    | "--exp" :: v :: rest ->
        if fl.ri_exp <> None then usage "duplicate flag --exp";
        fl.ri_exp <- Some v; loop rest
    | "--desk" :: v :: rest ->
        if fl.ri_desk <> None then usage "duplicate flag --desk";
        fl.ri_desk <- Some v; loop rest
    | "--model" :: v :: rest ->
        if fl.ri_model <> None then usage "duplicate flag --model";
        fl.ri_model <- Some v; loop rest
    | ["--run-id"] | ["--harness"] | ["--session-id"] | ["--pid"]
    | ["--tape-path"] | ["--quest"] | ["--exp"] | ["--desk"] | ["--model"] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop args

let do_record_init args =
  let fl = parse_ri_flags args in
  let run_id = match fl.ri_run with
    | Some r when r <> "" -> r
    | _ -> usage "record-init needs --run-id <id>" in
  if contains_sub run_id "/" || contains_sub run_id ".."
     || contains_sub run_id " " then
    usage ("invalid run-id: " ^ run_id);
  let harness = match fl.ri_harness with
    | Some h when h = "muse-code" || h = "pi" -> h
    | Some h -> usage ("--harness must be muse-code or pi, got: " ^ h)
    | None -> usage "record-init needs --harness muse-code|pi" in
  (match derivations_dir () with
   | None ->
       err "E_NOT_FOUND" (`Assoc [("run_id", json_str run_id)])
         "No derivation store (not a git repo?); no InitRecord written." 1
   | Some dir ->
       let path = Filename.concat dir (run_id ^ ".jsonl") in
       if Sys.file_exists path then
         err "E_EXISTS" (`Assoc [("run_id", json_str run_id);
                                 ("path", json_str path)])
           "An InitRecord already exists for that run-id; refusing to overwrite." 1;
       ensure_dir dir;
       let opt_fields = List.filter_map (fun x -> x) [
         (match fl.ri_session with Some s -> Some ("session_id", json_str s) | None -> None);
         (match fl.ri_pid with Some p -> Some ("pid", `Int p) | None -> None);
         (match fl.ri_tape with Some s -> Some ("tape_path", json_str s) | None -> None);
         (match fl.ri_quest with Some s -> Some ("quest", json_str s) | None -> None);
         (match fl.ri_exp with Some s -> Some ("exp", json_str s) | None -> None);
         (match fl.ri_desk with Some s -> Some ("desk", json_str s) | None -> None);
         (match fl.ri_model with Some s -> Some ("model", json_str s) | None -> None);
       ] in
       let row = `Assoc ([
         ("kind", json_str "init_record");
         ("run_id", json_str run_id);
         ("harness", json_str harness);
         ("ts", json_str (now_ts ()));
       ] @ opt_fields) in
       (try create_row path (Yojson.Safe.to_string row)
        with Unix.Unix_error (Unix.EEXIST, _, _) ->
          err "E_EXISTS" (`Assoc [("run_id", json_str run_id);
                                  ("path", json_str path)])
            "An InitRecord already exists for that run-id; refusing to overwrite." 1);
       print_endline (Yojson.Safe.to_string (`Assoc [
         ("ok", `Bool true);
         ("run_id", json_str run_id);
         ("harness", json_str harness);
         ("session_id", (match fl.ri_session with Some s -> json_str s | None -> `Null));
         ("pid", (match fl.ri_pid with Some p -> `Int p | None -> `Null));
         ("tape_path", (match fl.ri_tape with Some s -> json_str s | None -> `Null));
         ("quest", (match fl.ri_quest with Some s -> json_str s | None -> `Null));
         ("exp", (match fl.ri_exp with Some s -> json_str s | None -> `Null));
         ("path", json_str path);
       ]));
       0)

(* ---------- backtest (backtest.1: findings, not a gate) ---------- *)
let count_sub text sub =
  let n = String.length text and m = String.length sub in
  let rec go i acc =
    if m = 0 || i + m > n then acc
    else if String.sub text i m = sub then go (i + m) (acc + 1)
    else go (i + 1) acc in
  go 0 0

let extract_codes text =
  let codes = ref [] in
  let add v = if not (List.mem v !codes) then codes := v :: !codes in
  (try
     let re = Str.regexp "E_[A-Z][A-Z0-9_][A-Z0-9_]+" in
     let rec go from =
       if from < String.length text then
         match (try Some (Str.search_forward re text from) with _ -> None) with
         | Some i -> add (Str.matched_string text); go (i + 1)
         | None -> () in
     go 0
   with _ -> ());
  List.rev !codes

let extract_shas text =
  let is_hex c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') in
  let n = String.length text in
  let shas = ref [] in
  let rec go i =
    if i + 40 <= n && List.length !shas < 20 then
      let bounded_before = i = 0 || not (is_hex text.[i - 1]) in
      let bounded_after = i + 40 = n || not (is_hex text.[i + 40]) in
      if bounded_before && bounded_after then
        let rec all_hex k = k = 40 || (is_hex text.[i + k] && all_hex (k + 1)) in
        if all_hex 0 then begin
          let v = String.sub text i 40 in
          if not (List.mem v !shas) then shas := v :: !shas;
          go (i + 40)
        end else go (i + 1)
      else go (i + 1) in
  go 0;
  List.rev !shas

type bt_flags = { mutable bt_corpus : string option }

let parse_bt_flags args =
  let fl = { bt_corpus = None } in
  let rec loop = function
    | [] -> fl
    | "--corpus" :: v :: rest ->
        if fl.bt_corpus <> None then usage "duplicate flag --corpus";
        fl.bt_corpus <- Some v; loop rest
    | ["--corpus"] -> usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop args

let do_backtest args =
  let fl = parse_bt_flags args in
  let corpus = match fl.bt_corpus with
    | Some d when d <> "" -> d
    | _ -> (match tape_roots "muse-code" with d :: _ -> d | [] -> ".") in
  if not (try Sys.is_directory corpus with _ -> false) then
    err "E_NOT_FOUND" (`Assoc [("corpus", json_str corpus)])
      ("Corpus directory does not exist: " ^ corpus) 1;
  let tapes = List.sort String.compare (collect_tapes corpus []) in
  let traces = ref [] and findings = ref [] in
  List.iter (fun path ->
    try
      let text = read_file_or path "" in
      let (_lines, torn) = whole_lines text in
      let run_ids = extract_run_ids text in
      let refusals = extract_codes text in
      let commits = extract_shas text in
      let (fin, exit_e, torn_t) = tape_evidence "muse-code" text in
      let torn = torn || torn_t in
      let bp3_calls = count_sub text "bp3 q " + count_sub text "bp3 harness" in
      let has_submit = contains_sub text " submit" || contains_sub text "\"submit\"" in
      let run_id = match run_ids with r :: _ -> r | [] -> "" in
      traces := `Assoc [
        ("tape", json_str path); ("run_ids", `List (List.map json_str run_ids));
        ("bp3_calls", `Int bp3_calls);
        ("refusals", `List (List.map json_str refusals));
        ("commits", `List (List.map json_str commits));
        ("has_submit", `Bool has_submit);
        ("finish_evidence", `Bool fin); ("exit_observed", `Bool exit_e);
        ("torn_tail", `Bool torn)] :: !traces;
      let add_finding evidence target =
        findings := `Assoc [
          ("tape", json_str path); ("run_id", json_str run_id);
          ("evidence", json_str evidence); ("fix_target", json_str target)] :: !findings in
      if torn then add_finding "torn final tape entry" "adapter";
      if run_ids = [] then add_finding "foreign tape: no BP3_RUN_ID binding" "adapter";
      List.iter (fun code ->
        if not has_submit then
          add_finding (code ^ " refusal with no submit") "bp3 q u / hooks") refusals;
      if run_ids <> [] && not fin && not exit_e && refusals = [] then
        add_finding "identifiable Run with no finish evidence" "adapter"
    with _ ->
      findings := `Assoc [
        ("tape", json_str path); ("run_id", json_str "");
        ("evidence", json_str "unreadable tape skipped");
        ("fix_target", json_str "adapter")] :: !findings) tapes;
  let traces = List.rev !traces and findings = List.rev !findings in
  let identifiable = List.fold_left (fun acc t ->
    match t with `Assoc fs ->
      (match List.assoc_opt "run_ids" fs with
       | Some (`List (_ :: _)) -> acc + 1 | _ -> acc) | _ -> acc) 0 traces in
  print_endline (Yojson.Safe.to_string (`Assoc [
    ("ok", `Bool true); ("engine", json_str "muse-code");
    ("corpus", json_str corpus);
    ("tapes_replayed", `Int (List.length tapes));
    ("identifiable", `Int identifiable);
    ("traces", `List traces); ("findings", `List findings)]));
  0

(* ---------- help (docstrings beside dispatch) ---------- *)
let help_harness = "bp3 harness - harness machinery door. Verbs:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]   passive loop: tell -> watch -> judge -> finalize\n\
  bp3 harness init-check [--engine muse-code|pi]   probe tape sources; blindness is W_SUPERVISOR_BLIND, never blocking\n\
  bp3 harness find-tape --run-id <id> [--entry <id>] [--before-entries <n>] [--after-entries <n>]   InitRecord-first run-id -> tape; --session-id <id> is a reverse lookup\n\
  bp3 harness watch --run-id <id> [--silence-seconds <n>] [--timeout-seconds <n>] [--grace-seconds <n>]   blocking watch: sole TERM/KILL owner\n\
  bp3 harness desk <verb> ...                      machine-local desks: derive, create, inspect, remove, prepare, check, exit, release, list\n\
  bp3 harness record-init --run-id <id> --harness muse-code|pi [--quest <q>] [--exp <e>] [--session-id <s>] [--pid <n>] [--tape-path <p>] [--desk <d>] [--model <m>]   launcher writes the InitRecord before the child starts (create-only)\n\
  bp3 harness backtest [--corpus <dir>]   replay the muse fold over stored tapes; findings, not a gate\n\
Aliases: s=supervisor, i=init-check, f=find-tape, w=watch, d=desk, r=record-init, b=backtest. Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_supervisor = "bp3 harness supervisor - passive supervisor loop for one quest:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]\n\
  Streams NDJSON lifecycle_change rows on stdout, ends with one JSON verdict {ok, quest, outcome, settled, rollup, runs, inbox, orphans}.\n\
  Outcomes and exit classes: settled=0, watchdog_killed=1 (terminal), timeout=3 (retryable), human_gate=4 (needs-human).\n\
  Durations are bare positive integers; 0, negatives, and suffixed values are usage errors.\n\
  Mechanism (mvp.4): each changed tick appends one pointer-only observation row to the Run's own <git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl (keyed by run-id; session-id is only an InitRecord field) and refreshes its disposable <run-id>.json cache. Since mvp.5 the derivation logs are the sole lifecycle read path; the retired shared maps are never read or written. Writer discipline (followup.1): each row is a single write() on an O_APPEND descriptor and the cache is a uniquely named temp file in the same directory, fsynced and renamed over the old cache, so parallel supervisors never tear a row or the cache; a torn final line is ignored by the fold and reported as W_TORN_TAIL.\n\
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
  Finish evidence is per harness, read off the last whole tape entry: muse-code closes on a session.end entry, and a runtime terminal entry is a child tape's exit entry (child tapes carry no close marker); pi never closes, so a session_closed entry or a final assistant entry that stopped is its clean end. Exit plus finish evidence (or settle plus finish evidence) with no live pid is settled; a live pid is never finished. A torn final tape entry finishes nothing and warns W_TORN_TAIL. Silence past --silence-seconds (default 600) sends SIGTERM, waits --grace-seconds (default 1), then SIGKILL: outcome watchdog_killed, lifecycle orphaned, settled false. Finish evidence or a settle row suspends the silence kill; the overall timeout (--timeout-seconds, default 1800) still applies and leaves the pid alone. A missing tape is blindness: W_SUPERVISOR_BLIND in warnings, the pid is still watched, and blindness is never an outcome.\n\
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

let help_record_init = "bp3 harness record-init - write one Run's InitRecord (the launcher's verb; the child never writes its own proof):\n\
  bp3 harness record-init --run-id <id> --harness muse-code|pi [--quest <q>] [--exp <e>] [--session-id <s>] [--pid <n>] [--tape-path <p>] [--desk <d>] [--model <m>]\n\
  Appends the first derivation row (kind init_record) to <git-common-dir>/bp3/run-lifecycle-derivations/<run-id>.jsonl before the child starts, so find-tape/watch/supervisor resolve the Run from birth. Create-only: an existing log for the run-id is E_EXISTS; a bad run-id, engine, or pid is E_USAGE. Emits {ok, run_id, harness, session_id, pid, tape_path, quest, exp, path}.\n\
Example: bp3 harness record-init --run-id 20261115T000000Z-submit-muse-code-model-c1 --harness muse-code --quest toy --exp exp-1\n"

let is_help = function "-h" | "--help" -> true | _ -> false

let help_backtest = "bp3 harness backtest - replay the muse fold over stored tapes (findings, not a gate):\n\
  bp3 harness backtest [--corpus <dir>]\n\
  Reads every .jsonl tape under the corpus (default: the muse tape source), folds mechanical facts per tape (BP3_RUN_ID bindings, bp3 invocations, E_* refusals, commit shas, finish/exit evidence, torn tails) and emits one verdict {ok, engine, corpus, tapes_replayed, identifiable, traces, findings}. Each finding names its tape, run-id, evidence lines, and proposed fix target (bp3 q u, hooks, or adapter). A parser crash fails the call; findings themselves never gate. Truncated, foreign, and torn tapes are reported in findings, never fatal.\n\
Example: bp3 harness backtest --corpus ~/.local/share/muse/sessions\n"

let normalize_verb = function
  | "b" | "backtest" -> "backtest"
  | "s" | "supervisor" -> "supervisor"
  | "i" | "init-check" -> "init-check"
  | "f" | "find-tape" -> "find-tape"
  | "w" | "watch" -> "watch"
  | "d" | "desk" -> "desk"
  | "r" | "record-init" -> "record-init"
  | other -> other

let run = function
  | [] -> usage "harness needs a verb: supervisor, init-check, find-tape, watch, desk, record-init, or backtest"
  | [h] when is_help h -> print_string help_harness; 0
  | verb :: (h :: _) when is_help h ->
      print_string (match normalize_verb verb with
        | "supervisor" -> help_supervisor
        | "init-check" -> help_init_check
        | "find-tape" -> help_find_tape
        | "watch" -> help_watch
        | "desk" -> help_desk
        | "record-init" -> help_record_init
        | "backtest" -> help_backtest
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
       | "record-init" -> do_record_init rest
       | "backtest" -> do_backtest rest
       | "desk" ->
           (match rest with
            | [] -> usage "desk needs a verb: derive, create, inspect, remove, prepare, check, exit, release, or list"
            | _ -> Render.print_verdict ~fmt:"json" (Worktree.run rest); 0)
       | other -> usage ("unknown harness verb: " ^ other))
