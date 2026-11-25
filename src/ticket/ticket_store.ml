(* ticket_store — cross-repo ticket queue in bp3.sqlite (sqlite-control-plane ticket.1).
   Bottom-layer library: strict --to validation against repos, atomic BEGIN IMMEDIATE
   claiming/unclaiming/resolving, and a pure status/verb judge. *)

type ticket = {
  id : int;
  from_repo : string;
  to_repo : string;
  kind : string;
  title : string;
  body : string;
  status : string;
  claimed_by : string option;
  claimed_at : string option;
  resolved_at : string option;
  resolution_reason : string option;
  created_at : string;
}

let valid_kind = function
  | "bug" | "feature" | "note" -> true
  | _ -> false

let valid_status = function
  | "open" | "claimed" | "done" | "dismissed" -> true
  | _ -> false

let valid_list_status = function
  | "open" | "claimed" | "done" | "dismissed" | "all" -> true
  | _ -> false

let legal_verbs_of_status = function
  | "open" -> [ "claim"; "done"; "dismiss" ]
  | "claimed" -> [ "unclaim"; "done"; "dismiss" ]
  | "done" | "dismissed" -> []
  | _ -> []

let opt_json = function
  | Some s -> `String s
  | None -> `Null

let ticket_json (t : ticket) =
  `Assoc
    [
      ("id", `Int t.id);
      ("from_repo", Db.json_str t.from_repo);
      ("to_repo", Db.json_str t.to_repo);
      ("kind", Db.json_str t.kind);
      ("title", Db.json_str t.title);
      ("body", Db.json_str t.body);
      ("status", Db.json_str t.status);
      ("claimed_by", opt_json t.claimed_by);
      ("claimed_at", opt_json t.claimed_at);
      ("resolved_at", opt_json t.resolved_at);
      ("resolution_reason", opt_json t.resolution_reason);
      ("created_at", Db.json_str t.created_at);
    ]

let ticket_not_found id =
  Db.verdict_err "E_NOT_FOUND"
    (`Assoc [ ("ticket", `Int id) ])
    (Printf.sprintf "ticket not found: %d" id)
    2

let illegal_edge ~id ~status ~verb =
  let legal = legal_verbs_of_status status in
  Db.verdict_err "E_ILLEGAL_EDGE"
    (`Assoc
       [
         ("id", `Int id);
         ("status", Db.json_str status);
         ("verb", Db.json_str verb);
         ("legal_verbs", `List (List.map Db.json_str legal));
       ])
    (Printf.sprintf "Cannot %s ticket %d in status %S." verb id status)
    1

let select_cols =
  "id, from_repo, to_repo, kind, title, body, status, claimed_by, claimed_at, resolved_at, resolution_reason, created_at"

let row_to_ticket row =
  {
    id = Db.data_to_int row.(0);
    from_repo = Db.data_to_str row.(1);
    to_repo = Db.data_to_str row.(2);
    kind = Db.data_to_str row.(3);
    title = Db.data_to_str row.(4);
    body = Db.data_to_str row.(5);
    status = Db.data_to_str row.(6);
    claimed_by = Db.data_to_str_opt row.(7);
    claimed_at = Db.data_to_str_opt row.(8);
    resolved_at = Db.data_to_str_opt row.(9);
    resolution_reason = Db.data_to_str_opt row.(10);
    created_at = Db.data_to_str row.(11);
  }

let get_in db id =
  match
    Db.query_rows db
      ("SELECT " ^ select_cols ^ " FROM tickets WHERE id = ?;")
      [ Sqlite3.Data.INT (Int64.of_int id) ]
  with
  | row :: _ -> Some (row_to_ticket row)
  | [] -> None

let get_exn_in db id =
  match get_in db id with
  | Some t -> t
  | None -> ticket_not_found id

let add ?db_path ~to_repo ?from_repo ?(kind = "note") ~title ?(body = "") () =
  if String.trim to_repo = "" then Db.usage "--to is required and cannot be empty";
  if not (valid_kind kind) then
    Db.usage ("--kind must be bug, feature, or note: " ^ kind);
  if String.trim title = "" then Db.usage "--title is required and cannot be empty";
  (match from_repo with
   | Some s when String.trim s = "" -> Db.usage "--from cannot be empty"
   | _ -> ());
  (* Resolve caller git root before acquiring SQLite write lock so concurrent
     writers never block on a git subprocess. *)
  let caller_root =
    match from_repo with
    | Some _ -> None
    | None -> (
        try Some (Repo_store.resolve_main_root (Repo_store.default_caller_path ()))
        with Db.Error _ -> None)
  in
  let ts = Db.now_ts () in
  Db.with_db ?path:db_path (fun db ->
      Db.with_tx_immediate db (fun db ->
          let registered = Repo_store.list_names_in db in
          if not (List.mem to_repo registered) then
            Db.not_found
              ~extra:[ ("registered", `List (List.map Db.json_str registered)) ]
              "repo" to_repo;
          let from_val =
            match from_repo with
            | Some s -> s
            | None -> (
                match caller_root with
                | None -> "unknown"
                | Some root_path -> (
                    match Repo_store.find_by_path_in db root_path with
                    | Some r -> r.Repo_store.name
                    | None -> (
                        match Db.slugify (Filename.basename root_path) with
                        | Ok s -> s
                        | Error _ -> "unknown")))
          in
          Db.exec_params db
            "INSERT INTO tickets (from_repo, to_repo, kind, title, body, status, created_at) \
             VALUES (?, ?, ?, ?, ?, 'open', ?);"
            [
              Sqlite3.Data.TEXT from_val;
              Sqlite3.Data.TEXT to_repo;
              Sqlite3.Data.TEXT kind;
              Sqlite3.Data.TEXT title;
              Sqlite3.Data.TEXT body;
              Sqlite3.Data.TEXT ts;
            ];
          let tid = Int64.to_int (Sqlite3.last_insert_rowid db) in
          get_exn_in db tid))

