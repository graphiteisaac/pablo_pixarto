import argv
import disco
import disco/api
import disco/client
import disco/gateway
import disco/rest
import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/order
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import gleam_community/ansi
import logging
import simplifile

const bluesky_api_base = "public.api.bsky.app"

const bluesky_actor = "pixeldailies.bsky.social"

const check_interval_ms = 60_000

type AppState {
  AppState(
    last_updated: Timestamp,
    posted_uris: Set(String),
    channel_id: String,
  )
}

pub fn main() -> Nil {
  logging.configure()

  case argv.load().arguments {
    ["bot"] -> bot()
    ["list"] -> list_posts()
    _ -> io.println("Usage:\n\tgleam run <bot|list>")
  }
}

fn list_posts() -> Nil {
  case latest_bsky_posts(bluesky_actor, 50) {
    Ok(posts) -> {
      list.each(posts, fn(post) {
        io.print(
          "\n- "
          <> case post.is_repost {
            True -> ansi.blue("REPOST")
            False -> ansi.green("POST  ")
          }
          <> " "
          <> ansi.gray(post.uri)
          <> "\n\t"
          <> post.text
          <> "\n- "
          <> ansi.gray(timestamp.to_rfc3339(
            post.created_at,
            calendar.local_offset(),
          ))
          <> "\n\n",
        )
      })
      Nil
    }
    Error(err) -> {
      echo err
      Nil
    }
  }
}

fn bot() -> Nil {
  let assert Ok(token) = envoy.get("BOT_TOKEN")
    as "no BOT_TOKEN variable provided"
  let assert Ok(channel_id) = envoy.get("CHANNEL_ID")
    as "not CHANNEL_ID variable provided"

  // Load the cached values fro last updated and the list of posted URIs
  let #(uris, last_updated) = load_cache()

  let client =
    disco.new(token)
    |> disco.with_intents([
      client.GuildsIntent,
    ])

  process.trap_exits(True)

  let initial_state = AppState(last_updated, uris, channel_id)

  let bot = disco.supervised(client:, on_event:, initial_state:)
  let scheduler = schedule_child(client, initial_state)

  let _ =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(supervision.supervisor(fn() { bot }))
    |> supervisor.add(supervision.supervisor(fn() { scheduler }))
    |> supervisor.start

  process.sleep_forever()
}

fn on_event(
  state: #(gateway.GatewayState, AppState),
  msg: gateway.GatewayEvent,
) {
  case msg {
    gateway.Ready(session_id:, ..) -> {
      logging.log(logging.Info, "Bot connected and ready!")
      logging.log(logging.Info, "Session ID: " <> session_id)

      actor.continue(state)
    }
    _ -> actor.continue(state)
  }
}

// 
// # Scheduled checking logic
//

type ScheduleMsg {
  ScheduleTick
}

fn schedule_child(
  client: client.Client,
  state: AppState,
) -> Result(actor.Started(process.Subject(ScheduleMsg)), actor.StartError) {
  actor.new(state)
  |> actor.on_message(fn(state, msg) {
    case msg {
      ScheduleTick -> {
        logging.log(logging.Info, "[bluesky] checking for new posts")
        let new_state = check_and_post(client, state)
        let self = process.new_subject()
        process.send_after(self, check_interval_ms, ScheduleTick)
        actor.continue(new_state)
      }
    }
  })
  |> actor.start
}

//
// # Bluesky 
// 

pub type BlueskyPost {
  BlueskyPost(
    uri: String,
    text: String,
    created_at: Timestamp,
    author_handle: String,
    is_repost: Bool,
  )
}

fn bluesky_post_decoder() -> decode.Decoder(BlueskyPost) {
  use uri <- decode.subfield(
    ["post", "uri"],
    decode.map(decode.string, atproto_uri_to_bsky_web),
  )
  use text <- decode.subfield(["post", "record", "text"], decode.string)
  use created_at <- decode.subfield(
    ["post", "record", "createdAt"],
    decode.then(decode.string, fn(str) {
      case timestamp.parse_rfc3339(str) {
        Ok(ts) -> decode.success(ts)
        Error(_) ->
          decode.failure(
            timestamp.from_unix_seconds(0),
            "could not parse RFD3339 timestamp",
          )
      }
    }),
  )
  use author_handle <- decode.subfield(
    ["post", "author", "handle"],
    decode.string,
  )

  use is_repost <- decode.optional_field("reason", False, {
    use type_ <- decode.field("$type", decode.string)
    decode.success(type_ == "app.bsky.feed.defs#reasonRepost")
  })

  decode.success(BlueskyPost(
    uri:,
    text:,
    created_at:,
    author_handle:,
    is_repost:,
  ))
}

//
// # Posting logic
// 

fn post_to_discord(client: client.Client, state: AppState, post: BlueskyPost) {
  case
    rest.send_message(
      client,
      state.channel_id,
      api.MessageContent(text: post.uri, embeds: []),
    )
  {
    Ok(msg) -> {
      logging.log(logging.Info, "[discord] created message ID #" <> msg.id)

      case rest.crosspost_message(client, msg) {
        Ok(_) ->
          logging.log(logging.Info, "[discord] successfully announced message")
        Error(err) ->
          logging.log(
            logging.Error,
            "[discord] could not announce message: " <> string.inspect(err),
          )
      }
    }
    Error(err) ->
      logging.log(
        logging.Error,
        "[discord] could not post message: " <> string.inspect(err),
      )
  }
}

