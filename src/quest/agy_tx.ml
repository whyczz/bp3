(* Antigravity CLI (agy) transcripts (fast-agy-induct agy.1): one JSONL
   file per conversation under
   ~/.gemini/antigravity-cli/brain/<conv-id>/.system_generated/logs/transcript.jsonl
   with an optional sibling transcript_full.jsonl for truncated lines.
   Pure: text in, Tx.cost + tool_events + author windows out. *)

type msg = {
  m_step : int;
  m_ts : string;
  m_model : string;
  m_usage : Tx.usage;
  m_has_tools : bool;
}

type call = {
  c_step : int;
  c_ts : string;
  c_name : string;
  c_cmd : string;
}

type tx = {
  conv_id : string;
  first_prompt : string;
  first_ts : string;
  last_ts : string;
  msgs : msg list;
  calls : call list;
  results : (int * string * bool) list; (* step_index, content, is_error *)
  tool_spans : (float * float) list;
  tool_events : Tx.tool_event list;
  marks : (float * bool) list;          (* stamp, ends_turn *)
  bad_at : string list;
  skipped_lines : int;
  bad_usage : int;
}

let member = Tx.member
let str = Tx.str
let int_of = Tx.int_of

(* agy wraps some string args in an extra JSON string layer (e.g. "\"ls -la\""). *)
let unquote_arg s =
  let s = String.trim s in
  if String.length s >= 2 && s.[0] = '"' && s.[String.length s - 1] = '"' then
    (try match Yojson.Safe.from_string s with `String inner -> inner | _ -> s with _ -> s)
  else s

let usage_of j =
  match int_of "input_tokens" j, int_of "output_tokens" j, int_of "cache_read_tokens" j with
  | Some input, Some output, Some cache_read ->
      Some { Tx.input; output; cache_read; cache_write = 0 }
  | _ -> None

let has_truncated j =
  match member "truncated_fields" j with
  | `List (_ :: _) -> true
  | `Assoc (_ :: _) -> true
  | _ -> false

(* agy invoke_subagent sessions deliver their prompt in a SYSTEM_MESSAGE
   wrapper: "...[Message] ... content=<prompt>\n</SYSTEM_MESSAGE>".
   Strip the wrapper so Tx.join_line_names and Brief.is_verbatim match
   the prompt verbatim. *)
let unwrap_system_prompt s =
  let marker = " content=" in
  let body = match Tx.find_from s 0 marker with
    | Some i ->
        let start = i + String.length marker in
        String.sub s start (String.length s - start)
    | None -> s in
  let strip_suffix suf x =
    let n = String.length x and m = String.length suf in
    if n >= m && String.sub x (n - m) m = suf then String.sub x 0 (n - m) else x in
  body |> strip_suffix "\n</SYSTEM_MESSAGE>" |> strip_suffix "</SYSTEM_MESSAGE>"

(* Parse an agy transcript.jsonl; when ~full_text is provided and a line
   carries truncated_fields, replace it with the matching line from
   transcript_full.jsonl (by index). *)
let parse ?(conv_id = "") ?full_text text =
  let lines = Array.of_list (String.split_on_char '\n' text) in
  let full_lines = lazy (
    match full_text with
    | None -> [||]
    | Some ft -> Array.of_list (String.split_on_char '\n' ft)) in
  let first_prompt = ref "" and first_ts = ref "" and last_ts = ref "" in
  let msgs = ref [] and calls = ref [] and results = ref [] in
  let tool_spans = ref [] and tool_events = ref [] and marks = ref [] in
  let bad_at = ref [] and skipped = ref 0 and bad_usage = ref 0 in
  (* pending tool batch from the most recent PLANNER_RESPONSE *)
  let pending : (string * string * float * int) list ref = ref [] in
  Array.iteri (fun idx raw_line ->
      if String.trim raw_line <> "" then
        let parsed = try Some (Yojson.Safe.from_string raw_line) with _ -> None in
        let parsed = match parsed with
          | Some (`Assoc _ as j) when has_truncated j ->
              let fl = Lazy.force full_lines in
              if idx < Array.length fl && String.trim fl.(idx) <> "" then
                (try Some (Yojson.Safe.from_string fl.(idx)) with _ -> Some j)
              else Some j
          | other -> other in
        match parsed with
        | Some (`Assoc _ as j) ->
            let ts = str "created_at" j in
            let step = Option.value (int_of "step_index" j) ~default:idx in
            if ts <> "" then begin
              if !first_ts = "" then first_ts := ts;
              last_ts := ts
            end;
            (match str "type" j with
             | "USER_INPUT" ->
                 if !first_prompt = "" then first_prompt := str "content" j
             | "SYSTEM_MESSAGE" ->
                 if !first_prompt = "" then first_prompt := unwrap_system_prompt (str "content" j)
             | "PLANNER_RESPONSE" ->
                 let tcs = match member "tool_calls" j with `List xs -> xs | _ -> [] in
                 let has_tools = tcs <> [] in
                 (match Tx.seconds ts with
                  | Some at -> marks := (at, not has_tools) :: !marks
                  | None -> ());
                 (match usage_of j with
                  | Some u ->
                      msgs := { m_step = step; m_ts = ts; m_model = str "model" j;
                                m_usage = u; m_has_tools = has_tools } :: !msgs
                  | None ->
                      incr bad_usage;
                      bad_at := ts :: !bad_at);
                 pending := [];
                 List.iter (fun tc ->
                     let name = str "name" tc in
                     let args = member "args" tc in
                     let cmd = unquote_arg (str "CommandLine" args) in
                     calls := { c_step = step; c_ts = ts; c_name = name; c_cmd = cmd } :: !calls;
                     let start_s = Option.value (Tx.seconds ts) ~default:0. in
                     pending := !pending @ [ (name, cmd, start_s, step) ]) tcs
             | "GENERIC" ->
                 let status = str "status" j in
                 let is_err = status = "ERROR" in
                 let content = str "content" j in
                 let at = Tx.seconds ts in
                 (match at with Some a -> marks := (a, false) :: !marks | None -> ());
                 results := (step, content, is_err) :: !results;
                 (match !pending with
                  | (name, cmd, start_s, pstep) :: rest ->
                      pending := rest;
                      let end_s = Option.value at ~default:start_s in
                      if end_s > start_s then tool_spans := (start_s, end_s) :: !tool_spans;
                      tool_events := { Tx.te_name = name; te_cmd_head = Tx.cmd_head cmd;
                                       te_error = is_err; te_start = start_s; te_end = end_s;
                                       te_step = pstep } :: !tool_events
                  | [] -> ())
             | _ -> ())
        | _ -> incr skipped)
    lines;
  { conv_id;
    first_prompt = !first_prompt; first_ts = !first_ts; last_ts = !last_ts;
    msgs = List.rev !msgs; calls = List.rev !calls; results = List.rev !results;
    tool_spans = List.rev !tool_spans; tool_events = List.rev !tool_events;
    marks = List.stable_sort (fun (a, _) (b, _) -> compare a b) (List.rev !marks);
    bad_at = List.rev !bad_at; skipped_lines = !skipped; bad_usage = !bad_usage }

