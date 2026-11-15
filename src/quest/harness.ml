(* harness — the bp3 harness door: supervisor, init-check,
   find-tape, watch, desk. This exp (mvp.1) builds the door,
   the verdict/exit contract, the lifecycle fold, and the
   passive supervisor loop. find-tape (mvp.2), watch (mvp.3),
   and desk (mvp.6) refuse typed until their exps land.
   The supervisor never signals a pid and never finalizes
   from a watch outcome: tick phases are tell -> watch ->
   judge (fresh quest read) -> finalize. *)
open Gitx
open Store

(* ---------- lifecycle fold (pure) ---------- *)
type init_record = {
  run_id : string;
  harness : string;
  session_id : string option;
  pid : int option;
  tape_path : string option;
  quest : string option;
  exp : string option;
}

type observation = {
  pid_alive : bool option;
  exit_observed : bool;
  tape_closed : bool;
  settle_row : bool;
  tape_seen : bool;
  fresh : bool;
}

let no_observation = {
  pid_alive = None; exit_observed = false; tape_closed = false;
  settle_row = false; tape_seen = false; fresh = false;
}

(* Lifecycle is derived, never narrated: init / active /
   finished / orphaned. A settle row alone never finishes a
   live child; stale plus alive stays active; blind probes
   add no fifth word (None means no InitRecord, no claim). *)
let derive_lifecycle init obs =
  match init with
  | None -> None
  | Some _ ->
      if (obs.exit_observed && obs.tape_closed)
         || (obs.settle_row && obs.tape_closed) then Some "finished"
      else if not obs.tape_seen && obs.pid_alive = None
              && not obs.exit_observed && not obs.settle_row then Some "init"
      else if not obs.fresh && obs.pid_alive <> Some true then Some "orphaned"
      else Some "active"

(* Exit classes: settled adopts the success class (0),
   watchdog_killed the terminal domain class (1). No
   retryable or needs-human class existed in the binary
   (call failures are 1 domain / 2 usage), so timeout (3)
   and human_gate (4) extend the outcome classes here. *)
let exit_of_outcome = function
  | "settled" -> 0
  | "watchdog_killed" -> 1
  | "timeout" -> 3
  | "human_gate" -> 4
  | _ -> 1

(* ---------- derivation store (read-only in this exp) ---------- *)
let derivations_dir () =
  let out, code = git_out ["rev-parse"; "--git-common-dir"] in
  if code <> 0 || out = "" then None
  else
    let dir = if Filename.is_relative out then Filename.concat root out else out in
    Some (Filename.concat (Filename.concat dir "bp3") "run-lifecycle-derivations")

let pid_alive pid =
  try Unix.kill pid 0; true
  with Unix.Unix_error (Unix.EPERM, _, _) -> true
     | Unix.Unix_error _ -> false

let get_bool j key =
  try match Yojson.Safe.Util.member key j with `Bool b -> b | _ -> false
  with _ -> false

let get_int_opt j key =
  try match Yojson.Safe.Util.member key j with `Int n -> Some n | _ -> None
  with _ -> None

(* Fold one Run's derivation log. Malformed lines (a torn
   final line included) carry no fact and are skipped. *)
