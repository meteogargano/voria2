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

// WLRealtimeWeather polls a Davis WeatherLink "realtime" text file: a single
// pipe-delimited line. It normalizes the data into the shared WeatherStationResponse
// model, converting units only where the source unit requires it.
type WLRealtimeWeather struct {
	methods.BaseHTTPPoller
	URL string
}

func (w *WLRealtimeWeather) Name() string { return "wlrealtime" }

func (w *WLRealtimeWeather) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings("wlrealtime", settings)
}

func (w *WLRealtimeWeather) InitFromSettings(settings map[string]interface{}) error {
	url, ok := settings["url"]
	if !ok {
		return fmt.Errorf("url is required in methodSettings")
	}
	w.URL = url.(string)
	return nil
}

func (w *WLRealtimeWeather) Poll(ctx context.Context) (interface{}, error) {
	w.Init(30 * time.Second)

	data, err := w.DoRequest(ctx, w.URL, nil)
	if err != nil {
		return nil, err
	}
	return parseWLRealtime(data)
}

func (w *WLRealtimeWeather) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(rawData)
}

// parseWLRealtime parses the WeatherLink realtime pipe-delimited format.
// Conversions applied only where needed: temperature F->C, wind km/hr or m/s
// into the dual kmh/ms representation. Pressure (hPa) and rain (mm) are used as-is.
func parseWLRealtime(data []byte) (WeatherStationResponse, error) {
	fields := strings.Split(string(data), "|")
	if len(fields) <= 40 {
		return WeatherStationResponse{}, fmt.Errorf("invalid response format: expected at least 41 fields, got %d", len(fields))
	}

	temperatureRaw, err := strconv.ParseFloat(strings.TrimSpace(fields[2]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse temperature: %w", err)
	}
	humidity, err := strconv.ParseFloat(strings.TrimSpace(fields[3]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse humidity: %w", err)
	}
	pressure, err := strconv.ParseFloat(strings.TrimSpace(fields[10]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse pressure: %w", err)
	}
	windAvgRaw, err := strconv.ParseFloat(strings.TrimSpace(fields[5]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse wind avg: %w", err)
	}
	windGustRaw, err := strconv.ParseFloat(strings.TrimSpace(fields[40]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse wind gust: %w", err)
	}
	windDirection, err := strconv.ParseFloat(strings.TrimSpace(fields[7]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse wind direction: %w", err)
	}
	rain, err := strconv.ParseFloat(strings.TrimSpace(fields[20]), 64)
	if err != nil {
		return WeatherStationResponse{}, fmt.Errorf("failed to parse rain: %w", err)
	}

	// source units (offset 13 wind, 14 temp, 15 pressure hPa, 16 rain mm)
	tempUnit := strings.ToUpper(strings.TrimSpace(fields[14]))
	windUnit := strings.TrimSpace(fields[13])

	// temperature: convert only when Fahrenheit; otherwise treat as Celsius
	var temperature float64
	if strings.Contains(tempUnit, "F") {
		temperature = (temperatureRaw - 32) * 5 / 9
	} else {
		temperature = temperatureRaw
	}

	// wind: m/s or km/hr (km/h alias accepted)
	var windSpeedKmh, windSpeedMs, windGustMs float64
	switch windUnit {
	case "m/s":
		windSpeedMs = windAvgRaw
		windSpeedKmh = windAvgRaw * 3.6
		windGustMs = windGustRaw
	case "km/hr", "km/h":
		windSpeedKmh = windAvgRaw
		windSpeedMs = windAvgRaw / 3.6
		windGustMs = windGustRaw / 3.6
	default:
		return WeatherStationResponse{}, fmt.Errorf("unsupported wind unit: %q", windUnit)
	}

	return WeatherStationResponse{
		TemperatureCelsius: temperature,
		HumidityPercent:    humidity,
		PressureHPa:        pressure,
		WindSpeedKmh:       windSpeedKmh,
		WindSpeedMs:        windSpeedMs,
		WindDirectionDeg:   windDirection,
		WindGustMs:         windGustMs,
		RainCumulativeMM:   rain,
	}, nil
}
