type t =
  {
    roots_of_ccs: Mods.IntSet.t Connected_component.Map.t;
    unary_ccs_of_roots: Connected_component.Set.t Mods.IntMap.t;
    matchings_of_rule:
      (Connected_component.Matching.t * int list) list Mods.IntMap.t;
    unary_candidates: Mods.Int2Set.t Mods.IntMap.t;
    unary_pathes: (int * Edges.path) Mods.Int2Map.t;
    edges: Edges.t;
    tokens: Nbr.t array;
    outdated_elements:
      Operator.DepSet.t *
      (((Connected_component.Set.t*int) * Edges.path) list
       * ((Connected_component.Set.t*int) * Edges.path) list) list
      * bool;
    story_machinery :
      (((bool*bool*bool)*bool) *
       (Trace.event_kind * Connected_component.t array *
        Instantiation.abstract Instantiation.test list)
         list Connected_component.Map.t (*currently tracked ccs *) *
       Trace.t) option;
    unary_distances: Data.distances option;
  }

type result = Clash | Success of t | Corrected of t

let empty ?story_compression ~store_distances env =
  {
    roots_of_ccs = Connected_component.Map.empty;
    unary_ccs_of_roots = Mods.IntMap.empty;
    matchings_of_rule = Mods.IntMap.empty;
    unary_candidates = Mods.IntMap.empty;
    unary_pathes = Mods.Int2Map.empty;
    edges = Edges.empty ();
    tokens = Array.make (Environment.nb_tokens env) Nbr.zero;
    outdated_elements = Operator.DepSet.empty,[],true;
    story_machinery =
      (match story_compression with
       | Some ((none,weak,strong),dump as story_compression) ->
         if none || weak || strong || dump
         then Some (story_compression,Connected_component.Map.empty,[])
         else None
       | None -> None);
    unary_distances =
      Tools.option_map
        (fun _ -> Array.make ((Environment.nb_syntactic_rules env)+1) None)
        store_distances;
  }

let print_injections ?sigs pr f roots_of_ccs =
  Format.fprintf
    f "@[<v>%a@]"
    (Pp.set Connected_component.Map.bindings Pp.space
       (fun f (cc,roots) ->
          Format.fprintf
            f "@[# @[%a@] ==>@ @[%a@]@]"
            (Connected_component.print ?sigs ~with_id:()) cc
            (Pp.set Mods.IntSet.elements Pp.comma pr) roots
       )
    ) roots_of_ccs

let update_roots is_add unary_ccs (map,rev) cc root =
  let va =
    Connected_component.Map.find_default Mods.IntSet.empty cc map in
  Connected_component.Map.add
    cc ((if is_add then Mods.IntSet.add else Mods.IntSet.remove) root va) map,
  if Connected_component.Set.mem cc unary_ccs then
    let va' =
      Mods.IntMap.find_default Connected_component.Set.empty root rev in
    let set =
      (if is_add
       then Connected_component.Set.add
       else Connected_component.Set.remove) cc va' in
    if Connected_component.Set.is_empty set
        then Mods.IntMap.remove root rev
        else Mods.IntMap.add root set rev
  else rev

let add_path x y p pathes =
  let add pair pathes =
    match Mods.Int2Map.find_option pair pathes with
    | None -> Mods.Int2Map.add pair (1,p) pathes
    | Some (i,_) -> Mods.Int2Map.add pair (succ i,p) pathes in
  if x = y then add (x,y) (add (y,x) pathes) else add (min x y, max x y) pathes
let add_candidate cands pathes rule_id x y p =
  let va = Mods.IntMap.find_default Mods.Int2Set.empty rule_id cands in
  (Mods.IntMap.add rule_id (Mods.Int2Set.add (x,y) va) cands,
   add_path x y p pathes)
let remove_path (x,y) pathes =
  let del pair pathes =
    match Mods.Int2Map.find_option pair pathes with
    | None -> pathes
    | Some (1,_) -> Mods.Int2Map.remove pair pathes
    | Some (i,p) -> Mods.Int2Map.add pair (pred i,p) pathes in
  if x = y then del (x,y) (del (y,x) pathes) else del (min x y, max x y) pathes
