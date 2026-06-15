package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"scale-eng/internal/observability"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

var (
	baseURL string
	dbURL   string
	client  = &http.Client{Timeout: 3 * time.Second, Transport: otelhttp.NewTransport(http.DefaultTransport)}
	chars   = []byte("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
)

func main() {
	ctx := context.Background()
	shutdown, err := observability.Init(ctx, "url-shortener-api")
	if err != nil {
		log.Fatalf("init OpenTelemetry: %v", err)
	}
	defer observability.Shutdown(ctx, shutdown)

	addr := os.Getenv("HTTP_ADDR")
	baseURL = os.Getenv("BASE_URL")
	dbURL = os.Getenv("DB_URL")
	if addr == "" || baseURL == "" || dbURL == "" {
		log.Fatal("HTTP_ADDR, BASE_URL and DB_URL are required")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/create", create)
	mux.HandleFunc("/", redirect)

	log.Fatal(http.ListenAndServe(addr, otelhttp.NewHandler(mux, "api")))
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

	shortCode, err := save(r.Context(), code(), u.String())
	if err != nil {
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

	originalURL, ok, err := load(r.Context(), code)
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

func save(ctx context.Context, code, originalURL string) (string, error) {
	body, _ := json.Marshal(map[string]string{"url": originalURL})
	req, _ := http.NewRequestWithContext(ctx, http.MethodPut, strings.TrimRight(dbURL, "/")+"/"+code, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("db returned %d", resp.StatusCode)
	}
	var bodyResp struct {
		Code string `json:"code"`
	}
	return bodyResp.Code, json.NewDecoder(resp.Body).Decode(&bodyResp)
}

func load(ctx context.Context, code string) (string, bool, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(dbURL, "/")+"/"+code, nil)
	resp, err := client.Do(req)
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
