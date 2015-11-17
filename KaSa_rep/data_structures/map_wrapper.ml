module type Set_with_logs =
  sig
    type elt
    type t

    val empty: t
    val is_empty: t -> bool
    val singleton: elt -> t
    val is_singleton: t -> bool

   
    val add: Remanent_parameters_sig.parameters -> Exception.method_handler -> elt -> t -> Exception.method_handler * t 
    val remove:  Remanent_parameters_sig.parameters -> Exception.method_handler -> elt -> t -> Exception.method_handler * t 			      
   
    val union: Remanent_parameters_sig.parameters -> Exception.method_handler -> t -> t -> Exception.method_handler * t 
    val inter: Remanent_parameters_sig.parameters -> Exception.method_handler -> t -> t -> Exception.method_handler * t
    val diff:  Remanent_parameters_sig.parameters -> Exception.method_handler -> t -> t -> Exception.method_handler * t
    val cardinal: t -> int

    val mem: elt -> t -> bool
    val exists: (elt -> bool) -> t -> bool
    val filter: (elt -> bool) -> t -> t
    val for_all: (elt -> bool) -> t -> bool
    val partition: (elt -> bool) -> t -> t * t

    val compare: t -> t -> int
    val equal: t -> t -> bool
    val subset: t -> t -> bool

    val iter: (elt -> unit) -> t -> unit
    val fold: (elt -> 'a -> 'a) -> t -> 'a -> 'a
    val fold_inv: (elt -> 'a -> 'a) -> t -> 'a -> 'a

    val elements: t -> elt list

    val choose: t -> elt option
    val min_elt: t -> elt option
    val max_elt: t -> elt option
  end