let self_checks tx = tx.bad_usage = 0 && tx.msgs <> []

let cost tx =
  let sum f = List.fold_left (fun acc m -> acc + f m.m_usage) 0 tx.msgs in
  let last = match List.rev tx.msgs with m :: _ -> Some m | [] -> None in
  let wall = match Tx.seconds tx.first_ts, Tx.seconds tx.last_ts with
    | Some a, Some b -> Float.round ((b -. a) *. 1000.) /. 1000. | _ -> 0. in
  let tool_errors = List.length (List.filter (fun (e : Tx.tool_event) -> e.te_error) tx.tool_events) in
  { Tx.wall_s = wall;
    tool_calls = List.length tx.calls;
    context_end = (match last with
        | Some m -> m.m_usage.input + m.m_usage.cache_read + m.m_usage.cache_write + m.m_usage.output
        | None -> 0);
    tokens_in = sum (fun u -> u.input);
    tokens_out = sum (fun u -> u.output);
    tokens_cache_read = sum (fun u -> u.cache_read);
    tokens_cache_write = sum (fun u -> u.cache_write);
    model = (match last with
        | Some m -> if Metrics.model_ok m.m_model then m.m_model else "other"
        | None -> "unknown");
    tool_s = Tx.ms (Tx.measure tx.tool_spans);
    tool_errors;
    turns = List.length tx.msgs }

