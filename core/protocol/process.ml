open Packet

(* Signals (including Lwt's SIGCHLD notifications) can interrupt waitpid.
   Retry the wait for this same child; never restart the external command. *)
let rec wait pid =
  try snd (Unix.waitpid [] pid)
  with Unix.Unix_error (Unix.EINTR, _, _) -> wait pid

(* Capture both streams in files: no pipe deadlock and no shell interpolation. *)
let run argv =
  if argv = [] then fail "empty command";
  let out = Filename.temp_file "bp3-out-" ".log"
  and err = Filename.temp_file "bp3-err-" ".log" in
  Fun.protect
    ~finally:(fun () ->
      Sys.remove out;
      Sys.remove err)
    (fun () ->
      let fd path = Unix.openfile path [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
      let stdout = fd out
      and stderr = fd err
      and stdin = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0 in
      let pid =
        Fun.protect
          ~finally:(fun () -> List.iter Unix.close [ stdout; stderr; stdin ])
          (fun () ->
            Unix.create_process (List.hd argv) (Array.of_list argv) stdin stdout
              stderr)
      in
      let status = wait pid in
      let output = read_file out and errors = read_file err in
      match status with
      | Unix.WEXITED 0 -> String.trim output
      (* Arguments can contain local credentials; diagnostics name the program,
         not its full invocation. Callers retain their own non-secret context. *)
      | _ -> fail (List.hd argv ^ " failed: " ^ errors ^ output))

let git repo args = run ([ "git"; "-C"; repo ] @ args)

let commit repo rev =
  git repo [ "rev-parse"; "--verify"; "--end-of-options"; rev ^ "^{commit}" ]

let repo path = Unix.realpath (git path [ "rev-parse"; "--show-toplevel" ])
