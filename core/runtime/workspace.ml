open Packet

(* Controller shells opened by bp3-zellij-init bind launches to their workspace.
   This prevents accidental cross-session routing, not malicious same-user calls. *)
let bind_session ~session payload =
  match session with
  | None -> payload
  | Some name -> (
      let name = Packet.id name in
      (match get payload "session_name" with
      | `Null -> ()
      | value ->
          if string value <> name then
            fail "session_name conflicts with BP3_SESSION");
      match payload with
      | `Assoc fields ->
          obj
            (("session_name", str name)
            :: List.remove_assoc "session_name" fields)
      | _ -> fail "launch payload must be an object")

(* Explicit layout avoids inheriting a user's multi-pane default. Keep a single
   Worker terminal plus tab/status bars, and leave the human's current tab focused. *)
let tab_layout =
  {|layout {
    pane size=1 borderless=true {
        plugin location="tab-bar"
    }
    pane
    pane size=1 borderless=true {
        plugin location="status-bar"
    }
}
|}

let tab_argv ~session ~run_id ~worktree ~launch_file =
  [
    "zellij";
    "--session";
    session;
    "action";
    "new-tab";
    "--name";
    "bp3:" ^ run_id;
    "--cwd";
    worktree;
    "--no-focus";
    "--layout-string";
    tab_layout;
    "--";
    "/bin/sh";
    launch_file;
  ]
