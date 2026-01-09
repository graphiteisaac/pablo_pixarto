import gleam/dynamic/decode
import gleam/hackney
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import grom
import logging
import simplifile

const bluesky_api_base = "https://public.api.bsky.app"

const uris_file = "posted.txt"

const bluesky_actor = "pixeldailies.bsky.app"

const check_interval_ms = 60_000

pub fn main() -> Nil {
  let actor = "isaacary.com"
  let limit = 1

  let assert Ok(feed) =
    latest_bsky_posts(actor, limit)
    |> echo

  Nil
}

pub type BlueskyPost {
  BlueskyPost(
    uri: String,
    text: String,
    created_at: String,
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
    decode.string,
  )
  use author_handle <- decode.subfield(
    ["post", "author", "handle"],
    decode.string,
  )

  decode.success(BlueskyPost(uri, text:, created_at:, author_handle:))
}

type AppState {
  AppState(client: grom.Client, posted_uris: Set(String))
}

fn check_and_post(state: AppState) -> AppState {
  case latest_bsky_posts(bluesky_actor, 50) {
    Ok(posts) -> {
      let matched =
        list.filter(posts, fn(post) {
          has_theme_and_tag(post.text)
          && !set.contains(state.posted_uris, post.uri)
        })

      case matched {
        // No posts match this time
        [] -> state

        [matching, ..] -> {
          logging.log(
            logging.Info,
            "Found a matching post: " <> matching.text <> " at " <> matching.uri,
          )

          // TODO: Make this real
          // post_to_discord(state.client, matching)

          AppState(
            ..state,
            posted_uris: set.insert(state.posted_uris, matching.uri),
          )
        }
      }

      state
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

pub fn load_posted_uris() -> Set(String) {
  case simplifile.read(uris_file) {
    Ok(content) ->
      content
      |> string.split("\n")
      |> list.map(string.trim)
      |> list.filter(string.is_empty)
      |> set.from_list()
    Error(_) -> {
      logging.log(
        logging.Info,
        "No existing uris text file ("
          <> uris_file
          <> "), starting a fresh list!",
      )
      set.new()
    }
  }
}

pub fn save_new_uri(post_uri: String) -> Result(Nil, simplifile.FileError) {
  let line = post_uri <> "\n"

  simplifile.append(uris_file, line)
}
