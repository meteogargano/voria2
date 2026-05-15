package voriaapi

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"
)

type Client struct {
	baseURL string
	http    *http.Client
}

type HTTPError struct {
	StatusCode int
	Body       string
}

func (e *HTTPError) Error() string {
	return fmt.Sprintf("HTTP %d: %s", e.StatusCode, e.Body)
}

type BulkResult struct {
	OK      bool         `json:"ok"`
	Count   int          `json:"count"`
	Results []ItemResult `json:"results"`
}

type ItemResult struct {
	Index int    `json:"index"`
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

type WebcamUploadResult struct {
	OK        bool   `json:"ok"`
	ShotID    string `json:"shot_id"`
	S3Key     string `json:"s3_key"`
	Duplicate bool   `json:"duplicate,omitempty"`
}

func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		http:    &http.Client{Timeout: 30 * time.Second},
	}
}

func isPermanent(err error) bool {
	var he *HTTPError
	if errors.As(err, &he) {
		return he.StatusCode >= 400 && he.StatusCode < 500
	}
	return false
}

func (c *Client) VerifyKey(apiKey string) (string, error) {
	req, err := http.NewRequest("POST", c.baseURL+"/api/v1/ingest/verify", nil)
	if err != nil {
		return "", fmt.Errorf("create verify request: %w", err)
	}
	req.Header.Set("X-Api-Key", apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return "", &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}

	var result struct {
		OK          bool   `json:"ok"`
		StationName string `json:"station_name"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("decode verify response: %w", err)
	}
	return result.StationName, nil
}

func (c *Client) VerifyWebcamKey(apiKey string) (string, error) {
	req, err := http.NewRequest("POST", c.baseURL+"/api/v1/webcam/ingest/verify", nil)
	if err != nil {
		return "", fmt.Errorf("create verify request: %w", err)
	}
	req.Header.Set("X-Api-Key", apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return "", &HTTPError{StatusCode: resp.StatusCode, Body: string(body)}
	}

	var result struct {
		OK         bool   `json:"ok"`
		WebcamName string `json:"webcam_name"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("decode verify response: %w", err)
	}
	return result.WebcamName, nil
}

func (c *Client) BulkPost(apiKey string, batch []map[string]any) (BulkResult, error) {
	body, err := json.Marshal(batch)
	if err != nil {
		return BulkResult{}, fmt.Errorf("marshal batch: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL+"/api/v1/ingest/bulk",
		bytes.NewReader(body))
	if err != nil {
		return BulkResult{}, fmt.Errorf("create bulk request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Api-Key", apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return BulkResult{}, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode >= 400 {
		return BulkResult{}, &HTTPError{StatusCode: resp.StatusCode, Body: string(respBody)}
	}

	var result BulkResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return BulkResult{}, fmt.Errorf("decode bulk response: %w", err)
	}
	return result, nil
}

func (c *Client) UploadWebcamImage(apiKey string, imageData []byte) (WebcamUploadResult, error) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("image", "image.jpg")
	if err != nil {
		return WebcamUploadResult{}, fmt.Errorf("create form file: %w", err)
	}

	_, err = part.Write(imageData)
	if err != nil {
		return WebcamUploadResult{}, fmt.Errorf("write image data: %w", err)
	}

	err = writer.Close()
	if err != nil {
		return WebcamUploadResult{}, fmt.Errorf("close multipart writer: %w", err)
	}

	req, err := http.NewRequest("POST", c.baseURL+"/api/v1/webcam/ingest", body)
	if err != nil {
		return WebcamUploadResult{}, fmt.Errorf("create upload request: %w", err)
	}

	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("X-Api-Key", apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return WebcamUploadResult{}, err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode >= 400 {
		return WebcamUploadResult{}, &HTTPError{StatusCode: resp.StatusCode, Body: string(respBody)}
	}

	var result WebcamUploadResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return WebcamUploadResult{}, fmt.Errorf("decode upload response: %w", err)
	}

	return result, nil
}