let fold_run_file ~silence_seconds path =
  let text = read_file_or path "" in
  let init = ref None in
  let obs = ref no_observation in
  String.split_on_char '\n' text |> List.iter (fun ln ->
    let ln = String.trim ln in
    if ln <> "" then
      try
        let j = Yojson.Safe.from_string ln in
        match get_str j "kind" "" with
        | "init_record" ->
            init := Some {
              run_id = get_str j "run_id" "";
              harness = get_str j "harness" "";
              session_id = get_opt j "session_id";
              pid = get_int_opt j "pid";
              tape_path = get_opt j "tape_path";
              quest = get_opt j "quest";
              exp = get_opt j "exp";
            }
        | "observation" ->
            let o = !obs in
            obs := {
              pid_alive = (match Yojson.Safe.Util.member "pid_alive" j with
                | `Bool b -> Some b | _ -> o.pid_alive);
              exit_observed = o.exit_observed || get_bool j "exit_observed";
              tape_closed = o.tape_closed || get_bool j "tape_closed";
              settle_row = o.settle_row || get_bool j "settle_row";
              tape_seen = o.tape_seen || get_bool j "tape_seen";
              fresh = o.fresh;
            }
        | _ -> ()
      with _ -> ());
  (match !init with
   | None -> (!init, !obs, [])
   | Some rec_ ->
       let o = !obs in
       let alive = match rec_.pid with
         | Some p -> Some (pid_alive p) | None -> o.pid_alive in
       let blind = ref false in
       let tape_seen, fresh = match rec_.tape_path with
         | None -> (o.tape_seen, o.fresh)
         | Some tp ->
             (try
                let st = Unix.stat tp in
                (true, Unix.time () -. st.Unix.st_mtime
                        <= float_of_int silence_seconds)
              with _ -> blind := true; (o.tape_seen, o.fresh)) in
       let o = { o with pid_alive = alive; tape_seen; fresh } in
       (!init, o, if !blind then ["W_SUPERVISOR_BLIND"] else []))

type run_view = {
  rv_id : string;
  rv_lifecycle : string option;
  rv_harness : string;
  rv_warnings : string list;
}

let fold_runs ~quest ~silence_seconds =
  match derivations_dir () with
  | None -> ([], [])
  | Some dir ->
      let names = try Array.to_list (Sys.readdir dir) with _ -> [] in
      let views = List.filter_map (fun n ->
        if not (Filename.check_suffix n ".jsonl") then None
        else
          let path = Filename.concat dir n in
          let (init, obs, warns) = fold_run_file ~silence_seconds path in
          match init with
          | None -> None
          | Some rec_ ->
              if rec_.quest <> None && rec_.quest <> Some quest then None
              else Some {
                rv_id = if rec_.run_id <> "" then rec_.run_id
                        else Filename.remove_extension n;
                rv_lifecycle = derive_lifecycle init obs;
                rv_harness = rec_.harness;
                rv_warnings = warns;
              }) names in
      let warns = List.concat_map (fun v -> v.rv_warnings) views in
      (views, warns)

(* ---------- argv ---------- *)
let positive_seconds flag v =
  let n = try int_of_string v with _ -> -1 in
  if n <= 0 || string_of_int n <> v then
    usage (flag ^ " needs a bare positive integer, got: " ^ v)
  else n

type sup_flags = {
  engine : string option;
  timeout_seconds : int;
  silence_seconds : int;
  grace_seconds : int option;
}

let parse_sup_flags args =
  let rec loop acc = function
    | [] -> acc
    | "--engine" :: v :: rest ->
        if acc.engine <> None then usage "duplicate flag --engine";
        if v <> "muse-code" && v <> "pi" then
          usage "--engine must be muse-code or pi";
        loop { acc with engine = Some v } rest
    | "--timeout-seconds" :: v :: rest ->
        loop { acc with timeout_seconds = positive_seconds "--timeout-seconds" v } rest
    | "--silence-seconds" :: v :: rest ->
        loop { acc with silence_seconds = positive_seconds "--silence-seconds" v } rest
    | "--grace-seconds" :: v :: rest ->
        if acc.grace_seconds <> None then usage "duplicate flag --grace-seconds";
        loop { acc with grace_seconds = Some (positive_seconds "--grace-seconds" v) } rest
    | ["--engine"] | ["--timeout-seconds"] | ["--silence-seconds"] | ["--grace-seconds"] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop { engine = None; timeout_seconds = 30; silence_seconds = 600;
         grace_seconds = None } args

let split_positional args =
  let rec go pos flags = function
    | [] -> (List.rev pos, flags)
    | a :: rest when String.length a >= 2 && a.[0] = '-' && a.[1] = '-' ->
        (List.rev pos, a :: rest @ flags)
    | a :: rest -> go (a :: pos) flags rest in
  go [] [] args

(* ---------- verdict helpers ---------- *)
let run_json v =
  `Assoc [
    ("run_id", json_str v.rv_id);
    ("lifecycle", (match v.rv_lifecycle with Some l -> json_str l | None -> `Null));
    ("harness", json_str v.rv_harness);
  ]

let dedup xs =
  List.fold_left (fun acc x -> if List.mem x acc then acc else acc @ [x]) [] xs

(* ---------- supervisor ---------- *)
let do_supervisor quest args =
  check_slug quest;
  let (pos, fl) = split_positional args in
  if pos <> [] then usage "stray positional in supervisor";
  let fl = parse_sup_flags fl in
  ignore fl.grace_seconds;
  (match fold_quest quest with None -> not_found "quest" quest | Some _ -> ());
  (* engine stated here (no single Run); a contradiction with
     any folded InitRecord is a usage error *)
  let (runs0, _) = fold_runs ~quest ~silence_seconds:fl.silence_seconds in
  (match fl.engine with
   | Some e ->
       if List.exists (fun v -> v.rv_harness <> "" && v.rv_harness <> e) runs0 then
         usage "--engine contradicts a Run InitRecord"
   | None -> ());
  let deadline = Unix.time () +. float_of_int fl.timeout_seconds in
  let last_key = ref "" in
  let streamed = ref [] in
  let rec tick () =
    (* tell: derive Runs; watch: passive observation only,
       this loop never signals a pid *)
    let (runs, run_warns) = fold_runs ~quest ~silence_seconds:fl.silence_seconds in
    (* judge: fresh quest read, never a cached view *)
    let (view, inbox, rollup, _qs) = Render.quest_view quest in
    ignore view;
    let key = String.concat ";" (
      List.map (fun v -> v.rv_id ^ "=" ^
        (match v.rv_lifecycle with Some l -> l | None -> "?")) runs)
      ^ "|" ^ rollup ^ "|" ^ string_of_int (List.length inbox) in
    if key <> !last_key then begin
      last_key := key;
      let row = `Assoc [
        ("kind", json_str "lifecycle_change");
        ("quest", json_str quest);
        ("rollup", json_str rollup);
        ("runs", `List (List.map run_json runs));
      ] in
      streamed := row :: !streamed;
      print_endline (Yojson.Safe.to_string row);
      flush stdout
    end;
    let finish outcome =
      let orphans = List.filter_map (fun v ->
        if v.rv_lifecycle = Some "orphaned" then Some (json_str v.rv_id)
        else None) runs in
      let warnings = dedup run_warns in
      let fields = [
        ("ok", `Bool true); ("quest", json_str quest);
        ("outcome", json_str outcome);
        ("settled", `Bool (outcome = "settled"));
        ("rollup", json_str rollup);
        ("runs", `List (List.map run_json runs));
        ("inbox", `List inbox);
        ("orphans", `List orphans);
      ] in
      let fields = if warnings = [] then fields
        else fields @ [("warnings", `List (List.map json_str warnings))] in
      print_endline (Yojson.Safe.to_string (`Assoc fields));
      exit_of_outcome outcome in
    if rollup = "landed" then finish "settled"
    else if inbox <> [] then finish "human_gate"
    else if Unix.time () >= deadline then finish "timeout"
    else begin
      ignore (Unix.select [] [] [] 1.0);
      tick ()
    end in
  tick ()

(* ---------- init-check ---------- *)
let tape_source = function
  | "muse-code" ->
      (match Sys.getenv_opt "HOME" with
       | Some h -> Filename.concat h ".local/share/muse/sessions"
       | None -> ".local/share/muse/sessions")
  | _ ->
      (match Sys.getenv_opt "HOME" with
       | Some h -> Filename.concat h ".pi/sessions"
       | None -> ".pi/sessions")

let do_init_check args =
  let (pos, fl) = split_positional args in
  if pos <> [] then usage "stray positional in init-check";
  let engines = match fl with
    | [] -> ["muse-code"; "pi"]
    | ["--engine"; e] ->
        if e <> "muse-code" && e <> "pi" then
          usage "--engine must be muse-code or pi";
        [e]
    | ["--engine"] -> usage "flag needs a value"
    | f :: _ -> usage ("unknown flag: " ^ f) in
  let checks = List.map (fun e ->
    let src = tape_source e in
    let present = try Sys.is_directory src with _ -> false in
    (`Assoc [
       ("harness", json_str e); ("tape_source", json_str src);
       ("present", `Bool present);
     ], present)) engines in
  let blind = List.exists (fun (_, p) -> not p) checks in
  let fields = [
    ("ok", `Bool true);
    ("checks", `List (List.map fst checks));
  ] in
  let fields = if blind then
    fields @ [("warnings", `List [json_str "W_SUPERVISOR_BLIND"])] else fields in
  print_endline (Yojson.Safe.to_string (`Assoc fields));
  0

(* ---------- find-tape (mvp.2) ---------- *)
(* SHA-256 over the exact entry line: pointer digests are
   verified from the tape bytes themselves, never trusted. *)
let sha256_hex s =
  let k = [|
    0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l; 0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
    0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l; 0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
    0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl; 0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
    0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l; 0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
    0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l; 0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
    0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l; 0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
    0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l; 0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
    0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l; 0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l |] in
  let h = [| 0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
             0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l |] in
  let rotr x n = Int32.logor (Int32.shift_right_logical x n) (Int32.shift_left x (32 - n)) in
  let len = String.length s in
  let bitlen = Int64.mul (Int64.of_int len) 8L in
  let pad_zeros = (56 - (len + 1) mod 64 + 64) mod 64 in
  let total = len + 1 + pad_zeros + 8 in
  let buf = Bytes.make total '\x00' in
  Bytes.blit_string s 0 buf 0 len;
  Bytes.set buf len '\x80';
  for i = 0 to 7 do
    Bytes.set buf (total - 1 - i)
      (Char.chr (Int64.to_int (Int64.logand (Int64.shift_right_logical bitlen (8 * i)) 0xffL)))
  done;
  let w = Array.make 64 0l in
  for chunk = 0 to total / 64 - 1 do
    let base = chunk * 64 in
    for i = 0 to 15 do
      let o = base + i * 4 in
      w.(i) <- Int32.logor (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf o))) 24)
        (Int32.logor (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf (o + 1)))) 16)
        (Int32.logor (Int32.shift_left (Int32.of_int (Char.code (Bytes.get buf (o + 2)))) 8)
           (Int32.of_int (Char.code (Bytes.get buf (o + 3))))))
    done;
    for i = 16 to 63 do
      let s0 = Int32.logxor (rotr w.(i - 15) 7) (Int32.logxor (rotr w.(i - 15) 18) (Int32.shift_right_logical w.(i - 15) 3)) in
      let s1 = Int32.logxor (rotr w.(i - 2) 17) (Int32.logxor (rotr w.(i - 2) 19) (Int32.shift_right_logical w.(i - 2) 10)) in
      w.(i) <- Int32.add w.(i - 16) (Int32.add s0 (Int32.add w.(i - 7) s1))
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2) and d = ref h.(3) in
    let e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and hh = ref h.(7) in
    for i = 0 to 63 do
      let s1 = Int32.logxor (rotr !e 6) (Int32.logxor (rotr !e 11) (rotr !e 25)) in
      let ch = Int32.logxor (Int32.logand !e !f) (Int32.logand (Int32.lognot !e) !g) in
      let t1 = Int32.add !hh (Int32.add s1 (Int32.add ch (Int32.add k.(i) w.(i)))) in
      let s0 = Int32.logxor (rotr !a 2) (Int32.logxor (rotr !a 13) (rotr !a 22)) in
      let maj = Int32.logxor (Int32.logand !a !b) (Int32.logxor (Int32.logand !a !c) (Int32.logand !b !c)) in
      let t2 = Int32.add s0 maj in
      hh := !g; g := !f; f := !e; e := Int32.add !d t1;
      d := !c; c := !b; b := !a; a := Int32.add t1 t2
    done;
    h.(0) <- Int32.add h.(0) !a; h.(1) <- Int32.add h.(1) !b;
    h.(2) <- Int32.add h.(2) !c; h.(3) <- Int32.add h.(3) !d;
    h.(4) <- Int32.add h.(4) !e; h.(5) <- Int32.add h.(5) !f;
    h.(6) <- Int32.add h.(6) !g; h.(7) <- Int32.add h.(7) !hh
  done;
  let hex = Buffer.create 64 in
  Array.iter (fun x ->
    for i = 7 downto 0 do
      let nib = Int32.to_int (Int32.logand (Int32.shift_right_logical x (i * 4)) 0xfl) in
      Buffer.add_char hex ("0123456789abcdef".[nib])
    done) h;
  Buffer.contents hex

