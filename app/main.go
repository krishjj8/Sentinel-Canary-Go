package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requestCounter = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "sentinel_http_requests_total",
			Help: "Total number of HTTP requests handled by Sentinel",
		},
		[]string{"path", "version"},
	)
)

func init() {
	prometheus.MustRegister(requestCounter)
}

type VersionResponse struct {
	Version string `json:"version"`
	Status  string `json:"status"`
}

func main() {
	appVersion := os.Getenv("APP_VERSION")
	if appVersion == "" {
		appVersion = "1.0.0-v1"
	}

	http.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		requestCounter.WithLabelValues("/version", appVersion).Inc()

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(VersionResponse{
			Version: appVersion,
			Status:  "healthy",
		})
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "UP"})
	})

	http.Handle("/metrics", promhttp.Handler())

	port := ":8080"
	log.Printf("[Sentinel-Canary] Service starting on port %s (Version: %s)", port, appVersion)
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}