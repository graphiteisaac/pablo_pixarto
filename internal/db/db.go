// Package db contains our database, stored in a simple
// JSON file. There's no need for anything more complex.
package db

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type PostsDB struct {
	LastUpdated int64    `json:"lastUpdated"`
	Posts       []string `json:"posts"`
}

// LoadDB loads the database JSON from the location
// on disk
func LoadDB(path string) (*PostsDB, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}

	var output PostsDB
	if err := json.NewDecoder(file).Decode(&output); err != nil {
		return nil, err
	}

	return &output, nil
}

// SaveDatabase atomically writes the data struct to
// disk as JSON. We atomically write here by creating
// a tmp file that is moved across when complete.
func SaveDatabase(path string, data *PostsDB) error {
	dir := filepath.Dir(path)

	tmpFile, err := os.CreateTemp(dir, "db-*.tmp")
	if err != nil {
		return fmt.Errorf("failed to create tmp file: %w", err)
	}
	tmpName := tmpFile.Name()

	defer func() {
		tmpFile.Close()
		os.Remove(tmpName) // Ignored if already renamed successfully
	}()

	if err := json.NewEncoder(tmpFile).Encode(data); err != nil {
		return fmt.Errorf("failed to encode json: %w", err)
	}

	if err := tmpFile.Sync(); err != nil {
		return fmt.Errorf("failed to sync file: %w", err)
	}

	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("failed to close tmp file: %w", err)
	}

	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("failed to replace db file: %w", err)
	}

	return nil
}
