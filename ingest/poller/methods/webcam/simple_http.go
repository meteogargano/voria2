package webcam

import (
	"context"
	"fmt"
	"time"

	"voria2ingest/config"
	"voria2ingest/poller/methods"
)

type SimpleHTTPWebcam struct {
	methods.BaseHTTPPoller
	URL string
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

	return nil
}

func (p *SimpleHTTPWebcam) Poll(ctx context.Context) (interface{}, error) {
	p.Init(30 * time.Second)

	imageData, err := p.DoRequest(ctx, p.URL, nil)
	if err != nil {
		return nil, err
	}

	response := &WebcamResponse{
		ImageURL:  p.URL,
		ImageData: imageData,
	}

	return response, nil
}

func (p *SimpleHTTPWebcam) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(p.Name(), rawData)
}
