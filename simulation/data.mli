type flux_data = {
    flux_name : string;
    flux_start : float;
    flux_hits : int array;
    flux_fluxs : float array array;
  }
type flux_map =
  { flux_rules : string array;
    flux_data : flux_data;
    flux_end : float;
  }
type file_line = { file_name : string option ; line : string }

type snapshot = {
    snap_file : string;
    snap_event : int;
    agents : (int * Raw_mixture.t) list;
    tokens : (string * Nbr.t) array;
  }

type distances = (float * int) list option array

type unary_distances =
    { distances_data : distances;
      distances_rules : string array;
    }

type t = Flux of flux_map
       | Plot of float * Nbr.t array
       | Print of file_line
       | Snapshot of snapshot
       | Log of string
       | UnaryDistances of unary_distances
