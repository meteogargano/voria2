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

type MeteobridgeWeather struct {
	methods.BaseHTTPPoller
	URL string
}

func (v *MeteobridgeWeather) Name() string {
	return "meteobridge"
}

func (v *MeteobridgeWeather) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings("meteobridge", settings)
}

func (v *MeteobridgeWeather) InitFromSettings(settings map[string]interface{}) error {
	url, ok := settings["url"]
	if !ok {
		return fmt.Errorf("url is required in methodSettings")
	}
	v.URL = url.(string)
	return nil
}

func (v *MeteobridgeWeather) Poll(ctx context.Context) (interface{}, error) {
	v.Init(30 * time.Second)

	data, err := v.DoRequest(ctx, v.URL, nil)
	if err != nil {
		return nil, err
	}

	fields := strings.Fields(string(data))
	if len(fields) <= 40 {
		return nil, fmt.Errorf("invalid response format: expected at least 41 fields, got %d", len(fields))
	}

	temperature, err := strconv.ParseFloat(strings.TrimSpace(fields[2]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse temperature: %w", err)
	}

	humidity, err := strconv.ParseFloat(strings.TrimSpace(fields[3]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse humidity: %w", err)
	}

	pressure, err := strconv.ParseFloat(strings.TrimSpace(fields[10]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse pressure: %w", err)
	}

	windAvgRaw, err := strconv.ParseFloat(strings.TrimSpace(fields[5]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind avg: %w", err)
	}

	windGustRaw, err := strconv.ParseFloat(strings.TrimSpace(fields[40]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind gust: %w", err)
	}

	windUnit := strings.TrimSpace(fields[13])

	var windSpeedKmh float64
	var windSpeedMs float64
	var windGustMs float64

	switch windUnit {
	case "m/s":
		windSpeedMs = windAvgRaw
		windSpeedKmh = windAvgRaw * 3.6
		windGustMs = windGustRaw
	case "km/h":
		windSpeedKmh = windAvgRaw
		windSpeedMs = windAvgRaw / 3.6
		windGustMs = windGustRaw / 3.6
	default:
		return nil, fmt.Errorf("unsupported wind unit: %s", windUnit)
	}

	windDirection, err := strconv.ParseFloat(strings.TrimSpace(fields[7]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse wind direction: %w", err)
	}

	rain, err := strconv.ParseFloat(strings.TrimSpace(fields[20]), 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse rain: %w", err)
	}

	response := WeatherStationResponse{
		TemperatureCelsius: temperature,
		HumidityPercent:    humidity,
		PressureHPa:        pressure,
		WindSpeedKmh:       windSpeedKmh,
		WindSpeedMs:        windSpeedMs,
		WindDirectionDeg:   windDirection,
		WindGustMs:         windGustMs,
		RainCumulativeMM:   rain,
	}

	return response, nil
}

func (v *MeteobridgeWeather) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(rawData)
}
