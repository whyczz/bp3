(* Claude Code transcripts (metric-collectors scrape.1, scrape.2): one
   JSONL file per session or subagent, read into the few facts the
   scrapers count. The format is the harness's, not a published
   contract, so a count is cross-checked against the harness report
   before it is trusted (QUEST.md R1). Pure: text in, facts out. *)

type usage = { input : int; output : int; cache_read : int; cache_write : int }
type msg = { id : string; ts : string; model : string; usage : usage; sidechain : bool }

type tx = {
  session : string;       (* "" when the file never names one *)
  agent : string;         (* "" for a main session *)
  first_prompt : string;  (* matched against, never stored *)
  first_ts : string;
  last_ts : string;
  msgs : msg list;        (* one per message.id, last snapshot, first-seen order *)
  tool_use_ids : string list;
  skipped_lines : int;    (* not JSON, or an assistant line with no message.id or bad usage *)
  bad_usage : int;        (* assistant lines whose usage lacks one of its four counts *)
}

(* Milliseconds matter: a grade's wall is the span of its lines. *)
let seconds ts =
  if String.length ts < 20 then None
  else
    match Harness.epoch_of_iso (String.sub ts 0 19 ^ "Z") with
    | None -> None
    | Some s ->
        let frac = String.sub ts 19 (String.length ts - 19) in
        if frac = "Z" then Some s
        else if String.length frac >= 3 && frac.[0] = '.' && frac.[String.length frac - 1] = 'Z' then
          (match float_of_string_opt ("0" ^ String.sub frac 0 (String.length frac - 1)) with
           | Some f -> Some (s +. f)
           | None -> None)
        else None

(* Total field access: a line of an unexpected shape (a null message, a
   list) reads as absent fields, never as an exception that kills the
   whole scrape. *)
let member k j = match j with `Assoc fs -> (match List.assoc_opt k fs with Some v -> v | None -> `Null) | _ -> `Null
let str k j = match member k j with `String s -> s | _ -> ""

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

(* ~until (epoch seconds) reads only the lines stamped at or before it:
   the part of a transcript a harness report covers. *)
let parse ?until text =
  let order = ref [] and by_id = Hashtbl.create 64 and tools = Hashtbl.create 64 in
  let tool_order = ref [] and skipped = ref 0 and bad_usage = ref 0 in
  let session = ref "" and agent = ref "" and prompt = ref None in
  let first_ts = ref "" and last_ts = ref "" in
  let late ts = match until, seconds ts with Some u, Some s -> s > u | _ -> false in
  List.iter (fun line ->
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
             | "user" when !prompt = None ->
                 prompt := Some (prompt_text (member "content" message))
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
                                Hashtbl.replace tools tid (); tool_order := tid :: !tool_order end) blocks
                    | _ -> ())
                 end
             | _ -> ())
        | _ -> incr skipped)
    (String.split_on_char '\n' text);
  { session = !session; agent = !agent;
    first_prompt = (match !prompt with Some p -> p | None -> "");
    first_ts = !first_ts; last_ts = !last_ts;
    msgs = List.rev_map (Hashtbl.find by_id) !order;
    tool_use_ids = List.rev !tool_order; skipped_lines = !skipped; bad_usage = !bad_usage }

(* The .meta.json beside a subagent transcript names the parent's
   tool call that spawned it: the join key to the harness report. *)
let meta_tool_use_id text =
  match (try Some (Yojson.Safe.from_string text) with _ -> None) with
  | Some j -> (match str "toolUseId" j with "" -> None | s -> Some s)
  | None -> None

type cost = {
  wall_s : float; tool_calls : int; context_end : int;
  tokens_in : int; tokens_out : int; tokens_cache_read : int; tokens_cache_write : int;
  model : string;
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
        | None -> "unknown") }

(* A grade transcript names its node and the graded commit in its
   first prompt (past briefs already did), and runs inside the
   handoff-to-grade window. Ledger times are whole seconds, so the
   window closes one second after the grade's stamp. *)
(* No allocation per position: session files are tens of MB. *)
let find_from s i sub =
  let n = String.length sub and m = String.length s in
  let rec at i k = k = n || (s.[i + k] = sub.[k] && at i (k + 1)) in
  let rec go i = if i + n > m then None else if at i 0 then Some i else go (i + 1) in
  if n = 0 then None else go i

let contains s sub = find_from s 0 sub <> None

let names_grade tx ~node ~commit =
  String.length commit >= 7 && contains tx.first_prompt node && contains tx.first_prompt (String.sub commit 0 7)

let in_window tx ~handed_at ~graded_at =
  match seconds tx.first_ts, seconds tx.last_ts, seconds handed_at, seconds graded_at with
  | Some a, Some b, Some h, Some g -> a >= h && b < g +. 1.
  | _ -> false

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
  s_bad_usage : int;
}

