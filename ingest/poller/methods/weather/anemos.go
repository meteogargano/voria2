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

type AnemosWeather struct {
	methods.BaseHTTPPoller
	URL string
}

func (v *AnemosWeather) Name() string {
	return "anemos"
}

func (v *AnemosWeather) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings("anemos", settings)
}

func (v *AnemosWeather) InitFromSettings(settings map[string]interface{}) error {
	url, ok := settings["url"]
	if !ok {
		return fmt.Errorf("url is required in methodSettings")
	}
	v.URL = url.(string)
	return nil
}

func (v *AnemosWeather) Poll(ctx context.Context) (interface{}, error) {
	v.Init(30 * time.Second)

	data, err := v.DoRequest(ctx, v.URL, nil)
	if err != nil {
		return nil, err
	}

	fields := strings.Split(string(data), "|")
	if len(fields) <= 35 {
		return nil, fmt.Errorf("invalid response format: expected at least 35 fields, got %d", len(fields))
	}

	temperature, err := strconv.ParseFloat(strings.TrimSpace(fields[5]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse temperature: %w", err)
	}

	humidity, err := strconv.ParseFloat(strings.TrimSpace(fields[19]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse humidity: %w", err)
	}

	pressure, err := strconv.ParseFloat(strings.TrimSpace(fields[23]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse pressure: %w", err)
	}

	windAvgKmh, err := strconv.ParseFloat(strings.TrimSpace(fields[26]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind avg: %w", err)
	}

	windGustRaw := strings.TrimSpace(fields[28])
	windGustParts := strings.Split(windGustRaw, " ")
	windGustKmh, err := strconv.ParseFloat(strings.TrimSpace(windGustParts[0]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind gust: %w", err)
	}

	windDirRaw := strings.TrimSpace(fields[27])
	windDirParts := strings.Split(windDirRaw, "(")
	if len(windDirParts) < 2 {
		return nil, fmt.Errorf("invalid wind direction format: %s", windDirRaw)
	}
	windDirStr := strings.TrimSuffix(strings.TrimSpace(windDirParts[1]), ")")
	windDirection, err := strconv.ParseFloat(windDirStr, 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind direction: %w", err)
	}

	rain, err := strconv.ParseFloat(strings.TrimSpace(fields[35]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse rain: %w", err)
	}

	windSpeedMs := windAvgKmh / 3.6
	windGustMs := windGustKmh / 3.6

	response := WeatherStationResponse{
		TemperatureCelsius: temperature,
		HumidityPercent:    humidity,
		PressureHPa:        pressure,
		WindSpeedKmh:       windAvgKmh,
		WindSpeedMs:        windSpeedMs,
		WindDirectionDeg:   windDirection,
		WindGustMs:         windGustMs,
		RainCumulativeMM:   rain,
	}

	return response, nil
}

func (v *AnemosWeather) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(rawData)
}
