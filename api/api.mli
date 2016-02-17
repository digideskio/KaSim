type runtime = < parse : ApiTypes_j.code -> ApiTypes_j.error Lwt.t;
                 start : ApiTypes_j.parameter -> ApiTypes_j.token ApiTypes_j.result Lwt.t;
                 status : ApiTypes_j.token -> ApiTypes_j.state ApiTypes_j.result Lwt.t;
                 list : unit -> ApiTypes_j.catalog ApiTypes_j.result Lwt.t;
                 stop : ApiTypes_j.token -> unit ApiTypes_j.result Lwt.t
               >;;
module Base : sig

  class runtime : (unit -> unit Lwt.t) -> object
                    method parse : ApiTypes_j.code -> ApiTypes_j.error Lwt.t
                    method start : ApiTypes_j.parameter -> ApiTypes_j.token ApiTypes_j.result Lwt.t
                    method status : ApiTypes_j.token -> ApiTypes_j.state ApiTypes_j.result Lwt.t
                    method list : unit -> ApiTypes_j.catalog ApiTypes_j.result Lwt.t
                    method stop : ApiTypes_j.token -> unit ApiTypes_j.result Lwt.t
                  end;;
end;;