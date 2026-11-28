(* hooks — the bp3 q hooks emitter. Reads one Muse hook
   event JSON from stdin, self-gates, resolves the witnessed Run
   binding, and appends past-tense event lines to the node ledger
   through the internal fact writer below. Always exits 0:
   fail-open, never blocks a tool, never judges an edge.
   Event lines carry event/ts/run_id and never edge/from/to,
   so the Store fold skips them by construction. *)
open Gitx
open Util
open Store

(* ---------- small helpers ---------- *)
let verdict ?(warnings = []) event_line reason =
  let base = [
    ("ok", `Bool true);
    ("event_line", event_line);
    ("reason", (match reason with Some r -> json_str r | None -> `Null));
  ] in
  let fields =
    if warnings = [] then base
    else base @ [ ("warnings", `List warnings) ] in
  `Assoc fields

let no_write ?(warnings = []) reason = verdict ~warnings `Null (Some reason)

let read_stdin () =
  let buf = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_string buf (input_line stdin);
       Buffer.add_char buf '\n'
     done
   with End_of_file -> ());
  Buffer.contents buf

let member_str j key = Util.get_str j key ""
let member_int j key = Util.get_int j key 0

let rec collect_strings acc = function
  | `String s -> s :: acc
  | `Assoc fs -> List.fold_left (fun a (_, v) -> collect_strings a v) acc fs
  | `List xs -> List.fold_left collect_strings acc xs
  | _ -> acc

let payload_strings j =
  List.concat (List.map (fun k ->
    try collect_strings [] (Yojson.Safe.Util.member k j) with _ -> [])
    ["tool_response"; "tool_output"; "output"; "response"; "result"; "error"])

let command_of j =
  let claude_cmd =
    try match Yojson.Safe.Util.member "tool_input" j with
      | `Assoc _ as ti -> member_str ti "command"
      | _ -> ""
    with _ -> "" in
  if claude_cmd <> "" then claude_cmd
  else
    try match Yojson.Safe.Util.member "toolCall" j with
      | `Assoc _ as tc ->
          (match Yojson.Safe.Util.member "args" tc with
           | `Assoc _ as args -> member_str args "CommandLine"
           | _ -> "")
      | _ -> ""
    with _ -> ""

let file_path_of j =
  let claude_path =
    try match Yojson.Safe.Util.member "tool_input" j with
      | `Assoc _ as ti ->
          let p = member_str ti "file_path" in
          if p <> "" then p else member_str ti "path"
      | _ -> ""
    with _ -> "" in
  if claude_path <> "" then claude_path
  else
    try match Yojson.Safe.Util.member "toolCall" j with
      | `Assoc _ as tc ->
          (match Yojson.Safe.Util.member "args" tc with
           | `Assoc _ as args ->
               let p = member_str args "Path" in
               if p <> "" then p
               else
                 let p2 = member_str args "TargetFile" in
                 if p2 <> "" then p2 else member_str args "path"
           | _ -> "")
      | _ -> ""
    with _ -> ""

(* ---------- per-session quest binding (<git-common-dir>/bp3/sessions/<sid>.json) ---------- *)
let session_ttl_s = 86400

type session_action =
  | Session_bind of { quest : string; mode : string; red_ink_path : string option }
  | Session_clear of string

let sanitize_session_id sid =
  let n = String.length sid in
  if n = 0 || n > 128 || sid.[0] = '.' || contains_sub sid ".." then None
  else
    let ok c =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
      || (c >= '0' && c <= '9') || c = '.' || c = '_' || c = '-' in
    let rec loop i = if i >= n then true else ok sid.[i] && loop (i + 1) in
    if loop 0 then Some sid else None

let strip_matching_quotes s =
  let n = String.length s in
  if n >= 2 && ((s.[0] = '"' && s.[n - 1] = '"') || (s.[0] = '\'' && s.[n - 1] = '\''))
  then String.sub s 1 (n - 2)
  else s

let split_shell_segments cmd =
  let n = String.length cmd in
  let buf = Buffer.create 64 in
  let segs = ref [] in
  let flush () =
    let s = String.trim (Buffer.contents buf) in
    Buffer.clear buf;
    if s <> "" then segs := s :: !segs in
  let i = ref 0 in
  let in_sq = ref false and in_dq = ref false in
  while !i < n do
    let c = cmd.[!i] in
    if !in_sq then begin
      if c = '\'' then in_sq := false;
      Buffer.add_char buf c;
      incr i
    end else if !in_dq then begin
      if c = '"' then in_dq := false;
      Buffer.add_char buf c;
      incr i
    end else if c = '\'' then begin
      in_sq := true; Buffer.add_char buf c; incr i
    end else if c = '"' then begin
      in_dq := true; Buffer.add_char buf c; incr i
    end else if c = '\n' || c = ';' then begin
      flush (); incr i
    end else if c = '&' && !i + 1 < n && cmd.[!i + 1] = '&' then begin
      flush (); i := !i + 2
    end else if c = '|' then begin
      flush ();
      if !i + 1 < n && cmd.[!i + 1] = '|' then i := !i + 2 else incr i
    end else begin
      Buffer.add_char buf c; incr i
    end
  done;
  flush ();
  List.rev !segs

let tokenize_segment seg =
  let n = String.length seg in
  let buf = Buffer.create 32 in
  let toks = ref [] in
  let flush () =
    let s = Buffer.contents buf in
    Buffer.clear buf;
    if s <> "" then toks := strip_matching_quotes s :: !toks in
  let i = ref 0 in
  let in_sq = ref false and in_dq = ref false in
  while !i < n do
    let c = seg.[!i] in
    if !in_sq then begin
      if c = '\'' then in_sq := false;
      Buffer.add_char buf c; incr i
    end else if !in_dq then begin
      if c = '"' then in_dq := false;
      Buffer.add_char buf c; incr i
    end else if c = '\'' then begin
      in_sq := true; Buffer.add_char buf c; incr i
    end else if c = '"' then begin
      in_dq := true; Buffer.add_char buf c; incr i
    end else if c = ' ' || c = '\t' || c = '\r' then begin
      flush (); incr i
    end else begin
      Buffer.add_char buf c; incr i
    end
  done;
  flush ();
  List.rev !toks

let is_env_assign tok =
  match String.index_opt tok '=' with
  | Some idx when idx > 0 ->
      let k = String.sub tok 0 idx in
      let ok c =
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9') || c = '_' in
      let rec loop i = i >= idx || (ok k.[i] && loop (i + 1)) in
      k.[0] <> '-' && loop 0
  | _ -> false

let rec drop_env_prefix = function
  | "env" :: rest -> drop_env_prefix rest
  | tok :: rest when is_env_assign tok -> drop_env_prefix rest
  | toks -> toks

let is_bp3_bin tok =
  tok = "bp3"
  || (let n = String.length tok in n > 4 && String.sub tok (n - 4) 4 = "/bp3")

let reserved_q_verbs =
  [ "c"; "create"; "r"; "read"; "hooks"; "metrics"; "help"; "-h"; "--help"; "version"; "--version" ]

let rec find_quest_flag = function
  | "--quest" :: q :: _ -> Some q
  | tok :: rest ->
      (match strip_prefix ~prefix:"--quest=" tok with
       | Some q -> Some q
       | None -> find_quest_flag rest)
  | [] -> None

let extract_release_quest args =
  if List.exists (fun a -> a = "--dry-run" || a = "--commit" || starts_with a "--commit=") args
  then None
  else
    let rec go = function
      | [] -> None
      | "--bump" :: _ :: rest -> go rest
      | tok :: rest when starts_with tok "-" -> go rest
      | q :: _ -> if valid_slug q then Some q else None in
    go args

let extract_action_from_segment seg =
  match drop_env_prefix (tokenize_segment seg) with
  | cmd :: rest when is_bp3_bin cmd ->
      (match rest with
       | "release" :: args ->
           (match extract_release_quest args with
            | Some q -> Some (Session_clear q)
            | None -> None)
       | "harness" :: "desk" :: "prepare" :: args
       | "worktree" :: "prepare" :: args ->
           (match find_quest_flag args with
            | Some q when valid_slug q ->
                Some (Session_bind { quest = q; mode = "induct"; red_ink_path = None })
            | _ -> None)
       | "q" :: q_args ->
           (match q_args with
            | ("c" | "create" | "r" | "read") :: q :: _ when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (Session_bind { quest = q; mode = "induct"; red_ink_path = None })
            | q :: _sub :: _ when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (Session_bind { quest = q; mode = "induct"; red_ink_path = None })
            | _ -> None)
       | _ -> None)
  | _ -> None

let extract_red_ink_from_path file_path =
  let norm = String.map (fun c -> if c = '\\' then '/' else c) (String.trim file_path) in
  let marker = "docs/quests/" in
  let mlen = String.length marker in
  let n = String.length norm in
  let rec find_marker i =
    if i + mlen > n then None
    else if String.sub norm i mlen = marker && (i = 0 || norm.[i - 1] = '/') then
      Some (String.sub norm (i + mlen) (n - i - mlen))
    else find_marker (i + 1) in
  match find_marker 0 with
  | None -> None
  | Some tail ->
      (match String.split_on_char '/' tail with
       | [ q; fname ]
         when valid_slug q && (fname = "QUEST.red-ink.md" || fname = "QUEST.2b-reviewed.md") ->
           Some (Session_bind {
             quest = q;
             mode = "red-ink";
             red_ink_path = Some (marker ^ q ^ "/" ^ fname);
           })
       | _ -> None)

let extract_quest_phase_from_path file_path =
  let norm = String.map (fun c -> if c = '\\' then '/' else c) (String.trim file_path) in
  let marker = "docs/quests/" in
  let mlen = String.length marker in
  let n = String.length norm in
  let rec find_marker i =
    if i + mlen > n then None
    else if String.sub norm i mlen = marker && (i = 0 || norm.[i - 1] = '/') then
      Some (String.sub norm (i + mlen) (n - i - mlen))
    else find_marker (i + 1) in
  match find_marker 0 with
  | None -> None
  | Some tail ->
      (match String.split_on_char '/' tail with
       | q :: fname :: _ when valid_slug q ->
           if fname = "QUEST.red-ink.md" || fname = "QUEST.2b-reviewed.md" then Some (q, "red-ink")
           else if fname = "FEEDBACK.md" || fname = "demo" then Some (q, "fin")
           else if fname = "QUEST.md" || fname = "quest.json" || fname = "LOG.md" || fname = "nodes" then Some (q, "init")
           else None
       | _ -> None)

let extract_quest_phase_from_segment_detail seg =
  match drop_env_prefix (tokenize_segment seg) with
  | cmd :: rest when is_bp3_bin cmd ->
      (match rest with
       | "release" :: args ->
           let rec go = function
             | [] -> None
             | "--bump" :: _ :: tl -> go tl
             | ("--commit" | "--target" | "--remote" | "--reason" | "--tag") :: _ :: tl -> go tl
             | tok :: tl when starts_with tok "-" -> go tl
             | q :: _ -> if valid_slug q then Some (q, "fin", false) else None in
           go args
       | "warden" :: args ->
           let rec go = function
             | [] -> None
             | ("human-log" | "query") :: _ -> None
             | ("--session" | "--format" | "--last" | "--dir" | "--claude-dir" | "--pi-dir" | "--agy-dir") :: _ :: tl -> go tl
             | tok :: tl when starts_with tok "-" -> go tl
             | q :: _ -> if valid_slug q then Some (q, "fin", false) else None in
           go args
       | "harness" :: "desk" :: "prepare" :: args
       | "worktree" :: "prepare" :: args ->
           (match find_quest_flag args with
            | Some q when valid_slug q -> Some (q, "induct", false)
            | _ -> None)
       | "q" :: q_args ->
           (match q_args with
            | ("r" | "read") :: q :: _ when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (q, "induct", true)
            | ("c" | "create") :: q :: _ when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (q, "induct", false)
            | q :: ("r" | "read") :: _ when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (q, "induct", true)
            | q :: ("n" | "node") :: _ :: ("r" | "read" | "brief") :: _
              when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (q, "induct", true)
            | q :: "metrics" :: ("r" | "read") :: _
              when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (q, "induct", true)
            | q :: _sub :: _ when valid_slug q && not (List.mem q reserved_q_verbs) ->
                Some (q, "induct", false)
            | _ -> None)
       | _ -> None)
  | _ -> None

let extract_quest_phase_from_segment seg =
  Option.map (fun (q, p, _) -> (q, p)) (extract_quest_phase_from_segment_detail seg)

let extract_quest_phase_detail ~command ~file_path =
  match extract_quest_phase_from_path file_path with
  | Some (q, p) -> Some (q, p, true, false)
  | None ->
      if String.trim command = "" then None
      else
        List.fold_left (fun acc seg ->
          match extract_quest_phase_from_segment_detail seg with
          | Some (q, p, readonly) -> Some (q, p, false, readonly)
          | None -> acc) None (split_shell_segments command)

let extract_quest_phase ~command ~file_path =
  Option.map (fun (q, p, _, _) -> (q, p)) (extract_quest_phase_detail ~command ~file_path)

let extract_session_action ~command ~file_path =
  match extract_red_ink_from_path file_path with
  | Some _ as act -> act
  | None ->
      if String.trim command = "" then None
      else
        List.fold_left (fun acc seg ->
          match extract_action_from_segment seg with
          | Some _ as act -> act
          | None -> acc) None (split_shell_segments command)

let canon_path p = try Unix.realpath p with _ -> p

let bp3_common_dir_of gate_root =
  match run_capture [ "git"; "-C"; gate_root; "rev-parse"; "--git-common-dir" ] with
  | (raw, 0) when raw <> "" ->
      let abs =
        if Filename.is_relative raw then Filename.concat gate_root raw else raw in
      Some (Filename.concat (canon_path abs) "bp3")
  | _ -> None

let session_dir_of gate_root =
  Option.map (fun d -> Filename.concat d "sessions") (bp3_common_dir_of gate_root)

let quest_sessions_dir_of gate_root =
  Option.map (fun d -> Filename.concat d "quest-sessions") (bp3_common_dir_of gate_root)

let harness_of_payload payload =
  if member_str payload "conversationId" <> "" then "agy"
  else if member_str payload "hook_event_name" <> "" then "claude"
  else "pi"

let last_nonempty_line text =
  String.split_on_char '\n' text
  |> List.rev
  |> List.find_opt (fun ln -> String.trim ln <> "")

let should_skip_quest_phase ~last_sid ~last_phase ~sid ~phase ~readonly =
  last_sid = sid
  && (last_phase = phase || (last_phase = "fin" && phase = "induct" && readonly))

let rec canon_path_deep p =
  if Sys.file_exists p then canon_path p
  else
    let dir = Filename.dirname p in
    if dir = p then p
    else Filename.concat (canon_path_deep dir) (Filename.basename p)

let path_within_root ~gate_root file_path =
  let norm = String.map (fun c -> if c = '\\' then '/' else c) (String.trim file_path) in
  if norm = "" || norm.[0] <> '/' then true
  else
    let canon_root = canon_path_deep gate_root in
    let canon_fp = canon_path_deep norm in
    starts_with norm (gate_root ^ "/")
    || starts_with canon_fp (canon_root ^ "/")

let quest_known_in_repo ~gate_root ~qdir quest =
  Sys.file_exists (Filename.concat qdir (quest ^ ".jsonl"))
  || List.exists (fun r ->
         Sys.file_exists (Filename.concat gate_root (Filename.concat r quest)))
       (Layout.quests_root :: Layout.legacy_quests_roots)
  || snd (run_capture [ "git"; "-C"; gate_root; "show-ref"; "--verify"; "--quiet";
                        Layout.quest_ref_of Layout.quest_ref_kind quest ]) = 0

let append_quest_session ~qdir ~quest ~sid ~harness ~phase ?(readonly = false) ~ts () =
  match sanitize_session_id sid with
  | None -> ()
  | Some clean_sid ->
      if not (valid_slug quest) then ()
      else
        let path = Filename.concat qdir (quest ^ ".jsonl") in
        let existing = if Sys.file_exists path then read_file_or path "" else "" in
        let skip =
          match last_nonempty_line existing with
          | None -> false
          | Some ln ->
              (try
                 match Yojson.Safe.from_string ln with
                 | `Assoc _ as j ->
                     should_skip_quest_phase
                       ~last_sid:(member_str j "sid")
                       ~last_phase:(member_str j "phase")
                       ~sid:clean_sid ~phase ~readonly
                 | _ -> false
               with _ -> false) in
        if not skip then begin
          Util.mkdir_p qdir;
          let line = Yojson.Safe.to_string (`Assoc [
            ("sid", json_str clean_sid);
            ("harness", json_str harness);
            ("phase", json_str phase);
            ("ts", `Int ts);
          ]) ^ "\n" in
          let oc = open_out_gen [ Open_creat; Open_append; Open_wronly ] 0o644 path in
          Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc line)
        end

let has_quests_dir gate_root =
  List.exists (fun r ->
    try Sys.is_directory (Filename.concat gate_root r) with _ -> false)
    (Layout.quests_root :: Layout.legacy_quests_roots)

let prune_stale_sessions ~sdir ~now ~ttl_s =
  if Sys.file_exists sdir && Sys.is_directory sdir then
    let entries = try Array.to_list (Sys.readdir sdir) with _ -> [] in
    List.iter (fun name ->
      let len = String.length name in
      if len > 5 && String.sub name (len - 5) 5 = ".json" then
        let path = Filename.concat sdir name in
        try
          let txt = read_file_or path "" in
          let ts_opt =
            try
              match Yojson.Safe.from_string txt with
              | `Assoc _ as j -> Util.get_int_opt j "updated_ts"
              | _ -> None
            with _ -> None in
          let stale =
            match ts_opt with
            | Some ts -> now - ts > ttl_s
            | None ->
                let st = Unix.stat path in
                float_of_int now -. st.Unix.st_mtime > float_of_int ttl_s in
          if stale then (try Unix.unlink path with _ -> ())
        with _ -> ()) entries

let unlink_session_if_quest path quest =
  if Sys.file_exists path then
    try
      let txt = read_file_or path "" in
      match Yojson.Safe.from_string txt with
      | `Assoc _ as j when member_str j "quest" = quest ->
          (try Unix.unlink path with _ -> ())
      | _ -> ()
    with _ -> ()

let update_session_binding ~harness ~gate_root ~sid ~event ~command ~file_path ~is_failure ~has_refusal =
  try
    match sanitize_session_id sid with
    | None -> ()
    | Some clean_sid ->
        if not (has_quests_dir gate_root) then ()
        else
          (match session_dir_of gate_root with
           | None -> ()
           | Some sdir ->
               let now = int_of_float (Clock.time ()) in
               match event with
               | "SessionStart" ->
                   prune_stale_sessions ~sdir ~now ~ttl_s:session_ttl_s
               | "PreToolUse" | "PostToolUse" ->
                   let spath = Filename.concat sdir (clean_sid ^ ".json") in
                   (match extract_session_action ~command ~file_path with
                    | None -> ()
                    | Some (Session_clear q) ->
                        if event = "PostToolUse" && not is_failure && not has_refusal then
                          unlink_session_if_quest spath q
                    | Some (Session_bind { quest; mode; red_ink_path }) ->
                        if not is_failure then begin
                          Util.mkdir_p sdir;
                          let j = `Assoc [
                            ("session_id", json_str clean_sid);
                            ("quest", json_str quest);
                            ("mode", json_str mode);
                            ("desk", `Null);
                            ("red_ink_path", (match red_ink_path with Some p -> json_str p | None -> `Null));
                            ("updated_ts", `Int now);
                          ] in
                          Util.write_file_atomic spath (Yojson.Safe.to_string j ^ "\n")
                        end);
                   if event = "PostToolUse" && not is_failure then
                     (match extract_quest_phase_detail ~command ~file_path, quest_sessions_dir_of gate_root with
                      | Some (q, phase, from_path, readonly), Some qdir ->
                          let allowed =
                            if from_path then path_within_root ~gate_root file_path
                            else quest_known_in_repo ~gate_root ~qdir q in
                          if allowed then
                            append_quest_session ~qdir ~quest:q ~sid:clean_sid ~harness ~phase ~readonly ~ts:now ()
                      | _ -> ())
               | _ -> ())
  with _ -> ()

let extract_preset command key =
  try
    let re = Str.regexp (key ^ "=\\([^ \t\"']+\\)") in
    ignore (Str.search_forward re command 0);
    Some (Str.matched_group 1 command)
  with _ -> None

let parse_edge_cycle run_id =
  let parts = String.split_on_char '-' run_id in
  let edge = match parts with _ :: e :: _ -> e | _ -> "" in
  let cycle =
    match List.rev parts with
    | last :: _ when String.length last >= 2 && last.[0] = 'c' ->
        (match int_of_string_opt (String.sub last 1 (String.length last - 1)) with
         | Some n -> n | None -> 1)
    | _ -> 1 in
  (edge, cycle)

let attempted_edge command =
  let toks = String.split_on_char ' ' command
    |> List.map String.trim |> List.filter (fun s -> s <> "") in
  let rec go = function
    | "u" :: _node :: edge :: _ -> Some edge
    | "update" :: _node :: edge :: _ -> Some edge
    | _ :: rest -> go rest
    | [] -> None in
  go toks

let lint_check_of command =
  if contains_sub command "make check" then Some "make check"
  else if contains_sub command "make lint" then Some "make lint"
  else if contains_sub command "shellcheck" then Some "shellcheck"
  else
    let toks = String.split_on_char ' ' command
      |> List.map String.trim |> List.filter (fun s -> s <> "") in
    match List.find_opt (fun t ->
      contains_sub t "test/" && String.length t > 3 &&
      String.sub t (String.length t - 3) 3 = ".sh") toks with
    | Some t -> Some (Filename.basename t)
    | None -> None

let refusal_code j =
  let text = String.concat "\n" (payload_strings j) in
  try
    let re = Str.regexp "\"code\"[ \t]*:[ \t]*\"\\(E_[A-Z_]+\\)\"" in
    ignore (Str.search_forward re text 0);
    Some (Str.matched_group 1 text)
  with _ -> None

(* ---------- run registry (in the git dir, never the worktree,
   so witnessing a Run never dirties the tree it observes) ---------- *)
type binding = {
  quest : string; node : string; run_id : string; session_id : string;
  started_ts : string; started_epoch : float;
  mutable last_seen_ts : string; mutable last_seen_epoch : float;
  mutable settled : bool; mutable unsettled : bool;
  mutable emitted : string list;
  mutable in_tok : int; mutable out_tok : int;
  mutable cached_tok : int; mutable reasoning_tok : int;
  mutable llm_calls : int;
}

let registry_path () =
  match git_out ["rev-parse"; "--absolute-git-dir"] with
  | (out, 0) when out <> "" -> Filename.concat out "bp3-run-registry.json"
  | _ -> Filename.concat (Filename.concat (current_root ()) ".git") "bp3-run-registry.json"

let binding_to_json b =
  (b.session_id, `Assoc [
    ("quest", json_str b.quest); ("node", json_str b.node);
    ("run_id", json_str b.run_id); ("started_ts", json_str b.started_ts);
    ("started_epoch", `Float b.started_epoch);
    ("last_seen_ts", json_str b.last_seen_ts);
    ("last_seen_epoch", `Float b.last_seen_epoch);
    ("settled", `Bool b.settled); ("unsettled", `Bool b.unsettled);
    ("emitted", `List (List.map json_str b.emitted));
    ("input_tokens", `Int b.in_tok); ("output_tokens", `Int b.out_tok);
    ("cached_tokens", `Int b.cached_tok);
    ("reasoning_tokens", `Int b.reasoning_tok);
    ("llm_calls", `Int b.llm_calls)])

let binding_of_json sid j =
  let f key = try match Yojson.Safe.Util.member key j with `Float x -> x | `Int n -> float_of_int n | _ -> 0. with _ -> 0. in
  let bl key = try match Yojson.Safe.Util.member key j with `Bool x -> x | _ -> false with _ -> false in
  { quest = (let v = member_str j "quest" in if v <> "" then v else member_str j "graph"); node = member_str j "node";
    run_id = member_str j "run_id"; session_id = sid;
    started_ts = member_str j "started_ts"; started_epoch = f "started_epoch";
    last_seen_ts = member_str j "last_seen_ts";
    last_seen_epoch = (let e = f "last_seen_epoch" in
      if e > 0. then e else f "started_epoch");
    settled = bl "settled"; unsettled = bl "unsettled";
    emitted = (try match Yojson.Safe.Util.member "emitted" j with
      | `List xs -> List.filter_map (function `String s -> Some s | _ -> None) xs
      | _ -> [] with _ -> []);
    in_tok = member_int j "input_tokens"; out_tok = member_int j "output_tokens";
    cached_tok = member_int j "cached_tokens";
    reasoning_tok = member_int j "reasoning_tokens";
    llm_calls = member_int j "llm_calls" }

let load_registry () =
  try
    let text = read_file_or (registry_path ()) "" in
    if String.trim text = "" then [] else
    match Yojson.Safe.from_string text with
    | `Assoc fs ->
        (match List.assoc_opt "sessions" fs with
         | Some (`Assoc ss) -> List.map (fun (sid, j) -> binding_of_json sid j) ss
         | _ -> [])
    | _ -> []
  with _ -> []

let save_registry bindings =
  try
    let path = registry_path () in
    Util.write_file_atomic path
      (Yojson.Safe.to_string
         (`Assoc [("sessions", `Assoc (List.map binding_to_json bindings))]))
  with _ -> ()

(* A binding is stale only when nothing has touched it for this
   long: a SessionStart from a new session proves nothing about a
   Run that is still live in parallel, so the sweep below must
   not mark fresh bindings run_unsettled. *)
let stale_after_s = 900.

let touch b =
  b.last_seen_ts <- now_ts ();
  b.last_seen_epoch <- Clock.time ()

(* ---------- fact writer: appends one event line to the node
   ledger on its branch. The only ledger door hooks may use;
   it writes no state.yaml because event lines change no state. ---------- *)
let append_event quest node line =
  match ledger_read (node_branch quest node) (node_ledger_path quest node) (legacy_node_ledger_paths quest node) with
  | None -> false
  | Some (tip, text, lpath) ->
      let new_text = (if String.trim text = "" then "" else
        (if text.[String.length text - 1] = '\n' then text else text ^ "\n"))
        ^ line ^ "\n" in
      (try
         ignore (commit_files ~branch:(node_branch quest node) ~base_tip:tip
           ~expect_tip:tip ~files:[(lpath, new_text)]
           ~msg:"bp3: hooks");
         true
       with _ -> false)

let emit bindings b kind fields dedupe_key =
  ignore bindings;
  if List.mem dedupe_key b.emitted then None
  else
    let fields = ("event", json_str kind) :: ("ts", json_str (now_ts ()))
      :: ("run_id", json_str b.run_id) :: fields in
    let line = Yojson.Safe.to_string (`Assoc fields) in
    if append_event b.quest b.node line then begin
      b.emitted <- dedupe_key :: b.emitted;
      Some (`Assoc fields)
    end else None

let agy_reply event =
  if event = "PreToolUse" then `Assoc [("decision", json_str "allow")]
  else `Assoc []

(* ---------- gate root & legacy local skill detection (global.2) ---------- *)

let payload_cwd ?(fallback = "") j =
  let c = member_str j "cwd" in
  if c <> "" then c
  else
    let from_ws =
      try
        match Yojson.Safe.Util.member "workspacePaths" j with
        | `List xs ->
            List.find_map (function `String s when s <> "" -> Some s | _ -> None) xs
        | _ -> None
      with _ -> None in
    match from_ws with
    | Some p -> p
    | None -> fallback

let resolve_gate_root raw =
  if raw <> "" && Sys.file_exists raw then
    match run_capture [ "git"; "-C"; raw; "rev-parse"; "--show-toplevel" ] with
    | (top, 0) when top <> "" -> top
    | _ -> raw
  else raw

let is_bp3_repo gate_root =
  gate_root <> "" && (
    Sys.file_exists (Filename.concat gate_root Layout.manifest_file)
    || (Sys.file_exists (Filename.concat gate_root "bin/bp3")
        && List.exists (fun r ->
             try Sys.is_directory (Filename.concat gate_root r) with _ -> false)
           (Layout.quests_root :: Layout.legacy_quests_roots)))

let is_host_git_repo gate_root =
  let inside, c1 = run_capture [ "git"; "-C"; gate_root; "rev-parse"; "--is-inside-work-tree" ] in
  if c1 <> 0 || inside <> "true" then false
  else
    run_status [ "git"; "-C"; gate_root; "ls-files"; "--error-unmatch"; "--";
                 Layout.engine_src; "bin/bp3" ] <> 0

let detect_legacy_local_skills gate_root =
  if gate_root = "" || not (is_host_git_repo gate_root) then []
  else
    let dirs = [ ".claude/skills"; ".agents/skills"; ".pi/skills" ] in
    List.concat_map (fun rel ->
      let base = Filename.concat gate_root rel in
      if not (Sys.file_exists base && Sys.is_directory base) then []
      else
        let entries =
          try Array.to_list (Sys.readdir base) |> List.sort String.compare
          with _ -> [] in
        List.filter_map (fun name ->
          let rel_path = rel ^ "/" ^ name ^ "/SKILL.md" in
          let skill_md = Filename.concat gate_root rel_path in
          if not (Sys.file_exists skill_md) then None
          else
            let txt = read_file_or skill_md "" in
            if contains_sub txt "<!-- GENERATED from skills/" then Some rel_path
            else None) entries) dirs

let legacy_skills_warning paths =
  `Assoc [
    ("code", json_str Names.w_local_skills_legacy);
    ("files", `List (List.map json_str paths));
    ("message", json_str
      (Printf.sprintf
         "Found %d legacy local generated bp3 skill file(s); skills are now user-global. Run `bp3 skills prune-local` to remove them."
         (List.length paths)));
  ]

(* ---------- the verb ---------- *)
let handle () =
  try
    let raw = read_stdin () in
    let payload =
      try match Yojson.Safe.from_string raw with
        | `Assoc _ as j -> j
        | _ -> raise Not_found
      with _ -> `Assoc [] in
    if payload = `Assoc [] then no_write "unparseable payload"
    else
      let is_agy = member_str payload "conversationId" <> "" in
      let event =
        let e = member_str payload "hook_event_name" in
        if e <> "" then e
        else
          let e2 = member_str payload "hookEventName" in
          if e2 <> "" then e2 else member_str payload "event" in
      let wrap v = if is_agy then agy_reply event else v in
      let session =
        let s = member_str payload "session_id" in
        if s <> "" then s else member_str payload "conversationId" in
      if session = "" then wrap (no_write "no session_id")
      else
        let raw_gate_root = payload_cwd ~fallback:(current_root ()) payload in
        let gate_root = resolve_gate_root raw_gate_root in
        let command = command_of payload in
        let file_path = file_path_of payload in
        let is_reentrant = contains_sub command "bp3 q hooks" in
        if not is_reentrant then begin
          let is_failure = event = "PostToolUseFailure" || member_str payload "error" <> "" in
          let has_refusal = refusal_code payload <> None in
          let harness = harness_of_payload payload in
          update_session_binding ~harness ~gate_root ~sid:session ~event ~command ~file_path ~is_failure ~has_refusal
        end;
        if not (is_bp3_repo gate_root) then begin
          if event = "SessionStart" then
            match detect_legacy_local_skills gate_root with
            | [] -> wrap (no_write "not a bp3 repo")
            | paths ->
                wrap (no_write ~warnings:[ legacy_skills_warning paths ] "not a bp3 repo")
          else wrap (no_write "not a bp3 repo")
        end else begin
          set_root gate_root;
          if is_reentrant
          then wrap (no_write "reentrant")
          else begin
            let bindings = ref (load_registry ()) in
            let find sid = List.find_opt (fun b -> b.session_id = sid) !bindings in
            let finish v = save_registry !bindings; wrap v in
            match event with
            | "PreToolUse" ->
                (match find session with
                 | Some b ->
                     touch b;
                     finish (no_write "already bound")
                 | None ->
                     (match extract_preset command "BP3_RUN_ID",
                            extract_preset command "BP3_QUEST",
                            extract_preset command "BP3_NODE" with
                      | Some run_id, Some q, Some e
                        when valid_slug q && valid_slug e ->
                          let run_dir = Filename.concat (current_root ())
                            (Filename.concat (node_dir q e)
                               (Filename.concat Layout.runs_dir run_id)) in
                          if not (try Sys.is_directory run_dir with _ -> false)
                          then finish (no_write "no matching run folder")
                          else begin
                            let (_edge, cycle) = parse_edge_cycle run_id in
                            let b = { quest = q; node = e; run_id;
                              session_id = session; started_ts = now_ts ();
                              started_epoch = Clock.time ();
                              last_seen_ts = now_ts ();
                              last_seen_epoch = Clock.time (); settled = false;
                              unsettled = false; emitted = [];
                              in_tok = 0; out_tok = 0; cached_tok = 0;
                              reasoning_tok = 0; llm_calls = 0 } in
                            bindings := b :: !bindings;
                            (match emit !bindings b "run_started"
                               [("cycle", `Int cycle);
                                ("session_id", json_str session)]
                               (run_id ^ "|run_started") with
                             | Some line -> finish (verdict line None)
                             | None -> finish (no_write "fact writer refused"))
                          end
                      | _ -> finish (no_write "no binding witnessed for session")))
            | "SessionStart" ->
                let swept = ref None in
                List.iter (fun b ->
                  if b.session_id <> session && not b.settled && not b.unsettled
                     && Clock.stale ~now:(Clock.time ())
                          ~last_seen:b.last_seen_epoch ~stale_after_s then
                    match emit !bindings b "run_unsettled"
                      [("last_seen_ts", json_str b.last_seen_ts)]
                      (b.run_id ^ "|run_unsettled") with
                    | Some line -> begin
                        b.unsettled <- true;
                        if !swept = None then swept := Some line
                      end
                    | None -> ()) !bindings;
                (match find session with
                 | Some b -> touch b
                 | None -> ());
                let warnings =
                  match detect_legacy_local_skills gate_root with
                  | [] -> []
                  | paths -> [ legacy_skills_warning paths ] in
                finish (match !swept with
                  | Some line -> verdict ~warnings line None
                  | None -> no_write ~warnings "no stale bindings")
            | "PostLLMCall" ->
                (match find session with
                 | None -> wrap (no_write "no binding witnessed for session")
                 | Some b ->
                     let usage =
                       try Yojson.Safe.Util.member "usage" payload with _ -> `Null in
                     b.in_tok <- b.in_tok + member_int usage "input_tokens";
                     b.out_tok <- b.out_tok + member_int usage "output_tokens";
                     b.cached_tok <- b.cached_tok +
                       (let c = member_int usage "cached_tokens" in
                        if c <> 0 then c else member_int usage "cache_read_tokens");
                     b.reasoning_tok <- b.reasoning_tok + member_int usage "reasoning_tokens";
                     b.llm_calls <- b.llm_calls + 1;
                     touch b;
                     finish (no_write "usage tallied"))
            | "PostToolUse" | "PostToolUseFailure" ->
                (match find session with
                 | None -> wrap (no_write "no binding witnessed for session")
                 | Some b ->
                     touch b;
                     let failure = event = "PostToolUseFailure" || member_str payload "error" <> "" in
                     let is_update =
                       contains_sub command "bp3" &&
                       attempted_edge command <> None in
                     let refused =
                       if is_update then
                         match refusal_code payload with
                         | Some code -> Some code
                         | None -> None
                       else None in
                     (match refused, attempted_edge command with
                      | Some code, Some attempted ->
                          (match emit !bindings b "refused"
                             [("code", json_str code);
                              ("attempted", json_str attempted)]
                             (b.run_id ^ "|refused|" ^ code ^ "|" ^ attempted) with
                           | Some line -> finish (verdict line None)
                           | None -> finish (no_write "duplicate or unwritable fact"))
                      | _ ->
                          (match lint_check_of command with
                           | Some check ->
                               let result = if failure then "fail" else "pass" in
                               (match emit !bindings b "lint_checked"
                                  [("check", json_str check);
                                   ("result", json_str result)]
                                  (b.run_id ^ "|lint_checked|" ^ check ^ "|" ^ result) with
                                | Some line -> finish (verdict line None)
                                | None -> finish (no_write "duplicate or unwritable fact"))
                           | None -> finish (no_write "nothing to emit"))))
            | "SubagentStop" | "SessionEnd" ->
                (match find session with
                 | None -> wrap (no_write "no binding witnessed for session")
                 | Some b ->
                     if b.settled then finish (no_write "already settled")
                     else begin
                       let settled_ts = now_ts () in
                       let wall_ms =
                         int_of_float ((Clock.time () -. b.started_epoch) *. 1000.) in
                       ignore (emit !bindings b "usage_recorded"
                         [("input_tokens", `Int b.in_tok);
                          ("output_tokens", `Int b.out_tok);
                          ("cached_tokens", `Int b.cached_tok);
                          ("reasoning_tokens", `Int b.reasoning_tok);
                          ("wall_ms", `Int wall_ms);
                          ("started_ts", json_str b.started_ts);
                          ("settled_ts", json_str settled_ts)]
                         (b.run_id ^ "|usage_recorded"));
                       (match emit !bindings b "run_settled"
                          [("outcome", json_str "settled")]
                          (b.run_id ^ "|run_settled") with
                        | Some line -> b.settled <- true;
                            b.last_seen_ts <- settled_ts;
                            b.last_seen_epoch <- Clock.time ();
                            finish (verdict line None)
                        | None -> finish (no_write "duplicate or unwritable fact"))
                     end)
            | "Stop" ->
                (match find session with
                 | Some b -> touch b;
                     finish (no_write "checkpoint only")
                 | None -> wrap (no_write "no binding witnessed for session"))
            | "SubagentStart" ->
                (match find session with
                 | Some b ->
                     let (_edge, cycle) = parse_edge_cycle b.run_id in
                     (match emit !bindings b "run_started"
                        [("cycle", `Int cycle);
                         ("session_id", json_str session)]
                        (b.run_id ^ "|run_started") with
                      | Some line -> finish (verdict line None)
                      | None -> finish (no_write "already started"))
                 | None -> wrap (no_write "no binding witnessed for session"))
            | _ -> wrap (no_write "unhandled event")
          end
        end
  with _ -> no_write "emitter error"
