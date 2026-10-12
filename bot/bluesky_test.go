package main

import "testing"

func TestGetPosts(t *testing.T) {
	posts, err := LatestBlueskyPosts("pixeldailies.bsky.social", 10)
	if err != nil {
		t.Fatal(err)
	}

	t.Log(posts)
}
