package webcam

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"voria2ingest/poller/methods"
)

func TestSimpleHTTPInitFromSettingsDefaults(t *testing.T) {
	p := &SimpleHTTPWebcam{}

	err := p.InitFromSettings(map[string]interface{}{
		"url": "https://example.com/cam.jpg",
	})
	if err != nil {
		t.Fatalf("InitFromSettings returned error: %v", err)
	}
	if p.URL != "https://example.com/cam.jpg" {
		t.Fatalf("expected URL set, got %q", p.URL)
	}
	if p.VerifyImage {
		t.Fatal("expected VerifyImage to default to false")
	}
	if p.VerifyRetries != defaultVerifyRetries {
		t.Fatalf("expected VerifyRetries default %d, got %d", defaultVerifyRetries, p.VerifyRetries)
	}
}

func TestSimpleHTTPInitFromSettingsParsesVerify(t *testing.T) {
	p := &SimpleHTTPWebcam{}

	err := p.InitFromSettings(map[string]interface{}{
		"url":            "https://example.com/cam.jpg",
		"verify_image":   true,
		"verify_retries": 5,
	})
	if err != nil {
		t.Fatalf("InitFromSettings returned error: %v", err)
	}
	if !p.VerifyImage {
		t.Fatal("expected VerifyImage true")
	}
	if p.VerifyRetries != 5 {
		t.Fatalf("expected VerifyRetries 5, got %d", p.VerifyRetries)
	}
}

func TestSimpleHTTPInitFromSettingsRejectsNonBoolVerifyImage(t *testing.T) {
	p := &SimpleHTTPWebcam{}

	err := p.InitFromSettings(map[string]interface{}{
		"url":          "https://example.com/cam.jpg",
		"verify_image": "yes",
	})
	if err == nil {
		t.Fatal("expected error for non-bool verify_image")
	}
}

func TestSimpleHTTPPollWithoutVerificationReturnsImage(t *testing.T) {
	validJPEG := encodeTestJPEG(t, 8, 8)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(validJPEG)
	}))
	defer server.Close()

	p := &SimpleHTTPWebcam{VerifyImage: false}
	p.InitFromSettings(map[string]interface{}{"url": server.URL})

	resp, err := p.Poll(context.Background())
	if err != nil {
		t.Fatalf("Poll returned error: %v", err)
	}

	wc, ok := resp.(*WebcamResponse)
	if !ok {
		t.Fatalf("expected *WebcamResponse, got %T", resp)
	}
	if len(wc.ImageData) == 0 {
		t.Fatal("expected non-empty image data")
	}
}

func TestSimpleHTTPPollWithVerificationRetriesUntilValid(t *testing.T) {
	validJPEG := encodeTestJPEG(t, 16, 16)
	truncatedJPEG := validJPEG[:len(validJPEG)/2]

	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt32(&calls, 1)
		if n == 1 {
			w.Write(truncatedJPEG)
			return
		}
		w.Write(validJPEG)
	}))
	defer server.Close()

	p := &SimpleHTTPWebcam{VerifyImage: true}
	p.InitFromSettings(map[string]interface{}{
		"url":            server.URL,
		"verify_image":   true,
		"verify_retries": defaultVerifyRetries,
	})

	resp, err := p.Poll(context.Background())
	if err != nil {
		t.Fatalf("expected Poll to succeed after retry, got: %v", err)
	}

	wc, ok := resp.(*WebcamResponse)
	if !ok {
		t.Fatalf("expected *WebcamResponse, got %T", resp)
	}
	if err := VerifyJPEG(wc.ImageData); err != nil {
		t.Fatalf("returned image should pass verification: %v", err)
	}
	if atomic.LoadInt32(&calls) < 2 {
		t.Fatalf("expected at least 2 fetch attempts, got %d", calls)
	}
}

func TestSimpleHTTPPollWithVerificationSkipsAfterAllAttemptsFail(t *testing.T) {
	validJPEG := encodeTestJPEG(t, 16, 16)
	truncatedJPEG := validJPEG[:len(validJPEG)/2]

	var calls int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		w.Write(truncatedJPEG)
	}))
	defer server.Close()

	p := &SimpleHTTPWebcam{VerifyImage: true}
	p.InitFromSettings(map[string]interface{}{
		"url":            server.URL,
		"verify_image":   true,
		"verify_retries": 1,
	})

	resp, err := p.Poll(context.Background())
	if err == nil {
		t.Fatalf("expected error after all retries failed, got response: %v", resp)
	}
	if !errors.Is(err, methods.ErrSkipCycle) {
		t.Fatalf("expected ErrSkipCycle, got: %v", err)
	}
	if atomic.LoadInt32(&calls) != 2 {
		t.Fatalf("expected exactly 2 attempts (1 + 1 retry), got %d", calls)
	}
}
