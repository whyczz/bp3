(* worktree — low-level git worktree primitives for bp3.
   The util layer only: derive a worktree path from
   (quest, exp, run-id), create a worktree on a branch or
   detached at a commit, inspect its ref and dirty state,
   and remove it. No registry, no override, no staleness
   policy, no workflow behavior. The dirty refusal lives in
   the remove primitive itself, so no caller can forget it. *)
open Gitx

(* ---------- derivation (pure) ---------- *)
let has_dotdot s =
  let n = String.length s in
  let rec loop i = i + 1 < n && ((s.[i] = '.' && s.[i + 1] = '.') || loop (i + 1)) in
  loop 0

(* A run id names one path component under .bp3/worktrees/.
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

let derive_path quest exp run_id =
  Store.check_slug quest;
  Store.check_slug exp;
  if not (valid_run_id run_id) then usage ("invalid run id: " ^ run_id);
  ".bp3/worktrees/" ^ quest ^ "/" ^ exp ^ "/" ^ run_id

(* ---------- git in a worktree ---------- *)
let abs_path p =
  if Filename.is_relative p then Filename.concat root p else p

let canon p = try Unix.realpath p with _ -> p

let git_in dir args = run_capture ("git" :: "-C" :: dir :: args)

let strip_prefix p s =
  let n = String.length p in
  if String.length s >= n && String.sub s 0 n = p
  then Some (String.sub s n (String.length s - n)) else None

(* Branches checked out in any worktree, the main one included. *)
let checked_out_branches () =
  let out, code = git_out ["worktree"; "list"; "--porcelain"] in
  if code <> 0 then []
  else List.filter_map (fun ln ->
    match strip_prefix "branch " ln with
    | Some r -> (match strip_prefix "refs/heads/" r with Some b -> Some b | None -> Some r)
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
    err "E_NOT_FOUND" (`Assoc [("worktree", json_str path)])
      "Path is not a git worktree." 2;
  if canon top <> canon abs then
    err "E_NOT_FOUND" (`Assoc [("worktree", json_str path)])
      "Path is not a worktree root." 2;
  let br, bcode = git_in abs ["symbolic-ref"; "--quiet"; "--short"; "HEAD"] in
  let (ref_, detached) =
    if bcode = 0 && br <> "" then (br, false)
    else
      let sha, scode = git_in abs ["rev-parse"; "HEAD"] in
      if scode <> 0 || sha = "" then
        err "E_NOT_FOUND" (`Assoc [("worktree", json_str path)])
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
let rec mkdir_p dir =
  if dir = "" || dir = "." || Sys.file_exists dir then ()
  else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

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
    err "E_EXISTS" (`Assoc [("path", json_str path)])
      "Worktree path already exists." 1;
  let args = match branch, commit with
    | Some b, None ->
        if not (valid_branch b) then usage ("invalid branch: " ^ b);
        if List.mem b (checked_out_branches ()) then
          err "E_BRANCH_CHECKED_OUT" (`Assoc [("branch", json_str b)])
            "Branch is already checked out in another worktree." 1;
        (match ref_tip ("refs/heads/" ^ b) with
         | Some _ -> ["worktree"; "add"; abs; b]
         | None -> ["worktree"; "add"; "-b"; b; abs])
    | None, Some c ->
        let full = match resolve_commit c with
          | Some f -> f | None -> not_found "commit" c in
        ["worktree"; "add"; "--detach"; abs; full]
    | _ -> usage "worktree create needs exactly one of --branch or --commit" in
  mkdir_p (Filename.dirname abs);
  if run_status (git args) <> 0 then
    (match branch with
     | Some b when List.mem b (checked_out_branches ()) ->
         err "E_BRANCH_CHECKED_OUT" (`Assoc [("branch", json_str b)])
           "Branch is already checked out in another worktree." 1
     | _ ->
         err "E_WORKTREE" (`Assoc [("path", json_str path)])
           "git worktree add failed; check the path and ref and retry." 1);
  inspect_json (inspect_info path)

(* ---------- remove: the dirty refusal lives here ---------- *)
let do_remove path force =
  let info = inspect_info path in
  if info.idirty && not force then
    err "E_DIRTY_TREE"
      (`Assoc [("path", json_str path); ("changed_count", `Int info.ichanged)])
      "Worktree is dirty; commit the work or remove with --force." 1;
  let abs = abs_path path in
  let top_root, _ = git_out ["rev-parse"; "--show-toplevel"] in
  if top_root <> "" && canon top_root = canon abs then
    err "E_MAIN_WORKTREE" (`Assoc [("path", json_str path)])
      "Refusing to remove the main worktree." 1;
  let args = ["worktree"; "remove"] @ (if force then ["--force"] else []) @ [abs] in
  if run_status (git args) <> 0 then
    (let again = inspect_info path in
     if again.idirty && not force then
       err "E_DIRTY_TREE"
         (`Assoc [("path", json_str path); ("changed_count", `Int again.ichanged)])
         "Worktree is dirty; commit the work or remove with --force." 1
     else
       err "E_WORKTREE" (`Assoc [("path", json_str path)])
         "git worktree remove failed; inspect the worktree and retry." 1);
  `Assoc [("ok", `Bool true); ("path", json_str path); ("removed", `Bool true)]

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

let run = function
  | "derive" :: [quest; exp; run_id] ->
      `Assoc [("ok", `Bool true); ("path", json_str (derive_path quest exp run_id))]
  | "derive" :: _ -> usage "worktree derive needs <quest> <exp> <run-id>"
  | "create" :: path :: rest ->
      let (branch, commit) = parse_create_flags rest in
      do_create path branch commit
  | ["create"] -> usage "worktree create needs a path and --branch or --commit"
  | "inspect" :: [path] -> inspect_json (inspect_info path)
  | "inspect" :: _ -> usage "worktree inspect needs exactly one path"
  | "remove" :: path :: rest -> do_remove path (parse_force rest)
  | ["remove"] -> usage "worktree remove needs a path"
  | verb :: _ -> usage ("unknown worktree verb: " ^ verb)
  | [] -> usage "worktree needs a verb: derive, create, inspect, or remove"
