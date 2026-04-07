type state = {
  last_seen_uri : string option;
  last_update : int;
  posts : string list;
}

type post = {
  uri : string;
  text : string;
  url : string;
}

let discord_webhook_url = Sys.getenv "DISCORD_WEBHOOK_URL"
let bluesky_handle = "pixeldailies.bsky.social"
let db_file = "db.json"
let filter_tags = [ "#theme"; "#set"; "#tileset" ]

let load_db () =
  if Sys.file_exists db_file then
    let json = Yojson.Safe.from_file db_file in
    match state_of_yojson with
    | Ok s -> s
    | Error _ -> { last_seen_uri = None; last_update = 0; posts = [] }
  else
    { last_seen_uri = None; last_update = 0; posts = [] }
