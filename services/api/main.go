package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

var (
	baseURL string
	dbURL   string
	client  = &http.Client{Timeout: 3 * time.Second}
	chars   = []byte("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
)

func main() {
	addr := os.Getenv("HTTP_ADDR")
	baseURL = os.Getenv("BASE_URL")
	dbURL = os.Getenv("DB_URL")
	if addr == "" || baseURL == "" || dbURL == "" {
		log.Fatal("HTTP_ADDR, BASE_URL and DB_URL are required")
	}

	http.HandleFunc("/create", create)
	http.HandleFunc("/", redirect)

	log.Fatal(http.ListenAndServe(addr, nil))
}

func create(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	defer r.Body.Close()

	var body struct {
		URL string `json:"url"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	u, err := url.Parse(strings.TrimSpace(body.URL))
	if err != nil || u.Scheme == "" || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		http.Error(w, "invalid url", http.StatusBadRequest)
		return
	}

	shortCode := code()
	if err := save(shortCode, u.String()); err != nil {
		log.Println(err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{"shortUrl": strings.TrimRight(baseURL, "/") + "/" + shortCode})
}

func redirect(w http.ResponseWriter, r *http.Request) {
	code := strings.TrimPrefix(r.URL.Path, "/")
	if r.Method != http.MethodGet || len(code) != 8 {
		http.NotFound(w, r)
		return
	}

	originalURL, ok, err := load(code)
	if err != nil {
		log.Println(err)
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	if !ok {
		http.NotFound(w, r)
		return
	}

	http.Redirect(w, r, originalURL, http.StatusFound)
}

func code() string {
	b := make([]byte, 8)
	rand.Read(b)
	for i := range b {
		b[i] = chars[int(b[i])%len(chars)]
	}
	return string(b)
}

func save(code, originalURL string) error {
	body, _ := json.Marshal(map[string]string{"url": originalURL})
	req, _ := http.NewRequest(http.MethodPut, strings.TrimRight(dbURL, "/")+"/"+code, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("db returned %d", resp.StatusCode)
	}
	return nil
}

func load(code string) (string, bool, error) {
	resp, err := client.Get(strings.TrimRight(dbURL, "/") + "/" + code)
	if err != nil {
		return "", false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", false, nil
	}
	if resp.StatusCode != http.StatusOK {
		return "", false, fmt.Errorf("db returned %d", resp.StatusCode)
	}

	var body struct {
		URL string `json:"url"`
	}
	return body.URL, true, json.NewDecoder(resp.Body).Decode(&body)
}
