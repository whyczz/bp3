(* pi sessions (pi-metrics reader.1): one JSONL file per session, a
   `session` header then entries in a tree (id/parentId). Read into the
   shared Tx.cost record so a pi grade is measured like any other
   harness. Pure: text in, facts out. *)

(* One usage-bearing entry: an assistant message, a `usage` entry, a
   compaction or branch summary, or a tool result with nested model work.
   All of them count toward pi's own session totals. *)
type entry = { e_id : string; e_ts : string; e_model : string; e_usage : Tx.usage; e_assistant : bool }

type tx = {
  session : string;        (* the header's id; "" when the file has no header *)
  cwd : string;
  first_prompt : string;   (* the first user message's text: matched against, never stored *)
  first_ts : string;
  last_ts : string;
  entries : entry list;    (* file order *)
  tool_calls : string list;    (* toolCall ids, first-seen order *)
  tool_results : string list;  (* toolResult toolCallIds *)
  tool_spans : (float * float) list;   (* [toolCall entry, toolResult entry) per paired call (measure.1) *)
  tool_events : Tx.tool_event list;
  s_user_steps : (int * float) list;   (* (line_1based, epoch_s) of role=user messages *)
  tool_errors : int;
  skipped_lines : int;     (* not JSON, or JSON that is not an object *)
  bad_usage : int;         (* usage lacking a count, or whose totalTokens is not their sum *)
}

let member = Tx.member
let str = Tx.str
let int_of = Tx.int_of

(* All four counts and the total, and the total adds up: `reasoning` is
   already in output and cacheWrite1h inside cacheWrite, so neither is
   added (message-types.md). *)
let usage_of j =
  match int_of "input" j, int_of "output" j, int_of "cacheRead" j, int_of "cacheWrite" j, int_of "totalTokens" j with
  | Some input, Some output, Some cache_read, Some cache_write, Some total
    when input + output + cache_read + cache_write = total ->
      Some { Tx.input; output; cache_read; cache_write }
  | _ -> None

let text_of content =
  match content with
  | `String s -> s
  | `List blocks -> String.concat "" (List.filter_map (fun b ->
      if str "type" b = "text" then (match member "text" b with `String s -> Some s | _ -> None) else None) blocks)
  | _ -> ""

let parse text =
  let session = ref "" and cwd = ref "" and first_prompt = ref "" and first_ts = ref "" and last_ts = ref "" in
  let entries = ref [] and calls = ref [] and results = ref [] and skipped = ref 0 and bad = ref 0 in
  let seen_call = Hashtbl.create 64 and call_meta = Hashtbl.create 64 in
  let uses = ref [] and results_at = ref [] and events = ref [] and user_steps = ref [] and tool_errors = ref 0 in
  let add_usage ~assistant ~model j u_json =
    match usage_of u_json with
    | Some u -> entries := { e_id = str "id" j; e_ts = str "timestamp" j; e_model = model; e_usage = u;
                             e_assistant = assistant } :: !entries
    | None -> incr bad in
  List.iteri (fun line_idx line ->
      if String.trim line <> "" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some (`Assoc _ as j) ->
            let ts = str "timestamp" j in
            if ts <> "" && str "type" j <> "session" then last_ts := ts;
            (match str "type" j with
             | "session" -> session := str "id" j; cwd := str "cwd" j
             | "message" ->
                 let m = member "message" j in
                 (match str "role" m with
                  | "user" ->
                      let txt = text_of (member "content" m) in
                      if !first_ts = "" then begin first_prompt := txt; first_ts := ts end;
                      (match Tx.seconds ts with
                       | Some at when String.trim txt <> "" -> user_steps := (line_idx + 1, at) :: !user_steps
                       | _ -> ())
                  | "assistant" ->
                      (* an assistant message always carries usage: none is a bad read *)
                      add_usage ~assistant:true ~model:(str "model" m) j (member "usage" m);
                      (match member "content" m with
                       | `List blocks -> List.iter (fun b ->
                           if str "type" b = "toolCall" then
                             let id = str "id" b in
                             if id <> "" && not (Hashtbl.mem seen_call id) then begin
                               Hashtbl.replace seen_call id (); calls := id :: !calls;
                               let name = str "name" b in
                               let cmd = str "command" (member "arguments" b) in
                               let start_s = Option.value (Tx.seconds ts) ~default:0. in
                               Hashtbl.replace call_meta id (name, cmd, start_s, line_idx + 1);
                               (match Tx.seconds ts with Some at -> uses := (id, at) :: !uses | None -> ()) end) blocks
                       | _ -> ())
                  | "toolResult" ->
                      let cid = str "toolCallId" m in
                      let is_err = Tx.bool_of "isError" m in
                      if is_err then incr tool_errors;
                      results := cid :: !results;
                      let end_at = Tx.seconds ts in
                      (match end_at with Some at -> results_at := (cid, at) :: !results_at | None -> ());
                      (match Hashtbl.find_opt call_meta cid with
                       | Some (name, cmd, start_s, step) ->
                           events := { Tx.te_name = name; te_cmd_head = Tx.cmd_head cmd;
                                       te_error = is_err; te_start = start_s;
                                       te_end = Option.value end_at ~default:start_s; te_step = step } :: !events
                       | None -> ());
                      if member "usage" m <> `Null then add_usage ~assistant:false ~model:"" j (member "usage" m)
                  | _ -> ())
             | _ ->
                 (* usage, compaction, branch_summary: usage when present *)
                 if member "usage" j <> `Null then add_usage ~assistant:false ~model:(str "model" j) j (member "usage" j))
        | _ -> incr skipped)
    (String.split_on_char '\n' text);
  { session = !session; cwd = !cwd; first_prompt = !first_prompt; first_ts = !first_ts; last_ts = !last_ts;
    entries = List.rev !entries; tool_calls = List.rev !calls; tool_results = List.rev !results;
    tool_spans = Tx.paired (List.rev !uses) (List.rev !results_at);
    tool_events = List.rev !events; s_user_steps = List.rev !user_steps; tool_errors = !tool_errors;
    skipped_lines = !skipped; bad_usage = !bad }

(* The read agrees with itself: every usage line added up, and every
   tool call has its result. Wall time has no check (QUEST.md). *)
let self_checks tx =
  tx.bad_usage = 0 && List.for_all (fun c -> List.mem c tx.tool_results) tx.tool_calls

(* Tx.cost's meaning, field by field: wall is the span from the
   first user message to the last entry; context_end and model come from
   the last assistant message. *)
let cost tx =
  let sum f = List.fold_left (fun acc e -> acc + f e.e_usage) 0 tx.entries in
  let last = List.find_opt (fun e -> e.e_assistant) (List.rev tx.entries) in
  let turns = List.length (List.filter (fun e -> e.e_assistant) tx.entries) in
  let wall = match Tx.seconds tx.first_ts, Tx.seconds tx.last_ts with
    | Some a, Some b -> Float.round ((b -. a) *. 1000.) /. 1000. | _ -> 0. in
  { Tx.wall_s = wall; tool_calls = List.length tx.tool_calls;
    context_end = (match last with
        | Some e -> e.e_usage.input + e.e_usage.cache_read + e.e_usage.cache_write + e.e_usage.output
        | None -> 0);
    tokens_in = sum (fun u -> u.input); tokens_out = sum (fun u -> u.output);
    tokens_cache_read = sum (fun u -> u.cache_read); tokens_cache_write = sum (fun u -> u.cache_write);
    model = (match last with
        | Some e -> if Metrics.model_ok e.e_model then e.e_model else "other"
        | None -> "unknown");
    tool_s = Tx.ms (Tx.measure tx.tool_spans);
    tool_errors = tx.tool_errors;
    turns }

(* ---------- full-session human interactions & step query (warden-planned-gates session.1) ---------- *)

let parse_interactions text =
  let turns = ref [] in
  let last_agent = ref "" in
  let recent_edges = ref [] in
  let add_edge e =
    if not (List.mem e !recent_edges) then recent_edges := !recent_edges @ [ e ] in
  List.iteri (fun line_idx line ->
      if String.trim line <> "" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some (`Assoc _ as j) when str "type" j = "message" ->
            let ts = str "timestamp" j in
            let step = line_idx + 1 in
            let m = member "message" j in
            (match str "role" m with
             | "user" ->
                 let txt = String.trim (text_of (member "content" m)) in
                 if txt <> "" then begin
                   let at = Option.value (Tx.seconds ts) ~default:0. in
                   turns := {
                     Tx.ht_step = step; ht_ts = at; ht_iso = ts;
                     ht_source = "user_input";
                     ht_agent_asked = Tx.clip ~max_chars:300 !last_agent;
                     ht_human_said = Tx.clip ~max_chars:1000 txt;
                     ht_nearby_edges = !recent_edges;
                   } :: !turns;
                   recent_edges := []
                 end
             | "assistant" ->
                 let content = member "content" m in
                 let txt = String.trim (text_of content) in
                 if txt <> "" then last_agent := txt;
                 (match content with
                  | `List blocks ->
                      List.iter (fun b ->
                          if str "type" b = "toolCall" then
                            let cmd = str "command" (member "arguments" b) in
                            match Tx.extract_edge_tag cmd with Some e -> add_edge e | None -> ()) blocks
                  | _ -> ())
             | _ -> ())
        | _ -> ())
    (String.split_on_char '\n' text);
  List.rev !turns

let query_window ~around ~window text =
  let steps = ref [] in
  List.iteri (fun line_idx line ->
      if String.trim line <> "" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some (`Assoc _ as j) when str "type" j = "message" ->
            let ts = str "timestamp" j in
            let step = line_idx + 1 in
            let m = member "message" j in
            let content = member "content" m in
            let (role, raw_text) = match str "role" m with
              | "user" -> ("user", text_of content)
              | "assistant" ->
                  let txt = text_of content in
                  if String.trim txt <> "" then ("assistant", txt)
                  else
                    let calls = match content with
                      | `List blocks ->
                          blocks
                          |> List.filter_map (fun b ->
                                 if str "type" b = "toolCall" then Some (str "name" b) else None)
                          |> String.concat ", "
                      | _ -> "" in
                    ("tool_call", calls)
              | "toolResult" -> ("tool_result", text_of content)
              | _ -> ("system", text_of content) in
            steps := { Tx.qs_step = step; qs_ts = ts; qs_role = role;
                       qs_text = Tx.clip ~max_chars:2000 raw_text } :: !steps
        | _ -> ())
    (String.split_on_char '\n' text);
  Tx.filter_window ~around ~window (List.rev !steps)