let all_init_records () =
  match derivations_dir () with
  | None -> []
  | Some dir ->
      let names = try Array.to_list (Sys.readdir dir) with _ -> [] in
      List.sort String.compare names |> List.concat_map (fun n ->
        if not (Filename.check_suffix n ".jsonl") then []
        else
          let text = read_file_or (Filename.concat dir n) "" in
          let found = ref [] in
          String.split_on_char '\n' text |> List.iter (fun ln ->
            let ln = String.trim ln in
            if ln <> "" then
              try
                let j = Yojson.Safe.from_string ln in
                if get_str j "kind" "" = "init_record" then
                  found := {
                    run_id = (let r = get_str j "run_id" "" in
                              if r <> "" then r else Filename.remove_extension n);
                    harness = get_str j "harness" "";
                    session_id = get_opt j "session_id";
                    pid = get_int_opt j "pid";
                    tape_path = get_opt j "tape_path";
                    quest = get_opt j "quest";
                    exp = get_opt j "exp";
                  } :: !found
              with _ -> ());
          List.rev !found)

let tape_roots = function
  | "pi" ->
      (match Sys.getenv_opt "BP3_PI_TAPE_DIR" with
       | Some d when d <> "" -> [d]
       | _ -> (match Sys.getenv_opt "HOME" with
               | Some home -> [Filename.concat home ".pi/agent/sessions";
                               Filename.concat home ".pi/sessions"]
               | None -> [".pi/agent/sessions"; ".pi/sessions"]))
  | _ ->
      (match Sys.getenv_opt "BP3_MUSE_TAPE_DIR" with
       | Some d when d <> "" -> [d]
       | _ -> (match Sys.getenv_opt "HOME" with
               | Some home -> [Filename.concat home ".local/share/muse/sessions"]
               | None -> [".local/share/muse/sessions"]))