let result_text content =
  match content with
  | `String s -> s
  | `List blocks -> String.concat "" (List.filter_map (fun b -> match member "text" b with
      | `String s -> Some s | _ -> None) blocks)
  | _ -> ""

let parse_session text =
  let order = ref [] and by_id = Hashtbl.create 256 and tools = Hashtbl.create 256 in
  let tool_order = ref [] and bash = ref [] and results = ref [] and bad = ref 0 and sid = ref "" in
  List.iter (fun line ->
      if contains line "\"type\":\"assistant\"" || (contains line "handed_off" && contains line "tool_result") then
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
                 (match usage_of (member "usage" message) with
                  | _ when id = "" -> ()
                  | None -> incr bad
                  | Some usage ->
                      if not (Hashtbl.mem by_id id) then order := id :: !order;
                      Hashtbl.replace by_id id { id; ts; model = str "model" message; usage; sidechain = false });
                 List.iter (fun b ->
                     if str "type" b = "tool_use" then begin
                       let tid = str "id" b in
                       if tid <> "" && not (Hashtbl.mem tools tid) then begin
                         Hashtbl.replace tools tid (); tool_order := (tid, ts) :: !tool_order end;
                       if str "name" b = "Bash" then
                         bash := { call_id = tid; call_ts = ts;
                                   command = str "command" (member "input" b) } :: !bash
                     end) blocks
             | "user" ->
                 List.iter (fun b ->
                     if str "type" b = "tool_result" then
                       let t = result_text (member "content" b) in
                       if contains t "handed_off" then results := (str "tool_use_id" b, t) :: !results) blocks
             | _ -> ())
        | _ -> ())
    (String.split_on_char '\n' text);
  { s_id = !sid; s_msgs = List.rev_map (Hashtbl.find by_id) !order; s_tools = List.rev !tool_order;
    s_bash = List.rev !bash; s_results = List.rev !results; s_bad_usage = !bad }

(* w stands as its own word in s: no id character on either side, so
   node "a" is not found inside "handoff". *)
let has_word s w =
  let id_char c = match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true | _ -> false in
  let n = String.length w and m = String.length s in
  let rec from i = match find_from s i w with
    | None -> false
    | Some j ->
        ((j = 0 || not (id_char s.[j - 1])) && (j + n = m || not (id_char s.[j + n]))) || from (j + 1) in
  n > 0 && from 0

(* The session that cast a handoff made a Bash call naming handoff and
   the node as words, inside that handoff's window [from, upto + 1)
   (a later read that greps the same words is not the cast), with one
   more piece of evidence: the command holds the commit's first 7, or
   the result holds the full commit, or the result is a successful
   move to handed_off. Commands often pass "$(git ...)" and results
   are often cut by jq to {ok, state} (test-pyramid tier.2). *)
let casts_handoff s ~node ~commit ~from ~upto =
  let in_window ts = match seconds ts with Some t -> t >= from && t < upto +. 1. | None -> false in
  (* a result that shows a commit must show ours; 6 hex because one real
     result was cut after six (dc314a) *)
  let ours t = let p = String.sub commit 0 6 in
    not (contains t "\"commit\":") || contains t ("\"commit\":\"" ^ p) || contains t ("\"commit\": \"" ^ p) in
  let moved t = (contains t "\"state\":\"handed_off\"" || contains t "\"state\": \"handed_off\"")
                && not (contains t "\"ok\":false" || contains t "\"ok\": false") && ours t in
  String.length commit >= 7
  && List.exists (fun c ->
         in_window c.call_ts && has_word c.command "handoff" && has_word c.command node
         && (contains c.command (String.sub commit 0 7)
             || (match List.assoc_opt c.call_id s.s_results with
                 | Some t -> contains t commit || moved t
                 | None -> false)))
       s.s_bash

(* Author windows of one session, in time order: each message and tool
   call is counted in the first window that holds it, so windows that
   share a boundary second never share spend. A window is (key, from,
   upto) in epoch seconds, holding what is stamped in [from, upto + 1). *)
let assign s windows =
  let taken = Hashtbl.create 256 in
  let inside (_, from, upto) ts = match seconds ts with Some t -> t >= from && t < upto +. 1. | None -> false in
  List.map (fun ((key, _, _) as w) ->
      let msgs = List.filter (fun (m : msg) ->
          inside w m.ts && not (Hashtbl.mem taken ("m" ^ m.id)) && (Hashtbl.replace taken ("m" ^ m.id) (); true)) s.s_msgs in
      let tools = List.filter (fun (id, ts) ->
          inside w ts && not (Hashtbl.mem taken ("t" ^ id)) && (Hashtbl.replace taken ("t" ^ id) (); true)) s.s_tools in
      (key, msgs, List.length tools))
    windows

let author_cost msgs tool_calls =
  let tx = { session = ""; agent = ""; first_prompt = ""; first_ts = ""; last_ts = ""; msgs;
             tool_use_ids = List.init tool_calls string_of_int; skipped_lines = 0; bad_usage = 0 } in
  cost tx
