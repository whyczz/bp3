type json = Yojson.Safe.t

exception Error of string

let fail s = raise (Error s)
let obj fields = `Assoc fields
let str s = `String s
let int n = `Int n

let get j k =
  match j with
  | `Assoc xs -> Option.value (List.assoc_opt k xs) ~default:`Null
  | _ -> fail "expected object"

let string = function
  | `String s -> s
  | _ -> fail "expected string"

let field j k =
  try string (get j k) with Error _ -> fail ("missing/string field: " ^ k)

let number = function
  | `Int n -> n
  | _ -> fail "expected integer"

let boolean = function
  | `Bool b -> b
  | _ -> fail "expected boolean"

let list = function
  | `List xs -> xs
  | _ -> fail "expected array"

let optional j k default =
  match get j k with
  | `Null -> default
  | x -> string x

let rec canonical = function
  | `Assoc xs ->
      let xs = List.sort (fun (a, _) (b, _) -> String.compare a b) xs in
      let rec unique = function
        | (a, _) :: ((b, _) :: _ as rest) ->
            if a = b then fail ("duplicate JSON key: " ^ a) else unique rest
        | _ -> ()
      in
      unique xs;
      `Assoc (List.map (fun (k, v) -> (k, canonical v)) xs)
  | `List xs -> `List (List.map canonical xs)
  | x -> x

let encode j = Yojson.Safe.to_string (canonical j)

let decode s =
  try canonical (Yojson.Safe.from_string s) with Yojson.Json_error e -> fail e

let id s =
  if
    s = ""
    || String.length s > 100
    || not
         (String.for_all
            (function
              | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' -> true
              | _ -> false)
            s)
  then fail "IDs must be 1-100 ASCII letters, digits, dash or underscore";
  s

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () -> really_input_string ic (in_channel_length ic))

let write_file path text =
  let oc = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out oc)
    (fun () -> output_string oc text)

let rec mkdir path =
  if not (Sys.file_exists path) then (
    let parent = Filename.dirname path in
    if parent <> path then mkdir parent;
    Unix.mkdir path 0o700)

let absolute path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
  else path

let random () =
  let ic = open_in_bin "/dev/urandom" in
  let bytes =
    Fun.protect
      ~finally:(fun () -> close_in ic)
      (fun () -> really_input_string ic 24)
  in
  String.concat ""
    (List.init (String.length bytes) (fun i ->
         Printf.sprintf "%02x" (Char.code bytes.[i])))

let now () = Unix.gettimeofday ()

let envelope ?(auth = `Null) operation payload =
  obj
    [
      ("v", int 1);
      ("op_id", str (random ()));
      ("op", str operation);
      ("auth", auth);
      ("payload", payload);
    ]

let validate_brief j =
  List.iter
    (fun k -> if String.trim (field j k) = "" then fail ("empty brief " ^ k))
    [ "objective"; "acceptance"; "scope"; "non_goals" ];
  let argv = List.map string (list (get j "check_argv")) in
  if argv = [] || List.hd argv = "" then fail "brief needs nonempty check_argv";
  let seconds = number (get j "max_seconds") in
  if seconds < 1 || seconds > 86400 then fail "max_seconds must be 1..86400";
  if optional j "result_kind" "code" <> "code" then
    fail "genesis supports only code results";
  if optional j "lane" "standard" <> "standard" then
    fail "genesis supports only standard lane";
  match get j "prerequisites" with
  | `Null | `List [] -> ()
  | _ -> fail "prerequisites are not implemented in genesis"
