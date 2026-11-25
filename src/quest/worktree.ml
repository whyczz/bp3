(* worktree — git worktree layers for bp3.
   Util layer: derive a central worktree path under
   $BP3_DESKS_DIR (~/.bp3/desks)/<repo>-<hash8>/{quests,runs},
   create a worktree on a branch or detached at a commit,
   inspect its ref and dirty state, and remove it.
   The dirty refusal lives in the remove primitive itself,
   so no caller can forget it.
   Bookkeeping layer: a machine-local registry under
   <repo_desks_dir>/.meta/ keyed by run_id (with read+release
   fallback to legacy <main_root>/.bp3/desks/), composed into
   prepare/check/exit/release/list. Dirty and stale stay
   derived, never stored. *)
open Gitx

(* ---------- canonical repo & central desk paths ---------- *)
let canon p = try Unix.realpath p with _ -> p

let main_root () =
  match git_common_dir () with
  | Some common ->
      let c = canon common in
      if Filename.basename c = ".git" then canon (Filename.dirname c)
      else canon root
  | None -> canon root

let desks_base () =
  Layout.desks_base_of
    (Sys.getenv_opt Layout.desks_env_var)
    (Sys.getenv_opt "HOME")

let repo_desks_dir () =
  let common = match git_common_dir () with
    | Some c -> canon c
    | None -> canon root in
  let mr = main_root () in
  let key = Layout.repo_key (Filename.basename mr) common in
  Layout.repo_desks_dir (desks_base ()) key

(* ---------- derivation ---------- *)
let has_dotdot s =
  let n = String.length s in
  let rec loop i = i + 1 < n && ((s.[i] = '.' && s.[i + 1] = '.') || loop (i + 1)) in
  loop 0

(* A run id names one path component under <repo_desks_dir>/runs/.
   It may carry timestamps and dots, but never a separator,
   never a leading dot or dash, and never "..": a derived
   path cannot escape the worktree root by construction. *)
