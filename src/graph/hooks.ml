(* hooks — the bp3 g hooks emitter. Reads one Muse hook
   event JSON from stdin, self-gates, resolves the witnessed Run
   binding, and appends past-tense event lines to the node ledger
   through the internal fact writer below. Always exits 0:
   fail-open, never blocks a tool, never judges an edge.
   Event lines carry event/ts/run_id and never edge/from/to,
   so the Store fold skips them by construction. *)
open Gitx
open Store

(* ---------- small helpers ---------- *)
let verdict event_line reason =
  `Assoc [("ok", `Bool true); ("event_line", event_line);
          ("reason", (match reason with Some r -> json_str r | None -> `Null))]

let no_write reason = verdict `Null (Some reason)

let read_stdin () =
  let buf = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_string buf (input_line stdin);
       Buffer.add_char buf '\n'
     done
   with End_of_file -> ());
  Buffer.contents buf

let member_str j key =
  try match Yojson.Safe.Util.member key j with `String s -> s | _ -> "" with _ -> ""

let member_int j key =
  try match Yojson.Safe.Util.member key j with `Int n -> n | _ -> 0 with _ -> 0

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
  try match Yojson.Safe.Util.member "tool_input" j with
    | `Assoc _ as ti -> member_str ti "command"
    | _ -> ""
  with _ -> ""

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
  graph : string; node : string; run_id : string; session_id : string;
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
  | _ -> Filename.concat (Filename.concat root ".git") "bp3-run-registry.json"

let binding_to_json b =
  (b.session_id, `Assoc [
    ("graph", json_str b.graph); ("node", json_str b.node);
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
  { graph = member_str j "graph"; node = member_str j "node";
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
    let tmp = path ^ ".tmp" in
    let oc = open_out_bin tmp in
    output_string oc (Yojson.Safe.to_string
      (`Assoc [("sessions", `Assoc (List.map binding_to_json bindings))]));
    close_out oc;
    Sys.rename tmp path
  with _ -> ()

(* A binding is stale only when nothing has touched it for this
   long: a SessionStart from a new session proves nothing about a
   Run that is still live in parallel, so the sweep below must
   not mark fresh bindings run_unsettled. *)
let stale_after_s = 900.

let touch b =
  b.last_seen_ts <- now_ts ();
  b.last_seen_epoch <- Unix.time ()

(* ---------- fact writer: appends one event line to the node
   ledger on its branch. The only ledger door hooks may use;
   it writes no state.yaml because event lines change no state. ---------- *)
let append_event graph node line =
  match ledger_read (node_branch graph node) (node_ledger_path graph node) (legacy_node_ledger_paths graph node) with
  | None -> false
  | Some (tip, text, lpath) ->
      let new_text = (if String.trim text = "" then "" else
        (if text.[String.length text - 1] = '\n' then text else text ^ "\n"))
        ^ line ^ "\n" in
      (try
         ignore (commit_files ~branch:(node_branch graph node) ~base_tip:tip
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
    if append_event b.graph b.node line then begin
      b.emitted <- dedupe_key :: b.emitted;
      Some (`Assoc fields)
    end else None

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
      let event =
        let e = member_str payload "hook_event_name" in
        if e <> "" then e else member_str payload "event" in
      let session = member_str payload "session_id" in
      if session = "" then no_write "no session_id"
      else
        let cwd_field = member_str payload "cwd" in
        let gate_root = if cwd_field <> "" then cwd_field else root in
        let is_repo =
          Sys.file_exists (Filename.concat gate_root "bin/bp3") &&
          List.exists (fun r ->
              try Sys.is_directory (Filename.concat gate_root r) with _ -> false)
            (Layout.quests_root :: Layout.legacy_quests_roots) in
        if not is_repo then no_write "not a bp3 repo"
        else
          let command = command_of payload in
          if contains_sub command "bp3 g hooks" ||
             contains_sub command "bp3 g hooks"
          then no_write "reentrant"
          else begin
            let bindings = ref (load_registry ()) in
            let find sid = List.find_opt (fun b -> b.session_id = sid) !bindings in
            let finish v = save_registry !bindings; v in
            match event with
            | "PreToolUse" ->
                (match find session with
                 | Some b ->
                     touch b;
                     finish (no_write "already bound")
                 | None ->
                     (match extract_preset command "BP3_RUN_ID",
                            extract_preset command "BP3_GRAPH",
                            extract_preset command "BP3_NODE" with
                      | Some run_id, Some q, Some e
                        when valid_slug q && valid_slug e ->
                          let run_dir = Filename.concat root
                            (Filename.concat (node_dir q e)
                               (Filename.concat Layout.runs_dir run_id)) in
                          if not (try Sys.is_directory run_dir with _ -> false)
                          then finish (no_write "no matching run folder")
                          else begin
                            let (_edge, cycle) = parse_edge_cycle run_id in
                            let b = { graph = q; node = e; run_id;
                              session_id = session; started_ts = now_ts ();
                              started_epoch = Unix.time ();
                              last_seen_ts = now_ts ();
                              last_seen_epoch = Unix.time (); settled = false;
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
                     && Unix.time () -. b.last_seen_epoch > stale_after_s then
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
                finish (match !swept with
                  | Some line -> verdict line None
                  | None -> no_write "no stale bindings")
            | "PostLLMCall" ->
                (match find session with
                 | None -> no_write "no binding witnessed for session"
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
                 | None -> no_write "no binding witnessed for session"
                 | Some b ->
                     touch b;
                     let failure = event = "PostToolUseFailure" in
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
                 | None -> no_write "no binding witnessed for session"
                 | Some b ->
                     if b.settled then finish (no_write "already settled")
                     else begin
                       let settled_ts = now_ts () in
                       let wall_ms =
                         int_of_float ((Unix.time () -. b.started_epoch) *. 1000.) in
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
                            b.last_seen_epoch <- Unix.time ();
                            finish (verdict line None)
                        | None -> finish (no_write "duplicate or unwritable fact"))
                     end)
            | "Stop" ->
                (match find session with
                 | Some b -> touch b;
                     finish (no_write "checkpoint only")
                 | None -> no_write "no binding witnessed for session")
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
                 | None -> no_write "no binding witnessed for session")
            | _ -> no_write "unhandled event"
          end
  with _ -> no_write "emitter error"
