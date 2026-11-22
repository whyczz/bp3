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
    ([ ("wall_s", "s", Sum); ("tool_calls", "count", Sum); ("context_end", "tokens", Max); ("tool_s", "s", Sum) ]
     @ List.map (fun t -> (t, "tokens", Sum)) tokens)
  @ rows author_window "author"
      ([ ("tool_calls", "count", Sum); ("wall_s", "s", Sum); ("active_s", "s", Sum); ("tool_s", "s", Sum) ]
       @ List.map (fun t -> (t, "tokens", Sum)) tokens)
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

(* Str's $ also matches before a newline, so a full match is checked by
   its end position, never by $. *)
let ts_re = Str.regexp
    "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\(\\.[0-9]+\\)?Z"
let ts_ok s = Str.string_match ts_re s 0 && Str.match_end () = String.length s

(* A model is a closed shape, not an id: a known family's prefix then
   lowercase [a-z0-9.-], or the scraper's own "unknown" / "other".
   Anything else could be text riding in a model field (QUEST.md R4);
   pi-metrics reader.1 added the families pi reports beside claude-. *)
let model_families = [ "claude-"; "gpt-"; "gemini-"; "grok-" ]
let model_ok m =
  m = "unknown" || m = "other"
  || (String.length m <= 64
      && List.exists (fun p ->
          let n = String.length p in
          String.length m > n && String.starts_with ~prefix:p m
          && String.for_all (function 'a' .. 'z' | '0' .. '9' | '.' | '-' -> true | _ -> false)
               (String.sub m n (String.length m - n))) model_families)

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
      else if not (ts_ok s.at) then Error ("E_METRIC_VALUE", "at")
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

type edge = { e_ts : string; e_edge : string; e_cycle : int; e_commit : string option; e_to : string }

(* Edge and state names fold as the engine folds them (Store), so the
   deriver below sees the ledger the rollup sees. *)
let edges_of_text text =
  String.split_on_char '\n' text
  |> List.filter_map (fun l ->
         if String.trim l = "" then None
         else
           try
             let j = Yojson.Safe.from_string l in
             let open Yojson.Safe.Util in
             Some { e_ts = to_string (member "ts" j); e_edge = Store.fold_edge (to_string (member "edge" j));
                    e_cycle = (match member "cycle" j with `Int c -> c | _ -> 1);
                    e_commit = to_string_option (member "commit" j);
                    e_to = (match member "to" j with `String s -> Store.fold_state_name s | _ -> "") }
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

(* One handoff's author window (scrape.2): from the quest's previous
   edge to the handoff. A resume is skipped as a start: it is the
   owner's gate, and the author's work for that cycle began at the
   edge before it. Edges are compared as ledger stamps (one format). *)
type author_span = { a_cycle : int; a_commit : string; a_from : string; a_upto : string }

let author_spans ~node all =
  List.filter_map (fun (n, e) ->
      if n <> node || e.e_edge <> "handoff" then None
      else
        let from = List.fold_left (fun acc (_, x) ->
            if x.e_edge <> "resume" && x.e_ts < e.e_ts && x.e_ts > acc then x.e_ts else acc) "" all in
        Some { a_cycle = e.e_cycle; a_commit = Option.value e.e_commit ~default:"";
               a_from = (if from = "" then e.e_ts else from); a_upto = e.e_ts }) all

(* What one scrape did to one node. Every grade lands in exactly one
   outcome bucket (checked, unchecked, self_checked, ambiguous,
   mismatched, owner): self_checked is a pi grade that agreed with
   itself (Pi_tx.self_checks), never with a separate report,
   and every handoff in one (authored, author_missing,
   author_ambiguous, author_bad_usage); written and skipped count
   samples; skipped_lines counts transcript lines the reader could not
   use (never read as 0). author_bad_usage is the author side of
   mismatched: a window holding a usage-less line writes nothing. *)
type tally = {
  grades : int; checked : int; unchecked : int; self_checked : int; ambiguous : int;
  mismatched : int; owner_graded : int; written : int; skipped : int;
  skipped_lines : int;
  handoffs : int; authored : int; author_missing : int; author_ambiguous : int;
  author_bad_usage : int;
}

let zero = { grades = 0; checked = 0; unchecked = 0; self_checked = 0; ambiguous = 0;
             mismatched = 0; owner_graded = 0; written = 0; skipped = 0; skipped_lines = 0;
             handoffs = 0; authored = 0; author_missing = 0; author_ambiguous = 0;
             author_bad_usage = 0 }

let buckets_add_up t =
  t.checked + t.unchecked + t.self_checked + t.ambiguous + t.mismatched + t.owner_graded = t.grades
  && t.authored + t.author_missing + t.author_ambiguous + t.author_bad_usage = t.handoffs

let tally_json t =
  `Assoc [ ("grades", `Int t.grades); ("checked", `Int t.checked); ("unchecked", `Int t.unchecked);
           ("self_checked", `Int t.self_checked);
           ("ambiguous", `Int t.ambiguous); ("mismatched", `Int t.mismatched);
           ("owner", `Int t.owner_graded); ("written", `Int t.written); ("skipped", `Int t.skipped);
           ("skipped_lines", `Int t.skipped_lines);
           ("handoffs", `Int t.handoffs); ("authored", `Int t.authored);
           ("author_missing", `Int t.author_missing); ("author_ambiguous", `Int t.author_ambiguous);
           ("author_bad_usage", `Int t.author_bad_usage) ]

