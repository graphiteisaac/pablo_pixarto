import dotenv_gleam
import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/hackney
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import grom
import grom/activity
import grom/gateway
import grom/gateway/intent
import grom/message
import logging
import simplifile

const bluesky_api_base = "https://public.api.bsky.app"

const bluesky_actor = "pixeldailies.bsky.social"

const check_interval_ms = 60_000

pub fn main() -> Nil {
  logging.configure()

  // We can safely void this result and not care if it's an error
  // because we are using dotenv in development, but not production.
  let _ = dotenv_gleam.config()

  let assert Ok(token) = envoy.get("BOT_TOKEN")
  let assert Ok(channel_id) = envoy.get("CHANNEL_ID")

  // Load the cached values fro last updated and the list of posted URIs
  let #(uris, last_updated) = load_cache()

  let client = grom.Client(token:)
  let identify =
    client
    |> gateway.identify(intents: [intent.Guilds, intent.GuildMessages])

  let state = AppState(client, last_updated, uris, channel_id)
  let gateway_start_result =
    gateway.new(identify, state)
    |> gateway.on_event(handle_event)
    |> gateway.start()

  case gateway_start_result {
    Ok(_) -> {
      logging.log(logging.Info, "Started the gateway!")

      process.spawn(fn() { schedule_check(state) })
      process.sleep_forever()
    }
    Error(err) -> {
      logging.log(
        logging.Error,
        "Couldn't start the gateway: " <> string.inspect(err),
      )
    }
  }

  Nil
}

fn handle_event(
  state: AppState,
  event: gateway.Event,
  connection: gateway.Connection(AppState),
) {
  case event {
    gateway.ErrorEvent(error) -> {
      logging.log(logging.Error, "[discord] " <> string.inspect(error))
      gateway.continue(state)
    }
    gateway.ReadyEvent(_) -> on_ready(state, connection)
    _ -> gateway.continue(state)
  }
}

fn on_ready(state: AppState, connection: gateway.Connection(AppState)) {
  logging.log(logging.Info, "Ready!")

  connection
  |> gateway.update_presence(using: gateway.UpdatePresenceMessage(
    status: gateway.Online,
    since: option.None,
    activities: [
      activity.new(named: "🖌️ Checking for themes...", type_: activity.Custom),
    ],
    is_afk: False,
  ))

  gateway.continue(state)
}

fn schedule_check(state: AppState) -> Nil {
  // Check for new posts first
  let new_state = check_and_post(state)

  // Sleep for the interval
  process.sleep(check_interval_ms)

  // Schedule next check
  schedule_check(new_state)
}

pub type BlueskyPost {
  BlueskyPost(
    uri: String,
    text: String,
    created_at: Timestamp,
    author_handle: String,
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

  decode.success(BlueskyPost(uri, text:, created_at:, author_handle:))
}

type AppState {
  AppState(
    client: grom.Client,
    last_updated: Timestamp,
    posted_uris: Set(String),
    channel_id: String,
  )
}

fn post_to_discord(state: AppState, post: BlueskyPost) {
  let content =
    message.Create(..message.new_create(), content: option.Some(post.uri))

  case message.create(state.client, state.channel_id, content) {
    Ok(msg) -> {
      case message.crosspost(state.client, state.channel_id, msg.id) {
        Ok(_) ->
          logging.log(logging.Info, "[discord] published (announced) message")
        Error(err) ->
          logging.log(
            logging.Error,
            "[discord] failed to announce message: " <> string.inspect(err),
          )
      }
      logging.log(logging.Info, "[discord] message sent")
    }
    Error(err) ->
      logging.log(
        logging.Error,
        "[discord] failed to send message: " <> string.inspect(err),
      )
  }
}

fn check_and_post(state: AppState) -> AppState {
  case latest_bsky_posts(bluesky_actor, 50) {
    Ok(posts) -> {
      // Only make posts that have existed for at least 5 minutes
      let now = timestamp.system_time()
      let timeago = fn(minutes: Int) {
        timestamp.add(now, duration.minutes(minutes * -1))
      }

      let matched =
        list.filter(posts, fn(post) {
          has_theme_and_tag(post.text)
          && !set.contains(state.posted_uris, post.uri)
          // Older than 1 minute
          && timestamp.compare(post.created_at, timeago(1)) == order.Lt
          // Newer than a few minutes ago
          && timestamp.compare(post.created_at, timeago(3)) == order.Gt
        })

      case matched {
        // No posts match this time
        [] -> state

        [matching, ..] -> {
          logging.log(
            logging.Info,
            "Found a matching post: " <> matching.text <> " at " <> matching.uri,
          )

          post_to_discord(state, matching)

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

  string.contains(lowercase, "theme") && string.contains(lowercase, "#")
}

pub fn latest_bsky_posts(
  actor: String,
  limit: Int,
) -> Result(List(BlueskyPost), String) {
  let url =
    bluesky_api_base
    <> "/xrpc/app.bsky.feed.getAuthorFeed?actor="
    <> actor
    <> "&limit="
    <> int.to_string(limit)

  let assert Ok(req) = request.to(url)

  let req =
    req
    |> request.set_header("connection", "keep-alive")
    |> request.set_header("user-agent", "pablo_pixarto/bot1.0.0")

  case hackney.send(req) {
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
