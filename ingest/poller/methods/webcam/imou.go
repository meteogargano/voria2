package webcam

import (
	"bytes"
	"context"
	"crypto/md5"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"voria2ingest/config"
	"voria2ingest/poller/methods"
)

const (
	imouAPIURL        = "https://openapi.easy4ip.com/openapi"
	imouHTTPTimeout   = 30 * time.Second
	imouFFmpegTimeout = 30 * time.Second
)

type ImouWebcam struct {
	client    *http.Client
	appID     string
	appSecret string
	device    imouDeviceSettings
	capture   imouCaptureSettings
}

type imouDeviceSettings struct {
	DeviceID  string
	ChannelID string
	Profile   string
}

type imouCaptureSettings struct {
	CropBottom int
	MinImageKB int
}

type imouAPIRequest struct {
	System imouAPISystem  `json:"system"`
	Params map[string]any `json:"params"`
	ID     string         `json:"id"`
}

type imouAPISystem struct {
	Ver   string `json:"ver"`
	Sign  string `json:"sign"`
	AppID string `json:"appId"`
	Time  int64  `json:"time"`
	Nonce string `json:"nonce"`
}

type imouAPIResponse struct {
	Result imouAPIResult `json:"result"`
}

type imouAPIResult struct {
	Code string          `json:"code"`
	Msg  string          `json:"msg"`
	Data json.RawMessage `json:"data"`
}

type imouAccessTokenResponse struct {
	AccessToken string `json:"accessToken"`
	ExpireTime  int64  `json:"expireTime"`
}

type imouDeviceOnlineResponse struct {
	OnLine string `json:"onLine"`
}

type imouBindDeviceLiveResponse struct {
	LiveToken string       `json:"liveToken"`
	Streams   []imouStream `json:"streams"`
}

type imouGetLiveStreamInfoResponse struct {
	Streams []imouExistingStream `json:"streams"`
}

type imouStream struct {
	StreamID int    `json:"streamId"`
	HLS      string `json:"hls"`
}

type imouExistingStream struct {
	LiveToken string `json:"liveToken"`
	StreamID  int    `json:"streamId"`
	HLS       string `json:"hls"`
	Status    string `json:"status"`
}

type imouAPIError struct {
	Code    string
	Message string
}

func (e *imouAPIError) Error() string {
	return fmt.Sprintf("imou API error (%s: %s)", e.Code, e.Message)
}

func (p *ImouWebcam) Name() string {
	return "imou"
}

func (p *ImouWebcam) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings(p.Name(), settings)
}

func (p *ImouWebcam) InitFromSettings(settings map[string]interface{}) error {
	appID, err := requiredString(settings, "app_id")
	if err != nil {
		return err
	}
	appSecret, err := requiredString(settings, "app_secret")
	if err != nil {
		return err
	}
	deviceMap, err := requiredMap(settings, "device")
	if err != nil {
		return err
	}
	captureMap, err := requiredMap(settings, "capture")
	if err != nil {
		return err
	}

	deviceID, err := requiredString(deviceMap, "device_id")
	if err != nil {
		return err
	}
	channelID, err := requiredString(deviceMap, "channel_id")
	if err != nil {
		return err
	}
	profile, err := requiredString(deviceMap, "profile")
	if err != nil {
		return err
	}
	profile = strings.ToUpper(strings.TrimSpace(profile))
	if profile != "HD" && profile != "SD" {
		return fmt.Errorf("device.profile must be HD or SD")
	}

	cropBottom, err := requiredInt(captureMap, "crop_bottom")
	if err != nil {
		return err
	}
	if cropBottom < 0 {
		return fmt.Errorf("capture.crop_bottom must be greater than or equal to 0")
	}

	minImageKB, err := requiredInt(captureMap, "min_image_kb")
	if err != nil {
		return err
	}
	if minImageKB < 0 {
		return fmt.Errorf("capture.min_image_kb must be greater than or equal to 0")
	}

	p.client = &http.Client{Timeout: imouHTTPTimeout}
	p.appID = appID
	p.appSecret = appSecret
	p.device = imouDeviceSettings{
		DeviceID:  deviceID,
		ChannelID: channelID,
		Profile:   profile,
	}
	p.capture = imouCaptureSettings{
		CropBottom: cropBottom,
		MinImageKB: minImageKB,
	}

	return nil
}

