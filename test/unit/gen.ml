(* Shared builders and generators for the unit tier. *)

let line fields = Yojson.Safe.to_string (`Assoc fields)
let jstr k v = (k, `String v)
let jint k v = (k, `Int v)

(* One ledger edge line in the shape the engine writes. *)
let edge ?(cycle = 1) ?commit ?verdict ?verify ?(reason = "r") ?(ts = "2026-11-18T00:00:00Z")
    ?deps ?checkpoint e from to_ =
  line ([ jstr "ts" ts; jstr "edge" e; jstr "from" from; jstr "to" to_; jint "cycle" cycle;
          ("commit", (match commit with Some c -> `String c | None -> `Null));
          ("verdict", (match verdict with Some v -> `String v | None -> `Null));
          jstr "reason" reason ]
        @ (match verify with Some v -> [ jstr "verify_verdict" v ] | None -> [])
        @ (match checkpoint with Some c -> [ jstr "checkpoint" c ] | None -> [])
        @ (match deps with Some ds -> [ ("depends_on", `List (List.map (fun d -> `String d) ds)) ] | None -> []))

let text lines = String.concat "\n" lines ^ "\n"

let read_sample name =
  let ic = open_in_bin (Filename.concat "samples" name) in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic; s

open QCheck2.Gen

let slug_char = oneof [ char_range 'a' 'z'; char_range '0' '9'; return '-' ]
let hex = string_size ~gen:(oneof [ char_range '0' '9'; char_range 'a' 'f' ]) (return 40)

(* A legal walk through the node FSM, as edge lines: every step takes
   one edge the current state allows, so the walk really moves state. *)
let fsm_walk : string list QCheck2.Gen.t =
  let step (st, cyc) =
    match st with
    | "todo" ->
        oneof [ map (fun c -> ("handed_off", cyc, edge ~cycle:cyc ~commit:c "handoff" st "handed_off")) hex;
                return ("blocked", cyc, edge ~cycle:cyc ~reason:"park" "block" st "blocked") ]
    | "handed_off" ->
        oneof_list [ ("approved", cyc, edge ~cycle:cyc ~verdict:"ship" ~verify:"pass" "grade" st "approved");
                 ("todo", cyc + 1, edge ~cycle:(cyc + 1) ~verdict:"needs_fix" ~verify:"pass" "grade" st "todo");
                 ("blocked", cyc, edge ~cycle:cyc ~verdict:"needs_fix" ~verify:"fail" ~checkpoint:"cp" "grade" st "blocked") ]
    | "approved" -> return ("landed", cyc, edge ~cycle:cyc "land" st "landed")
    | "blocked" -> return ("todo", cyc + 1, edge ~cycle:(cyc + 1) "resume" st "todo")
    | _ -> return (st, cyc, "") in
  int_range 0 8 >>= fun n ->
  let rec go k (st, cyc) acc =
    if k = 0 || st = "landed" then return (List.rev acc)
    else step (st, cyc) >>= fun (st', cyc', l) -> go (k - 1) (st', cyc') (l :: acc) in
  go n ("todo", 1) [ edge "create" "" "todo" ]

(* Event lines in the shape hooks.ml emits (its kinds and field keys):
   an "event" key, never edge/to/commit/verdict. *)
let event_line : string QCheck2.Gen.t =
  map3 (fun kind cyc tok ->
      line [ jstr "event" kind; jstr "ts" "2026-11-18T00:00:01Z"; jstr "run_id" "R-ev";
             jint "cycle" cyc; jint "input_tokens" tok; jstr "session_id" "S-ev";
             jstr "code" "E_DEPTH"; jstr "attempted" "handoff"; jstr "check" "make check";
             jstr "result" "pass"; jstr "outcome" "settled" ])
    (oneof_list [ "usage_recorded"; "run_settled"; "run_unsettled"; "run_started"; "refused"; "lint_checked" ])
    (int_range 1 9) (int_range 0 5000)

(* Insert each event at its own position (head, middle, tail all reachable). *)
let splice base events positions =
  List.fold_left2 (fun acc ev pos ->
      let n = List.length acc in
      let p = if n = 0 then 0 else pos mod (n + 1) in
      List.filteri (fun i _ -> i < p) acc @ [ ev ] @ List.filteri (fun i _ -> i >= p) acc)
    base events positions
