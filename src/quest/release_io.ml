(* release_io — git/gh I/O door for top-level `bp3 release`:
   - `bp3 release <quest> [flags]`       promote & release a goal_fin quest
   - `bp3 release --commit <sha> [flags]` cut a bugfix release from a commit
   - `bp3 release (<quest> | --tag <v>) --publish-only`  recover GitHub publish
   All pure version/URL/frontmatter/notes logic lives in Release. *)
open Gitx
open Store

type opts = {
  quest : string option;
  commit : string option;
  bump : string option;
  target : string option;
  remote : string;
  reason : string option;
  tag : string option;
  no_gh : bool;
  no_install : bool;
  dry_run : bool;
  publish_only : bool;
  fmt : string;
  help : bool;
}

let help_release =
  "bp3 release - atomic CAS quest promotion and semver release (GitHub Release or annotated git tag):\n\
  \  bp3 release <quest> [--bump major|minor|patch|none] [--target <branch>] [--remote <name>] [--reason <text>] [--no-gh] [--no-install] [--dry-run] [--format json|table]\n\
  \  bp3 release --commit <sha> [--bump patch|minor|major] [--target <branch>] [--remote <name>] [--reason <text>] [--no-gh] [--no-install] [--dry-run] [--format json|table]\n\
  \  bp3 release (<quest> | --tag <vX.Y.Z>) --publish-only [--target <branch>] [--remote <name>] [--format json|table]\n\
  Requires BP3_DECIDER=human for any real release (--dry-run is read-only).\n\
  Example: BP3_DECIDER=human bp3 release 2026-11-23-quest-promote-release\n"

let parse_args args =
  let init = {
    quest = None; commit = None; bump = None; target = None;
    remote = "origin"; reason = None; tag = None;
    no_gh = false; no_install = false; dry_run = false; publish_only = false;
    fmt = "json"; help = false;
  } in
  let seen_remote = ref false and seen_fmt = ref false in
  let rec loop acc = function
    | [] -> acc
    | ("-h" | "--help") :: _ -> { acc with help = true }
    | "--commit" :: v :: rest ->
        if acc.commit <> None then usage "duplicate flag --commit";
        loop { acc with commit = Some v } rest
    | "--bump" :: v :: rest ->
        if acc.bump <> None then usage "duplicate flag --bump";
        loop { acc with bump = Some v } rest
    | "--target" :: v :: rest ->
        if acc.target <> None then usage "duplicate flag --target";
        loop { acc with target = Some v } rest
    | "--remote" :: v :: rest ->
        if !seen_remote then usage "duplicate flag --remote";
        seen_remote := true;
        loop { acc with remote = v } rest
    | "--reason" :: v :: rest ->
        if acc.reason <> None then usage "duplicate flag --reason";
        loop { acc with reason = Some v } rest
    | "--tag" :: v :: rest ->
        if acc.tag <> None then usage "duplicate flag --tag";
        loop { acc with tag = Some v } rest
    | "--format" :: v :: rest ->
        if !seen_fmt then usage "duplicate flag --format";
        if v <> "json" && v <> "table" then usage "--format must be json or table";
        seen_fmt := true;
        loop { acc with fmt = v } rest
    | "--no-gh" :: rest ->
        if acc.no_gh then usage "duplicate flag --no-gh";
        loop { acc with no_gh = true } rest
    | "--no-install" :: rest ->
        if acc.no_install then usage "duplicate flag --no-install";
        loop { acc with no_install = true } rest
    | "--dry-run" :: rest ->
        if acc.dry_run then usage "duplicate flag --dry-run";
        loop { acc with dry_run = true } rest
    | "--publish-only" :: rest ->
        if acc.publish_only then usage "duplicate flag --publish-only";
        loop { acc with publish_only = true } rest
    | ("--commit" | "--bump" | "--target" | "--remote" | "--reason" | "--tag" | "--format") :: [] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 1 && f.[0] = '-' ->
        usage ("unknown flag: " ^ f)
    | pos :: rest ->
        if acc.quest <> None then usage ("unexpected extra positional: " ^ pos);
        loop { acc with quest = Some pos } rest in
  loop init args