(* ---------- the node-cost deriver (derive.1) ---------- *)

(* Seconds in each state, per cycle: the interval between two edges
   that move state belongs to the state the first moved into and to
   that edge's cycle (a needs_fix grade line already carries the next
   cycle, so its todo interval lands there). These are the intervals
   bp3 q r sums into timing.dwell_s, so per-cycle sums equal it. *)
let cycle_dwell edges =
  let moves = List.filter_map (fun e ->
      match Store.ts_epoch e.e_ts with Some t when e.e_to <> "" -> Some (t, e) | _ -> None) edges in
  let tbl = Hashtbl.create 8 in
  let rec go = function
    | (t0, a) :: ((t1, _) :: _ as rest) ->
        let k = (a.e_cycle, a.e_to) in
        Hashtbl.replace tbl k ((try Hashtbl.find tbl k with Not_found -> 0) + (t1 - t0));
        go rest
    | _ -> () in
  go moves;
  List.sort compare (Hashtbl.fold (fun (c, st) s acc -> (c, st, s) :: acc) tbl [])

(* The deriver's samples: cycle.todo_s and cycle.handed_off_s per cycle
   the node spent time in. Computed on read, never written (a Deriver's
   metrics refuse writes). *)
let derive_timing ~quest ~node edges =
  let d = cycle_dwell edges in
  let cycles = List.sort_uniq compare (List.map (fun (c, _, _) -> c) d) in
  let last_ts = match List.rev edges with e :: _ -> e.e_ts | [] -> "1970-01-01T00:00:00Z" in
  List.concat_map (fun c ->
      List.map (fun st ->
          let secs = List.fold_left (fun acc (c', st', s) -> if c' = c && st' = st then acc + s else acc) 0 d in
          { metric = "cycle." ^ st ^ "_s"; quest; node; cycle = c; run = "ledger"; model = "unknown";
            value = float_of_int secs; at = last_ts; source = node_cost.c_name })
        [ "todo"; "handed_off" ]) cycles

let median xs =
  match List.sort compare xs with
  | [] -> None
  | s -> let n = List.length s in
      Some (if n mod 2 = 1 then List.nth s (n / 2) else (List.nth s (n / 2 - 1) +. List.nth s (n / 2)) /. 2.)

let sum_metric samples m =
  List.fold_left (fun acc (s : sample) -> if s.metric = m then acc +. s.value else acc) 0. samples

let spend samples prefix =
  List.map (fun t -> (t, sum_metric samples (prefix ^ "." ^ t))) tokens

(* Roll-ups over one node's or one quest's samples and edges: what was
   measured, what was not (owner grades, missing sessions), wall, and
   spend by token field. Pure; order of samples never matters. *)
type rollup = {
  r_grades : int; r_grades_measured : int; r_handoffs : int; r_handoffs_measured : int;
  r_grade_walls : float list; r_grade_spend : (string * float) list; r_author_spend : (string * float) list;
  r_author_walls : float list; r_author_actives : float list;   (* measure.1 *)
}

let values samples m = List.filter_map (fun (s : sample) -> if s.metric = m then Some s.value else None) samples

let rollup ~edges samples =
  let measured prefix = List.sort_uniq compare (List.filter_map (fun (s : sample) ->
      if String.starts_with ~prefix:(prefix ^ ".") s.metric then Some (s.node, s.cycle) else None) samples) in
  { r_grades = List.length (grade_spans edges);
    r_grades_measured = List.length (measured "grade");
    r_handoffs = List.length (List.filter (fun e -> e.e_edge = "handoff") edges);
    r_handoffs_measured = List.length (measured "author");
    r_grade_walls = values samples "grade.wall_s";
    r_grade_spend = spend samples "grade"; r_author_spend = spend samples "author";
    r_author_walls = values samples "author.wall_s"; r_author_actives = values samples "author.active_s" }

let rollup_json r =
  let f v = if Float.is_integer v && Float.abs v < 1e15 then `Int (int_of_float v) else `Float v in
  let stats = function
    | [] -> `Null
    | ws -> `Assoc [ ("median", f (Option.get (median ws))); ("min", f (List.fold_left min infinity ws));
                     ("max", f (List.fold_left max neg_infinity ws)); ("sum", f (List.fold_left ( +. ) 0. (List.sort compare ws))) ] in
  `Assoc [ ("grades", `Int r.r_grades); ("grades_measured", `Int r.r_grades_measured);
           ("handoffs", `Int r.r_handoffs); ("handoffs_measured", `Int r.r_handoffs_measured);
           ("grade_wall_s", stats r.r_grade_walls);
           ("author_wall_s", stats r.r_author_walls); ("author_active_s", stats r.r_author_actives);
           ("spend", `Assoc [ ("grade", `Assoc (List.map (fun (k, v) -> (k, f v)) r.r_grade_spend));
                              ("author", `Assoc (List.map (fun (k, v) -> (k, f v)) r.r_author_spend)) ]) ]
