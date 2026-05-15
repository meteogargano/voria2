package weather

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"voria2ingest/config"
	"voria2ingest/poller/methods"
)

type Weatherlinklive struct {
	methods.BaseHTTPPoller
	StationID             string
	APIKey                string
	APISecret             string
	BaroCalibrationOffset float64
}

func (v *Weatherlinklive) Name() string {
	return "weatherlinklive"
}

func (v *Weatherlinklive) ValidateSettings(settings map[string]interface{}) error {
	return config.ValidateMethodSettings("weatherlinklive", settings)
}

func (v *Weatherlinklive) InitFromSettings(settings map[string]interface{}) error {
	stationID, ok := settings["stationId"]
	if !ok {
		return fmt.Errorf("stationId is required")
	}
	v.StationID = stationID.(string)

	apiKey, ok := settings["apiKey"]
	if !ok {
		return fmt.Errorf("apiKey is required")
	}
	v.APIKey = apiKey.(string)

	apiSecret, ok := settings["apiSecret"]
	if !ok {
		return fmt.Errorf("apiSecret is required")
	}
	v.APISecret = apiSecret.(string)

	baroOffset, ok := settings["baroCalibrationOffset"]
	if !ok {
		return fmt.Errorf("baroCalibrationOffset is required")
	}
	v.BaroCalibrationOffset = baroOffset.(float64)

	return nil
}

func (v *Weatherlinklive) Poll(ctx context.Context) (interface{}, error) {
	v.Init(30 * time.Second)

	url := fmt.Sprintf("https://api.weatherlink.com/v2/current/%s?api-key=%s", v.StationID, v.APIKey)

	headers := map[string]string{
		"X-Api-Secret": v.APISecret,
	}

	data, err := v.DoRequest(ctx, url, headers)
	if err != nil {
		return nil, err
	}

	var jsonData interface{}
	if err := json.Unmarshal(data, &jsonData); err != nil {
		return nil, fmt.Errorf("failed to parse JSON response: %w", err)
	}

	tempF, err := findValueRecursive(jsonData, []string{"temp", "temp_out"})
	if err != nil {
		return nil, fmt.Errorf("failed to find temperature: %w", err)
	}
	temperature := (tempF - 32) * 5 / 9

	humidity, err := findValueRecursive(jsonData, []string{"hum", "hum_out"})
	if err != nil {
		return nil, fmt.Errorf("failed to find humidity: %w", err)
	}

	barInHg, err := findValueRecursive(jsonData, []string{"bar", "bar_absolute"})
	if err != nil {
		return nil, fmt.Errorf("failed to find pressure: %w", err)
	}
	pressure := (barInHg + v.BaroCalibrationOffset) * 33.8639

	windSpeedMph, err := findValueRecursive(jsonData, []string{"wind_speed", "wind_speed_last"})
	if err != nil {
		return nil, fmt.Errorf("failed to find wind speed: %w", err)
	}
	windSpeedMs := windSpeedMph * 0.44704

	windGustMph, err := findValueRecursive(jsonData, []string{"wind_speed_hi_last_2_min", "wind_gust_10_min"})
	if err != nil {
		return nil, fmt.Errorf("failed to find wind gust: %w", err)
	}
	windGustMs := windGustMph * 0.44704

	windDirection, err := findValueRecursive(jsonData, []string{"wind_dir", "wind_dir_last"})
	if err != nil {
		return nil, fmt.Errorf("failed to find wind direction: %w", err)
	}

	rain, err := findValueRecursive(jsonData, []string{"rain_year_mm", "rainfall_year_mm"})
	if err != nil {
		return nil, fmt.Errorf("failed to find rain: %w", err)
	}

	response := WeatherStationResponse{
		TemperatureCelsius: temperature,
		HumidityPercent:    humidity,
		PressureHPa:        pressure,
		WindSpeedMs:        windSpeedMs,
		WindDirectionDeg:   windDirection,
		WindGustMs:         windGustMs,
		RainCumulativeMM:   rain,
	}

	return response, nil
}

func (v *Weatherlinklive) Transform(rawData interface{}) (interface{}, error) {
	return TransformToUniform(rawData)
}

func findValueRecursive(data interface{}, keys []string) (float64, error) {
	if data == nil {
		return 0, fmt.Errorf("value not found")
	}

	switch v := data.(type) {
	case map[string]interface{}:
		for key, val := range v {
			if contains(keys, key) {
				if num, ok := val.(float64); ok {
					return num, nil
				}
				if num, ok := val.(int); ok {
					return float64(num), nil
				}
				if num, ok := val.(int64); ok {
					return float64(num), nil
				}
				return 0, fmt.Errorf("value for key %s is not a number", key)
			}
			result, err := findValueRecursive(val, keys)
			if err == nil {
				return result, nil
			}
		}
	case []interface{}:
		for _, item := range v {
			result, err := findValueRecursive(item, keys)
			if err == nil {
				return result, nil
			}
		}
	}

	return 0, fmt.Errorf("value not found")
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}
