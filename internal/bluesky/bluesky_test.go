package bluesky

import (
	"testing"
	"time"
)

func TestGetPosts(t *testing.T) {
	posts, err := LatestPosts("pixeldailies.bsky.social", 10)
	if err != nil {
		t.Fatal(err)
	}

	if len(posts) != 10 {
		t.Fatalf("expected 10 posts returned, got %d", len(posts))
	}
}

func TestThemePosts(t *testing.T) {
	cases := map[BlueskyPost]bool{
		{
			URI:       "at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.post/1",
			Text:      "lich dont matta",
			CreatedAt: time.Now(),
			IsRepost:  true,
		}: false,
		{
			URI:       "at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.post/2",
			Text:      "im doing a #theme and a #set but i'm a repost",
			CreatedAt: time.Now(),
			IsRepost:  true,
		}: false,
		{
			URI:       "at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.post/3",
			Text:      "ToDaY's ThEmE is #rocket",
			CreatedAt: time.Now(),
			IsRepost:  false,
		}: true,
		{
			URI:       "at://did:plc:7dowuvs7zrqj2kwjtxxvkqlc/app.bsky.feed.post/4",
			Text:      "today's task",
			CreatedAt: time.Now(),
			IsRepost:  false,
		}: true,
	}

	for post, expected := range cases {
		if IsThemePost(&post) != expected {
			t.Fatalf("expected theme=%t got=%t for '%s'", expected, IsThemePost(&post), post.Text)
		}
	}
}