(* Capture both stdout and stderr without going through a shell. *)
let run_capture_both ?(env = []) ?input args =
  let out_r, out_w = Unix.pipe ~cloexec:true () in
  let err_r, err_w = Unix.pipe ~cloexec:true () in
  let in_r, in_w = match input with
    | Some _ -> let r, w = Unix.pipe ~cloexec:true () in (r, Some w)
    | None -> (Unix.openfile "/dev/null" [Unix.O_RDONLY; Unix.O_CLOEXEC] 0, None) in
  let pid =
    try Some (Unix.create_process_env (List.hd args) (Array.of_list args)
                (child_env env) in_r out_w err_w)
    with Unix.Unix_error _ -> None in
  Unix.close in_r; Unix.close out_w; Unix.close err_w;
  (match in_w, input, pid with
   | Some w, Some s, Some _ ->
       let prev = Sys.signal Sys.sigpipe Sys.Signal_ignore in
       let oc = Unix.out_channel_of_descr w in
       (try output_string oc s; flush oc with Sys_error _ -> ());
       close_out_noerr oc;
       Sys.set_signal Sys.sigpipe prev
   | Some w, _, _ -> Unix.close w
   | None, _, _ -> ());
  let ic_out = Unix.in_channel_of_descr out_r in
  let out = In_channel.input_all ic_out in
  close_in ic_out;
  let ic_err = Unix.in_channel_of_descr err_r in
  let err_s = In_channel.input_all ic_err in
  close_in ic_err;
  let rec wait p =
    try snd (Unix.waitpid [] p) with Unix.Unix_error (Unix.EINTR, _, _) -> wait p in
  let code = match pid with
    | None -> 127
    | Some p -> (match wait p with Unix.WEXITED n -> n | _ -> 255) in
  (String.trim out, String.trim err_s, code)

let opt_json = function Some s -> json_str s | None -> `Null

(* Default self-mode tag-gated local $PREFIX install (sync.1).
   Runs only on tagged releases in self mode (never on untagged commits),
   building/installing from install_root (the synced target worktree when
   checked out, else root) so bp3 release works from either master or a desk. *)
let default_self_install ~install_root ~tag ~version ~commit =
  let prefix =
    match Sys.getenv_opt "PREFIX" with
    | Some p when p <> "" -> p
    | _ ->
        let home = match Sys.getenv_opt "HOME" with Some h -> h | None -> "." in
        Filename.concat home ".local" in
  let install_script = Filename.concat install_root "scripts/install-bp3.sh" in
  let env = [ "PREFIX=" ^ prefix ] in
  let fail detail =
    err Names.e_install_failed
      (`Assoc [ ("tag", json_str tag); ("version", json_str version);
                ("commit", json_str commit); ("prefix", json_str prefix);
                ("local_tagged", `Bool true); ("detail", json_str detail) ])
      "Local release tag succeeded, but local install to PREFIX failed; run make release && make install." 1 in
  match Sys.getenv_opt "BP3_RELEASE_ARTIFACT" with
  | Some art when art <> "" ->
      let out, err_s, code =
        run_capture_both ~env [ install_script; art ] in
      if code <> 0 then fail (if err_s <> "" then err_s else out);
      Some prefix
  | _ ->
      let mout, merr, mcode =
        run_capture_both ~env [ "make"; "-C"; install_root; "release" ] in
      if mcode <> 0 then fail (if merr <> "" then merr else mout);
      let iout, ierr, icode =
        run_capture_both ~env [ install_script ] in
      if icode <> 0 then fail (if ierr <> "" then ierr else iout);
      Some prefix

let self_install_hook :
    (install_root:string -> tag:string -> version:string -> commit:string -> string option) ref =
  ref default_self_install

let list_v_tags () =
  let out, code = git_out [ "tag"; "-l"; "v*" ] in
  if code <> 0 || out = "" then []
  else String.split_on_char '\n' out |> List.map String.trim |> List.filter (fun s -> s <> "")

let detect_target_branch = function
  | Some b ->
      if ref_tip ("refs/heads/" ^ b) = None then not_found "branch" b else b
  | None ->
      if ref_tip "refs/heads/master" <> None then "master"
      else if ref_tip "refs/heads/main" <> None then "main"
      else not_found "branch" "master"

let worktrees_on_branch branch_ref =
  let out, code = git_out [ "worktree"; "list"; "--porcelain" ] in
  if code <> 0 || out = "" then []
  else
    let lines = String.split_on_char '\n' out in
    let rec go cur_wt cur_br acc = function
      | [] ->
          (match cur_wt, cur_br with
           | Some p, Some b when b = branch_ref -> List.rev (p :: acc)
           | _ -> List.rev acc)
      | ln :: rest ->
          let t = String.trim ln in
          if t = "" then
            let acc = match cur_wt, cur_br with
              | Some p, Some b when b = branch_ref -> p :: acc | _ -> acc in
            go None None acc rest
          else if String.length t > 9 && String.sub t 0 9 = "worktree " then
            go (Some (String.sub t 9 (String.length t - 9))) cur_br acc rest
          else if String.length t > 7 && String.sub t 0 7 = "branch " then
            go cur_wt (Some (String.sub t 7 (String.length t - 7))) acc rest
          else go cur_wt cur_br acc rest in
    go None None [] lines

let check_clean_dir dir =
  let out, code = run_capture [ "git"; "-C"; dir; "status"; "--porcelain" ] in
  if code <> 0 || String.trim out <> "" then
    err Names.e_dirty_tree (`Assoc [ ("path", json_str dir) ])
      ("Worktree is dirty (" ^ dir ^ "); commit or clean it before releasing.") 1

let quest_promoted_info text =
  let found = ref None in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        if Util.get_str j "edge" "" = "promote" then
          let tag = get_opt j "tag" in
          let commit = get_opt j "commit" in
          let target = get_opt j "target" in
          found := Some (tag, commit, target)
      with _ -> ());
  !found

