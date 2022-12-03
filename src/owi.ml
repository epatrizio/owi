let error msg =
  Format.eprintf "error: %s@." msg;
  exit 1

let extern_module : Owi.Link.extern_module =
  let open Owi in
  let module M = struct
    let rint : int32 ref Value.Extern_ref.ty = Value.Extern_ref.fresh "int ref"

    let fresh i = ref i

    let set r (i : int32) = r := i

    let get r : int32 = !r
  end in
  let print_i32 (i : Int32.t) = Printf.printf "%li\n%!" i in
  let functions =
    [ ( "print_i32"
      , Value.Func.Extern_func (Func (Arg (I32, Res), R0), print_i32) )
    ; ( "fresh"
      , Value.Func.Extern_func
          (Func (Arg (I32, Res), R1 (Externref M.rint)), M.fresh) )
    ; ( "set_i32r"
      , Value.Func.Extern_func
          (Func (Arg (Externref M.rint, Arg (I32, Res)), R0), M.set) )
    ; ( "get_i32r"
      , Value.Func.Extern_func
          (Func (Arg (Externref M.rint, Res), R1 I32), M.get) )
    ]
  in
  { functions }

let simplify_then_link_then_run file =
  let cmds =
    List.filter_map
      (function
        | Owi.Types.Module m -> Some (`Module (Owi.Simplify.simplify m))
        | Owi.Types.Register (name, id) -> Some (`Register (name, id))
        | _ -> None )
      file
  in
  let () = Owi.Log.debug "* Simplified %i modules@." (List.length cmds) in
  let link_state = Owi.Link.empty_state in
  let link_state =
    Owi.Link.link_extern_module "stuff" extern_module link_state
  in
  let to_run, _link_state =
    List.fold_left
      (fun (to_run, state) cmd ->
        match cmd with
        | `Module module_ ->
          let module_to_run, state = Owi.Link.link_module module_ state in
          (module_to_run :: to_run, state)
        | `Register (name, id) ->
          (to_run, Owi.Link.register_module state ~name ~id) )
      ([], link_state) cmds
  in
  let () = Owi.Log.debug "* Linked@." in
  List.iter Owi.Interpret.exec_module (List.rev to_run);
  let () = Owi.Log.debug "* Done@." in
  ()

let run_as_script, debug, files =
  let run_as_script = ref false in
  let debug = ref false in
  let files = ref [] in
  let spec =
    Arg.
      [ ("--script", Set run_as_script, "run as a reference test suite script")
      ; ("-s", Set run_as_script, "short for --script")
      ; ("--debug", Set debug, "debug mode")
      ; ("-d", Set debug, "short for --debug")
      ]
  in
  Arg.parse spec (fun s -> files := s :: !files) "wast interpreter %s <file>";
  (!run_as_script, !debug, !files)

let () =
  Owi.Log.debug_on := debug;

  List.iter
    (fun file ->
      if not @@ Sys.file_exists file then
        error (Format.sprintf "file `%s` doesn't exist" file);

      match Owi.Parse.from_file ~filename:file with
      | Ok script -> begin
        Format.printf "%a@." Owi.Pp.Input.file script;
        if run_as_script then Owi.Script.exec script
        else simplify_then_link_then_run script
      end
      | Error e -> error e )
    files
