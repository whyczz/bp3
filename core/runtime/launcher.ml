open Packet

(* The reservation is the retry boundary. After it exists, a launch retry only
   returns its stage: it must not guess whether Zellij already spawned a pane. *)
let launch db ~board ~binary ~bridge p =
  let run_id = Packet.id (field p "run_id") in
  let exp_id = Packet.id (field p "exp_id") in
  let session_name = Packet.id (field p "session_name") in
  let root = Unix.realpath (field p "root") in
  let worktree = Filename.concat root run_id in
  let branch = "bp3/" ^ run_id in
  match Store.query db "SELECT * FROM runs WHERE id=?" [ str run_id ] with
  | [ r ] ->
      if
        field r "exp_id" <> exp_id
        || field r "worktree" <> worktree
        || field r "session_name" <> session_name
      then fail "launch identity reused with different inputs";
      obj
        [
          ("run_id", str run_id);
          ("stage", get r "launch_stage");
          ("replayed", `Bool true);
        ]
  | _ :: _ -> assert false
  | [] ->
      (* Validate cheap environmental facts before claiming ownership. *)
      if not (Sys.file_exists binary && Sys.file_exists bridge) then
        fail "runtime binary/bridge absent";
      let sessions =
        Process.run [ "zellij"; "list-sessions"; "--short"; "--no-formatting" ]
        |> String.split_on_char '\n'
      in
      if not (List.mem session_name sessions) then
        fail "Zellij session absent; create/attach it first";
      let exp = Store.one db "SELECT * FROM exps WHERE id=?" [ str exp_id ] in
      let quest =
        Store.one db "SELECT * FROM quests WHERE id=?" [ get exp "quest_id" ]
      in
      let repo = field quest "repo" in
      if Process.commit repo (field quest "target") <> field quest "base" then
        fail "unreconciled Quest target movement";
      if Sys.file_exists worktree then fail "worktree path already exists";
      ignore
        (Board.apply db Board.Runtime
           (envelope "reserve"
              (obj
                 [
                   ("id", str run_id);
                   ("exp_id", str exp_id);
                   ("worktree", str worktree);
                   ("branch", str branch);
                   ("session_name", str session_name);
                 ])));
      let r = Store.run db run_id in
      let stage value =
        ignore
          (Board.apply db Board.Runtime
             (envelope "launch-stage"
                (obj [ ("run_id", str run_id); ("stage", str value) ])))
      in
      ignore
        (Process.git repo
           [ "worktree"; "add"; "-b"; branch; worktree; field r "base" ]);
      stage "worktree";
      (* Commit spawn intent BEFORE touching the external process. A crash after
      this point leaves an inspectable ambiguity, never a second Worker. *)
      stage "spawning";
      let environment =
        [
          "BP3_BOARD=" ^ board;
          "BP3_BIN=" ^ binary;
          "BP3_SOCKET=" ^ Transport.socket_path board;
          "BP3_RUN=" ^ run_id;
          "BP3_GENERATION=" ^ string_of_int (number (get r "generation"));
          "BP3_TOKEN=" ^ field r "token";
        ]
      in
      let model_args =
        match get p "model" with
        | `Null -> []
        | model -> [ "--model"; string model ]
      in
      let command =
        [
          "pi";
          "--no-extensions";
          "--no-skills";
          "--no-prompt-templates";
          "--no-mcp";
          "--no-context-files";
          "--no-approve";
          "--offline";
          "--extension";
          bridge;
          "--session-dir";
          Filename.concat root (run_id ^ "-sessions");
        ]
        @ model_args
      in
      (* Zellij exposes argv in pane metadata. Keep local capabilities in a
         private file, never in the new-tab command or diagnostic response.
         Shell quoting is mechanical; no brief/model content becomes shell code. *)
      let launch_file = Filename.concat root (run_id ^ ".launch") in
      let fd =
        Unix.openfile launch_file
          [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL ]
          0o600
      in
      let channel = Unix.out_channel_of_descr fd in
      Fun.protect
        ~finally:(fun () -> close_out channel)
        (fun () ->
          output_string channel "#!/bin/sh\n";
          List.iter
            (fun binding ->
              output_string channel ("export " ^ Filename.quote binding ^ "\n"))
            environment;
          output_string channel
            ("exec "
            ^ String.concat " " (List.map Filename.quote command)
            ^ "\n"));
      let tab =
        Process.run
          (Workspace.tab_argv ~session:session_name ~run_id ~worktree
             ~launch_file)
      in
      (* The tab returned here is diagnostic only. The bridge's actual endpoint
      still supplies authoritative pane/session identity in the ready signal. *)
      obj
        [ ("run_id", str run_id); ("stage", str "spawning"); ("tab", str tab) ]
