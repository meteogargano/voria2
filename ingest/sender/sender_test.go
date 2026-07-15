package sender

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	client "voria2ingest/client"
	"voria2ingest/types"
)

func newTestSender(t *testing.T, server *httptest.Server, retries int) *HTTPSender {
	t.Helper()
	return &HTTPSender{
		destinationClient: client.NewClient(server.URL),
		retries:           retries,
	}
}

func sendWebcamPayload(s *HTTPSender, ctx context.Context) error {
	return s.Send(ctx, "dest-key", "webcam", &types.WebcamData{
		ID:        "test",
		ImageData: []byte("fake-image-bytes"),
	})
}

func TestSenderRetriesOnServerError(t *testing.T) {
	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(`{"error":"server error"}`))
	}))
	defer server.Close()

	s := newTestSender(t, server, 3)
	err := sendWebcamPayload(s, context.Background())
	if err == nil {
		t.Fatal("expected error after retries on 500")
	}
	if got := atomic.LoadInt32(&calls); got != 3 {
		t.Fatalf("expected 3 attempts on 5xx, got %d", got)
	}
}

func TestSenderDoesNotRetryOnPermanentClientError(t *testing.T) {
	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		w.WriteHeader(http.StatusUnprocessableEntity)
		w.Write([]byte(`{"error":"image exceeds maximum allowed size","ok":false}`))
	}))
	defer server.Close()

	s := newTestSender(t, server, 3)
	err := sendWebcamPayload(s, context.Background())
	if err == nil {
		t.Fatal("expected error on 422")
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected exactly 1 attempt on 4xx (no retry), got %d", got)
	}
}

func TestSenderReturnsImmediatelyOnSuccess(t *testing.T) {
	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		w.WriteHeader(http.StatusCreated)
		w.Write([]byte(`{"ok":true,"shot_id":"abc","s3_key":"key"}`))
	}))
	defer server.Close()

	s := newTestSender(t, server, 3)
	if err := sendWebcamPayload(s, context.Background()); err != nil {
		t.Fatalf("expected success, got: %v", err)
	}
	if got := atomic.LoadInt32(&calls); got != 1 {
		t.Fatalf("expected exactly 1 attempt on success, got %d", got)
	}
}
