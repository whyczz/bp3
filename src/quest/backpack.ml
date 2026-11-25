(* backpack — pure OCaml parser, validator, and serializer for committed
   per-repo backpack.toml manifests (global-skills-and-backpack-toml manifest.1).
   Stdlib-only (zero external TOML dependencies). *)

type t = {
  version : int;
  repo : string;
  grade_gate : string option;
  warden_grade_wall_s : int option;
  release_target : string option;
}

let strip_cr s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s

(* Strip '#' comments occurring outside double-quoted strings, honoring
   backslash escapes inside quotes. *)
let strip_comment s =
  let n = String.length s in
  let rec go i in_q esc =
    if i >= n then s
    else
      let c = s.[i] in
      if in_q then
        if esc then go (i + 1) true false
        else if c = '\\' then go (i + 1) true true
        else if c = '"' then go (i + 1) false false
        else go (i + 1) true false
      else if c = '"' then go (i + 1) true false
      else if c = '#' then String.sub s 0 i
      else go (i + 1) false false
  in
  go 0 false false

let parse_string ~lineno raw =
  let s = String.trim raw in
  let n = String.length s in
  if n < 2 || s.[0] <> '"' then
    Error (Printf.sprintf "line %d: expected double-quoted string" lineno)
  else
    let buf = Buffer.create n in
    let rec go i =
      if i >= n then
        Error (Printf.sprintf "line %d: unterminated string" lineno)
      else
        match s.[i] with
        | '"' ->
            let trailing = String.trim (String.sub s (i + 1) (n - i - 1)) in
            if trailing <> "" then
              Error (Printf.sprintf "line %d: unexpected trailing characters after string" lineno)
            else Ok (Buffer.contents buf)
        | '\\' ->
            if i + 1 >= n then
              Error (Printf.sprintf "line %d: trailing backslash in string" lineno)
            else begin
              match s.[i + 1] with
              | '"' -> Buffer.add_char buf '"'; go (i + 2)
              | '\\' -> Buffer.add_char buf '\\'; go (i + 2)
              | 'n' -> Buffer.add_char buf '\n'; go (i + 2)
              | 't' -> Buffer.add_char buf '\t'; go (i + 2)
              | 'r' -> Buffer.add_char buf '\r'; go (i + 2)
              | ch -> Error (Printf.sprintf "line %d: unsupported escape \\%c" lineno ch)
            end
        | c when Char.code c < 0x20 ->
            Error (Printf.sprintf "line %d: control character in string" lineno)
        | c -> Buffer.add_char buf c; go (i + 1)
    in
    go 1

let parse_int ~lineno raw =
  let s = String.trim raw in
  if s = "" then Error (Printf.sprintf "line %d: expected integer" lineno)
  else
    let len = String.length s in
    let start = if s.[0] = '-' || s.[0] = '+' then 1 else 0 in
    let digits_ok =
      start < len &&
      let rec check i =
        if i >= len then true
        else if s.[i] >= '0' && s.[i] <= '9' then check (i + 1)
        else false in
      check start in
    if not digits_ok then Error (Printf.sprintf "line %d: invalid integer %S" lineno s)
    else
      match int_of_string_opt s with
      | Some v -> Ok v
      | None -> Error (Printf.sprintf "line %d: integer out of range %S" lineno s)

let has_whitespace s =
  let n = String.length s in
  let rec go i =
    if i >= n then false
    else match s.[i] with
      | ' ' | '\t' | '\n' | '\r' -> true
      | _ -> go (i + 1) in
  go 0

