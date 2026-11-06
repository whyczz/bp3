open Packet
open Lwt.Infix

let serve ~board ~binary ~bridge =
  let board = Unix.realpath board in
  let lock =
    Unix.openfile (board ^ ".runtime.lock")
      [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_CLOEXEC ]
      0o600
  in
  (* An OS lock, not a PID file: death releases ownership even after SIGKILL. *)
  (try Unix.lockf lock Unix.F_TLOCK 0
   with Unix.Unix_error _ ->
     Unix.close lock;
     fail "runtime already owns this Board");
  let db = Store.open_db board and socket = Transport.socket_path board in
  let stop, wake = Lwt.wait () in
  let stopping _ = if Lwt.is_sleeping stop then Lwt.wakeup_later wake () in
  let term = Lwt_unix.on_signal Sys.sigterm stopping
  and interrupt = Lwt_unix.on_signal Sys.sigint stopping in
  let reconcile () =
    ignore (Board.apply db Board.Runtime (envelope "reconcile" (obj [])))
  in
  let dispatch request =
    match field request "command" with
    | "signal" -> Board.apply db Board.Bridge (get request "request")
    | "launch" ->
        Launcher.launch db ~board ~binary ~bridge (get request "payload")
    | "ping" -> obj [ ("pid", int (Unix.getpid ())); ("board", str board) ]
    | _ -> fail "unknown runtime command"
  in
  let handle _ (ic, oc) =
    Lwt.catch
      (fun () ->
        Lwt_unix.with_timeout 5. (fun () -> Transport.read_frame ic)
        >>= fun request ->
        let response =
          try obj [ ("ok", dispatch request) ] with
          | Error e -> obj [ ("error", str e) ]
          | e -> obj [ ("error", str (Printexc.to_string e)) ]
        in
        Transport.write_frame oc response)
      (fun _ -> Lwt.return_unit)
  in
  let rec watch () =
    Lwt.pick
      [
        (Lwt.protected stop >|= fun () -> false);
        (Lwt_unix.sleep 2. >|= fun () -> true);
      ]
    >>= function
    | false -> Lwt.return_unit
    | true ->
        reconcile ();
        watch ()
  in
  Fun.protect
    ~finally:(fun () ->
      Lwt_unix.disable_signal_handler term;
      Lwt_unix.disable_signal_handler interrupt;
      Store.close db;
      (* Unlink while still owning the lock: a successor must not bind its
         socket between our unlock and cleanup. *)
      if Sys.file_exists socket then Sys.remove socket;
      Unix.close lock)
    (fun () ->
      if Sys.file_exists socket then Sys.remove socket;
      reconcile ();
      Lwt_main.run
        ( Lwt_io.establish_server_with_client_address (Unix.ADDR_UNIX socket)
            handle
        >>= fun server ->
          Unix.chmod socket 0o600;
          Printf.printf "runtime ready: %s\n%!" socket;
          Lwt.finalize watch (fun () -> Lwt_io.shutdown_server server) ))
