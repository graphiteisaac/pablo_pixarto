(***********************
 * Config
 ***********************)
let discord_token = Sys.getenv "DISCORD_BOT_TOKEN"
let discord_channel_id = Sys.getenv "DISCORD_CHANNEL_ID"
let bluesky_handle = "pixeldailies.bsky.social"
let db_file = "db.json"
let filter_tags = [ "#theme"; "#set"; "#tileset" ]

(* type post = { *)
(*   uri : string; *)
(*   text : string; *)
(*   url : string; *)
(* } *)

(***********************
 * Database types and functions
 ***********************)

type db = {
  last_update : int;
  posts : string list;
}

let db_of_yojson json =
  match json with
  | `Assoc fields ->
      let last_update =
        match List.assoc_opt "lastUpdate" fields with
        | Some (`Int i) -> i
        | _ -> 0
      in
      let posts =
        match List.assoc_opt "posts" fields with
        | Some (`List items) ->
            List.filter_map
              (function
                | `String s -> Some s
                | _ -> None)
              items
        | _ -> []
      in
      Ok { last_update; posts }
  | _ -> Error "expected JSON object"

let db_to_yojson db =
  `Assoc
    [
      ("lastUpdate", `Int db.last_update);
      ("posts", `List (List.map (fun s -> `String s) db.posts));
    ]

let load_db db_file =
  if Sys.file_exists db_file then
    let json = Yojson.Safe.from_file db_file in
    match db_of_yojson json with
    | Ok db -> db
    | Error _ -> { last_update = 0; posts = [] }
  else
    { last_update = 0; posts = [] }

let save_db db_file db = db_to_yojson db |> Yojson.Safe.to_file db_file

(***********************
 * Main entrypoint
 ***********************)
let run () =
  print_endline "Hello world";
  Lwt.return_unit
