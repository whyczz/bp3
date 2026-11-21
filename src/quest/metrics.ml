(* Metric collectors (metric-collectors sink.1): the sample shape,
   the registry that names one owning collector per metric, and the
   pure checks every write goes through. No IO here: Metrics_io reads
   and writes the sink, Claude_tx reads transcripts. *)

type kind = Hook | Scraper | Deriver
type agg = Sum | Max | Last

(* A collector writes (or, for a deriver, computes) the metrics it
   owns; no metric has two owners, so no number has two sources. *)
type collector = { c_name : string; c_kind : kind }

let grade_transcripts = { c_name = "grade-transcripts"; c_kind = Scraper }
let author_window = { c_name = "author-window"; c_kind = Scraper }
let node_cost = { c_name = "node-cost"; c_kind = Deriver }
let collectors = [ grade_transcripts; author_window; node_cost ]

type row = { name : string; unit_ : string; agg : agg; owner : collector }

let tokens = [ "tokens_in"; "tokens_out"; "tokens_cache_read"; "tokens_cache_write" ]
let rows owner prefix specs =
  List.map (fun (f, unit_, agg) -> { name = prefix ^ "." ^ f; unit_; agg; owner }) specs

let registry =
  rows grade_transcripts "grade"
    ([ ("wall_s", "s", Sum); ("tool_calls", "count", Sum); ("context_end", "tokens", Max) ]
     @ List.map (fun t -> (t, "tokens", Sum)) tokens)
  @ rows author_window "author"
      (("tool_calls", "count", Sum) :: List.map (fun t -> (t, "tokens", Sum)) tokens)
  @ rows node_cost "cycle" [ ("todo_s", "s", Last); ("handed_off_s", "s", Last) ]

let find name = List.find_opt (fun r -> r.name = name) registry

(* One number about one thing. No free-text field: transcripts hold
   prompts, and node state branches get pushed (QUEST.md R4). *)
type sample = {
  metric : string; quest : string; node : string; cycle : int;
  run : string;     (* claude:<sessionId>/<agentId> | claude:<sessionId> *)
  model : string;
  value : float;
  at : string;      (* ISO 8601 UTC, end of the measured thing *)
  source : string;  (* the owning collector's name *)
}

let id_ok s =
  s <> "" && String.length s <= 200
  && String.for_all (function
       | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | ':' | '/' -> true
       | _ -> false) s

let ts_re = Str.regexp
    "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\(\\.[0-9]+\\)?Z$"

(* A model is a closed shape, not an id: claude-<lowercase>, or the
   scraper's own "unknown" / "other". Anything else could be text
   riding in a model field (QUEST.md R4). *)
let model_re = Str.regexp "^\\(claude-[a-z0-9.-]+\\|unknown\\|other\\)$"
let model_ok m = String.length m <= 64 && Str.string_match model_re m 0

(* Error is (code, detail); Metrics_io raises it as a verdict. *)
let validate s =
  match find s.metric with
  | None -> Error ("E_METRIC_UNKNOWN", s.metric)
  | Some r when r.owner.c_kind = Deriver -> Error ("E_METRIC_DERIVED", s.metric)
  | Some r when r.owner.c_name <> s.source -> Error ("E_METRIC_OWNER", s.metric ^ " is owned by " ^ r.owner.c_name)
  | Some _ ->
      if not (Float.is_finite s.value) || s.value < 0. then Error ("E_METRIC_VALUE", "value")
      else if s.cycle < 1 then Error ("E_METRIC_VALUE", "cycle")
      else if not (List.for_all id_ok [ s.quest; s.node; s.run ]) then Error ("E_METRIC_VALUE", "ids")
      else if not (model_ok s.model) then Error ("E_METRIC_VALUE", "model")
      else if not (Str.string_match ts_re s.at 0) then Error ("E_METRIC_VALUE", "at")
      else Ok ()

(* Two samples with one key measure the same thing: the sink keeps
   the first and skips the rest, so re-running a collector is safe. *)
let key s = String.concat "|" [ s.metric; s.node; string_of_int s.cycle; s.run ]

let dedupe ~existing batch =
  let seen = Hashtbl.create 64 in
  List.iter (fun s -> Hashtbl.replace seen (key s) ()) existing;
  let fresh = List.filter (fun s ->
      if Hashtbl.mem seen (key s) then false else (Hashtbl.replace seen (key s) (); true)) batch in
  (fresh, List.length batch - List.length fresh)

let to_json s =
  `Assoc [ ("metric", `String s.metric); ("quest", `String s.quest); ("node", `String s.node);
           ("cycle", `Int s.cycle); ("run", `String s.run); ("model", `String s.model);
           ("value", `Float s.value); ("at", `String s.at); ("source", `String s.source) ]

