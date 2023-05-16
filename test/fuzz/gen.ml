open Crowbarplus
open Owi.Types.Symbolic
open Syntax
module S = Type_stack
module B = Basic

let expr_always_available =
  (* TODO: complete this *)
  [ pair B.const_i32 (const [ S.Push (Num_type I32) ])
  ; pair B.const_i64 (const [ S.Push (Num_type I64) ])
  ; pair (const Nop) (const [ S.Nothing ])
  ]

let rec expr ~block_type ~stack =
  let _pt, rt =
    match block_type with
    | Arg.Bt_raw (_indice, (pt, rt)) -> (pt, rt)
    | _ -> assert false
  in
  Env.use_fuel ();
  if Env.has_no_fuel () then
    match (rt, stack) with
    | [], [] -> const [ Nop ]
    | rt, l ->
      (* TODO: if we have a matching prefix, keep it *)
      (* TODO: try to consume them instead of just dropping *)
      let drops = const (List.map (fun _typ -> Drop) l) in
      let adds =
        List.fold_left
          (fun (acc : instr list gen) typ ->
            list_cons (B.const_of_val_type typ) acc )
          (const []) rt
      in
      list_append drops adds
  else
    let expr_available_with_current_stack =
      (* TODO: complete this *)
      match stack with
      | Num_type I32 :: Num_type I32 :: _tl ->
        [ pair (const (I_binop (S32, Add))) (const [ S.Pop ]) ]
      | _ -> []
    in
    let expr_available =
      expr_always_available @ expr_available_with_current_stack
    in
    let* i, ops = choose expr_available in
    let stack = S.apply_stack_ops stack ops in
    let next = expr ~block_type ~stack in
    let i = const i in
    list_cons i next

let global =
  let* ((_mut, t) as typ) = B.global_type in
  let+ init = [ B.const_of_val_type t ] in
  let id = Some (Env.add_global typ) in
  let init = [ init ] in
  MGlobal { typ; init; id }

let func =
  Env.refill_fuel ();
  let locals = [] in
  let* type_f = B.block_type in
  let id = Some (Env.add_func type_f) in
  let+ body = [ expr ~block_type:type_f ~stack:[] ] in
  MFunc { type_f; locals; body; id }

let fields =
  let globals = list global in
  let start =
    let type_f = Arg.Bt_raw (None, ([], [])) in
    let id = Some "start" in
    let+ body = [ expr ~block_type:type_f ~stack:[] ] in
    MFunc { type_f; locals = []; body; id }
  in
  let funcs = list_cons start (list func) in
  list_append globals funcs

let modul =
  let start = MStart (Raw 0) in
  let id = Some "m" in
  let+ fields = [ fields ] in
  { id; fields = start :: fields }
