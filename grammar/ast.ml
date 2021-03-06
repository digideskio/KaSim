open Operator

type ('a,'annot) link =
  | LNK_VALUE of int * 'annot
  | FREE
  | LNK_ANY
  | LNK_SOME
  | LNK_TYPE of 'a (* port *)
    * 'a (*agent_type*)

type internal = string Location.annot list

type port = {port_nme:string Location.annot;
	     port_int:internal;
	     port_lnk:(string Location.annot,unit) link Location.annot;}

type agent = (string Location.annot * port list)

type mixture = agent list

type ('mixt,'id) ast_alg_expr =
    BIN_ALG_OP of
      bin_alg_op * ('mixt,'id) ast_alg_expr Location.annot
      * ('mixt,'id) ast_alg_expr Location.annot
  | UN_ALG_OP of un_alg_op * ('mixt,'id) ast_alg_expr Location.annot
  | STATE_ALG_OP of state_alg_op
  | OBS_VAR of 'id
  | TOKEN_ID of 'id
  | KAPPA_INSTANCE of 'mixt
  | CONST of Nbr.t

type 'a bool_expr =
  | TRUE
  | FALSE
  | BOOL_OP of
      bool_op * 'a bool_expr Location.annot * 'a bool_expr Location.annot
  | COMPARE_OP of compare_op * 'a Location.annot * 'a Location.annot

type arrow = RAR | LRAR

type rule = {
  lhs: mixture ;
  rm_token: ((mixture,string) ast_alg_expr Location.annot
	     * string Location.annot) list ;
  arrow:arrow ;
  rhs: mixture ;
  add_token: ((mixture,string) ast_alg_expr Location.annot
	      * string Location.annot) list;
  k_def: (mixture,string) ast_alg_expr Location.annot ;
  k_un:
    ((mixture,string) ast_alg_expr Location.annot *
       int Location.annot option) option;
  (*k_1:radius_opt*)
  k_op: (mixture,string) ast_alg_expr Location.annot option ;
  k_op_un:
    ((mixture,string) ast_alg_expr Location.annot *
       int Location.annot option) option;
  (*rate for backward rule*)
}

let flip_label str = str^"_op"

type 'alg_expr print_expr =
    Str_pexpr of string Location.annot
  | Alg_pexpr of 'alg_expr Location.annot

