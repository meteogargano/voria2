package weather

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"voria2ingest/config"
	"voria2ingest/poller/methods"
)

type ClientrawWeather struct {
	methods.BaseHTTPPoller
	URL string
}

func (v *ClientrawWeather) Name() string {
	return "clientraw"
}

func (v *ClientrawWeather) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings("clientraw", settings)
}

func (v *ClientrawWeather) InitFromSettings(settings map[string]interface{}) error {
	url, ok := settings["url"]
	if !ok {
		return fmt.Errorf("url is required in methodSettings")
	}
	v.URL = url.(string)
	return nil
}

func (v *ClientrawWeather) Poll(ctx context.Context) (interface{}, error) {
	v.Init(30 * time.Second)

	data, err := v.DoRequest(ctx, v.URL, nil)
	if err != nil {
		return nil, err
	}

	fields := strings.Split(string(data), " ")
	if len(fields) <= 140 {
		return nil, fmt.Errorf("invalid response format: expected at least 141 fields, got %d", len(fields))
	}

	temperature, err := strconv.ParseFloat(strings.TrimSpace(fields[4]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse temperature: %w", err)
	}

	humidity, err := strconv.ParseFloat(strings.TrimSpace(fields[5]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse humidity: %w", err)
	}

	pressure, err := strconv.ParseFloat(strings.TrimSpace(fields[6]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse pressure: %w", err)
	}

	windAvgKnots, err := strconv.ParseFloat(strings.TrimSpace(fields[1]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind avg: %w", err)
	}

	windGustKnots, err := strconv.ParseFloat(strings.TrimSpace(fields[140]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind gust: %w", err)
	}

	windDirection, err := strconv.ParseFloat(strings.TrimSpace(fields[3]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind direction: %w", err)
	}

	rain, err := strconv.ParseFloat(strings.TrimSpace(fields[9]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse rain: %w", err)
	}

	windSpeedMs := windAvgKnots * 0.51444444
	windGustMs := windGustKnots * 0.51444444

	response := WeatherStationResponse{
		TemperatureCelsius: temperature,
		HumidityPercent:    humidity,
		PressureHPa:        pressure,
		WindSpeedKmh:       windSpeedMs * 3.6,
		WindSpeedMs:        windSpeedMs,
		WindDirectionDeg:   windDirection,
		WindGustMs:         windGustMs,
		RainCumulativeMM:   rain,
	}

	return response, nil
}

func (v *ClientrawWeather) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(rawData)
}
