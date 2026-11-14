(* gitx — shell/git plumbing for bp3 q. No quest knowledge. *)
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

