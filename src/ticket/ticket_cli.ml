(* ticket_cli — CLI door for `bp3 ticket` (sqlite-control-plane ticket.1).
   Returns an int exit code directly so main.ml dispatches in one line. *)

let help_text =
  {|bp3 ticket — cross-repo ticket queue in bp3.sqlite.

Usage:
  bp3 ticket add --to <repo> --title <text> [--from <repo>] [--kind bug|feature|note] [--body <text>]
  bp3 ticket list [--to <repo>] [--from <repo>] [--status open|claimed|done|dismissed|all] [--format json|table]
  bp3 ticket read <id> [--format json|table]
  bp3 ticket claim <id> [--by <owner>]
  bp3 ticket unclaim <id> --reason <text>
  bp3 ticket done <id> --reason <text>
  bp3 ticket dismiss <id> --reason <text>
  bp3 ticket -h | --help

Exit codes:
  0  ok
  1  state/contention/DB error (E_ALREADY_CLAIMED, E_ILLEGAL_EDGE, E_DB_ERROR)
  2  usage or not-found error (E_USAGE, E_NOT_FOUND)
|}

let is_help = function "-h" | "--help" -> true | _ -> false

let parse_id s =
  match int_of_string_opt s with
  | Some n when n >= 1 -> n
  | _ -> Db.usage ("ticket id must be a positive integer: " ^ s)

let non_empty_env name =
  match Sys.getenv_opt name with
  | Some s when String.trim s <> "" -> Some s
  | _ -> None

let default_claim_owner () =
  match non_empty_env "BP3_RUN_ID" with
  | Some s -> s
  | None -> (
      match non_empty_env "BP3_HARNESS" with
      | Some s -> s
      | None -> "human")

let parse_add_flags args =
  let rec loop to_r from_r kind title body = function
    | [] ->
        let to_repo = match to_r with Some v -> v | None -> Db.usage "--to is required" in
        let title_v = match title with Some v -> v | None -> Db.usage "--title is required" in
        (to_repo, from_r, Option.value ~default:"note" kind, title_v, Option.value ~default:"" body)
    | "--to" :: v :: rest ->
        if to_r <> None then Db.usage "duplicate flag --to";
        loop (Some v) from_r kind title body rest
    | [ "--to" ] -> Db.usage "--to needs a value"
    | "--from" :: v :: rest ->
        if from_r <> None then Db.usage "duplicate flag --from";
        loop to_r (Some v) kind title body rest
    | [ "--from" ] -> Db.usage "--from needs a value"
    | "--kind" :: v :: rest ->
        if kind <> None then Db.usage "duplicate flag --kind";
        loop to_r from_r (Some v) title body rest
    | [ "--kind" ] -> Db.usage "--kind needs a value"
    | "--title" :: v :: rest ->
        if title <> None then Db.usage "duplicate flag --title";
        loop to_r from_r kind (Some v) body rest
    | [ "--title" ] -> Db.usage "--title needs a value"
    | "--body" :: v :: rest ->
        if body <> None then Db.usage "duplicate flag --body";
        loop to_r from_r kind title (Some v) rest
    | [ "--body" ] -> Db.usage "--body needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | stray :: _ -> Db.usage ("stray positional: " ^ stray)
  in
  loop None None None None None args

let parse_list_flags args =
  let rec loop to_r from_r status fmt fmt_set = function
    | [] -> (to_r, from_r, Option.value ~default:"open" status, fmt)
    | "--to" :: v :: rest ->
        if to_r <> None then Db.usage "duplicate flag --to";
        loop (Some v) from_r status fmt fmt_set rest
    | [ "--to" ] -> Db.usage "--to needs a value"
    | "--from" :: v :: rest ->
        if from_r <> None then Db.usage "duplicate flag --from";
        loop to_r (Some v) status fmt fmt_set rest
    | [ "--from" ] -> Db.usage "--from needs a value"
    | "--status" :: v :: rest ->
        if status <> None then Db.usage "duplicate flag --status";
        loop to_r from_r (Some v) fmt fmt_set rest
    | [ "--status" ] -> Db.usage "--status needs a value"
    | "--format" :: v :: rest ->
        if fmt_set then Db.usage "duplicate flag --format";
        if v <> "json" && v <> "table" then Db.usage "--format must be json or table";
        loop to_r from_r status v true rest
    | [ "--format" ] -> Db.usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | stray :: _ -> Db.usage ("stray positional: " ^ stray)
  in
  loop None None None "json" false args

let parse_read_args args =
  let rec loop id_opt fmt fmt_set = function
    | [] -> (
        match id_opt with
        | Some id -> (id, fmt)
        | None -> Db.usage "ticket read needs <id>")
    | "--format" :: v :: rest ->
        if fmt_set then Db.usage "duplicate flag --format";
        if v <> "json" && v <> "table" then Db.usage "--format must be json or table";
        loop id_opt v true rest
    | [ "--format" ] -> Db.usage "--format needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | raw :: rest ->
        if id_opt <> None then Db.usage ("stray positional: " ^ raw);
        loop (Some (parse_id raw)) fmt fmt_set rest
  in
  loop None "json" false args