module type Map_with_logs =
  sig
    type elt
    type set
    type +'a t
	     
    val empty: 'a t
    val is_empty: 'a t -> bool
    val min_elt: (elt -> 'a -> bool) -> 'a t -> elt option
    val find_option:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a t -> Exception.method_handler  * 'a option
    val find_default:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a -> elt -> 'a t -> Exception.method_handler  * 'a
    val find_default_without_logs: Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a -> elt -> 'a t -> Exception.method_handler  * 'a
    val find_option_without_logs: Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a t -> Exception.method_handler  * 'a option
    val add: Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a -> 'a t -> Exception.method_handler  * 'a t
    val remove: Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a t -> Exception.method_handler  * 'a t
    val update: Remanent_parameters_sig.parameters -> Exception.method_handler   -> 'a t -> 'a t -> Exception.method_handler  * 'a t    
    val map2:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a -> Exception.method_handler  * 'a) -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a -> Exception.method_handler  *  'a) -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a -> 'a -> Exception.method_handler  * 'a) -> 'a t -> 'a t -> Exception.method_handler  * 'a t
    val map2z:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a -> 'a -> Exception.method_handler  * 'a) -> 'a t -> 'a t -> Exception.method_handler  * 'a t 
    val fold2z: Remanent_parameters_sig.parameters -> Exception.method_handler  -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a  -> 'b  -> 'c   -> (Exception.method_handler  * 'c)) -> 'a t -> 'b t -> 'c -> Exception.method_handler  * 'c 
    val fold2:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a   -> 'c  -> Exception.method_handler  * 'c) -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'b  ->  'c  -> Exception.method_handler  * 'c) -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a -> 'b  -> 'c  -> Exception.method_handler  * 'c) ->  'a t -> 'b t -> 'c -> Exception.method_handler  * 'c 
  
    val fold2_sparse:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a  -> 'b  -> 'c  -> (Exception.method_handler  * 'c)) ->  'a t -> 'b t -> 'c -> Exception.method_handler  * 'c
    val iter2_sparse:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> (Remanent_parameters_sig.parameters -> Exception.method_handler  -> elt -> 'a  -> 'b  -> Exception.method_handler )->  'a t -> 'b t -> Exception.method_handler  
    val diff:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a t -> 'a t -> Exception.method_handler  * 'a t * 'a t 
    val diff_pred:  Remanent_parameters_sig.parameters -> Exception.method_handler  -> ('a -> 'a -> bool) -> 'a t -> 'a t -> Exception.method_handler  * 'a t * 'a t 
    val merge: Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a t -> 'a t -> Exception.method_handler  * 'a t
    val union: Remanent_parameters_sig.parameters -> Exception.method_handler  -> 'a t -> 'a t -> Exception.method_handler  * 'a t
    val fold_restriction: Remanent_parameters_sig.parameters -> Exception.method_handler  -> (elt -> 'a -> (Exception.method_handler  * 'b) -> (Exception.method_handler * 'b)) -> set -> 'a t -> 'b -> Exception.method_handler  * 'b 																       
								   
    val iter: (elt -> 'a -> unit) -> 'a t -> unit
    val fold: (elt -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
    val mapi: (elt -> 'a -> 'b) -> 'a t -> 'b t
    val map: ('a -> 'b) -> 'a t -> 'b t 
    val for_all: (elt -> 'a -> bool) -> 'a t -> bool
    val compare: ('a -> 'a -> int) -> 'a t -> 'a t -> int
    val equal: ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
    val bindings : 'a t -> (elt * 'a) list
   
  end

module type S_with_logs = sig
    type elt
    module Set : Set_with_logs with type elt = elt 
    module Map : Map_with_logs with type elt = elt and type set = Set.t
  end

let lift f = f Exception.wrap 
	   
						     
module Make(S_both:(SetMap.S)): S_with_logs with type elt = S_both.elt and type 'a Map.t= 'a S_both.Map.t and type Set.t = S_both.Set.t =
    (struct
      type elt = S_both.elt

      module Set =
	(struct
	  type elt=S_both.elt
	  type t=S_both.Set.t 
	  let empty = S_both.Set.empty
	  let is_empty = S_both.Set.is_empty
	  let singleton = S_both.Set.singleton
	  let is_singleton = S_both.Set.is_singleton 
	  let add = lift S_both.Set.add_with_logs 
	  let remove = lift S_both.Set.remove_with_logs
	  let union = lift S_both.Set.union_with_logs
	  let inter = lift S_both.Set.inter_with_logs
	  let diff = lift S_both.Set.diff_with_logs
	  let cardinal = S_both.Set.cardinal
	  let mem = S_both.Set.mem
	  let exists = S_both.Set.exists
	  let filter = S_both.Set.filter
	  let for_all = S_both.Set.for_all
	  let partition = S_both.Set.partition
	  let compare = S_both.Set.compare
	  let equal = S_both.Set.equal
	  let subset = S_both.Set.subset
	  let iter = S_both.Set.iter
	  let fold = S_both.Set.fold
	  let fold_inv = S_both.Set.fold_inv
	  let elements = S_both.Set.elements
	  let choose = S_both.Set.choose
	  let min_elt = S_both.Set.min_elt
	  let max_elt = S_both.Set.max_elt
	end:Set_with_logs with type elt = S_both.elt and type t = S_both.Set.t)
	
      module Map=
	(struct
	  type elt=S_both.elt 
	  type set=S_both.Set.t 
	  type +'data t = 'data S_both.Map.t
	 
	  let empty = S_both.Map.empty
	  let is_empty = S_both.Map.is_empty
	  let min_elt = S_both.Map.min_elt 
	  let find_option a b c d = lift S_both.Map.find_option_with_logs a b c d 
	  let find_default a b c d = lift S_both.Map.find_default_with_logs a b c d 
	  let find_option_without_logs a b c d = b,S_both.Map.find_option c d  
	  let find_default_without_logs a b c d e = b,S_both.Map.find_default c d e
	  let add a b c d = lift S_both.Map.add_with_logs a b c d
	  let remove a b c d = lift S_both.Map.remove_with_logs a b c d
	  let update a b c = lift S_both.Map.update_with_logs a b c 
	  let map2 a b c = lift S_both.Map.map2_with_logs a b c 
	  let map2z a b c = lift S_both.Map.map2z_with_logs a b c 
	  let fold2z a b c = lift S_both.Map.fold2z_with_logs a b c 
	  let fold2 a b c = lift S_both.Map.fold2_with_logs a b c 
	  let fold2_sparse a b c = lift S_both.Map.fold2_sparse_with_logs a b c
	  let iter2_sparse a b c = lift S_both.Map.iter2_sparse_with_logs a b c 
	  let diff a b c = lift S_both.Map.diff_with_logs a b c 
	  let diff_pred a b c = lift S_both.Map.diff_pred_with_logs a b c 
	  let merge a b c = lift S_both.Map.merge_with_logs a b c 
	  let union a b c = lift S_both.Map.union_with_logs a b c 
	  let fold_restriction a b c = lift S_both.Map.fold_restriction_with_logs a b c 
	  let iter = S_both.Map.iter 
	  let fold = S_both.Map.fold
	  let mapi = S_both.Map.mapi
	  let map = S_both.Map.map
	  let for_all = S_both.Map.for_all
	  let compare = S_both.Map.compare
	  let equal = S_both.Map.equal
	  let bindings = S_both.Map.bindings 		
	end:Map_with_logs with type elt = S_both.elt and type 'a t = 'a S_both.Map.t and type set = S_both.Set.t and type set = Set.t)	 
    end)
							    
