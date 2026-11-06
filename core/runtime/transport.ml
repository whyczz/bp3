open Packet
open Lwt.Infix

(* One bounded JSON frame per connection. Retrying callers retain the operation
   ID; neither socket reconnection nor a transport ACK is application success. *)
let max_frame = 1024 * 1024

let socket_path board =
  (* macOS Unix socket names are short. Canonical Board identity avoids aliases. *)
  let digest = Digest.to_hex (Digest.string (Unix.realpath board)) in
  let dir =
    (* TMPDIR may be nested by Dune and exceed macOS's sockaddr_un limit.
       A private, ownership-checked directory under /tmp keeps names bounded. *)
    Filename.concat "/tmp" ("bp3-" ^ string_of_int (Unix.getuid ()))
  in
  mkdir dir;
  let stat = Unix.lstat dir in
  if
    stat.Unix.st_kind <> Unix.S_DIR
    || stat.Unix.st_uid <> Unix.getuid ()
    || stat.Unix.st_perm land 0o077 <> 0
  then fail "unsafe socket directory";
  Filename.concat dir (digest ^ ".sock")

let read_frame ic =
  let buffer = Buffer.create 1024 in
  let rec loop () =
    Lwt_io.read_char ic >>= function
    | '\n' -> Lwt.return (decode (Buffer.contents buffer))
    | c ->
        if Buffer.length buffer >= max_frame then fail "socket frame too large";
        Buffer.add_char buffer c;
        loop ()
  in
  loop ()

let write_frame oc j =
  Lwt_io.write_line oc (encode j) >>= fun () -> Lwt_io.flush oc

let call board request =
  Lwt_unix.with_timeout 30. (fun () ->
      Lwt_io.with_connection
        (Unix.ADDR_UNIX (socket_path board))
        (fun (ic, oc) ->
          write_frame oc request >>= fun () ->
          read_frame ic >|= fun response ->
          match get response "error" with
          | `Null -> get response "ok"
          | error -> fail (string error)))
