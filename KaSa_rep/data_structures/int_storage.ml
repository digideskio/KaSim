(**
   * int_storage.ml
   *
   * Creation:                      <2010-07-27 feret>
   * Last modification: Time-stamp: <Jul 02 2016>
   *
   * openkappa
   * Jérôme Feret, projet Abstraction, INRIA Paris-Rocquencourt
   *
   *
   * This library provides primitives to deal with storage functions
   *
   * Copyright 2010,2011,2012,2013,2014,2015 Institut National
   * de Recherche en Informatique et en Automatique.
   * All rights reserved.  This file is distributed
   * under the terms of the GNU Library General Public License *)

type ('a,'b) unary = Remanent_parameters_sig.parameters -> Exception.method_handler -> 'a -> Exception.method_handler * 'b
type ('a,'b,'c) binary = Remanent_parameters_sig.parameters -> Exception.method_handler -> 'a -> 'b -> Exception.method_handler * 'c
type ('a,'b,'c,'d) ternary = Remanent_parameters_sig.parameters -> Exception.method_handler -> 'a -> 'b -> 'c -> Exception.method_handler * 'd
type ('a,'b,'c,'d,'e) quaternary = Remanent_parameters_sig.parameters -> Exception.method_handler -> 'a -> 'b -> 'c -> 'd -> Exception.method_handler * 'e

type 'a unary_no_output = Remanent_parameters_sig.parameters -> Exception.method_handler -> 'a -> Exception.method_handler
type ('a,'b) binary_no_output = Remanent_parameters_sig.parameters -> Exception.method_handler -> 'a -> 'b -> Exception.method_handler

module type Storage =
sig
  type 'a t
  type key
  type dimension

  val create: (dimension,'a t) unary
  val create_biggest_key: (key, 'a t) unary
  val expand_and_copy: ('a t,dimension,'a t) binary
  val init: (dimension, (key, 'a) unary, 'a t) binary
  val set: (key,'a,'a t,'a t) ternary
  val get: (key,'a t,'a option) binary
  val unsafe_get: (key,'a t,'a option) binary
  val dimension: ('a t, dimension) unary
  val print: ('a unary_no_output,'a t) binary_no_output
  val key_list: ('a t, key list) unary
  val iter:((key,'a) binary_no_output, 'a t) binary_no_output
  val fold_with_interruption: ((key,'a,'b,'b) ternary,'a t,'b,'b) ternary
  val fold: ((key,'a,'b,'b) ternary,'a t,'b,'b) ternary
  val fold2_common: ((key,'a,'b,'c,'c) quaternary,'a t,'b t, 'c, 'c) quaternary

end

let invalid_arg parameters mh message exn value  =
  Exception.warn parameters mh (Some "Int_storage") message exn (fun () -> value )

module Int_storage_imperatif =
  (struct
    type key = int
    type dimension = int
    type 'a t =
      {
        array:('a option) array ;
        size:int ;
      }

    let dimension _ error a = error, a.size

    let key_list _paremeters error t =
      let size = t.size in
      let array = t.array in
      let rec aux k sol =
        if k<0 then error,sol
        else
          match array.(k) with
          | None -> aux (k-1) sol
          | Some _ -> aux (k-1) (k::sol)
      in aux size []

    let rec create parameters error size  =
      if size < 0
      then
        let error,array = create parameters error 0 in
        invalid_arg parameters error (Some "create, line 60") Exit array
      else
        error,
        {
          array = Array.make (size+1) None;
          size = size;
        }

    let create_biggest_key parameters error x = create parameters error x

    let expand_and_copy parameters error array size =
      let error,dimension = dimension parameters error array in
      if dimension < size
      then
        let error,array' = create parameters error size in
        let _ = Array.blit array.array 0 array'.array 0 dimension in
        error,array'
      else
        error,{array = Array.sub array.array 0 size ; size = size}

    let set parameters error key value array =
      if key>array.size || key<0
      then
        invalid_arg parameters error (Some "set, line 81") Exit array
      else
        let _ = array.array.(key)<-Some value in
        error,array

    let rec init parameters error size f =
      if size < 0
      then
        let error,array = init parameters error 0 f in
        invalid_arg parameters error (Some "create, line 60") Exit array
      else
        let error, array = create parameters error size in
        let rec aux k error array =
          if k>size then error,array
          else
            let error, value = f parameters error k in
            let error, array = set parameters error k value array in
            aux (k+1) error array
        in
        aux 0 error array

    let get parameters error key array =
      if key>array.size || key<0 then
        invalid_arg parameters error (Some "get, line 88") Exit None
      else
        match array.array.(key) with
        | None -> invalid_arg parameters error (Some "get, line 92") Exit None
        | a -> error,a

    let unsafe_get _parameters error key array =
      if key>array.size || key<0 then
        error,None
      else
        error,array.array.(key)

    let print parameters error print_elt array =
      let rec aux i error =
        if i>array.size then error
        else
          let error =
            match array.array.(i) with
            | None -> error
            | Some elt ->
              let () =
                Loggers.fprintf (Remanent_parameters.get_logger parameters)
                  "%s%d:" (Remanent_parameters.get_prefix parameters) i in
              let () =
                Loggers.print_newline (Remanent_parameters.get_logger parameters)
              in
              let parameters = Remanent_parameters.update_prefix parameters
                  ((string_of_int i)^":") in
              let error = print_elt parameters error elt in
              error
          in aux (i+1) error
      in aux 0 error

    let iter parameter error f t =
      let size = t.size in
      let array = t.array in
      let rec aux k error =
        if k>size then error
        else
          match array.(k) with
          | None ->
            aux (k+1) error
          | Some x ->
            aux (k+1) (f parameter error k x)
      in
      aux 0 error

    let fold parameter error f t init =
      let size = t.size in
      let array = t.array in
      let rec aux k remanent =
        if k>size then remanent
        else
          match array.(k) with
          | None ->
            aux (k+1) remanent
          | Some x ->
            let error,sol  = remanent in
            aux (k+1) (f parameter error k x  sol)
      in
      aux 0  (error,init)

    let fold_with_interruption parameter error f t init =
      let size = t.size in
      let array = t.array in
      let rec aux k remanent =
        if k>size then remanent
        else
          match array.(k) with
          | None ->
            aux (k+1) remanent
          | Some x ->
            let error,sol  = remanent in
            let output_opt =
              try
                Some (f parameter error k x sol)
              with
                Sys.Break -> None
            in
            match
              output_opt
            with
            | None -> remanent
            | Some a -> aux (k+1) a
      in
      aux 0  (error,init)

    let fold2_common  parameter error f t1 t2 init =
      let size = min t1.size t2.size in
      let array1 = t1.array in
      let array2 = t2.array in
      let rec aux k remanent =
        if k>size then remanent
        else
          match array1.(k),array2.(k) with
          | None,_ | _,None -> aux (k+1) remanent
          | Some x1,Some x2 ->
            let error,sol = remanent in
            aux (k+1) (f parameter error k x1 x2 sol)
      in
      aux 0  (error,init)

  end:Storage with type key = int and type dimension = int)

module Nearly_infinite_arrays =
  functor (Basic:Storage with type dimension = int and type key = int) ->
    (struct
      type dimension = Basic.dimension
      type key = Basic.key
      type 'a t = 'a Basic.t

      let create = Basic.create
      let create_biggest_key = Basic.create_biggest_key
      let dimension = Basic.dimension
      let key_list = Basic.key_list

      let expand parameters error array =
        let error,old_dimension = dimension parameters error array in
        if old_dimension = Sys.max_array_length
        then
          invalid_arg parameters error (Some "expand, line 170") Exit array
        else
          Basic.expand_and_copy parameters error array
            (max 1 (min Sys.max_array_length (2*old_dimension)))

      let get = Basic.get
      let unsafe_get = Basic.unsafe_get
      let expand_and_copy = Basic.expand_and_copy
      let init = Basic.init

      let rec set parameters error key value array =
        let error,dimension = dimension parameters error array in
        if key>=dimension
        then
          let error,array' = expand parameters error array in
          if array == array'
          then
            invalid_arg parameters error (Some "set, line 185") Exit array
          else
            set parameters error key value array'
        else
          Basic.set parameters error key value array

      let print = Basic.print
      (*      let print_var_f = Basic.print_var_f
              let print_site_f = Basic.print_site_f*)
      let iter = Basic.iter
      let fold = Basic.fold
      let fold_with_interruption = Basic.fold_with_interruption
      let fold2_common = Basic.fold2_common

    end:Storage with type key = int and type dimension = int)

module Extend =
  functor (Extension:Storage) ->
  functor (Underlying:Storage) ->
    (struct

      type dimension = Extension.dimension * Underlying.dimension

      type key = Extension.key * Underlying.key

      type 'a t =
        {
          matrix : 'a Underlying.t Extension.t ;
          dimension : dimension;
        }

      let create parameters error dimension =
        let error,matrix = Extension.create parameters error (fst dimension) in
        error,
        {
          matrix = matrix;
          dimension = dimension ;
        }

      let create_biggest_key parameters error key =
        let error,matrix = Extension.create_biggest_key parameters error (fst key) in
        let error,matrix' = Underlying.create_biggest_key parameters error (snd key) in
        let error,dimension = Extension.dimension parameters error matrix in
        let error,dimension' = Underlying.dimension parameters error matrix' in
        error,
        {matrix = matrix;
         dimension = (dimension,dimension')}

      let key_list parameters error t =
        let error,ext_list = Extension.key_list parameters error t.matrix in
        List.fold_left
          (fun (error,list) key ->
             let error,t2 = Extension.get parameters error key t.matrix in
             match t2 with
             | None -> invalid_arg parameters error (Some "key_list, line 184") Exit list
             | Some t2 ->
               let error,l2 = Underlying.key_list parameters error t2 in
               error,
               List.fold_left
                 (fun list key2  -> (key,key2)::list)
                 list
                 (List.rev l2))
          (error,[])
          (List.rev ext_list)

      let expand_and_copy parameters error array _dimension =
        invalid_arg parameters error (Some "expand_and_copy, line 196") Exit array

      let init parameters error dim  f =
        let error, array =
          Extension.init parameters error (fst dim)
            (fun p e i ->
               Underlying.init p e (snd dim) (fun p' e' j -> f p' e' (i,j)))
        in
        error,
        {
          matrix = array;
          dimension = dim
        }

      let set parameters error (i,j) value array =
        let error,old_underlying = Extension.unsafe_get parameters error i array.matrix in
        let error,old_underlying =
          match old_underlying with
          | Some old_underlying -> error,old_underlying
          | None -> Underlying.create parameters error (snd array.dimension)
        in
        let error,new_underlying = Underlying.set parameters error j value old_underlying in
        let error,new_matrix = Extension.set parameters error i new_underlying array.matrix in
        (* let ordered = ordered && Extension.ordered new_matrix in*)
        error,{array with matrix = new_matrix}

      let get parameters error (i,j) array =
        let error,underlying = Extension.get parameters error i array.matrix in
        match underlying with
        | Some underlying -> Underlying.get parameters error j underlying
        | None ->  invalid_arg parameters error (Some "get, line 298") Exit None

      let unsafe_get parameters error (i,j) array =
        let error,underlying = Extension.unsafe_get parameters error i array.matrix in
        match underlying with
        | Some underlying -> Underlying.unsafe_get parameters error j underlying
        | _ -> error,None

      let dimension _ error a = error,a.dimension


      let print parameters error print_of a =
        Extension.print
          parameters
          error
          (fun p error -> Underlying.print p error print_of)
          a.matrix

      (*    let print_var_f error print_of parameters a =
            Extension.print error
              (fun error -> Underlying.print error print_of)
              parameters
              a.matrix

            let print_site_f error print_of parameters a =
            Extension.print error
              (fun error -> Underlying.print error print_of)
              parameters
              a.matrix*)

      let iter parameter error f a =
        Extension.iter
          parameter
          error
          (fun parameter error k a ->
             Underlying.iter
               parameter
               error
               (fun parameter error k' a' -> f parameter error (k,k') a')
               a
          )
          a.matrix

      let fold_gen fold1 fold2  parameter error f a b =
        fold1
          parameter
          error
          (fun parameter error k a b ->
             fold2
               parameter
               error
               (fun parameter error k' a' b -> f parameter error (k,k') a' b)
               a
               b
          )
          a.matrix
          b

      let fold parameter error f a b = fold_gen Extension.fold Underlying.fold parameter error f a b
      let fold_with_interruption parameter error f a b = fold_gen Extension.fold_with_interruption Underlying.fold_with_interruption parameter error f a b

      let fold2_common parameter error f a b c =
        fold
          parameter
          error
          (fun parameter error k a c ->
             let error,get = unsafe_get parameter error k b in
             match get with
             | None -> (error,c)
             | Some b -> f parameter error k a b c)
          a
          c


    end:Storage with type key = Extension.key * Underlying.key and type dimension = Extension.dimension * Underlying.dimension )


module Quick_key_list =
  functor (Basic:Storage) ->
    (struct
      type dimension = Basic.dimension
      type key = Basic.key
      type 'a t =
        {
          basic: 'a Basic.t ;
          keys: key list
        }

      let create parameters error i =
        let error,basic = Basic.create parameters error i in
        error,{basic = basic ; keys = []}

      let create_biggest_key parameters error key =
        let error,basic = Basic.create_biggest_key parameters error key in
        error,{basic = basic ; keys = []}

      let key_list _parameters error t = error,t.keys

      let expand_and_copy parameters error array j =
        let error, basic = Basic.expand_and_copy parameters error array.basic j in
        error,{basic = basic ; keys = array.keys}

      let init parameters error n f =
        let error, basic = Basic.init parameters error n f in
        let error, keys =
          Basic.fold parameters error
            (fun _ e k _ list -> e,k::list)
            basic []
        in
        error, {basic = basic; keys = keys}

      let set parameters error key value array =
        let error,old = Basic.unsafe_get parameters error key array.basic in
        let new_array =
          match old with
          | Some _ -> array
          | None -> {array with keys = key::array.keys}
        in
        let error,new_basic = Basic.set parameters error key value new_array.basic in
        error, {new_array with basic = new_basic}

      let get parameters error key array =
        Basic.get parameters error key array.basic

      let unsafe_get parameters error key array =
        Basic.unsafe_get parameters error key array.basic

      let dimension parameters error a = Basic.dimension parameters error a.basic

      let print error f parameters a = Basic.print error f parameters a.basic

      (*  let print_var_f error f parameters a =
          Basic.print_var_f error f parameters a.basic

          let print_site_f error f parameters a =
          Basic.print_site_f error f parameters a.basic*)

      let iter parameters error f a =
        let error,list = key_list parameters error a in
        List.fold_left
          (fun error k ->
             let error,im = get parameters error k a in
             match im with
             | None ->
               let error,_ = invalid_arg parameters error (Some "fold, line 391")
                   Exit () in error
             | Some im -> f parameters error k im)
          error (List.rev list)

      let fold parameters error f a b =
        let error,list = key_list parameters error a in
        List.fold_left
          (fun (error,b) k ->
             let error,im = get parameters error k a in
             match im with
             | None -> invalid_arg parameters error (Some "fold, line 391") Exit b
             | Some im -> f parameters error k im b)
          (error,b)
          (List.rev list)

      let fold_with_interruption parameters error f a b =
        let error,list = key_list parameters error a in
        let rec aux list output =
          match
            list
          with
          | [] -> output
          | head::tail ->
            let output_opt =
              try
                let error,im = get parameters error head a in
                let b = snd output in
                match im with
                | None ->
                  Some (invalid_arg parameters error (Some "fold, line 391") Exit b)
                | Some im -> Some (f parameters error head im b)
              with Sys.Break -> None
            in
            match
              output_opt
            with
            | None -> output
            | Some output -> aux tail output
        in aux list (error,b)

      let fold2_common parameter error f a b c =
        fold
          parameter
          error
          (fun parameter error k a c ->
             let error,get = unsafe_get parameter error k b in
             match get with
             | None -> (error,c)
             | Some b -> f parameter error k a b c)
          a
          c

    end:Storage with type key = Basic.key and type dimension = Basic.dimension)

module Nearly_inf_Imperatif = Nearly_infinite_arrays (Int_storage_imperatif)

module Quick_Nearly_inf_Imperatif = Quick_key_list (Nearly_inf_Imperatif)

module Int_Int_storage_Imperatif_Imperatif =
  Extend (Int_storage_imperatif)(Int_storage_imperatif)

module Nearly_Inf_Int_Int_storage_Imperatif_Imperatif =
  Extend (Quick_Nearly_inf_Imperatif)(Quick_Nearly_inf_Imperatif)

module Nearly_Inf_Int_Int_Int_storage_Imperatif_Imperatif_Imperatif =
  Extend (Quick_Nearly_inf_Imperatif)
    (Extend (Quick_Nearly_inf_Imperatif)(Quick_Nearly_inf_Imperatif))