let remove_candidate cands pathes rule_id (x,y as pair) =
  let va =
    Mods.Int2Set.remove
      pair (Mods.IntMap.find_default Mods.Int2Set.empty rule_id cands) in
  let va' = if x = y then Mods.Int2Set.remove (y,x) va else va in
  ((if Mods.Int2Set.is_empty va' then Mods.IntMap.remove rule_id cands
    else Mods.IntMap.add rule_id va' cands), remove_path pair pathes)

let new_place free_id (inj_nodes,inj_fresh) = function
  | Agent_place.Existing _ -> failwith "Rule_interpreter.new_place"
  | Agent_place.Fresh (_,id) ->
    (inj_nodes,Mods.IntMap.add id free_id inj_fresh)

let all_injections ?excp edges roots cca =
  snd @@
  Tools.array_fold_lefti
    (fun id (excp,inj_list) cc ->
       let cands,excp' =
         match excp with
         | Some (cc',root)
           when Connected_component.is_equal_canonicals cc cc' ->
           Mods.IntSet.add root Mods.IntSet.empty,None
         | (Some _ | None) ->
           Connected_component.Map.find_default Mods.IntSet.empty cc roots,excp in
       (excp',
        Mods.IntSet.fold
          (fun root new_injs ->
             List.fold_left
               (fun corrects (inj,roots) ->
                  match Connected_component.Matching.reconstruct
                          edges inj id cc root with
                  | None -> corrects
                  | Some new_inj -> (new_inj,root::roots) :: corrects)
               new_injs inj_list)
          cands []))
    (excp,[Connected_component.Matching.empty,[]]) cca

let apply_negative_transformation (side_effects,edges) = function
  | Primitives.Transformation.Agent (id,_) ->
    let edges' = Edges.remove_agent id edges in
    (side_effects,edges')
  | Primitives.Transformation.Freed ((id,_),s) -> (*(n,s)-bottom*)
    let edges' = Edges.remove_free id s edges in
    (side_effects,edges')
  | Primitives.Transformation.Linked (((id,_),s),((id',_),s')) ->
    let edges' = Edges.remove_link id s id' s' edges in
    (side_effects,edges')
  | Primitives.Transformation.NegativeWhatEver ((id,_),s) ->
    begin
      match Edges.link_destination id s edges with
      | None -> (side_effects,Edges.remove_free id s edges)
      | Some ((id',_ as nc'),s') ->
        ((nc',s')::side_effects,Edges.remove_link id s id' s' edges)
    end
  | Primitives.Transformation.PositiveInternalized _ ->
    raise
      (ExceptionDefn.Internal_Error
         (Location.dummy_annot "PositiveInternalized in negative update"))
  | Primitives.Transformation.NegativeInternalized ((id,_),s) ->
    let edges' = Edges.remove_internal id s edges in
    (side_effects,edges')

let apply_positive_transformation
    sigs (inj2graph,side_effects,edges) = function
  | Primitives.Transformation.Agent n ->
    let nc, inj2graph',edges' =
      let ty = Agent_place.get_type n in
      let id,edges' = Edges.add_agent sigs ty edges in
      (id,ty),new_place id inj2graph n,edges' in
    (inj2graph',side_effects,edges'),
    Primitives.Transformation.Agent nc
  | Primitives.Transformation.Freed (n,s) -> (*(n,s)-bottom*)
    let (id,_ as nc) = Agent_place.concretize inj2graph n in (*(A,23)*)
    let edges' = Edges.add_free id s edges in
    let side_effects' =
      Tools.list_smart_filter (fun x -> x <> (nc,s)) side_effects in
    (inj2graph,side_effects',edges'),
    Primitives.Transformation.Freed (nc,s)
  | Primitives.Transformation.Linked ((n,s),(n',s')) ->
    let nc = Agent_place.concretize inj2graph n in
    let nc' = Agent_place.concretize inj2graph n' in
    let edges' = Edges.add_link nc s nc' s' edges in
    let side_effects' = Tools.list_smart_filter
        (fun x -> x<>(nc,s) && x<>(nc',s')) side_effects in
    (inj2graph,side_effects',edges'),
    Primitives.Transformation.Linked ((nc,s),(nc',s'))
  | Primitives.Transformation.NegativeWhatEver _ ->
    raise
      (ExceptionDefn.Internal_Error
         (Location.dummy_annot "NegativeWhatEver in positive update"))
  | Primitives.Transformation.PositiveInternalized (n,s,i) ->
    let (id,_ as nc) = Agent_place.concretize inj2graph n in
    let edges' = Edges.add_internal id s i edges in
    (inj2graph,side_effects,edges'),
    Primitives.Transformation.PositiveInternalized (nc,s,i)
  | Primitives.Transformation.NegativeInternalized _ ->
    raise
      (ExceptionDefn.Internal_Error
         (Location.dummy_annot "NegativeInternalized in positive update"))

let obs_from_transformation domain edges acc = function
  | Primitives.Transformation.Agent nc ->
    Connected_component.Matching.observables_from_agent domain edges acc nc
  | Primitives.Transformation.Freed (nc,s) -> (*(n,s)-bottom*)
    Connected_component.Matching.observables_from_free domain edges acc nc s
  | Primitives.Transformation.Linked ((nc,s),(nc',s')) ->
    Connected_component.Matching.observables_from_link
      domain edges acc nc s nc' s'
  | Primitives.Transformation.PositiveInternalized (nc,s,i) ->
    Connected_component.Matching.observables_from_internal
      domain edges acc nc s i
  | Primitives.Transformation.NegativeInternalized ((id,_ as nc),s) ->
    let i  = Edges.get_internal id s edges in
    Connected_component.Matching.observables_from_internal
      domain edges acc nc s i
  | Primitives.Transformation.NegativeWhatEver ((id,_ as nc),s) ->
    match Edges.link_destination id s edges with
    | None ->
      Connected_component.Matching.observables_from_free domain edges acc nc s
    | Some (nc',s') ->
      Connected_component.Matching.observables_from_link
        domain edges acc nc s nc' s'

let add_path_to_tests path tests =
  let path_agents,path_tests =
    List.fold_left
      (fun (ag,te) (((id,_ as a),_),((id',_ as a'),_)) ->
         let ag',te' =
           if Mods.IntSet.mem id ag then ag,te
           else Mods.IntSet.add id ag,Instantiation.Is_Here a::te in
         if Mods.IntSet.mem id' ag' then ag',te'
         else Mods.IntSet.add id' ag',Instantiation.Is_Here a'::te')
      (Mods.IntSet.empty,[]) path in
  let tests' =
    List.filter (function
        | Instantiation.Is_Here (id, _) ->
          not @@ Mods.IntSet.mem id path_agents
        | Instantiation.Is_Bound_to (a,b) ->
          List.for_all (fun (x,y) -> x <> a && x <> b && y<>a && y<>b) path
        | (Instantiation.Has_Internal _ | Instantiation.Is_Free _
          | Instantiation.Is_Bound _
          | Instantiation.Has_Binding_type _) -> true)
      tests in
  List.rev_append
    path_tests
    (Tools.list_rev_map_append
       (fun (x,y) -> Instantiation.Is_Bound_to (x,y)) path tests')

let store_event counter inj2graph new_tracked_obs_instances event_kind
    ?path extra_side_effects rule = function
  | None as x -> x
  | Some (compressions,x,steps) ->
    let (ctests,(ctransfs,cside_sites,csides)) =
      Instantiation.concretize_event
        inj2graph rule.Primitives.instantiations in
    let cactions =
      (ctransfs,cside_sites,List.rev_append extra_side_effects csides) in
    let full_concrete_event =
      match path with
      | None -> ctests,cactions
      | Some path ->
        add_path_to_tests path ctests,cactions in
    let steps' =
      Trace.store_event counter (event_kind,full_concrete_event) steps in
    let steps'' =
      List.fold_left
        (fun steps x ->
           Trace.store_obs counter x steps)
        steps' new_tracked_obs_instances
    in
    Some (compressions,x,steps'')

let store_obs edges roots obs acc = function
  | None -> acc
  | Some (_,tracked,_) ->
    List.fold_left
      (fun acc (cc,(root,_)) ->
         try
           List.fold_left
             (fun acc (ev,ccs,tests) ->
                List.fold_left
                  (fun acc (inj,_) ->
                     let tests' =
                       List.map (Instantiation.concretize_test
                                   (inj,Mods.IntMap.empty)) tests in
                     (ev,tests') :: acc)
                  acc (all_injections ~excp:(cc,root) edges roots ccs))
             acc (Connected_component.Map.find_default [] cc tracked)
         with Not_found -> acc)
      acc obs

let potential_root_of_unary_ccs roots (i,_) =
  let ccs =
    Mods.IntMap.find_default Connected_component.Set.empty i roots in
  if Connected_component.Set.is_empty ccs then None else Some ccs

let remove_unary_instances unaries obs deps =
  Operator.DepSet.fold
    (fun x (cands,pathes,no_unaries as acc) ->
       match x with
       | (Operator.ALG _ | Operator.PERT _) -> acc
       | Operator.RULE i ->
         match Mods.IntMap.find_option i cands with
         | None -> acc
         | Some l ->
           let byebye,stay =
             Mods.Int2Set.partition
               (fun (x,y) -> List.exists (fun (_,(a,_)) -> a = x || a = y) obs)
               l in
           ((if Mods.Int2Set.is_empty stay then Mods.IntMap.remove i cands
             else Mods.IntMap.add i stay cands),
            Mods.Int2Set.fold remove_path byebye pathes,
            no_unaries&&Mods.Int2Set.is_empty byebye)
    ) deps unaries

let update_edges
    sigs counter domain unary_ccs inj_nodes state event_kind ?path rule =
  let former_deps,unary_cands,no_unary = state.outdated_elements in
  (*Negative update*)
  let concrete_removed =
    List.map (Primitives.Transformation.concretize
                (inj_nodes,Mods.IntMap.empty)) rule.Primitives.removed in
  let ((del_obs,del_deps),_) =
    List.fold_left
      (obs_from_transformation domain state.edges)
      (([],Operator.DepSet.empty),Connected_component.Matching.empty_cache)
      concrete_removed in
  let roots' =
    List.fold_left
      (fun r' (cc,(root,_)) -> update_roots false unary_ccs r' cc root)
      (state.roots_of_ccs,state.unary_ccs_of_roots) del_obs in
  let (side_effects,edges_after_neg) =
    List.fold_left
      apply_negative_transformation ([],state.edges) concrete_removed in
  (*Negative unary*)
  let (unary_candidates',unary_pathes',no_unary') =
    remove_unary_instances
      (state.unary_candidates,state.unary_pathes,no_unary) del_obs del_deps in
  (*Positive update*)
  let (final_inj2graph,remaining_side_effects,edges'),concrete_inserted =
    List.fold_left
      (fun (x,p) h ->
         let (x', h') = apply_positive_transformation sigs x h in
         (x',h'::p)) (((inj_nodes,Mods.IntMap.empty),side_effects,edges_after_neg),[])
      rule.Primitives.inserted in
  let (edges'',concrete_inserted') =
    List.fold_left
      (fun (e,i)  ((id,_ as nc),s) ->
         Edges.add_free id s e,Primitives.Transformation.Freed (nc,s)::i)
      (edges',concrete_inserted) remaining_side_effects in
  let ((new_obs,new_deps),_) =
    List.fold_left
      (obs_from_transformation domain edges'')
      (([],Operator.DepSet.empty),Connected_component.Matching.empty_cache)
      concrete_inserted' in
  let roots'' =
    List.fold_left
      (fun r' (cc,(root,_)) -> update_roots true unary_ccs r' cc root) roots' new_obs in
  (*Positive unary*)
  let unary_cands',no_unary'' =
    if Connected_component.Set.is_empty unary_ccs
    then (unary_cands,no_unary')
    else
      let unary_pack =
        List.fold_left
          (fun (unary_cands,_ as acc) (cc,root) ->
             if Connected_component.Set.mem cc unary_ccs then
               let oths =
                 Edges.paths_of_interest ~looping:((-1,-1),-1)
                   (potential_root_of_unary_ccs (snd roots''))
                   sigs edges'' root (Edges.empty_path) in
               (oths,[(Connected_component.Set.singleton cc,fst root),
                      Edges.empty_path])::unary_cands,false
             else acc) (unary_cands,no_unary') new_obs in
      if path = None && not (Mods.IntMap.is_empty (snd roots''))
      then
        List.fold_left
          (fun (unary_cands,_ as acc) ((n,s),(n',s')) ->
             let cn = Agent_place.concretize final_inj2graph n in
             let cn' = Agent_place.concretize final_inj2graph n' in
             match
               Edges.paths_of_interest ~looping:(cn',s')
                 (potential_root_of_unary_ccs (snd roots''))
                 sigs edges'' cn (Edges.singleton_path cn s cn' s') with
             | [] -> acc
             | l ->
               let l' =
                 Edges.paths_of_interest ~looping:(cn,s)
                   (potential_root_of_unary_ccs (snd roots''))
                   sigs edges'' cn' (Edges.singleton_path cn' s' cn s) in
               (l',l) :: unary_cands,false)
          unary_pack rule.Primitives.fresh_bindings
      else unary_pack in
  (*Store event*)
  let new_tracked_obs_instances =
    store_obs edges'' (fst roots'') new_obs [] state.story_machinery in
  let story_machinery' =
    store_event
      counter final_inj2graph new_tracked_obs_instances event_kind
      ?path remaining_side_effects rule state.story_machinery in

  let rev_deps = Operator.DepSet.union
      former_deps (Operator.DepSet.union del_deps new_deps) in

  { roots_of_ccs = fst roots''; unary_ccs_of_roots = snd roots'';
    unary_candidates = unary_candidates';
    matchings_of_rule = state.matchings_of_rule;
    unary_pathes = unary_pathes'; edges = edges''; tokens = state.tokens;
    outdated_elements = (rev_deps,unary_cands',no_unary'');
    story_machinery = story_machinery';
    unary_distances = state.unary_distances; }

let raw_instance_number state ccs_l =
  let size cc =
    Mods.IntSet.size (Connected_component.Map.find_default
                        Mods.IntSet.empty cc state.roots_of_ccs) in
  let rect_approx ccs =
    Array.fold_left (fun acc cc ->  acc * (size cc)) 1 ccs in
  List.fold_left (fun acc ccs -> acc + (rect_approx ccs)) 0 ccs_l
let instance_number state ccs_l =
  Nbr.I (raw_instance_number state ccs_l)

let value_bool ~get_alg counter state expr =
  Expr_interpreter.value_bool
    counter ~get_alg
    ~get_mix:(fun ccs -> instance_number state ccs)
    ~get_tok:(fun i -> state.tokens.(i))
    expr
let value_alg ~get_alg counter state alg =
  Expr_interpreter.value_alg
    counter ~get_alg
    ~get_mix:(fun ccs -> instance_number state ccs)
    ~get_tok:(fun i -> state.tokens.(i))
    alg

let extra_outdated_var i state =
  let deps,unary_cands,no_unary = state.outdated_elements in
  {state with
   outdated_elements =
     (Operator.DepSet.add (Operator.ALG i) deps,unary_cands,no_unary)}

let new_unary_instances rule_id cc1 cc2 created_obs state =
  let (unary_candidates,unary_pathes) =
    List.fold_left
      (fun acc (left_l,right_l) ->
         List.fold_left
           (fun acc ((ccs,id),path) ->
              let path = Edges.rev_path path in
              Connected_component.Set.fold
                (fun cc acc ->
                   try
                     let goal,reverse =
                       if Connected_component.is_equal_canonicals cc cc1
                       then cc2,false
                       else if Connected_component.is_equal_canonicals cc cc2
                       then cc1,true
                       else raise Not_found in
                     List.fold_left
                       (fun (cands,pathes as acc') ((x,d),p) ->
                          if Connected_component.Set.exists
                              (fun x -> Connected_component.is_equal_canonicals x goal)
                              x then
                            let p' = List.rev_append p path in
                            if reverse
                            then add_candidate cands pathes rule_id d id p'
                            else add_candidate cands pathes rule_id id d p'
                          else acc')
                       acc
                       left_l
                   with Not_found -> acc)
                ccs acc) acc right_l)
      (state.unary_candidates,state.unary_pathes) created_obs in
  {state with unary_candidates = unary_candidates;
              unary_pathes = unary_pathes }

let store_activity ~get_alg store env counter state id syntax_id rate cc_va =
  let rate =
    Nbr.to_float @@ value_alg counter state ~get_alg rate in
  let () =
    if !Parameter.debugModeOn then
      Format.printf "@[%sule %a has now %i instances.@]@."
        (if id mod 2 = 1 then "Unary r" else "R")
        (Environment.print_rule ~env) (id/2) cc_va in
  let act =
    if cc_va = 0 then 0. else rate *. float_of_int cc_va in
  store id syntax_id act

let update_outdated_activities ~get_alg store env counter state =
  let deps,unary_cands,no_unary = state.outdated_elements in
  let rec aux state deps =
    Operator.DepSet.fold
      (fun dep state ->
         match dep with
         | Operator.ALG j ->
           aux state (Environment.get_alg_reverse_dependencies env j)
         | Operator.PERT (-1) -> state (* TODO *)
         | Operator.PERT _ -> assert false
         | Operator.RULE i ->
           let rule = Environment.get_rule env i in
           let cc_va = raw_instance_number
               state [rule.Primitives.connected_components] in
           let () =
             store_activity
               ~get_alg store env counter state (2*i)
               rule.Primitives.syntactic_rule
               (fst rule.Primitives.rate) cc_va in
           match Mods.IntMap.pop i state.matchings_of_rule with
           | None,_ -> state
           | Some _, match' -> { state with matchings_of_rule = match'})
      deps state in
  let state' = aux state (Environment.get_always_outdated env) in
  let state'' = aux state' deps in
  let state''' =
    if no_unary then state'' else
      Environment.fold_rules
        (fun i state rule ->
           match rule.Primitives.unary_rate with
           | None -> state
           | Some (unrate, _) ->
             let state' =
               new_unary_instances
                 i rule.Primitives.connected_components.(0)
                 rule.Primitives.connected_components.(1) unary_cands state in
             let va =
               Mods.Int2Set.size
                 (Mods.IntMap.find_default Mods.Int2Set.empty i state'.unary_candidates) in
             let () =
               store_activity
                 ~get_alg store env counter state' (2*i+1)
                 rule.Primitives.syntactic_rule (fst unrate) va in
             state') state'' env in
  {state''' with outdated_elements = (Operator.DepSet.empty,[],true) }

let update_tokens ~get_alg env counter state consumed injected =
  let do_op op state l =
    List.fold_left
      (fun st ((expr,_),i) ->
         let () =
           st.tokens.(i) <-
             op st.tokens.(i) (value_alg ~get_alg counter st expr) in
         let deps' = Environment.get_token_reverse_dependencies env i in
         if Operator.DepSet.is_empty deps' then st
         else
           let deps,unary_cands,no_unary = st.outdated_elements in
           { st with outdated_elements =
                       (Operator.DepSet.union deps deps',unary_cands,no_unary) }
      ) state l in
  let state' = do_op Nbr.sub state consumed in do_op Nbr.add state' injected

let transform_by_a_rule
    ~get_alg env domain unary_ccs counter state event_kind ?path rule inj =
  let state' =
    update_tokens
      ~get_alg env counter state rule.Primitives.consumed_tokens
      rule.Primitives.injected_tokens in
  update_edges (Environment.signatures env)
    counter domain unary_ccs inj state' event_kind ?path rule

let apply_unary_rule ~rule_id ~get_alg env domain unary_ccs counter state event_kind rule =
  let (root1,root2 as roots) =
    match
      Mods.Int2Set.random
        (Mods.IntMap.find_default
           Mods.Int2Set.empty rule_id state.unary_candidates) with
    | None -> failwith "Tried apply_unary_rule with no roots"
    | Some x -> x in
  let () =
    if !Parameter.debugModeOn then
      Format.printf "@[On roots:@ %i@ %i@]@." root1 root2 in
  let cc1 = rule.Primitives.connected_components.(0) in
  let cc2 = rule.Primitives.connected_components.(1) in
  let pair = (min root1 root2,max root1 root2) in
  let candidate =
    match Mods.Int2Map.find_option pair state.unary_pathes with
    | Some (_,x) -> x
    | None -> raise Not_found in
  let cands,pathes = remove_candidate state.unary_candidates state.unary_pathes
         rule_id roots in
  let deps,unary_cands,_ = state.outdated_elements in
  let state' =
    {state with
      unary_candidates = cands; unary_pathes = pathes;
      outdated_elements =
        (Operator.DepSet.add (Operator.RULE rule_id) deps,unary_cands,false)} in
  let missing_ccs =
    not @@
    Mods.IntSet.mem root1 (Connected_component.Map.find_default
                             Mods.IntSet.empty cc1 state.roots_of_ccs) &&
    Mods.IntSet.mem root2 (Connected_component.Map.find_default
                             Mods.IntSet.empty cc2 state.roots_of_ccs) in
  let inj1 =
    Connected_component.Matching.reconstruct
      state'.edges Connected_component.Matching.empty 0 cc1 root1 in
  let inj =
    match inj1 with
    | None -> None
    | Some inj -> Connected_component.Matching.reconstruct
                    state'.edges inj 1 cc2 root2 in
  match inj with
  | None -> Clash
  | Some inj ->
    let nodes = Connected_component.Matching.elements_with_types
        rule.Primitives.connected_components inj in
    let dist = match rule.Primitives.unary_rate with
      | None -> None
      | Some (_, dist_opt) -> dist_opt in
    match Edges.are_connected ~candidate (Environment.signatures env)
            state.edges nodes.(0) nodes.(1)
            dist (state'.unary_distances<>None) with
    | None -> Corrected state'
    | Some _ when missing_ccs -> Corrected state'
    | Some p as path ->
      let () =
        match state'.unary_distances with
        | None -> ()
        | Some rule_arr ->
          let n = List.length p in
          let t = Counter.current_time counter in
          let rule = Environment.get_rule env rule_id in
          let syntactic_id = rule.Primitives.syntactic_rule in
          match rule_arr.(syntactic_id) with
          | None -> rule_arr.(syntactic_id) <- Some [(t,n)]
          | Some ls -> rule_arr.(syntactic_id) <- Some ((t,n)::ls) in
      Success
        (transform_by_a_rule ~get_alg env domain unary_ccs counter state'
           event_kind ?path rule inj)

let apply_rule
    ?rule_id ~get_alg env domain unary_ccs counter state event_kind rule =
  let from_ccs () =
    Tools.array_fold_left_mapi
      (fun id inj cc ->
         let root =
           match Mods.IntSet.random
                   (Connected_component.Map.find_default
                      Mods.IntSet.empty cc state.roots_of_ccs) with
           | None -> failwith "Tried to apply_rule with no root"
           | Some x -> x in
         (match inj with
          | Some inj ->
            Connected_component.Matching.reconstruct state.edges inj id cc root
          | None -> None),root)
      (Some Connected_component.Matching.empty)
      rule.Primitives.connected_components in
  let inj,roots =
    match rule_id with
    | None -> from_ccs ()
    | Some id ->
      match Mods.IntMap.find_option id state.matchings_of_rule with
      | Some [] -> assert false
      | Some l ->
        let (inj,rev_roots) = Tools.list_random l in
        Some inj, Tools.array_rev_of_list rev_roots
      | None -> from_ccs () in
  let () =
    if !Parameter.debugModeOn then
      Format.printf "@[On roots:@ @[%a@]@]@."
        (Pp.array Pp.space (fun _ -> Format.pp_print_int)) roots in
  match inj with
  | None -> Clash
  | Some inj ->
    match rule.Primitives.unary_rate with
    | None ->
      let out =
        transform_by_a_rule
          ~get_alg env domain unary_ccs counter state event_kind rule inj in
      Success out
    | Some _ ->
      try
        let point = (min roots.(0) roots.(1), max roots.(0) roots.(1)) in
        let nb_use_cand,candidate =
          match Mods.Int2Map.find_option point state.unary_pathes with
          | Some x -> x
          | None -> raise Not_found in
        let nodes = Connected_component.Matching.elements_with_types
            rule.Primitives.connected_components inj in
        let dist = match rule.Primitives.unary_rate with
          | None -> None
          | Some (_, dist_opt) -> dist_opt in
        match
          Edges.are_connected ~candidate (Environment.signatures env)
            state.edges nodes.(0) nodes.(1) dist false with
        | None ->
          let rid =
            match rule_id with None -> assert false | Some rid -> rid in
          let cands,pathes =
            remove_candidate state.unary_candidates state.unary_pathes rid
              (roots.(0),roots.(1)) in
          let state' =
            {state with unary_candidates = cands; unary_pathes = pathes} in
          Success (transform_by_a_rule
                     ~get_alg env domain unary_ccs counter state'
                     event_kind rule inj)
        | Some p ->
          let state' =
            if p == candidate then state
            else {state with
                  unary_pathes =
                    Mods.Int2Map.add point (nb_use_cand,p) state.unary_pathes}
          in Corrected state'
      with Not_found ->
        let out =
          transform_by_a_rule
            ~get_alg env domain unary_ccs counter state event_kind rule inj in
        Success out

let force_rule
    ~get_alg env domain unary_ccs counter state event_kind rule =
  match apply_rule ~get_alg env domain unary_ccs counter state event_kind rule with
  | (Success out | Corrected out) -> out
  | Clash ->
    match all_injections
            state.edges state.roots_of_ccs rule.Primitives.connected_components
    with
    | [] -> state
    | l ->
      let (h,_) = Tools.list_random l in
      (transform_by_a_rule
         ~get_alg env domain unary_ccs counter state event_kind rule h)

let adjust_rule_instances ~rule_id ~get_alg store env counter state rule =
  let matches =
    all_injections
      state.edges state.roots_of_ccs rule.Primitives.connected_components in
  let () =
    store_activity
      ~get_alg store env counter state (2*rule_id)
      rule.Primitives.syntactic_rule
      (fst rule.Primitives.rate) (List.length matches) in
  { state with
    matchings_of_rule =
      Mods.IntMap.add rule_id matches state.matchings_of_rule }

let adjust_unary_rule_instances ~rule_id ~get_alg store env counter state rule =
  let cands = Mods.IntMap.find_default
      Mods.Int2Set.empty rule_id state.unary_candidates in
  let cc1 = rule.Primitives.connected_components.(0) in
  let cc2 = rule.Primitives.connected_components.(1) in
  let byebye,stay =
    Mods.Int2Set.partition
      (fun (root1,root2) ->
         let inj1 =
           Connected_component.Matching.reconstruct
             state.edges Connected_component.Matching.empty 0 cc1 root1 in
         match inj1 with
         | None -> true
         | Some inj -> None =
                       Connected_component.Matching.reconstruct
                         state.edges inj 1 cc2 root2)
      cands in
  let () =
    store_activity
      ~get_alg store env counter state (2*rule_id+1)
      rule.Primitives.syntactic_rule
      (fst rule.Primitives.rate) (Mods.Int2Set.size stay) in
  { state with
    unary_candidates =
      if Mods.Int2Set.is_empty stay
      then Mods.IntMap.remove rule_id state.unary_candidates
      else Mods.IntMap.add rule_id stay state.unary_candidates;
    unary_pathes = Mods.Int2Set.fold remove_path byebye state.unary_pathes; }

let snapshot env counter fn state = {
  Data.snap_file = fn;
  Data.snap_event = Counter.current_event counter;
  Data.agents = Edges.build_snapshot (Environment.signatures env) state.edges;
  Data.tokens = Array.mapi (fun i x ->
      (Format.asprintf "%a" (Environment.print_token ~env) i,x)) state.tokens;
}

let print env f state =
  let sigs = Environment.signatures env in
  Format.fprintf
    f "@[<v>%a@,%a@]"
    (Pp.list Pp.space (fun f (i,mix) ->
         Format.fprintf f "%%init: %i @[<h>%a@]" i
           (Raw_mixture.print ~compact:false sigs) mix))
    (Edges.build_snapshot sigs state.edges)
    (Pp.array Pp.space (fun i f el ->
         Format.fprintf
           f "%%init: %a <- %a"
           (Environment.print_token ~env) i Nbr.print el))
    state.tokens

let unary_distances state = state.unary_distances

let debug_print f state =
  Format.fprintf
    f "@[<v>%a@,%a@,%a@,%a@]"
    Edges.debug_print state.edges
    (Pp.array Pp.space (fun i f el ->
         Format.fprintf f "token_%i <- %a"
           i Nbr.print el))
    state.tokens
    (print_injections ?sigs:None Format.pp_print_int) state.roots_of_ccs
    (Pp.set Mods.IntMap.bindings Pp.cut
       (fun f (rule,roots) ->
          Format.fprintf f "@[rule_%i ==> %a@]" rule
            (Pp.set Mods.Int2Set.elements Pp.comma
               (fun f (x,y) -> Format.fprintf f "(%i,%i)" x y))
            roots))
    state.unary_candidates

let add_tracked ccs event_kind tests state =
  match state.story_machinery with
  | None -> state
  | Some (comp,tcc,x) ->
    let tcc' =
      Array.fold_left
        (fun tcc cc ->
           let acc = Connected_component.Map.find_default [] cc tcc in
           Connected_component.Map.add cc ((event_kind,ccs,tests)::acc) tcc)
        tcc ccs in
    { state with story_machinery = Some (comp,tcc',x) }

let remove_tracked ccs state =
  match state.story_machinery with
  | None -> state
  | Some (comp,tcc,x) ->
    let tester (_,el,_) =
      not @@
      Tools.array_fold_lefti
        (fun i b x -> b && Connected_component.is_equal_canonicals x el.(i))
        true ccs in
    let tcc' =
      Array.fold_left
        (fun tcc cc ->
           let acc = Connected_component.Map.find_default [] cc tcc in
           match List.filter tester acc with
           | [] -> Connected_component.Map.remove cc tcc
           | l -> Connected_component.Map.add cc l tcc)
        tcc ccs in
    { state with story_machinery = Some (comp,tcc',x) }

let generate_stories state =
  Tools.option_map
    (fun (comp,_,steps) -> (comp,List.rev steps)) state.story_machinery
