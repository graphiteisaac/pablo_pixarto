package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"slices"
	"time"

	"forge.isaac.zone/isaac/nucord"
	"forge.isaac.zone/isaac/pablo_pixarto/bot/internal/bluesky"
	"forge.isaac.zone/isaac/pablo_pixarto/bot/internal/db"
	"forge.isaac.zone/isaac/pablo_pixarto/bot/internal/ticker"
)

var (
	token     = flag.String("token", "", "Bot authentication token")
	appID     = flag.String("app", "", "Application ID")
	guildID   = flag.String("guild", "", "Guild ID")
	channelID = flag.String("channel", "", "Channel ID to post to")
	bskyAcc   = flag.String("bsky", "pixeldailies.bsky.social", "Bluesky actor name")
	dbPath    = "./db.json"
)

func main() {
	flag.Parse()
	if *appID == "" {
		log.Fatal("application id is not set")
	}

	db, err := db.LoadDB(dbPath)
	if err != nil {
		log.Fatal(err)
	}

	session, _ := nucord.New("Bot " + *token)

	session.HandleReady(func(s *nucord.Session, r *nucord.Ready) {
		log.Printf("Logged in as %s\n", r.User.String())
		log.Println("Running ticker loop...")
		go ticker.Start(func() {
			runTask(session, db)
		})
	})

	// _, err := session.ApplicationCommandBulkOverwrite(*App, *Guild, commands)
	// if err != nil {
	// 	log.Fatalf("could not register commands: %s", err)
	// }

	if err := session.Open(); err != nil {
		log.Fatalf("could not open session: %s", err)
	}

	sigch := make(chan os.Signal, 1)
	signal.Notify(sigch, os.Interrupt)
	<-sigch

	if err := session.Close(); err != nil {
		log.Printf("could not close session gracefully: %s", err)
	}
}

func runTask(session *nucord.Session, data *db.PostsDB) {
	fmt.Println("Running post loop", time.Now().Format(time.RFC822Z))
	posts, err := bluesky.LatestPosts(*bskyAcc, 40)
	if err != nil {
		fmt.Println("failed to get latest posts", err)
	}

	for _, post := range posts {
		actualURL := bluesky.AtURIToURL(*bskyAcc, post.URI)

		if bluesky.IsThemePost(&post) &&
			post.CreatedAt.After(time.Unix(data.LastUpdated, 0).Add(time.Minute*-1)) &&
			!slices.Contains(data.Posts, actualURL) {
			data.Posts = append(data.Posts, actualURL)
			data.LastUpdated = time.Now().Unix()
			msg, err := session.ChannelMessageSend(*channelID, actualURL)
			if err != nil {
				fmt.Println("Failed to post message", err)
				continue
			}

			if _, err := session.ChannelMessageCrosspost(*channelID, msg.ID); err != nil {
				fmt.Println("Failed to crosspost (announce) message", err)
				continue
			}

			fmt.Println("Posted theme message", msg.ID)
		}
	}

	if err := db.SaveDatabase("./db.json", data); err != nil {
		fmt.Println("Failed to save database", err)
	}
}
