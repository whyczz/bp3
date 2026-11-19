(* run-suites — parallel suite runner (test-pyramid tier.1).
   Reads the suite table (test/suites.tsv) and runs the selected rows
   at once. Each suite gets its own process group, an environment of
   only the allowlisted variables, its own HOME and TMPDIR, and a
   wall-clock budget: only a real overrun kills the whole group and
   fails the suite by name (budgets are hang guards, red-ink R2').
   Rows with serial=1 never overlap. The largest budgets launch first.

   Each suite runs in a new session (setsid), so it leads its own
   process group and the terminal's Ctrl-C reaches only the runner.
   Signals: the handlers for INT, TERM, HUP and QUIT only record the
   signal. The loop acts on it at its own checkpoints, and by then
   every forked suite is in the running list, so none is missed. It
   reaps every suite group, removes the temp dir, and exits 128 + the
   signal number; further signals are ignored while it reaps. SIGPIPE
   is ignored, so a closed reader ends in the same cleanup (exit 2).

   The pure parts (table, selection, order, budgets, output lines)
   live in Suites and are unit-tested; this file is the I/O. *)

let usage msg = prerr_endline ("run-suites: " ^ msg); exit 2

let help = {|run-suites — parallel suite runner (test-pyramid tier.1).
Table: one row per suite, tab-separated, '#' starts a comment,
'-' marks an empty field:
  name  tier(unit|fixture|slow)  cmd  budget_s  serial(0|1)  why  paths
A slow row must carry a why. Budgets are hand-set integers (hang
guards). A relative --table is read from the caller's directory.
Usage:
  scripts/run-suites [--tier unit,fixture,slow] [--only a,b] [--table f]
                     [--jobs n] [--list] [--report]
--list prints the selected names in table order and runs nothing.
--report adds an actual-vs-budget table after the run.
Exit 0 when every selected suite passed, 1 when any failed, 2 on a
usage or table error, 128 + N when stopped by signal N.|}

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let rec rm_rf p =
  match Unix.lstat p with
  | { Unix.st_kind = Unix.S_DIR; _ } ->
      Array.iter (fun e -> rm_rf (Filename.concat p e)) (try Sys.readdir p with _ -> [||]);
      (try Unix.rmdir p with _ -> ())
  | _ -> (try Unix.unlink p with _ -> ())
  | exception _ -> ()

let last_lines n text =
  let lines = String.split_on_char '\n' text in
  let lines = match List.rev lines with "" :: rest -> List.rev rest | _ -> lines in
  let k = List.length lines in
  List.filteri (fun i _ -> i >= k - n) lines

let now_ms () = int_of_float (Clock.now () *. 1000.)

(* The exit status as bash's `wait` reports it: 128 + N for signal N. *)
let posix_signal s =
  List.assoc_opt s [ (Sys.sighup, 1); (Sys.sigint, 2); (Sys.sigquit, 3); (Sys.sigabrt, 6);
                     (Sys.sigkill, 9); (Sys.sigsegv, 11); (Sys.sigpipe, 13); (Sys.sigterm, 15) ]
let rc_of = function
  | Unix.WEXITED n -> n
  | Unix.WSIGNALED s | Unix.WSTOPPED s -> 128 + Option.value ~default:0 (posix_signal s)

let watched = [ Sys.sigint; Sys.sigterm; Sys.sighup; Sys.sigquit ]

type running = { row : Suites.row; pid : int; start : int }

let () =
  let caller_cwd = Sys.getcwd () in
  let root = match Sys.getenv_opt "RUN_SUITES_ROOT" with Some r when r <> "" -> r | _ -> caller_cwd in
  let table = ref (Filename.concat root "test/suites.tsv") in
  let tiers = ref (String.concat "," Suites.tiers) and only = ref None and jobs = ref None in
  let list = ref false and report = ref false in
  let rec args = function
    | [] -> ()
    | "--tier" :: v :: rest -> tiers := v; args rest
    | "--only" :: v :: rest -> only := Some v; args rest
    | "--table" :: v :: rest ->
        table := (if Filename.is_relative v then Filename.concat caller_cwd v else v); args rest
    | "--jobs" :: v :: rest -> jobs := Some v; args rest
    | "--list" :: rest -> list := true; args rest
    | "--report" :: rest -> report := true; args rest
    | ("-h" | "--help") :: _ -> print_endline help; exit 0
    | [ ("--tier" | "--only" | "--table" | "--jobs") as f ] -> usage (f ^ " needs a value")
    | a :: _ -> usage ("unknown argument: " ^ a) in
  args (List.tl (Array.to_list Sys.argv));
  if !tiers = "" then usage "--tier needs a value";
  let tier_list = String.split_on_char ',' !tiers in
  List.iter (fun t -> if not (Suites.valid_tier t) then usage ("unknown tier: " ^ t ^ " (unit, fixture or slow)")) tier_list;
  if !only = Some "" then usage "--only needs a value";
  if not (Sys.file_exists !table) then usage ("no suite table: " ^ !table);
  let jobs = match !jobs with
    | None -> max 1 (Domain.recommended_domain_count ())
    | Some v -> (match int_of_string_opt v with
        | Some n when n > 0 && Suites.all_digits v -> n
        | _ -> usage "--jobs must be a positive integer") in
  let sel =
    try
      let rows = Suites.parse_table ~file:!table (read_file !table) in
      let sel = Suites.select ~tiers:tier_list ~only:(Option.map (String.split_on_char ',') !only) rows in
      if sel = [] then
        raise (Suites.Table_error (Printf.sprintf "no suite selected (tiers: %s%s)" !tiers
          (match !only with Some o -> ", only: " ^ o | None -> "")));
      sel
    with Suites.Table_error m -> usage m in
  if !list then (List.iter (fun r -> print_endline r.Suites.name) sel; exit 0);
  let order = Suites.launch_order sel in
  Sys.chdir root;
  let caller_env = Array.to_list (Unix.environment ()) in

  (* Traps first, then the temp dir: no signal can leave it behind. *)
  let caught = ref None in
  List.iter (fun s -> Sys.set_signal s (Sys.Signal_handle (fun s -> if !caught = None then caught := Some s))) watched;
  (* a closed reader (`run-suites | head`) must not kill the runner
     before it reaps: the write fails instead, and the handler at the
     end cleans up *)
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let tmp_parent = match Sys.getenv_opt "TMPDIR" with Some t when t <> "" -> t | _ -> "/tmp" in
  let tmpbase = Filename.temp_dir ~temp_dir:tmp_parent "run-suites." "" in

  let pending = ref order and running = ref [] and done_ = ref [] in
  let kill_group pid =
    (try Unix.kill (- pid) Sys.sigterm with _ -> (try Unix.kill pid Sys.sigterm with _ -> ())) in
  let kill_group_hard pid =
    (try Unix.kill (- pid) Sys.sigkill with _ -> (try Unix.kill pid Sys.sigkill with _ -> ())) in
  (* after the leader is reaped its pid may be reused: signal the group only *)
  let kill_stragglers pid = (try Unix.kill (- pid) Sys.sigkill with _ -> ()) in
  let reap_all () =
    List.iter (fun s -> Sys.set_signal s Sys.Signal_ignore) watched;
    let pids = List.map (fun r -> r.pid) !running in
    List.iter kill_group pids;
    if pids <> [] then Unix.sleepf 0.3;
    List.iter kill_group_hard pids;
    List.iter (fun p -> try ignore (Unix.waitpid [] p) with _ -> ()) pids;
    running := [] in
  let interrupt s =
    reap_all ();
    rm_rf tmpbase;
    (try prerr_endline "run-suites: interrupted" with _ -> ());   (* the terminal may be gone *)
    exit (Suites.signal_exit s) in

  let launch (r : Suites.row) =
    let dir = Filename.concat tmpbase r.name in
    let home = Filename.concat dir "home" in
    mkdir_p (Filename.concat home "t");
    let env = Array.of_list (Suites.suite_env ~caller:caller_env ~home ~name:r.name) in
    match Unix.fork () with
    | 0 ->
        (* a new session gives the suite its own process group (OCaml's
           Unix has setsid, not setpgid); suites read /dev/null and need
           no terminal *)
        (try ignore (Unix.setsid ()) with _ -> ());
        List.iter (fun s -> Sys.set_signal s Sys.Signal_default) (Sys.sigpipe :: watched);
        (try
           let devnull = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0 in
           let log = Unix.openfile (Filename.concat dir "log") [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
           Unix.dup2 devnull Unix.stdin; Unix.dup2 log Unix.stdout; Unix.dup2 log Unix.stderr;
           Unix.execvpe "bash" [| "bash"; "-c"; r.cmd |] env
         with _ -> Unix._exit 127)
    | pid ->
        (* test hook (test/run-suites.sh 2c'): a signal between the fork
           and the bookkeeping below must still reap this suite *)
        (match Sys.getenv_opt "RUN_SUITES_SIGNAL_AFTER_FORK" with
         | Some "INT" -> Unix.kill (Unix.getpid ()) Sys.sigint
         | _ -> ());
        running := { row = r; pid; start = now_ms () } :: !running in

  let finish (x : running) outcome ~now =
    let took = now - x.start in
    done_ := (x.row, took, outcome) :: !done_;
    kill_stragglers x.pid;   (* background children the suite left *)
    print_endline (Suites.result_line x.row ~took_ms:took outcome) in

  let t0 = now_ms () in
  let run () =
     Printf.printf "run-suites: %d suites, %d jobs, HOME isolated\n%!" (List.length sel) jobs;
     let continue = ref true in
     while !continue do
       (match !caught with Some s -> interrupt s | None -> ());
       let now = now_ms () in
       List.iter (fun x ->
           match Unix.waitpid [ Unix.WNOHANG ] x.pid with
           | (0, _) ->
               if Suites.over_budget ~now_ms:now ~start_ms:x.start ~budget_s:x.row.budget_s then begin
                 kill_group x.pid; Unix.sleepf 0.3; kill_group_hard x.pid;
                 (try ignore (Unix.waitpid [] x.pid) with _ -> ());
                 running := List.filter (fun y -> y.pid <> x.pid) !running;
                 finish x Suites.Budget ~now
               end
           | (_, st) ->
               running := List.filter (fun y -> y.pid <> x.pid) !running;
               let rc = rc_of st in
               finish x (if rc = 0 then Suites.Passed else Suites.Exit rc) ~now
           | exception Unix.Unix_error (Unix.EINTR, _, _) -> ())
         !running;
       flush stdout;
       let serial_busy () = List.exists (fun x -> x.row.Suites.serial) !running in
       let rec fill = function
         | [] -> []
         | r :: rest when List.length !running < jobs && (not r.Suites.serial || not (serial_busy ())) ->
             (match !caught with Some s -> interrupt s | None -> ());
             launch r; fill rest
         | r :: rest -> r :: fill rest in
       pending := fill !pending;
       if !running = [] && !pending = [] then continue := false
       else (try Unix.sleepf 0.1 with Unix.Unix_error (Unix.EINTR, _, _) -> ())
     done;
  let wall = now_ms () - t0 in
  let results = List.rev !done_ in
  let failed = List.filter (fun (_, _, o) -> o <> Suites.Passed) results in
  (* clean up before printing: passed suites go, failed ones lose their
     HOME and keep their log. A closed reader after this point ends the
     run in the handler below, which removes the whole temp dir *)
  List.iter (fun ((r : Suites.row), _, o) ->
      let dir = Filename.concat tmpbase r.name in
      if o = Suites.Passed then rm_rf dir else rm_rf (Filename.concat dir "home")) results;
  if failed = [] then (try Unix.rmdir tmpbase with _ -> ());
  if !report then List.iter print_endline (Suites.report_lines (List.map (fun (r, t, _) -> (r, t)) results));
  List.iter (fun ((r : Suites.row), _, _) ->
      let log = Filename.concat (Filename.concat tmpbase r.name) "log" in
      Printf.printf "--- %s (log: %s, last 20 lines)\n" r.name log;
      List.iter print_endline (last_lines 20 (try read_file log with _ -> ""))) failed;
  if failed = [] then begin
    let sum = List.fold_left (fun a (_, t, _) -> a + t) 0 results in
    print_endline (Suites.summary_ok ~count:(List.length sel) ~wall_ms:wall ~sum_ms:sum);
    exit 0
  end;
  print_endline (Suites.summary_fail ~failed:(List.map (fun ((r : Suites.row), _, _) -> r.name) failed)
                   ~count:(List.length sel) ~wall_ms:wall);
  exit 1 in
  (* every write, during the run or after it, can meet a closed reader *)
  try run () with
  | Sys_error m -> reap_all (); rm_rf tmpbase; (try prerr_endline ("run-suites: " ^ m) with _ -> ()); exit 2
  | e -> reap_all (); rm_rf tmpbase; raise e
