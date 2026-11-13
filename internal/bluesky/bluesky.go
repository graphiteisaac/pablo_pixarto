package bluesky

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type BlueskyPost struct {
	URI       string    `json:"uri"`
	Text      string    `json:"text"`
	CreatedAt time.Time `json:"created_at"`
	IsRepost  bool      `json:"is_repost"`
}

type BlueskyReason struct {
	Type string `json:"$type"`
}

type BlueskyResponse struct {
	Feed []struct {
		Post struct {
			URI    string `json:"uri"`
			Record struct {
				Text      string    `json:"text"`
				CreatedAt time.Time `json:"createdAt"`
			} `json:"record"`
		}
		Reason *BlueskyReason `json:"reason,omitempty"`
	} `json:"feed"`
}

func LatestPosts(actor string, limit int) ([]BlueskyPost, error) {
	url := &url.URL{
		Scheme: "https",
		Host:   "public.api.bsky.app",
		Path:   "/xrpc/app.bsky.feed.getAuthorFeed",
	}

	q := url.Query()
	q.Set("actor", actor)
	q.Set("limit", strconv.Itoa(limit))

	url.RawQuery = q.Encode()

	req, err := http.NewRequest(http.MethodGet, url.String(), nil)
	if err != nil {
		return nil, err
	}

	req.Header.Add("Connection", "keep-alive")
	req.Header.Add("User-Agent", "pablo_pixarto/bot@2.0.0")

	client := http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var raw BlueskyResponse
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, err
	}

	out := make([]BlueskyPost, len(raw.Feed))
	for i, raw := range raw.Feed {
		isRespost := false
		if raw.Reason != nil {
			isRespost = raw.Reason.Type == "app.bsky.feed.defs#reasonRepost"
		}
		out[i] = BlueskyPost{
			URI:       raw.Post.URI,
			Text:      raw.Post.Record.Text,
			CreatedAt: raw.Post.Record.CreatedAt,
			IsRepost:  isRespost,
		}
	}

	return out, nil
}

func AtURIToURL(actor string, aturi string) string {
	split := strings.Split(aturi, "/")
	return "https://bsky.app/profile/" + actor + "/post/" + split[len(split)-1]
}

func IsThemePost(post *BlueskyPost) bool {
	lower := strings.ToLower(post.Text)

	return !post.IsRepost && (strings.Contains(lower, "today's task") || strings.Contains(lower, "today's theme"))
}
