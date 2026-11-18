(* gitx — process/git plumbing for bp3 q. No quest knowledge. *)
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

(* env: "KEY=value" overrides for the child only; never putenv. *)
let child_env env =
  let key kv = match String.index_opt kv '=' with
    | Some i -> String.sub kv 0 (i + 1) | None -> kv in
  let keys = List.map key env in
  let inherited = Array.to_list (Unix.environment ())
    |> List.filter (fun kv -> not (List.mem (key kv) keys)) in
  Array.of_list (env @ inherited)

(* Exec args directly (no shell, no temp files). stdout is captured,
   stderr discarded, stdin fed from [input]. Exit codes match the old
   Sys.command path: n on exit, 255 on signal, 127 when exec fails. *)
let run_capture ?(env = []) ?input args =
  let null_out = Unix.openfile "/dev/null" [Unix.O_WRONLY; Unix.O_CLOEXEC] 0 in
  let out_r, out_w = Unix.pipe ~cloexec:true () in
  let in_r, in_w = match input with
    | Some _ -> let r, w = Unix.pipe ~cloexec:true () in (r, Some w)
    | None -> (Unix.openfile "/dev/null" [Unix.O_RDONLY; Unix.O_CLOEXEC] 0, None) in
  let pid =
    try Some (Unix.create_process_env (List.hd args) (Array.of_list args)
                (child_env env) in_r out_w null_out)
    with Unix.Unix_error _ -> None in
  Unix.close in_r; Unix.close out_w; Unix.close null_out;
  (* Inputs are a ledger or a commit message, read whole by the child
     before it writes, so writing all of stdin first cannot deadlock.
     SIGPIPE is ignored only here: a child that exits early yields EPIPE. *)
  (match in_w, input, pid with
   | Some w, Some s, Some _ ->
       let prev = Sys.signal Sys.sigpipe Sys.Signal_ignore in
       let oc = Unix.out_channel_of_descr w in
       (try output_string oc s; flush oc with Sys_error _ -> ());
       close_out_noerr oc;
       Sys.set_signal Sys.sigpipe prev
   | Some w, _, _ -> Unix.close w
   | None, _, _ -> ());
  let ic = Unix.in_channel_of_descr out_r in
  let out = In_channel.input_all ic in
  close_in ic;
  let rec wait p =
    try snd (Unix.waitpid [] p) with Unix.Unix_error (Unix.EINTR, _, _) -> wait p in
  let code = match pid with
    | None -> 127
    | Some p -> (match wait p with Unix.WEXITED n -> n | _ -> 255) in
  (String.trim out, code)

let run_status ?env ?input args = snd (run_capture ?env ?input args)
let git args = "git" :: "-C" :: root :: args
let git_out ?env ?input args = run_capture ?env ?input (git args)
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
  let env = ["GIT_INDEX_FILE=" ^ idx] in
  let cleanup () = try Unix.unlink idx with _ -> () in
  let fail () = cleanup (); err "E_STALE_WORLD" (`Assoc [("branch", json_str branch)])
    "Branch tip moved; re-read and retry." 1 in
  if run_status ~env (git ["read-tree"; base_tip]) <> 0 then fail ();
  List.iter (fun (path, content) ->
    let blob, code = git_out ~input:content ["hash-object"; "-w"; "--stdin"] in
    if code <> 0 then fail ();
    if run_status ~env (git ["update-index"; "--add"; "--cacheinfo";
                             "100644," ^ blob ^ "," ^ path]) <> 0 then fail ()
  ) files;
  let tree, code = git_out ~env ["write-tree"] in
  if code <> 0 then fail ();
  let new_tip, code = git_out ~input:msg ["commit-tree"; tree; "-p"; base_tip] in
  if code <> 0 then fail ();
  cleanup ();
  let code = run_status (git ["update-ref"; branch; new_tip; expect_tip]) in
  if code <> 0 then err "E_STALE_WORLD" (`Assoc [("branch", json_str branch)])
    "Branch tip moved; re-read and retry." 1;
  new_tip

let create_branch_commit ~branch ~base_tip ~files ~msg =
  (* branch must not exist; update-ref with zero old value *)
  commit_files ~branch ~base_tip ~expect_tip:"0000000000000000000000000000000000000000" ~files ~msg

