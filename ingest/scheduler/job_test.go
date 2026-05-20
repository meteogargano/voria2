package scheduler

import (
	"context"
	"testing"
	"time"

	"voria2ingest/poller/methods"
)

type stubPoller struct {
	pollErr error
	called  int
}

func (s *stubPoller) Name() string { return "stub" }

func (s *stubPoller) ValidateSettings(settings map[string]interface{}) error { return nil }

func (s *stubPoller) InitFromSettings(settings map[string]interface{}) error { return nil }

func (s *stubPoller) Poll(ctx context.Context) (interface{}, error) {
	s.called++
	return nil, s.pollErr
}

func (s *stubPoller) Transform(rawData interface{}) (interface{}, error) { return rawData, nil }

type stubSender struct {
	called bool
}

func (s *stubSender) Send(ctx context.Context, destinationKey string, dataType string, data interface{}) error {
	s.called = true
	return nil
}

func TestBaseJobRunSkipsCycleWithoutError(t *testing.T) {
	p := &stubPoller{pollErr: methods.ErrSkipCycle}
	s := &stubSender{}
	job := NewBaseJob("cam", p, s, time.Minute, "dest", "webcam")

	err := job.Run(context.Background())
	if err != nil {
		t.Fatalf("expected skip cycle to return nil, got %v", err)
	}
	if s.called {
		t.Fatal("sender should not be called for skipped cycles")
	}
}