let rec collect_tapes dir acc =
  let entries = try Array.to_list (Sys.readdir dir) with _ -> [] in
  List.fold_left (fun acc n ->
    let p = Filename.concat dir n in
    if try Sys.is_directory p with _ -> false then collect_tapes p acc
    else if Filename.check_suffix n ".jsonl" then p :: acc else acc) acc entries

let member_str_opt j key =
  try match Yojson.Safe.Util.member key j with `String s -> Some s | _ -> None
  with _ -> None

let entry_id_of_line ln =
  try
    let j = Yojson.Safe.from_string ln in
    (match member_str_opt j "id" with Some _ as v -> v | None ->
     match member_str_opt j "uuid" with Some _ as v -> v | None ->
     match member_str_opt j "session_id" with Some _ as v -> v | None ->
     (* muse retained frames wrap the real record as a string *)
     try match Yojson.Safe.Util.member "children" j with
       | `List (first :: _) ->
           (match member_str_opt first "record_json" with
            | Some raw ->
                (try let inner = Yojson.Safe.from_string raw in
                     member_str_opt inner "id"
                 with _ -> None)
            | None -> None)
       | _ -> None
     with _ -> None)
  with _ -> None

(* A tape references a Run only through a binding, never a
   bare mention: BP3_RUN_ID=<id> in a command or a stamped
   "run_id" field. A session is referenced by owning it. *)
