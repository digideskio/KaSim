(** Network/ODE generation
  * Creation: 15/07/2016
  * Last modification: Time-stamp: <Jul 29 2016>
*)



module Make(I:Ode_interface.Interface) =
struct

  let alg_of_int i =
    Location.dummy_annot (Ast.CONST (Nbr.I i))
  let alg_of_float f =
    Location.dummy_annot (Ast.CONST (Nbr.F f))
  module SpeciesSetMap =
    SetMap.Make
      (struct
        type t = I.chemical_species
        let compare = compare
        let print = I.print_chemical_species
      end)
  module SpeciesSet = SpeciesSetMap.Set
  module SpeciesMap = SpeciesSetMap.Map


  module Store =
    SetMap.Make
      (struct
        type t =
          I.rule_id * I.direction * I.connected_component_id
        let compare = compare
        let print a (r,dir,cc) =
          let () =
            Format.fprintf a
              "Component_wise:(%s,%a,%a)"
              (match dir with I.Direct -> "->" | I.Reverse -> "<-")
              I.print_rule_id r I.print_connected_component_id cc  in
          let () = I.print_rule_id a r in
          let () = I.print_connected_component_id a cc in
          ()
      end)

  module StoreMap = Store.Map

  type id = int
  type ode_var_id = id
  type intro_coef_id = id
  type var_id = id
  type obs_id = id
  type rule_id = id
  let fst_id = 1
  let next_id id = id + 1

  type ode_var = Nembed of I.canonic_species | Token of string | Dummy
  type lhs_decl = Init_decl | Var_decl of string | Init_value of ode_var


  module VarSetMap =
    SetMap.Make
      (struct
        type t = ode_var
        let compare = compare
        let print log x =
          match x with
          | Nembed x -> I.print_canonic_species log x
          | Token x -> Format.fprintf log "%s" x
          | Dummy -> ()
      end)
  module VarSet = VarSetMap.Set
  module VarMap = VarSetMap.Map

  type decl =
    | Var of (var_id * string Location.annot option * (ode_var_id, string) Ast.ast_alg_expr Location.annot)
    | Init_expr of var_id * string Location.annot option  * (ode_var_id, string) Ast.ast_alg_expr Location.annot * ode_var_id list
    | Dummy_decl

  let var_id_of_decl decl =
    match decl with
    | Var (a,_,_) -> a
    | Init_expr (a,_,_,_) -> a
    | Dummy_decl -> fst_id

  type enriched_rule =
    {
      rule_id: rule_id ;
      rule: I.rule ;
      mode: I.rule_mode ;
      lhs: I.pattern ;
      lhs_cc:
        (I.connected_component_id * I.connected_component) list ;
      divide_rate_by: int
    }

  let var_of_rule rule =
    match rule.mode with
    | I.Direct, I.Usual -> Ode_loggers.Rate rule.rule_id
    | I.Direct, I.Unary -> Ode_loggers.Rateun rule.rule_id
    | I.Reverse, I.Usual -> Ode_loggers.Rated rule.rule_id
    | I.Reverse, I.Unary -> Ode_loggers.Rateund rule.rule_id

  type network =
    {
      rules : enriched_rule list ;
      ode_variables : VarSet.t ;
      reactions: (id list * id list * ((I.pattern,string) Ast.ast_alg_expr Location.annot * id Location.annot) list * enriched_rule) list ;

      ode_vars_tab: ode_var Mods.DynArray.t ;
      id_of_ode_var: ode_var_id VarMap.t ;
      fresh_ode_var_id: ode_var_id ;

      species_tab: I.chemical_species Mods.DynArray.t ;

      varmap: var_id Mods.StringMap.t ;
      tokenmap: ode_var_id Mods.StringMap.t ;

      fresh_var_id: var_id ;
      var_declaration: decl list ;

      n_rules: int ;

      obs: (obs_id * (ode_var_id,string) Ast.ast_alg_expr Location.annot) list ;
      n_obs: int ;

    }


  let get_fresh_var_id network = network.fresh_var_id
  let get_last_var_id network = network.fresh_var_id-1
  let inc_fresh_var_id network =
    {network with fresh_var_id = next_id network.fresh_var_id}
  let get_fresh_ode_var_id network = network.fresh_ode_var_id
  let get_last_ode_var_id network = network.fresh_ode_var_id-1
  let inc_fresh_ode_var_id network =
    {network with fresh_ode_var_id = next_id network.fresh_ode_var_id}
  let get_fresh_obs_id network = network.n_obs
  let last_fresh_obs_id network = network.n_obs-1
  let inc_fresh_obs_id network =
    {network with n_obs = next_id network.n_obs}


  let fold_left_swap f a b =
    List.fold_left
      (fun a b -> f b a)
      b a

  let get_compil = I.get_compil
  let init () =
    {
      rules = [] ;
      reactions = [] ;
      ode_variables = VarSet.empty ;
      ode_vars_tab = Mods.DynArray.create 0 Dummy ;
      id_of_ode_var = VarMap.empty ;
      species_tab = Mods.DynArray.create 0 I.dummy_chemical_species ;
      fresh_ode_var_id = fst_id ;
      fresh_var_id = fst_id ;
      varmap = Mods.StringMap.empty ;
      tokenmap = Mods.StringMap.empty ;
      var_declaration = [];
      n_rules = 0 ;
      obs = [] ;
      n_obs = 1 ;
    }

  let is_known_variable variable network =
    VarSet.mem variable network.ode_variables

  let add_new_var var network =
    let () =
      Mods.DynArray.set
        network.ode_vars_tab
        (get_fresh_ode_var_id network)
        var
    in
    let network =
      { network
        with
          ode_variables = VarSet.add var network.ode_variables ;
          id_of_ode_var = VarMap.add var network.fresh_ode_var_id network.id_of_ode_var ;
      }
    in
    inc_fresh_ode_var_id network,
    get_fresh_ode_var_id network

  let add_new_canonic_species canonic species network =
    let () =
      Mods.DynArray.set
        network.species_tab
        (get_fresh_ode_var_id network)
        species
    in
    add_new_var (Nembed canonic) network

  let add_new_token token network =
    let network, id = add_new_var (Token token) network in
    {network with tokenmap = Mods.StringMap.add token id network.tokenmap},
    id

  let enrich_rule rule mode id =
    let lhs = I.lhs rule mode in
    let lhs_cc = I.connected_components_of_patterns lhs in
    {
      rule_id = id ;
      rule = rule ;
      mode = mode ;
      lhs = lhs ;
      lhs_cc = lhs_cc ;
      divide_rate_by =
        if I.do_we_divide_rates_by_n_auto_in_lhs
        then I.nbr_automorphisms_in_pattern lhs
        else 1
    }

  let add_embedding key embed store =
    let old_list =
      StoreMap.find_default [] key store
    in
    StoreMap.add key (embed::old_list) store

  let add_embedding_list key lembed store =
    let old_list =
      StoreMap.find_default [] key store
    in
    let new_list =
      fold_left_swap (fun a b -> a::b)
        lembed
        old_list
    in
    StoreMap.add key new_list store

  let translate_canonic_species canonic species remanent =
    let id_opt =
      VarMap.find_option
        (Nembed canonic)
        (snd remanent).id_of_ode_var in
    match
      id_opt
    with
    | None ->
      let to_be_visited, network = remanent in
      let network, id = add_new_canonic_species canonic species network
      in
      (species::to_be_visited,network), id
    | Some i -> remanent,i

  let translate_species species remanent =
    translate_canonic_species
      (I.canonic_form species) species remanent

  let translate_token token remanent =
    let id_opt =
      VarMap.find_option
        (Token token) (snd remanent).id_of_ode_var
    in
    match id_opt with
    | None ->
      let to_be_visited, network = remanent in
      let network, id = add_new_token token network in
      (to_be_visited, network), id
    | Some i -> remanent, i

  (*  let petrify_canonic_species = translate_canonic_species*)
  let petrify_species species =
    translate_canonic_species (I.canonic_form species) species
  let petrify_species_list l remanent =
    fold_left_swap
      (fun species (remanent,l) ->
         let remanent, i =
           petrify_species species remanent
         in
         remanent,(i::l))
      l
      (remanent,[])

  let petrify_mixture mixture =
    petrify_species_list (I.connected_components_of_mixture mixture)

  let add_to_prefix_list connected_component key prefix_list store acc =
    let list_embeddings =
      StoreMap.find_default [] key store
    in
    List.fold_left
      (fun new_list prefix ->
         List.fold_left
           (fun new_list (embedding,chemical_species) ->
              ((connected_component,embedding,chemical_species)::prefix)::new_list)
           new_list
           list_embeddings
      )
      acc prefix_list

  let add_reaction enriched_rule mode embedding_forest mixture remanent =
    let rule = enriched_rule.rule in
    let remanent, reactants = petrify_mixture mixture remanent in
    let products = I.apply rule mode embedding_forest mixture in
    let tokens = I.token_vector rule mode in
    let remanent, products = petrify_mixture products remanent in
    let remanent, tokens =
      List.fold_left
        (fun (remanent, tokens) (a,(b,c)) ->
           let remanent, id = translate_token b remanent in
           remanent,(a,(id,c))::tokens)
        (remanent,[])
        tokens
    in
    let to_be_visited, network = remanent in
    let network =
      {
        network
        with reactions = (List.rev reactants, List.rev products, List.rev tokens, enriched_rule)::network.reactions
      }
    in
    to_be_visited, network

  let initial_network initial_states =
    List.fold_left
      (fun remanent species -> fst (translate_species species remanent))
      ([], init ())
      initial_states

  let compute_reactions rules initial_states =
    (* Let us annotate the rules with cc decomposition *)
    let n_rules = List.length rules in
    let _,rules =
      List.fold_left
        (fun (id,list) rule ->
           let modes = I.valid_modes rule in
           next_id id,
           List.fold_left
             (fun list mode ->
                (enrich_rule rule mode id)::list)
             list modes)
        (fst_id,[]) rules
    in
    let to_be_visited, network = initial_network initial_states in
    let network =
      {network
       with n_rules = pred n_rules;
            rules = rules }
    in
    let store = StoreMap.empty in
    (* store maps each cc in the lhs of a rule to the list of embedding between this cc and a pattern in set\to_be_visited *)
    let rec aux to_be_visited network store =
      match
        to_be_visited
      with
      | []   -> network

      | new_species::to_be_visited ->
        (* add in store the embeddings from cc of lhs to new_species,
           for unary application of binary rule, the dictionary of species is updated, and the reaction entered directly *)
        let store, to_be_visited, network  =
          List.fold_left
            (fun
              (store_old_embeddings, to_be_visited, network)  enriched_rule ->
              (*  (rule_id,rule,mode,lhs,lhs_cc)*)
              (* regular application of tules, we store the embeddings*)
              let direction,arity = enriched_rule.mode in
              match arity with
              | I.Usual ->
                begin
                  let store_new_embeddings =
                    List.fold_left
                      (fun store (cc_id, cc) ->
                         let lembed = I.find_embeddings cc new_species in
                         add_embedding_list
                           (enriched_rule.rule_id,direction,
                            cc_id)
                           (List.rev_map (fun a -> a,new_species) (List.rev lembed))
                           store
                      )
                      StoreMap.empty
                      enriched_rule.lhs_cc
                  in
                  let (),store_all_embeddings =
                    StoreMap.map2_with_logs
                      (fun _ a _ _ _ -> a)
                      ()
                      ()
                      (fun _ _ b -> (),b)
                      (fun _ _ b -> (),b)
                      (fun _ _ b c ->
                         (),List.fold_left
                           (fun list elt -> elt::list)
                           b c)
                      store_old_embeddings
                      store_new_embeddings
                  in
                  (* compute the embedding betwen lhs and tuple of species that contain at least one occurence of new_species *)
                  let _,new_embedding_list =
                    List.fold_left
                      (fun (partial_emb_list,partial_emb_list_with_new_species) (cc_id,cc) ->
                         (* First case, we complete with an embedding towards the new_species *)
                         let partial_emb_list =
                           add_to_prefix_list cc (enriched_rule.rule_id,direction,cc_id) partial_emb_list store_old_embeddings []
                         in
                         let partial_emb_list_with_new_species =
                           add_to_prefix_list cc (enriched_rule.rule_id,direction,cc_id)
                             partial_emb_list
                             store_new_embeddings
                             (add_to_prefix_list cc (enriched_rule.rule_id,direction,cc_id) partial_emb_list_with_new_species
                                store_all_embeddings [])
                         in
                         partial_emb_list, partial_emb_list_with_new_species
                      )
                      ([[]],[[]])
                      enriched_rule.lhs_cc
                  in
                  (* compute the corresponding rhs, and put the new species in the working list, and store the corrsponding reactions *)
                  let to_be_visited, network =
                    List.fold_left
                      (fun remanent list ->
                         let _,embed,mixture = I.disjoint_union list in
                         add_reaction enriched_rule (I.Direct,I.Usual) embed mixture remanent)
                      (to_be_visited,network)
                      new_embedding_list
                  in
                  store_all_embeddings,to_be_visited,network
                end

              | I.Unary ->
                begin
                  (* unary application of binary rules *)
                  let to_be_visited, network =
                    let lembed = I.find_embeddings_unary_binary enriched_rule.lhs new_species in
                    fold_left_swap
                      (fun embed ->
                         add_reaction enriched_rule enriched_rule.mode embed
                           (I.lift_species new_species))
                      lembed
                      (to_be_visited, network)
                  in
                  store_old_embeddings, to_be_visited, network
                end
            )
            (store, to_be_visited, network)
            rules
        in
        aux to_be_visited network store
    in
    aux to_be_visited network store

  let convert_tokens compil network =
    let tokens = I.get_tokens compil in
    List.fold_left
      (fun network (a,_) ->
         snd (fst (translate_token a ([],network))))
      network
      tokens

  let translate_species species network =
    snd (translate_species species ([],network))

  let translate_token token network =
    snd (translate_token token ([],network))

  let convert_cc connected_component network =
    VarMap.fold
      (fun vars id alg ->
         match vars with
         | Nembed _ ->
           begin
             let species = Mods.DynArray.get network.species_tab id in
             let n_embs =
               List.length
                 (I.find_embeddings connected_component species)
             in
             if n_embs = 0
             then
               alg
             else
               let species = Ast.KAPPA_INSTANCE id in
               let term =
                 if n_embs = 1
                 then
                   species
                 else
                   Ast.BIN_ALG_OP
                     (
                       Operator.MULT,
                       alg_of_int n_embs,
                       Location.dummy_annot species)
               in
               if alg = Ast.CONST (Nbr.zero) then term
               else
                 Ast.BIN_ALG_OP
                   (
                     Operator.SUM,
                     Location.dummy_annot alg,
                     Location.dummy_annot term)
           end
         | Token _ | Dummy ->
           alg

      )
      network.id_of_ode_var
      (Ast.CONST (Nbr.zero))

  let species_of_species_id network =
    (fun i -> Mods.DynArray.get network.species_tab i)
  let get_reactions network = network.reactions

  let rec convert_alg_expr alg network =
    match
      alg
    with
    | Ast.BIN_ALG_OP (op, arg1, arg2 ),loc ->
      Ast.BIN_ALG_OP (op, convert_alg_expr arg1 network, convert_alg_expr arg2 network),loc
    | Ast.UN_ALG_OP (op, arg),loc ->
      Ast.UN_ALG_OP (op, convert_alg_expr arg network),loc
    | Ast.KAPPA_INSTANCE pattern, loc ->
      let cc = I.connected_components_of_patterns pattern in
      begin
        match cc with
        | [] ->
          Ast.CONST Nbr.zero
        | (_,h)::t ->
          List.fold_left
            (fun expr (_,h) ->
               Ast.BIN_ALG_OP
                 (Operator.MULT,
                  Location.dummy_annot expr,
                  Location.dummy_annot (convert_cc h network)))
            (convert_cc h network)
            t
      end, loc
    | Ast.TOKEN_ID a, loc ->
      Ast.TOKEN_ID a, loc
    | Ast.OBS_VAR a, loc ->
      Ast.OBS_VAR a, loc
    | Ast.CONST a , loc ->
      Ast.CONST a, loc
    | Ast.STATE_ALG_OP op,loc ->
      Ast.STATE_ALG_OP op,loc

  let convert_initial_state intro network =
    let a,b,c = intro in
    a,
    convert_alg_expr ((*Location.dummy_annot*) b) network,
    match
      fst c
    with
    | Ast.INIT_MIX m ->
      begin
        let cc = I.connected_components_of_mixture m in
        let list =
          List.rev_map
            (fun x -> translate_species x network)
            (List.rev cc)
        in
        list
      end
    | Ast.INIT_TOK token ->
      [translate_token
         token
         network]


  let convert_var_def variable_def network =
    let a,b = variable_def in
    a,convert_alg_expr b network

  let convert_var_defs compil network =
    let list_var = I.get_variables compil in
    let list, network =
      List.fold_left
        (fun (list,network) def ->
           let a,b = convert_var_def def network in
           (Var (get_fresh_var_id network,Some a,b))::list,
           inc_fresh_var_id
             {network with varmap = Mods.StringMap.add (fst a) (get_fresh_var_id network) network.varmap})
        ([],network)
        list_var
    in
    let list_init = I.get_initial_state compil in
    let init_tab =
      Mods.DynArray.make (get_fresh_ode_var_id network) []
    in
    let add i j =
      Mods.DynArray.set
        init_tab
        i
        (j::(Mods.DynArray.get init_tab i))
    in
    let list, network =
      List.fold_left
        (fun (list,network) def ->
           let a,b,c = convert_initial_state def network in
           let () =
             List.iter
               (fun id -> add id (get_fresh_var_id network))
               c
           in
           (Init_expr (network.fresh_var_id,a,b,c))::list,
           (inc_fresh_var_id network)
        )
        (list,network)
        list_init
    in
    let size = List.length list in
    let npred =
      Mods.DynArray.create (get_fresh_var_id network) 0
    in
    let lsucc =
      Mods.DynArray.create (get_fresh_var_id network) []
    in
    let dec_tab =
      Mods.DynArray.create network.fresh_var_id
        (Dummy_decl,None,Location.dummy_annot (Ast.CONST Nbr.zero))
    in
    let add_succ i j =
      let () = Mods.DynArray.set npred j (1+(Mods.DynArray.get npred j)) in
      let () = Mods.DynArray.set lsucc i (j::(Mods.DynArray.get lsucc i)) in
      ()
    in
    let () =
      List.iter
        (fun decl ->
           match decl
           with
           | Dummy_decl -> ()
           | Init_expr (id,a,b,_)
           | Var (id,a,b) ->
             begin
               let () = Mods.DynArray.set dec_tab id (decl,a,b) in
               let rec aux expr =
                 match expr with
                 | Ast.CONST _,_ -> ()
                 | Ast.BIN_ALG_OP (_,a,b),_ -> (aux a;aux b)
                 | Ast.UN_ALG_OP (_,a),_ -> aux a
                 | Ast.STATE_ALG_OP _,_ -> ()
                 | Ast.OBS_VAR string,_ ->
                   let id' =
                     Mods.StringMap.find_option string
                       network.varmap in
                   begin
                     match id' with
                     | Some id' ->
                       add_succ id id'
                     | None ->
                       ()
                   end
                 | Ast.TOKEN_ID s,_ ->
                   let id' = translate_token s network in
                   let list =
                     Mods.DynArray.get
                       init_tab
                       id'
                   in
                   List.iter (fun id' -> add_succ id id') list
                 | Ast.KAPPA_INSTANCE id',_ ->
                   let list =
                     Mods.DynArray.get
                       init_tab
                       id'
                   in
                   List.iter (fun id' -> add_succ id id') list
               in
               aux b
             end
        )
        list
    in
    let top_sort =
      let clean k to_be_visited =
        let l = Mods.DynArray.get lsucc k in
        List.fold_left
          (fun to_be_visited j ->
             let old = Mods.DynArray.get npred j in
             let () = Mods.DynArray.set npred j (old-1) in
             if old = 1 then j::to_be_visited else to_be_visited)
          to_be_visited l
      in
      let to_be_visited =
        let rec aux k l =
          if k < fst_id
          then l
          else
          if Mods.DynArray.get npred k = 0
          then
            aux (k-1) (k::l)
          else
            aux (k-1) l
        in
        aux (network.fresh_var_id-1) []
      in
      let rec aux to_be_visited l =
        match to_be_visited with
        | [] -> List.rev l
        | h::t -> aux (clean h t) (h::l)
      in
      let l = aux to_be_visited [] in
      let l =
        List.rev_map
          (fun x ->
             let decl,_,_ = Mods.DynArray.get dec_tab x in decl
          ) l
      in l
    in
    let size' = List.length top_sort in
    if size' = size
    then
      {network with var_declaration = top_sort}
    else
      let () = Printf.fprintf stdout "Circular dependencies\n" in
      assert false

  let convert_one_obs obs network =
    let a,b = obs in
    a,convert_alg_expr b network

  let convert_obs compil network =
    let list_obs = I.get_obs compil in
    let network =
      List.fold_left
        (fun network obs ->
           inc_fresh_obs_id
             {network with
              obs = (get_fresh_obs_id network,
                     convert_alg_expr obs network)
                    ::network.obs})
        network
        list_obs
    in
    {network with
     obs = List.rev network.obs;
     n_obs = network.n_obs - 1}


  let species_of_initial_state =
    List.fold_left
      (fun list (_,_,(b,_)) ->
         match b with
         | Ast.INIT_MIX b ->
           begin
             List.fold_left
               (fun list a -> a::list)
               list
               (I.connected_components_of_mixture b)
           end
         | Ast.INIT_TOK _ -> list)
      []

  let rec is_const expr constvarset =
    match
      expr
    with
    | Ast.CONST _,_ -> true
    | Ast.BIN_ALG_OP (_,a,b),_ ->
      is_const a constvarset && is_const b constvarset
    | Ast.UN_ALG_OP (_,a),_ -> is_const a constvarset

    | Ast.OBS_VAR string,_ ->
      Mods.StringSet.mem string constvarset
    | Ast.STATE_ALG_OP _,_
    | Ast.TOKEN_ID _,_
    | Ast.KAPPA_INSTANCE _,_ -> false

  type rate =
    (ode_var_id, string) Ast.ast_alg_expr Location.annot

  type sort_rules_and_decl =
    {
      const_decl_set : Mods.StringSet.t ;
      const_decl: decl list ;
      var_decl: decl list ;
      init: decl list ;
      const_rate :
        (I.rule_id * I.rule * I.rule_mode * rate) list ;
      var_rate :
        (I.rule_id * I.rule * I.rule_mode * rate) list ;
    }

  let init_sort_rules_and_decl =
    {
      const_decl_set = Mods.StringSet.empty ;
      const_decl = [] ;
      var_decl = [] ;
      const_rate = [] ;
      var_rate = [] ;
      init = [] ;
    }

  let var_rate (id,mode,_) =
    match mode with
    | I.Direct, I.Usual ->
      Ode_loggers.Rate id
    | I.Direct, I.Unary ->
      Ode_loggers.Rateun id
    | I.Reverse, I.Usual ->
      Ode_loggers.Rated id
    | I.Reverse, I.Unary ->
      Ode_loggers.Rateund id

  let split_var_declaration network sort_rules_and_decls =
    let decl =
      List.fold_left
        (fun sort_decls decl ->
           match decl with
           | Dummy_decl
           | Var (_,None,_)
           | Init_expr _ ->
             {
               sort_decls
               with
                 init = decl::sort_decls.init}
           | Var (_id,Some (a,_),b) ->
             if is_const b sort_decls.const_decl_set
             then
               {
                 sort_decls
                 with
                   const_decl_set = Mods.StringSet.add a sort_decls.const_decl_set ;
                   const_decl = decl::sort_decls.const_decl
               }
             else
               {
                 sort_decls
                 with
                   var_decl =
                     decl::sort_decls.var_decl
               })
        sort_rules_and_decls
        network.var_declaration
    in
    {decl
     with
      const_decl = List.rev decl.const_decl ;
      var_decl = List.rev decl.var_decl ;
      init = List.rev decl.init}


  let split_rules network sort_rules_and_decls =
    let sort =
      List.fold_left
        (fun sort_rules enriched_rule ->
           let rate = I.rate enriched_rule.rule enriched_rule.mode in
           match rate with
           | None -> sort_rules
           | Some rate ->
             let rate = convert_alg_expr rate network in
             let sort_rules =
               if is_const rate sort_rules_and_decls.const_decl_set
               then
                 {
                   sort_rules
                   with const_rate =
                          (enriched_rule.rule_id,
                           enriched_rule.rule,
                           enriched_rule.mode, rate)::sort_rules.const_rate
                 }
               else
                 {
                   sort_rules
                   with var_rate =
                          (enriched_rule.rule_id,
                           enriched_rule.rule,
                           enriched_rule.mode, rate)::sort_rules.var_rate
                 }
             in
             sort_rules)
        sort_rules_and_decls
        network.rules
    in
    {sort
     with const_rate = List.rev sort.const_rate ;
          var_rate = List.rev sort.var_rate}

  let split_rules_and_decl network =
    split_rules network (split_var_declaration network init_sort_rules_and_decl)

  let network_from_compil compil =
    let rules = I.get_rules compil in
    let initial_state = species_of_initial_state (I.get_initial_state compil) in
    let network = compute_reactions rules initial_state in
    let network = convert_tokens compil network in
    let network = convert_var_defs compil network in
    let network = convert_obs compil network in
    network

  let handler_init =
    {
      Ode_loggers.int_of_obs = (fun i  -> i) ;
      Ode_loggers.int_of_kappa_instance = (fun i -> i) ;
      Ode_loggers.int_of_token_id = (fun i -> Printf.fprintf stdout "%i" i ; i) ;
    }

  let handler_expr network =
    {
      Ode_loggers.int_of_obs = (fun string  -> Mods.StringMap.find_default 0 string network.varmap) ;
      Ode_loggers.int_of_kappa_instance = (fun i -> i) ;
      Ode_loggers.int_of_token_id = (fun string ->
          Mods.StringMap.find_default 0 string network.tokenmap) ;
    }


  let increment is_zero ?init_mode:(init_mode=false) logger x =
    if is_zero x
    then
      Ode_loggers.associate ~init_mode logger (Ode_loggers.Init x)
    else
      Ode_loggers.increment ~init_mode logger (Ode_loggers.Init x)

  let affect_var is_zero ?init_mode:(init_mode=false) logger network decl =
    let handler_expr = handler_expr network in
    match decl with
    | Dummy_decl -> ()
    | Init_expr (id',_comment, expr, list) ->
      begin
        match list with
        | [] -> ()
        | [a] ->
          let n = I.nbr_automorphisms_in_chemical_species (species_of_species_id network a)
          in
          let expr =
            if n = 1
            then
              expr
            else
              Location.dummy_annot (Ast.BIN_ALG_OP(Operator.MULT,alg_of_int n,expr))
          in
          increment is_zero ~init_mode logger a expr handler_expr
        | _ ->
          let () = Ode_loggers.associate ~init_mode logger (Ode_loggers.Expr id') expr handler_expr in
          List.iter
            (fun id ->
               let n = I.nbr_automorphisms_in_chemical_species (species_of_species_id network id)
               in
               let expr = Location.dummy_annot (Ast.OBS_VAR id') in
               let expr =
                 if n = 1
                 then
                   expr
                 else
                   Location.dummy_annot (Ast.BIN_ALG_OP(Operator.MULT,alg_of_int n,expr))
               in
               increment is_zero logger ~init_mode id expr handler_init)
            list
      end
    | Var (id,_comment,expr) ->
      Ode_loggers.associate ~init_mode logger (Ode_loggers.Expr id) expr handler_expr

  let fresh_is_zero network =
    let is_zero = Mods.DynArray.create (get_fresh_ode_var_id network) true in
    let is_zero x =
      if Mods.DynArray.get is_zero x
      then
        let () = Mods.DynArray.set is_zero x false in
        true
      else
        false
    in is_zero

  let declare_rates_global logger network =
    let do_it f =
      Ode_loggers.declare_global logger (f network.n_rules)
    in
    let () = do_it (fun x -> Ode_loggers.Rate x) in
    let () = do_it (fun x -> Ode_loggers.Rated x) in
    let () = do_it (fun x -> Ode_loggers.Rateun x) in
    let () = do_it (fun x -> Ode_loggers.Rateund x) in
    let () = Loggers.print_newline logger in
    ()

  let export_main
      ~command_line ~command_line_quotes ~data_file ~init_t ~max_t ~nb_points
      logger compil network split =
    let is_zero = fresh_is_zero network in
    let handler_expr = handler_expr network in
    let () = Ode_loggers.open_procedure logger "main" "main" [] in
    let () = Loggers.fprintf logger "%%%% command line: " in
    let () = Loggers.print_newline logger in
    let () = Loggers.fprintf logger "%%" in
    let () = Ode_loggers.print_comment logger ("     "^command_line_quotes) in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.print_ode_preamble logger () in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.associate logger Ode_loggers.Tinit (alg_of_float init_t) handler_expr in
    let () =
      Ode_loggers.associate logger Ode_loggers.Tend
        (alg_of_float max_t)
        handler_expr
    in
    let () =
      Ode_loggers.associate logger Ode_loggers.InitialStep
        (alg_of_float  0.000001) handler_expr
    in
    let () =
      Ode_loggers.associate logger Ode_loggers.Num_t_points
        (alg_of_int nb_points) handler_expr
    in
    let () = Loggers.print_newline logger in
    let () =
      Ode_loggers.declare_global logger Ode_loggers.N_ode_var
    in
    let () =
      Ode_loggers.associate
        logger
        Ode_loggers.N_ode_var
        (alg_of_int (get_last_ode_var_id network))
        handler_expr
    in
    let () =
      Ode_loggers.associate
        logger
        Ode_loggers.N_var
        (alg_of_int (get_last_var_id network))
        handler_expr
    in
    let () =
      Ode_loggers.associate
        logger
        Ode_loggers.N_obs
        (alg_of_int network.n_obs)
        handler_expr in
    let () =
      Ode_loggers.associate
        logger
        Ode_loggers.N_rules
        (alg_of_int network.n_rules)
        handler_expr
    in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.declare_global logger (Ode_loggers.Expr network.fresh_var_id) in
    let () = Ode_loggers.initialize logger (Ode_loggers.Expr network.fresh_var_id) in
    let () = Ode_loggers.declare_global logger (Ode_loggers.Init network.fresh_ode_var_id) in
    let () = Ode_loggers.initialize logger (Ode_loggers.Init network.fresh_ode_var_id) in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.start_time logger init_t in
    let () = Loggers.print_newline logger in
    let () =
      Ode_loggers.associate logger
        (Ode_loggers.Init (get_last_ode_var_id network))
        (Location.dummy_annot (Ast.STATE_ALG_OP Operator.TIME_VAR))
        handler_init
    in
    let () =
      List.iter
        (affect_var is_zero logger ~init_mode:true network)
        network.var_declaration
    in
    let () = Loggers.print_newline logger in
    let () = declare_rates_global logger network in
    let () =
      List.iter
        (fun (id,_rule,mode,rate) ->
           Ode_loggers.associate
             logger
             (var_rate (id,mode,rate)) rate handler_expr)
        split.const_rate
    in
    let titles = I.get_obs_titles compil in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.print_license_check logger in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.print_options logger in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.print_integrate logger in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.associate_nrows logger in
    let () = Ode_loggers.initialize logger Ode_loggers.Tmp  in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.print_interpolate logger in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.print_dump_plots ~data_file ~command_line ~titles logger in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.close_procedure logger in
    let () = Loggers.print_newline logger in
    let () = Loggers.print_newline logger in
    let () = Loggers.print_newline logger in
    ()

  let export_dydt logger network split =
    let is_zero = fresh_is_zero network in
    let () = Ode_loggers.open_procedure logger "dydt" "ode_aux" ["t";"y"] in
    let () = Loggers.print_newline logger in
    let () =
      Ode_loggers.declare_global logger Ode_loggers.N_ode_var
    in
    let () =
      Ode_loggers.declare_global logger (Ode_loggers.Expr 1)
    in
    let () = declare_rates_global logger network in
    let () = List.iter (affect_var is_zero logger ~init_mode:false network) split.var_decl in
    let () = Loggers.print_newline logger in
    let () =
      List.iter
        (fun (id,_rule,mode,rate) ->
           Ode_loggers.associate
             logger
             (var_rate (id,mode,rate)) rate (handler_expr network))
        split.var_rate
    in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.initialize logger (Ode_loggers.Deriv 1) in
    let do_it f l reactants enriched_rule =
      List.iter
        (fun species ->
           let nauto_in_species =
             I.nbr_automorphisms_in_chemical_species (species_of_species_id network species)
           in
           let nauto_in_lhs = enriched_rule.divide_rate_by in
           f logger (Ode_loggers.Deriv species) ~nauto_in_species ~nauto_in_lhs (var_of_rule enriched_rule) reactants)
        l
    in
    let () =
      List.iter
        (fun (reactants, products, token_vector, enriched_rule) ->
           let nauto_in_lhs = enriched_rule.divide_rate_by in
           let reactants' = List.rev_map (fun x -> Ode_loggers.Concentration x) (List.rev reactants) in

           let () = do_it Ode_loggers.consume reactants reactants' enriched_rule in
           let () = do_it Ode_loggers.produce products reactants' enriched_rule in
           let () =
             List.iter
               (fun (expr,(token,_loc)) ->
                  Ode_loggers.update_token
                    logger
                    (Ode_loggers.Deriv token) ~nauto_in_lhs (var_of_rule enriched_rule)
                    (convert_alg_expr expr network) reactants' (handler_expr network))
               token_vector
           in ()
        )
        network.reactions
    in
    (* Derivative of time is equal to 1 *)
    let () = Ode_loggers.associate logger (Ode_loggers.Deriv (get_last_ode_var_id network)) (alg_of_int 1) (handler_expr network) in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.close_procedure logger in
    let () = Loggers.print_newline logger in
    let () = Loggers.print_newline logger in
    ()

  let export_init logger network =
    let () = Ode_loggers.open_procedure logger "Init" "ode_init" [] in
    let () = Loggers.print_newline logger in
    let () =
      Ode_loggers.declare_global logger Ode_loggers.N_ode_var
    in
    let () =
      Ode_loggers.declare_global logger (Ode_loggers.Init (get_last_ode_var_id network))
    in
    let () = Ode_loggers.initialize logger (Ode_loggers.Initbis (get_last_ode_var_id network)) in
    let () = Loggers.print_newline logger in
    let rec aux k =
      if
        k >= get_fresh_ode_var_id network
      then
        ()
      else
        let () = Ode_loggers.declare_init logger k in
        aux (next_id k)
    in
    let () = aux fst_id in
    let () = Ode_loggers.close_procedure logger in
    let () = Loggers.print_newline logger in
    let () = Loggers.print_newline logger in
    ()

  let export_obs logger network split =
    let is_zero = fresh_is_zero network in
    let () = Ode_loggers.open_procedure logger "obs" "ode_obs" ["y"] in
    (* add t *)
    let () = Loggers.print_newline logger in
    let () =
      Ode_loggers.declare_global logger Ode_loggers.N_obs
    in
    let () =
      Ode_loggers.declare_global logger (Ode_loggers.Expr 1)
    in
    let () =
      Ode_loggers.initialize logger (Ode_loggers.Obs (network.n_obs))
    in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.associate_t logger (get_last_ode_var_id network) in
    let () = List.iter (affect_var is_zero logger ~init_mode:false network) split.var_decl in
    let () = Loggers.print_newline logger in
    let () =
      List.iter
        (fun (id,expr) -> Ode_loggers.associate logger (Ode_loggers.Obs id) expr (handler_expr network))
        network.obs
    in
    let () = Loggers.print_newline logger in
    let () = Ode_loggers.close_procedure logger in
    let () = Loggers.print_newline logger in
    let () = Loggers.print_newline logger in
    ()

  let export_network
      ~command_line ~command_line_quotes ~data_file ~init_t ~max_t ~nb_points
      logger compil network =
    (* add a spurious variable for time *)
    let network = inc_fresh_ode_var_id network in
    let sorted_rules_and_decl =
      split_rules_and_decl network
    in
    let () =
      export_main
        ~command_line ~command_line_quotes ~data_file ~init_t ~max_t ~nb_points
        logger compil network sorted_rules_and_decl
    in
    let () = export_dydt logger network sorted_rules_and_decl in
    let () = export_init logger network in
    let () = export_obs logger network sorted_rules_and_decl in
    let () = Ode_loggers.launch_main logger in
    ()

  let get_reactions network =
    let list = get_reactions network in
    List.rev_map
      (fun (a,b,c,d)-> (a,b,c,d.rule))
      (List.rev list)

end