func (p *ImouWebcam) Poll(ctx context.Context) (interface{}, error) {
	if p.client == nil {
		p.client = &http.Client{Timeout: imouHTTPTimeout}
	}

	accessToken, err := p.fetchAccessToken(ctx)
	if err != nil {
		return nil, fmt.Errorf("fetch access token: %w", err)
	}

	var status imouDeviceOnlineResponse
	accessToken, err = p.callAPI(ctx, "deviceOnline", accessToken, map[string]any{
		"deviceId": p.device.DeviceID,
	}, &status)
	if err != nil {
		return nil, fmt.Errorf("check device online status: %w", err)
	}
	if status.OnLine != "1" {
		return nil, fmt.Errorf("device %s is not online (status: %s)", p.device.DeviceID, status.OnLine)
	}

	streams, liveToken, owned, accessToken, err := p.bindOrReuseLive(ctx, accessToken)
	if err != nil {
		return nil, fmt.Errorf("bind device live: %w", err)
	}
	if liveToken == "" {
		return nil, fmt.Errorf("bind device live: missing live token")
	}

	if owned {
		defer p.unbindLive(liveToken)
	}

	streamURL, err := p.selectBestStream(streams)
	if err != nil {
		return nil, err
	}

	imageData, err := p.captureFrame(ctx, streamURL)
	if err != nil {
		return nil, err
	}

	minBytes := p.capture.MinImageKB * 1024
	if minBytes > 0 && len(imageData) < minBytes {
		return nil, fmt.Errorf("%w: captured image too small (%d bytes < %d bytes)", methods.ErrSkipCycle, len(imageData), minBytes)
	}

	return &WebcamResponse{
		ImageURL:  streamURL,
		ImageData: imageData,
	}, nil
}

func (p *ImouWebcam) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(p.Name(), rawData)
}

func (p *ImouWebcam) preferredStreamID() int {
	if p.device.Profile == "SD" {
		return 1
	}

	return 0
}

func (p *ImouWebcam) fetchAccessToken(ctx context.Context) (string, error) {
	var response imouAccessTokenResponse
	_, err := p.callAPI(ctx, "accessToken", "", map[string]any{}, &response)
	if err != nil {
		return "", err
	}
	if response.AccessToken == "" {
		return "", fmt.Errorf("accessToken response missing accessToken")
	}

	return response.AccessToken, nil
}

func (p *ImouWebcam) bindOrReuseLive(ctx context.Context, accessToken string) ([]imouStream, string, bool, string, error) {
	bindResponse, accessToken, err := p.bindLive(ctx, accessToken)
	if err == nil {
		if bindResponse.LiveToken == "" {
			return nil, "", false, accessToken, fmt.Errorf("bindDeviceLive response missing liveToken")
		}
		return bindResponse.Streams, bindResponse.LiveToken, true, accessToken, nil
	}

	var apiErr *imouAPIError
	if !errors.As(err, &apiErr) || apiErr.Code != "LV1001" {
		return nil, "", false, accessToken, err
	}

	var existing imouGetLiveStreamInfoResponse
	accessToken, err = p.callAPI(ctx, "getLiveStreamInfo", accessToken, map[string]any{
		"deviceId":  p.device.DeviceID,
		"channelId": p.device.ChannelID,
	}, &existing)
	if err != nil {
		return nil, "", false, accessToken, fmt.Errorf("recover existing live after LV1001: %w", err)
	}

	streams, liveToken, err := normalizeExistingStreams(existing.Streams)
	if err == nil {
		return streams, liveToken, false, accessToken, nil
	}

	staleLiveToken := firstExistingLiveToken(existing.Streams)
	if staleLiveToken == "" {
		return nil, "", false, accessToken, fmt.Errorf("recover existing live after LV1001: %w", err)
	}

	accessToken, retryErr := p.unbindLiveWithAccessToken(ctx, accessToken, staleLiveToken)
	if retryErr != nil {
		return nil, "", false, accessToken, fmt.Errorf("recover existing live after LV1001: %w; stale live cleanup failed: %w", err, retryErr)
	}

	bindResponse, accessToken, retryErr = p.bindLive(ctx, accessToken)
	if retryErr != nil {
		return nil, "", false, accessToken, fmt.Errorf("recover existing live after LV1001: %w; rebind after stale cleanup failed: %w", err, retryErr)
	}
	if bindResponse.LiveToken == "" {
		return nil, "", false, accessToken, fmt.Errorf("rebind after stale cleanup returned no live token")
	}

	return bindResponse.Streams, bindResponse.LiveToken, true, accessToken, nil
}

func (p *ImouWebcam) bindLive(ctx context.Context, accessToken string) (imouBindDeviceLiveResponse, string, error) {
	var bindResponse imouBindDeviceLiveResponse
	accessToken, err := p.callAPI(ctx, "bindDeviceLive", accessToken, map[string]any{
		"deviceId":  p.device.DeviceID,
		"channelId": p.device.ChannelID,
		"streamId":  p.preferredStreamID(),
	}, &bindResponse)

	return bindResponse, accessToken, err
}