let list ?db_path ?to_repo ?from_repo ?(status = "open") () =
  if not (valid_list_status status) then
    Db.usage ("--status must be open, claimed, done, dismissed, or all: " ^ status);
  let clauses = ref [] in
  let params = ref [] in
  let add_eq col v =
    clauses := (col ^ " = ?") :: !clauses;
    params := Sqlite3.Data.TEXT v :: !params
  in
  (match to_repo with Some r -> add_eq "to_repo" r | None -> ());
  (match from_repo with Some r -> add_eq "from_repo" r | None -> ());
  if status <> "all" then add_eq "status" status;
  let where =
    match List.rev !clauses with
    | [] -> ""
    | cs -> " WHERE " ^ String.concat " AND " cs
  in
  let sql = "SELECT " ^ select_cols ^ " FROM tickets" ^ where ^ " ORDER BY id ASC;" in
  Db.with_db ?path:db_path (fun db ->
      Db.query_rows db sql (List.rev !params) |> List.map row_to_ticket)

let read ?db_path id =
  if id < 1 then Db.usage ("ticket id must be a positive integer: " ^ string_of_int id);
  Db.with_db ?path:db_path (fun db -> get_exn_in db id)

let claim ?db_path ~id ~by () =
  if id < 1 then Db.usage ("ticket id must be a positive integer: " ^ string_of_int id);
  if String.trim by = "" then Db.usage "--by cannot be empty";
  let ts = Db.now_ts () in
  Db.with_db ?path:db_path (fun db ->
      Db.with_tx_immediate db (fun db ->
          let t = get_exn_in db id in
          match t.status with
          | "open" ->
              Db.exec_params db
                "UPDATE tickets SET status = 'claimed', claimed_by = ?, claimed_at = ? \
                 WHERE id = ? AND status = 'open';"
                [
                  Sqlite3.Data.TEXT by;
                  Sqlite3.Data.TEXT ts;
                  Sqlite3.Data.INT (Int64.of_int id);
                ];
              if Sqlite3.changes db <> 1 then
                Db.db_error (Printf.sprintf "atomic claim did not update ticket %d" id);
              get_exn_in db id
          | "claimed" ->
              Db.verdict_err "E_ALREADY_CLAIMED"
                (`Assoc
                   [
                     ("id", `Int id);
                     ("status", Db.json_str "claimed");
                     ("claimed_by", opt_json t.claimed_by);
                   ])
                (Printf.sprintf "Ticket %d is already claimed by %s." id
                   (Option.value ~default:"unknown" t.claimed_by))
                1
          | s -> illegal_edge ~id ~status:s ~verb:"claim"))

let unclaim ?db_path ~id ~reason () =
  if id < 1 then Db.usage ("ticket id must be a positive integer: " ^ string_of_int id);
  if String.trim reason = "" then Db.usage "--reason is required and cannot be empty";
  Db.with_db ?path:db_path (fun db ->
      Db.with_tx_immediate db (fun db ->
          let t = get_exn_in db id in
          if t.status <> "claimed" then
            illegal_edge ~id ~status:t.status ~verb:"unclaim";
          Db.exec_params db
            "UPDATE tickets SET status = 'open', claimed_by = NULL, claimed_at = NULL \
             WHERE id = ? AND status = 'claimed';"
            [ Sqlite3.Data.INT (Int64.of_int id) ];
          if Sqlite3.changes db <> 1 then
            Db.db_error (Printf.sprintf "unclaim did not update ticket %d" id);
          get_exn_in db id))

let resolve ~new_status ~verb ?db_path ~id ~reason () =
  if id < 1 then Db.usage ("ticket id must be a positive integer: " ^ string_of_int id);
  if String.trim reason = "" then Db.usage "--reason is required and cannot be empty";
  let ts = Db.now_ts () in
  Db.with_db ?path:db_path (fun db ->
      Db.with_tx_immediate db (fun db ->
          let t = get_exn_in db id in
          if t.status = "done" || t.status = "dismissed" then
            illegal_edge ~id ~status:t.status ~verb;
          Db.exec_params db
            "UPDATE tickets SET status = ?, resolved_at = ?, resolution_reason = ? \
             WHERE id = ?;"
            [
              Sqlite3.Data.TEXT new_status;
              Sqlite3.Data.TEXT ts;
              Sqlite3.Data.TEXT reason;
              Sqlite3.Data.INT (Int64.of_int id);
            ];
          if Sqlite3.changes db <> 1 then
            Db.db_error (Printf.sprintf "%s did not update ticket %d" verb id);
          get_exn_in db id))

let mark_done ?db_path ~id ~reason () =
  resolve ~new_status:"done" ~verb:"done" ?db_path ~id ~reason ()

let dismiss ?db_path ~id ~reason () =
  resolve ~new_status:"dismissed" ~verb:"dismiss" ?db_path ~id ~reason ()
