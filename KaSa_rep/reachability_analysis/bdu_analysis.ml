(**
  * bdu_analysi.ml
  * openkappa
  * Jérôme Feret, projet Abstraction, INRIA Paris-Rocquencourt
  * 
  * Creation: 2015, the 26th of June
  * Last modification: 
  * 
  * Compute the relations between sites in the BDU data structures
  * 
  * Copyright 2010,2011,2012,2013,2014 Institut National de Recherche en Informatique et   
  * en Automatique.  All rights reserved.  This file is distributed     
  * under the terms of the GNU Library General Public License *)

open Printf
open Cckappa_sig
open Int_storage
open Mvbdu_sig
open Bdu_analysis_type
open Print_bdu_analysis

let warn parameters mh message exn default =
  Exception.warn parameters mh (Some "BDU analysis") message exn (fun () -> default)  

let trace = false

(*---------------------------------------------------------------------------------*)
(*common function for building bdu from a list of pair (site, state)*)

let f parameter error a' x y =
  match x y with
    | error, (handler, Some a) -> error, handler, a
    | error, (handler, None) ->
      let error, a =
        Exception.warn parameter error (Some "") (Some "") Exit (fun _ -> a')
      in error, handler, a
  
let build_bdu parameter error pair_list =
  (*build bdu for this list*)
  let remanent_bdu = Sanity_test.remanent parameter in
  let error        = remanent_bdu.Sanity_test_sig.error in
  let allocate     = remanent_bdu.Sanity_test_sig.allocate_mvbdu in
  (*'b: memo_tables; 'a: mvbdu_dic; 'c: list_dic*)
  let (handler: ('b, 'a, 'c, bool, int) Memo_sig.handler) =
    remanent_bdu.Sanity_test_sig.mvbdu_handler
  in
  let a_val = Mvbdu_sig.Leaf true in
  let b_val = Mvbdu_sig.Leaf false in
  (*build bdu from a_val: 
    a',a'_id: output of build_already_compressed_cell;
    a'', a''_id: output of compress_node
  *)
  let error, handler, a', a'_id, a'', a''_id =
    Mvbdu_test.build_without_and_with_compressing
      allocate
      error
      handler
      a_val
      a_val
  in
  (*build bdu_b from b_val*)
  let error, handler, b', b'_id, b'', b''_id =
    Mvbdu_test.build_without_and_with_compressing
      allocate
      error
      handler
      b_val
      b_val
  in
  (*---------------------------------------------------------------------------*)    
  (*build bdu_list from a list of pair [site, state] computed above in cv*)
  let error, (handler, list_a) =
    List_algebra.build_list
      (Boolean_mvbdu.list_allocate parameter)
      error
      parameter
      handler
      pair_list
  in
  (*compute redefine in a list_a, a': mvbdu_input*)
  let error, handler, mvbdu =
    f parameter error a' 
      (Boolean_mvbdu.redefine parameter error parameter handler a') list_a
  in
  (*---------------------------------------------------------------------------*)
  (*return redefine*)
  error, (handler, mvbdu)

(************************************************************************************)    
(*build initial bdu: false branch*)

let bdu_init parameter =
  let remanent_bdu = Sanity_test.remanent parameter in
  let error        = remanent_bdu.Sanity_test_sig.error in
  let allocate     = remanent_bdu.Sanity_test_sig.allocate_mvbdu in
  let (handler: ('b, 'a, 'c, bool, int) Memo_sig.handler) =
    remanent_bdu.Sanity_test_sig.mvbdu_handler
  in
  let a_val = Mvbdu_sig.Leaf false in
  let error, handler, a', a'_id, a'', a''_id =
    Mvbdu_test.build_without_and_with_compressing
      allocate
      error
      handler
      a_val
      a_val
  in
  error, (handler, a')

(************************************************************************************)    
(*compute bdu for initial state or creation actions*)

let int_of_port port = port.site_state.min

let collect_pair_creation parameter error viewsrhs creation store_creation =
  let error, (handler, bdu_init) = bdu_init parameter in
  List.fold_left (fun (error, store_creation) (agent_id, agent_type) ->
    let error, agent = AgentMap.get parameter error agent_id viewsrhs in
    match agent with
      | None -> warn parameter error (Some "line 143") Exit store_creation
      | Some Ghost -> error, store_creation
      | Some Agent agent ->
        (*get the site and state on the rhs*)
        let (pair_list, (handler, bdu)) =
          Site_map_and_set.fold_map
            (fun site port (current_list, _)  ->
              let state = int_of_port port in
              let l = (site, state) :: current_list in
	      let error, (handler, bdu) =
		build_bdu parameter error l
	      in
	      l, (handler, bdu)
            ) agent.agent_interface ([], (handler, bdu_init))
        in
	(*---------------------------------------------------------------------------*)
        (*get old*)
        let error, (old_list, (handler, old_bdu)) =
          match AgentMap.unsafe_get parameter error agent_type store_creation with
            | error, None -> error, ([], (handler, bdu_init))
            | error, Some (l, (handler, b)) -> error, (l, (handler, b))
        in
	let new_list = List.concat [pair_list; old_list] in
	let error, handler, new_bdu =
	  f parameter error old_bdu (Boolean_mvbdu.boolean_mvbdu_or
	       parameter handler error parameter old_bdu) bdu
	in
	(*--------------------------------------------------------------------------*)
        (*store*)
        let error, store_creation =
          AgentMap.set
            parameter
            error
            agent_type
            (List.rev new_list, (handler, new_bdu))
            store_creation
        in
        error, store_creation
  ) (error, store_creation) creation

(************************************************************************************)
(*side effects: unknow binding - know binding - deletion*)

(*unknow binding*)

let collect_half_break_bdu parameter error kappa_handler store_half_break half_break =
  let error, (handler, bdu_init) = bdu_init parameter in
  List.fold_left (fun (error, store_half_break) (site_add, state) ->
    let site = site_add.site in
    let agent_type = site_add.agent_type in
    (*---------------------------------------------------------------------------------*)
    (*get state*)
    let error, (min, max) =
      match state with
	| None ->
	  begin
	    let error, value_state =
	      Misc_sa.unsome
		(Nearly_Inf_Int_Int_storage_Imperatif_Imperatif.get
		   parameter
		   error
		   (agent_type, site)
		   kappa_handler.states_dic)
		(fun error -> warn parameter error (Some "line 296")
		  Exit (Dictionary_of_States.init ()))
	    in
	    let error, last_entry =
	      Dictionary_of_States.last_entry parameter error value_state
	    in
	    error, (1, last_entry)
	  end
	| Some interval -> error, (interval.min, interval.max)
    in
    let pair_list = [site, min] in
    (*---------------------------------------------------------------------------------*)
    (*build bdu for half_break*)
    let error, (handler, bdu_half_break) = build_bdu parameter error pair_list in
    (*---------------------------------------------------------------------------------*)
    (*get old*)
    let error, (old_list, (handler, old_bdu)) =
      match AgentMap.unsafe_get parameter error agent_type store_half_break with
	| error, None -> error, ([], (handler, bdu_init))
	| error, Some (l, (handler, bdu)) -> error, (l, (handler, bdu))
    in
    let new_list = List.concat [pair_list; old_list] in
    let error, handler, new_bdu =
      f parameter error old_bdu
        (Boolean_mvbdu.boolean_mvbdu_or
	   parameter handler error parameter old_bdu) bdu_half_break
    in
    (*---------------------------------------------------------------------------------*)
    (*store*)
    AgentMap.set
      parameter
      error
      agent_type
      (List.rev new_list, (handler, new_bdu))
      store_half_break
  ) (error, store_half_break) half_break

(*remove actions (deletion)*)
    
(************************************************************************************)
(*Covering class*)

let collect_test_modif parameter error viewslhs diff_reverse store_result =
  let error, (handler, bdu_init) = bdu_init parameter in
  AgentMap.fold2_common parameter error
    (fun parameter error agent_id agent site_modif store_result ->
    (*If there is no modified site then return the enabled rules*)
      if Site_map_and_set.is_empty_map site_modif.agent_interface
      then error, store_result
      else
        match agent with
          | Ghost -> error, store_result
          | Agent agent ->
            let agent_type = agent.agent_name in
            (*------------------------------------------------------------------------*)
	    let (pair_list, (handler, bdu)) =
	      Site_map_and_set.fold_map
		(fun site port (current_list, _) ->
		  let state = int_of_port port in
		  let l = (site, state) :: current_list in
		  (*build bdu*)
		  let error, (handler, bdu) = build_bdu parameter error l in
		  l, (handler, bdu)
		) agent.agent_interface ([], (handler, bdu_init))
	    in
            (*------------------------------------------------------------------------*)
	    (*get old*)
	    let error, (old_list, (handler, old_bdu)) =
	      match AgentMap.unsafe_get parameter error agent_type store_result with
		| error, None -> error, ([], (handler, bdu_init))
		| error, Some (l, (handler, bdu)) -> error, (l, (handler, bdu))
	    in
	    (*new*)
	    let new_list = List.concat [pair_list; old_list] in
	    let error, handler, new_bdu =
	      f parameter error old_bdu (Boolean_mvbdu.boolean_mvbdu_or
		   parameter handler error parameter old_bdu) bdu
	    in
            (*------------------------------------------------------------------------*)
	    AgentMap.set
	      parameter
	      error
	      agent_type
	      (List.rev new_list, (handler, new_bdu))
	      store_result
    ) viewslhs diff_reverse store_result

(************************************************************************************)
(*iteration function of bdu creation union with bdu of test and
  modification (covering class)*)

let iteration_creation_cv parameter error store_creation store_cv store_result =
  let error, (handler, bdu_init) = bdu_init parameter in
  AgentMap.fold2_common parameter error
    (fun parameter error agent_type
      (_, (handler, bdu_created))
      (_, (handler, bdu_cv)) store_result ->
	let error, handler, bdu_iterate =
	  f parameter error bdu_created
            (Boolean_mvbdu.boolean_mvbdu_or
	       parameter handler error parameter bdu_created) bdu_cv
	in
	(*store*)
	AgentMap.set
	  parameter
	  error
	  agent_type
	  (handler, bdu_iterate)
	  store_result
    ) store_creation store_cv store_result

(************************************************************************************)
(*iteration function of side effect (half_break), creation and covering class*)
    
let iterate_half_break_created_cv parameter error store_iterate_created_cv store_half_break
    store_result =
  let error, (handler, bdu_init) = bdu_init parameter in
  AgentMap.fold2_common parameter error
    (fun parameter error agent_type
      (handler, bdu_iterate)
      (_, (handler, bdu_half_break)) store_result ->
	let error, handler, bdu_iterate =
	  f parameter error bdu_iterate
            (Boolean_mvbdu.boolean_mvbdu_or
	       parameter handler error parameter bdu_iterate) bdu_half_break
	in
	(*store*)
	AgentMap.set
	  parameter
	  error
	  agent_type
	  (handler, bdu_iterate)
	  store_result
    ) store_iterate_created_cv store_half_break store_result

(************************************************************************************)
(*iteration function of side effect (half_break) and covering class*)

let iterate_half_break_cv parameter error store_cv store_half_break store_result =
  let error, (handler, bdu_init) = bdu_init parameter in
  AgentMap.fold2_common parameter error
    (fun parameter error agent_type
      (_, (handler, bdu_cv))
      (_, (handler, bdu_hf)) store_result ->
      let error, handler, bdu_iterate =
	f parameter error bdu_cv 
          (Boolean_mvbdu.boolean_mvbdu_or
	     parameter handler error parameter bdu_cv) bdu_hf
      in
      AgentMap.set
	parameter
	error
	agent_type
	(handler, bdu_iterate)
	store_result
    ) store_cv store_half_break store_result

(************************************************************************************)
(*iteration function of side effect half_break and creation*)

let iterate_half_break_created parameter error store_created store_half_break store_result =
  let error, (handler, bdu_init) = bdu_init parameter in
  AgentMap.fold2_common parameter error
    (fun parameter error agent_type
      (_, (handler, bdu_created))
      (_, (handler, bdu_half_break)) store_result ->
      let error, handler, bdu_iterate =
	f parameter error bdu_created
          (Boolean_mvbdu.boolean_mvbdu_or
	     parameter handler error parameter bdu_created) bdu_half_break
      in
      AgentMap.set
	parameter
	error
	agent_type
	(handler, bdu_iterate)
	store_result
    ) store_created store_half_break store_result
    
(************************************************************************************)
(*RULE*)

let scan_rule parameter error handler rule rules store_result =
  (*------------------------------------------------------------------------------*)
  (*creation rules*)
  let error, store_creation =
    collect_pair_creation
      parameter
      error
      rule.rule_rhs.views
      rule.actions.creation
      store_result.store_creation
  in
  (*------------------------------------------------------------------------------*)
  (*side effect - half_break*)
  let error, store_half_break =
    collect_half_break_bdu
      parameter
      error
      handler
      store_result.store_half_break
      rule.actions.half_break
  in
  (*------------------------------------------------------------------------------*)
  (*side effect - deletion*)
  (*let error, store_remove_bdu =
    collect_remove_bdu
      parameter
      error
      store_result.store_remove_bdu
      rule.actions.remove
  in*)
  (*------------------------------------------------------------------------------*)
  (*test and modification: covering class*)
  let error, store_test_modif =
    collect_test_modif
      parameter
      error
      rule.rule_lhs.views
      rule.diff_reverse
      store_result.store_test_modif
  in
  (*------------------------------------------------------------------------------*)
  (*iteration: creation and covering class*)
  let error, store_iterate_created_cv =
    iteration_creation_cv
      parameter
      error
      store_creation
      store_test_modif
      store_result.store_iterate_created_cv
  in
  (*------------------------------------------------------------------------------*)
  (*iteration: half_break and covering class*)
  let error, store_iterate_half_cv =
    iterate_half_break_cv
      parameter
      error
      store_test_modif
      store_half_break
      store_result.store_iterate_half_cv
  in
  (*------------------------------------------------------------------------------*)
  (*iteration: half_break and creation*)
  let error, store_iterate_half_created =
    iterate_half_break_created
      parameter
      error
      store_creation
      store_half_break
      store_result.store_iterate_half_created
  in
  (*------------------------------------------------------------------------------*)
  (*iteration: half_break, creation and cv*)
  let error, store_iterate_half_created_cv =
    iterate_half_break_created_cv
      parameter
      error
      store_iterate_created_cv
      store_half_break
      store_result.store_iterate_half_created_cv
  in
  (*------------------------------------------------------------------------------*)
  (*store*)
  error,
  {
    store_creation   = store_creation;
    store_half_break = store_half_break;
    store_test_modif = store_test_modif;
    store_iterate_created_cv      = store_iterate_created_cv;
    store_iterate_half_cv         = store_iterate_half_cv;
    store_iterate_half_created    = store_iterate_half_created;
    store_iterate_half_created_cv = store_iterate_half_created_cv;
  }   
  
(************************************************************************************)
(*RULES*)

let scan_rule_set parameter error handler rules =
  let error, init_creation   = AgentMap.create parameter error 0 in
  let error, init_half_break = AgentMap.create parameter error 0 in
  let error, init_test_modif = AgentMap.create parameter error 0 in
  let error, init_iterate_created_cv      = AgentMap.create parameter error 0 in
  let error, init_iterate_half_cv         = AgentMap.create parameter error 0 in
  let error, init_iterate_half_created    = AgentMap.create parameter error 0 in
  let error, init_iterate_half_created_cv = AgentMap.create parameter error 0 in
  let init_bdu =
    {
      store_creation   = init_creation;
      store_half_break = init_half_break;
      store_test_modif = init_test_modif;
      store_iterate_created_cv      = init_iterate_created_cv;
      store_iterate_half_cv         = init_iterate_half_cv;
      store_iterate_half_created    = init_iterate_half_created;
      store_iterate_half_created_cv = init_iterate_half_created_cv;
    }
  in
  (*------------------------------------------------------------------------------*)
  (*map each agent to a covering classes*)
  let error, store_results =
    Nearly_inf_Imperatif.fold
      parameter error
      (fun parameter error rule_id rule store_result ->
        (*let _ = Printf.fprintf stdout "rule_id:%i:\n" rule_id in*)
        let error, result =
          scan_rule
            parameter
            error
            handler
            rule.e_rule_c_rule
            rules
            store_result
        in
        error, result
      ) rules init_bdu
  in
  error, store_results

(************************************************************************************)
(*MAIN*)

let bdu_main parameter error handler cc_compil =
  let parameter = Remanent_parameters.update_prefix parameter "agent_type:" in
  let error, result = scan_rule_set parameter error handler cc_compil.rules in
  let _ = print_result parameter error result in
  error, result