func (p *ImouWebcam) callAPI(ctx context.Context, endpoint string, accessToken string, params map[string]any, out interface{}) (string, error) {
	response, err := p.postAPI(ctx, endpoint, accessToken, params)
	if err != nil {
		return accessToken, err
	}

	if response.Result.Code == "TK1002" && endpoint != "accessToken" {
		accessToken, err = p.fetchAccessToken(ctx)
		if err != nil {
			return "", err
		}

		response, err = p.postAPI(ctx, endpoint, accessToken, params)
		if err != nil {
			return accessToken, err
		}
	}

	if response.Result.Code != "0" {
		return accessToken, p.imouError(response.Result.Code, response.Result.Msg)
	}

	if out != nil && len(response.Result.Data) > 0 {
		if err := json.Unmarshal(response.Result.Data, out); err != nil {
			return accessToken, fmt.Errorf("decode %s response: %w", endpoint, err)
		}
	}

	return accessToken, nil
}

func (p *ImouWebcam) postAPI(ctx context.Context, endpoint string, accessToken string, params map[string]any) (*imouAPIResponse, error) {
	timestamp := time.Now().Unix()
	nonce, err := randomHex(16)
	if err != nil {
		return nil, fmt.Errorf("generate nonce: %w", err)
	}
	requestID, err := randomHex(8)
	if err != nil {
		return nil, fmt.Errorf("generate request id: %w", err)
	}

	payload := cloneMap(params)
	if accessToken != "" {
		payload["token"] = accessToken
	}

	signInput := fmt.Sprintf("time:%d,nonce:%s,appSecret:%s", timestamp, nonce, p.appSecret)
	sign := md5.Sum([]byte(signInput))

	requestBody := imouAPIRequest{
		System: imouAPISystem{
			Ver:   "1.0",
			Sign:  hex.EncodeToString(sign[:]),
			AppID: p.appID,
			Time:  timestamp,
			Nonce: nonce,
		},
		Params: payload,
		ID:     requestID,
	}

	body, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("marshal %s request: %w", endpoint, err)
	}

	url := imouAPIURL + "/" + endpoint
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create %s request: %w", endpoint, err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send %s request: %w", endpoint, err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read %s response: %w", endpoint, err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s returned HTTP %d: %s", endpoint, resp.StatusCode, strings.TrimSpace(string(respBody)))
	}

	var parsed imouAPIResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("decode %s response: %w", endpoint, err)
	}
	if parsed.Result.Code == "" && parsed.Result.Msg == "" {
		return nil, fmt.Errorf("invalid %s response: missing result metadata", endpoint)
	}

	return &parsed, nil
}

func (p *ImouWebcam) imouError(code string, message string) error {
	message = strings.TrimSpace(message)

	switch code {
	case "OP1008", "SN1001":
		return fmt.Errorf("invalid app_id or app_secret (%s: %s)", code, message)
	case "OP1009":
		return fmt.Errorf("not authorized (%s: %s)", code, message)
	default:
		return &imouAPIError{Code: code, Message: message}
	}
}

func (p *ImouWebcam) selectBestStream(streams []imouStream) (string, error) {
	if len(streams) == 0 {
		return "", fmt.Errorf("bindDeviceLive response missing streams")
	}

	preferredStreamID := p.preferredStreamID()

	httpsStreams := filterStreams(streams, "https://")
	httpStreams := filterStreams(streams, "http://")

	if stream := findStreamByID(httpsStreams, preferredStreamID); stream != nil {
		return stream.HLS, nil
	}
	if len(httpsStreams) > 0 {
		return httpsStreams[0].HLS, nil
	}
	if stream := findStreamByID(httpStreams, preferredStreamID); stream != nil {
		return stream.HLS, nil
	}
	if len(httpStreams) > 0 {
		return httpStreams[0].HLS, nil
	}

	return "", fmt.Errorf("bindDeviceLive response did not contain a usable HLS stream URL")
}

