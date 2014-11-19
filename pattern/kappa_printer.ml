let lnk_t env f = function
  | Mixture.WLD -> Format.fprintf f "?"
  | Mixture.BND -> Format.fprintf f "!"
  | Mixture.FREE -> Format.fprintf f ""
  | Mixture.TYPE (site_id,sig_id) ->
     Format.fprintf f "!%s.%s" (Environment.site_of_id sig_id site_id env)
	(Environment.name sig_id env)

let follower_string (bnd,fresh) mix uid = function
  | Mixture.BND ->
     let opt = Mixture.follow uid mix in
     begin
       match opt with
       | Some (agent_id',site_id') ->
	  begin
	    let lnk =
	      try Hashtbl.find bnd uid with
	      | Not_found ->
		 (Hashtbl.replace bnd (agent_id',site_id') !fresh ;
		  let i = !fresh in
		  fresh := !fresh+1 ;
		  i)
	    in
	    Hashtbl.replace bnd uid lnk ;
	    (string_of_int lnk)
	  end
       | None ->
	  try string_of_int (Hashtbl.find bnd uid)
	  with Not_found -> "_"
     end
  | _ -> ""

let intf_item env (bnd,fresh) mix sig_id agent_id
		    f (site_id,(opt_v,opt_l)) =
  let s_int f = match opt_v with
    | (Some x) ->
       Format.fprintf f "~%s" (Environment.state_of_id sig_id site_id x env)
    | None -> Format.fprintf f ""
  in
  let s_lnk f =
    Format.fprintf f "%a%s" (lnk_t env) opt_l
       (follower_string (bnd,fresh) mix (agent_id,site_id) opt_l)
  in
  Format.fprintf f "%s%t%t" (Environment.site_of_id sig_id site_id env)
     s_int s_lnk

let intf env mix sig_id agent_id (bnd,fresh) f interface =
  Pp.set Mods.IntMap.bindings (fun f -> Format.fprintf f ",")
	 (intf_item env (bnd,fresh) mix sig_id agent_id)
	 f (Mods.IntMap.remove 0 interface)
(* Beware: removes "_" the hackish way *)

let agent with_number env mix (bnd,fresh) f (id,ag) =
  let sig_id = Mixture.name ag in
  let name = if with_number
	     then (Environment.name sig_id env)^"#"^(string_of_int id)
	     else Environment.name sig_id env
  in
  Format.fprintf f "%s(%a)" name (intf env mix sig_id id (bnd,fresh))
		 (Mixture.interface ag)

let mixture with_number env f mix =
  let bnd = Hashtbl.create 7 in
  let fresh = ref 0 in
  Pp.set Mods.IntMap.bindings (fun f -> Format.fprintf f ",")
	 (agent with_number env mix (bnd,fresh))
	 f (Mixture.agents mix)

let print_alg env f alg =
  let rec aux f = function
    | Expr.BIN_ALG_OP (op, (a,_), (b,_)) ->
       Format.fprintf f "(%a %a %a)" aux a Term.print_bin_alg_op op aux b
    | Expr.UN_ALG_OP (op, (a,_)) ->
       Format.fprintf f "(%a %a)" Term.print_un_alg_op op aux a
    | Expr.STATE_ALG_OP op -> Term.print_state_alg_op f op
    | Expr.CONST n -> Nbr.print f n
    | Expr.ALG_VAR i ->
       Format.fprintf f "'%a'" (Environment.print_alg env) i
    | Expr.KAPPA_INSTANCE i ->
       Format.fprintf f "|#secret#|"
		     (* (mixture false env) (Environment.kappa_of_num i env) *)
    | Expr.TOKEN_ID i ->
       Format.fprintf f "|%a|" (Environment.print_token env) i
  in aux f alg
