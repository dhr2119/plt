open Llvm
open Ast
open Sast
module L = Llvm
module A = Ast
module S = Sast

module StringMap = Map.Make(String)

let translate(globals, functions) =
  let context = L.global_context() in
  let the_module = L.create_module context "CMAT"

  and i32_t   = L.i32_type context
  and i1_t    = L.i1_type context
  and i8_t    = L.i8_type context
  and void_t  = L.void_type context in

  let ltype_of_typ = function
      A.Int  -> i32_t
    | A.Bool -> i1_t
    | A.Void -> void_t in

  let ltype_of_datatype = function
    A.Datatype(p) -> ltype_of_typ p in

  let global_vars =
    let global_var m (t,n) =
      let init = L.const_int (ltype_of_datatype t) 0
      in StringMap.add n (L.define_global n init the_module) m in
    List.fold_left global_var StringMap.empty globals in

  let printf_t =
    L.var_arg_function_type i32_t [| L.pointer_type i8_t |] in
  let printf_func =
    L.declare_function "printf" printf_t the_module in

  let function_decls =
    let function_decl m fdecl =
      let name = fdecl.S.sfname
      and formal_types = Array.of_list
        (List.map (function A.Formal(t,s) -> ltype_of_datatype t) fdecl.S.sformals)
      in let ftype =
        L.function_type (ltype_of_datatype fdecl.S.sreturn_type) formal_types in
        StringMap.add name (L.define_function name ftype the_module, fdecl) m in
        List.fold_left function_decl StringMap.empty functions in

  let build_function_body fdecl =

    let (the_function, _) =
      StringMap.find fdecl.S.sfname function_decls in

    let builder = (* Create an instruction builder *)
      L.builder_at_end context (L.entry_block the_function) in

  let local_vars =
    let add_formal m (t, n) p = L.set_value_name n p;
      let local = L.build_alloca (ltype_of_datatype t) n builder in
      ignore (L.build_store p local builder);
      StringMap.add n local m in

    let add_local m (t, n) =
      let local_var = L.build_alloca (ltype_of_datatype t) n builder
      in StringMap.add n local_var m in

    let formals = List.fold_left2 add_formal StringMap.empty
      (List.map (function A.Formal(t,n) -> (t,n)) fdecl.S.sformals) (Array.to_list (L.params the_function)) in
    List.fold_left add_local formals (List.map (function A.Local(t,n) -> (t,n)) fdecl.S.slocals) in

    let lookup n = try StringMap.find n local_vars
                   with Not_found -> StringMap.find n global_vars
    in
    let rec expr builder = function
        S.SBool_lit b    -> L.const_int i1_t (if b then 1 else 0)
      | S.SString_lit s  -> L.build_global_stringptr s "tmp" builder
      | S.SNoexpr        -> L.const_int i32_t 0
      | S.SId (s, d)     -> L.build_load (lookup s) s builder
      | S.SAssign (s, e, d) -> let e' = expr builder e in
              ignore (L.build_store e' (lookup s) builder); e'
      | S.SBinop (e1, op, e2, d) ->
          let e1' = expr builder e1
          and e2' = expr builder e2 in
          (match op with
          	A.Add     -> L.build_add
          | A.Sub	  -> L.build_sub
      	  | A.Mult	  -> L.build_mul
      	  | A.Div	  -> L.build_sdiv
      	  | A.And	  -> L.build_and
      	  | A.Or	  -> L.build_or
      	  | A.Equal	  -> L.build_icmp L.Icmp.Eq
      	  | A.Neq	  -> L.build_icmp L.Icmp.Ne
      	  | A.Less	  -> L.build_icmp L.Icmp.Slt
      	  | A.Leq	  -> L.build_icmp L.Icmp.Sle
      	  | A.Greater -> L.build_icmp L.Icmp.Sgt
      	  | A.Geq	  -> L.build_icmp L.Icmp.Sge
      	  ) e1' e2' "tmp" builder
      | S.SUnop(op, e, d)   ->
          let e' = expr builder e in (match op with
            A.Neg   -> L.build_neg
          | A.Not   -> L.build_not) e' "tmp" builder;
      | S.SCall ("print_line", [e], d) ->
          L.build_call printf_func
            [| (expr builder e) |]
            "printf" builder
      | S.SCall (f, act, d) ->
          let (fdef, fdecl) = StringMap.find f function_decls in
          let actuals = List.rev (List.map (expr builder) (List.rev act)) in
          let result = (match fdecl.S.sreturn_type with A.Datatype(A.Void) -> ""
                                                       | _ -> f ^ "_result") in
          L.build_call fdef (Array.of_list actuals) result builder in

    let add_terminal builder f =
      match L.block_terminator (L.insertion_block builder) with
        Some _ -> ()
      | None -> ignore (f builder) in
    let rec stmt builder = function
        S.SBlock sl -> List.fold_left stmt builder sl
      | S.SExpr (e, d) -> ignore (expr builder e); builder
      | S.SReturn (e, d) -> ignore (match fdecl.S.sreturn_type with
          A.Datatype(A.Void) -> L.build_ret_void builder
        | _ -> L.build_ret (expr builder e) builder); builder
      | S.SIf (predicate, then_stmt, else_stmt) ->
      	 let bool_val = expr builder predicate in
      	 let merge_bb = L.append_block context
      	 				  "merge" the_function in
      	 let then_bb = L.append_block context
      	 				  "then" the_function in
      	 add_terminal
      	  (stmt (L.builder_at_end context then_bb)
      			then_stmt)
      	  (L.build_br merge_bb);
      	 let else_bb = L.append_block context
      	  					"else" the_function in
      	 add_terminal
      	  (stmt (L.builder_at_end context else_bb)
      			 else_stmt)
      	  (L.build_br merge_bb);

      	 ignore (L.build_cond_br bool_val
      	 			 then_bb else_bb builder);
      	 L.builder_at_end context merge_bb
      | S.SWhile (predicate, body) ->
      	 let pred_bb = L.append_block context
      	 				"while" the_function in
      	 ignore (L.build_br pred_bb builder);
      	 let body_bb = L.append_block context
      	 				"while_body" the_function in
      	 add_terminal (stmt (L.builder_at_end
      	 						context body_bb)
      						body)
      	 	(L.build_br pred_bb);
      	 let pred_builder =
      	 	L.builder_at_end context pred_bb in
      	 let bool_val =
      	 		expr pred_builder predicate in
      	 let merge_bb = L.append_block context
      	 				"merge" the_function in
      	 ignore (L.build_cond_br bool_val
      	 		body_bb merge_bb pred_builder);
      	 L.builder_at_end context merge_bb
      (*Need For statements *)
  	in

    (* Build the code for each statement in the function *)
    let builder = stmt builder (S.SBlock fdecl.S.sbody) in

    (* Add a return if the last block falls off the end *)
    add_terminal builder (match fdecl.S.sreturn_type with
        A.Datatype(A.Void) -> L.build_ret_void
        | t -> L.build_ret (L.const_int (ltype_of_datatype t) 0))
    in
    List.iter build_function_body functions;
    the_module
