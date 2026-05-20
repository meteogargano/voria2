package config

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

type MethodValidator interface {
	ValidateSettings(settings map[string]interface{}) error
}

func ValidateMethodSettings(method string, settings map[string]interface{}) error {
	switch method {
	case "anemos":
		return validateAnemosSettings(settings)
	case "clientraw":
		return validateClientrawSettings(settings)
	case "meteobridge":
		return validateMeteobridgeSettings(settings)
	case "weatherlinklive":
		return validateWeatherlinkliveSettings(settings)
	case "imou":
		return validateImouSettings(settings)
	case "simple-http":
		return validateSimpleHTTPSettings(settings)
	case "ftp":
		return validateFTPWebcamSettings(settings)
	default:
		return fmt.Errorf("unknown method: %s", method)
	}
}

func validateAnemosSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateClientrawSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateMeteobridgeSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateSimpleHTTPSettings(settings map[string]interface{}) error {
	if _, ok := settings["url"]; !ok {
		return fmt.Errorf("url is required")
	}
	return nil
}

func validateImouSettings(settings map[string]interface{}) error {
	if value := strings.TrimSpace(settingString(settings, "app_id")); value == "" {
		return fmt.Errorf("app_id is required")
	}
	if value := strings.TrimSpace(settingString(settings, "app_secret")); value == "" {
		return fmt.Errorf("app_secret is required")
	}

	device, ok := settings["device"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("device is required")
	}
	if value := strings.TrimSpace(settingString(device, "device_id")); value == "" {
		return fmt.Errorf("device.device_id is required")
	}
	if value := strings.TrimSpace(settingString(device, "channel_id")); value == "" {
		return fmt.Errorf("device.channel_id is required")
	}
	profile := strings.ToUpper(strings.TrimSpace(settingString(device, "profile")))
	if profile == "" {
		return fmt.Errorf("device.profile is required")
	}
	if profile != "HD" && profile != "SD" {
		return fmt.Errorf("device.profile must be HD or SD")
	}

	capture, ok := settings["capture"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("capture is required")
	}
	cropBottom, err := settingInt(capture, "crop_bottom")
	if err != nil {
		return fmt.Errorf("capture.crop_bottom must be a whole number")
	}
	minImageKB, err := settingInt(capture, "min_image_kb")
	if err != nil {
		return fmt.Errorf("capture.min_image_kb must be a whole number")
	}
	if minImageKB < 0 {
		return fmt.Errorf("capture.min_image_kb must be greater than or equal to 0")
	}
	if cropBottom < 0 {
		return fmt.Errorf("capture.crop_bottom must be greater than or equal to 0")
	}

	return nil
}

func validateWeatherlinkliveSettings(settings map[string]interface{}) error {
	if _, ok := settings["stationId"]; !ok {
		return fmt.Errorf("stationId is required")
	}
	if _, ok := settings["apiKey"]; !ok {
		return fmt.Errorf("apiKey is required")
	}
	if _, ok := settings["apiSecret"]; !ok {
		return fmt.Errorf("apiSecret is required")
	}
	if _, ok := settings["baroCalibrationOffset"]; !ok {
		return fmt.Errorf("baroCalibrationOffset is required")
	}
	return nil
}

func validateFTPWebcamSettings(settings map[string]interface{}) error {
	if _, ok := settings["username"]; !ok {
		return fmt.Errorf("username is required")
	}
	if _, ok := settings["password"]; !ok {
		return fmt.Errorf("password is required")
	}
	return nil
}

func settingString(settings map[string]interface{}, key string) string {
	value, ok := settings[key]
	if !ok || value == nil {
		return ""
	}

	switch typed := value.(type) {
	case string:
		return typed
	default:
		return fmt.Sprint(typed)
	}
}

func settingInt(settings map[string]interface{}, key string) (int, error) {
	value, ok := settings[key]
	if !ok || value == nil {
		return 0, fmt.Errorf("missing value")
	}

	switch typed := value.(type) {
	case int:
		return typed, nil
	case int64:
		return int(typed), nil
	case float64:
		if math.Trunc(typed) != typed {
			return 0, fmt.Errorf("not an integer")
		}
		return int(typed), nil
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(typed))
		if err != nil {
			return 0, err
		}
		return parsed, nil
	default:
		return 0, fmt.Errorf("unsupported type %T", value)
	}
}