type ('mixture,'id) modif_expr =
  | INTRO of
      (('mixture,'id) ast_alg_expr Location.annot * 'mixture Location.annot)
  | DELETE of
      (('mixture,'id) ast_alg_expr Location.annot * 'mixture Location.annot)
  | UPDATE of
      ('id Location.annot *
	 ('mixture,'id) ast_alg_expr Location.annot) (*TODO: pause*)
  | UPDATE_TOK of
      ('id Location.annot *
	 ('mixture,'id) ast_alg_expr Location.annot) (*TODO: pause*)
  | STOP of ('mixture,'id) ast_alg_expr print_expr list
  | SNAPSHOT of ('mixture,'id) ast_alg_expr print_expr list
  (*maybe later of mixture too*)
  | PRINT of
      ((('mixture,'id) ast_alg_expr print_expr list) *
	 (('mixture,'id)  ast_alg_expr print_expr list))
  | PLOTENTRY
  | CFLOWLABEL of (bool * string Location.annot)
  | CFLOWMIX of (bool * 'mixture Location.annot)
  | FLUX of bool * ('mixture,'id) ast_alg_expr print_expr list
  | FLUXOFF of ('mixture,'id) ast_alg_expr print_expr list

type ('mixture,'id) perturbation =
  (('mixture,'id) ast_alg_expr bool_expr Location.annot *
     (('mixture,'id) modif_expr list) *
       ('mixture,'id) ast_alg_expr bool_expr Location.annot option) Location.annot

type configuration = string Location.annot * (string Location.annot list)

type ('mixture,'id) variable_def =
    string Location.annot * ('mixture,'id) ast_alg_expr Location.annot

type ('mixture,'id) init_t =
  | INIT_MIX of 'mixture
  | INIT_TOK of 'id

type ('mixture,'id) instruction =
  | SIG      of agent
  | TOKENSIG of string Location.annot
  | VOLSIG   of string * float * string (* type, volume, parameter*)
  | INIT     of
      string Location.annot option *
	('mixture,'id) ast_alg_expr Location.annot *
	  ('mixture,'id) init_t Location.annot
  (*volume, init, position *)
  | DECLARE  of ('mixture,'id) variable_def
  | OBS      of ('mixture,'id) variable_def (*for backward compatibility*)
  | PLOT     of ('mixture,'id) ast_alg_expr Location.annot
  | PERT     of ('mixture,'id) perturbation
  | CONFIG   of configuration

type ('mixture,'id) command =
  | RUN of ('mixture,'id) ast_alg_expr bool_expr
  | MODIFY of ('mixture,'id) modif_expr
  | QUIT

type ('agent,'mixture,'id,'rule) compil =
    {
      variables :
	('mixture,'id) variable_def list;
      (*pattern declaration for reusing as variable in perturbations or kinetic rate*)
      signatures :
	'agent list; (*agent signature declaration*)
      rules :
	(string Location.annot option * 'rule Location.annot) list;
      (*rules (possibly named)*)
      observables :
	('mixture,'id) ast_alg_expr Location.annot list;
      (*list of patterns to plot*)
      init :
	(string Location.annot option *
	   ('mixture,'id) ast_alg_expr Location.annot *
	     ('mixture,'id) init_t Location.annot) list;
      (*initial graph declaration*)
      perturbations :
	('mixture,'id) perturbation list;
      configurations :
	configuration list;
      tokens :
	string Location.annot list;
      volumes :
	(string * float * string) list
    }

let no_more_site_on_right warning left right =
  List.for_all
    (fun p ->
     List.exists (fun p' -> fst p.port_nme = fst p'.port_nme) left
     || let () =
	  if warning then
	    ExceptionDefn.warning
	      ~pos:(snd p.port_nme)
	      (fun f ->
		Format.fprintf
		  f "@[Site@ '%s'@ was@ not@ mentionned in@ the@ left-hand@ side."
		  (fst p.port_nme);
		Format.fprintf
		  f "This@ agent@ and@ the@ following@ will@ be@ removed@ and@ ";
		Format.fprintf
		  f "recreated@ (probably@ causing@ side@ effects).@]")
	in false)
    right

let empty_compil =
    {
      variables      = [];
      signatures     = [];
      rules          = [];
      init           = [];
      observables    = [];
      perturbations  = [];
      configurations = [];
      tokens         = [];
      volumes        = []
    }

(*
  let reverse res = 
  let l_pat = List.rev !res.patterns
  and l_sig = List.rev !res.signatures
  and l_rul = List.rev !res.rules
  and l_ini = List.rev !res.init
  and l_obs = List.rev !res.observables
  in
  res:={patterns=l_pat ; signatures=l_sig ; rules=l_rul ; init = l_ini ; observables = l_obs}
*)

let print_link pr_port pr_type pr_annot f = function
  | FREE -> ()
  | LNK_TYPE (p, a) -> Format.fprintf f "!%a.%a" (pr_port a) p pr_type a
  | LNK_ANY -> Format.fprintf f "?"
  | LNK_SOME -> Format.fprintf f "!_"
  | LNK_VALUE (i,a) -> Format.fprintf f "!%i%a" i pr_annot a

let link_to_json port_to_json type_to_json annot_to_json = function
  | FREE -> `String "FREE"
  | LNK_TYPE (p, a) -> `List [port_to_json a p; type_to_json a]
  | LNK_ANY -> `Null
  | LNK_SOME -> `String "SOME"
  | LNK_VALUE (i,a) -> `List (`Int i :: annot_to_json a)
let link_of_json port_of_json type_of_json annot_of_json = function
  | `String "FREE" -> FREE
  | `List [p; a] -> let x = type_of_json a in LNK_TYPE (port_of_json x p, x)
  | `Null -> LNK_ANY
  | `String "SOME" -> LNK_SOME
  | `List (`Int i :: ( [] | _::_::_ as a)) -> LNK_VALUE (i,annot_of_json a)
  | x -> raise (Yojson.Basic.Util.Type_error ("Uncorrect link",x))

let print_ast_link =
  print_link
    (fun _ f (x,_) -> Format.pp_print_string f x)
    (fun f (x,_) -> Format.pp_print_string f x)
    (fun _ () -> ())
let print_ast_internal f l =
  Pp.list Pp.empty (fun f (x,_) -> Format.fprintf f "~%s" x) f l

let print_ast_port f p =
  Format.fprintf f "%s%a%a" (fst p.port_nme)
		 print_ast_internal p.port_int
		 print_ast_link (fst p.port_lnk)

let print_ast_agent f ((ag_na,_),l) =
  Format.fprintf f "%s(%a)" ag_na
		 (Pp.list (fun f -> Format.fprintf f ",") print_ast_port) l

let print_ast_mix f m = Pp.list Pp.comma print_ast_agent f m

let rec print_ast_alg pr_mix pr_tok pr_var f = function
  | CONST n -> Nbr.print f n
  | OBS_VAR lab -> Format.fprintf f "'%a'" pr_var lab
  | KAPPA_INSTANCE ast ->
     Format.fprintf f "|%a|" pr_mix ast
  | TOKEN_ID tk -> Format.fprintf f "|%a|" pr_tok tk
  | STATE_ALG_OP op -> Operator.print_state_alg_op f op
  | BIN_ALG_OP (op, (a,_), (b,_)) ->
     Format.fprintf f "(%a %a %a)"
		    (print_ast_alg pr_mix pr_tok pr_var) a
		    Operator.print_bin_alg_op op
		    (print_ast_alg pr_mix pr_tok pr_var) b
  |UN_ALG_OP (op, (a,_)) ->
    Format.fprintf f "(%a %a)" Operator.print_un_alg_op op
		   (print_ast_alg pr_mix pr_tok pr_var) a

let print_tok pr_mix pr_tok pr_var f ((nb,_),(n,_)) =
  Format.fprintf f "%a:%a" (print_ast_alg pr_mix pr_tok pr_var) nb pr_tok n
let print_one_size tk f mix =
  Format.fprintf
    f "%a%t%a" print_ast_mix mix
    (fun f -> match tk with [] -> () | _::_ -> Format.pp_print_string f " | ")
    (Pp.list
       (fun f -> Format.pp_print_string f " + ")
       (print_tok print_ast_mix Format.pp_print_string Format.pp_print_string))
    tk
let print_arrow f = function
  | RAR -> Format.pp_print_string f "->"
  | LRAR -> Format.pp_print_string f "<->"
let print_raw_rate pr_mix pr_tok pr_var op f (def,_) =
  Format.fprintf
    f "%a%t" (print_ast_alg pr_mix pr_tok pr_var) def
    (fun f ->
     match op with
       None -> ()
     | Some (d,_) ->
	Format.fprintf f ", %a" (print_ast_alg pr_mix pr_tok pr_var) d)
let print_rates un op f def =
  Format.fprintf
    f "%a%t"
    (print_raw_rate print_ast_mix Format.pp_print_string Format.pp_print_string op)
    def
    (fun f ->
     match un with
       None -> ()
     | Some ((d,_),max_dist) ->
	Format.fprintf
	  f "(%a:%a)" 
	  (print_ast_alg print_ast_mix Format.pp_print_string Format.pp_print_string) d
	  (Pp.option (fun f (md,_) -> Format.pp_print_int f md)) max_dist)
let print_ast_rule f r =
  Format.fprintf
    f "@[<h>%a %a %a @@ %a@]"
    (print_one_size r.rm_token) r.lhs
    print_arrow r.arrow
    (print_one_size r.add_token) r.rhs
    (print_rates r.k_un r.k_op) r.k_def
let print_ast_rule_no_rate ~reverse f r =
    Format.fprintf
    f "@[<h>%a -> %a@]"
    (print_one_size r.rm_token) (if reverse then r.rhs else r.lhs)
    (print_one_size r.add_token) (if reverse then r.lhs else r.rhs)

let rec print_bool p_alg f = function
  | TRUE -> Format.fprintf f "[true]"
  | FALSE -> Format.fprintf f "[false]"
  | BOOL_OP (op,(a,_), (b,_)) ->
     Format.fprintf f "(%a %a %a)" (print_bool p_alg) a
		    Operator.print_bool_op op (print_bool p_alg) b
  | COMPARE_OP (op,(a,_), (b,_)) ->
     Format.fprintf f "(%a %a %a)"
		    p_alg a Operator.print_compare_op op p_alg b

let print_ast_bool pr_mix pr_tok pr_var =
  print_bool (print_ast_alg pr_mix pr_tok pr_var)

let merge_internals =
  List.fold_left
    (fun acc (x,_ as y) ->
      if List.exists (fun (x',_) -> String.compare x x' = 0) acc then acc else y::acc)

let merge_ports =
  List.fold_left
    (fun acc p ->
      let rec aux = function
	| [] -> [{p with port_lnk = Location.dummy_annot FREE}]
	| h :: t when fst p.port_nme = fst h.port_nme ->
	  {h with port_int = merge_internals h.port_int p.port_int}::t
	| h :: t -> h :: aux t in
      aux acc)

let merge_agents =
  List.fold_left
    (fun acc ((na,_ as x),s) ->
      let rec aux = function
	| [] -> [x,List.map
	  (fun p -> {p with port_lnk = Location.dummy_annot FREE}) s]
	| ((na',_),s') :: t when String.compare na na' = 0 ->
	  (x,merge_ports s' s)::t
	| h :: t -> h :: aux t in
      aux acc)

let merge_tokens =
  List.fold_left
  (fun acc (_,(na,_ as tok)) ->
      let rec aux = function
	| [] -> [ tok ]
	| (na',_) :: _ as l when String.compare na na' = 0 -> l
	| h :: t as l ->
	  let o = aux t in
	  if t == o then l else h::o in
      aux acc)

let sig_from_inits =
  List.fold_left
    (fun (ags,toks) -> function
    | _,_,(INIT_MIX m,_) -> (merge_agents ags m,toks)
    | _,na,(INIT_TOK t,pos) -> (ags,merge_tokens toks [na,(t,pos)]))

let sig_from_rules =
  List.fold_left
    (fun (ags,toks) (_,(r,_)) ->
      let (ags',toks') =
	match r.arrow with
	| RAR -> (ags,toks)
	| LRAR -> (merge_agents ags r.rhs, merge_tokens toks r.add_token) in
      (merge_agents ags' r.lhs, merge_tokens toks' r.rm_token))

let sig_from_perts =
  List.fold_left
    (fun acc ((_,p,_),_) ->
      List.fold_left
	(fun (ags,toks) -> function
	| INTRO (_,(m,_)) ->
	  (merge_agents ags m,toks)
	| UPDATE_TOK (t,na) ->
	  (ags,merge_tokens toks [na,t])
	| (DELETE _ | UPDATE _ | STOP _ | SNAPSHOT _ | PRINT _ | PLOTENTRY |
	    CFLOWLABEL _ | CFLOWMIX _ | FLUX _ | FLUXOFF _) -> (ags,toks))
	acc p)

let implicit_signature r =
  let acc = sig_from_inits (r.signatures,r.tokens) r.init in
  let acc' = sig_from_rules acc r.rules in
  let ags,toks = sig_from_perts acc' r.perturbations in
  { r with signatures = ags; tokens = toks }
