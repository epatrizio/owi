open Types
module S = Simplify_bis

type module_ = S.result

module StringMap = Map.Make (String)

module Memory = struct
  type mem_id = Mid of int

  type t = Memory of mem_id * string option * mem_type

  let fresh =
    let r = ref (-1) in
    fun () ->
      incr r;
      Mid !r

  let init ?label (typ : mem_type) : t = Memory (fresh (), label, typ)
end

type memory = Memory.t

module Table = struct
  type table_id = Tid of int

  type t = Table of table_id * string option * table_type

  let fresh =
    let r = ref (-1) in
    fun () ->
      incr r;
      Tid !r

  let init ?label (typ : table_type) : t = Table (fresh (), label, typ)
end

module Index = struct
  type t = S.index

  let pp fmt (I id) = Format.fprintf fmt "%i" id

  let compare = compare
end

module IMap = Map.Make (Index)

module Env = struct
  type t =
    { globals : Value.t IMap.t
    ; memories : memory IMap.t
    ; tables : Table.t IMap.t
    ; functions : Value.func IMap.t
    ; data : string IMap.t
    ; elem : Value.t list IMap.t
    }

  let pp fmt t =
    let elt fmt (id, const) =
      Format.fprintf fmt "%a -> %a" Index.pp id Value.pp const
    in
    Format.fprintf fmt "@[<hov 2>{@ %a@ }@]"
      (Format.pp_print_list
         ~pp_sep:(fun fmt () -> Format.fprintf fmt ",@ ")
         elt )
      (IMap.bindings t.globals)

  let empty =
    { globals = IMap.empty
    ; memories = IMap.empty
    ; tables = IMap.empty
    ; functions = IMap.empty
    ; data = IMap.empty
    ; elem = IMap.empty
    }

  let add_global id const env =
    { env with globals = IMap.add id const env.globals }

  let add_memory id mem env =
    { env with memories = IMap.add id mem env.memories }

  let add_table id table env =
    { env with tables = IMap.add id table env.tables }

  let add_func id func env =
    { env with functions = IMap.add id func env.functions }

  let add_data id data env =
    { env with data = IMap.add id data env.data }

  let add_elem id elem env =
    { env with elem = IMap.add id elem env.elem }

  let get_global (env : t) id : Value.t =
    match IMap.find_opt id env.globals with
    | None ->
      Debug.debugerr "%a@." pp env;
      failwith "unbound global"
    | Some v -> v

  let get_memory (env : t) id : Memory.t =
    match IMap.find_opt id env.memories with
    | None ->
      Debug.debugerr "%a@." pp env;
      failwith "unbound memory"
    | Some v -> v

  let get_table (env : t) id : Table.t =
    match IMap.find_opt id env.tables with
    | None ->
      Debug.debugerr "%a@." pp env;
      failwith "unbound table"
    | Some v -> v

  let get_func (env : t) id : Value.func =
    match IMap.find_opt id env.functions with
    | None ->
      Debug.debugerr "%a@." pp env;
      failwith (Format.asprintf "unbound function %a" Index.pp id)
    | Some v -> v

  let get_data (env : t) id : string =
    match IMap.find_opt id env.data with
    | None ->
      Debug.debugerr "%a@." pp env;
      failwith "unbound data"
    | Some v -> v

  let get_elem (env : t) id : Value.t list =
    match IMap.find_opt id env.elem with
    | None ->
      Debug.debugerr "%a@." pp env;
      failwith "unbound elem"
    | Some v -> v
end

type exports =
  { globals : Value.t StringMap.t
  ; memories : memory StringMap.t
  ; tables : Table.t StringMap.t
  ; functions : Value.func StringMap.t
  }

type module_to_run = {
  module_ : module_;
  env : Env.t;
  to_run : (S.index, func_type) expr' list;
}

type link_state =
  { modules : module_to_run list
  ; by_name : exports StringMap.t
  }

let empty_state = { modules = []; by_name = StringMap.empty }

