open Packet

(* The reservation is the retry boundary. After it exists, a launch retry only
   returns its stage: it must not guess whether Zellij already spawned a pane. *)
let launch db ~board ~binary ~bridge p =
  let execution_id = Packet.id (field p "execution_id") in
  let exp_id = Packet.id (field p "exp_id") in
  let session_name = Packet.id (field p "session_name") in
  let root = Unix.realpath (field p "root") in
  let worktree = Filename.concat root execution_id in
  let branch = "bp3/" ^ execution_id in
  match
    Store.query db "SELECT * FROM executions WHERE id=?" [ str execution_id ]
  with
  | [ e ] ->
      if
        field e "exp_id" <> exp_id
        || field e "worktree" <> worktree
        || field e "session_name" <> session_name
      then fail "launch identity reused with different inputs";
      obj
        [
          ("execution_id", str execution_id);
          ("stage", get e "launch_stage");
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
                   ("id", str execution_id);
                   ("exp_id", str exp_id);
                   ("worktree", str worktree);
                   ("branch", str branch);
                   ("session_name", str session_name);
                 ])));
      let e = Store.execution db execution_id in
      let stage value =
        ignore
          (Board.apply db Board.Runtime
             (envelope "launch-stage"
                (obj
                   [ ("execution_id", str execution_id); ("stage", str value) ])))
      in
      ignore
        (Process.git repo
           [ "worktree"; "add"; "-b"; branch; worktree; field e "base" ]);
      stage "worktree";
      (* Commit spawn intent BEFORE touching the external process. A crash after
      this point leaves an inspectable ambiguity, never a second Worker. *)
      stage "spawning";
      let environment =
        [
          "BP3_BOARD=" ^ board;
          "BP3_BIN=" ^ binary;
          "BP3_SOCKET=" ^ Transport.socket_path board;
          "BP3_EXECUTION=" ^ execution_id;
          "BP3_GENERATION=" ^ string_of_int (number (get e "generation"));
          "BP3_TOKEN=" ^ field e "token";
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
          Filename.concat root (execution_id ^ "-sessions");
        ]
        @ model_args
      in
      (* Zellij exposes argv in pane metadata. Keep local capabilities in a
         private file, never in the new-pane command or diagnostic response.
         Shell quoting is mechanical; no brief/model content becomes shell code. *)
      let launch_file = Filename.concat root (execution_id ^ ".launch") in
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
      let pane =
        Process.run
          [
            "zellij";
            "--session";
            session_name;
            "action";
            "new-pane";
            "--name";
            "bp3:" ^ execution_id;
            "--cwd";
            worktree;
            "--";
            "/bin/sh";
            launch_file;
          ]
      in
      (* The pane returned here is diagnostic only. The bridge's actual endpoint
      supplies authoritative pane/session identity in the ready signal. *)
      obj
        [
          ("execution_id", str execution_id);
          ("stage", str "spawning");
          ("pane", str pane);
        ]
