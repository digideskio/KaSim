type agent = int * int
(** agent_id * agent_type *)

let print_agent ?sigs f (id,ty) =
  match sigs with
  | None -> Format.pp_print_int f id
  | Some sigs -> Format.fprintf f "%a_%i" (Signature.print_agent sigs) ty id

let agent_to_json (id,ty) = `Assoc ["id", `Int id; "type", `Int ty]
let agent_of_json = function
  | `Assoc ["id", `Int id; "type", `Int ty]
  | `Assoc ["type", `Int ty; "id", `Int id] -> (id,ty)
  | x -> raise (Yojson.Basic.Util.Type_error ("Invalid agent",x))

module Edge = struct
  type t = agent * int
  (** agent * site *)

  let _compare ((n,_),s) ((n',_),s') =
    let c = Mods.int_compare n n' in
    if c <> 0 then c else Mods.int_compare s s'

  (* let dummy_link = ((-1,-1),-1) *)
end

module Cache = struct
  type t = int Mods.DynArray.t
  let int_l = 30

  let create () = Mods.DynArray.make 1 0

  let mark t i =
    Mods.DynArray.set t (i / int_l)
      ((Mods.DynArray.get t (i / int_l)) lor (1 lsl (i mod int_l)))
  let test t i =
    (Mods.DynArray.get t (i / int_l)) land (1 lsl (i mod int_l)) <> 0

  let reset t = Mods.DynArray.fill t 0 (Mods.DynArray.length t) 0
end

type t =
  {
    mutable outdated : bool;
    connect : Edge.t option array Mods.DynArray.t;
    missings : Mods.Int2Set.t;
    state : int option array Mods.DynArray.t;
    sort : int option Mods.DynArray.t;
    cache : Cache.t;
    free_id : int * int list;
  }
(** (agent,site -> binding_state; missings);
    agent,site -> internal_state; agent -> sort; free_id
    the free sites are neither in missings nor in linking_destination *)

let empty () =
  {
    outdated = false;
    connect = Mods.DynArray.make 1 [||];
    missings = Mods.Int2Set.empty;
    state = Mods.DynArray.make 1 [||];
    sort = Mods.DynArray.make 1 None;
    cache = Cache.create ();
    free_id =(0,[]);
  }

let add_agent sigs ty graph =
  let ar = Signature.arity sigs ty in
  let al = Array.make ar None in
  let ai = Array.make ar None in
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  match graph.free_id with
  | new_id,h :: t ->
    let missings' = Tools.recti (fun a s -> Mods.Int2Set.add (h,s) a)
        graph.missings ar in
    let () = Mods.DynArray.set graph.connect h al in
    let () = Mods.DynArray.set graph.state h ai in
    let () = Mods.DynArray.set graph.sort h (Some ty) in
    h,
    {
      outdated = false;
      connect = graph.connect;
      missings = missings';
      state = graph.state;
      sort = graph.sort;
      cache = graph.cache;
      free_id = (new_id,t);
    }
  | new_id,[] ->
    let missings' = Tools.recti (fun a s -> Mods.Int2Set.add (new_id,s) a)
        graph.missings ar in
    let () = Mods.DynArray.set graph.connect new_id al in
    let () = Mods.DynArray.set graph.state new_id ai in
    let () = Mods.DynArray.set graph.sort new_id (Some ty) in
    new_id,
    {
      outdated = false;
      connect = graph.connect;
      missings = missings';
      state = graph.state;
      sort = graph.sort;
      cache = graph.cache;
      free_id = (succ new_id,[])
    }

let add_free ag s graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = (Mods.DynArray.get graph.connect ag).(s) <- None in
  {
    outdated = false;
    connect = graph.connect;
    missings = Mods.Int2Set.remove (ag,s) graph.missings;
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = graph.free_id;
  }
let add_internal ag s i graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = (Mods.DynArray.get graph.state ag).(s) <- Some i in
  {
    outdated = false;
    connect = graph.connect;
    missings = graph.missings;
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = graph.free_id;
  }

let add_link (ag,ty) s (ag',ty') s' graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = (Mods.DynArray.get graph.connect ag).(s) <- Some ((ag',ty'),s') in
  let () = (Mods.DynArray.get graph.connect ag').(s') <- Some ((ag,ty),s) in
  {
    outdated = false;
    connect = graph.connect;
    missings =
      Mods.Int2Set.remove (ag,s) (Mods.Int2Set.remove (ag',s') graph.missings);
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = graph.free_id;
  }

let remove_agent ag graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = Mods.DynArray.set graph.connect ag [||] in
  let () = Mods.DynArray.set graph.state ag [||] in
  let () = Mods.DynArray.set graph.sort ag None in
  {
    outdated = false;
    connect = graph.connect;
    missings = Mods.Int2Set.filter (fun (ag',_) -> ag <> ag') graph.missings;
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = let new_id,ids = graph.free_id in (new_id,ag::ids);
  }
let remove_free ag s graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = assert ((Mods.DynArray.get graph.connect ag).(s) = None) in
  {
    outdated = false;
    connect = graph.connect;
    missings = Mods.Int2Set.add (ag,s) graph.missings;
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = graph.free_id
  }
let get_internal ag s graph =
  let () = assert (not graph.outdated) in
  match (Mods.DynArray.get graph.state ag).(s) with
  | Some i -> i
  | None ->
    failwith ("Site "^string_of_int s^ " of agent "^string_of_int ag^
              " has no internal state to remove in the current graph.")

let remove_internal ag s graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = (Mods.DynArray.get graph.state ag).(s) <- None in
  {
    outdated = false;
    connect = graph.connect;
    missings = graph.missings;
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = graph.free_id
  }

let remove_link ag s ag' s' graph =
  let () = assert (not graph.outdated) in
  let () = graph.outdated <- true in
  let () = (Mods.DynArray.get graph.connect ag).(s) <- None in
  let () = (Mods.DynArray.get graph.connect ag').(s') <- None in
  {
    outdated = false;
    connect = graph.connect;
    missings =
      Mods.Int2Set.add (ag,s) (Mods.Int2Set.add (ag',s') graph.missings);
    state = graph.state;
    sort = graph.sort;
    cache = graph.cache;
    free_id = graph.free_id;
  }

let is_agent (ag,ty) graph =
  let () = assert (not graph.outdated&&Mods.Int2Set.is_empty graph.missings) in
  match Mods.DynArray.get graph.sort ag with
  | Some ty' -> let () = assert (ty = ty') in true
  | None -> false
let is_free ag s graph =
  let () = assert (not graph.outdated&&Mods.Int2Set.is_empty graph.missings) in
  let t = Mods.DynArray.get graph.connect ag in t <> [||] && t.(s) = None
let is_internal i ag s graph =
  let () = assert (not graph.outdated&&Mods.Int2Set.is_empty graph.missings) in
  let t = Mods.DynArray.get graph.state ag in
  t <> [||] && match t.(s) with
  | Some j -> j = i
  | None -> false
let link_exists ag s ag' s' graph =
  let () = assert (not graph.outdated&&Mods.Int2Set.is_empty graph.missings) in
  let t = Mods.DynArray.get graph.connect ag in
  t <> [||] &&
    match t.(s) with
  | Some ((ag'',_),s'') -> ag'=ag'' && s'=s''
  | None -> false

let exists_fresh ag s ty s' graph =
  let () = assert (not graph.outdated&&Mods.Int2Set.is_empty graph.missings) in
  let t = Mods.DynArray.get graph.connect ag in
  if t = [||] then None else
    match t.(s) with
    | Some ((ag',ty'),s'') ->
      if ty'=ty && s'=s'' then Some ag' else None
    | None -> None

let link_destination ag s graph =
  let () = assert (not graph.outdated) in
  (Mods.DynArray.get graph.connect ag).(s)

(** The snapshot machinery *)
let one_connected_component sigs ty node graph =
  let rec build acc free_id dangling =
    function
    | [] -> acc,free_id
    | (ty,node) :: todos ->
      if Cache.test graph.cache node
      then build acc free_id dangling todos
      else match Mods.DynArray.get graph.sort node with
        | None -> failwith "Edges.one_connected_component"
        | Some _ ->
          let () = Cache.mark graph.cache node in
          let arity = Signature.arity sigs ty in
          let ports = Array.make arity Raw_mixture.FREE in
          let (free_id',dangling',todos'),ports =
            Tools.array_fold_left_mapi
              (fun i (free_id,dangling,todos) _ ->
                 match (Mods.DynArray.get graph.connect node).(i) with
                 | None ->
                   (free_id,dangling,todos),Raw_mixture.FREE
                 | Some ((n',ty'),s') ->
                   match Mods.Int2Map.pop (n',s') dangling with
                   | None, dangling ->
                     (succ free_id,
                      Mods.Int2Map.add (node,i) free_id dangling,
                      if n' = node || List.mem (ty',n') todos
                      then todos
                      else (ty',n')::todos),
                     Raw_mixture.VAL free_id
                   | Some id, dangling' ->
                     (free_id,dangling',todos), Raw_mixture.VAL id)
              (free_id,dangling,todos) ports in
          let skel =
            { Raw_mixture.a_type = ty;
              Raw_mixture.a_ports = ports;
              Raw_mixture.a_ints = Mods.DynArray.get graph.state node; } in
          build (skel::acc) free_id' dangling' todos'
  in build [] 1 Mods.Int2Map.empty [ty,node]

let build_snapshot sigs graph =
  let () = assert (not graph.outdated) in
  let rec increment x = function
    | [] -> [1,x]
    | (n,y as h)::t ->
      if Raw_mixture.equal sigs x y then (succ n,y)::t
      else h::increment x t in
  let rec aux ccs node =
    if node = Mods.DynArray.length graph.sort
    then let () = Cache.reset graph.cache in ccs
    else
    if Cache.test graph.cache node
    then aux ccs (succ node)
    else match Mods.DynArray.get graph.sort node with
      | None -> aux ccs (succ node)
      | Some ty ->
        let (out,_) =
          one_connected_component sigs ty node graph in
        aux (increment out ccs) (succ node) in
  aux [] 0

let debug_print f graph =
  let print_sites ag =
    (Pp.array Pp.comma
       (fun s f l ->
          Format.fprintf
            f "%i%t%t" s
            (match (Mods.DynArray.get graph.state ag).(s) with
             | Some int -> fun f -> Format.fprintf f "~%i" int
             | None -> fun _ -> ())
            (fun f -> match l with
               | None ->
                 if Mods.Int2Set.mem (ag,s) graph.missings
                 then Format.pp_print_string f "?"
               | Some ((ag',ty'),s') ->
                 Format.fprintf f "->%i:%i.%i" ag' ty' s'))) in
  Mods.DynArray.print
    Pp.empty
    (fun ag f a ->
       match Mods.DynArray.get graph.sort ag with
       | Some ty ->
         Format.fprintf
           f "%i:%i(@[%a@])@ " ag ty (print_sites ag) a
       | None -> if a = [||] then ()
         else Format.fprintf
             f "%i:NOTYPE(@[%a@])@ " ag (print_sites ag) a
    )
    f graph.connect

type path = ((agent * int) * (agent * int)) list
(** ((agent_id, agent_name),site_name) *)

let aux_print_site ?sigs ty f i =
  match sigs with
  | None -> Format.pp_print_int f i
  | Some sigs -> Signature.print_site sigs ty f i
let rec print_path ?sigs f = function
  | [] -> Pp.empty_set f
  | [((_,ty as ag),s),((_,ty' as ag'),s')] ->
    Format.fprintf f "%a.%a@,-%a.%a"
      (print_agent ?sigs) ag (aux_print_site ?sigs ty) s
      (aux_print_site ?sigs ty') s' (print_agent ?sigs) ag'
  | (((_,ty as ag),s),((p',ty' as ag'),s'))::((((p'',_),_),_)::_ as l) ->
    Format.fprintf f "%a.%a@,-%a.%t%a"
      (print_agent ?sigs) ag (aux_print_site ?sigs ty) s
      (aux_print_site ?sigs ty') s'
      (fun f ->
         if p' <> p'' then Format.fprintf f "%a##" (print_agent ?sigs) ag')
      (print_path ?sigs) l

let empty_path = []
let singleton_path n s n' s' = [(n,s),(n',s')]
let rev_path l = List.rev_map (fun (x,y) -> (y,x)) l
let is_valid_path graph l =
  List.for_all (fun (((a,_),s),((a',_),s')) -> link_exists a s a' s' graph) l

(* depth = number of edges between root and node *)
let breadth_first_traversal
    ~looping dist stop_on_find is_interesting sigs links cache out todos =
  let rec look_each_site ((id,_ as ag),path as x) site (out,next as acc) =
    if site = 0 then Some (false,out,next) else
      match (Mods.DynArray.get links id).(pred site) with
      | None -> look_each_site x (pred site) acc
      | Some ((id',_ as ag'),site' as y) ->
        if ag' = fst looping  && site' <> snd looping then None
        else if Cache.test cache id' then look_each_site x (pred site) acc
        else
          let () = Cache.mark cache id' in
          let path' = (y,(ag,pred site))::path in
          let next' = (ag',path')::next in
          let out',store =
            match is_interesting ag' with
            | Some x -> ((x,id'),path')::out,true
            | None -> out,false in
          if store&&stop_on_find then Some (true,out',next')
          else look_each_site x (pred site) (out',next') in
  let rec aux depth out next = function
    | ((_,ty),_ as x)::todos ->
      (match look_each_site x (Signature.arity sigs ty) (out,next) with
       | None -> []
       | Some (stop,out',next') ->
         if stop then let () = Cache.reset cache in out'
         else aux depth out' next' todos)
    | [] -> match next with
      | [] -> let () = Cache.reset cache in out
      (* end when all graph traversed and return the list of paths *)
      | _ -> match dist with
        | Some d when d <= depth -> let () = Cache.reset cache in []
        (* stop when the max distance is reached *)
        | Some _ -> aux (depth+1) out [] next
        | None -> aux depth out [] next in
  aux 1 out [] todos

let paths_of_interest
    ~looping is_interesting sigs graph (start_point,start_ty) done_path =
  let () = assert (not graph.outdated) in
  let () = Cache.mark graph.cache start_point in
  let () = List.iter (fun (_,((x,_),_)) -> Cache.mark graph.cache x)
      done_path in
  let acc = match is_interesting (start_point,start_ty) with
    | None -> []
    | Some x -> [(x,start_point),done_path] in
  breadth_first_traversal ~looping None false is_interesting sigs graph.connect
    graph.cache acc [(start_point,start_ty),done_path]

(* nodes_x: agent_id list = (int * int) list
   nodes_y: adent_id list = int list *)
let are_connected
    ?candidate sigs graph nodes_x nodes_y dist store_dist =
  let () = assert (not graph.outdated) in
  (* look for the closest node in nodes_y *)
  let is_in_nodes_y z = if List.mem z nodes_y then Some () else None in
  (* breadth first search is called on a list of sites;
     start the breadth first search with the boundaries of nodes_x,
     that is all sites that are connected to other nodes in x
     and with all nodes in nodes_x marked as done *)
  match candidate with
  | Some p when dist = None && not store_dist && is_valid_path graph p -> Some p
  | (Some _ | None) ->
    let prepare =
      List.fold_left (fun acc (id,_ as ag) ->
          let () = Cache.mark graph.cache id in
          (ag,[])::acc) [] nodes_x in
    match breadth_first_traversal ~looping:((-1,-1),-1) dist true is_in_nodes_y
            sigs graph.connect graph.cache [] prepare
    with [] -> None
       | [ _,p ] -> Some p
       | _ :: _ -> failwith "Edges.are_they_connected completely broken"