let valid_run_id s =
  let n = String.length s in
  n >= 1 && s <> "." && s <> ".." && not (has_dotdot s) &&
  (let ok c =
     (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
     || (c >= '0' && c <= '9') || c = '-' || c = '_' || c = '.' in
   let rec loop i = i >= n || (ok s.[i] && loop (i + 1)) in
   s.[0] <> '.' && s.[0] <> '-' && loop 0)

let derive_path quest node run_id =
  Store.check_slug quest;
  Store.check_slug node;
  if not (valid_run_id run_id) then usage ("invalid run id: " ^ run_id);
  Layout.run_desk_dir (repo_desks_dir ()) quest node run_id

(* ---------- git in a worktree ---------- *)
let abs_path p =
  if Filename.is_relative p then Filename.concat (main_root ()) p else p

let git_in dir args = run_capture ("git" :: "-C" :: dir :: args)

(* Branches checked out in any worktree, the main one included. *)
let checked_out_branches () =
  let out, code = git_out ["worktree"; "list"; "--porcelain"] in
  if code <> 0 then []
  else List.filter_map (fun ln ->
    match Util.strip_prefix ~prefix:"branch " ln with
    | Some r -> (match Util.strip_prefix ~prefix:"refs/heads/" r with Some b -> Some b | None -> Some r)
    | None -> None)
    (String.split_on_char '\n' out)

(* ---------- inspect ---------- *)
type inspection = {
  ipath : string; iref : string; idetached : bool;
  idirty : bool; ichanged : int;
}

let inspect_info path =
  let abs = abs_path path in
  if not (Sys.file_exists abs) then not_found "worktree" path;
  let top, code = git_in abs ["rev-parse"; "--show-toplevel"] in
  if code <> 0 || top = "" then
    err Names.e_not_found (`Assoc [("worktree", json_str path)])
      "Path is not a git worktree." 2;
  if canon top <> canon abs then
    err Names.e_not_found (`Assoc [("worktree", json_str path)])
      "Path is not a worktree root." 2;
  let br, bcode = git_in abs ["symbolic-ref"; "--quiet"; "--short"; "HEAD"] in
  let (ref_, detached) =
    if bcode = 0 && br <> "" then (br, false)
    else
      let sha, scode = git_in abs ["rev-parse"; "HEAD"] in
      if scode <> 0 || sha = "" then
        err Names.e_not_found (`Assoc [("worktree", json_str path)])
          "Worktree has no readable HEAD." 2;
      (sha, true) in
  let status, _ = git_in abs ["status"; "--porcelain"] in
  let lines = List.filter (fun l -> String.trim l <> "")
    (String.split_on_char '\n' status) in
  { ipath = path; iref = ref_; idetached = detached;
    idirty = lines <> []; ichanged = List.length lines }

let inspect_json i =
  `Assoc [("ok", `Bool true); ("path", json_str i.ipath);
          ("ref", json_str i.iref); ("detached", `Bool i.idetached);
          ("dirty", `Bool i.idirty); ("changed_count", `Int i.ichanged)]

(* ---------- create ---------- *)
let valid_branch b =
  let n = String.length b in
  n >= 1 && b.[0] <> '-' && not (has_dotdot b) &&
  (let rec loop i =
     i >= n || (let c = b.[i] in c <> ' ' && c <> '\t' && c <> '\n' && loop (i + 1)) in
   loop 0)

let do_create path branch commit =
  (match branch, commit with
   | Some _, Some _ | None, None ->
       usage "worktree create needs exactly one of --branch or --commit"
   | _ -> ());
  let abs = abs_path path in
  if Sys.file_exists abs then
    err Names.e_exists (`Assoc [("path", json_str path)])
      "Worktree path already exists." 1;
  let args = match branch, commit with
    | Some b, None ->
        if not (valid_branch b) then usage ("invalid branch: " ^ b);
        if List.mem b (checked_out_branches ()) then
          err Names.e_branch_checked_out (`Assoc [("branch", json_str b)])
            "Branch is already checked out in another worktree." 1;
        (match ref_tip ("refs/heads/" ^ b) with
         | Some _ -> ["worktree"; "add"; abs; b]
         | None -> ["worktree"; "add"; "-b"; b; abs])
    | None, Some c ->
        let full = match resolve_commit c with
          | Some f -> f | None -> not_found "commit" c in
        ["worktree"; "add"; "--detach"; abs; full]
    | _ -> usage "worktree create needs exactly one of --branch or --commit" in
  Util.mkdir_p (Filename.dirname abs);
  if run_status (git args) <> 0 then
    (match branch with
     | Some b when List.mem b (checked_out_branches ()) ->
         err Names.e_branch_checked_out (`Assoc [("branch", json_str b)])
           "Branch is already checked out in another worktree." 1
     | _ ->
         err Names.e_worktree (`Assoc [("path", json_str path)])
           "git worktree add failed; check the path and ref and retry." 1);
  inspect_json (inspect_info path)

(* ---------- remove: the dirty refusal lives here ---------- *)
let do_remove path force =
  let info = inspect_info path in
  if info.idirty && not force then
    err Names.e_dirty_tree
      (`Assoc [("path", json_str path); ("changed_count", `Int info.ichanged)])
      "Worktree is dirty; commit the work or remove with --force." 1;
  let abs = abs_path path in
  let mr = main_root () in
  if mr <> "" && mr = canon abs then
    err Names.e_main_worktree (`Assoc [("path", json_str path)])
      "Refusing to remove the main worktree." 1;
  let args = ["worktree"; "remove"] @ (if force then ["--force"] else []) @ [abs] in
  if run_status ("git" :: "-C" :: mr :: args) <> 0 then
    (let again = inspect_info path in
     if again.idirty && not force then
       err Names.e_dirty_tree
         (`Assoc [("path", json_str path); ("changed_count", `Int again.ichanged)])
         "Worktree is dirty; commit the work or remove with --force." 1
     else
       err Names.e_worktree (`Assoc [("path", json_str path)])
         "git worktree remove failed; inspect the worktree and retry." 1);
  `Assoc [("ok", `Bool true); ("path", json_str path); ("removed", `Bool true)]

(* ---------- bookkeeping: one file per run_id ---------- *)
(* One record per Run, stored as one file per key at
   <repo_desks_dir>/.meta/<run_id>.json: the creation facts that
   cannot be derived (above all the actual path when --path
   overrides the derivation). Created exclusively and
   published by hard link, so parallel writers for distinct
   Run IDs never rewrite each other's records. Dirty and
   stale are never stored; they are recomputed live by
   check/list. Release deletes the file — no tombstone.
   Legacy <main_root>/.bp3/desks/<run_id>.json records are
   read-only fallback on load and unlinked on release; new
   records are never written inside the repo. *)
type record = {
  r_run : string; r_quest : string; r_node : string;
  r_path : string; r_ref : string; r_detached : bool;
  r_created : int;
}

let desks_meta_dir () = Layout.desks_meta_dir (repo_desks_dir ())
let desk_file run_id = Filename.concat (desks_meta_dir ()) (run_id ^ ".json")
let legacy_desks_dir () = Filename.concat (main_root ()) Layout.legacy_desks_meta_dir
let legacy_desk_file run_id = Filename.concat (legacy_desks_dir ()) (run_id ^ ".json")

let record_of_json j =
  match Util.get_str_opt j "run_id" with
  | None -> None
  | Some run ->
      Some { r_run = run;
             r_quest = Util.get_str j "quest" (Util.get_str j "graph" "");
             r_node = Util.get_str j "node" "";
             r_path = Util.get_str j "path" "";
             r_ref = Util.get_str j "ref" "";
             r_detached = Util.get_bool j "detached" false;
             r_created = Util.get_int j "created_ts" 0 }

let load_record_file file =
  if not (Sys.file_exists file) then None
  else
    try record_of_json (Yojson.Safe.from_string (read_file_or file ""))
    with _ -> None

let load_record run_id =
  if not (valid_run_id run_id) then None
  else
    match load_record_file (desk_file run_id) with
    | Some r -> Some r
    | None -> load_record_file (legacy_desk_file run_id)

let json_run_ids_in dir =
  if not (Sys.file_exists dir) then []
  else
    try
      Sys.readdir dir |> Array.to_list
      |> List.filter_map (fun name ->
           let n = String.length name in
           if n > 5 && String.sub name (n - 5) 5 = ".json" then
             Some (String.sub name 0 (n - 5))
           else None)
    with _ -> []

let load_records () =
  let seen = Hashtbl.create 16 in
  let add_from dir =
    List.iter (fun run_id ->
      if valid_run_id run_id && not (Hashtbl.mem seen run_id) then
        match load_record_file (Filename.concat dir (run_id ^ ".json")) with
        | Some r -> Hashtbl.replace seen run_id r
        | None -> ())
      (json_run_ids_in dir) in
  add_from (desks_meta_dir ());
  add_from (legacy_desks_dir ());
  Hashtbl.fold (fun _ r acc -> r :: acc) seen []
  |> List.sort (fun a b -> String.compare a.r_run b.r_run)

(* Publish one record exclusively: write a per-process temp
   file in the same directory, then hard-link it to the
   final name. The link fails if the key already exists, so
   no writer ever clobbers another Run's record. *)
let save_record r =
  let dir = desks_meta_dir () in
  Util.mkdir_p dir;
  let final = desk_file r.r_run in
  let tmp = Filename.concat dir
      (Printf.sprintf ".%s.%d.tmp" r.r_run (Unix.getpid ())) in
  let json = `Assoc [("run_id", json_str r.r_run);
                     ("quest", json_str r.r_quest);
                     ("node", json_str r.r_node);
                     ("path", json_str r.r_path);
                     ("ref", json_str r.r_ref);
                     ("detached", `Bool r.r_detached);
                     ("created_ts", `Int r.r_created)] in
  let oc = open_out_bin tmp in
  output_string oc (Yojson.Safe.to_string json);
  close_out oc;
  try Unix.link tmp final; Unix.unlink tmp; true
  with Unix.Unix_error (Unix.EEXIST, _, _) ->
    (try Unix.unlink tmp with _ -> ()); false

let delete_record run_id =
  (try Unix.unlink (desk_file run_id) with _ -> ());
  (try Unix.unlink (legacy_desk_file run_id) with _ -> ())

let now_s () = int_of_float (Clock.time ())
let stale_s r = max 0 (now_s () - r.r_created)

let record_json r =
  [("run_id", json_str r.r_run); ("quest", json_str r.r_quest);
   ("node", json_str r.r_node); ("path", json_str r.r_path);
   ("ref", json_str r.r_ref); ("detached", `Bool r.r_detached);
   ("created_ts", `Int r.r_created)]

let live_json r =
  let base = record_json r in
  if not (Sys.file_exists (abs_path r.r_path)) then
    base @ [("missing", `Bool true); ("orphan", `Bool false)]
  else
    (try
       let i = inspect_info r.r_path in
       let base = List.filter (fun (k, _) -> k <> "ref" && k <> "detached") base in
       base @ [("ref", json_str i.iref); ("detached", `Bool i.idetached);
               ("dirty", `Bool i.idirty); ("changed_count", `Int i.ichanged);
               ("stale_s", `Int (stale_s r)); ("missing", `Bool false);
               ("orphan", `Bool false)]
     with Verdict _ ->
       base @ [("missing", `Bool true); ("orphan", `Bool false)])

let prepare_verdict r existing =
  let fields = [("ok", `Bool true)] @ record_json r in
  `Assoc (if existing then fields @ [("existing", `Bool true)] else fields)

let do_prepare quest node run_id commit path_override =
  Store.check_creatable quest;
  Store.check_creatable node;
  let default_path = derive_path quest node run_id in
  match load_record run_id with
  | Some r ->
      if Sys.file_exists (abs_path r.r_path) then prepare_verdict r true
      else begin
        (* record outlived its worktree: rebuild it in place *)
        let _ = if r.r_detached then do_create r.r_path None (Some r.r_ref)
                else do_create r.r_path (Some r.r_ref) None in
        prepare_verdict r true
      end
  | None ->
      let path = match path_override with Some p -> p | None -> default_path in
      let branch = Layout.node_branch_short quest (Store.canon_node_id node) in
      let _ = (match commit with
               | Some c -> do_create path None (Some c)
               | None -> do_create path (Some branch) None) in
      let i = inspect_info path in
      let r = { r_run = run_id; r_quest = quest; r_node = node; r_path = path;
                r_ref = i.iref; r_detached = i.idetached;
                r_created = now_s () } in
      if save_record r then prepare_verdict r false
      else (match load_record run_id with
            | Some existing -> prepare_verdict existing true
            | None -> prepare_verdict r false)

(* Node 8: one worktree per quest for a whole induct.
   Record key is quest-<quest>; node field is "(quest)". *)
let quest_run_id quest = "quest-" ^ quest

let do_prepare_quest quest =
  Store.check_creatable quest;
  let run_id = quest_run_id quest in
  match load_record run_id with
  | Some r ->
      if Sys.file_exists (abs_path r.r_path) then prepare_verdict r true
      else begin
        let _ = do_create r.r_path (Some r.r_ref) None in
        prepare_verdict r true
      end
  | None ->
      let path = Layout.quest_desk_dir (repo_desks_dir ()) quest in
      let branch = Layout.work_branch quest in
      let _ = do_create path (Some branch) None in
      let i = inspect_info path in
      let r = { r_run = run_id; r_quest = quest; r_node = "(quest)";
                r_path = path; r_ref = i.iref; r_detached = i.idetached;
                r_created = now_s () } in
      if save_record r then prepare_verdict r false
      else (match load_record run_id with
            | Some existing -> prepare_verdict existing true
            | None -> prepare_verdict r false)

let do_check run_id =
  let r = match load_record run_id with
    | Some r -> r | None -> not_found "run" run_id in
  if not (Sys.file_exists (abs_path r.r_path)) then
    err Names.e_not_found
      (`Assoc [("run_id", json_str run_id); ("path", json_str r.r_path)])
      "Recorded worktree is missing on disk." 2;
  let i = inspect_info r.r_path in
  let stored = List.filter (fun (k, _) -> k <> "ref" && k <> "detached")
    (record_json r) in
  `Assoc ([("ok", `Bool true)] @ stored @
          [("ref", json_str i.iref); ("detached", `Bool i.idetached);
           ("dirty", `Bool i.idirty); ("changed_count", `Int i.ichanged);
           ("stale_s", `Int (stale_s r))])

let release_record r force =
  if Sys.file_exists (abs_path r.r_path) then begin
    let _ = do_remove r.r_path force in
    delete_record r.r_run;
    `Assoc ([("ok", `Bool true); ("released", `Bool true);
             ("removed", `Bool true)] @ record_json r)
  end else begin
    delete_record r.r_run;
    `Assoc ([("ok", `Bool true); ("released", `Bool true);
             ("removed", `Bool false); ("missing", `Bool true)]
            @ record_json r)
  end

let do_release_quest quest =
  Store.check_slug quest;
  let run_id = quest_run_id quest in
  let r = match load_record run_id with
    | Some r -> r | None -> not_found "quest worktree" quest in
  release_record r false

let do_release run_id force =
  let r = match load_record run_id with
    | Some r -> r | None -> not_found "run" run_id in
  release_record r force

let do_exit force =
  let cwd = canon (Sys.getcwd ()) in
  let records = load_records () in
  let inside r =
    let p = canon (abs_path r.r_path) in
    cwd = p || (String.length cwd > String.length p
                && String.sub cwd 0 (String.length p + 1) = p ^ "/") in
  match List.find_opt inside records with
  | None ->
      err Names.e_not_found (`Assoc [("cwd", json_str cwd)])
        "Current directory is not inside a registered worktree." 2
  | Some r ->
      let v = release_record r force in
      (match v with
       | `Assoc fs ->
           `Assoc ((List.filter (fun (k, _) -> k <> "ok") fs)
                   @ [("ok", `Bool true);
                      ("conductor_path", json_str (main_root ()))])
       | other -> other)

(* Orphans: worktrees under the repo's central desk dir (or legacy
   .bp3/worktrees/) with no record. Quest/node/run are read back
   from the derived path. *)
let build_orphan ~run_id ~quest ~node ~shown ~inspect_target =
  let live =
    (try
       let i = inspect_info inspect_target in
       [("ref", json_str i.iref); ("detached", `Bool i.idetached);
        ("dirty", `Bool i.idirty); ("changed_count", `Int i.ichanged)]
     with Verdict _ -> [("missing", `Bool true)]) in
  Some (quest, `Assoc ([("run_id", json_str run_id); ("quest", json_str quest);
                        ("node", json_str node); ("path", json_str shown);
                        ("orphan", `Bool true); ("missing", `Bool false);
                        ("stale_s", `Int 0)] @ live))

let orphan_entry abs =
  let c_abs = canon abs in
  let repo_dir = repo_desks_dir () in
  let c_repo_dir = canon repo_dir in
  match Util.strip_prefix ~prefix:(c_repo_dir ^ "/") c_abs with
  | Some rel ->
      (match String.split_on_char '/' rel with
       | [sub; q; e; r] when sub = Layout.runs_desks_subdir ->
           let shown = Layout.run_desk_dir repo_dir q e r in
           build_orphan ~run_id:r ~quest:q ~node:e ~shown ~inspect_target:abs
       | [sub; q] when sub = Layout.quests_desks_subdir ->
           let shown = Layout.quest_desk_dir repo_dir q in
           build_orphan ~run_id:(quest_run_id q) ~quest:q ~node:"(quest)"
             ~shown ~inspect_target:abs
       | _ -> None)
  | None ->
      let legacy_prefix = main_root () ^ "/" ^ Layout.legacy_desks_root ^ "/" in
      (match Util.strip_prefix ~prefix:legacy_prefix c_abs with
       | Some rel ->
           (match String.split_on_char '/' rel with
            | [q; e; r] ->
                let shown = String.concat "/" [Layout.legacy_desks_root; q; e; r] in
                build_orphan ~run_id:r ~quest:q ~node:e ~shown ~inspect_target:abs
            | [q] ->
                let shown = Layout.legacy_desks_root ^ "/" ^ q in
                build_orphan ~run_id:(quest_run_id q) ~quest:q ~node:"(quest)"
                  ~shown ~inspect_target:abs
            | _ -> None)
       | None -> None)

let do_list quest_filter =
  let records = load_records () in
  let shown_records = List.filter
    (fun r -> match quest_filter with None -> true | Some q -> r.r_quest = q)
    records in
  let recorded = List.map (fun r -> canon (abs_path r.r_path)) records in
  let wt_paths =
    let out, code = git_out ["worktree"; "list"; "--porcelain"] in
    if code <> 0 then []
    else List.filter_map (fun ln -> Util.strip_prefix ~prefix:"worktree " ln)
           (String.split_on_char '\n' out) in
  let orphans = List.filter_map (fun p ->
    if List.mem (canon p) recorded then None
    else match orphan_entry p with
      | Some (q, j) ->
          (match quest_filter with
           | Some f when f <> q -> None | _ -> Some j)
      | None -> None) wt_paths in
  `Assoc [("ok", `Bool true);
          ("worktrees", `List (List.map (fun r -> `Assoc (live_json r))
                                 shown_records @ orphans))]

(* ---------- dispatch ---------- *)
let parse_create_flags args =
  let rec loop branch commit = function
    | [] -> (branch, commit)
    | "--branch" :: v :: rest ->
        if branch <> None then usage "duplicate flag --branch";
        loop (Some v) commit rest
    | "--commit" :: v :: rest ->
        if commit <> None then usage "duplicate flag --commit";
        loop branch (Some v) rest
    | ["--branch"] | ["--commit"] -> usage "flag needs a value"
    | f :: _ -> usage ("unknown flag: " ^ f) in
  loop None None args

let parse_force args =
  let rec loop force = function
    | [] -> force
    | "--force" :: rest ->
        if force then usage "duplicate flag --force";
        loop true rest
    | f :: _ -> usage ("unknown flag: " ^ f) in
  loop false args

(* Bookkeeping verbs address worktrees by Run ID only;
   a raw path is never their primary input. --run and a
   single positional Run ID are the same handle. *)
let parse_run_flag args =
  let rec loop run force = function
    | [] -> (run, force)
    | "--run" :: v :: rest ->
        if run <> None then usage "duplicate flag --run";
        loop (Some v) force rest
    | "--force" :: rest ->
        if force then usage "duplicate flag --force";
        loop run true rest
    | ["--run"] -> usage "--run needs a value"
    | v :: rest when String.length v < 2 || v.[0] <> '-' ->
        if run <> None then usage "worktree verb takes one Run ID";
        loop (Some v) force rest
    | f :: _ -> usage ("unknown flag: " ^ f) in
  loop None false args

let parse_prepare_flags args =
  let rec loop run commit path = function
    | [] -> (run, commit, path)
    | "--run" :: v :: rest ->
        if run <> None then usage "duplicate flag --run";
        loop (Some v) commit path rest
    | "--commit" :: v :: rest ->
        if commit <> None then usage "duplicate flag --commit";
        loop run (Some v) path rest
    | "--path" :: v :: rest ->
        if path <> None then usage "duplicate flag --path";
        loop run commit (Some v) rest
    | ["--run"] | ["--commit"] | ["--path"] -> usage "flag needs a value"
    | v :: rest when String.length v < 2 || v.[0] <> '-' ->
        if run <> None then usage "worktree prepare takes one Run ID";
        loop (Some v) commit path rest
    | f :: _ -> usage ("unknown flag: " ^ f) in
  loop None None None args

let parse_quest_flag args =
  let rec loop quest = function
    | [] -> quest
    | "--quest" :: v :: rest ->
        if quest <> None then usage "duplicate flag --quest";
        loop (Some v) rest
    | ["--quest"] -> usage "--quest needs a value"
    | f :: _ -> usage ("unknown flag: " ^ f) in
  loop None args

let run = function
  | "prepare" :: "--quest" :: [quest] -> do_prepare_quest quest
  | "release" :: "--quest" :: [quest] -> do_release_quest quest
  | "prepare" :: quest :: node :: rest ->
      let (run_id, commit, path) = parse_prepare_flags rest in
      let run_id = (match run_id with
        | Some r -> r | None -> usage "worktree prepare needs --run <run-id>") in
      do_prepare quest node run_id commit path
  | "prepare" :: _ -> usage "worktree prepare needs <quest> <node> --run <run-id>"
  | "check" :: rest ->
      let (run_id, _) = parse_run_flag rest in
      let run_id = (match run_id with
        | Some r -> r | None -> usage "worktree check needs --run <run-id>") in
      do_check run_id
  | "release" :: rest ->
      let (run_id, force) = parse_run_flag rest in
      let run_id = (match run_id with
        | Some r -> r | None -> usage "worktree release needs --run <run-id>") in
      do_release run_id force
  | "exit" :: rest -> do_exit (parse_force rest)
  | "list" :: rest -> do_list (parse_quest_flag rest)
  | "derive" :: [quest; node; run_id] ->
      `Assoc [("ok", `Bool true); ("path", json_str (derive_path quest node run_id))]
  | "derive" :: _ -> usage "worktree derive needs <quest> <node> <run-id>"
  | "create" :: path :: rest ->
      let (branch, commit) = parse_create_flags rest in
      do_create path branch commit
  | ["create"] -> usage "worktree create needs a path and --branch or --commit"
  | "inspect" :: [path] -> inspect_json (inspect_info path)
  | "inspect" :: _ -> usage "worktree inspect needs exactly one path"
  | "remove" :: path :: rest -> do_remove path (parse_force rest)
  | ["remove"] -> usage "worktree remove needs a path"
  | verb :: _ -> usage ("unknown worktree verb: " ^ verb)
  | [] -> usage "worktree needs a verb: derive, create, inspect, remove, prepare, check, exit, release, or list"