module Const_interp = struct
  open Types

  type env = Env.t

  module Stack = Stack_bis

  let exec_ibinop stack nn (op : Const.ibinop) =
    match nn with
    | S32 ->
      let (n1, n2), stack = Stack.pop2_i32 stack in
      Stack.push_i32 stack
        (let open Int32 in
        match op with Add -> add n1 n2 | Sub -> sub n1 n2 | Mul -> mul n1 n2)
    | S64 ->
      let (n1, n2), stack = Stack.pop2_i64 stack in
      Stack.push_i64 stack
        (let open Int64 in
        match op with Add -> add n1 n2 | Sub -> sub n1 n2 | Mul -> mul n1 n2)

  let exec_instr (env : env) (stack : Stack_bis.t) (instr : Const.instr) =
    match instr with
    | I32_const n -> Stack.push_i32 stack n
    | I64_const n -> Stack.push_i64 stack n
    | F32_const f -> Stack.push_f32 stack f
    | F64_const f -> Stack.push_f64 stack f
    | I_binop (nn, op) -> exec_ibinop stack nn op
    | Ref_null t -> Stack.push stack (Value.ref_null t)
    | Ref_func f ->
      let value = Value.Ref (Funcref (Some (Env.get_func env f))) in
      Stack.push stack value
    | Global_get id -> Stack.push stack (Env.get_global env id)

  let exec_expr env (e : Const.expr) : Value.t =
    let stack = List.fold_left (exec_instr env) Stack.empty e in
    match stack with
    | [] -> failwith "const expr returning zero values"
    | _ :: _ :: _ -> failwith "const expr returning more than one value"
    | [ result ] -> result
end

let load_from_module ls f (import : _ S.imp) =
  match StringMap.find import.module_ ls.by_name with
  | exception Not_found -> failwith ("unbound module " ^ import.module_)
  | exports -> (
    match StringMap.find import.name (f exports) with
    | exception Not_found -> failwith ("unbound name " ^ import.name)
    | v -> v )

let load_global (ls : link_state) (import : S.global_import S.imp) : Value.t =
  match import.desc with
  | Var, _ -> failwith "non constant global"
  | Const, _ -> load_from_module ls (fun (e : exports) -> e.globals) import

