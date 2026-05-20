package webcam

import "testing"

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
