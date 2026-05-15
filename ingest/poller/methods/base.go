package methods

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"
)

type BaseHTTPPoller struct {
	client *http.Client
}

func (b *BaseHTTPPoller) Init(timeout time.Duration) {
	b.client = &http.Client{
		Timeout: timeout,
	}
}

func (b *BaseHTTPPoller) DoRequest(ctx context.Context, url string, headers map[string]string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	for key, value := range headers {
		req.Header.Set(key, value)
	}

	resp, err := b.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	return data, nil
}
