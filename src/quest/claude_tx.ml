(* Claude Code transcripts (metric-collectors scrape.1, scrape.2): one
   JSONL file per session or subagent, read into the few facts the
   scrapers count. The format is the harness's, not a published
   contract, so a count is cross-checked against the harness report
   before it is trusted (QUEST.md R1). Pure: text in, facts out. *)

type usage = Tx.usage = { input : int; output : int; cache_read : int; cache_write : int }
type msg = { id : string; ts : string; model : string; usage : usage; sidechain : bool }

type tx = {
  session : string;       (* "" when the file never names one *)
  agent : string;         (* "" for a main session *)
  first_prompt : string;  (* matched against, never stored *)
  first_ts : string;
  last_ts : string;
  msgs : msg list;        (* one per message.id, last snapshot, first-seen order *)
  tool_use_ids : string list;
  tool_spans : (float * float) list;   (* [tool_use, tool_result) per paired call, epoch seconds *)
  tool_events : Tx.tool_event list;
  s_user_steps : (int * float) list;   (* (line_1based, epoch_s) of human prompt lines *)
  tool_errors : int;
  skipped_lines : int;    (* not JSON, or an assistant line with no message.id or bad usage *)
  bad_usage : int;        (* assistant lines whose usage lacks one of its four counts *)
}

let seconds = Tx.seconds
let merge = Tx.merge
let measure = Tx.measure
let inter = Tx.inter
let ms = Tx.ms
let paired = Tx.paired
let member = Tx.member
let str = Tx.str

(* All four counts or nothing: a renamed or missing key is never read
   as 0, or a format change would pass as a cheap grade (QUEST.md R1). *)
let usage_of j =
  let int_of k = match j with
    | `Assoc fields -> (match List.assoc_opt k fields with Some (`Int i) -> Some i | _ -> None)
    | _ -> None in
  match int_of "input_tokens", int_of "output_tokens",
        int_of "cache_read_input_tokens", int_of "cache_creation_input_tokens" with
  | Some input, Some output, Some cache_read, Some cache_write -> Some { input; output; cache_read; cache_write }
  | _ -> None