let remote_url remote =
  let out, code = git_out [ "remote"; "get-url"; remote ] in
  if code = 0 && out <> "" then
    match Release.parse_github_repo out with
    | Some _ -> Some out
    | None ->
        let raw, rcode = git_out [ "config"; "--get"; "remote." ^ remote ^ ".url" ] in
        if rcode = 0 && raw <> "" then Some raw else Some out
  else None

let commit_subject sha =
  let out, code = git_out [ "show"; "-s"; "--format=%s"; sha ] in
  if code = 0 then out else ""

let commit_body sha =
  let out, code = git_out [ "show"; "-s"; "--format=%b"; sha ] in
  if code = 0 then out else ""

let commits_since prev_tag source_tip =
  let range = match prev_tag with
    | Some t -> t ^ ".." ^ source_tip
    | None -> source_tip in
  let out, code = git_out [ "log"; "--no-merges"; "-n"; "30"; "--format=%s (%h)"; range ] in
  if code <> 0 || out = "" then []
  else String.split_on_char '\n' out |> List.map String.trim |> List.filter (fun s -> s <> "")

let plumbing_commit ~base_tip ~files ~msg =
  !Gitx.write_guard ();
  let idx = tmp_path "rel-index" in
  let env = [ "GIT_INDEX_FILE=" ^ idx ] in
  let cleanup () = try Unix.unlink idx with _ -> () in
  let fail detail =
    cleanup ();
    err Names.e_stale_world (`Assoc [ ("detail", json_str detail) ])
      "Failed to assemble release commit in plumbing." 1 in
  if run_status ~env (git [ "read-tree"; base_tip ]) <> 0 then fail "read-tree";
  List.iter (fun (path, content) ->
    let blob, code = git_out ~input:content [ "hash-object"; "-w"; "--stdin" ] in
    if code <> 0 || blob = "" then fail ("hash-object " ^ path);
    if run_status ~env (git [ "update-index"; "--add"; "--cacheinfo";
                              "100644," ^ blob ^ "," ^ path ]) <> 0 then
      fail ("update-index " ^ path)
  ) files;
  let tree, code = git_out ~env [ "write-tree" ] in
  if code <> 0 || tree = "" then fail "write-tree";
  let new_tip, code = git_out ~input:msg [ "commit-tree"; tree; "-p"; base_tip ] in
  cleanup ();
  if code <> 0 || new_tip = "" then fail "commit-tree";
  new_tip

let plumbing_mktag ~commit ~tag ~message =
  let name =
    let s, c = git_out [ "config"; "user.name" ] in
    if c = 0 && s <> "" then s else "bp3" in
  let email =
    let s, c = git_out [ "config"; "user.email" ] in
    if c = 0 && s <> "" then s else "bp3@local" in
  let epoch = int_of_float (Clock.time ()) in
  let payload =
    Printf.sprintf "object %s\ntype commit\ntag %s\ntagger %s <%s> %d +0000\n\n%s"
      commit tag name email epoch message in
  let out, err_s, code = run_capture_both ~input:payload (git [ "mktag" ]) in
  if code <> 0 || out = "" then
    err Names.e_stale_world (`Assoc [ ("tag", json_str tag); ("detail", json_str err_s) ])
      "Failed to create annotated tag object via git mktag." 1;
  out

