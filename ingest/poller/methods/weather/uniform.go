package weather

import (
	"fmt"
	"math"
	"time"

	"voria2ingest/types"
)

type WeatherStationResponse struct {
	TemperatureCelsius float64 `json:"temperature_celsius"`
	HumidityPercent    float64 `json:"humidity_percent"`
	PressureHPa        float64 `json:"pressure_hpa"`
	WindSpeedKmh       float64 `json:"wind_speed_kmh"`
	WindDirectionDeg   float64 `json:"wind_direction_deg"`
	WindSpeedMs        float64 `json:"wind_speed_ms"`
	WindGustMs         float64 `json:"wind_gust_ms"`
	RainCumulativeMM   float64 `json:"rain_cumulative_mm"`
}

func windToUV(speedMs, directionDeg float64) (u, v float64) {
	rad := directionDeg * math.Pi / 180
	u = speedMs * math.Sin(rad)
	v = speedMs * math.Cos(rad)
	return
}

func TransformToUniform(vendorData interface{}) (*types.WeatherStationData, error) {
	data, ok := vendorData.(WeatherStationResponse)
	if !ok {
		return nil, fmt.Errorf("invalid vendor data type")
	}

	windSpeedMs := data.WindSpeedMs
	if windSpeedMs == 0 {
		windSpeedMs = data.WindSpeedKmh / 3.6
	}

	windGustMs := data.WindGustMs
	if windGustMs == 0 {
		windGustMs = windSpeedMs
	}

	u, v := windToUV(windSpeedMs, data.WindDirectionDeg)

	ts := time.Now().UTC().Format(time.RFC3339)
	rainMM := data.RainCumulativeMM

	measurements := []types.WeatherMeasurement{
		{
			Sensor:    "temperature",
			Value:     data.TemperatureCelsius,
			Timestamp: ts,
		},
		{
			Sensor:    "humidity",
			Value:     data.HumidityPercent,
			Timestamp: ts,
		},
		{
			Sensor:    "pressure",
			Value:     data.PressureHPa,
			Timestamp: ts,
		},
		{
			Sensor:    "wind",
			U:         u,
			V:         v,
			Gust:      windGustMs,
			Timestamp: ts,
		},
		{
			Sensor:       "rain",
			CumulativeMM: rainMM,
			Timestamp:    ts,
		},
	}

	return &types.WeatherStationData{
		Measurements: measurements,
		Timestamp:    time.Now(),
	}, nil
}
