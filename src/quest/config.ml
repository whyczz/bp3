(* config — the machine-local bp3 config store (config.1):
   <git-common-dir>/bp3/ holding config.json (machine
   settings only: local thresholds and gates), the per-run
   configs runs/<run_id>.json (one canonical record per
   Run; the shape is defined here, its writers are link
   mint/claim and bind-tape in mvp.1), links/, claims/, the
   derived by-session index, desks/, and the supervisor's
   run-lifecycle-derivations. Written only by bp3 verbs,
   never hand-edited, never committed; every worktree of
   the repo resolves the same tree through the git common
   dir, while contexts stay per-session. bp3 config views
   the store; contexts are folded from runs/, never stored
   in config.json. Thresholds are stored and viewed here;
   verdicts beyond the view consume them when their verbs
   land (depth cap at link mint in mvp.1, W_SETUP_SLOW in
   mvp.3). *)
open Gitx

(* ---------- layout ---------- *)
let config_dir () =
  match git_common_dir () with
  | None -> None
  | Some abs ->
      (* one spelling per store: /var and /private/var are the
         same tree on this host, and worktrees must agree *)
      let canon = try Unix.realpath abs with _ -> abs in
      Some (Filename.concat canon "bp3")

let runs_dir dir = Filename.concat dir "runs"
let links_dir dir = Filename.concat dir "links"
let claims_dir dir = Filename.concat dir "claims"
let by_session_dir dir = Filename.concat dir "by-session"
let desks_dir dir = Filename.concat dir "desks"
let derivations_dir_of dir = Filename.concat dir "run-lifecycle-derivations"
let config_file dir = Filename.concat dir "config.json"

