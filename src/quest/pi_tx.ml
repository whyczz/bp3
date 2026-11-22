(* pi sessions (pi-metrics reader.1): one JSONL file per session, a
   `session` header then entries in a tree (id/parentId). Read into the
   same cost record a Claude Code transcript gives, so a pi grade is
   measured like a Claude one. pi writes no separate harness report, so
   the read checks itself instead (self_checks). Pure: text in, facts
   out. Format: pi docs session-format.md and message-types.md (1.5.0). *)

(* One usage-bearing entry: an assistant message, a `usage` entry, a
   compaction or branch summary, or a tool result with nested model work.
   All of them count toward pi's own session totals. *)
type entry = { e_id : string; e_ts : string; e_model : string; e_usage : Claude_tx.usage; e_assistant : bool }

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
  skipped_lines : int;     (* not JSON, or JSON that is not an object *)
  bad_usage : int;         (* usage lacking a count, or whose totalTokens is not their sum *)
}

let member = Claude_tx.member
let str = Claude_tx.str
let int_of k j = match member k j with `Int n -> Some n | _ -> None

(* All four counts and the total, and the total adds up: `reasoning` is
   already in output and cacheWrite1h inside cacheWrite, so neither is
   added (message-types.md). *)
let usage_of j =
  match int_of "input" j, int_of "output" j, int_of "cacheRead" j, int_of "cacheWrite" j, int_of "totalTokens" j with
  | Some input, Some output, Some cache_read, Some cache_write, Some total
    when input + output + cache_read + cache_write = total ->
      Some { Claude_tx.input; output; cache_read; cache_write }
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
  let seen_call = Hashtbl.create 64 in
  let uses = ref [] and results_at = ref [] in
  let add_usage ~assistant ~model j u_json =
    match usage_of u_json with
    | Some u -> entries := { e_id = str "id" j; e_ts = str "timestamp" j; e_model = model; e_usage = u;
                             e_assistant = assistant } :: !entries
    | None -> incr bad in
  List.iter (fun line ->
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
                      if !first_ts = "" then begin first_prompt := text_of (member "content" m); first_ts := ts end
                  | "assistant" ->
                      (* an assistant message always carries usage: none is a bad read *)
                      add_usage ~assistant:true ~model:(str "model" m) j (member "usage" m);
                      (match member "content" m with
                       | `List blocks -> List.iter (fun b ->
                           if str "type" b = "toolCall" then
                             let id = str "id" b in
                             if id <> "" && not (Hashtbl.mem seen_call id) then begin
                               Hashtbl.replace seen_call id (); calls := id :: !calls;
                               (match Claude_tx.seconds ts with Some at -> uses := (id, at) :: !uses | None -> ()) end) blocks
                       | _ -> ())
                  | "toolResult" ->
                      results := str "toolCallId" m :: !results;
                      (match Claude_tx.seconds ts with
                       | Some at -> results_at := (str "toolCallId" m, at) :: !results_at | None -> ());
                      if member "usage" m <> `Null then add_usage ~assistant:false ~model:"" j (member "usage" m)
                  | _ -> ())
             | _ ->
                 (* usage, compaction, branch_summary: usage when present *)
                 if member "usage" j <> `Null then add_usage ~assistant:false ~model:(str "model" j) j (member "usage" j))
        | _ -> incr skipped)
    (String.split_on_char '\n' text);
  { session = !session; cwd = !cwd; first_prompt = !first_prompt; first_ts = !first_ts; last_ts = !last_ts;
    entries = List.rev !entries; tool_calls = List.rev !calls; tool_results = List.rev !results;
    tool_spans = Claude_tx.paired (List.rev !uses) (List.rev !results_at);
    skipped_lines = !skipped; bad_usage = !bad }

(* The read agrees with itself: every usage line added up, and every
   tool call has its result. Wall time has no check (QUEST.md). *)
let self_checks tx =
  tx.bad_usage = 0 && List.for_all (fun c -> List.mem c tx.tool_results) tx.tool_calls

(* Claude_tx.cost's meaning, field by field: wall is the span from the
   first user message to the last entry; context_end and model come from
   the last assistant message. *)
let cost tx =
  let sum f = List.fold_left (fun acc e -> acc + f e.e_usage) 0 tx.entries in
  let last = List.find_opt (fun e -> e.e_assistant) (List.rev tx.entries) in
  let wall = match Claude_tx.seconds tx.first_ts, Claude_tx.seconds tx.last_ts with
    | Some a, Some b -> Float.round ((b -. a) *. 1000.) /. 1000. | _ -> 0. in
  { Claude_tx.wall_s = wall; tool_calls = List.length tx.tool_calls;
    context_end = (match last with
        | Some e -> e.e_usage.input + e.e_usage.cache_read + e.e_usage.cache_write + e.e_usage.output
        | None -> 0);
    tokens_in = sum (fun u -> u.input); tokens_out = sum (fun u -> u.output);
    tokens_cache_read = sum (fun u -> u.cache_read); tokens_cache_write = sum (fun u -> u.cache_write);
    model = (match last with
        | Some e -> if Metrics.model_ok e.e_model then e.e_model else "other"
        | None -> "unknown");
    tool_s = Claude_tx.ms (Claude_tx.measure tx.tool_spans) }
