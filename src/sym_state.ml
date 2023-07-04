module Batch = Encoding.Batch

let trap msg = raise (Types.Trap msg)

let ( let* ) o f = Result.fold ~ok:f ~error:trap o

module Def_value = Value

module P = struct
  module Value = struct
    include Sym_value.S
  end

  type memory = Sym_memory.M.t

  type table = unit

  type elem = unit

  type data = unit

  type global = unit

  type vbool = Value.vbool

  type int32 = Value.int32

  type int64 = Value.int64

  type float32 = Value.float32

  type float64 = Value.float64

  type thread =
    { solver : Batch.t
    ; pc : Value.vbool list
    ; mem : memory
    }

  module Choice_once = struct
    type 'a t = thread -> 'a * thread

    let return (v : 'a) : 'a t = fun t -> (v, t)

    let bind (v : 'a t) (f : 'a -> 'b t) : 'b t =
     fun t ->
      let r, t = v t in
      (f r) t

    let select (sym_bool : vbool) : bool t =
     fun ({ solver; pc = path_condition; mem } as pc) ->
      let sym_bool = Encoding.Expression.simplify sym_bool in
      match sym_bool with
      | Val (Bool b) -> (b, pc)
      | Val (Num (I32 0l)) -> (false, pc)
      | Val (Num (I32 _)) -> (true, pc)
      | _ ->
        let value, path_condition =
          if Batch.check_sat solver (sym_bool :: path_condition) then
            (true, sym_bool :: path_condition)
          else
            let no = Value.Bool.not sym_bool in
            if Batch.check_sat solver (no :: path_condition) then
              (false, no :: path_condition)
            else assert false
        in
        Format.printf "%s@." (Encoding.Expression.to_string sym_bool);
        (value, { solver; pc = path_condition; mem })

    let select_i32 _sym_int = assert false

    let get : thread t = fun t -> (t, t)

    let trap : Interpret_functor_intf.trap -> 'a t = function
      | Out_of_bounds_table_access -> assert false
      | Out_of_bounds_memory_access -> assert false
      | Integer_overflow -> assert false
      | Integer_divide_by_zero -> assert false
      | Unreachable -> assert false

    (* raise (Types.Trap "out of bounds memory access") *)
  end

  module Choice_list = struct
    type 'a t = thread -> ('a * thread) list

    let return (v : 'a) : 'a t = fun t -> [ (v, t) ]

    let bind (v : 'a t) (f : 'a -> 'b t) : 'b t =
     fun t ->
      let lst = v t in
      List.flatten @@ List.map (fun (r, t) -> (f r) t) lst

    let select (sym_bool : vbool) : bool t =
     fun ({ solver; pc = path_condition; mem } as pc) ->
      let sym_bool = Encoding.Expression.simplify sym_bool in
      match sym_bool with
      | Val (Bool b) -> [ (b, pc) ]
      | Val (Num (I32 _)) -> assert false
      | _ ->
        let cases =
          if Batch.check_sat solver (sym_bool :: path_condition) then
            [ (true, { solver; pc = sym_bool :: path_condition; mem }) ]
          else []
        in
        let cases =
          let no = Value.Bool.not sym_bool in
          if Batch.check_sat solver (no :: path_condition) then
            (false, { solver; pc = no :: path_condition; mem }) :: cases
          else cases
        in
        (* Format.printf "%s@." (Encoding.Expression.to_string sym_bool); *)
        (* (value, (solver, path_condition)) *)
        let cases =
          match cases with
          | [] | [ _ ] -> cases
          | lst ->
            List.map
              (fun (b, r) -> (b, { r with mem = Sym_memory.M.clone r.mem }))
              lst
        in
        cases

    let select_i32 _sym_int = assert false

    let get : thread t = fun t -> [ (t, t) ]

    let trap : Interpret_functor_intf.trap -> 'a t = function
      | Out_of_bounds_table_access -> assert false
      | Out_of_bounds_memory_access -> assert false
      | Integer_overflow -> assert false
      | Integer_divide_by_zero -> assert false
      | Unreachable -> fun _ -> []

    (* raise (Types.Trap "out of bounds memory access") *)
  end

  module Choice = Choice_list
  module Extern_func = Def_value.Make_extern_func (Value)(Choice)

  type extern_func = Extern_func.extern_func

  type env = extern_func Link_env.t

  type func = Def_value.Func.t

  module Func = struct
    include Extern_func
  end

  module Global = struct
    type t = global

    let value _ = assert false

    let set_value _ = assert false

    let mut _ = assert false

    let typ _ = assert false
  end

  module Table = struct
    type t = table

    let get _ = assert false

    let set _ = assert false

    let size _ = assert false
  end

  module Memory = struct
    include Sym_memory.M
  end

  module Env = struct
    type t = env

    type t' = Env_id.t

    let get_memory _ _ = Ok Sym_memory.memory

    let get_func = Link_env.get_func

    let get_extern_func = Link_env.get_extern_func

    let get_table _ = assert false

    let get_elem _ = assert false

    let get_data _ = assert false

    let get_global _ = assert false

    let drop_elem _ = assert false

    let drop_data _ = assert false

    let pp _ _ = ()
  end

  module Module_to_run = struct
    (** runnable module *)
    type t =
      { modul : Simplified.modul
      ; env : Env.t
      ; to_run : Simplified.expr list
      }

    let env (t : t) = t.env

    let modul (t : t) = t.modul

    let to_run (t : t) = t.to_run
  end
end

module P' : Interpret_functor_intf.P = P

let convert_module_to_run (m : 'f Link.module_to_run) =
  P.Module_to_run.{ modul = m.modul; env = m.env; to_run = m.to_run }
