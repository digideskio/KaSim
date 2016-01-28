open Js

open Lwt
open Visualization
open Codemirror
open Storage
open Counter

module Html5 = Tyxml_js.Html5
module R = Tyxml_js.R
let document = Dom_html.window##document
let number_events_id = "number_events"
let number_events =
  Html5.input
    ~a:[Html5.a_id number_events_id ;
        Html5.a_input_type `Number; Html5.a_class ["form-control"];
        Html5.a_placeholder "Max number";
        Tyxml_js.R.Html5.a_value
          (React.S.l1 (fun x -> match x with
                                | Some va -> string_of_int va
                                | None -> "") Storage.model_max_events)]
    ()
let time_limit_id = "time_limit"
let time_limit =
  Html5.input
    ~a:[Html5.a_id time_limit_id ;
        Html5.a_input_type `Number; Html5.a_class ["form-control"];
        Html5.a_placeholder "Time limit";
        Tyxml_js.R.Html5.a_value
          (React.S.l1 (fun x -> match x with
                                | Some va -> string_of_float va
                                | None -> "") Storage.model_max_time)]
    ()
let plot_points_id = "plot_points"
let plot_points =
  Html5.input
    ~a:[Html5.a_id plot_points_id;
        Html5.a_input_type `Number; Html5.a_class ["form-control"];
        Html5.a_placeholder "Expected number";
        Tyxml_js.R.Html5.a_value
          (React.S.l1 string_of_int Storage.model_nb_plot)]
    ()
(*
let number_events_id = "number_events"
let time_limit_id = "time_limit"
let plot_points_id = "plot_points"
 *)
let signal_change id signal_handler =
    let input_dom : Dom_html.inputElement Js.t =
    Js.Unsafe.coerce
    ((Js.Opt.get (document##getElementById (Js.string id))
                (fun () -> assert false))
     : Dom_html.element Js.t) in
    input_dom##onchange <-
      Dom_html.handler
        (fun _ ->
         let () = signal_handler (Js.to_string (input_dom##value))
         in Js._false)

let error_messages signal formatter =
  Html5.div
    ~a:[Tyxml_js.R.Html5.a_class
          (React.S.bind
             signal
             (fun e -> React.S.const (match e with
                                        Some _ -> ["panel-footer";"error-footer"]
                                      | None -> ["panel-footer";"panel-pre"]
                                     ))
          )
       ]
    [Tyxml_js.R.Html5.pcdata
       (React.S.bind
          signal
          (fun error -> React.S.const (match error with
                                         Some error -> formatter error
                                       | None -> ""
                                      ))
       )
    ]

let code_messages = error_messages model_syntax_error Storage.format_error_message
let start_button_id = "start-button"
let start_button = Html5.button ~a:([ Html5.a_id start_button_id
                                    ; Html5.Unsafe.string_attrib "type" "button"
                                    ])
                                [ Html5.cdata "start" ]
let configuration_settings =
  <:html5<<div class="panel-footer panel-footer-white">
            <div class="row">
                        <div class="col-md-4">
                           $number_events$
                        </div>
                        <div class="col-md-2">
                           events
                        </div>
                     </div>

                     <div class="row">
                        <div class="col-md-4">
                           $time_limit$
                        </div>
                        <div class="col-md-2">
                           sec
                        </div>
                     </div>

                     <div class="row">
                        <div class="col-md-4">
                           $plot_points$
                        </div>
                        <div class="col-md-2">
                           points
                        </div>
                     </div>
                  </div> >>
let configuration_button =
    <:html5<<div class="panel-footer">
                    $start_button$
            </div> >>

let configuration_id = "configuration-id"
let configuration_xml =
  Html5.div
    ~a:[ Html5.a_id configuration_id
       ; Tyxml_js.R.Html5.a_class (React.S.bind
                                     model_is_running
                                     (fun is_running -> React.S.const (if is_running then
                                                                         ["hidden"]
                                                                       else
                                                                         ["visible"]
                                                                      )
                                     )
                                  )
       ]
    [code_messages; configuration_settings; configuration_button ]
  (*

   *)
let map_events (f : Storage.runtime_state option -> int option) : int React.signal
  = React.S.map
      (fun (state : Storage.runtime_state option) ->
       match f state with
       | None -> 0
       | Some va -> va)
      (model_runtime_state : (Storage.runtime_state option) React.signal)

let progress_bar signal =
  Html5.div ~a:[ Html5.a_id start_button_id
                                   ; Html5.Unsafe.string_attrib "role" "progressbar"
                                   ; Tyxml_js.R.Html5.Unsafe.int_attrib "aria-valuenow" signal
                                   ; Html5.Unsafe.int_attrib "aria-valuemin" 0
                                   ; Html5.Unsafe.int_attrib "aria-valuemax" 100
                                   ; Tyxml_js.R.Html5.Unsafe.string_attrib "style"
                                                                           (React.S.map (fun s -> Format.sprintf "width: %d;" s)
                                                                                        signal)
                                   ; Html5.a_class ["progress-bar"] ] []

let time_progress_bar = progress_bar (map_events Storage.get_time_percentage)
let event_progress_bar = progress_bar (map_events Storage.get_event_percentage)

let stop_button_id = "stop_button"
let stop_button = Html5.button ~a:[ Html5.a_id stop_button_id
                                   ; Html5.Unsafe.string_attrib "type" "button"
                                   ; Html5.a_class ["btn";"btn-default"] ] [ Html5.cdata "stop" ]

let tracked_events_count = Tyxml_js.R.Html5.pcdata
                        (React.S.bind
                           model_runtime_state
                           (fun state -> match get_tracked_events state with
                                           Some c -> React.S.const
                                                       (if c > 0 then
                                                          string_of_int c
                                                        else " ")
                                         | None -> React.S.const "")
                        )
let tracked_events_label = Tyxml_js.R.Html5.pcdata
                        (React.S.bind
                           model_runtime_state
                           (fun state -> match get_tracked_events state with
                                           Some c -> React.S.const
                                                       (if c > 0 then
                                                          "tracked events"
                                                        else " ")
                                         | None -> React.S.const "")
                        )

let simulation_messages = error_messages Storage.model_runtime_error_message (fun i -> i)
let simulation_progress =
    <:html5<<div class="panel-footer panel-footer-white">
                <div class="row">
                  <div class="col-md-4">
                    <div class="progress">
                       $event_progress_bar$
                    </div>
                  </div>
                  <div class="col-md-2">
                    events
                  </div>
                </div>

                <div class="row">
                  <div class="col-md-4">
                    <div class="progress">
                       $time_progress_bar$
                    </div>
                  </div>
                  <div class="col-md-4">
                    time
                  </div>
                </div>

                <div class="row">
                  <div class="col-md-4">
                    $tracked_events_count$
                  </div>
                  <div class="col-md-4">
                    $tracked_events_label$
                  </div>
                  <div class="col-md-1 panel-pre"> </div>
                </div>
              </div> >>

let simulation_buttons =
              <:html5<<div class="panel-footer">
                      $stop_button$
                      </div> >>
let simulation_id : string = "simulation-panel"
let simulation_xml =
  Html5.div
    ~a:[ Html5.a_id simulation_id
       ; Tyxml_js.R.Html5.a_class (React.S.bind
                                     model_is_running
                                     (fun model_is_running -> React.S.const (if model_is_running then
                                                                               ["visible"]
                                                                             else
                                                                               ["hidden"]
                                                                 ))
                                  )
       ]
    [simulation_messages; simulation_progress ; simulation_buttons ]

let xml = <:html5<<div>
                  $configuration_xml$
                  $simulation_xml$
                  </div> >>

let onload () : unit Lwt.t =
  let start_button_dom : Dom_html.linkElement Js.t =
    Js.Unsafe.coerce
      (Js.Opt.get (document##getElementById (Js.string start_button_id))
                  (fun () -> assert false)) in
  let stop_button_dom : Dom_html.linkElement Js.t =
    Js.Unsafe.coerce
      (Js.Opt.get (document##getElementById (Js.string stop_button_id))
                  (fun () -> assert false)) in
  let () = start_button_dom##onclick <-
             Dom.handler
               (fun _ ->
                let () = Storage.set_model_is_running true in
                let _ = start_button_dom##disabled <- Js._true in
                let _ = Storage.start
                          (fun stopper -> stop_button_dom##disabled <- Js._false;
                                          start_button_dom##disabled <- Js._false;
                                          stop_button_dom##onclick <-
                                            Dom.handler
                                              (fun _ ->
                                               let _ = stop_button_dom##disabled <- Js._true in
                                               let _ = Lwt.wakeup stopper ()
                                               in Js._true)
                          )
                          (fun _ -> stop_button_dom##disabled <- Js._true;
                                    start_button_dom##disabled <- Js._false)
                in Js._true)
  in
  let () = signal_change number_events_id (fun value -> Storage.set_model_max_events
                                                          (try Some (int_of_string value)
                                                           with Failure _ -> None)
                                          ) in
  let () = signal_change time_limit_id    (fun value -> Storage.set_model_max_time
                                                          (try Some (float_of_string value)
                                                           with Failure _ -> None)) in
  let () = signal_change plot_points_id   (fun value -> try Storage.set_model_nb_plot
                                                              (int_of_string value)
                                                        with Not_found
                                                           | Failure "int_of_string" -> ()) in
  Lwt.return_unit
