(* util — small pure + stdlib/unix/yojson primitives shared across src/quest/.
   Zero domain knowledge: no quest, node, or ledger concepts live here. *)

(* ---------- string ---------- *)
let contains_sub s sub =
  let n = String.length s and m = String.length sub in
  if m = 0 then true
  else if m > n then false
  else
    let rec at i j = j = m || (s.[i + j] = sub.[j] && at i (j + 1)) in
    let rec loop i = i + m <= n && (at i 0 || loop (i + 1)) in
    loop 0

let strip_prefix ~prefix s =
  let plen = String.length prefix and slen = String.length s in
  if slen >= plen && String.sub s 0 plen = prefix then
    Some (String.sub s plen (slen - plen))
  else None

(* ---------- filesystem ---------- *)
let rec mkdir_p dir =
  if dir = "" || dir = "." || dir = "/" || Sys.file_exists dir then ()
  else begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755
    with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let write_counter = ref 0

let write_file_atomic path content =
  incr write_counter;
  let tmp = Printf.sprintf "%s.tmp.%d.%d" path (Unix.getpid ()) !write_counter in
  let fd = Unix.openfile tmp [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o644 in
  (try
     let n = Unix.write_substring fd content 0 (String.length content) in
     if n <> String.length content then
       raise (Unix.Unix_error (Unix.EIO, "write", path));
     Unix.fsync fd
   with e ->
     (try Unix.close fd with _ -> ());
     (try Unix.unlink tmp with _ -> ());
     raise e);
  Unix.close fd;
  Sys.rename tmp path

(* ---------- time ---------- *)
(* UTC ISO-8601 (YYYY-MM-DDTHH:MM:SSZ) -> epoch seconds (Howard Hinnant's civil algorithm). *)
let epoch_of_iso s =
  let digit i =
    let c = s.[i] in
    if c < '0' || c > '9' then raise Exit
    else Char.code c - Char.code '0' in
  let num i n =
    let rec go k acc =
      if k = n then acc else go (k + 1) (acc * 10 + digit (i + k)) in
    go 0 0 in
  try
    if String.length s <> 20 || s.[4] <> '-' || s.[7] <> '-'
       || s.[10] <> 'T' || s.[13] <> ':' || s.[16] <> ':'
       || s.[19] <> 'Z' then None
    else
      let y = num 0 4 and mo = num 5 2 and d = num 8 2 in
      let hh = num 11 2 and mi = num 14 2 and ss = num 17 2 in
      if mo < 1 || mo > 12 || d < 1 || d > 31 || hh > 23
         || mi > 59 || ss > 60 then None
      else
        let y = if mo <= 2 then y - 1 else y in
        let era = (if y >= 0 then y else y - 399) / 400 in
        let yoe = y - era * 400 in
        let mp = (mo + 9) mod 12 in
        let doy = (153 * mp + 2) / 5 + d - 1 in
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy in
        let days = era * 146097 + doe - 719468 in
        Some (float_of_int (((days * 24 + hh) * 60 + mi) * 60 + ss))
  with _ -> None

(* ---------- total Yojson helpers ---------- *)
let member key j =
  match j with
  | `Assoc fs -> (match List.assoc_opt key fs with Some v -> v | None -> `Null)
  | _ -> `Null

let get_str_opt j key =
  match member key j with `String s -> Some s | _ -> None

let get_str j key default =
  match member key j with `String s -> s | _ -> default

let get_int_opt j key =
  match member key j with `Int n -> Some n | _ -> None

let get_int j key default =
  match member key j with `Int n -> n | _ -> default

let get_bool j key default =
  match member key j with `Bool b -> b | _ -> default

let get_obj j key =
  match member key j with `Assoc _ as o -> Some o | _ -> None