fn check_and_post(client: client.Client, state: AppState) -> AppState {
  case latest_bsky_posts(bluesky_actor, 50) {
    Ok(posts) -> {
      // Only make posts that have existed for at least 5 minutes
      let now = timestamp.system_time()
      let timeago = fn(minutes: Int) {
        timestamp.add(now, duration.minutes(minutes * -1))
      }

      let matched =
        list.filter(posts, fn(post) {
          // Contains a theme and the required tag
          has_theme_and_tag(post.text)
          // Hasn't already been posted
          && !set.contains(state.posted_uris, post.uri)
          // Older than 1 minute
          && timestamp.compare(post.created_at, timeago(1)) == order.Lt
          // Newer than a few minutes ago
          && timestamp.compare(post.created_at, timeago(3)) == order.Gt
          // Not a repost
          && !post.is_repost
        })

      case matched {
        // No posts match this time
        [] -> state

        [matching, ..] -> {
          logging.log(
            logging.Info,
            "Found a matching post: " <> matching.text <> " at " <> matching.uri,
          )

          post_to_discord(client, state, matching)

          case write_cache(matching) {
            Ok(_) ->
              logging.log(
                logging.Info,
                "[io] saved uri and latest timestamp for post",
              )
            Error(err) ->
              logging.log(
                logging.Error,
                "[io] failed to save new uri: " <> string.inspect(err),
              )
          }

          AppState(
            ..state,
            last_updated: matching.created_at,
            posted_uris: set.insert(state.posted_uris, matching.uri),
          )
        }
      }
    }
    Error(err) -> {
      logging.log(
        logging.Error,
        "failed to retrieve bluesky posts: " <> string.inspect(err),
      )

      state
    }
  }
}

fn has_theme_and_tag(post_content: String) -> Bool {
  let lowercase = string.lowercase(post_content)

  {
    string.contains(lowercase, "task is") || string.contains(lowercase, "theme")
  }
  && string.contains(lowercase, "#")
}

pub fn latest_bsky_posts(
  actor: String,
  limit: Int,
) -> Result(List(BlueskyPost), String) {
  let req =
    request.new()
    |> request.set_scheme(http.Https)
    |> request.set_host(bluesky_api_base)
    |> request.set_path("/xrpc/app.bsky.feed.getAuthorFeed")
    |> request.set_query([#("actor", actor), #("limit", int.to_string(limit))])
    |> request.set_header("connection", "keep-alive")
    |> request.set_header("user-agent", "pablo_pixarto/bot@2.0.0")

  case httpc.send(req) {
    Ok(response.Response(status:, body:, ..)) if status == 200 ->
      parse_bluesky_posts(body)

    Ok(response.Response(status:, body:, ..)) ->
      Error(
        "[bsky] req failed (code " <> int.to_string(status) <> "): " <> body,
      )
    Error(e) -> Error("[bsky] req failed: " <> string.inspect(e))
  }
}

@internal
pub fn parse_bluesky_posts(body: String) -> Result(List(BlueskyPost), String) {
  json.parse(body, using: {
    use posts <- decode.field("feed", decode.list(bluesky_post_decoder()))
    decode.success(posts)
  })
  |> result.replace_error("Failed to parse JSON response")
}

// Turn an atproto URI into a Bluesky web URL
// eg      "at://did:plc:abc/app.bsky.feed.post/abcdefg"
// becomes "https://bsky.app/profile/{handle}/post/abc123"
fn atproto_uri_to_bsky_web(atproto_uri: String) -> String {
  case string.split(atproto_uri, "/") {
    ["at:", "", _did, "app.bsky.feed.post", post_id] ->
      "https://bsky.app/profile/" <> bluesky_actor <> "/post/" <> post_id

    _ -> atproto_uri
  }
}

const cache_file = "db.json"

pub fn load_cache() -> #(Set(String), Timestamp) {
  case simplifile.read(cache_file) {
    Ok(content) -> {
      let decoder = {
        use posts <- decode.field("posts", decode.list(decode.string))
        use last_updated <- decode.field(
          "lastUpdate",
          decode.map(decode.int, timestamp.from_unix_seconds),
        )

        decode.success(#(set.from_list(posts), last_updated))
      }

      let assert Ok(data) = json.parse(content, decoder)

      data
    }
    Error(_) -> {
      logging.log(
        logging.Info,
        "[cache] no existing cache file, creating " <> cache_file,
      )
      let _ = simplifile.write(cache_file, "{\"lastUpdate\": 0,\n\"posts\":[]}")

      #(set.new(), timestamp.from_unix_seconds(0))
    }
  }
}

pub fn write_cache(post: BlueskyPost) -> Result(Nil, simplifile.FileError) {
  let #(posts, _) = load_cache()
  let posts = set.insert(posts, post.uri)

  let updated =
    json.object([
      #(
        "lastUpdate",
        json.int(float.round(timestamp.to_unix_seconds(post.created_at))),
      ),
      #("posts", json.array(set.to_list(posts), json.string)),
    ])
    |> json.to_string

  simplifile.write(cache_file, updated)
}