let of_json j =
  let open Yojson.Safe.Util in
  try
    let num = match member "value" j with `Int i -> float_of_int i | `Float f -> f | _ -> raise Exit in
    Some { metric = to_string (member "metric" j); quest = to_string (member "quest" j);
           node = to_string (member "node" j); cycle = to_int (member "cycle" j);
           run = to_string (member "run" j); model = to_string (member "model" j);
           value = num; at = to_string (member "at" j); source = to_string (member "source" j) }
  with _ -> None

let of_text text =
  String.split_on_char '\n' text
  |> List.filter_map (fun l ->
         if String.trim l = "" then None
         else try of_json (Yojson.Safe.from_string l) with _ -> None)

let to_text samples =
  String.concat "" (List.map (fun s -> Yojson.Safe.to_string (to_json s) ^ "\n") samples)

(* ---------- ledger edges, as the collectors join them ---------- *)

type edge = { e_ts : string; e_edge : string; e_cycle : int; e_commit : string option }

let edges_of_text text =
  String.split_on_char '\n' text
  |> List.filter_map (fun l ->
         if String.trim l = "" then None
         else
           try
             let j = Yojson.Safe.from_string l in
             let open Yojson.Safe.Util in
             Some { e_ts = to_string (member "ts" j); e_edge = to_string (member "edge" j);
                    e_cycle = (match member "cycle" j with `Int c -> c | _ -> 1);
                    e_commit = to_string_option (member "commit" j) }
           with _ -> None)

(* One grade and the handoff it judged. A needs_fix grade line carries
   the next cycle's number, so the cycle is the handoff's. *)
type grade_span = { g_cycle : int; g_commit : string; handed_at : string; graded_at : string }

let grade_spans edges =
  let rec go last acc = function
    | [] -> List.rev acc
    | e :: rest when e.e_edge = "handoff" -> go (Some e) acc rest
    | e :: rest when e.e_edge = "grade" ->
        (match last with
         | Some h ->
             let commit = match h.e_commit with Some c -> c | None -> "" in
             go None ({ g_cycle = h.e_cycle; g_commit = commit; handed_at = h.e_ts; graded_at = e.e_ts } :: acc) rest
         | None -> go None acc rest)
    | _ :: rest -> go last acc rest in
  go None [] edges

(* What one scrape did to one node. Every grade lands in exactly one
   outcome bucket (checked, unchecked, ambiguous, mismatched, owner);
   written and skipped count samples, not grades; skipped_lines counts
   transcript lines the reader could not use (never read as zero). *)
type tally = {
  grades : int; checked : int; unchecked : int; ambiguous : int;
  mismatched : int; owner_graded : int; written : int; skipped : int;
  skipped_lines : int;
}

let zero = { grades = 0; checked = 0; unchecked = 0; ambiguous = 0;
             mismatched = 0; owner_graded = 0; written = 0; skipped = 0; skipped_lines = 0 }

let buckets_add_up t = t.checked + t.unchecked + t.ambiguous + t.mismatched + t.owner_graded = t.grades

let tally_json t =
  `Assoc [ ("grades", `Int t.grades); ("checked", `Int t.checked); ("unchecked", `Int t.unchecked);
           ("ambiguous", `Int t.ambiguous); ("mismatched", `Int t.mismatched);
           ("owner", `Int t.owner_graded); ("written", `Int t.written); ("skipped", `Int t.skipped);
           ("skipped_lines", `Int t.skipped_lines) ]
