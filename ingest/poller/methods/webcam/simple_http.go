package webcam

import (
	"context"
	"fmt"
	"log"
	"time"

	"voria2ingest/config"
	"voria2ingest/poller/methods"
)

const (
	defaultVerifyRetries = 2
	verifyRetryDelay     = 1 * time.Second
	verifyRequestTimeout = 30 * time.Second
)

type SimpleHTTPWebcam struct {
	methods.BaseHTTPPoller
	URL           string
	VerifyImage   bool
	VerifyRetries int
}

func (p *SimpleHTTPWebcam) Name() string {
	return "simple-http"
}

func (p *SimpleHTTPWebcam) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings("simple-http", settings)
}

func (p *SimpleHTTPWebcam) InitFromSettings(settings map[string]interface{}) error {
	url, ok := settings["url"]
	if !ok {
		return fmt.Errorf("url is required in methodSettings")
	}
	p.URL = url.(string)

	if value, ok := settings["verify_image"]; ok {
		boolValue, ok := value.(bool)
		if !ok {
			return fmt.Errorf("verify_image must be a boolean")
		}
		p.VerifyImage = boolValue
	}

	p.VerifyRetries = defaultVerifyRetries
	if value, ok := settings["verify_retries"]; ok {
		intValue, err := parseVerifyRetries(value)
		if err != nil {
			return err
		}
		p.VerifyRetries = intValue
	}

	return nil
}

func (p *SimpleHTTPWebcam) Poll(ctx context.Context) (interface{}, error) {
	p.Init(verifyRequestTimeout)

	if !p.VerifyImage {
		return p.fetchOnce(ctx)
	}

	return p.fetchWithVerification(ctx)
}

func (p *SimpleHTTPWebcam) fetchOnce(ctx context.Context) (*WebcamResponse, error) {
	imageData, err := p.DoRequest(ctx, p.URL, nil)
	if err != nil {
		return nil, err
	}

	return &WebcamResponse{
		ImageURL:  p.URL,
		ImageData: imageData,
	}, nil
}

func (p *SimpleHTTPWebcam) fetchWithVerification(ctx context.Context) (*WebcamResponse, error) {
	maxAttempts := p.VerifyRetries + 1
	var lastVerifyErr error

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		imageData, err := p.DoRequest(ctx, p.URL, nil)
		if err != nil {
			if attempt < maxAttempts {
				log.Printf("simple-http: fetch error on attempt %d/%d, retrying: %v", attempt, maxAttempts, err)
				if !sleepOrCancel(ctx, verifyRetryDelay) {
					return nil, ctx.Err()
				}
				continue
			}
			return nil, err
		}

		if verifyErr := VerifyJPEG(imageData); verifyErr == nil {
			return &WebcamResponse{
				ImageURL:  p.URL,
				ImageData: imageData,
			}, nil
		} else {
			lastVerifyErr = verifyErr
			if attempt < maxAttempts {
				log.Printf("simple-http: image verification failed on attempt %d/%d, retrying: %v", attempt, maxAttempts, verifyErr)
				if !sleepOrCancel(ctx, verifyRetryDelay) {
					return nil, ctx.Err()
				}
				continue
			}
		}
	}

	return nil, fmt.Errorf("%w: image verification failed after %d attempts: %v", methods.ErrSkipCycle, maxAttempts, lastVerifyErr)
}

func (p *SimpleHTTPWebcam) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(p.Name(), rawData)
}

func parseVerifyRetries(value interface{}) (int, error) {
	switch typed := value.(type) {
	case int:
		return typed, nil
	case int64:
		return int(typed), nil
	case float64:
		if typed != float64(int(typed)) {
			return 0, fmt.Errorf("verify_retries must be a whole number")
		}
		return int(typed), nil
	default:
		return 0, fmt.Errorf("verify_retries must be a whole number")
	}
}

func sleepOrCancel(ctx context.Context, d time.Duration) bool {
	timer := time.NewTimer(d)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
