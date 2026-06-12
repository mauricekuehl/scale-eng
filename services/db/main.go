package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
)

var (
	mu      sync.RWMutex
	urls    = map[string]string{}
	urlCode = map[string]string{}
)

func main() {
	http.HandleFunc("/", handle)
	addr := os.Getenv("HTTP_ADDR")
	if addr == "" {
		log.Fatal("HTTP_ADDR is required")
	}
	log.Fatal(http.ListenAndServe(addr, nil))
}

func handle(w http.ResponseWriter, r *http.Request) {
	code := strings.TrimPrefix(r.URL.Path, "/")
	if code == "" {
		http.NotFound(w, r)
		return
	}

	if r.Method == http.MethodGet {
		mu.RLock()
		originalURL, ok := urls[code]
		mu.RUnlock()
		if !ok {
			http.NotFound(w, r)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"url": originalURL})
		return
	}

	if r.Method == http.MethodPut {
		defer r.Body.Close()
		var body struct {
			URL string `json:"url"`
		}
		if json.NewDecoder(r.Body).Decode(&body) != nil || strings.TrimSpace(body.URL) == "" {
			http.Error(w, "invalid JSON", http.StatusBadRequest)
			return
		}

		mu.Lock()
		defer mu.Unlock()
		if existingCode, exists := urlCode[body.URL]; exists {
			json.NewEncoder(w).Encode(map[string]string{"code": existingCode})
			return
		}
		if _, exists := urls[code]; exists {
			http.Error(w, "exists", http.StatusConflict)
			return
		}
		urls[code] = body.URL
		urlCode[body.URL] = code
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"code": code})
		return
	}

	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
}
