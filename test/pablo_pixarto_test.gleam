import gleam/http/request
import gleam/httpc
import gleeunit
import pablo_pixarto

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn decode_posts_test() {
  let assert Ok([post_one, post_two]) =
    "{\"feed\":[{\"post\":{\"uri\":\"at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.post/3mbw2ah4yec2e\",\"cid\":\"bafyreiao6p737s5zx7wvjjki6lqn2u7zftnnmb3ard2fhq2zlqh6gtk4g4\",\"author\":{\"did\":\"did:plc:7dowuvs7zrqj2kwjtxxvkqlc\",\"handle\":\"pixeldailies.bsky.social\",\"displayName\":\"Pixel Dailies\",\"avatar\":\"https://cdn.bsky.app/img/avatar/plain/did:plc:7dowuvs7zrqj2kwjtxxvkqlc/bafkreiezzvcz6sw3d2a6fzyvn4kqe37ak6hnhpvchskejbzixgbhugjnca@jpeg\",\"associated\":{\"chat\":{\"allowIncoming\":\"all\"},\"activitySubscription\":{\"allowSubscriptions\":\"followers\"}},\"labels\":[],\"createdAt\":\"2023-07-15T03:34:39.602Z\"},\"record\":{\"$type\":\"app.bsky.feed.post\",\"createdAt\":\"2026-01-08T13:04:33.566Z\",\"facets\":[{\"features\":[{\"$type\":\"app.bsky.richtext.facet#tag\",\"tag\":\"dice\"}],\"index\":{\"byteEnd\":22,\"byteStart\":17}},{\"features\":[{\"$type\":\"app.bsky.richtext.facet#tag\",\"tag\":\"pixel_dailies\"}],\"index\":{\"byteEnd\":38,\"byteStart\":24}}],\"langs\":[\"en\"],\"text\":\"Today's theme is #dice. #pixel_dailies\"},\"bookmarkCount\":0,\"replyCount\":0,\"repostCount\":2,\"likeCount\":34,\"quoteCount\":0,\"indexedAt\":\"2026-01-08T13:04:36.130Z\",\"labels\":[]}},{\"post\":{\"uri\":\"at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.post/3mbtf552je22u\",\"cid\":\"bafyreidg5if5hdoz3skaifduvod5a4nlohk3ktcb3ez2tepfbu2qzszdza\",\"author\":{\"did\":\"did:plc:7dowuvs7zrqj2kwjtxxvkqlc\",\"handle\":\"pixeldailies.bsky.social\",\"displayName\":\"Pixel Dailies\",\"avatar\":\"https://cdn.bsky.app/img/avatar/plain/did:plc:7dowuvs7zrqj2kwjtxxvkqlc/bafkreiezzvcz6sw3d2a6fzyvn4kqe37ak6hnhpvchskejbzixgbhugjnca@jpeg\",\"associated\":{\"chat\":{\"allowIncoming\":\"all\"},\"activitySubscription\":{\"allowSubscriptions\":\"followers\"}},\"labels\":[],\"createdAt\":\"2023-07-15T03:34:39.602Z\"},\"record\":{\"$type\":\"app.bsky.feed.post\",\"createdAt\":\"2026-01-07T11:41:34.280Z\",\"langs\":[\"en\"],\"text\":\"Hi everyone, Reports that the Pixel Dailies server has been hacked are correct. If you're still a part of the Discord server, please report the moderator account \\\"Jamie\\\" block them and leave the server.\"},\"bookmarkCount\":2,\"replyCount\":9,\"repostCount\":102,\"likeCount\":182,\"quoteCount\":2,\"indexedAt\":\"2026-01-07T11:41:36.128Z\",\"labels\":[]},\"reason\":{\"$type\":\"app.bsky.feed.defs#reasonRepost\",\"by\":{\"did\":\"did:plc:7dowuvs7zrqj2kwjtxxvkqlc\",\"handle\":\"pixeldailies.bsky.social\",\"displayName\":\"Pixel Dailies\",\"avatar\":\"https://cdn.bsky.app/img/avatar/plain/did:plc:7dowuvs7zrqj2kwjtxxvkqlc/bafkreiezzvcz6sw3d2a6fzyvn4kqe37ak6hnhpvchskejbzixgbhugjnca@jpeg\",\"associated\":{\"chat\":{\"allowIncoming\":\"all\"},\"activitySubscription\":{\"allowSubscriptions\":\"followers\"}},\"labels\":[],\"createdAt\":\"2023-07-15T03:34:39.602Z\"},\"uri\":\"at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.repost/3mbw24vy2ih2d\",\"cid\":\"bafyreigqxuzvbamrkb4pqfj7flsl6xrjah6ldytkbzfbzhjocqrrxav77y\",\"indexedAt\":\"2026-01-08T13:02:35.035Z\"}}],\"cursor\":\"2026-01-08T13:02:32.687Z\"}"
    |> pablo_pixarto.parse_bluesky_posts

  assert post_one.text == "Today's theme is #dice. #pixel_dailies"
  assert post_two.text
    == "Hi everyone, Reports that the Pixel Dailies server has been hacked are correct. If you're still a part of the Discord server, please report the moderator account \"Jamie\" block them and leave the server."
}

pub fn retrieve_bluesky_feed_test() {
  let actor = "isaacary.com"
  let limit = 1

  let assert Ok(feed) =
    pablo_pixarto.latest_bsky_posts(actor, limit)
    |> echo
}