let prompt_text content =
  match content with
  | `String s -> s
  | `List blocks ->
      String.concat "\n" (List.filter_map (fun b -> match member "text" b with
          | `String s -> Some s | _ -> None) blocks)
  | _ -> ""

let is_human_user content j =
  if Tx.bool_of "isMeta" j then false
  else
    let has_tool_result = match content with
      | `List blocks -> List.exists (fun b -> str "type" b = "tool_result") blocks
      | _ -> false in
    if has_tool_result then false
    else
      let txt = String.trim (prompt_text content) in
      txt <> ""
      && not (String.starts_with ~prefix:"<task-notification>" txt)
      && not (String.starts_with ~prefix:"<local-command" txt)
      && not (String.starts_with ~prefix:"<command-name>" txt)

(* ~until (epoch seconds) reads only the lines stamped at or before it:
   the part of a transcript a harness report covers. *)
let parse ?until text =
  let order = ref [] and by_id = Hashtbl.create 64 and tools = Hashtbl.create 64 in
  let call_meta = Hashtbl.create 64 and events = ref [] and user_steps = ref [] and tool_errors = ref 0 in
  let tool_order = ref [] and skipped = ref 0 and bad_usage = ref 0 in
  let uses = ref [] and results = ref [] in
  let session = ref "" and agent = ref "" and prompt = ref None in
  let first_ts = ref "" and last_ts = ref "" in
  let late ts = match until, seconds ts with Some u, Some s -> s > u | _ -> false in
  List.iteri (fun line_idx line ->
      if String.trim line <> "" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some (`Assoc _ as j) when late (str "timestamp" j) -> ()
        | Some (`Assoc _ as j) ->
            let ts = str "timestamp" j in
            if ts <> "" then begin
              if !first_ts = "" then first_ts := ts;
              last_ts := ts
            end;
            if !session = "" then session := str "sessionId" j;
            if !agent = "" then agent := str "agentId" j;
            let message = member "message" j in
            (match str "type" j with
             | "user" ->
                 let content = member "content" message in
                 if !prompt = None then prompt := Some (prompt_text content);
                 (match seconds ts with
                  | Some at when is_human_user content j -> user_steps := (line_idx + 1, at) :: !user_steps
                  | _ -> ());
                 (match content, seconds ts with
                  | `List blocks, Some at ->
                      List.iter (fun b -> if str "type" b = "tool_result" then begin
                                    let tid = str "tool_use_id" b in
                                    let is_err = Tx.bool_of "is_error" b in
                                    if is_err then incr tool_errors;
                                    results := (tid, at) :: !results;
                                    (match Hashtbl.find_opt call_meta tid with
                                     | Some (name, cmd, start_s, step) ->
                                         events := { Tx.te_name = name; te_cmd_head = Tx.cmd_head cmd;
                                                     te_error = is_err; te_start = start_s;
                                                     te_end = at; te_step = step } :: !events
                                     | None -> ()) end) blocks
                  | _ -> ())
             | "assistant" ->
                 let id = str "id" message in
                 let usage = usage_of (member "usage" message) in
                 if id = "" then incr skipped
                 else if usage = None then begin incr skipped; incr bad_usage end
                 else begin
                   if not (Hashtbl.mem by_id id) then order := id :: !order;
                   Hashtbl.replace by_id id
                     { id; ts; model = str "model" message; usage = Option.get usage;
                       sidechain = (match member "isSidechain" j with `Bool b -> b | _ -> false) };
                   (match member "content" message with
                    | `List blocks ->
                        List.iter (fun b ->
                            if str "type" b = "tool_use" then
                              let tid = str "id" b in
                              if tid <> "" && not (Hashtbl.mem tools tid) then begin
                                Hashtbl.replace tools tid (); tool_order := tid :: !tool_order;
                                let name = str "name" b in
                                let cmd = str "command" (member "input" b) in
                                let start_s = Option.value (seconds ts) ~default:0. in
                                Hashtbl.replace call_meta tid (name, cmd, start_s, line_idx + 1);
                                (match seconds ts with Some at -> uses := (tid, at) :: !uses | None -> ()) end) blocks
                    | _ -> ())
                 end
             | _ -> ())
        | _ -> incr skipped)
    (String.split_on_char '\n' text);
  { session = !session; agent = !agent;
    first_prompt = (match !prompt with Some p -> p | None -> "");
    first_ts = !first_ts; last_ts = !last_ts;
    msgs = List.rev_map (Hashtbl.find by_id) !order;
    tool_use_ids = List.rev !tool_order; tool_spans = paired (List.rev !uses) (List.rev !results);
    tool_events = List.rev !events; s_user_steps = List.rev !user_steps; tool_errors = !tool_errors;
    skipped_lines = !skipped; bad_usage = !bad_usage }

(* The .meta.json beside a subagent transcript names the parent's
   tool call that spawned it: the join key to the harness report. *)
let meta_tool_use_id text =
  match (try Some (Yojson.Safe.from_string text) with _ -> None) with
  | Some j -> (match str "toolUseId" j with "" -> None | s -> Some s)
  | None -> None

type cost = Tx.cost = {
  wall_s : float; tool_calls : int; context_end : int;
  tokens_in : int; tokens_out : int; tokens_cache_read : int; tokens_cache_write : int;
  model : string;
  tool_s : float;   (* union of the paired tool spans (measure.1) *)
  tool_errors : int;
  turns : int;
}

let real_model m = m <> "" && m.[0] <> '<'   (* "<synthetic>" carries no spend *)

(* context_end and model come from the last real message: a synthetic
   one carries zero usage and no model, and the harness report's
   subagent_tokens is the context of the last real call. *)
let cost tx =
  let sum f = List.fold_left (fun acc m -> acc + f m.usage) 0 tx.msgs in
  let last = List.find_opt (fun (m : msg) -> real_model m.model) (List.rev tx.msgs) in
  let wall = match seconds tx.first_ts, seconds tx.last_ts with
    | Some a, Some b -> Float.round ((b -. a) *. 1000.) /. 1000. | _ -> 0. in
  { wall_s = wall; tool_calls = List.length tx.tool_use_ids;
    context_end = (match last with
        | Some m -> m.usage.input + m.usage.cache_read + m.usage.cache_write + m.usage.output
        | None -> 0);
    tokens_in = sum (fun u -> u.input); tokens_out = sum (fun u -> u.output);
    tokens_cache_read = sum (fun u -> u.cache_read); tokens_cache_write = sum (fun u -> u.cache_write);
    model = (match last with
        | Some m -> if Metrics.model_ok m.model then m.model else "other"
        | None -> "unknown");
    tool_s = ms (measure tx.tool_spans);
    tool_errors = tx.tool_errors;
    turns = List.length tx.msgs }

let find_from = Tx.find_from
let contains = Tx.contains
let prompt_names_grade = Tx.prompt_names_grade
let span_in_window = Tx.span_in_window
let join_line_names = Tx.join_line_names

let names_grade tx ~node ~commit = prompt_names_grade tx.first_prompt ~node ~commit

let in_window tx ~handed_at ~graded_at =
  span_in_window ~first_ts:tx.first_ts ~last_ts:tx.last_ts ~handed_at ~graded_at

(* The harness report (scrape.1): each time a subagent stops, the
   harness queues a <task-notification> to the parent session with a
   <usage> block, keyed by <task-id> (the agent id) and, on the first
   stop, the spawning call's <tool-use-id>. It is read from
   queue-operation enqueue lines only: the parent's own messages may
   quote the same text, and quoting is not reporting. Under each key
   the last report wins: a subagent resumed by a follow-up stops again
   and its later report covers the whole transcript. r_at is when the
   report was queued; the report covers the lines up to r_at. *)
type report = { r_at : string; r_tool_uses : int; r_duration_ms : int; r_subagent_tokens : int }

let tag name s =
  let o = "<" ^ name ^ ">" and c = "</" ^ name ^ ">" in
  match find_from s 0 o with
  | None -> None
  | Some i ->
      let start = i + String.length o in
      (match find_from s start c with
       | Some j -> Some (String.sub s start (j - start))
       | None -> None)

let reports_of_text text =
  let found = Hashtbl.create 16 and order = ref [] in
  List.iter (fun line ->
      if contains line "\"queue-operation\"" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some j when str "type" j = "queue-operation" && str "operation" j = "enqueue" ->
            let c = str "content" j in
            let num t = match tag t c with Some v -> int_of_string_opt (String.trim v) | None -> None in
            (match num "tool_uses", num "duration_ms", num "subagent_tokens" with
             | Some tu, Some ms, Some st ->
                 let r = { r_at = str "timestamp" j; r_tool_uses = tu; r_duration_ms = ms; r_subagent_tokens = st } in
                 List.iter (fun key -> match tag key c with
                     | Some id ->
                         if not (Hashtbl.mem found id) then order := id :: !order;
                         Hashtbl.replace found id r
                     | None -> ()) [ "task-id"; "tool-use-id" ]
             | _ -> ())
        | _ -> ())
    (String.split_on_char '\n' text);
  List.rev_map (fun id -> (id, Hashtbl.find found id)) !order

(* c is the cost of the transcript cut at r_at (parse ~until). It
   agrees when the tool calls match exactly, the wall is within a
   second, and the end context is at most 1% under the report's,
   never over: the transcript can log a final message's output only
   partially (4 of 43 reports, 2026-11-21: 62 to 1009 tokens short,
   at most 0.74%), but it never logs more than the harness counted. *)
let agrees (c : cost) r =
  let short = r.r_subagent_tokens - c.context_end in
  c.tool_calls = r.r_tool_uses && short >= 0 && short * 100 <= r.r_subagent_tokens
  && Float.abs (c.wall_s -. (float_of_int r.r_duration_ms /. 1000.)) <= 1.

(* A cut transcript checks out when no usage line in it was unreadable
   and its cost agrees with the report. *)
let checks (cut : tx) r = cut.bad_usage = 0 && agrees (cost cut) r

(* ---------- main sessions (scrape.2) ---------- *)

(* A main session file is the author's side: its own messages (not a
   subagent's: those live in their own files), the Bash calls it made,
   and the results of calls that moved a node to handed_off. Only
   assistant lines and tool results are parsed; the file is tens of MB. *)
type call = { call_id : string; call_ts : string; command : string }
type session = {
  s_id : string;
  s_msgs : msg list;                  (* one per message.id, last snapshot; main thread only *)
  s_tools : (string * string) list;   (* tool_use id, ts of the line that first holds it *)
  s_bash : call list;
  s_results : (string * string) list; (* tool_use_id, result text, for results naming handed_off *)
  s_bad_at : string list;            (* stamps of usage-less lines, main thread; a window holding one writes nothing *)
  s_marks : (float * bool) list;     (* main-thread assistant and tool-result lines: stamp, ends a turn (measure.1) *)
  s_results_at : (string * float) list;  (* tool_use_id, stamp of its result *)
  s_events : Tx.tool_event list;
  s_user_steps : (int * float) list;     (* (line_1based, epoch_s) of human prompt lines *)
}

let result_text content =
  match content with
  | `String s -> s
  | `List blocks -> String.concat "" (List.filter_map (fun b -> match member "text" b with
      | `String s -> Some s | _ -> None) blocks)
  | _ -> ""

let parse_session text =
  let order = ref [] and by_id = Hashtbl.create 256 and tools = Hashtbl.create 256 in
  let call_meta = Hashtbl.create 256 and events = ref [] and user_steps = ref [] in
  let tool_order = ref [] and bash = ref [] and results = ref [] and bad = ref [] and sid = ref "" in
  let marks = ref [] and results_at = ref [] in
  List.iteri (fun line_idx line ->
      if contains line "\"type\":\"assistant\"" || contains line "\"tool_result\"" || contains line "\"type\":\"user\"" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some (`Assoc _ as j) when (match member "isSidechain" j with `Bool b -> b | _ -> false) -> ()
        | Some (`Assoc _ as j) ->
            let ts = str "timestamp" j in
            if !sid = "" then sid := str "sessionId" j;
            let message = member "message" j in
            let blocks = match member "content" message with `List bs -> bs | _ -> [] in
            (match str "type" j with
             | "assistant" ->
                 let id = str "id" message in
                 (match seconds ts with
                  | Some at -> marks := (at, str "stop_reason" message = "end_turn") :: !marks
                  | None -> ());
                 (match usage_of (member "usage" message) with
                  | _ when id = "" -> ()
                  | None -> bad := ts :: !bad
                  | Some usage ->
                      if not (Hashtbl.mem by_id id) then order := id :: !order;
                      Hashtbl.replace by_id id { id; ts; model = str "model" message; usage; sidechain = false });
                 List.iter (fun b ->
                     if str "type" b = "tool_use" then begin
                       let tid = str "id" b in
                       let name = str "name" b in
                       let cmd = str "command" (member "input" b) in
                       if tid <> "" && not (Hashtbl.mem tools tid) then begin
                         Hashtbl.replace tools tid (); tool_order := (tid, ts) :: !tool_order;
                         let start_s = Option.value (seconds ts) ~default:0. in
                         Hashtbl.replace call_meta tid (name, cmd, start_s, line_idx + 1) end;
                       if name = "Bash" then
                         bash := { call_id = tid; call_ts = ts; command = cmd } :: !bash
                     end) blocks
             | "user" ->
                 let at = seconds ts in
                 let content = member "content" message in
                 (match at with
                  | Some a when is_human_user content j -> user_steps := (line_idx + 1, a) :: !user_steps
                  | _ -> ());
                 List.iter (fun b ->
                     if str "type" b = "tool_result" then begin
                       let tid = str "tool_use_id" b in
                       let is_err = Tx.bool_of "is_error" b in
                       (match at with
                        | Some a ->
                            marks := (a, false) :: !marks; results_at := (tid, a) :: !results_at;
                            (match Hashtbl.find_opt call_meta tid with
                             | Some (name, cmd, start_s, step) ->
                                 events := { Tx.te_name = name; te_cmd_head = Tx.cmd_head cmd;
                                             te_error = is_err; te_start = start_s;
                                             te_end = a; te_step = step } :: !events
                             | None -> ())
                        | None -> ());
                       let t = result_text (member "content" b) in
                       if contains t "handed_off" then results := (tid, t) :: !results end) blocks
             | _ -> ())
        | _ -> ())
    (String.split_on_char '\n' text);
  { s_id = !sid; s_msgs = List.rev_map (Hashtbl.find by_id) !order; s_tools = List.rev !tool_order;
    s_bash = List.rev !bash; s_results = List.rev !results; s_bad_at = List.rev !bad;
    s_marks = List.stable_sort (fun (a, _) (b, _) -> compare a b) (List.rev !marks);
    s_results_at = List.rev !results_at; s_events = List.rev !events;
    s_user_steps = List.rev !user_steps }

let has_word = Tx.has_word
let shown = Tx.shown
let casts_node = Tx.casts_node

(* The session that cast a handoff made a Bash call that casts this
   quest's node (casts_node), inside that handoff's window
   [from, upto + 1) (a later read is not the cast), with one more piece
   of evidence: the command holds the commit's first 7, or the result
   holds the full commit, or the result is a successful move to
   handed_off. Commands often pass "$(git ...)" and results are often
   cut to {ok, state} (test-pyramid tier.2). If a result shows a quest,
   node or commit, at least one of each must be ours: equal, or a
   prefix of at least 2 when the result was cut. *)
let casts_handoff s ~quest ~node ~commit ~from ~upto =
  let in_window ts = match seconds ts with Some t -> t >= from && t < upto +. 1. | None -> false in
  let ours t key v = match shown t key with
    | [] -> true
    | xs -> List.exists (fun (x, closed) ->
        if closed then x = v
        else String.length x >= 2 && String.length x <= String.length v && String.sub v 0 (String.length x) = x) xs in
  let consistent t = ours t "quest" quest && ours t "node" node && ours t "commit" commit in
  let moved t = (contains t "\"state\":\"handed_off\"" || contains t "\"state\": \"handed_off\"")
                && not (contains t "\"ok\":false" || contains t "\"ok\": false") in
  String.length commit >= 7
  && List.exists (fun c ->
         in_window c.call_ts && casts_node c.command ~quest ~node
         && (contains c.command (String.sub commit 0 7)
             || (match List.assoc_opt c.call_id s.s_results with
                 | Some t -> consistent t && (contains t commit || moved t)
                 | None -> false)))
       s.s_bash

(* Author windows of one session, in time order: each message and tool
   call is counted in the first window that holds it, so windows that
   share a boundary second never share spend. A window is (key, from,
   upto) in epoch seconds, holding what is stamped in [from, upto + 1).
   Usage-less lines follow the same rule (usage.1): w_bad counts the
   ones a window holds first, so one bad line fails one window. *)
type window_spend = {
  w_key : string; w_msgs : msg list; w_tools : int; w_errors : int; w_bad : int;
  w_events : Tx.tool_event list; w_user_steps : (int * float) list
}

let assign s windows =
  let taken = Hashtbl.create 256 in
  let inside (_, from, upto) ts = match seconds ts with Some t -> t >= from && t < upto +. 1. | None -> false in
  let inside_f (_, from, upto) t = t >= from && t < upto +. 1. in
  let take k = not (Hashtbl.mem taken k) && (Hashtbl.replace taken k (); true) in
  let non_kickoff = match s.s_user_steps with [] -> [] | _ :: rest -> rest in
  List.map (fun ((key, _, _) as w) ->
      let msgs = List.filter (fun (m : msg) -> inside w m.ts && take ("m" ^ m.id)) s.s_msgs in
      let tools = List.filter (fun (id, ts) -> inside w ts && take ("t" ^ id)) s.s_tools in
      let events = List.filteri (fun i (e : Tx.tool_event) -> inside_f w e.te_start && take ("e" ^ string_of_int i)) s.s_events in
      let usteps = List.filteri (fun i (_, at) -> inside_f w at && take ("u" ^ string_of_int i)) non_kickoff in
      let errors = List.length (List.filter (fun (e : Tx.tool_event) -> e.te_error) events) in
      let bad = List.filteri (fun i ts -> inside w ts && take ("b" ^ string_of_int i)) s.s_bad_at in
      { w_key = key; w_msgs = msgs; w_tools = List.length tools; w_errors = errors;
        w_bad = List.length bad; w_events = events; w_user_steps = usteps })
    windows

let author_cost ?(tool_errors = 0) msgs tool_calls =
  let tx = { session = ""; agent = ""; first_prompt = ""; first_ts = ""; last_ts = ""; msgs;
             tool_use_ids = List.init tool_calls string_of_int; tool_spans = [];
             tool_events = []; s_user_steps = []; tool_errors; skipped_lines = 0; bad_usage = 0 } in
  cost tx

(* An author window's times (induct-inline-as-default measure.1). Wall is
   the ledger span. Active counts only what this session did: the gaps
   between its consecutive lines in the window, skipping a gap that
   starts where a turn ended (the session was waiting, for a human or a
   notification). Before its first line in the window nothing is active:
   another session, or a break. Tool time is the paired calls' spans
   inside the active gaps, so 0 <= tool <= active <= wall. *)
type window_times = { t_wall : float; t_active : float; t_tool : float }

let window_times s ~from ~upto =
  let inside t = t >= from && t < upto +. 1. in
  let marks = List.filter (fun (t, _) -> inside t) s.s_marks in
  let rec gaps = function
    | (a, ended) :: ((b, _) :: _ as rest) -> if ended then gaps rest else (a, b) :: gaps rest
    | _ -> [] in
  let present = inter (gaps marks) [ (from, upto) ] in
  let uses = List.filter_map (fun (id, ts) -> match seconds ts with
      | Some u when inside u -> Some (id, u) | _ -> None) s.s_tools in
  { t_wall = Float.max 0. (upto -. from);
    t_active = ms (measure present);
    t_tool = ms (measure (inter (paired uses s.s_results_at) present)) }
