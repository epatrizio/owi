(* SPDX-License-Identifier: AGPL-3.0-or-later *)
(* Copyright © 2021 Léo Andrès *)
(* Copyright © 2021 Pierre Chambart *)

open Types
open Syntax

module Host_externref = struct
  type t = int

  let ty : t Type.Id.t = Type.Id.make ()

  let value i = Value.Externref (Some (Value.E (ty, i)))
end

let check_error ~expected ~got =
  let ok =
    got = expected
    || String.starts_with ~prefix:expected got
    || got = "constant out of range"
       && (expected = "i32 constant out of range" || expected = "i32 constant")
  in
  if not ok then begin
    Log.debug "expected: `%s`@." expected;
    Log.debug "got     : `%s`@." got;
    Error got
  end
  else Ok ()

let check_error_result expected = function
  | Ok _whatever ->
    Log.debug "expected: `%s`@." expected;
    Log.debug "got     :  Ok@.";
    error_s "expected Error (%S) but got Ok" expected
  | Error got -> check_error ~expected ~got

let load_func_from_module ls mod_id f_name =
  let* exports, env_id =
    match mod_id with
    | None -> begin
      match ls.Link.last with
      | None -> Error "unbound last module"
      | Some m -> Ok m
    end
    | Some mod_id -> (
      match Link.StringMap.find mod_id ls.Link.by_id with
      | exception Not_found -> error_s "unbound module %s" mod_id
      | exports -> Ok exports )
  in
  match Link.StringMap.find f_name exports.functions with
  | exception Not_found -> error_s "unbound name %s" f_name
  | v -> Ok (v, env_id)

let load_global_from_module ls mod_id name =
  let* exports =
    match mod_id with
    | None -> begin
      match ls.Link.last with
      | None -> Error "unbound last module"
      | Some (m, _env_id) -> Ok m
    end
    | Some mod_id -> (
      match Link.StringMap.find mod_id ls.Link.by_id with
      | exception Not_found -> error_s "unbound module %s" mod_id
      | exports, _env_id -> Ok exports )
  in
  match Link.StringMap.find name exports.globals with
  | exception Not_found -> error_s "unbound name %s" name
  | v -> Ok v

let compare_result_const result (const : Value.t) =
  match (result, const) with
  | Text.Result_const (Literal (Const_I32 n)), I32 n' -> n = n'
  | Result_const (Literal (Const_I64 n)), I64 n' -> n = n'
  | Result_const (Literal (Const_F32 n)), F32 n' -> n = n'
  | Result_const (Literal (Const_F64 n)), F64 n' -> n = n'
  | Result_const (Literal (Const_null Func_ht)), Ref (Funcref None) -> true
  | Result_const (Literal (Const_null Extern_ht)), Ref (Externref None) -> true
  | Result_const (Literal (Const_extern n)), Ref (Externref (Some ref)) -> begin
    match Value.cast_ref ref Host_externref.ty with
    | None -> false
    | Some n' -> n = n'
  end
  | Result_const (Nan_canon S32), F32 f ->
    f = Float32.pos_nan || f = Float32.neg_nan
  | Result_const (Nan_canon S64), F64 f ->
    f = Float64.pos_nan || f = Float64.neg_nan
  | Result_const (Nan_arith S32), F32 f ->
    let pos_nan = Float32.to_bits Float32.pos_nan in
    Int32.logand (Float32.to_bits f) pos_nan = pos_nan
  | Result_const (Nan_arith S64), F64 f ->
    let pos_nan = Float64.to_bits Float64.pos_nan in
    Int64.logand (Float64.to_bits f) pos_nan = pos_nan
  | Result_const (Nan_arith _), _
  | Result_const (Nan_canon _), _
  | Result_const (Literal (Const_I32 _)), _
  | Result_const (Literal (Const_I64 _)), _
  | Result_const (Literal (Const_F32 _)), _
  | Result_const (Literal (Const_F64 _)), _
  | Result_const (Literal (Const_null _)), _
  | Result_const (Literal (Const_host _)), _ ->
    false
  | _ ->
    Log.debug "TODO (Script.compare_result_const)@\n";
    false

let value_of_const : Text.const -> Concrete.V.t Result.t = function
  | Const_I32 v -> ok @@ Value.I32 v
  | Const_I64 v -> ok @@ Value.I64 v
  | Const_F32 v -> ok @@ Value.F32 v
  | Const_F64 v -> ok @@ Value.F64 v
  | Const_null rt ->
    let+ rt = Simplified_types.convert_heap_type None rt in
    Value.ref_null rt
  | Const_extern i -> ok @@ Value.Ref (Host_externref.value i)
  | i ->
    Log.debug "TODO (Script.value_of_const) %a@\n" Text.Pp.const i;
    ok @@ Value.I32 (Int32.of_int 666)

