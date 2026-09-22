package httpapi

import (
	"encoding/json"
	"net/http"
)

type response struct {
	Service string `json:"service,omitempty"`
	Status  string `json:"status,omitempty"`
	Version string `json:"version,omitempty"`
}

// NewHandler returns the complete HTTP API without starting a network listener.
func NewHandler(version string) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /{$}", func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, http.StatusOK, response{
			Service: "assessment-api",
			Version: version,
		})
	})

	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, http.StatusOK, response{Status: "healthy"})
	})

	mux.HandleFunc("GET /api/version", func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, http.StatusOK, response{Version: version})
	})

	return mux
}

func writeJSON(writer http.ResponseWriter, status int, body response) {
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.WriteHeader(status)
	_ = json.NewEncoder(writer).Encode(body)
}