let eval_global ls env
    (global : ((S.index, Const.expr) global', S.global_import) S.runtime) :
    Value.t =
  match global with
  | S.Local global -> Const_interp.exec_expr env global.init
  | S.Imported import -> load_global ls import

let eval_globals ls globals : Env.t =
  S.Fields.fold
    (fun id global env ->
      let const = eval_global ls env global in
      let env = Env.add_global id const env in
      env )
    globals Env.empty

let eval_in_data (env : Env.t) (data : _ data') : (S.index, Value.t) data' =
  let mode =
    match data.mode with
    | Data_passive -> Data_passive
    | Data_active (id, expr) ->
      let const = Const_interp.exec_expr env expr in
      Data_active (id, const)
  in
  { data with mode }

let limit_is_included l ~into =
  into.min <= l.min
  &&
  match into.max with
  | None -> true
  | Some into_max -> (
    match l.max with None -> false | Some l_max -> into_max >= l_max )

let load_memory (ls : link_state) (import : S.mem_import S.imp) : memory =
  let limits : mem_type = import.desc in
  let (Memory (_, _, limits') as mem) =
    load_from_module ls (fun (e : exports) -> e.memories) import
  in
  if limit_is_included limits' ~into:limits then mem
  else failwith "incompatible memory limits"

let eval_memory ls (memory : (mem, S.mem_import) S.runtime) : Memory.t =
  match memory with
  | Local (label, mem_type) -> Memory.init ?label mem_type
  | Imported import -> load_memory ls import

let eval_memories ls env memories =
  S.Fields.fold
    (fun id mem env ->
      let memory = eval_memory ls mem in
      let env = Env.add_memory id memory env in
      env )
    memories env

let table_types_are_compatible (l1, (t1 : ref_type)) (l2, t2) =
  limit_is_included l2 ~into:l1 && t1 = t2

let load_table (ls : link_state) (import : S.table_import S.imp) : Table.t =
  let type_ : table_type = import.desc in
  let (Table (_, _, type') as table) =
    load_from_module ls (fun (e : exports) -> e.tables) import
  in
  if table_types_are_compatible type_ type' then table
  else failwith "incompatible table import"

let eval_table ls (table : (table, S.table_import) S.runtime) : Table.t =
  match table with
  | Local (label, table_type) -> Table.init ?label table_type
  | Imported import -> load_table ls import

let eval_tables ls env tables =
  S.Fields.fold
    (fun id table env ->
      let table = eval_table ls table in
      let env = Env.add_table id table env in
      env )
    tables env

let func_types_are_compatible _t1 _t2 =
  (* TODO *)
  true

let load_func (ls : link_state) (import : func_type S.imp) : Value.func =
  let type_ : func_type = import.desc in
  let func =
    load_from_module ls (fun (e : exports) -> e.functions) import
  in
  let type' = Value.Func.type_ func in
  if func_types_are_compatible type_ type' then func
  else failwith "incompatible function import "

let eval_func ls (func : (S.func, func_type) S.runtime) : Value.func =
  match func with
  | Local func -> Value.Func.wasm func
  | Imported import -> load_func ls import

let eval_functions ls env functions =
  S.Fields.fold
    (fun id func env ->
      let func = eval_func ls func in
      let env = Env.add_func id func env in
      env )
    functions env

let active_elem_expr length ~table ~elem =
  [ I32_const 0l;
    I32_const length;
    Table_init (table, elem);
    Elem_drop elem ]

let active_data_expr length ~mem ~data =
  assert(mem = I 0);
  [ I32_const 0l;
    I32_const length;
    Memory_init data;
    Data_drop data ]

let get_i32 = function
  | Value.I32 i -> i
  | _ -> failwith "Not an i32 const"

let define_data env data =
  S.Fields.fold
    (fun id data (env, init) ->
       let env = Env.add_data id data.init env in
       let init =
         match data.mode with
         | Data_active (mem, offset) ->
           let offset = Const_interp.exec_expr env offset in
           active_data_expr (get_i32 offset) ~mem ~data:id :: init
         | Data_passive -> init
       in
       env, init )
    data (env, [])

let define_elem env elem =
  S.Fields.fold
    (fun id (elem : _ elem') (env, inits) ->
      let init = List.map (Const_interp.exec_expr env) elem.init in
      let env = Env.add_elem id init env in
      let inits =
        match elem.mode with
        | Elem_active (table, offset) ->
          let offset = Const_interp.exec_expr env offset in
          active_elem_expr (get_i32 offset) ~table ~elem:id :: inits
        | Elem_passive | Elem_declarative -> inits
      in
      env, inits )
    elem (env, [])

let populate_exports env (exports : S.index S.exports) : exports =
  let fill_exports get_env exports =
    List.fold_left
      (fun acc (export : _ S.export) ->
        let value = get_env env export.id in
        StringMap.add export.name value acc )
      StringMap.empty exports
  in
  let globals = fill_exports Env.get_global exports.global in
  let memories = fill_exports Env.get_memory exports.mem in
  let tables = fill_exports Env.get_table exports.table in
  let functions = fill_exports Env.get_func exports.func in
  { globals; memories; tables; functions }

let link_module (module_ : module_) (ls : link_state) : link_state =
  Debug.debug Format.err_formatter "LINK %a@\n" Pp.pp_id module_.id;
  let env = eval_globals ls module_.global in
  let env = eval_memories ls env module_.mem in
  let env = eval_tables ls env module_.table in
  let env = eval_functions ls env module_.func in
  let env, init_active_data = define_data env module_.data in
  let env, init_active_elem = define_elem env module_.elem in
  Debug.debug Format.err_formatter "EVAL %a@\n" Env.pp env;
  let by_name_exports = populate_exports env module_.exports in
  let by_name =
    (* TODO: this is not the actual module name *)
    match module_.id with
    | None -> ls.by_name
    | Some name -> StringMap.add name by_name_exports ls.by_name
  in
  let start =
    List.map (fun start_id -> Call start_id) module_.start
  in
  let to_run =
    init_active_data @
    init_active_elem @
    [ start ]
  in
  { modules = { module_; env; to_run } :: ls.modules; by_name }