let tape_references_run text run =
  contains_sub text ("BP3_RUN_ID=" ^ run)
  || contains_sub text ("\"run_id\":\"" ^ run ^ "\"")
  || contains_sub text ("\"run_id\": \"" ^ run ^ "\"")

let tape_references_session text session =
  contains_sub text ("\"session_id\":\"" ^ session ^ "\"")
  || contains_sub text ("\"session_id\": \"" ^ session ^ "\"")

let session_id_of_tape path =
  let text = read_file_or path "" in
  let lines = String.split_on_char '\n' text in
  let from_lines =
    List.fold_left (fun acc ln ->
      match acc with Some _ -> acc | None ->
        (try
           let j = Yojson.Safe.from_string (String.trim ln) in
           (match member_str_opt j "type" with
            | Some "session" -> member_str_opt j "id"
            | _ ->
                (match member_str_opt j "session_id" with Some _ as v -> v | None ->
                 try match Yojson.Safe.Util.member "children" j with
                   | `List (first :: _) ->
                       (match member_str_opt first "record_json" with
                        | Some raw ->
                            (try let inner = Yojson.Safe.from_string raw in
                                 (try match Yojson.Safe.Util.member "stream" inner with
                                    | `Assoc fs -> (match List.assoc_opt "id" fs with
                                                    | Some (`String s) -> Some s | _ -> None)
                                    | _ -> None
                                  with _ -> None)
                             with _ -> None)
                        | None -> None)
                   | _ -> None
                 with _ -> None))
         with _ -> None)) None lines in
  match from_lines with
  | Some _ as v -> v
  | None ->
      if Filename.basename path = "session.jsonl"
      then Some (Filename.basename (Filename.dirname path)) else None

let extract_run_ids text =
  let ids = ref [] in
  let add v = if v <> "" && not (List.mem v !ids) then ids := v :: !ids in
  let scan marker parse =
    let rec go from =
      if from < String.length text then
        match (try Some (Str.search_forward (Str.regexp_string marker) text from) with _ -> None) with
        | Some i -> parse (i + String.length marker); go (i + String.length marker)
        | None -> () in
    go 0 in
  scan "BP3_RUN_ID=" (fun start ->
    let rec take j = if j < String.length text &&
      ((text.[j] >= 'a' && text.[j] <= 'z') || (text.[j] >= 'A' && text.[j] <= 'Z') ||
       (text.[j] >= '0' && text.[j] <= '9') || text.[j] = '-' || text.[j] = '_' || text.[j] = '.')
      then take (j + 1) else j in
    let stop = take start in
    if stop > start then add (String.sub text start (stop - start)));
  scan "\"run_id\":\"" (fun start ->
    match (try Some (String.index_from text start '"') with _ -> None) with
    | Some stop -> add (String.sub text start (stop - start))
    | None -> ());
  List.rev !ids

type ft_flags = {
  mutable ft_run : string option; mutable ft_session : string option;
  mutable ft_entry : string option;
  mutable ft_before : int; mutable ft_after : int;
  mutable ft_before_set : bool; mutable ft_after_set : bool;
}

let nonneg_int flag v =
  let n = try int_of_string v with _ -> -1 in
  if n < 0 || string_of_int n <> v then
    usage (flag ^ " needs a non-negative integer, got: " ^ v)
  else n

let parse_ft_flags args =
  let fl = { ft_run = None; ft_session = None; ft_entry = None;
             ft_before = 0; ft_after = 0; ft_before_set = false; ft_after_set = false } in
  let rec loop = function
    | [] -> fl
    | "--run-id" :: v :: rest ->
        if fl.ft_run <> None then usage "duplicate flag --run-id";
        fl.ft_run <- Some v; loop rest
    | "--session-id" :: v :: rest ->
        if fl.ft_session <> None then usage "duplicate flag --session-id";
        fl.ft_session <- Some v; loop rest
    | "--entry" :: v :: rest ->
        if fl.ft_entry <> None then usage "duplicate flag --entry";
        fl.ft_entry <- Some v; loop rest
    | "--before-entries" :: v :: rest ->
        if fl.ft_before_set then usage "duplicate flag --before-entries";
        fl.ft_before <- nonneg_int "--before-entries" v; fl.ft_before_set <- true; loop rest
    | "--after-entries" :: v :: rest ->
        if fl.ft_after_set then usage "duplicate flag --after-entries";
        fl.ft_after <- nonneg_int "--after-entries" v; fl.ft_after_set <- true; loop rest
    | ["--run-id"] | ["--session-id"] | ["--entry"] | ["--before-entries"] | ["--after-entries"] ->
        usage "flag needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        (match String.index_opt f '=' with
         | Some _ -> usage ("unknown flag form: " ^ f)
         | None -> usage ("unknown flag: " ^ f))
    | stray :: _ -> usage ("stray positional: " ^ stray) in
  loop args

type tape_entry = {
  te_index : int; te_id : string option; te_offset : int; te_line : string;
}

let tape_entries path =
  let text = read_file_or path "" in
  let n = String.length text in
  let rec go idx off acc =
    if off >= n then List.rev acc
    else
      let stop = try String.index_from text off '\n' with _ -> n in
      let ln = String.sub text off (stop - off) in
      if String.trim ln = "" then go idx (stop + 1) acc
      else go (idx + 1) (stop + 1)
        ({ te_index = idx; te_id = entry_id_of_line ln; te_offset = off; te_line = ln } :: acc) in
  go 0 0 []

let entry_json e =
  let parsed = try Yojson.Safe.from_string e.te_line with _ -> json_str e.te_line in
  `Assoc [
    ("id", (match e.te_id with Some i -> json_str i | None -> `Null));
    ("index", `Int e.te_index);
    ("byte_offset", `Int e.te_offset);
    ("byte_length", `Int (String.length e.te_line));
    ("digest", json_str ("sha256:" ^ sha256_hex e.te_line));
    ("entry", parsed);
  ]

let ambiguous what candidates =
  err "E_AMBIGUOUS" (`Assoc [(what, `List (List.map json_str candidates))])
    ("Ambiguous " ^ what ^ "; refusing to pick: " ^ String.concat ", " candidates) 1

let do_find_tape args =
  let fl = parse_ft_flags args in
  if (fl.ft_before_set || fl.ft_after_set) && fl.ft_entry = None then
    usage "--before-entries/--after-entries need --entry";
  (match fl.ft_run, fl.ft_session with
   | None, None -> usage "find-tape needs --run-id or --session-id"
   | Some "", _ | _, Some "" -> usage "identity flags need a non-empty value"
   | _ -> ());
  let records = all_init_records () in
  let by_run = match fl.ft_run with
    | Some r -> List.filter (fun (rec_ : init_record) -> rec_.run_id = r) records
    | None -> [] in
  let by_sess = match fl.ft_session with
    | Some s -> List.filter (fun (rec_ : init_record) -> rec_.session_id = Some s) records
    | None -> [] in
  let sess_runs = dedup (List.map (fun (rec_ : init_record) -> rec_.run_id) by_sess) in
  if List.length sess_runs > 1 then ambiguous "session-id" sess_runs;
  (match fl.ft_run, fl.ft_session with
   | Some r, Some s ->
       if by_run <> [] && by_sess <> [] && sess_runs <> [r] then
         usage "--run-id and --session-id disagree";
       List.iter (fun (rec_ : init_record) ->
         if rec_.session_id <> None && rec_.session_id <> Some s then
           usage "--run-id and --session-id disagree") by_run
   | _ -> ());
  let record = match by_run with
    | rec_ :: _ -> Some rec_
    | [] -> (match by_sess with rec_ :: _ -> Some rec_ | [] -> None) in
  (match by_run with
   | _ :: _ :: _ ->
       let tapes = dedup (List.filter_map (fun (rec_ : init_record) -> rec_.tape_path) by_run) in
       let sessions = dedup (List.filter_map (fun (rec_ : init_record) -> rec_.session_id) by_run) in
       if List.length tapes > 1 || List.length sessions > 1 then
         ambiguous "run-id" (tapes @ sessions)
   | _ -> ());
  let run_needles = dedup (
    (match fl.ft_run with Some r -> [r] | None -> []) @
    (match record with Some rec_ -> [rec_.run_id] | None -> [])) in
  let sess_needles = dedup (
    (match fl.ft_session with Some s -> [s] | None -> []) @
    (match record with Some rec_ -> (match rec_.session_id with Some s -> [s] | None -> []) | None -> [])) in
  let tape_matches text path =
    List.exists (fun nd -> tape_references_run text nd) run_needles
    || List.exists (fun nd -> tape_references_session text nd
                              || session_id_of_tape path = Some nd) sess_needles in
  (* resolve (wal, harness, session_id, pid, run_id) *)
  let record_hit =
    match record with
    | Some rec_ ->
        (match rec_.tape_path with
         | Some tp when Sys.file_exists tp ->
             let text = read_file_or tp "" in
             if tape_matches text tp
             then Some (tp, rec_.harness, rec_.session_id, rec_.pid, rec_.run_id)
             else None
         | Some tp ->
             err "E_NOT_FOUND" (`Assoc [("wal", json_str tp); ("run_id", json_str rec_.run_id)])
               ("Tape named by the InitRecord does not exist: " ^ tp) 1
         | None -> None)
    | None -> None in
  let (wal, harness, session_id, pid, run_id) =
    match record_hit with
    | Some hit -> hit
    | None ->
        let harnesses = match record with
          | Some rec_ when rec_.harness <> "" -> [rec_.harness]
          | _ -> ["muse-code"; "pi"] in
        let candidates = List.concat_map (fun h ->
          List.concat_map (fun root_ -> collect_tapes root_ []) (tape_roots h)
          |> List.filter_map (fun p ->
               let text = read_file_or p "" in
               if tape_matches text p
               then Some (p, h, text) else None)) harnesses in
        let paths = dedup (List.map (fun (p, _, _) -> p) candidates) in
        (match paths with
         | [] ->
             let facts = match fl.ft_run with
               | Some r -> `Assoc [("run_id", json_str r)]
               | None -> `Assoc [("session_id", json_str (match fl.ft_session with Some s -> s | None -> ""))] in
             err "E_NOT_FOUND" facts "No tape references that run; no guess made." 1
         | _ :: _ :: _ -> ambiguous "tape" paths
         | [p] ->
             let (_, h, text) = List.find (fun (cp, _, _) -> cp = p) candidates in
             let sess = (match record with Some rec_ -> rec_.session_id | None -> None) in
             let sess = match sess with Some _ -> sess | None -> session_id_of_tape p in
             let sess = match sess with Some _ -> sess | None -> fl.ft_session in
             let run = (match record with Some rec_ -> rec_.run_id | None ->
                        match fl.ft_run with Some r -> r | None ->
                        match extract_run_ids text with
                        | [r] -> r
                        | _ :: _ :: _ -> ambiguous "session-id" (extract_run_ids text)
                        | [] -> (match fl.ft_session with Some s -> s | None -> "")) in
             let pid = match record with Some rec_ -> rec_.pid | None -> None in
             (p, h, sess, pid, run)) in
  (match fl.ft_session, session_id with
   | Some s, Some found when s <> found ->
       err "E_NOT_FOUND" (`Assoc [("session_id", json_str s)])
         "The tape for that run carries a different session-id." 1
   | _ -> ());
  let base = [
    ("ok", `Bool true);
    ("run_id", json_str run_id);
    ("harness", json_str harness);
    ("session_id", (match session_id with Some s -> json_str s | None -> `Null));
    ("wal", json_str wal);
    ("tape_path", json_str wal);
    ("pid", (match pid with Some p -> `Int p | None -> `Null));
  ] in
  (match fl.ft_entry with
   | None -> print_endline (Yojson.Safe.to_string (`Assoc base)); 0
   | Some wanted ->
       let entries = tape_entries wal in
       (match List.find_opt (fun e -> e.te_id = Some wanted) entries with
        | None ->
            err "E_NOT_FOUND" (`Assoc [("entry", json_str wanted); ("wal", json_str wal)])
              ("No entry with that id in the tape: " ^ wanted) 1
        | Some hit ->
            let lo = max 0 (hit.te_index - fl.ft_before) in
            let hi = min (List.length entries - 1) (hit.te_index + fl.ft_after) in
            let window = List.filter (fun e -> e.te_index >= lo && e.te_index <= hi) entries in
            let fields = base @ [
              ("entry", entry_json hit);
              ("entries", `List (List.map entry_json window));
            ] in
            print_endline (Yojson.Safe.to_string (`Assoc fields)); 0))

(* ---------- later-exps door ---------- *)
let not_yet verb =
  err "E_UNSUPPORTED" (`Assoc [("verb", json_str verb)])
    ("bp3 harness " ^ verb ^ " is not implemented yet; its exp owns it.") 1

(* ---------- help (docstrings beside dispatch) ---------- *)
let help_harness = "bp3 harness - harness machinery door. Verbs:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]   passive loop: tell -> watch -> judge -> finalize\n\
  bp3 harness init-check [--engine muse-code|pi]   probe tape sources; blindness is W_SUPERVISOR_BLIND, never blocking\n\
  bp3 harness find-tape --run-id <id> [--entry <id>] [--before-entries <n>] [--after-entries <n>]   InitRecord-first run-id -> tape; --session-id <id> is a reverse lookup\n\
  bp3 harness watch --run-id <id>                  blocking watch (owned by a later exp)\n\
  bp3 harness desk <verb> ...                      desks (owned by a later exp)\n\
Aliases: s=supervisor, i=init-check, f=find-tape, w=watch, d=desk. Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_supervisor = "bp3 harness supervisor - passive supervisor loop for one quest:\n\
  bp3 harness supervisor <quest> [--engine muse-code|pi] [--timeout-seconds <n>] [--silence-seconds <n>] [--grace-seconds <n>]\n\
  Streams NDJSON lifecycle_change rows on stdout, ends with one JSON verdict {ok, quest, outcome, settled, rollup, runs, inbox, orphans}.\n\
  Outcomes and exit classes: settled=0, watchdog_killed=1 (terminal), timeout=3 (retryable), human_gate=4 (needs-human).\n\
  Durations are bare positive integers; 0, negatives, and suffixed values are usage errors.\n\
Example: bp3 harness supervisor toy --timeout-seconds 1800\n"

let help_init_check = "bp3 harness init-check - probe tape sources per harness:\n\
  bp3 harness init-check [--engine muse-code|pi]\n\
  Emits {ok, checks}; a missing or reshaped tape source adds W_SUPERVISOR_BLIND to warnings and never blocks work.\n\
Example: bp3 harness init-check --engine muse-code\n"

let help_find_tape = "bp3 harness find-tape - InitRecord-first tape lookup:\n\
  bp3 harness find-tape --run-id <id> [--entry <id>] [--before-entries <n>] [--after-entries <n>]\n\
  bp3 harness find-tape --session-id <id>\n\
  Run-id is the sole primary key; --session-id is a reverse lookup that must resolve to exactly one run-id. Both, neither, or disagreeing identity flags are E_USAGE; misses are E_NOT_FOUND; ambiguity is E_AMBIGUOUS and names every candidate.\n\
  --entry returns the one digest-verified entry (sha256 over its exact line, with byte range), widened by --before-entries/--after-entries (non-negative integers, default 0).\n\
  Emits {ok, run_id, harness, session_id, wal, pid} or, with --entry, plus {entry, entries}.\n\
Example: bp3 harness find-tape --run-id 20261115T000000Z-submit-pi-model-c1\n"

let is_help = function "-h" | "--help" -> true | _ -> false

let normalize_verb = function
  | "s" | "supervisor" -> "supervisor"
  | "i" | "init-check" -> "init-check"
  | "f" | "find-tape" -> "find-tape"
  | "w" | "watch" -> "watch"
  | "d" | "desk" -> "desk"
  | other -> other

let run = function
  | [] -> usage "harness needs a verb: supervisor, init-check, find-tape, watch, or desk"
  | [h] when is_help h -> print_string help_harness; 0
  | verb :: (h :: _) when is_help h ->
      print_string (match normalize_verb verb with
        | "supervisor" -> help_supervisor
        | "init-check" -> help_init_check
        | "find-tape" -> help_find_tape
        | _ -> help_harness); 0
  | verb_raw :: rest ->
      (match normalize_verb verb_raw with
       | "supervisor" ->
           (match rest with
            | quest :: tail -> do_supervisor quest tail
            | [] -> usage "supervisor needs a quest")
       | "init-check" -> do_init_check rest
       | "find-tape" -> do_find_tape rest
       | "watch" -> not_yet "watch"
       | "desk" -> not_yet "desk"
       | other -> usage ("unknown harness verb: " ^ other))
