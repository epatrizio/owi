(** runtime table *)
type table = Value.ref_value array

type t =
  { id : int
  ; label : string option
  ; limits : Types.limits
  ; typ : Simplified.ref_type
  ; mutable data : table
  }

val get : t -> int32 -> Value.ref_value

val set : t -> int32 -> Value.ref_value -> bool

val size : t -> int32

val update : t -> table -> unit

val init : ?label:string -> Simplified.table_type -> t
