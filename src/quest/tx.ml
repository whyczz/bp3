(* Shared transcript core (fast-agy-induct agy.1): harness-neutral
   usage, cost, tool-event traces, timestamp math, interval union, and
   join helpers used by Claude_tx, Pi_tx, Agy_tx, Metrics_io, and
   Warden Layer 2. Pure: text/records in, facts out. *)

type usage = { input : int; output : int; cache_read : int; cache_write : int }

type cost = {
  wall_s : float; tool_calls : int; context_end : int;
  tokens_in : int; tokens_out : int; tokens_cache_read : int; tokens_cache_write : int;
  model : string;
  tool_s : float;   (* union of paired tool spans *)
  tool_errors : int;
  turns : int;
}

(* Compact tool execution record kept for Warden Layer 2 session-trace
   plugs (retry loops, mid-cycle check-full spam, context bloat). *)
type tool_event = {
  te_name : string;
  te_cmd_head : string;
  te_error : bool;
  te_start : float;
  te_end : float;
  te_step : int;
}

type joined_trace = {
  jt_node : string;
  jt_cycle : int;
  jt_role : string;   (* "grade" | "author" | "session" *)
  jt_path : string;
  jt_run : string;
  jt_context_end : int;
  jt_turns : int;
  jt_tool_errors : int;
  jt_events : tool_event list;
  jt_user_steps : (int * float) list;  (* (step_or_line, epoch_s) of mid-window human inputs *)
}

(* Compact full-session human interaction turn & drill-down step records
   (warden-planned-gates session.1). *)
type human_turn = {
  ht_step : int;
  ht_ts : float;
  ht_iso : string;
  ht_source : string;      (* "user_input" | "ask_question" *)
  ht_agent_asked : string; (* bounded <= 300 chars *)
  ht_human_said : string;  (* bounded <= 1000 chars *)
  ht_nearby_edges : string list;
}

type query_step = {
  qs_step : int;
  qs_ts : string;
  qs_role : string;        (* "user" | "assistant" | "tool_call" | "tool_result" | "system" *)
  qs_text : string;        (* bounded <= 2000 chars *)
}

let collapse_ws s =
  let n = String.length s in
  let buf = Buffer.create (min n 256) in
  let in_ws = ref true in
  for i = 0 to n - 1 do
    match s.[i] with
    | ' ' | '\t' | '\r' | '\n' ->
        if not !in_ws then begin
          Buffer.add_char buf ' ';
          in_ws := true
        end
    | c ->
        Buffer.add_char buf c;
        in_ws := false
  done;
  let out = Buffer.contents buf in
  let m = String.length out in
  if m > 0 && out.[m - 1] = ' ' then String.sub out 0 (m - 1) else out

let clip ~max_chars s =
  let max_chars = max 0 max_chars in
  let clean = collapse_ws s in
  let n = String.length clean in
  if n <= max_chars then clean
  else if max_chars <= 3 then String.sub clean 0 max_chars
  else String.sub clean 0 (max_chars - 3) ^ "..."

let strip_agy_tool_headers s =
  String.split_on_char '\n' s
  |> List.filter (fun ln ->
         let t = String.trim ln in
         not (String.starts_with ~prefix:"Created At:" t
              || String.starts_with ~prefix:"Completed At:" t))
  |> String.concat "\n"
  |> String.trim

let extract_edge_tag cmd =
  let toks =
    String.split_on_char ' ' (collapse_ws cmd)
    |> List.filter (fun t -> t <> "") in
  let rec go = function
    | "e" :: edge :: _ when List.mem edge Names.all_edges -> Some edge
    | ("u" | "update") :: _node :: edge :: _ when List.mem edge Names.all_edges -> Some edge
    | _ :: rest -> go rest
    | [] -> None in
  if Util.contains_sub cmd "bp3" && (Util.contains_sub cmd " q " || Util.contains_sub cmd "\tq ") then go toks
  else None

let filter_window ~around ~window steps =
  let w = max 0 window in
  let lo = around - w and hi = around + w in
  List.filter (fun (qs : query_step) -> qs.qs_step >= lo && qs.qs_step <= hi) steps

(* Milliseconds matter: a grade's wall is the span of its lines. *)
let seconds ts =
  if String.length ts < 20 then None
  else
    match Util.epoch_of_iso (String.sub ts 0 19 ^ "Z") with
    | None -> None
    | Some s ->
        let frac = String.sub ts 19 (String.length ts - 19) in
        if frac = "Z" then Some s
        else if String.length frac >= 3 && frac.[0] = '.' && frac.[String.length frac - 1] = 'Z' then
          (match float_of_string_opt ("0" ^ String.sub frac 0 (String.length frac - 1)) with
           | Some f -> Some (s +. f)
           | None -> None)
        else None

(* Intervals [a, b) in epoch seconds: parallel tool calls overlap, so
   time is the union of the spans, never the sum of their lengths. *)
let merge spans =
  List.sort compare (List.filter (fun (a, b) -> b > a) spans)
  |> List.fold_left (fun acc (a, b) -> match acc with
      | (pa, pb) :: rest when a <= pb -> (pa, Float.max pb b) :: rest
      | _ -> (a, b) :: acc) []
  |> List.rev

let measure spans = List.fold_left (fun acc (a, b) -> acc +. (b -. a)) 0. (merge spans)

let inter xs ys =
  let ys = merge ys in
  List.concat_map (fun (a, b) ->
      List.filter_map (fun (c, d) ->
          let lo = Float.max a c and hi = Float.min b d in if hi > lo then Some (lo, hi) else None) ys)
    (merge xs)

let ms v = Float.round (v *. 1000.) /. 1000.

(* Each paired call's span; a call with no result counts nothing, so
   tool time is a lower bound. *)
let paired uses results =
  let at = Hashtbl.create 64 in
  List.iter (fun (id, r) -> if not (Hashtbl.mem at id) then Hashtbl.replace at id r) results;
  List.filter_map (fun (id, u) -> match Hashtbl.find_opt at id with Some r -> Some (u, r) | None -> None) uses

(* Total JSON field access: unexpected shapes read as absent, never
   raising to kill a scrape. *)
let member k j = match j with `Assoc fs -> (match List.assoc_opt k fs with Some v -> v | None -> `Null) | _ -> `Null
let str k j = match member k j with `String s -> s | _ -> ""
let int_of k j = match member k j with `Int n -> Some n | _ -> None
let bool_of k j = match member k j with `Bool b -> b | _ -> false

