(* config — read-only machine-local bp3 config view:
   reads <git-common-dir>/bp3/config.json (optional machine settings)
   and .bp3/desks/*.json without ever writing to .git/ on read. *)
open Gitx

let config_dir () =
  match git_common_dir () with
  | None -> None
  | Some abs ->
      let canon = try Unix.realpath abs with _ -> abs in
      Some (Filename.concat canon "bp3")

let config_file dir = Filename.concat dir "config.json"

type thresholds = { setup_slow_s : int; depth_cap : int }

let default_thresholds = { setup_slow_s = 180; depth_cap = 3 }

let thresholds_json t =
  `Assoc [("setup_slow_s", `Int t.setup_slow_s); ("depth_cap", `Int t.depth_cap)]

let thresholds_of_json j =
  let scope = match Util.get_obj j "thresholds" with Some t -> t | None -> j in
  { setup_slow_s = Util.get_int scope "setup_slow_s" default_thresholds.setup_slow_s;
    depth_cap = Util.get_int scope "depth_cap" default_thresholds.depth_cap }

let load_thresholds dir =
  let path = config_file dir in
  if not (Sys.file_exists path) then default_thresholds
  else
    try thresholds_of_json (Yojson.Safe.from_string (read_file_or path ""))
    with _ -> default_thresholds

let list_desks () =
  let d = Filename.concat root ".bp3/desks" in
  if not (Sys.file_exists d) then []
  else
    try
      Sys.readdir d |> Array.to_list
      |> List.filter (fun n -> Filename.check_suffix n ".json")
      |> List.sort String.compare
      |> List.filter_map (fun n ->
          try
            let j = Yojson.Safe.from_string (read_file_or (Filename.concat d n) "") in
            match Yojson.Safe.Util.member "path" j with
            | `String p when p <> "" -> Some (json_str p)
            | _ -> None
          with _ -> None)
    with _ -> []

let view ~source =
  ignore source;
  match config_dir () with
  | None ->
      err "E_NOT_FOUND" (`Assoc [])
        "No bp3 config store: not inside a git repository." 1
  | Some dir ->
      let t = load_thresholds dir in
      `Assoc [("ok", `Bool true);
              ("config_dir", json_str dir);
              ("mode", json_str (repo_mode ()));
              ("thresholds", thresholds_json t);
              ("desks", `List (list_desks ()))]