(* ---------- author windows ---------- *)

let casts_handoff tx ~quest ~node ~commit ~from ~upto =
  let in_window ts = match Tx.seconds ts with Some t -> t >= from && t < upto +. 1. | None -> false in
  String.length commit >= 7
  && List.exists (fun (c : call) ->
         c.c_name = "run_command" && in_window c.c_ts
         && Tx.casts_node c.c_cmd ~quest ~node
         && (Tx.contains c.c_cmd (String.sub commit 0 7)
             || List.exists (fun (st, txt, is_err) ->
                    st > c.c_step && not is_err
                    && (Tx.contains txt commit || Tx.contains txt "\"state\":\"handed_off\""))
                  tx.results))
       tx.calls

type window_spend = {
  w_key : string;
  w_msgs : msg list;
  w_tools : int;
  w_errors : int;
  w_bad : int;
  w_events : Tx.tool_event list;
}

let assign tx windows =
  let taken = Hashtbl.create 256 in
  let inside (_, from, upto) ts = match Tx.seconds ts with Some t -> t >= from && t < upto +. 1. | None -> false in
  let inside_f (_, from, upto) t = t >= from && t < upto +. 1. in
  let take k = not (Hashtbl.mem taken k) && (Hashtbl.replace taken k (); true) in
  List.map (fun ((key, _, _) as w) ->
      let msgs = List.filter (fun (m : msg) -> inside w m.m_ts && take ("m" ^ string_of_int m.m_step)) tx.msgs in
      let calls = List.filteri (fun i (c : call) -> inside w c.c_ts && take ("c" ^ string_of_int i)) tx.calls in
      let events = List.filteri (fun i (e : Tx.tool_event) -> inside_f w e.te_start && take ("e" ^ string_of_int i)) tx.tool_events in
      let errors = List.length (List.filter (fun (e : Tx.tool_event) -> e.te_error) events) in
      let bad = List.filteri (fun i ts -> inside w ts && take ("b" ^ string_of_int i)) tx.bad_at in
      { w_key = key; w_msgs = msgs; w_tools = List.length calls; w_errors = errors;
        w_bad = List.length bad; w_events = events })
    windows

let author_cost msgs tool_calls tool_errors =
  let sum f = List.fold_left (fun acc m -> acc + f m.m_usage) 0 msgs in
  let last = match List.rev msgs with m :: _ -> Some m | [] -> None in
  { Tx.wall_s = 0.; tool_calls;
    context_end = (match last with
        | Some m -> m.m_usage.input + m.m_usage.cache_read + m.m_usage.cache_write + m.m_usage.output
        | None -> 0);
    tokens_in = sum (fun u -> u.input);
    tokens_out = sum (fun u -> u.output);
    tokens_cache_read = sum (fun u -> u.cache_read);
    tokens_cache_write = sum (fun u -> u.cache_write);
    model = (match last with
        | Some m -> if Metrics.model_ok m.m_model then m.m_model else "other"
        | None -> "unknown");
    tool_s = 0.; tool_errors; turns = List.length msgs }

type window_times = { t_wall : float; t_active : float; t_tool : float }

let window_times tx ~from ~upto =
  let inside t = t >= from && t < upto +. 1. in
  let marks = List.filter (fun (t, _) -> inside t) tx.marks in
  let rec gaps = function
    | (a, ended) :: ((b, _) :: _ as rest) -> if ended then gaps rest else (a, b) :: gaps rest
    | _ -> [] in
  let present = Tx.inter (gaps marks) [ (from, upto) ] in
  let spans = List.filter (fun (a, _) -> inside a) tx.tool_spans in
  { t_wall = Float.max 0. (upto -. from);
    t_active = Tx.ms (Tx.measure present);
    t_tool = Tx.ms (Tx.measure (Tx.inter spans present)) }