(* No allocation per position: session files can be tens of MB. *)
let find_from s i sub =
  let n = String.length sub and m = String.length s in
  let rec at i k = k = n || (s.[i + k] = sub.[k] && at i (k + 1)) in
  let rec go i = if i + n > m then None else if at i 0 then Some i else go (i + 1) in
  if n = 0 then None else go i

let contains s sub = find_from s 0 sub <> None

(* Compact command head (first 80 printable chars) for Warden rules. *)
let cmd_head s =
  let s = String.trim s in
  let n = min (String.length s) 80 in
  let buf = Buffer.create n in
  for i = 0 to n - 1 do
    let c = s.[i] in
    Buffer.add_char buf (if c = '\n' || c = '\r' || c = '\t' then ' ' else c)
  done;
  Buffer.contents buf

(* The grade join's two rules, on any harness's transcript: the first
   prompt names the node and the commit's first 7 characters, and the
   transcript lies inside [handoff, grade + 1s). *)
let prompt_names_grade prompt ~node ~commit =
  String.length commit >= 7 && contains prompt node && contains prompt (String.sub commit 0 7)

let span_in_window ~first_ts ~last_ts ~handed_at ~graded_at =
  match seconds first_ts, seconds last_ts, seconds handed_at, seconds graded_at with
  | Some a, Some b, Some h, Some g -> a >= h && b < g +. 1.
  | _ -> false

let join_line_names prompt ~node ~commit =
  let first = match String.index_opt prompt '\n' with Some i -> String.sub prompt 0 i | None -> prompt in
  prompt_names_grade first ~node ~commit

(* w stands as its own word in s: no id character on either side. *)
let has_word s w =
  let id_char c = match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true | _ -> false in
  let n = String.length w and m = String.length s in
  let rec from i = match find_from s i w with
    | None -> false
    | Some j ->
        ((j = 0 || not (id_char s.[j - 1])) && (j + n = m || not (id_char s.[j + n]))) || from (j + 1) in
  n > 0 && from 0

(* Every value a result shows for a JSON key, each with whether it closed. *)
let shown t key =
  List.concat_map (fun o ->
      let rec from i = match find_from t i o with
        | None -> []
        | Some k ->
            let start = k + String.length o in
            let rec stop j = if j >= String.length t || t.[j] = '"' || t.[j] = '\n' then j else stop (j + 1) in
            let j = stop start in
            let v = String.sub t start (j - start) in
            if j < String.length t && t.[j] = '"' then (v, true) :: from (j + 1)
            else (v, false) :: from j in
      from 0)
    [ "\"" ^ key ^ "\":\""; "\"" ^ key ^ "\": \"" ]

(* The command casts this quest's node: `q <Q> n <N> e handoff` or
   `q <Q> u|update <N> handoff`, with literal or same-command shell vars. *)
let casts_node command ~quest ~node =
  let tok = "\\([^ \t;&|]+\\)" in
  let re = Str.regexp ("\\(^\\|[ \t;&|(]\\)q[ \t]+" ^ tok ^ "[ \t]+\\(n[ \t]+" ^ tok ^ "[ \t]+e\\|\\(u\\|update\\)[ \t]+"
                       ^ tok ^ "\\)[ \t]+handoff\\($\\|[ \t;&|)]\\)") in
  let names value tok =
    tok = value
    || (let strip = List.fold_left (fun s (p, q) ->
            if String.length s >= String.length p + String.length q && String.starts_with ~prefix:p s
               && String.ends_with ~suffix:q s
            then String.sub s (String.length p) (String.length s - String.length p - String.length q) else s) in
        let var = strip tok [ ("\"", "\""); ("$", ""); ("{", "}") ] in
        var <> tok && var <> "" && String.for_all (function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true | _ -> false) var
        && List.exists (fun v -> has_word command (var ^ "=" ^ v)) [ value; "\"" ^ value ^ "\""; "'" ^ value ^ "'" ]) in
  let group g = try Some (Str.matched_group g command) with Not_found | Invalid_argument _ -> None in
  let rec from i = match (try Some (Str.search_forward re command i) with Not_found -> None) with
    | None -> false
    | Some k ->
        let q = group 2 and n = (match group 4 with Some n -> Some n | None -> group 6) in
        (match q, n with Some q, Some n -> names quest q && names node n | _ -> false) || from (k + 1) in
  from 0