func (p *ImouWebcam) captureFrame(ctx context.Context, streamURL string) ([]byte, error) {
	cmdCtx, cancel := context.WithTimeout(ctx, imouFFmpegTimeout)
	defer cancel()

	args := []string{"-v", "error", "-i", streamURL}
	if p.capture.CropBottom > 0 {
		args = append(args, "-vf", fmt.Sprintf("crop=in_w:in_h-%d:0:0", p.capture.CropBottom))
	}
	args = append(args, "-vframes", "1", "-q:v", "1", "-f", "image2pipe", "pipe:1")

	cmd := exec.CommandContext(cmdCtx, "ffmpeg", args...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if errors.Is(err, exec.ErrNotFound) {
			return nil, fmt.Errorf("ffmpeg not found in PATH")
		}
		if cmdCtx.Err() == context.DeadlineExceeded {
			return nil, fmt.Errorf("ffmpeg timed out after %s", imouFFmpegTimeout)
		}

		errorOutput := strings.TrimSpace(stderr.String())
		if errorOutput == "" {
			errorOutput = err.Error()
		}
		return nil, fmt.Errorf("ffmpeg failed: %s", errorOutput)
	}

	imageData := stdout.Bytes()
	if len(imageData) < 2 || imageData[0] != 0xff || imageData[1] != 0xd8 {
		return nil, fmt.Errorf("ffmpeg output is not a valid JPEG image")
	}

	return imageData, nil
}

func (p *ImouWebcam) unbindLive(liveToken string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	accessToken, err := p.fetchAccessToken(ctx)
	if err != nil {
		log.Printf("Imou webcam: failed to refresh access token for unbindLive: %v", err)
		return
	}

	if _, err := p.unbindLiveWithAccessToken(ctx, accessToken, liveToken); err != nil {
		log.Printf("Imou webcam: failed to unbind live token %s: %v", liveToken, err)
	}
}

func (p *ImouWebcam) unbindLiveWithAccessToken(ctx context.Context, accessToken string, liveToken string) (string, error) {
	return p.callAPI(ctx, "unbindLive", accessToken, map[string]any{"liveToken": liveToken}, nil)
}

func filterStreams(streams []imouStream, prefix string) []imouStream {
	filtered := make([]imouStream, 0, len(streams))
	for _, stream := range streams {
		if strings.HasPrefix(stream.HLS, prefix) {
			filtered = append(filtered, stream)
		}
	}

	return filtered
}

func findStreamByID(streams []imouStream, streamID int) *imouStream {
	for i := range streams {
		if streams[i].StreamID == streamID {
			return &streams[i]
		}
	}

	return nil
}

func normalizeExistingStreams(streams []imouExistingStream) ([]imouStream, string, error) {
	if len(streams) == 0 {
		return nil, "", fmt.Errorf("getLiveStreamInfo returned no streams")
	}

	normalized := make([]imouStream, 0, len(streams))
	liveToken := ""
	for _, stream := range streams {
		if stream.HLS == "" {
			continue
		}
		normalized = append(normalized, imouStream{
			StreamID: stream.StreamID,
			HLS:      stream.HLS,
		})
		if liveToken == "" && stream.LiveToken != "" {
			liveToken = stream.LiveToken
		}
	}

	if len(normalized) == 0 {
		return nil, "", fmt.Errorf("getLiveStreamInfo returned no usable streams")
	}
	if liveToken == "" {
		return nil, "", fmt.Errorf("getLiveStreamInfo response missing live token")
	}

	return normalized, liveToken, nil
}

func firstExistingLiveToken(streams []imouExistingStream) string {
	for _, stream := range streams {
		if stream.LiveToken != "" {
			return stream.LiveToken
		}
	}

	return ""
}

func cloneMap(source map[string]any) map[string]any {
	cloned := make(map[string]any, len(source))
	for key, value := range source {
		cloned[key] = value
	}

	return cloned
}

func randomHex(size int) (string, error) {
	buf := make([]byte, size)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}

	return hex.EncodeToString(buf), nil
}

func requiredMap(settings map[string]interface{}, key string) (map[string]interface{}, error) {
	value, ok := settings[key].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("%s is required", key)
	}

	return value, nil
}

func requiredString(settings map[string]interface{}, key string) (string, error) {
	value, ok := settings[key]
	if !ok || value == nil {
		return "", fmt.Errorf("%s is required", key)
	}

	stringValue := strings.TrimSpace(fmt.Sprint(value))
	if stringValue == "" {
		return "", fmt.Errorf("%s is required", key)
	}

	return stringValue, nil
}

func requiredInt(settings map[string]interface{}, key string) (int, error) {
	value, ok := settings[key]
	if !ok || value == nil {
		return 0, fmt.Errorf("%s is required", key)
	}

	switch typed := value.(type) {
	case int:
		return typed, nil
	case int64:
		return int(typed), nil
	case float64:
		if math.Trunc(typed) != typed {
			return 0, fmt.Errorf("%s must be a whole number", key)
		}
		return int(typed), nil
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(typed))
		if err != nil {
			return 0, fmt.Errorf("%s must be a whole number", key)
		}
		return parsed, nil
	default:
		return 0, fmt.Errorf("%s must be a whole number", key)
	}
}
