(* db_cli — CLI door for `bp3 db` (sqlite-control-plane db.1).
   Returns an int exit code directly so main.ml dispatches in one line
   with zero dependency on bp3_quest. *)

let help_text =
  {|bp3 db — machine-local SQLite control-plane store.

Usage:
  bp3 db info [--format json|table]    show resolved DB path, schema version, journal mode, counts
  bp3 db -h | --help                   show this help (never touches or creates the DB)

Environment:
  BP3_DB          override SQLite file path (wins over XDG_DATA_HOME / HOME)
  XDG_DATA_HOME   base data dir -> $XDG_DATA_HOME/bp3/bp3.sqlite
  HOME            fallback -> $HOME/.local/share/bp3/bp3.sqlite

Exit codes:
  0  ok
  1  DB error (E_DB_ERROR)
  2  usage error (E_USAGE)
|}

let is_help = function "-h" | "--help" -> true | _ -> false

let parse_info_flags args =
  let rec loop fmt fmt_set = function
    | [] -> fmt
    | "--format" :: v :: rest ->
        if fmt_set then Db.usage "duplicate flag --format";
        if v <> "json" && v <> "table" then Db.usage "--format must be json or table";
        loop v true rest
    | [ "--format" ] -> Db.usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | stray :: _ -> Db.usage ("stray positional: " ^ stray)
  in
  loop "json" false args

let format_info_table (i : Db.db_info) =
  Db.format_table [ "field"; "value" ]
    [
      [ "db_path"; i.db_path ];
      [ "schema_version"; string_of_int i.schema_version ];
      [ "journal_mode"; i.journal_mode ];
      [ "repos"; string_of_int i.repos_count ];
      [ "tickets_open"; string_of_int i.tickets_open ];
      [ "tickets_total"; string_of_int i.tickets_total ];
    ]

let run_inner ?db_path = function
  | [] -> Db.usage "db needs a subcommand: info (see bp3 db -h)"
  | h :: _ when is_help h ->
      print_string help_text;
      0
  | "info" :: h :: _ when is_help h ->
      print_string help_text;
      0
  | "info" :: rest ->
      let fmt = parse_info_flags rest in
      let i = Db.info ?path:db_path () in
      (match fmt with
       | "table" -> print_string (format_info_table i)
       | _ -> print_endline (Yojson.Safe.to_string (Db.info_json i)));
      0
  | sub :: _ -> Db.usage ("unknown db subcommand: " ^ sub ^ " (expected: info)")

let run ?db_path args =
  try run_inner ?db_path args
  with Db.Error (code, json) ->
    print_endline (Yojson.Safe.to_string json);
    code