(* Only an already-existing directory is benign; any other
   mkdir failure is the caller's diagnosis, raised here at
   the site that caused it (worktree.ml's ensure_dir rule). *)
let ensure_dir dir =
  let parent = Filename.dirname dir in
  (try Unix.mkdir parent 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (try Unix.mkdir dir 0o755
   with Unix.Unix_error (Unix.EEXIST, _, _) -> ())

(* Single-write temp file in the same directory, fsynced,
   then renamed over the target (followup.1 discipline):
   a reader sees the old snapshot or the new one, never a
   torn one. *)
let write_counter = ref 0

let write_file_atomic path content =
  incr write_counter;
  let tmp = Printf.sprintf "%s.tmp.%d.%d" path (Unix.getpid ()) !write_counter in
  let fd = Unix.openfile tmp [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o644 in
  (try
     let n = Unix.write_substring fd content 0 (String.length content) in
     if n <> String.length content then
       raise (Unix.Unix_error (Unix.EIO, "write", path));
     Unix.fsync fd
   with e ->
     (try Unix.close fd with _ -> ());
     (try Unix.unlink tmp with _ -> ());
     raise e);
  Unix.close fd;
  Sys.rename tmp path

(* ---------- thresholds (machine settings only) ---------- *)
type thresholds = { setup_slow_s : int; depth_cap : int }

let default_thresholds = { setup_slow_s = 180; depth_cap = 3 }

let thresholds_json t =
  `Assoc [("setup_slow_s", `Int t.setup_slow_s); ("depth_cap", `Int t.depth_cap)]

let default_config_json = `Assoc [("thresholds", thresholds_json default_thresholds)]

let jstr j key default =
  try match Yojson.Safe.Util.member key j with `String s -> s | _ -> default
  with _ -> default

let jopt j key =
  try match Yojson.Safe.Util.member key j with
    | `String s when s <> "" -> Some s | _ -> None
  with _ -> None

let jint j key default =
  try match Yojson.Safe.Util.member key j with `Int n -> n | _ -> default
  with _ -> default

let jobj j key =
  try match Yojson.Safe.Util.member key j with `Assoc _ as o -> Some o | _ -> None
  with _ -> None

(* Thresholds from a config document: under "thresholds" or at the
   top level; a missing or non-int field keeps its default. *)
let thresholds_of_json j =
  let scope = match jobj j "thresholds" with Some t -> t | None -> j in
  { setup_slow_s = jint scope "setup_slow_s" default_thresholds.setup_slow_s;
    depth_cap = jint scope "depth_cap" default_thresholds.depth_cap }

let load_thresholds dir =
  let path = config_file dir in
  if not (Sys.file_exists path) then default_thresholds
  else
    try thresholds_of_json (Yojson.Safe.from_string (read_file_or path ""))
    with _ -> default_thresholds

(* Zero setup: the first bp3 write on a fresh repo creates
   the whole tree with defaults; an existing config.json is
   never overwritten. Outside a git repo there is no store
   and the caller refuses. Returns the config dir. *)
let ensure_config () =
  match config_dir () with
  | None ->
      err "E_NOT_FOUND" (`Assoc [])
        "No bp3 config store: not inside a git repository." 1
  | Some dir ->
      List.iter ensure_dir
        [dir; runs_dir dir; links_dir dir; claims_dir dir; by_session_dir dir;
         desks_dir dir; derivations_dir_of dir];
      let cf = config_file dir in
      if not (Sys.file_exists cf) then
        write_file_atomic cf (Yojson.Safe.to_string default_config_json ^ "\n");
      dir

(* ---------- run configs: the contexts ---------- *)
type run_config = {
  rc_id : string;
  rc_kind : string;
  rc_quest : string;
  rc_node : string;
  rc_edge : string option;
  rc_state : string;
  rc_desk : string;
  rc_session : string option;
  rc_minted_at : string;
  rc_claimed_at : string;
  rc_parent : string;
  rc_depth : int;
  rc_harness : string;
  rc_pid : int option;
  rc_tape : string option;
  rc_mode : string;
}

let run_config_of_file path =
  try
    let j = Yojson.Safe.from_string (read_file_or path "") in
    let creator = jobj j "creator" in
    let claim = jobj j "claim" in
    let nested o key = match o with Some x -> jstr x key "" | None -> "" in
    let nested_opt o key = match o with Some x -> jopt x key | None -> None in
    let id = match jopt j "run_id" with
      | Some r -> r
      | None -> Filename.remove_extension (Filename.basename path) in
    if id = "" then None
    else
      Some { rc_id = id;
             rc_kind = jstr j "kind" "";
             rc_quest = jstr j "quest" (jstr j "graph" "");
             rc_node = jstr j "node" "";
             rc_edge = jopt j "edge";
             rc_state = jstr j "state" "";
             rc_desk = jstr j "desk" "";
             rc_session = nested_opt claim "session_id";
             rc_minted_at = nested creator "minted_at";
             rc_claimed_at = nested claim "claimed_at";
             rc_parent = nested creator "run_id";
             rc_depth = (match creator with
               | Some c -> jint c "depth" 0 | None -> 0);
             rc_harness = nested creator "harness";
             rc_pid = (match claim with
               | Some c -> (try match Yojson.Safe.Util.member "pid" c with
                            | `Int n -> Some n | _ -> None with _ -> None)
               | None -> None);
             rc_tape = jopt j "tape_path";
             rc_mode = jstr j "mode" "" }
  with _ -> None

(* A torn or foreign file under runs/ is never read as a
   valid run config; it is skipped, not folded. *)
let list_run_configs dir =
  let rd = runs_dir dir in
  if not (Sys.file_exists rd) then []
  else
    try
      Sys.readdir rd |> Array.to_list
      |> List.filter (fun n -> Filename.check_suffix n ".json")
      |> List.sort String.compare
      |> List.filter_map (fun n -> run_config_of_file (Filename.concat rd n))
      |> List.sort (fun a b -> String.compare a.rc_id b.rc_id)
    with _ -> []

let opt_json = function Some s -> json_str s | None -> `Null

let context_json rc =
  `Assoc [("quest", json_str rc.rc_quest); ("node", json_str rc.rc_node);
          ("edge", opt_json rc.rc_edge); ("run_id", json_str rc.rc_id);
          ("session_id", opt_json rc.rc_session);
          ("desk", json_str rc.rc_desk); ("state", json_str rc.rc_state);
          ("kind", json_str rc.rc_kind);
          ("parent_run_id", json_str rc.rc_parent);
          ("depth", `Int rc.rc_depth);
          ("mode", json_str rc.rc_mode)]

(* ---------- raw run configs (link mint/claim writers) ---------- *)
let run_config_path dir run_id =
  Filename.concat (runs_dir dir) (run_id ^ ".json")

let load_run_config_json dir run_id =
  let path = run_config_path dir run_id in
  if not (Sys.file_exists path) then None
  else
    try
      let j = Yojson.Safe.from_string (read_file_or path "") in
      (match j with `Assoc _ -> Some j | _ -> None)
    with _ -> None

let save_run_config_json dir run_id j =
  write_file_atomic (run_config_path dir run_id)
    (Yojson.Safe.to_string j ^ "\n")

(* Provenance: which verb wrote this context, and when.
   A claimed run config was last written by link claim; a
   minted one only by link mint. *)
let source_context_json rc =
  let (verb, ts) =
    if rc.rc_claimed_at <> "" || rc.rc_session <> None then
      ("link claim", rc.rc_claimed_at)
    else if rc.rc_minted_at <> "" then ("link mint", rc.rc_minted_at)
    else ("run config", "") in
  match context_json rc with
  | `Assoc fs ->
      `Assoc (fs @ [("source", `Assoc [("verb", json_str verb);
                                       ("ts", json_str ts)])])
  | other -> other

let desks_json rcs =
  let desks =
    List.sort_uniq String.compare
      (List.filter_map
         (fun rc -> if rc.rc_desk = "" then None else Some rc.rc_desk) rcs) in
  List.map (fun d ->
    `Assoc [("desk", json_str d);
            ("run_ids", `List (List.map json_str
              (List.map (fun rc -> rc.rc_id)
                 (List.filter (fun rc -> rc.rc_desk = d) rcs))))]) desks

(* ---------- by-session index (derived, rebuildable) ---------- *)
let contains_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec loop i = i + m <= n && (String.sub s i m = sub || loop (i + 1)) in
  m = 0 || loop 0

let valid_index_key s =
  s <> "" && s <> "." && s <> ".."
  && not (contains_sub s "/") && not (contains_sub s "\\")
  && not (contains_sub s "..") && s.[0] <> '.'

(* Rebuilt from runs/ on every view: deleting by-session/
   loses nothing. Stale entries for sessions no run config
   claims any more are removed. Returns the entry count. *)
let rebuild_by_session dir rcs =
  let bd = by_session_dir dir in
  ensure_dir bd;
  let wanted =
    List.filter_map (fun rc ->
      match rc.rc_session with
      | Some s when valid_index_key s -> Some (s, rc.rc_id)
      | _ -> None) rcs in
  (try
     Sys.readdir bd |> Array.iter (fun name ->
       if not (List.mem_assoc name wanted) then
         (try Unix.unlink (Filename.concat bd name) with _ -> ()))
   with _ -> ());
  List.iter (fun (s, run_id) ->
    write_file_atomic (Filename.concat bd s) (run_id ^ "\n")) wanted;
  List.length wanted

let derivations_count dir =
  let dd = derivations_dir_of dir in
  if not (Sys.file_exists dd) then 0
  else (try Array.length (Sys.readdir dd) with _ -> 0)

(* ---------- context resolution (mvp.2) ---------- *)
(* Context is resolved, never carried: session rung first
   (by-session claim), desk rung second (the desk context a
   claim wrote, checked against cwd). Env vars are hints the
   caller cross-checks, never the store. Resolution reads
   only; it never creates the store. *)
let observed_session_id () =
  let first_env names =
    List.fold_left (fun acc n ->
      match acc with Some _ -> acc
      | None -> (match Sys.getenv_opt n with
                 | Some v when v <> "" -> Some v | _ -> None)) None names in
  match first_env ["BP3_SESSION_ID"; "MUSE_SESSION_ID"; "MUSE_THREAD_ID";
                   "PI_SESSION_ID"] with
  | Some _ as v -> v
  | None ->
      (match Sys.getenv_opt "PI_SESSION_FILE" with
       | Some f when f <> "" ->
           let b = Filename.basename f in
           Some (if Filename.check_suffix b ".jsonl"
                 then Filename.remove_extension b else b)
       | _ -> None)

let canon_path p =
  let p = if p <> "/" && Filename.check_suffix p "/" then
      String.sub p 0 (String.length p - 1) else p in
  try Unix.realpath p with _ -> p

(* A stored desk matches cwd when any spelling of it (as
   stored, root-relative, or common-dir-relative) names cwd. *)
let desk_matches desk cwd =
  if desk = "" then false
  else
    let target = canon_path cwd in
    let spellings =
      desk
      :: (if Filename.is_relative desk then
            [Filename.concat root desk;
             (match config_dir () with
              | Some dir -> Filename.concat (Filename.dirname (Filename.dirname dir)) desk
              | None -> desk)]
          else []) in
    List.exists (fun s -> canon_path s = target) spellings

type resolution =
  | Resolved of run_config * string (* run config, source rung: session | desk *)
  | Ambiguous of string list * string (* live run_ids, desk *)
  | No_context

let rec resolve_context () =
  match config_dir () with
  | None -> No_context
  | Some dir ->
      if not (Sys.file_exists dir) then No_context
      else
        let claimed =
          List.filter (fun rc -> rc.rc_state = "claimed")
            (list_run_configs dir) in
        (match observed_session_id () with
         | Some sid ->
             (* one session may claim again over its life;
                the latest claim is its context, matching the
                by-session index the last claim wrote *)
             let mine =
               List.filter (fun rc -> rc.rc_session = Some sid) claimed in
             (match mine with
              | [] -> resolve_desk claimed
              | first :: rest ->
                  let latest = List.fold_left
                    (fun a b ->
                      if (b.rc_claimed_at, b.rc_id) > (a.rc_claimed_at, a.rc_id)
                      then b else a) first rest in
                  Resolved (latest, "session"))
         | None -> resolve_desk claimed)

and resolve_desk claimed =
  let cwd = Sys.getcwd () in
  let at_desk =
    List.filter (fun rc -> desk_matches rc.rc_desk cwd) claimed in
  match at_desk with
  | [rc] -> Resolved (rc, "desk")
  | _ :: _ :: _ ->
      Ambiguous (List.sort String.compare
                   (List.map (fun rc -> rc.rc_id) at_desk), cwd)
  | [] ->
      (* the desk context file a claim wrote into this desk
         corroborates the rung, checked against cwd: a file
         naming a run whose desk is elsewhere resolves
         nothing (no sibling inheritance) *)
      let file = Filename.concat cwd Layout.context_file in
      if not (Sys.file_exists file) then No_context
      else
        (try
           let j = Yojson.Safe.from_string (read_file_or file "") in
           match jopt j "run_id" with
           | Some rid ->
               (match List.find_opt (fun rc -> rc.rc_id = rid) claimed with
                | Some rc when desk_matches rc.rc_desk cwd ->
                    Resolved (rc, "desk")
                | _ -> No_context)
           | None -> No_context
         with _ -> No_context)

let resolved_context_json rc source =
  match context_json rc with
  | `Assoc fs ->
      `Assoc (fs @ [("source", json_str source);
                    ("source_rung", json_str source)])
  | other -> other

(* ---------- the view ---------- *)
let view ~source =
  let dir = ensure_config () in
  let t = load_thresholds dir in
  let rcs = list_run_configs dir in
  let n_by = rebuild_by_session dir rcs in
  let contexts =
    List.map (if source then source_context_json else context_json) rcs in
  `Assoc [("ok", `Bool true); ("config_dir", json_str dir);
          ("mode", json_str (repo_mode ()));
          ("thresholds", thresholds_json t);
          ("contexts", `List contexts);
          ("desks", `List (desks_json rcs));
          ("by_session_entries", `Int n_by);
          ("derivations", `Int (derivations_count dir))]