let parse text =
  let lines = String.split_on_char '\n' text in
  let version = ref None in
  let repo = ref None in
  let grade_gate = ref None in
  let warden_grade_wall_s = ref None in
  let release_target = ref None in
  let seen_sections = Hashtbl.create 4 in
  let seen_keys = Hashtbl.create 8 in
  let rec loop lineno section = function
    | [] ->
        (match !version, !repo with
         | None, _ -> Error "missing required key: version"
         | _, None -> Error "missing required key: repo"
         | Some v, Some r ->
             Ok {
               version = v;
               repo = r;
               grade_gate = !grade_gate;
               warden_grade_wall_s = !warden_grade_wall_s;
               release_target = !release_target;
             })
    | raw :: rest ->
        let line = String.trim (strip_comment (strip_cr raw)) in
        if line = "" then loop (lineno + 1) section rest
        else if line.[0] = '[' then
          let len = String.length line in
          if len < 3 || line.[len - 1] <> ']' then
            Error (Printf.sprintf "line %d: malformed section header" lineno)
          else
            let sec = String.trim (String.sub line 1 (len - 2)) in
            if sec <> "grade" && sec <> "warden" && sec <> "release" then
              Error (Printf.sprintf "line %d: unknown section [%s]" lineno sec)
            else if Hashtbl.mem seen_sections sec then
              Error (Printf.sprintf "line %d: duplicate section [%s]" lineno sec)
            else begin
              Hashtbl.add seen_sections sec ();
              loop (lineno + 1) sec rest
            end
        else
          match String.index_opt line '=' with
          | None -> Error (Printf.sprintf "line %d: expected key = value" lineno)
          | Some eq ->
              let key = String.trim (String.sub line 0 eq) in
              let raw_val = String.sub line (eq + 1) (String.length line - eq - 1) in
              if key = "" || has_whitespace key then
                Error (Printf.sprintf "line %d: invalid key %S" lineno key)
              else
                let full_key = if section = "" then key else section ^ "." ^ key in
                if Hashtbl.mem seen_keys full_key then
                  Error (Printf.sprintf "line %d: duplicate key %s" lineno full_key)
                else begin
                  Hashtbl.add seen_keys full_key ();
                  let res = match full_key with
                    | "version" ->
                        (match parse_int ~lineno raw_val with
                         | Error e -> Error e
                         | Ok 1 -> version := Some 1; Ok ()
                         | Ok v -> Error (Printf.sprintf "line %d: unsupported version %d (expected 1)" lineno v))
                    | "repo" ->
                        (match parse_string ~lineno raw_val with
                         | Error e -> Error e
                         | Ok s when String.trim s = "" || has_whitespace s ->
                             Error (Printf.sprintf "line %d: repo must be a non-empty slug without spaces" lineno)
                         | Ok s -> repo := Some s; Ok ())
                    | "grade.gate" ->
                        (match parse_string ~lineno raw_val with
                         | Error e -> Error e
                         | Ok s when String.trim s = "" ->
                             Error (Printf.sprintf "line %d: grade.gate must be non-empty" lineno)
                         | Ok s -> grade_gate := Some s; Ok ())
                    | "warden.grade_wall_s" ->
                        (match parse_int ~lineno raw_val with
                         | Error e -> Error e
                         | Ok n when n <= 0 ->
                             Error (Printf.sprintf "line %d: warden.grade_wall_s must be > 0" lineno)
                         | Ok n -> warden_grade_wall_s := Some n; Ok ())
                    | "release.target" ->
                        (match parse_string ~lineno raw_val with
                         | Error e -> Error e
                         | Ok s when String.trim s = "" || has_whitespace s ->
                             Error (Printf.sprintf "line %d: release.target must be a non-empty branch name" lineno)
                         | Ok s -> release_target := Some s; Ok ())
                    | _ ->
                        Error (Printf.sprintf "line %d: unknown key %s" lineno full_key) in
                  match res with
                  | Error e -> Error e
                  | Ok () -> loop (lineno + 1) section rest
                end
  in
  loop 1 "" lines

let escape_string s =
  let buf = Buffer.create (String.length s + 4) in
  String.iter (function
    | '\\' -> Buffer.add_string buf "\\\\"
    | '"' -> Buffer.add_string buf "\\\""
    | '\n' -> Buffer.add_string buf "\\n"
    | '\t' -> Buffer.add_string buf "\\t"
    | '\r' -> Buffer.add_string buf "\\r"
    | c -> Buffer.add_char buf c) s;
  Buffer.contents buf

let render t =
  let buf = Buffer.create 160 in
  Printf.bprintf buf "version = %d\nrepo = \"%s\"\n" t.version (escape_string t.repo);
  (match t.grade_gate with
   | Some g -> Printf.bprintf buf "\n[grade]\ngate = \"%s\"\n" (escape_string g)
   | None -> ());
  (match t.warden_grade_wall_s with
   | Some n -> Printf.bprintf buf "\n[warden]\ngrade_wall_s = %d\n" n
   | None -> ());
  (match t.release_target with
   | Some tgt -> Printf.bprintf buf "\n[release]\ntarget = \"%s\"\n" (escape_string tgt)
   | None -> ());
  Buffer.contents buf

let default_config ~repo ~target =
  {
    version = 1;
    repo;
    grade_gate = Some "make check-full";
    warden_grade_wall_s = Some 300;
    release_target = Some target;
  }

let render_default ~repo ~target =
  render (default_config ~repo ~target)

let opt_str = function Some s -> `String s | None -> `Null
let opt_int = function Some n -> `Int n | None -> `Null

let to_json t =
  `Assoc [
    ("version", `Int t.version);
    ("repo", `String t.repo);
    ("grade", `Assoc [ ("gate", opt_str t.grade_gate) ]);
    ("warden", `Assoc [ ("grade_wall_s", opt_int t.warden_grade_wall_s) ]);
    ("release", `Assoc [ ("target", opt_str t.release_target) ]);
  ]

let warning_no_repo_config () =
  `Assoc [
    ("code", `String Names.w_no_repo_config);
    ("message", `String "backpack.toml not found; run bp3 init-repo to create backpack.toml");
  ]

let load_opt repo_root =
  let path = Filename.concat repo_root Layout.manifest_file in
  if not (Sys.file_exists path) then Ok None
  else
    try
      let ic = open_in_bin path in
      let text = Fun.protect ~finally:(fun () -> close_in ic)
        (fun () -> really_input_string ic (in_channel_length ic)) in
      match parse text with
      | Ok cfg -> Ok (Some cfg)
      | Error e -> Error e
    with Sys_error msg -> Error msg
