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
  skipped_lines : int;    (* not JSON, or an assistant line with no message.id *)
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

let str k j = match Yojson.Safe.Util.member k j with `String s -> s | _ -> ""
let int_of k j = match Yojson.Safe.Util.member k j with `Int i -> i | _ -> 0

let usage_of j =
  { input = int_of "input_tokens" j; output = int_of "output_tokens" j;
    cache_read = int_of "cache_read_input_tokens" j; cache_write = int_of "cache_creation_input_tokens" j }

let prompt_text content =
  match content with
  | `String s -> s
  | `List blocks ->
      String.concat "\n" (List.filter_map (fun b -> match Yojson.Safe.Util.member "text" b with
          | `String s -> Some s | _ -> None) blocks)
  | _ -> ""

let parse text =
  let order = ref [] and by_id = Hashtbl.create 64 and tools = Hashtbl.create 64 in
  let tool_order = ref [] and skipped = ref 0 in
  let session = ref "" and agent = ref "" and prompt = ref None in
  let first_ts = ref "" and last_ts = ref "" in
  List.iter (fun line ->
      if String.trim line <> "" then
        match (try Some (Yojson.Safe.from_string line) with _ -> None) with
        | Some (`Assoc _ as j) ->
            let ts = str "timestamp" j in
            if ts <> "" then begin
              if !first_ts = "" then first_ts := ts;
              last_ts := ts
            end;
            if !session = "" then session := str "sessionId" j;
            if !agent = "" then agent := str "agentId" j;
            let message = Yojson.Safe.Util.member "message" j in
            (match str "type" j with
             | "user" when !prompt = None ->
                 prompt := Some (prompt_text (Yojson.Safe.Util.member "content" message))
             | "assistant" ->
                 let id = str "id" message in
                 if id = "" then incr skipped
                 else begin
                   if not (Hashtbl.mem by_id id) then order := id :: !order;
                   Hashtbl.replace by_id id
                     { id; ts; model = str "model" message; usage = usage_of (Yojson.Safe.Util.member "usage" message);
                       sidechain = (match Yojson.Safe.Util.member "isSidechain" j with `Bool b -> b | _ -> false) };
                   (match Yojson.Safe.Util.member "content" message with
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
    tool_use_ids = List.rev !tool_order; skipped_lines = !skipped }

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
    model = (match last with Some m -> m.model | None -> "unknown") }

(* A grade transcript names its node and the graded commit in its
   first prompt (past briefs already did), and runs inside the
   handoff-to-grade window. Ledger times are whole seconds, so the
   window closes one second after the grade's stamp. *)
let names_grade tx ~node ~commit =
  let has s sub =
    let n = String.length sub and m = String.length s in
    let rec go i = i + n <= m && (String.sub s i n = sub || go (i + 1)) in
    n > 0 && go 0 in
  String.length commit >= 7 && has tx.first_prompt node && has tx.first_prompt (String.sub commit 0 7)

let in_window tx ~handed_at ~graded_at =
  match seconds tx.first_ts, seconds tx.last_ts, seconds handed_at, seconds graded_at with
  | Some a, Some b, Some h, Some g -> a >= h && b < g +. 1.
  | _ -> false

(* The harness report (scrape.1): the <usage> block the parent session
   receives when a subagent ends. Not read yet; until scrape.1 lands,
   every grade it would check is counted "unchecked". *)
type report = { r_tool_uses : int; r_duration_ms : int; r_subagent_tokens : int }
let reports_of_text (_ : string) : (string * report) list = []