let action (link_state : Value.Func.extern_func Link.state) = function
  | Text.Invoke (mod_id, f, args) -> begin
    Log.debug "invoke %a %s %a...@\n"
      (Format.pp_print_option
         ~none:(fun ppf () -> Format.pp_print_string ppf "")
         Format.pp_print_string )
      mod_id f Text.Pp.consts args;
    let* f, env_id = load_func_from_module link_state mod_id f in
    let* stack = list_map value_of_const args in
    let stack = List.rev stack in
    Interpret.I.exec_vfunc_from_outside ~locals:stack ~env:env_id
      ~envs:link_state.envs f
  end
  | Get (mod_id, name) ->
    Log.debug "get...@\n";
    let+ global = load_global_from_module link_state mod_id name in
    [ global.value ]

let run ~with_exhaustion ~optimize script =
  let state =
    Link.extern_module Link.empty_state ~name:"spectest_extern"
      Spectest.extern_m
  in
  let script = Spectest.m :: Register ("spectest", Some "spectest") :: script in
  let debug_on = !Log.debug_on in
  let registered = ref false in
  let curr_module = ref 0 in
  list_fold_left
    (fun (link_state : Value.Func.extern_func Link.state) -> function
      | Text.Module m ->
        if !curr_module = 0 then Log.debug_on := false;
        Log.debug "*** module@\n";
        incr curr_module;
        let+ link_state =
          Compile.until_interpret link_state ~optimize ~name:None m
        in
        Log.debug_on := debug_on;
        link_state
      | Assert (Assert_trap_module (m, expected)) ->
        Log.debug "*** assert_trap@\n";
        incr curr_module;
        let* m, link_state =
          Compile.until_link link_state ~optimize ~name:None m
        in
        let+ () =
          check_error_result expected (Interpret.I.modul link_state.envs m)
        in
        link_state
      | Assert (Assert_malformed_binary _) ->
        Log.debug "*** assert_malformed_binary@\n";
        (* TODO: check this when binary format is supported *)
        Ok link_state
      | Assert (Assert_malformed_quote (m, expected)) ->
        Log.debug "*** assert_malformed_quote@\n";
        let+ () =
          match Parse.Script.from_string (String.concat "\n" m) with
          | Error got -> check_error ~expected ~got
          | Ok [ Module m ] -> (
            match Compile.until_simplify m with
            | Error got -> check_error ~expected ~got
            | Ok _m ->
              let got = "Ok" in
              check_error ~expected ~got )
          | Ok _ -> assert false
        in
        link_state
      | Assert (Assert_invalid_binary _) ->
        Log.debug "*** assert_invalid_binary@\n";
        (* TODO: check this when binary format is supported *)
        Ok link_state
      | Assert (Assert_invalid (m, expected)) ->
        Log.debug "*** assert_invalid@\n";
        let+ () =
          match Compile.until_link link_state ~optimize ~name:None m with
          | Ok _ -> check_error ~expected ~got:"Ok"
          | Error got -> check_error ~expected ~got
        in
        link_state
      | Assert (Assert_invalid_quote (m, expected)) ->
        Log.debug "*** assert_invalid_quote@\n";
        let got = Parse.Script.from_string (String.concat "\n" m) in
        let+ () = check_error_result expected got in
        link_state
      | Assert (Assert_unlinkable (m, expected)) ->
        Log.debug "*** assert_unlinkable@\n";
        let+ () =
          check_error_result expected
            (Compile.until_link link_state ~optimize ~name:None m)
        in
        link_state
      | Assert (Assert_malformed _) ->
        Log.debug "*** assert_malformed@\n";
        Log.err "TODO"
      | Assert (Assert_return (a, res)) ->
        Log.debug "*** assert_return@\n";
        let* stack = action link_state a in
        if
          List.compare_lengths res stack <> 0
          || not (List.for_all2 compare_result_const res (List.rev stack))
        then begin
          Format.eprintf "got:      %a@.expected: %a@." Stack.pp
            (List.rev stack) Text.Pp.results res;
          Error "Bad result"
        end
        else Ok link_state
      | Assert (Assert_trap (a, expected)) ->
        Log.debug "*** assert_trap@\n";
        let got = action link_state a in
        let+ () = check_error_result expected got in
        link_state
      | Assert (Assert_exhaustion (a, expected)) ->
        Log.debug "*** assert_exhaustion@\n";
        let+ () =
          if with_exhaustion then
            let got = action link_state a in
            check_error_result expected got
          else Ok ()
        in
        link_state
      | Register (name, mod_name) ->
        if !curr_module = 1 && !registered = false then Log.debug_on := false;
        Log.debug "*** register@\n";
        let+ state = Link.register_module link_state ~name ~id:mod_name in
        Log.debug_on := debug_on;
        state
      | Action a ->
        Log.debug "*** action@\n";
        let+ _stack = action link_state a in
        link_state )
    state script

let exec ?(with_exhaustion = false) ~optimize script =
  let+ _link_state = run ~with_exhaustion ~optimize script in
  ()