let atomic_cas_update ~target ~new_tip ~old_target_tip ~tag_opt ~tag_obj_opt =
  !Gitx.write_guard ();
  let buf = Buffer.create 256 in
  Buffer.add_string buf "start\n";
  Printf.bprintf buf "update refs/heads/%s %s %s\n" target new_tip old_target_tip;
  (match tag_opt, tag_obj_opt with
   | Some t, Some obj -> Printf.bprintf buf "create refs/tags/%s %s\n" t obj
   | _ -> ());
  Buffer.add_string buf "commit\n";
  let _out, err_s, code =
    run_capture_both ~input:(Buffer.contents buf) (git [ "update-ref"; "--stdin" ]) in
  if code <> 0 then
    err Names.e_stale_world
      (`Assoc [ ("target", json_str target); ("tag", opt_json tag_opt);
                ("detail", json_str err_s) ])
      "Target branch moved or release tag already exists; re-read and retry." 1;
  invalidate_ref_caches ()

let sync_clean_worktrees wts =
  List.iter (fun wt ->
    ignore (run_status [ "git"; "-C"; wt; "reset"; "--hard"; "--quiet"; "HEAD" ])
  ) wts

let append_quest_promote_line ~quest ~from_st ~commit ~tag ~bump_str ~target
    ~release_kind ~reason ~id =
  match ledger_read (quest_branch quest) (quest_ledger_path quest) (legacy_quest_ledger_paths quest) with
  | None -> not_found "quest" quest
  | Some (tip, text, lpath) ->
      let line =
        ledger_line ~edge:"promote" ~from:from_st ~to_:"landed" ~cycle:1
          ~commit:(Some commit) ~verdict:None ~reason ~id
          ~extra:[ ("tag", opt_json tag);
                   ("bump", json_str bump_str);
                   ("target", json_str target);
                   ("release_kind", json_str release_kind) ] () in
      let new_text =
        (if String.trim text = "" then "" else
           if text.[String.length text - 1] = '\n' then text else text ^ "\n")
        ^ line ^ "\n" in
      ignore (commit_files ~branch:(quest_branch quest) ~base_tip:tip ~expect_tip:tip
        ~files:[ (lpath, new_text) ] ~msg:("bp3: promote quest " ^ quest))

let push_and_create_gh_release ~remote ~target ~tag ~repo ~title ~body ~commit =
  let _pout, perr, pcode =
    run_capture_both (git [ "push"; remote; "refs/heads/" ^ target; "refs/tags/" ^ tag ]) in
  if pcode <> 0 then
    err Names.e_remote_rejected
      (`Assoc [ ("remote", json_str remote); ("target", json_str target);
                ("tag", json_str tag); ("commit", json_str commit);
                ("local_tagged", `Bool true); ("detail", json_str perr) ])
      "Local tag succeeded, but non-force git push was rejected. Reconcile remote and re-run with --publish-only." 1;
  if run_status [ "gh"; "release"; "view"; tag; "--repo"; repo ] = 0 then
    err Names.e_release_exists
      (`Assoc [ ("tag", json_str tag); ("repo", json_str repo);
                ("local_tagged", `Bool true) ])
      ("GitHub Release " ^ tag ^ " already exists on " ^ repo ^ "; refusing to overwrite.") 1;
  let gout, gerr, gcode =
    run_capture_both [ "gh"; "release"; "create"; tag; "--repo"; repo;
                       "--title"; title; "--notes"; body ] in
  if gcode <> 0 then
    err Names.e_gh_failed
      (`Assoc [ ("tag", json_str tag); ("repo", json_str repo);
                ("commit", json_str commit); ("local_tagged", `Bool true);
                ("detail", json_str (if gerr <> "" then gerr else gout)) ])
      "Local tag succeeded, but gh release create failed. Fix gh auth/network and re-run with --publish-only." 1;
  if gout <> "" then Some gout else None

let title_from_tag_body tag body =
  let lines = String.split_on_char '\n' body in
  let rec go = function
    | [] -> tag
    | l :: rest ->
        let t = String.trim l in
        if String.length t >= 2 && t.[0] = '#' && t.[1] = ' ' then
          String.trim (String.sub t 2 (String.length t - 2))
        else if t <> "" then t
        else go rest in
  go lines

let format_table_verdict v =
  match v with
  | `Assoc fs ->
      let get k = match List.assoc_opt k fs with
        | Some (`String s) -> s
        | Some (`Bool b) -> string_of_bool b
        | Some `Null | None -> "-"
        | Some other -> Yojson.Safe.to_string other in
      let keys = [ "mode"; "quest"; "target"; "bump"; "previous_tag"; "tag";
                   "commit"; "release_kind"; "repo"; "release_url";
                   "installed_prefix"; "dry_run" ] in
      List.iter (fun k -> Printf.printf "%-18s %s\n" k (get k)) keys;
      (match List.assoc_opt "notes" fs with
       | Some (`String n) when n <> "" ->
           Printf.printf "\n%s" n;
           if n.[String.length n - 1] <> '\n' then print_newline ()
       | _ -> ())
  | other -> print_endline (Yojson.Safe.to_string other)

let emit_verdict ~fmt v =
  if fmt = "table" then format_table_verdict v
  else Render.print_verdict ~fmt:"json" v

let do_publish_only opts id =
  if not id.decider_human then
    err Names.e_human_required (`Assoc [])
      "Publishing a release requires a human decision (BP3_DECIDER=human)." 1;
  let (mode, quest_opt, tag, target, commit) =
    match opts.tag, opts.quest with
    | Some t, None ->
        let ttype, c1 = git_out [ "cat-file"; "-t"; t ] in
        if c1 <> 0 then not_found "tag" t;
        if ttype <> "tag" then
          err Names.e_illegal_edge (`Assoc [ ("tag", json_str t) ])
            ("Tag " ^ t ^ " is not an annotated tag.") 1;
        let sha = match ref_tip t with Some s -> s | None -> not_found "tag" t in
        let tgt = detect_target_branch opts.target in
        ("commit", None, t, tgt, sha)
    | None, Some q ->
        check_slug q;
        (match fold_quest q with
         | None -> not_found "quest" q
         | Some (_, _, _, _, text) ->
             (match quest_promoted_info text with
              | Some (Some t, Some c, tgt_opt) ->
                  let tgt = detect_target_branch (match opts.target with Some _ as o -> o | None -> tgt_opt) in
                  ("quest", Some q, t, tgt, c)
              | _ ->
                  err Names.e_illegal_edge (`Assoc [ ("quest", json_str q) ])
                    "Quest has no local release tag to publish." 1))
    | Some _, Some _ -> usage "pass either <quest> or --tag with --publish-only, not both"
    | None, None -> usage "--publish-only requires <quest> or --tag <vX.Y.Z>" in
  let gh_repo =
    match Release.classify_remote (remote_url opts.remote) with
    | Release.GitHub r -> r
    | Release.Local_tag ->
        usage ("--publish-only requires a GitHub remote on " ^ opts.remote) in
  let body, _ = git_out [ "for-each-ref"; "--format=%(contents)"; "refs/tags/" ^ tag ] in
  let title = title_from_tag_body tag body in
  let url =
    push_and_create_gh_release ~remote:opts.remote ~target ~tag ~repo:gh_repo
      ~title ~body ~commit in
  let ver = match Release.parse_semver_tag tag with
    | Some sv -> Some (Release.format_semver sv) | None -> None in
  let v = `Assoc [
    ("ok", `Bool true);
    ("mode", json_str mode);
    ("quest", opt_json quest_opt);
    ("state", (if quest_opt <> None then json_str "landed" else `Null));
    ("target", json_str target);
    ("previous_tag", `Null);
    ("version", opt_json ver);
    ("tag", json_str tag);
    ("bump", `Null);
    ("commit", json_str commit);
    ("release_kind", json_str "github");
    ("repo", json_str gh_repo);
    ("release_url", opt_json url);
    ("installed_prefix", `Null);
    ("dry_run", `Bool false);
    ("publish_only", `Bool true);
    ("notes", json_str body);
  ] in
  emit_verdict ~fmt:opts.fmt v; 0

let release_commit_msg ~quest_opt ~tag_opt ~subject ~body_summary =
  let subj =
    match tag_opt, quest_opt with
    | Some t, Some q -> Printf.sprintf "chore(release): %s (%s)" t q
    | Some t, None -> Printf.sprintf "chore(release): %s" t
    | None, Some q -> Printf.sprintf "chore(promote): %s" q
    | None, None -> "chore(release): " ^ subject in
  Printf.sprintf "%s\n\n%s\n" subj body_summary

let run argv id =
  let opts = parse_args argv in
  if opts.help then (print_string help_release; 0)
  else if opts.dry_run && opts.publish_only then
    usage "--dry-run and --publish-only cannot be combined"
  else if opts.publish_only then do_publish_only opts id
  else if opts.tag <> None then
    usage "--tag is only valid with --publish-only"
  else if opts.quest <> None && opts.commit <> None then
    usage "pass either <quest> or --commit <sha>, not both"
  else if opts.quest = None && opts.commit = None then
    usage "expected bp3 release <quest> or bp3 release --commit <sha>"
  else begin
    let mode = if opts.quest <> None then "quest" else "commit" in
    if not opts.dry_run && not id.decider_human then
      err Names.e_human_required (`Assoc [ ("mode", json_str mode) ])
        "Releasing requires a human decision (BP3_DECIDER=human); use --dry-run to preview." 1;
    let target = detect_target_branch opts.target in
    let target_ref = "refs/heads/" ^ target in
    let target_tip = match ref_tip target_ref with Some s -> s | None -> not_found "branch" target in

    (* Mode-specific validation and source resolution *)
    let (source_tip, qs_from_st, node_summaries, quest_md_path_opt, quest_md_text_opt, meta_opt) =
      match opts.quest, opts.commit with
      | Some q, None ->
          check_slug q;
          let (_, qs, _, _, qtext) =
            match fold_quest q with Some v -> v | None -> not_found "quest" q in
          if qs.st = "deleted" then
            err Names.e_illegal_edge (`Assoc [ ("quest", json_str q); ("state", json_str "deleted") ])
              "Cannot release a deleted quest." 1;
          (match quest_promoted_info qtext with
           | Some (ptag, pcommit, _) ->
               err Names.e_already_promoted
                 (`Assoc [ ("quest", json_str q); ("tag", opt_json ptag);
                           ("commit", opt_json pcommit) ])
                 "Quest was already released; use --publish-only to retry GitHub publishing." 1
           | None -> ());
          let nodes = list_nodes q in
          let folded = List.map (fun n ->
            match fold_node q n with
            | Some (_, s, _) -> (n, s)
            | None -> (n, fresh_state ())) nodes in
          let pending =
            List.filter_map (fun (n, s) ->
              if s.st <> "landed" && s.st <> "deleted" then Some n else None) folded in
          if folded = [] || pending <> [] then
            err Names.e_not_ready
              (`Assoc [ ("quest", json_str q);
                        ("pending_nodes", `List (List.map json_str pending)) ])
              "All quest nodes must be landed or deleted (goal_fin) before releasing." 1;
          let work_ref = "refs/heads/" ^ Layout.work_branch q in
          let src =
            match ref_tip work_ref with
            | Some s -> s
            | None -> head_sha () in
          let qpath = Layout.quest_dir q ^ "/" ^ Layout.quest_file in
          let qmd = match git_show src qpath with Some t -> t | None -> "" in
          let meta = Release.parse_quest_md qmd in
          let summaries =
            List.filter_map (fun (n, s) ->
              if s.st = "deleted" then None
              else
                let subj = match s.last_commit with Some c -> commit_subject c | None -> "" in
                Some { Release.node_id = n; state = s.st; commit = s.last_commit; subject = subj })
              folded in
          (src, qs.st, summaries, Some qpath, (if qmd = "" then None else Some qmd), Some meta)
      | None, Some raw_sha ->
          let full = match resolve_commit raw_sha with
            | Some f -> f
            | None ->
                err Names.e_commit_mismatch (`Assoc [ ("commit", json_str raw_sha) ])
                  "Commit does not exist; pass a valid commit SHA." 1 in
          (full, "", [], None, None, None)
      | _ -> usage "invalid release arguments" in

    (* Clean worktree checks (current + every worktree on target branch) *)
    let target_wts = worktrees_on_branch target_ref in
    if not opts.dry_run then begin
      check_clean_dir root;
      List.iter check_clean_dir target_wts
    end;

    (* Fast-forward ancestry check *)
    if not (is_ancestor target_tip source_tip) then
      err Names.e_not_fast_forward
        (`Assoc [ ("target", json_str target); ("target_tip", json_str target_tip);
                  ("source_tip", json_str source_tip) ])
        ("Target branch " ^ target ^ " moved ahead of source commit (parallel release). Rebase onto "
         ^ target ^ ", re-verify, and retry.") 1;

    (* Bump resolution *)
    let bump =
      match mode, opts.bump, meta_opt with
      | "quest", Some b_str, _ ->
          (match Release.parse_bump b_str with
           | Some b -> b
           | None -> usage ("invalid --bump: " ^ b_str ^ " (expected major|minor|patch|none)"))
      | "quest", None, Some m ->
          (match m.Release.bump with
           | Some b_str ->
               (match Release.parse_bump b_str with
                | Some b -> b
                | None ->
                    err Names.e_bump_missing (`Assoc [ ("bump", json_str b_str) ])
                      ("Invalid QUEST.md bump: " ^ b_str ^ "; pass --bump major|minor|patch|none.") 1)
           | None ->
               err Names.e_bump_missing (`Assoc [ ("quest", opt_json opts.quest) ])
                 "No bump: in QUEST.md frontmatter; add bump: or pass --bump major|minor|patch|none." 1)
      | "commit", Some b_str, _ ->
          (match Release.parse_bump b_str with
           | Some Release.None_bump -> usage "--bump none is not valid for --commit releases"
           | Some b -> b
           | None -> usage ("invalid --bump: " ^ b_str ^ " (expected major|minor|patch)"))
      | "commit", None, _ -> Release.Patch
      | _ -> usage "unable to resolve bump" in

    let prev_sv = Release.latest_semver_tag (list_v_tags ()) in
    let prev_tag = Option.map Release.format_tag prev_sv in
    let next_sv = Release.next_semver prev_sv bump in
    let next_ver = Option.map Release.format_semver next_sv in
    let tag_opt = Option.map Release.format_tag next_sv in
    let gh_repo =
      if opts.no_gh || tag_opt = None then None
      else match Release.classify_remote (remote_url opts.remote) with
        | Release.GitHub r -> Some r
        | Release.Local_tag -> None in
    let release_kind =
      match tag_opt, gh_repo with
      | None, _ -> "none"
      | Some _, Some _ -> "github"
      | Some _, None -> "git_tag" in

    let commits = commits_since prev_tag source_tip in
    let notes =
      match opts.quest, meta_opt with
      | Some q, Some meta ->
          Release.render_what_changed ~quest:q
            ~tag:(Option.value tag_opt ~default:q) ~prev_tag ~meta
            ~nodes:node_summaries ~commit_subjects:commits
      | _ ->
          Release.render_commit_what_changed ~sha:source_tip
            ~subject:(commit_subject source_tip) ~body:(commit_body source_tip)
            ~tag:(Option.value tag_opt ~default:(Release.short_sha source_tip))
            ~prev_tag ~commit_subjects:commits in

    if opts.dry_run then begin
      let v = `Assoc [
        ("ok", `Bool true);
        ("mode", json_str mode);
        ("quest", opt_json opts.quest);
        ("state", (if opts.quest <> None then json_str "landed" else `Null));
        ("target", json_str target);
        ("previous_tag", opt_json prev_tag);
        ("version", opt_json next_ver);
        ("tag", opt_json tag_opt);
        ("bump", json_str (Release.bump_to_string bump));
        ("commit", json_str source_tip);
        ("release_kind", json_str release_kind);
        ("repo", opt_json gh_repo);
        ("release_url", `Null);
        ("installed_prefix", `Null);
        ("dry_run", `Bool true);
        ("notes", json_str notes.Release.body);
      ] in
      emit_verdict ~fmt:opts.fmt v; 0
    end else begin
      (* Assemble files for plumbing release commit *)
      let files = ref [] in
      (match quest_md_path_opt, quest_md_text_opt with
       | Some p, Some txt ->
           let updated = Release.set_quest_status_landed txt in
           if updated <> txt then files := (p, updated) :: !files
       | _ -> ());
      (match next_ver with
       | Some nv ->
           if repo_mode () = "self" then begin
             match git_show source_tip "src/quest/gitx.ml" with
             | Some gitx_txt ->
                 (match Release.sync_bp3_version ~new_version:nv gitx_txt with
                  | Ok updated -> files := ("src/quest/gitx.ml", updated) :: !files
                  | Error msg ->
                      err Names.e_stale_world (`Assoc [ ("detail", json_str msg) ]) msg 1)
             | None -> ()
           end else begin
             match git_show source_tip "VERSION" with
             | Some _ -> files := ("VERSION", nv ^ "\n") :: !files
             | None -> ()
           end
       | None -> ());
      let files = List.rev !files in
      let new_tip =
        if files = [] then source_tip
        else
          let msg =
            release_commit_msg ~quest_opt:opts.quest ~tag_opt
              ~subject:(commit_subject source_tip) ~body_summary:notes.Release.body in
          plumbing_commit ~base_tip:source_tip ~files ~msg in
      let tag_obj_opt =
        match tag_opt with
        | Some t -> Some (plumbing_mktag ~commit:new_tip ~tag:t ~message:notes.Release.body)
        | None -> None in

      (* Atomic CAS over target branch + new tag *)
      atomic_cas_update ~target ~new_tip ~old_target_tip:target_tip ~tag_opt ~tag_obj_opt;
      sync_clean_worktrees target_wts;

      (* Record quest ledger promote line *)
      (match opts.quest with
       | Some q ->
           let reason = match opts.reason with
             | Some r when r <> "" -> r
             | _ -> "release " ^ q in
           append_quest_promote_line ~quest:q ~from_st:qs_from_st ~commit:new_tip
             ~tag:tag_opt ~bump_str:(Release.bump_to_string bump) ~target
             ~release_kind ~reason ~id
       | None -> ());

      (* Optional GitHub push + release *)
      let release_url =
        match tag_opt, gh_repo with
        | Some t, Some r ->
            push_and_create_gh_release ~remote:opts.remote ~target ~tag:t ~repo:r
              ~title:notes.Release.title ~body:notes.Release.body ~commit:new_tip
        | _ -> None in

      (* Optional self-mode tag-gated local $PREFIX install (hook wired in sync.1) *)
      let installed_prefix =
        let env_skip = Sys.getenv_opt "BP3_RELEASE_NO_INSTALL" = Some "1" in
        let install_root = match target_wts with wt :: _ -> wt | [] -> root in
        match repo_mode (), tag_opt, next_ver with
        | "self", Some t, Some nv when not opts.no_install && not env_skip ->
            !self_install_hook ~install_root ~tag:t ~version:nv ~commit:new_tip
        | _ -> None in

      let v = `Assoc [
        ("ok", `Bool true);
        ("mode", json_str mode);
        ("quest", opt_json opts.quest);
        ("state", (if opts.quest <> None then json_str "landed" else `Null));
        ("target", json_str target);
        ("previous_tag", opt_json prev_tag);
        ("version", opt_json next_ver);
        ("tag", opt_json tag_opt);
        ("bump", json_str (Release.bump_to_string bump));
        ("commit", json_str new_tip);
        ("release_kind", json_str release_kind);
        ("repo", opt_json gh_repo);
        ("release_url", opt_json release_url);
        ("installed_prefix", opt_json installed_prefix);
        ("dry_run", `Bool false);
        ("notes", json_str notes.Release.body);
      ] in
      emit_verdict ~fmt:opts.fmt v; 0
    end
  end