let parse_claim_args args =
  let rec loop id_opt by_opt = function
    | [] -> (
        match id_opt with
        | Some id -> (id, match by_opt with Some b -> b | None -> default_claim_owner ())
        | None -> Db.usage "ticket claim needs <id>")
    | "--by" :: v :: rest ->
        if by_opt <> None then Db.usage "duplicate flag --by";
        loop id_opt (Some v) rest
    | [ "--by" ] -> Db.usage "--by needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | raw :: rest ->
        if id_opt <> None then Db.usage ("stray positional: " ^ raw);
        loop (Some (parse_id raw)) by_opt rest
  in
  loop None None args

let parse_reason_args verb args =
  let rec loop id_opt reason_opt = function
    | [] -> (
        let id =
          match id_opt with Some id -> id | None -> Db.usage ("ticket " ^ verb ^ " needs <id>")
        in
        let reason =
          match reason_opt with Some r -> r | None -> Db.usage "--reason is required"
        in
        (id, reason))
    | "--reason" :: v :: rest ->
        if reason_opt <> None then Db.usage "duplicate flag --reason";
        loop id_opt (Some v) rest
    | [ "--reason" ] -> Db.usage "--reason needs a value"
    | f :: _ when String.length f >= 2 && f.[0] = '-' && f.[1] = '-' ->
        Db.usage ("unknown flag: " ^ f)
    | raw :: rest ->
        if id_opt <> None then Db.usage ("stray positional: " ^ raw);
        loop (Some (parse_id raw)) reason_opt rest
  in
  loop None None args

let format_list_table tickets =
  let rows =
    List.map
      (fun (t : Ticket_store.ticket) ->
        [
          string_of_int t.id;
          t.to_repo;
          t.from_repo;
          t.kind;
          t.status;
          Option.value ~default:"-" t.claimed_by;
          t.title;
        ])
      tickets
  in
  Db.format_table [ "id"; "to"; "from"; "kind"; "status"; "claimed_by"; "title" ] rows

let format_read_table (t : Ticket_store.ticket) =
  let dash = Option.value ~default:"-" in
  let meta =
    Db.format_table [ "field"; "value" ]
      [
        [ "id"; string_of_int t.id ];
        [ "to"; t.to_repo ];
        [ "from"; t.from_repo ];
        [ "kind"; t.kind ];
        [ "status"; t.status ];
        [ "claimed_by"; dash t.claimed_by ];
        [ "claimed_at"; dash t.claimed_at ];
        [ "resolved_at"; dash t.resolved_at ];
        [ "resolution_reason"; dash t.resolution_reason ];
        [ "created_at"; t.created_at ];
        [ "title"; t.title ];
      ]
  in
  if t.body = "" then meta else meta ^ "\nbody:\n" ^ t.body ^ "\n"

let print_ticket_json t =
  print_endline
    (Yojson.Safe.to_string (`Assoc [ ("ok", `Bool true); ("ticket", Ticket_store.ticket_json t) ]))

let run_inner ?db_path = function
  | [] ->
      Db.usage
        "ticket needs a subcommand: add, list, read, claim, unclaim, done, dismiss (see bp3 ticket -h)"
  | h :: _ when is_help h ->
      print_string help_text;
      0
  | ("add" | "list" | "read" | "claim" | "unclaim" | "done" | "dismiss") :: rest
    when List.exists is_help rest ->
      print_string help_text;
      0
  | "add" :: rest ->
      let to_repo, from_repo, kind, title, body = parse_add_flags rest in
      let t = Ticket_store.add ?db_path ~to_repo ?from_repo ~kind ~title ~body () in
      print_ticket_json t;
      0
  | "list" :: rest ->
      let to_repo, from_repo, status, fmt = parse_list_flags rest in
      let ts = Ticket_store.list ?db_path ?to_repo ?from_repo ~status () in
      (match fmt with
       | "table" -> print_string (format_list_table ts)
       | _ ->
           print_endline
             (Yojson.Safe.to_string
                (`Assoc
                   [ ("ok", `Bool true); ("tickets", `List (List.map Ticket_store.ticket_json ts)) ])));
      0
  | "read" :: rest ->
      let id, fmt = parse_read_args rest in
      let t = Ticket_store.read ?db_path id in
      (match fmt with
       | "table" -> print_string (format_read_table t)
       | _ -> print_ticket_json t);
      0
  | "claim" :: rest ->
      let id, by = parse_claim_args rest in
      let t = Ticket_store.claim ?db_path ~id ~by () in
      print_ticket_json t;
      0
  | "unclaim" :: rest ->
      let id, reason = parse_reason_args "unclaim" rest in
      let t = Ticket_store.unclaim ?db_path ~id ~reason () in
      print_ticket_json t;
      0
  | "done" :: rest ->
      let id, reason = parse_reason_args "done" rest in
      let t = Ticket_store.mark_done ?db_path ~id ~reason () in
      print_ticket_json t;
      0
  | "dismiss" :: rest ->
      let id, reason = parse_reason_args "dismiss" rest in
      let t = Ticket_store.dismiss ?db_path ~id ~reason () in
      print_ticket_json t;
      0
  | sub :: _ ->
      Db.usage
        ("unknown ticket subcommand: " ^ sub
       ^ " (expected: add, list, read, claim, unclaim, done, dismiss)")

let run ?db_path args =
  try run_inner ?db_path args
  with Db.Error (code, json) ->
    print_endline (Yojson.Safe.to_string json);
    code
