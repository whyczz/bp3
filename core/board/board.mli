(** The only mutation boundary used by CLI/runtime clients. Handlers commit
    state, event and idempotency receipt together; Git preflight is outside it.
*)
type caller = Controller | Worker | Bridge | Runtime

val apply : Store.t -> caller -> Packet.json -> Packet.json
(** Authenticate, replay an identical receipt, or fence and apply a new op.
    Raises [Packet.Error] on protocol refusals. No operation grants land
    authority. *)

val request_auth : Packet.json -> Packet.json
(** Extract the local run capability for runtime launch/test clients. Never
    include its result in a public context projection. *)
