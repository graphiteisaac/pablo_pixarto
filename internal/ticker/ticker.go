// Package ticker contains the periodic check-and-post
// function and timer loop.
package ticker

import (
	"time"
)

func Start(taskFn func()) {
	taskFn()

	ticker := time.NewTicker(2 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		taskFn()
	}
}
