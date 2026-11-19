(* The one wall-clock reader (test-pyramid unit.2). Time decisions
   are pure predicates taking ~now, so unit tests pass literal times;
   effectful code reads the swappable source through [time] or [now],
   and tests pin it with [with_fixed]. The binary honors no time env
   var: nothing outside a test can move the clock. *)

let source : (unit -> float) ref = ref Unix.gettimeofday

(* Sub-second wall clock. *)
let now () = !source ()

(* Whole seconds, exactly what Unix.time returned: every pre-seam
   call site reads this, so the seam changes no behavior. *)
let time () = Float.of_int (truncate (now ()))

(* Pin the clock at [t] for [f]; restores the previous source even
   when [f] raises. *)
let with_fixed t f =
  let old = !source in
  source := (fun () -> t);
  Fun.protect ~finally:(fun () -> source := old) f

(* A binding untouched for more than [stale_after_s] is stale. *)
let stale ~now ~last_seen ~stale_after_s = now -. last_seen > stale_after_s

(* Silence: nothing new for more than [silence_s]; within it is fresh. *)
let silent ~now ~last ~silence_s = now -. last > silence_s

(* A deadline is reached at the deadline itself. *)
let past_deadline ~now ~deadline = now >= deadline
