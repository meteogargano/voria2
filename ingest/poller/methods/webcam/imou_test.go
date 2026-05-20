package webcam

import (
	"errors"
	"testing"
)

func TestImouSelectBestStreamPrefersHTTPSAndRequestedProfile(t *testing.T) {
	poller := &ImouWebcam{device: imouDeviceSettings{Profile: "HD"}}

	url, err := poller.selectBestStream([]imouStream{
		{StreamID: 1, HLS: "http://example.com/sd.m3u8"},
		{StreamID: 0, HLS: "https://example.com/hd.m3u8"},
		{StreamID: 1, HLS: "https://example.com/sd.m3u8"},
	})
	if err != nil {
		t.Fatalf("selectBestStream returned error: %v", err)
	}

	if url != "https://example.com/hd.m3u8" {
		t.Fatalf("expected HD https stream, got %q", url)
	}
}

func TestImouSelectBestStreamFallsBackToAnyHTTPS(t *testing.T) {
	poller := &ImouWebcam{device: imouDeviceSettings{Profile: "HD"}}

	url, err := poller.selectBestStream([]imouStream{
		{StreamID: 1, HLS: "https://example.com/sd.m3u8"},
		{StreamID: 0, HLS: "http://example.com/hd.m3u8"},
	})
	if err != nil {
		t.Fatalf("selectBestStream returned error: %v", err)
	}

	if url != "https://example.com/sd.m3u8" {
		t.Fatalf("expected HTTPS fallback stream, got %q", url)
	}
}

func TestImouInitFromSettingsParsesConfig(t *testing.T) {
	poller := &ImouWebcam{}

	err := poller.InitFromSettings(map[string]interface{}{
		"app_id":     "app-id",
		"app_secret": "app-secret",
		"device": map[string]interface{}{
			"device_id":  "device-1",
			"channel_id": 1,
			"profile":    "hd",
		},
		"capture": map[string]interface{}{
			"crop_bottom":  220,
			"min_image_kb": 25,
		},
	})
	if err != nil {
		t.Fatalf("InitFromSettings returned error: %v", err)
	}

	if poller.device.ChannelID != "1" {
		t.Fatalf("expected channel_id to normalize to string, got %q", poller.device.ChannelID)
	}
	if poller.device.Profile != "HD" {
		t.Fatalf("expected profile to normalize to HD, got %q", poller.device.Profile)
	}
	if poller.capture.MinImageKB != 25 {
		t.Fatalf("expected min_image_kb to be 25, got %d", poller.capture.MinImageKB)
	}
}

func TestNormalizeExistingStreams(t *testing.T) {
	streams, liveToken, err := normalizeExistingStreams([]imouExistingStream{
		{LiveToken: "live-1", StreamID: 1, HLS: "https://example.com/sd.m3u8"},
		{LiveToken: "live-1", StreamID: 0, HLS: "https://example.com/hd.m3u8"},
	})
	if err != nil {
		t.Fatalf("normalizeExistingStreams returned error: %v", err)
	}
	if liveToken != "live-1" {
		t.Fatalf("expected live token live-1, got %q", liveToken)
	}
	if len(streams) != 2 {
		t.Fatalf("expected 2 streams, got %d", len(streams))
	}
}

func TestNormalizeExistingStreamsRequiresLiveToken(t *testing.T) {
	_, _, err := normalizeExistingStreams([]imouExistingStream{{StreamID: 0, HLS: "https://example.com/hd.m3u8"}})
	if err == nil {
		t.Fatal("expected error when live token is missing")
	}
}

func TestImouErrorReturnsStructuredAPIErrorForLV1001(t *testing.T) {
	err := (&ImouWebcam{}).imouError("LV1001", "The video live exists.")

	var apiErr *imouAPIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("expected imouAPIError, got %T", err)
	}
	if apiErr.Code != "LV1001" {
		t.Fatalf("expected code LV1001, got %q", apiErr.Code)
	}
}

func TestFirstExistingLiveToken(t *testing.T) {
	liveToken := firstExistingLiveToken([]imouExistingStream{
		{LiveToken: ""},
		{LiveToken: "live-2"},
	})

	if liveToken != "live-2" {
		t.Fatalf("expected live-2, got %q", liveToken)
	}
}

func TestFirstExistingLiveTokenEmpty(t *testing.T) {
	liveToken := firstExistingLiveToken([]imouExistingStream{{}, {}})
	if liveToken != "" {
		t.Fatalf("expected empty live token, got %q", liveToken)
	}
}
